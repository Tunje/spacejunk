class_name HeatSystem
extends SimSystem
## The heat loop of networks.md section 4. One loop per unit. Waste heat comes from the parts
## PowerSystem ran this tick, so this system must be registered after it.

const HEAT_CLEAR_PPM := 800000
const PPM := 1000000
const REASON_OVER_LIMIT := "over_heat_limit"
const FLOW_KEY := "heat"


func update_stores(ctx: SimContext) -> void:
	var flows := {}
	ctx.flows[FLOW_KEY] = flows
	var power: Dictionary = ctx.flows[PowerSystem.FLOW_KEY]
	for id: int in _sorted(ctx.state["units"]):
		flows[id] = _settle_loop(ctx, id, power[id]["ran"])


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
func _settle_loop(ctx: SimContext, id: int, ran: Array) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][id]
	var index := UnitIndex.of(ctx, id)
	var heat_w: Dictionary = index["heat_w"]
	var input_w := 0
	for part_id: int in ran:
		input_w += heat_w[part_id]
	var reject_w := UnitIndex.healthy_total(ctx, index["radiators"])
	var before_j: int = unit["heat_stored_j"]
	var in_rem: int = unit["heat_in_remainder"]
	var out_rem: int = unit["heat_out_remainder"]
	var added_j := Rate.amount(input_w, in_rem)
	var rejected_j := mini(before_j + added_j, Rate.amount(reject_w, out_rem))
	unit["heat_in_remainder"] = Rate.carry(input_w, in_rem)
	unit["heat_out_remainder"] = Rate.carry(reject_w, out_rem)
	unit["heat_stored_j"] = before_j + added_j - rejected_j
	unit["heat_input_w"] = input_w
	return {
		"before_j": before_j, "added_j": added_j, "rejected_j": rejected_j,
		"after_j": unit["heat_stored_j"], "input_w": input_w, "reject_w": reject_w,
	}


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
	for part_id: int in producers:
		if input_w <= flow["reject_w"]:
			return
		var heat_w: int = UnitIndex.of(ctx, id)["heat_w"][part_id]
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
