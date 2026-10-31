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
		var limit_j := Units.capability_sum(ctx.state, ctx.defs, id, "heat_capacity", "limit_j")
		if unit["heat_stored_j"] > limit_j:
			_fault_parts(ctx, id, flows[id])
		elif unit["heat_stored_j"] <= IntMath.mul_div(limit_j, HEAT_CLEAR_PPM, PPM):
			_clear_faults(ctx, id)


func fill_ledger(ctx: SimContext, ledger: Dictionary) -> void:
	ledger["heat"] = ctx.flows.get(FLOW_KEY, {}).duplicate(true)


## Phase 6: heat rises first, then radiators take off what they can. A clamped amount is dropped,
## so radiators build no credit while the loop is cold.
func _settle_loop(ctx: SimContext, id: int, ran: Array) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][id]
	var input_w := 0
	for part_id: int in ran:
		input_w += Units.module_of(ctx.state, ctx.defs, part_id)["heat_w"]
	var reject_w := Units.healthy_sum(ctx.state, ctx.defs, id, "radiator", "reject_w")
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
		var heat_w: int = Units.module_of(ctx.state, ctx.defs, part_id)["heat_w"]
		if heat_w > 0:
			parts[part_id]["fault"] = REASON_OVER_LIMIT
			input_w -= heat_w
			ctx.emit_event("fault", id, { "module": part_id, "reason": REASON_OVER_LIMIT })


func _clear_faults(ctx: SimContext, id: int) -> void:
	for part_id in Units.sorted_part_ids(ctx.state, id):
		var part: Dictionary = ctx.state["parts"][part_id]
		if part["fault"] == REASON_OVER_LIMIT:
			part["fault"] = ""
			ctx.emit_event("fault_cleared", id, { "module": part_id })


func _sorted(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids
