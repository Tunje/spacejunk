class_name Propellant
extends RefCounted
## Two-propellant burns (task A61, production_chains.md, the Lead's off-ratio ruling). A thruster's
## `mixture` gives parts by mass of each propellant item, as { "hydrogen": 1, "oxygen": 6 }. Every
## gram a burn, a trip or a landing spends is split across those items in that ratio, and it runs
## short when any one item can't cover its share. So the usable propellant is what the scarcest
## item allows; any excess of the others stays unusable until it is rebalanced. A thruster with no
## mixture burns the single `propellant` item, as before A61.

const LEGACY := { "propellant": 1 }


## The mixture a unit burns with: its burn thruster's (BurnSystem.thruster), or the single item.
static func mixture_of(ctx: SimContext, unit_id: int) -> Dictionary:
	var found := BurnSystem.thruster(ctx, unit_id)
	if found.is_empty():
		return LEGACY
	return mixture_of_part(ctx, found["part"])


static func mixture_of_part(ctx: SimContext, part_id: int) -> Dictionary:
	var stats: Dictionary = Units.module_of(ctx.state, ctx.defs, part_id)["capabilities"].get(BurnSystem.CAPABILITY, {})
	var mixture: Dictionary = stats.get("mixture", {})
	return LEGACY if mixture.is_empty() else mixture


static func items_of(mixture: Dictionary) -> Array:
	var items: Array = mixture.keys()
	items.sort()
	return items


static func total_parts(mixture: Dictionary) -> int:
	var total := 0
	for item: String in items_of(mixture):
		total += int(mixture[item])
	return maxi(1, total)


## The grams of each item in total_g, in ratio. Items go in ID order, and the last takes what the
## rounding leaves, so the parts always sum to total_g.
static func split(total_g: int, mixture: Dictionary) -> Dictionary:
	var items := items_of(mixture)
	var parts := total_parts(mixture)
	var result := {}
	var left := total_g
	for i in items.size():
		var item: String = items[i]
		var grams := left if i == items.size() - 1 else IntMath.mul_div(total_g, int(mixture[item]), parts)
		result[item] = grams
		left -= grams
	return result


## True if the unit's free stock of every item covers its share of total_g.
static func fits(ctx: SimContext, unit_id: int, mixture: Dictionary, total_g: int) -> bool:
	var shares := split(total_g, mixture)
	for item: String in items_of(mixture):
		if int(shares[item]) > Reservations.free_stock(ctx, unit_id, item):
			return false
	return true


## The most propellant the unit can spend in ratio: what its scarcest item allows.
static func usable_g(ctx: SimContext, unit_id: int, mixture: Dictionary) -> int:
	var parts := total_parts(mixture)
	var best := -1
	for item: String in items_of(mixture):
		var allows := IntMath.mul_div(Reservations.free_stock(ctx, unit_id, item), parts, int(mixture[item]))
		best = allows if best < 0 else mini(best, allows)
	var usable := maxi(0, best)
	# Rounding in split can ask an item for a gram more than mul_div allowed; step down until it fits.
	while usable > 0 and not fits(ctx, unit_id, mixture, usable):
		usable -= 1
	return usable


## Claims total_g in ratio for this tick and gives the split, for the delta.
static func claim(ctx: SimContext, unit_id: int, mixture: Dictionary, total_g: int) -> Dictionary:
	var shares := split(total_g, mixture)
	for item: String in items_of(mixture):
		if int(shares[item]) > 0:
			Reservations.claim_stock(ctx, unit_id, item, shares[item])
	return shares


## Phase 6: takes a claimed split out of the inventory into the exhaust sink. An old delta with only
## `grams` is the single item.
static func spend(ctx: SimContext, payload: Dictionary) -> void:
	var shares: Dictionary = payload.get("items", { Travel.PROPELLANT: payload["grams"] })
	var inventory: Dictionary = ctx.state["units"][payload["unit"]]["inventory"]
	var sink: Dictionary = ctx.state["sinks"].get_or_add(Travel.SINK, {})
	for item: String in items_of(shares):
		var grams: int = shares[item]
		if grams <= 0:
			continue
		Units.remove_stock(inventory, item, grams)
		sink[item] = sink.get(item, 0) + grams
