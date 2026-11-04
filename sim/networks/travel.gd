class_name Travel
extends RefCounted
## Routes and trip prices (networks.md section 6). `check`, phase 1 and phase 4 all use quote, so
## the number shown is the number paid.

const STANDOFF_MM := 150000
const CAPABILITY := "thruster"
const PROPELLANT := "propellant"
const SINK := "propellant_exhaust"
## A move_to target outside the unit's frame, or on an orbit, needs the transfer planner of A13.
const REASON_OTHER_PLACE := "unsupported_orbit"
const KIND_ROUTE := "route"
const REASON_NO_WINDOW := "no_window"


## The fastest healthy thruster, lowest part ID on a tie, as { part, thruster } or { reason }.
static func thruster(ctx: SimContext, unit_id: int) -> Dictionary:
	var best := {}
	var reason := TaskSystem.REASON_MODULE_MISSING
	for part_id in Units.sorted_part_ids(ctx.state, unit_id):
		var stats: Dictionary = Units.module_of(ctx.state, ctx.defs, part_id)["capabilities"].get(CAPABILITY, {})
		if stats.is_empty():
			continue
		if ctx.state["parts"][part_id]["fault"] != "":
			reason = TaskSystem.REASON_MODULE_FAULT
		elif best.is_empty() or stats["speed_mm_s"] > best["thruster"]["speed_mm_s"]:
			best = { "part": part_id, "thruster": stats }
	return best if not best.is_empty() else { "reason": reason }


## Where a trip would end, what it takes and what it costs, or { reason }.
static func quote(ctx: SimContext, unit_id: int, target: int) -> Dictionary:
	return quote_trip(ctx, unit_id, target, ctx.tick)


## The trip from the unit to a target, leaving at the first chance at or after from_tick (A13).
## Inside one frame, or in the old world, it is today's route, with `kind` "route" and leaving at
## from_tick. Between places it is a transfer from Transfer.plan, leaving at its window. Both carry
## { kind, target, depart_tick, arrive_tick, ticks, cost_g }, or the trip gives { reason }.
static func quote_trip(ctx: SimContext, unit_id: int, target: int, from_tick: int) -> Dictionary:
	var place := RailSystem.unit_place(ctx.state, unit_id)
	if place != RailSystem.ON_ORBIT and place == RailSystem.target_place(ctx.state, target):
		var at := Units.at(ctx.state, unit_id, target)
		return _route(ctx, unit_id, ctx.state["units"][unit_id]["pos_mm"], target,
			Units.unit_mass(ctx.state, ctx.defs, unit_id), at, from_tick)
	return Transfer.plan(ctx, unit_id, target, from_tick)


## As quote_trip, if the trip costs no more than cap_g, otherwise { reason: no_window }.
static func next_window(ctx: SimContext, unit_id: int, target: int, from_tick: int, cap_g: int) -> Dictionary:
	var quoted := quote_trip(ctx, unit_id, target, from_tick)
	if not quoted.has("reason") and quoted["cost_g"] > cap_g:
		return { "reason": REASON_NO_WINDOW }
	return quoted


## A leg the unit has not reached yet, for pricing a whole lap ahead: from `from_place` (a body,
## unit or frame member whose place gives the start) to the target, at mass_g. Same dictionary as
## quote_trip, using the unit's own thrusters.
static func quote_leg(ctx: SimContext, unit_id: int, from_place: int, target: int, mass_g: int, from_tick: int) -> Dictionary:
	var start := RailSystem.target_place(ctx.state, from_place)
	if start != RailSystem.ON_ORBIT and start == RailSystem.target_place(ctx.state, target):
		return _route(ctx, unit_id, _position(ctx, from_place), target, mass_g, from_place == target, from_tick)
	var from_orbit := Transfer.target_orbit(ctx, from_place)
	return Transfer.plan_from(ctx, unit_id, from_orbit, target, mass_g, from_tick)


## Today's straight-line route and price (networks.md section 6), from a point at a mass.
static func _route(ctx: SimContext, unit_id: int, from_mm: Array, target: int, mass_g: int, at: bool,
		from_tick: int) -> Dictionary:
	var found := thruster(ctx, unit_id)
	if found.has("reason"):
		return found
	var stats: Dictionary = found["thruster"]
	var result := {
		"kind": KIND_ROUTE, "target": target, "from_mm": from_mm.duplicate(), "to_mm": from_mm.duplicate(),
		"length_mm": 0, "speed_mm_s": stats["speed_mm_s"], "ticks": 1, "cost_g": 0,
		"depart_tick": from_tick, "arrive_tick": from_tick,
	}
	var target_mm := _position(ctx, target)
	var total_mm := IntMath.dist(from_mm, target_mm)
	var stop_mm := _stop_distance(ctx, target)
	if at or total_mm <= stop_mm:
		return result
	result["to_mm"] = stop_point(from_mm, target_mm, total_mm, stop_mm)
	result["length_mm"] = IntMath.dist(from_mm, result["to_mm"])
	result["ticks"] = IntMath.mul_div_ceil(result["length_mm"], Sim.TICKS_PER_SECOND, stats["speed_mm_s"])
	var base_g := IntMath.mul_div_ceil(result["ticks"], stats["propellant_g_per_s"], Sim.TICKS_PER_SECOND)
	result["cost_g"] = IntMath.mul_div_ceil(base_g, mass_g, stats["rated_mass_g"])
	result["arrive_tick"] = from_tick + result["ticks"] - 1
	return result


## The point `stop_mm` short of the target on the line from `from_mm`, floored on each axis.
static func stop_point(from_mm: Array, target_mm: Array, total_mm: int, stop_mm: int) -> Array:
	var point := []
	for axis in 3:
		point.append(along(from_mm[axis], target_mm[axis], total_mm - stop_mm, total_mm))
	return point


## One axis of a point `done` of `whole` along the way from `start` to `end`.
static func along(start: int, end: int, done: int, whole: int) -> int:
	var step := IntMath.mul_div(absi(end - start), done, whole)
	return start + step if end >= start else start - step


static func _position(ctx: SimContext, target: int) -> Array:
	if ctx.state["bodies"].has(target):
		return ctx.state["bodies"][target]["pos_mm"]
	return ctx.state["units"][target]["pos_mm"]


static func _stop_distance(ctx: SimContext, target: int) -> int:
	if ctx.state["bodies"].has(target):
		return ctx.state["bodies"][target]["radius_mm"] + STANDOFF_MM
	return STANDOFF_MM
