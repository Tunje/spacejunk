class_name PowerSystem
extends SimSystem
## The power network of networks.md sections 2 and 3. One network per unit. Phase 3 works out
## what is available, phase 4 chooses which loads run, and phase 6 settles the batteries.
##
## Register this after any system that starts jobs in phase 4, so a new run is seen as a load.
## From phase 5 on, a system tests a part with Units.can_run before doing work with it.

const SET_PRIORITY := "set_priority"
const SHED_HOLD_SECONDS := 5
## The work_per_tick of a full-size facility, at which a recipe draws its stated power.
const FULL_RATE_WORK_PER_TICK := 100
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
	var casters := RailSystem.shadow_casters(ctx.state)
	for id: int in _sorted(ctx.state["units"]):
		flows[id] = _available(ctx, id, casters)


func allocate(ctx: SimContext) -> void:
	var flows: Dictionary = ctx.flows[FLOW_KEY]
	var jobs := _jobs_by_unit(ctx)
	for id: int in _sorted(ctx.state["units"]):
		var flow: Dictionary = flows[id]
		var loads := _loads(ctx, id, jobs.get(id, []))
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


## Coast (A33). The last stepped tick's flows repeat exactly while every input to them holds:
## - no generator crosses a shadow's edge (a bound by CoastBounds);
## - no shed load's hold runs out;
## - every battery stays in the same regime: one drawing at its full rate keeps enough stored, and
##   one charging keeps room for what it took. A battery limited by what it holds or lacks is stepped.
## Loads change only by ops, jobs and faults, which other systems' horizons step.
func horizon(ctx: SimContext) -> int:
	var flows: Dictionary = ctx.flows.get(FLOW_KEY, {})
	var units: Dictionary = ctx.state["units"]
	if flows.size() != units.size():
		ctx.coast_cap = "power"
		return 0
	var now: int = ctx.state["tick"]
	var skip := NO_LIMIT
	var parts: Dictionary = ctx.state["parts"]
	var casters := _coast_casters(ctx.state)
	# Speeds between bodies are worked out once per pass, not once per unit (A38).
	var chains := {}
	# Units sitting still in a frame wait, by frame, until the rest are bounded (A38).
	var waiting := {}
	for id: int in _sorted(units):
		var index := UnitIndex.of(ctx, id)
		var shed := false
		for part_id: int in index["ids"]:
			var part: Dictionary = parts[part_id]
			shed = shed or part["shed"]
			var until: int = part["shed_until_tick"]
			if until > now:
				skip = mini(skip, until - now - 1)
		if not index["generators"].is_empty() and not casters.is_empty():
			var place := _still_place(units, id)
			if place != 0:
				waiting.get_or_add(place, []).append(id)
			else:
				skip = mini(skip, _shadow_horizon(ctx, id, casters, chains))
		var batteries: Dictionary = flows[id]["batteries"]
		for part_id: int in _sorted(batteries):
			skip = mini(skip, _battery_horizon(ctx, part_id, batteries[part_id], shed))
		if skip <= 0:
			break
	# One bound from each frame's centre, less its farthest still unit's distance from it, is below
	# every one of theirs. When it is no lower than the horizon already found, theirs can't lower
	# it, so they are skipped; otherwise each is bounded on its own. The horizon is the same either way.
	for frame_id: int in _sorted(waiting):
		if skip <= 0:
			break
		if _frame_shadow_bound(ctx, frame_id, waiting[frame_id], casters, chains) >= skip:
			continue
		for id: int in waiting[frame_id]:
			skip = mini(skip, _shadow_horizon(ctx, id, casters, chains))
	if skip <= 0:
		ctx.coast_cap = "power"
	return maxi(skip, 0)


## Coast (A33): each battery takes in and gives out what it did last tick, every tick, which sums in
## closed form with its remainders. The loads' draws and shed flags are already as they would be.
func coast(ctx: SimContext, ticks: int) -> void:
	var flows: Dictionary = ctx.flows[FLOW_KEY]
	for id: int in _sorted(ctx.state["units"]):
		var batteries: Dictionary = flows[id]["batteries"]
		for part_id: int in _sorted(batteries):
			var part: Dictionary = ctx.state["parts"][part_id]
			var battery: Dictionary = batteries[part_id]
			var charged: int = battery["stored_w"] * ticks + part["charge_remainder"]
			part["stored_j"] += charged / Sim.TICKS_PER_SECOND
			part["charge_remainder"] = charged % Sim.TICKS_PER_SECOND
			var drawn: int = battery["discharged_w"] * ticks + part["discharge_remainder"]
			part["stored_j"] -= drawn / Sim.TICKS_PER_SECOND
			part["discharge_remainder"] = drawn % Sim.TICKS_PER_SECOND


## Each shadow caster as RailSystem.shadow_casters gives it, with what a coast horizon needs worked
## out once per call rather than once per unit: [world_mm, direction, radius_mm, body ID, distance
## from the star, the body's speed bound].
static func _coast_casters(state: Dictionary) -> Array:
	var result := []
	var casters := RailSystem.shadow_casters(state)
	if casters.is_empty():
		return result
	var star_mm := _star_mm(state)
	var ids: Array = []
	for id: int in _sorted_static(state["bodies"]):
		var body: Dictionary = state["bodies"][id]
		if body["kind"] != RailSystem.STAR_KIND and body["gm"] > 0 and not body["orbit"].is_empty():
			ids.append(id)
	# shadow_casters lists the same bodies in the same ascending order.
	for n in casters.size():
		var caster: Array = casters[n]
		var body_mm: Array = caster[0]
		var from_star := IntMath.dist([int(body_mm[0]) - star_mm[0], int(body_mm[1]) - star_mm[1],
			int(body_mm[2]) - star_mm[2]], [0, 0, 0])
		result.append([body_mm, caster[1], caster[2], ids[n], maxi(1, from_star),
			CoastBounds.body_speed_um_s(state, ids[n])])
	return result


## The ticks before a unit's generators could pass into or out of any caster's shadow.
static func _shadow_horizon(ctx: SimContext, unit_id: int, casters: Array, chains: Dictionary = {}) -> int:
	return _shadow_horizon_at(ctx.state, RailSystem.world_mm(ctx.state, "units", unit_id),
		CoastBounds.unit_base(ctx.state, unit_id), 0, casters, chains)


## The ticks before anything within `slack_mm` of a point, moving at most as `base` allows, could
## pass into or out of any caster's shadow. The gap to a shadow's edge changes by no more than the
## distance moved, so a frame's still units can share one bound from its centre, with the farthest
## of them as the slack (A38).
static func _shadow_horizon_at(state: Dictionary, point_mm: Array, base: Array, slack_mm: int, casters: Array,
		chains: Dictionary) -> int:
	var skip := NO_LIMIT
	for caster: Array in casters:
		var body_mm: Array = caster[0]
		var direction: Array = caster[1]
		var radius: int = caster[2]
		var offset: Array[int] = []
		for axis in 3:
			offset.append(int(point_mm[axis]) - int(body_mm[axis]))
		var along := OrbitMath.dot(offset, direction)
		var across: Array[int] = []
		for axis in 3:
			across.append(offset[axis] - OrbitMath.smul_div(direction[axis], along, OrbitMath.ONE))
		var side := IntMath.dist(across, [0, 0, 0])
		var gap := 0
		if along > 0 and side < radius:
			gap = mini(radius - side, along)
		elif along <= 0:
			gap = maxi(-along, side - radius)
		else:
			gap = side - radius
		# The unit closes on the shadow as fast as it closes on the caster, and the shadow also
		# swings round the star with the caster.
		var closing := CoastBounds.UNBOUNDED_UM_S
		if base[1] < CoastBounds.UNBOUNDED_UM_S:
			var key := Vector2i(base[0], caster[3])
			if not chains.has(key):
				chains[key] = CoastBounds.chain_um_s(state, base[0], caster[3])
			closing = mini(int(base[1]) + int(chains[key]), CoastBounds.UNBOUNDED_UM_S)
		var swing := IntMath.mul_div(IntMath.dist(offset, [0, 0, 0]) + slack_mm, caster[5], caster[4])
		skip = mini(skip, CoastBounds.ticks_to_close(gap - slack_mm, closing + swing))
	return skip


## A shadow bound below that of every unit in `ids`, all sitting still in the frame: the frame
## centre's, with the farthest of them from it as the slack, plus a metre for the millimetres each
## worked-out gap can be out by.
static func _frame_shadow_bound(ctx: SimContext, frame_id: int, ids: Array, casters: Array,
		chains: Dictionary) -> int:
	var units: Dictionary = ctx.state["units"]
	var far := CoastBounds.GAP_SLACK_MM
	var spread := 0
	for id: int in ids:
		spread = maxi(spread, IntMath.dist(units[_still_host(units, id)]["pos_mm"], [0, 0, 0]))
	far += spread
	var frame: Dictionary = ctx.state["frames"][frame_id]
	var parent: int = frame["orbit"]["parent"]
	var base := [parent, CoastBounds.orbit_max_um_s(ctx.state["bodies"][parent]["gm"], frame["orbit"])]
	return _shadow_horizon_at(ctx.state, RailSystem.world_mm(ctx.state, "frames", frame_id), base, far,
		casters, chains)


## The frame a unit sits still in, through its dock, or 0.
static func _still_place(units: Dictionary, id: int) -> int:
	var unit: Dictionary = units[_still_host(units, id)]
	if unit["frame"] == 0 or not unit["orbit"].is_empty() or not unit["route"].is_empty() \
			or unit.get("low_flight", 0) != 0 or not unit.get("landed", {}).is_empty() \
			or unit["vel_um_s"] != [0, 0, 0]:
		return 0
	return unit["frame"]


static func _still_host(units: Dictionary, id: int) -> int:
	var host := id
	while not units[host]["dock"].is_empty():
		host = units[host]["dock"]["target_unit"]
	return host


static func _star_mm(state: Dictionary) -> Array:
	for id: int in _sorted_static(state["bodies"]):
		if state["bodies"][id]["kind"] == RailSystem.STAR_KIND:
			return RailSystem.world_mm(state, "bodies", id)
	return [0, 0, 0]


## Coast windows are searched up to this many ticks, which keeps every closed-form sum in range.
const MAX_BATTERY_WINDOW := 1 << 40


## The ticks a battery keeps last tick's flows: a full-rate draw keeps its cap while the store lasts,
## and a charge keeps its room while it fills. A charging battery below its full draw raises the
## unit's budget each tick, which could bring back a shed load, so with any load shed it is stepped.
## Stored energy moves one way, so checking the last tick of a window is enough, and the window is
## found by doubling and halving.
func _battery_horizon(ctx: SimContext, part_id: int, battery: Dictionary, shed: bool) -> int:
	var part: Dictionary = ctx.state["parts"][part_id]
	var drawn: int = battery["discharged_w"]
	var charged: int = battery["charged_w"]
	var limits: Dictionary = Units.module_of(ctx.state, ctx.defs, part_id)["capabilities"]["battery"]
	var cap_now: int = part["stored_j"] * Sim.TICKS_PER_SECOND - part["discharge_remainder"]
	if drawn == 0 and charged == 0:
		return NO_LIMIT
	# A battery that one more tick of these flows leaves exactly as it is will be offered the same
	# flows again, for ever: full and taking a trickle its losses round to nothing, or empty and
	# giving one that rounds to nothing. That is most of the game in sunlight (C, C17).
	if _battery_holds_still(part, battery):
		return NO_LIMIT
	if drawn > 0 and cap_now < limits["max_discharge_w"]:
		return 0  # the store, not the rate, limits the draw
	var free_now: int = (limits["capacity_j"] - part["stored_j"]) * Sim.TICKS_PER_SECOND - part["charge_remainder"]
	if charged > 0 and free_now < limits["max_charge_w"]:
		return 0  # the room left, not the rate, limits the charge
	if charged > 0 and shed and cap_now < limits["max_discharge_w"]:
		return 0  # a rising budget could bring a shed load back
	return _battery_window(part, battery, limits)


## The largest k below MAX_BATTERY_WINDOW for which _battery_holds, which only stops holding once.
static func _battery_window(part: Dictionary, battery: Dictionary, limits: Dictionary) -> int:
	# A straight-line estimate lands within a few ticks of the answer, so the search gallops out from there
	# rather than doubling up from 1 (A38): the same answer in a handful of checks, not about 80.
	var guess := _battery_guess(part, battery, limits)
	var low := 0
	var high := MAX_BATTERY_WINDOW
	if guess > 0 and _battery_holds(part, battery, limits, guess):
		low = guess
		var step := 1
		while low + step < MAX_BATTERY_WINDOW and _battery_holds(part, battery, limits, low + step):
			low += step
			step *= 2
		high = mini(low + step, MAX_BATTERY_WINDOW)
	elif guess > 0:
		high = guess
		var step := 1
		while high - step > 0 and not _battery_holds(part, battery, limits, high - step):
			high -= step
			step *= 2
		low = maxi(0, high - step)
	else:
		high = 1
		while high < MAX_BATTERY_WINDOW and _battery_holds(part, battery, limits, high):
			low = high
			high *= 2
		high = mini(high, MAX_BATTERY_WINDOW)
	while high - low > 1:
		var mid := (low + high) / 2
		if _battery_holds(part, battery, limits, mid):
			low = mid
		else:
			high = mid
	return low


## Roughly how many ticks a battery's regime lasts, from its store moving in a straight line, for
## _battery_horizon to search out from. Only a starting point: the search finds the exact window.
static func _battery_guess(part: Dictionary, battery: Dictionary, limits: Dictionary) -> int:
	var net: int = int(battery["stored_w"]) - int(battery["discharged_w"])
	var stored: int = part["stored_j"]
	var guess := MAX_BATTERY_WINDOW - 1
	if battery["discharged_w"] > 0 and net < 0:
		guess = mini(guess, (stored * Sim.TICKS_PER_SECOND - int(limits["max_discharge_w"])) / -net)
	if battery["charged_w"] > 0 and net > 0:
		guess = mini(guess, ((int(limits["capacity_j"]) - stored) * Sim.TICKS_PER_SECOND
			- int(limits["max_charge_w"])) / net)
	return clampi(guess, 0, MAX_BATTERY_WINDOW - 1)


## Whether one tick of last tick's flows leaves the battery's store and both remainders unchanged.
static func _battery_holds_still(part: Dictionary, battery: Dictionary) -> bool:
	var charged: int = battery["stored_w"] + part["charge_remainder"]
	var drawn: int = battery["discharged_w"] + part["discharge_remainder"]
	if charged / Sim.TICKS_PER_SECOND != drawn / Sim.TICKS_PER_SECOND:
		return false
	if charged % Sim.TICKS_PER_SECOND != part["charge_remainder"]:
		return false
	return drawn % Sim.TICKS_PER_SECOND == part["discharge_remainder"]


## Whether the battery's limits still leave last tick's flows after `ticks` more ticks of them, so
## the tick after can repeat them too.
static func _battery_holds(part: Dictionary, battery: Dictionary, limits: Dictionary, ticks: int) -> bool:
	var charged: int = battery["stored_w"] * ticks + part["charge_remainder"]
	var drawn: int = battery["discharged_w"] * ticks + part["discharge_remainder"]
	var stored: int = part["stored_j"] + charged / Sim.TICKS_PER_SECOND - drawn / Sim.TICKS_PER_SECOND
	var cap: int = stored * Sim.TICKS_PER_SECOND - drawn % Sim.TICKS_PER_SECOND
	var free: int = (limits["capacity_j"] - stored) * Sim.TICKS_PER_SECOND - charged % Sim.TICKS_PER_SECOND
	if battery["discharged_w"] > 0 and cap < limits["max_discharge_w"]:
		return false
	return battery["charged_w"] == 0 or free >= limits["max_charge_w"]


static func _sorted_static(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids


## Phase 3: healthy supply and what each healthy battery can give this tick.
func _available(ctx: SimContext, unit: int, casters: Array) -> Dictionary:
	var index := UnitIndex.of(ctx, unit)
	# Generators are solar, so a unit in a planet's shadow has none (orbital_flight.md 11.3, A16).
	var supply_w := 0
	if not index["generators"].is_empty() and (casters.is_empty() or not RailSystem.in_shadow(ctx.state, unit, casters)):
		supply_w = UnitIndex.healthy_total(ctx, index["generators"])
	var budget_w := 0
	var batteries := {}
	for entry: Array in index["batteries"]:
		var part: Dictionary = ctx.state["parts"][entry[0]]
		if part["fault"] != "":
			continue
		var limits: Dictionary = entry[1]
		var cap_w := maxi(0, mini(limits["max_discharge_w"],
			part["stored_j"] * Sim.TICKS_PER_SECOND - part["discharge_remainder"]))
		batteries[entry[0]] = {
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
func _loads(ctx: SimContext, unit: int, jobs: Array) -> Array[Dictionary]:
	var wanted := _wanted_draws(ctx, unit, jobs)
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
func _wanted_draws(ctx: SimContext, unit_id: int, jobs: Array) -> Dictionary:
	var state := ctx.state
	var unit: Dictionary = state["units"][unit_id]
	var index := UnitIndex.of(ctx, unit_id)
	var powers: Dictionary = index["power_w"]
	var parts: Dictionary = state["parts"]
	var wanted := {}
	for part_id: int in index["always_on"]:
		wanted[part_id] = powers[part_id]
	var core: int = unit["core"]
	if core != 0:
		wanted[core] = powers[core]
	var op: Dictionary = unit["op"]
	if op["part"] != 0 and op["type"] != OP_IDLE and op["type"] != OP_MOVING and powers.has(op["part"]):
		wanted[op["part"]] = powers[op["part"]]
	for job: Dictionary in jobs:
		wanted[job["facility"]] = job_draw_w(ctx, job)
	for part_id: int in wanted.keys():
		if parts[part_id]["fault"] != "":
			wanted.erase(part_id)
	return wanted


## A job's draw: its recipe's power at the full-size rate, scaled to its facility's rate and rounded
## up, so a run uses about the same energy on any size of facility (contracts section 5).
static func job_draw_w(ctx: SimContext, job: Dictionary) -> int:
	return IntMath.mul_div_ceil(ctx.defs["recipes"][job["recipe"]]["power_w"],
		JobSystem.work_per_tick(ctx, job["facility"]), FULL_RATE_WORK_PER_TICK)


## Load-making jobs by the unit their facility is on, in ascending job ID.
func _jobs_by_unit(ctx: SimContext) -> Dictionary:
	var result := {}
	var jobs: Dictionary = ctx.state["jobs"]
	var parts: Dictionary = ctx.state["parts"]
	for job_id: int in _sorted(jobs):
		var job: Dictionary = jobs[job_id]
		if parts.has(job["facility"]) and _job_is_load(job):
			result.get_or_add(parts[job["facility"]]["unit"], []).append(job)
	return result


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
	for part_id: int in UnitIndex.of(ctx, unit)["ids"]:
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
