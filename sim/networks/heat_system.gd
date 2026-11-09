class_name HeatSystem
extends SimSystem
## The heat loop of networks.md section 4. One loop per unit. Waste heat comes from the parts
## PowerSystem ran this tick, so this system must be registered after it. A facility's heat is its
## job's, at the rate it ran (C30); any other part's is its module's heat_w.
##
## Heat by temperature (A60, the Lead's rule): a load's heat goes only to radiators at or below its
## temperature, the module's heat_temp_k, and a radiator works at its radiator.temp_k, both 300 K
## when not given. Each tick the loads that ran are placed from coldest to hottest, each into the
## healthy radiators it may use, hottest of those first; since a hotter load may use every radiator
## a colder one may, that places as much as the rule allows. What finds no radiator is stranded and
## warms the store, which counts as 300 K, so only spare radiators at or below 300 K cool it. With
## every load and radiator at 300 K this is the loop as it was.

const HEAT_CLEAR_PPM := 800000
const PPM := 1000000
const REASON_OVER_LIMIT := "over_heat_limit"
const FLOW_KEY := "heat"
const COLD_K := 300


func update_stores(ctx: SimContext) -> void:
	var flows := {}
	ctx.flows[FLOW_KEY] = flows
	var power: Dictionary = ctx.flows[PowerSystem.FLOW_KEY]
	for id: int in _sorted(ctx.state["units"]):
		flows[id] = _settle_loop(ctx, id, power[id]["ran"], power[id]["job_heat_w"])


func detect(ctx: SimContext) -> void:
	var flows: Dictionary = ctx.flows[FLOW_KEY]
	for id: int in _sorted(ctx.state["units"]):
		var unit: Dictionary = ctx.state["units"][id]
		var limit_j: int = UnitIndex.of(ctx, id)["limit_j"]
		if unit["heat_stored_j"] > limit_j:
			_fault_parts(ctx, id, flows[id])
		elif unit["heat_stored_j"] <= IntMath.mul_div(limit_j, HEAT_CLEAR_PPM, PPM):
			_clear_faults(ctx, id)


## Coast windows are searched up to this many ticks, which keeps every closed-form sum in range.
const MAX_HEAT_WINDOW := 1 << 40


## Coast (A33). Each loop takes in and gives out at last tick's rates, which the power horizon keeps
## steady. A loop coasts while it stays clear of both the clamp at 0 and its fault limits:
## - cold and kept cold: nothing stored, and radiators that take off more than comes in each tick;
## - warm: enough stored that the radiators never empty it, and the store stays on the same side of
##   the limit and of the clear threshold for the whole window.
func horizon(ctx: SimContext) -> int:
	var flows: Dictionary = ctx.flows.get(FLOW_KEY, {})
	var units: Dictionary = ctx.state["units"]
	if flows.size() != units.size():
		ctx.coast_cap = "heat"
		return 0
	var skip := NO_LIMIT
	for id: int in _sorted(units):
		skip = mini(skip, _loop_horizon(ctx, id, flows[id]))
		if skip <= 0:
			ctx.coast_cap = "heat"
			return 0
	return skip


## Coast (A33): the store and both remainders after `ticks` ticks at last tick's rates. The horizon
## made sure no tick in them clamps, so each tick's rejection is its full amount.
func coast(ctx: SimContext, ticks: int) -> void:
	var flows: Dictionary = ctx.flows[FLOW_KEY]
	for id: int in _sorted(ctx.state["units"]):
		var unit: Dictionary = ctx.state["units"][id]
		var after := _after(unit, flows[id], ticks)
		unit["heat_stored_j"] = after[0]
		unit["heat_in_remainder"] = after[1]
		unit["heat_out_remainder"] = after[2]


## [stored, in remainder, out remainder] after `ticks` unclamped ticks, or a cold loop kept at 0.
static func _after(unit: Dictionary, flow: Dictionary, ticks: int) -> Array:
	var added: int = flow["input_w"] * ticks + unit["heat_in_remainder"]
	var taken: int = flow["reject_w"] * ticks + unit["heat_out_remainder"]
	var stored: int = unit["heat_stored_j"]
	if stored > 0:
		stored += added / Sim.TICKS_PER_SECOND - taken / Sim.TICKS_PER_SECOND
	return [stored, added % Sim.TICKS_PER_SECOND, taken % Sim.TICKS_PER_SECOND]


func _loop_horizon(ctx: SimContext, id: int, flow: Dictionary) -> int:
	var unit: Dictionary = ctx.state["units"][id]
	var input_w: int = flow["input_w"]
	var reject_w: int = flow["reject_w"]
	var stored: int = unit["heat_stored_j"]
	if stored == 0:
		# Kept at 0 if each tick takes off at least what comes in, whatever the remainders.
		return NO_LIMIT if input_w == 0 or reject_w >= input_w + Sim.TICKS_PER_SECOND else 0
	var limit_j: int = UnitIndex.of(ctx, id)["limit_j"]
	var clear_j := IntMath.mul_div(limit_j, HEAT_CLEAR_PPM, PPM)
	if not _loop_holds(unit, flow, 0, limit_j, clear_j):
		return 0
	var low := 0
	var high := 1
	while high < MAX_HEAT_WINDOW and _loop_holds(unit, flow, high, limit_j, clear_j):
		low = high
		high *= 2
	while high - low > 1:
		var mid := (low + high) / 2
		if _loop_holds(unit, flow, mid, limit_j, clear_j):
			low = mid
		else:
			high = mid
	return low


## Whether, after `ticks` ticks, the loop still has enough stored for a full rejection, and has not
## crossed its limit or its clear threshold. The store moves one way, so the end of a window decides.
static func _loop_holds(unit: Dictionary, flow: Dictionary, ticks: int, limit_j: int, clear_j: int) -> bool:
	var before: int = unit["heat_stored_j"]
	var stored: int = _after(unit, flow, ticks)[0]
	var most_taken: int = (flow["reject_w"] + Sim.TICKS_PER_SECOND - 1) / Sim.TICKS_PER_SECOND
	if stored < most_taken:
		return false
	if (before > limit_j) != (stored > limit_j):
		return false
	return (before <= clear_j) == (stored <= clear_j)


func fill_ledger(ctx: SimContext, ledger: Dictionary) -> void:
	ledger["heat"] = ctx.flows.get(FLOW_KEY, {}).duplicate(true)


## Phase 6: heat rises first, then radiators take off what they can. A clamped amount is dropped,
## so radiators build no credit while the loop is cold.
func _settle_loop(ctx: SimContext, id: int, ran: Array, job_heat_w: Dictionary) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][id]
	var index := UnitIndex.of(ctx, id)
	var heat_w: Dictionary = index["heat_w"]
	var input_w := 0
	var loads: Array = []
	for part_id: int in ran:
		var given: int = job_heat_w.get(part_id, heat_w[part_id])
		input_w += given
		if given > 0:
			loads.append([heat_temp_k(ctx, part_id), given, part_id])
	var spares := radiator_spares(ctx, id)
	var radiator_w := spare_total(spares)
	var placed_w := place_all(spares, loads)
	# The radiators that act on this loop: what took this tick's heat, and the spare cold enough
	# for the store.
	var reject_w := placed_w + spare_at(spares, COLD_K)
	var before_j: int = unit["heat_stored_j"]
	var in_rem: int = unit["heat_in_remainder"]
	var out_rem: int = unit["heat_out_remainder"]
	var added_j := Rate.amount(input_w, in_rem)
	var rejected_j := mini(before_j + added_j, Rate.amount(reject_w, out_rem))
	unit["heat_in_remainder"] = Rate.carry(input_w, in_rem)
	unit["heat_out_remainder"] = Rate.carry(reject_w, out_rem)
	unit["heat_stored_j"] = before_j + added_j - rejected_j
	unit["heat_input_w"] = input_w
	unit["heat_stranded_w"] = input_w - placed_w
	return {
		"before_j": before_j, "added_j": added_j, "rejected_j": rejected_j,
		"after_j": unit["heat_stored_j"], "input_w": input_w, "reject_w": reject_w,
		"stranded_w": input_w - placed_w, "radiator_w": radiator_w,
	}


# ------------------------------------------------------------------------------ temperatures (A60)

## The temperature a part's heat leaves at.
static func heat_temp_k(ctx: SimContext, part_id: int) -> int:
	return int(Units.module_of(ctx.state, ctx.defs, part_id).get("heat_temp_k", COLD_K))


## The unit's healthy radiators as [temp_k, spare_w, part], hottest first, then by part ID.
static func radiator_spares(ctx: SimContext, unit_id: int) -> Array:
	var parts: Dictionary = ctx.state["parts"]
	var spares: Array = []
	for pair: Array in UnitIndex.of(ctx, unit_id)["radiators"]:
		if parts[pair[0]]["fault"] != "":
			continue
		var radiator: Dictionary = Units.module_of(ctx.state, ctx.defs, pair[0])["capabilities"]["radiator"]
		spares.append([int(radiator.get("temp_k", COLD_K)), int(pair[1]), int(pair[0])])
	spares.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] if a[0] != b[0] else a[2] < b[2])
	return spares


static func spare_total(spares: Array) -> int:
	var total := 0
	for spare: Array in spares:
		total += int(spare[1])
	return total


## The spare a load at temp_k may use: radiators at or below it.
static func spare_at(spares: Array, temp_k: int) -> int:
	var total := 0
	for spare: Array in spares:
		if int(spare[0]) <= temp_k:
			total += int(spare[1])
	return total


## Places heat_w at temp_k on the radiators it may use, hottest first, and gives the watts placed.
static func place(spares: Array, temp_k: int, heat_w: int) -> int:
	var left := heat_w
	for spare: Array in spares:
		if left <= 0:
			break
		if int(spare[0]) > temp_k:
			continue
		var taken := mini(left, int(spare[1]))
		spare[1] = int(spare[1]) - taken
		left -= taken
	return heat_w - left


## Places loads, [temp_k, heat_w, part] each, coldest first and then by part ID, and gives the watts
## placed.
static func place_all(spares: Array, loads: Array) -> int:
	var ordered := loads.duplicate()
	ordered.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if a[0] != b[0] else a[2] < b[2])
	var placed := 0
	for load: Array in ordered:
		placed += place(spares, load[0], load[1])
	return placed


## Faults running heat producers, lowest priority and highest ID first, until the heat coming in
## is at or below what the radiators can reject.
func _fault_parts(ctx: SimContext, id: int, flow: Dictionary) -> void:
	var parts: Dictionary = ctx.state["parts"]
	var producers: Array = ctx.flows[PowerSystem.FLOW_KEY][id]["ran"].duplicate()
	producers.sort_custom(func(a: int, b: int) -> bool:
		if parts[a]["priority"] != parts[b]["priority"]:
			return parts[a]["priority"] < parts[b]["priority"]
		return a > b)
	var input_w: int = flow["input_w"]
	var job_heat_w: Dictionary = ctx.flows[PowerSystem.FLOW_KEY][id]["job_heat_w"]
	for part_id: int in producers:
		if input_w <= flow["reject_w"]:
			return
		var heat_w: int = job_heat_w.get(part_id, UnitIndex.of(ctx, id)["heat_w"][part_id])
		if heat_w > 0:
			parts[part_id]["fault"] = REASON_OVER_LIMIT
			input_w -= heat_w
			ctx.emit_event("fault", id, { "module": part_id, "reason": REASON_OVER_LIMIT })


func _clear_faults(ctx: SimContext, id: int) -> void:
	for part_id: int in UnitIndex.of(ctx, id)["ids"]:
		var part: Dictionary = ctx.state["parts"][part_id]
		if part["fault"] == REASON_OVER_LIMIT:
			part["fault"] = ""
			ctx.emit_event("fault_cleared", id, { "module": part_id })


func _sorted(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids
