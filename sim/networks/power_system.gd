class_name PowerSystem
extends SimSystem
## The power network of networks.md sections 2 and 3. One network per unit. Phase 3 works out
## what is available, phase 4 chooses which loads run, and phase 6 settles the batteries.
##
## Register this after any system that starts jobs in phase 4, so a new run is seen as a load.
## From phase 5 on, a system tests a part with Units.can_run before doing work with it.

const SET_PRIORITY := "set_priority"
const SHED_HOLD_SECONDS := 5
const PPM := 1000000
const REASON_NO_POWER := "no_power"
const REASON_MALFORMED := "malformed_command"
const REASON_UNKNOWN_PART := "unknown_part"
const OP_IDLE := "idle"
const OP_MOVING := "moving"
const JOB_RUNNING := "running"
const JOB_PAUSED := "paused"

## Per-tick figures by unit ID, shared with the heat loop through ctx.flows.
const FLOW_KEY := "power"


func commands() -> PackedStringArray:
	return PackedStringArray([SET_PRIORITY])


func validate(ctx: SimContext, command: Dictionary) -> Dictionary:
	var args: Dictionary = command["args"]
	if typeof(args.get("module")) != TYPE_INT or typeof(args.get("priority")) != TYPE_INT \
			or args["priority"] < 0:
		return SimSystem.reject(REASON_MALFORMED)
	var parts: Dictionary = ctx.state["parts"]
	if not parts.has(args["module"]) or parts[args["module"]]["unit"] != command["unit"]:
		return SimSystem.reject(REASON_UNKNOWN_PART)
	return SimSystem.ok()


func apply(ctx: SimContext, command: Dictionary) -> void:
	ctx.state["parts"][command["args"]["module"]]["priority"] = command["args"]["priority"]


func calculate_power(ctx: SimContext) -> void:
	var flows := {}
	ctx.flows[FLOW_KEY] = flows
	for id: int in _sorted(ctx.state["units"]):
		flows[id] = _available(ctx, id)


func allocate(ctx: SimContext) -> void:
	var flows: Dictionary = ctx.flows[FLOW_KEY]
	for id: int in _sorted(ctx.state["units"]):
		var flow: Dictionary = flows[id]
		var loads := _loads(ctx, id)
		_choose(ctx, id, loads, flow["budget_w"])
		_settle_flows(flow, loads)


func update_stores(ctx: SimContext) -> void:
	var flows: Dictionary = ctx.flows[FLOW_KEY]
	for id: int in _sorted(ctx.state["units"]):
		var batteries: Dictionary = flows[id]["batteries"]
		for part_id: int in _sorted(batteries):
			_settle_battery(ctx.state["parts"][part_id], batteries[part_id])


func fill_ledger(ctx: SimContext, ledger: Dictionary) -> void:
	ledger["energy"] = ctx.flows.get(FLOW_KEY, {}).duplicate(true)


## Phase 3: healthy supply and what each healthy battery can give this tick.
func _available(ctx: SimContext, unit: int) -> Dictionary:
	var supply_w := 0
	var budget_w := 0
	var batteries := {}
	for part_id in Units.sorted_part_ids(ctx.state, unit):
		var part: Dictionary = ctx.state["parts"][part_id]
		if part["fault"] != "":
			continue
		var capabilities: Dictionary = Units.module_of(ctx.state, ctx.defs, part_id)["capabilities"]
		supply_w += capabilities.get("generate", {}).get("power_w", 0)
		if capabilities.has("battery"):
			var limits: Dictionary = capabilities["battery"]
			var cap_w := maxi(0, mini(limits["max_discharge_w"],
				part["stored_j"] * Sim.TICKS_PER_SECOND - part["discharge_remainder"]))
			batteries[part_id] = {
				"discharge_cap_w": cap_w, "max_charge_w": limits["max_charge_w"],
				"free_w": maxi(0, (limits["capacity_j"] - part["stored_j"]) * Sim.TICKS_PER_SECOND
					- part["charge_remainder"]),
				"efficiency_ppm": limits["charge_efficiency_ppm"],
				"discharged_w": 0, "charged_w": 0, "stored_w": 0, "conversion_loss_w": 0,
			}
			budget_w += cap_w
	return {
		"generated_w": supply_w, "budget_w": budget_w + supply_w, "consumed_w": 0, "discharged_w": 0,
		"charged_w": 0, "curtailed_w": 0, "batteries": batteries, "ran": [],
	}


## Every load on a unit in keep order: priority descending, then part ID ascending.
func _loads(ctx: SimContext, unit: int) -> Array[Dictionary]:
	var wanted := _wanted_draws(ctx, unit)
	var result: Array[Dictionary] = []
	var parts: Dictionary = ctx.state["parts"]
	for part_id: int in _sorted(wanted):
		result.append({
			"part": part_id, "draw_w": wanted[part_id], "priority": parts[part_id]["priority"],
			"held": parts[part_id]["shed_until_tick"] > ctx.tick, "keep": false,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["priority"] != b["priority"]:
			return a["priority"] > b["priority"]
		return a["part"] < b["part"])
	return result


## Draw by part ID, for each part that wants power (networks.md section 2).
func _wanted_draws(ctx: SimContext, unit_id: int) -> Dictionary:
	var state := ctx.state
	var unit: Dictionary = state["units"][unit_id]
	var parts: Dictionary = state["parts"]
	var wanted := {}
	for part_id in Units.part_ids(state, unit_id):
		var module: Dictionary = Units.module_of(state, ctx.defs, part_id)
		if module["capabilities"].get("always_on", false) or part_id == unit["core"]:
			wanted[part_id] = module["power_w"]
	var op: Dictionary = unit["op"]
	if op["part"] != 0 and op["type"] != OP_IDLE and op["type"] != OP_MOVING and parts.has(op["part"]):
		wanted[op["part"]] = Units.module_of(state, ctx.defs, op["part"])["power_w"]
	var jobs: Dictionary = state["jobs"]
	for job_id: int in _sorted(jobs):
		var job: Dictionary = jobs[job_id]
		if parts.get(job["facility"], {}).get("unit", 0) == unit_id and _job_is_load(job):
			wanted[job["facility"]] = ctx.defs["recipes"][job["recipe"]]["power_w"]
	for part_id: int in wanted.keys():
		if parts[part_id]["fault"] != "":
			wanted.erase(part_id)
	return wanted


func _job_is_load(job: Dictionary) -> bool:
	return job["status"] == JOB_RUNNING \
		or (job["status"] == JOB_PAUSED and job["reason"] == REASON_NO_POWER)


## Phase 4 allocation, then the state and events of what changed.
func _choose(ctx: SimContext, unit: int, loads: Array[Dictionary], budget_w: int) -> void:
	var total_w := 0
	for entry: Dictionary in loads:
		entry["keep"] = not entry["held"]
		if entry["keep"]:
			total_w += entry["draw_w"]
	for i in range(loads.size() - 1, -1, -1):
		if total_w > budget_w and loads[i]["keep"] and loads[i]["draw_w"] > 0:
			loads[i]["keep"] = false
			total_w -= loads[i]["draw_w"]
	for entry: Dictionary in loads:
		if not entry["keep"] and not entry["held"] and total_w + entry["draw_w"] <= budget_w:
			entry["keep"] = true
			total_w += entry["draw_w"]
	_apply_choice(ctx, unit, loads)


func _apply_choice(ctx: SimContext, unit: int, loads: Array[Dictionary]) -> void:
	var parts: Dictionary = ctx.state["parts"]
	var demand_w := 0
	var is_load := {}
	for entry: Dictionary in loads:
		var part: Dictionary = parts[entry["part"]]
		is_load[entry["part"]] = true
		demand_w += entry["draw_w"]
		part["draw_w"] = entry["draw_w"] if entry["keep"] else 0
		if entry["keep"] and part["shed"]:
			part["shed"] = false
			ctx.emit_event("power_restored", unit, { "module": entry["part"] })
		elif not entry["keep"] and not part["shed"]:
			part["shed"] = true
			if not entry["held"]:
				part["shed_until_tick"] = ctx.tick + SHED_HOLD_SECONDS * Sim.TICKS_PER_SECOND
			ctx.emit_event("power_shed", unit, { "module": entry["part"], "reason": REASON_NO_POWER })
	ctx.state["units"][unit]["demand_w"] = demand_w
	for part_id in Units.part_ids(ctx.state, unit):
		if not is_load.has(part_id):
			parts[part_id]["shed"] = false
			parts[part_id]["draw_w"] = 0


## Splits the kept loads across supply and batteries, in ascending part ID.
func _settle_flows(flow: Dictionary, loads: Array[Dictionary]) -> void:
	var consumed_w := 0
	var ran: Array = []
	for entry: Dictionary in loads:
		if entry["keep"]:
			consumed_w += entry["draw_w"]
			ran.append(entry["part"])
	ran.sort()
	flow["ran"] = ran
	flow["consumed_w"] = consumed_w
	var generated_w: int = flow["generated_w"]
	var batteries: Dictionary = flow["batteries"]
	var owed_w := maxi(0, consumed_w - generated_w)
	var surplus_w := maxi(0, generated_w - consumed_w)
	flow["discharged_w"] = owed_w
	for part_id: int in _sorted(batteries):
		var battery: Dictionary = batteries[part_id]
		var drawn_w := mini(owed_w, battery["discharge_cap_w"])
		battery["discharged_w"] = drawn_w
		owed_w -= drawn_w
		var accepted_w := mini(surplus_w, mini(battery["max_charge_w"], battery["free_w"]))
		battery["charged_w"] = accepted_w
		surplus_w -= accepted_w
		flow["charged_w"] += accepted_w
	flow["curtailed_w"] = surplus_w


## Phase 6: the only place power rounds to joules, with one remainder per direction.
func _settle_battery(part: Dictionary, battery: Dictionary) -> void:
	var stored_w := IntMath.mul_div(battery["charged_w"], battery["efficiency_ppm"], PPM)
	battery["stored_w"] = stored_w
	battery["conversion_loss_w"] = battery["charged_w"] - stored_w
	var charge_rem: int = part["charge_remainder"]
	var discharge_rem: int = part["discharge_remainder"]
	part["stored_j"] += Rate.amount(stored_w, charge_rem)
	part["charge_remainder"] = Rate.carry(stored_w, charge_rem)
	part["stored_j"] -= Rate.amount(battery["discharged_w"], discharge_rem)
	part["discharge_remainder"] = Rate.carry(battery["discharged_w"], discharge_rem)


func _sorted(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids
