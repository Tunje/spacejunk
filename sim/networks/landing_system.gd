class_name LandingSystem
extends SimSystem
## Landing, takeoff and collisions (orbital_flight.md section 11, task A15). Landing and takeoff are
## autopilot operations with an integer delta-v cost, not simulated descents (planets.md section 3.2).
##
## - `land { body, cell }` from an orbit around the body. The cost is the burn down to the surface
##   on half an ellipse, plus killing the speed left at the surface, with a gravity loss. It is
##   paid at the start, and the operation lasts the half ellipse. Then the unit is landed: its place
##   is the body and cell, at the cell's centre and integer height.
## - `take_off { altitude_mm }` reverses it, onto a circular orbit through the cell's direction,
##   moving east.
## - A unit on an orbit whose position falls below its parent body's surface crashes. It is
##   landed on the cell below, its burn or transfer ends, and `crashed` fires. Damage comes later.
##
## Both operations are atomic, as docking is. Register after BurnSystem and before PowerSystem.

const LAND := "land"
const TAKE_OFF := "take_off"
const OP_LANDING := "landing"
const OP_TAKING_OFF := "taking_off"
const DELTA_PROPELLANT := "propellant"
const REASON_MALFORMED := "malformed_command"
const REASON_NOT_FLYING := "not_flying"
const REASON_INVALID := "invalid_target"
const REASON_BUSY := "part_busy"
const REASON_NO_PROPELLANT := "no_propellant"
const REASON_NO_THRUSTER := "module_missing"
const REASON_NOT_LANDED := "not_landed"
## Landing and takeoff lose 3% more than the ideal burns to gravity: on an airless body the craft
## kills its speed close to the ground, so the loss is small.
const GRAVITY_LOSS_PERMILLE := 1030
## The default octave weights for a planet's height, as A14's tests use.
const HEIGHT_WEIGHTS := [4, 2, 1]


func commands() -> PackedStringArray:
	return PackedStringArray([LAND, TAKE_OFF])


func validate(ctx: SimContext, command: Dictionary) -> Dictionary:
	var unit_id: int = command["unit"]
	var unit: Dictionary = ctx.state["units"][unit_id]
	var args: Dictionary = command["args"]
	if unit["op"]["type"] != Units.IDLE_OP or not unit["burn"].is_empty() or not unit["route"].is_empty() \
			or not unit["transfer"].is_empty():
		return SimSystem.reject(REASON_BUSY)
	var plan := _plan(ctx, unit_id, command["type"], args)
	if plan.has("reason"):
		return SimSystem.reject(plan["reason"])
	var free := Reservations.free_stock(ctx, unit_id, Travel.PROPELLANT)
	if plan["cost_g"] > free:
		return SimSystem.reject(REASON_NO_PROPELLANT, { "need_g": plan["cost_g"], "have_g": free })
	var result := SimSystem.ok()
	result["detail"] = { "dv_um_s": plan["dv_um_s"], "propellant_g": plan["cost_g"], "ticks": plan["ticks"] }
	return result


func apply(ctx: SimContext, command: Dictionary) -> void:
	var unit_id: int = command["unit"]
	var unit: Dictionary = ctx.state["units"][unit_id]
	var plan := _plan(ctx, unit_id, command["type"], command["args"])
	var op_type := OP_LANDING if command["type"] == LAND else OP_TAKING_OFF
	unit["op"] = { "type": op_type, "target": plan["body"], "part": 0, "start_tick": ctx.tick,
		"end_tick": ctx.tick + plan["ticks"] - 1, "cell": plan["cell"], "altitude_mm": plan["altitude_mm"] }
	unit["at_target"] = 0
	if plan["cost_g"] > 0:
		Reservations.claim_stock(ctx, unit_id, Travel.PROPELLANT, plan["cost_g"])
		ctx.record_delta(unit_id, self, { "kind": DELTA_PROPELLANT, "unit": unit_id, "grams": plan["cost_g"] })


## Phase 5: finish landings and takeoffs, then crash anything below a surface.
func run(ctx: SimContext) -> void:
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		var unit: Dictionary = units[id]
		var op: Dictionary = unit["op"]
		if (op["type"] == OP_LANDING or op["type"] == OP_TAKING_OFF) and ctx.tick >= op["end_tick"]:
			if op["type"] == OP_LANDING:
				_set_down(ctx, id, op["target"], op["cell"])
				ctx.emit_event("landed", id, { "body": op["target"], "cell": op["cell"] })
			else:
				_lift(ctx, id, op["altitude_mm"])
				ctx.emit_event("took_off", id, { "body": op["target"] })
			unit["op"] = { "type": Units.IDLE_OP, "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 }
		elif not unit["orbit"].is_empty() and unit["dock"].is_empty() and op["type"] != OP_LANDING:
			_check_crash(ctx, id)


func apply_delta(ctx: SimContext, payload: Dictionary) -> void:
	Units.remove_stock(ctx.state["units"][payload["unit"]]["inventory"], Travel.PROPELLANT, payload["grams"])
	var sink: Dictionary = ctx.state["sinks"].get_or_add(Travel.SINK, {})
	sink[Travel.PROPELLANT] = sink.get(Travel.PROPELLANT, 0) + payload["grams"]


func fill_view(ctx: SimContext, view: Dictionary) -> void:
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		view["units"][id]["landed"] = units[id]["landed"].duplicate()


# ------------------------------------------------------------------------------ plans

## { body, cell, altitude_mm, dv_um_s, cost_g, ticks } for a land or take_off, or { reason }.
static func _plan(ctx: SimContext, unit_id: int, type: String, args: Dictionary) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][unit_id]
	if not unit["dock"].is_empty():
		return { "reason": REASON_NOT_FLYING }
	var found := BurnSystem.thruster(ctx, unit_id)
	if found.is_empty():
		return { "reason": REASON_NO_THRUSTER }
	var body_id: int
	var cell: int
	var low_mm: int
	var high_mm: int
	var altitude := 0
	if type == LAND:
		if typeof(args.get("body")) != TYPE_INT or typeof(args.get("cell")) != TYPE_INT:
			return { "reason": REASON_MALFORMED }
		if unit["orbit"].is_empty() or unit["orbit"]["parent"] != args["body"] or not unit["landed"].is_empty():
			return { "reason": REASON_NOT_FLYING }
		body_id = args["body"]
		cell = args["cell"]
		if cell < 0 or cell >= PlanetGrid.cell_count(_grid_n(ctx, body_id)):
			return { "reason": REASON_INVALID }
		low_mm = ctx.state["bodies"][body_id]["radius_mm"]
		high_mm = IntMath.dist(unit["pos_mm"], [0, 0, 0])
	else:
		if unit["landed"].is_empty():
			return { "reason": REASON_NOT_LANDED }
		if typeof(args.get("altitude_mm")) != TYPE_INT or args["altitude_mm"] <= 0:
			return { "reason": REASON_MALFORMED }
		body_id = unit["landed"]["body"]
		cell = unit["landed"]["cell"]
		altitude = args["altitude_mm"]
		low_mm = ctx.state["bodies"][body_id]["radius_mm"]
		high_mm = low_mm + altitude
		var soi: int = ctx.state["bodies"][body_id].get("soi_mm", 0)
		if soi > 0 and high_mm >= soi:
			return { "reason": REASON_INVALID }
	var gm: int = ctx.state["bodies"][body_id]["gm"]
	var a_t := (low_mm + high_mm) / 2
	var surface := IntMath.mul_div(OrbitMath.speed_um_s(gm, low_mm, a_t), GRAVITY_LOSS_PERMILLE, 1000)
	var orbit_end := absi(OrbitMath.speed_um_s(gm, high_mm, high_mm) - OrbitMath.speed_um_s(gm, high_mm, a_t))
	var dv := surface + orbit_end
	var mass_g := Units.unit_mass(ctx.state, ctx.defs, unit_id)
	var ticks := maxi(1, OrbitMath.period_sub(gm, a_t) / (2 * OrbitMath.SUB_TICKS))
	return {
		"body": body_id, "cell": cell, "altitude_mm": altitude, "dv_um_s": dv, "ticks": ticks,
		"cost_g": OrbitMath.burn_g(mass_g, dv, found["exhaust_mm_s"]),
	}


## The grid size of a body, from its radius: about 7 km a hex (A14).
static func _grid_n(ctx: SimContext, body_id: int) -> int:
	return PlanetGrid.n_for_radius(ctx.state["bodies"][body_id]["radius_mm"])


## A cell's centre in mm from the body's centre, at its integer height. A body with no `planet`
## settings is a smooth sphere.
static func cell_mm(ctx: SimContext, body_id: int, cell: int) -> Array[int]:
	var body: Dictionary = ctx.state["bodies"][body_id]
	var n := _grid_n(ctx, body_id)
	var height := 0
	var planet: Dictionary = body.get("planet", {})
	if not planet.is_empty():
		var dir := PlanetGrid.direction(cell, n)
		height = PlanetGrid.height_m(planet["seed"], dir, HEIGHT_WEIGHTS, planet.get("height_range_m", 0))
	return PlanetGrid.centre_mm(cell, n, body["radius_mm"], height)


## The cell under a point, by its nearest centre among a short walk of neighbours from a good guess.
static func cell_below(ctx: SimContext, body_id: int, pos: Array) -> int:
	var n := _grid_n(ctx, body_id)
	var dir := OrbitMath.unit(pos)
	var best := PlanetGrid.NORTH if dir[1] >= 0 else PlanetGrid.SOUTH
	var best_dot := OrbitMath.dot(PlanetGrid.direction(best, n), dir)
	# Start from the nearer of the twelve icosahedron corners' cells, then walk downhill.
	for d in PlanetGrid.DIAMONDS:
		var corner := PlanetGrid.cell_at(d, n, 0, n)
		var closeness := OrbitMath.dot(PlanetGrid.direction(corner, n), dir)
		if closeness > best_dot:
			best = corner
			best_dot = closeness
	var improved := true
	while improved:
		improved = false
		for other in PlanetGrid.neighbours(best, n):
			var closeness := OrbitMath.dot(PlanetGrid.direction(other, n), dir)
			if closeness > best_dot:
				best = other
				best_dot = closeness
				improved = true
	return best


static func _set_down(ctx: SimContext, unit_id: int, body_id: int, cell: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	unit["landed"] = { "body": body_id, "cell": cell }
	unit["orbit"] = {}
	unit["frame"] = 0
	unit["pos_mm"] = cell_mm(ctx, body_id, cell)
	unit["vel_um_s"] = [0, 0, 0]
	unit["drift_carry"] = [0, 0, 0]


## Onto a circular orbit at the altitude, through the cell's direction, moving east around +Y.
static func _lift(ctx: SimContext, unit_id: int, altitude_mm: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var body_id: int = unit["landed"]["body"]
	var body: Dictionary = ctx.state["bodies"][body_id]
	var dir := PlanetGrid.direction(unit["landed"]["cell"], _grid_n(ctx, body_id))
	var east := OrbitMath.unit(OrbitMath.cross([0, OrbitMath.ONE, 0], dir))
	if east == [0, 0, 0]:
		east = [OrbitMath.ONE, 0, 0]  # at a pole, any direction is east
	var a: int = body["radius_mm"] + altitude_mm
	var speed := OrbitMath.speed_um_s(body["gm"], a, a)
	var r: Array[int] = []
	var v: Array[int] = []
	for axis in 3:
		r.append(OrbitMath.smul_div(dir[axis], a, OrbitMath.ONE))
		v.append(OrbitMath.smul_div(east[axis], speed, OrbitMath.ONE))
	var orbit := OrbitMath.from_state(r, v, body["gm"], ctx.tick)
	orbit["parent"] = body_id
	unit["orbit"] = orbit
	unit["landed"] = {}
	unit["pos_mm"] = OrbitMath.position_at(orbit, ctx.tick)


## A unit on an orbit below its parent's surface comes down on the cell beneath it.
func _check_crash(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var body_id: int = unit["orbit"]["parent"]
	var body: Dictionary = ctx.state["bodies"][body_id]
	if body["gm"] <= 0 or IntMath.dist(unit["pos_mm"], [0, 0, 0]) >= body["radius_mm"]:
		return
	var cell := cell_below(ctx, body_id, unit["pos_mm"])
	if not unit["burn"].is_empty():
		ctx.emit_event("burn_short", unit_id, { "burn": unit["burn"]["id"], "reason": "crashed",
			"dv_um_s": unit["burn"]["done_um_s"], "propellant_g": unit["burn"].get("spent_g", 0) })
		unit["burn"] = {}
	unit["transfer"] = {}
	unit["op"] = { "type": Units.IDLE_OP, "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 }
	_set_down(ctx, unit_id, body_id, cell)
	ctx.emit_event("crashed", unit_id, { "body": body_id, "cell": cell })


func _sorted(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids
