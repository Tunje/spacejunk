class_name Reservations
extends RefCounted
## The per-tick cargo table of networks.md section 5: destination space and source grams already
## promised this tick. It lives in ctx.flows, so it is rebuilt each tick and never saved.
## Anything that moves matter in phase 5, including mining, claims here in ascending unit ID.

const FLOW_KEY := "cargo"


## Grams of an item a unit holds that nothing has claimed yet.
static func free_stock(ctx: SimContext, unit: int, item: String) -> int:
	var claimed: Dictionary = _side(ctx, "out", unit)
	return ctx.state["units"][unit]["inventory"].get(item, 0) - claimed.get(item, 0)


## Grams of an item a unit can still take this tick.
static func free_space(ctx: SimContext, unit: int, item: String) -> int:
	return Units.grams_that_fit(ctx.state, ctx.defs, unit, item, _side(ctx, "in", unit))


static func claim_stock(ctx: SimContext, unit: int, item: String, grams: int) -> void:
	var claimed: Dictionary = _side(ctx, "out", unit)
	claimed[item] = claimed.get(item, 0) + grams


static func claim_space(ctx: SimContext, unit: int, item: String, grams: int) -> void:
	var claimed: Dictionary = _side(ctx, "in", unit)
	claimed[item] = claimed.get(item, 0) + grams


static func _side(ctx: SimContext, side: String, unit: int) -> Dictionary:
	var table: Dictionary = ctx.flows.get_or_add(FLOW_KEY, { "in": {}, "out": {} })
	return table[side].get_or_add(unit, {})
