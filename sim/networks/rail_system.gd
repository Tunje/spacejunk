class_name RailSystem
extends SimSystem
## Where things are (orbital_flight.md section 11). Every body, frame and unit is in one place:
## - On an orbit around a parent body. Its `pos_mm` is relative to the parent, and derived from the
##   tick by OrbitMath.
## - In a frame, such as the rock cluster. Its `pos_mm` is local to the frame, and today's travel
##   works inside it unchanged.
## - Neither: frame 0, with `pos_mm` as given. This is the old world, in which nothing moves on its own.
## A docked unit is wherever its host is.
##
## Register first, so phase 2 moves everything on rails before any other system reads a position.

## Place of anything on an orbit. Only frames are travelled within, so this matches nothing.
const ON_ORBIT := -1
const STAR_KIND := "star"


func update_tasks(ctx: SimContext) -> void:
	var bodies: Dictionary = ctx.state["bodies"]
	for id: int in _sorted(bodies):
		if not bodies[id]["orbit"].is_empty():
			bodies[id]["pos_mm"] = OrbitMath.position_at(bodies[id]["orbit"], ctx.tick)
	var frames: Dictionary = ctx.state["frames"]
	for id: int in _sorted(frames):
		frames[id]["pos_mm"] = OrbitMath.position_at(frames[id]["orbit"], ctx.tick)
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		if not units[id]["orbit"].is_empty() and units[id]["dock"].is_empty():
			units[id]["pos_mm"] = OrbitMath.position_at(units[id]["orbit"], ctx.tick)


func fill_view(ctx: SimContext, view: Dictionary) -> void:
	var frames: Dictionary = ctx.state["frames"]
	for id: int in _sorted(frames):
		var frame: Dictionary = frames[id]
		view["frames"][id] = {
			"name": frame["name"], "radius_mm": frame["radius_mm"], "orbit": frame["orbit"].duplicate(true),
			"pos_mm": frame["pos_mm"].duplicate(), "world_mm": world_mm(ctx.state, "frames", id),
		}


## The frame a unit travels in, ON_ORBIT if it is on an orbit, or 0 in the old world.
static func unit_place(state: Dictionary, unit_id: int) -> int:
	var unit: Dictionary = state["units"][unit_id]
	if not unit["dock"].is_empty():
		return unit_place(state, unit["dock"]["target_unit"])
	if not unit["orbit"].is_empty() or not unit.get("landed", {}).is_empty():
		return ON_ORBIT
	return unit["frame"]


## The frame a move_to target sits in, as unit_place gives for units.
static func target_place(state: Dictionary, target: int) -> int:
	if state["bodies"].has(target):
		var body: Dictionary = state["bodies"][target]
		return ON_ORBIT if not body["orbit"].is_empty() else body["frame"]
	return unit_place(state, target)


## The position relative to the root of everything, in mm, for "bodies", "frames" or "units".
static func world_mm(state: Dictionary, table: String, id: int) -> Array[int]:
	var entry: Dictionary = state[table][id]
	if table == "units" and not entry["dock"].is_empty():
		return world_mm(state, "units", entry["dock"]["target_unit"])
	var pos: Array = entry["pos_mm"]
	var base: Array[int] = [0, 0, 0]
	if not entry["orbit"].is_empty():
		base = world_mm(state, "bodies", entry["orbit"]["parent"])
	elif table == "units" and not entry.get("landed", {}).is_empty():
		base = world_mm(state, "bodies", entry["landed"]["body"])
	elif table != "frames" and entry["frame"] != 0:
		base = world_mm(state, "frames", entry["frame"])
	return [base[0] + pos[0], base[1] + pos[1], base[2] + pos[2]]


## True if a body with gravity stands between the unit and the star, by a cylinder test: the
## unit is behind the body, seen from the star, and closer to the body's line than its radius
## (task A16). Integers only. A world without a body of kind "star" has no shadows. Pass the
## casters from shadow_casters when testing many units in one tick.
static func in_shadow(state: Dictionary, unit_id: int, casters: Array = []) -> bool:
	if casters.is_empty():
		casters = shadow_casters(state)
	var unit_mm := world_mm(state, "units", unit_id)
	for caster: Array in casters:
		var body_mm: Array = caster[0]
		var direction: Array = caster[1]
		var offset: Array[int] = []
		for axis in 3:
			offset.append(unit_mm[axis] - int(body_mm[axis]))
		var along := OrbitMath.dot(offset, direction)
		if along <= 0:
			continue
		var across: Array[int] = []
		for axis in 3:
			across.append(offset[axis] - OrbitMath.smul_div(direction[axis], along, OrbitMath.ONE))
		if IntMath.dist(across, [0, 0, 0]) < caster[2]:
			return true
	return false


## Each body that can cast a shadow this tick, as [world_mm, direction from the star in Q30,
## radius_mm]. Working the directions out once per tick keeps the slow wide distance at AU scale
## out of the per-unit test.
static func shadow_casters(state: Dictionary) -> Array:
	var bodies: Dictionary = state["bodies"]
	var star := 0
	for id: int in _keys(bodies):
		if bodies[id]["kind"] == STAR_KIND:
			star = id
			break
	var casters := []
	if star == 0:
		return casters
	var star_mm := world_mm(state, "bodies", star)
	for id: int in _keys(bodies):
		var body: Dictionary = bodies[id]
		if id == star or body["gm"] <= 0 or body["orbit"].is_empty():
			continue
		var body_mm := world_mm(state, "bodies", id)
		var away: Array[int] = []
		for axis in 3:
			away.append(body_mm[axis] - star_mm[axis])
		casters.append([body_mm, OrbitMath.unit(away), body["radius_mm"]])
	return casters


static func _keys(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids


func _sorted(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids
