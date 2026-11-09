class_name LowFlight
extends RefCounted
## Stepped flight (real_orbits.md section 2, task A55; first written for the hand-flown landing in
## A19). A unit flies as a position and velocity relative to a body, stepped every tick in integers,
## when it is:
## - thrusting, anywhere: a burn's start converts its orbit exactly (state_at), and each tick's
##   thrust is added to the velocity;
## - coasting on a path within the ground's reach (the contact gate: the body's highest ground plus
##   CONTACT_MARGIN_MM), so the ground is met tick by tick.
## Otherwise it rides an exact orbit record, which coasting can skip ahead. A coasting stepped unit
## converts back (from_state) once it is RETURN_MARGIN_MM above the gate. The unit's `stepped`
## field is the body's ID, or 0. This replaces A19's 20 km and 30 km altitudes.
##
## Each tick is velocity Verlet: half a tick of gravity, the move, then half a tick of gravity at the
## new place. The velocity's sub-um/s remainder is kept in `vel_carry_nm` and the position's
## sub-millimetre one in `drift_carry`, in 1/STEP_PER_MM mm, so no rounding builds up between ticks.
## Thrust is an impulse at the end of its tick, as an orbit burn's always was. Gravity is one body's
## (patched conics); crossing a sphere of influence re-bases the state to the new body.
##
## The ground is the height of the cell below. A unit that meets it at or under its landing gear's
## touchdown speed lands; any faster and it crashes. Both leave it landed on the cell. A body with
## no terrain data has no ground here.

## The lowest orbit take_off reaches (A27, A39). Stage 5 of real orbits flies take-off and revises it.
const LEAVE_MM := 30_000_000
## Contact is only tested below the highest the body's ground can be, plus this margin.
const CONTACT_MARGIN_MM := 1_000_000
## A coasting stepped unit goes back onto an orbit this far above the contact gate.
const RETURN_MARGIN_MM := 1_000_000
const GEAR := "landing_gear"
## Gravity: GM in units of 1000 m^3/s^2, over r in mm squared, times this, is um/s^2.
const UM_PER_S2_FACTOR := 1_000_000_000_000_000
## The position remainder's units per mm (0.1 nm), and the velocity remainder's per um/s.
const STEP_PER_MM := 10_000_000
const NM_PER_UM := 1000
## Half a tick, as a divisor of a per-second rate in nm/s^2, giving nm/s.
const HALF_TICKS_PER_SECOND := 2 * Sim.TICKS_PER_SECOND


static func altitude_mm(ctx: SimContext, body: int, pos: Array) -> int:
	return IntMath.dist(pos, [0, 0, 0]) - int(ctx.state["bodies"][body]["radius_mm"])


## The touchdown speed limit from the unit's healthy landing gear, or 0 with none.
static func touchdown_mm_s(ctx: SimContext, unit_id: int) -> int:
	var best := 0
	for part_id in Units.part_ids(ctx.state, unit_id):
		if ctx.state["parts"][part_id]["fault"] != "":
			continue
		var gear: Dictionary = Units.module_of(ctx.state, ctx.defs, part_id)["capabilities"].get(GEAR, {})
		best = maxi(best, gear.get("max_touchdown_mm_s", 0))
	return best


## The height above the datum below which a coasting orbit is stepped: the contact gate.
static func enter_mm(ctx: SimContext, body: int) -> int:
	return contact_gate_mm(ctx, body)


## The height above the datum above which a coasting stepped unit goes back onto an orbit.
static func return_mm(ctx: SimContext, body: int) -> int:
	return contact_gate_mm(ctx, body) + RETURN_MARGIN_MM


## True if a coasting unit on an orbit round a body with gravity is within the ground's reach.
static func should_enter(ctx: SimContext, unit: Dictionary) -> bool:
	var body: Dictionary = ctx.state["bodies"][unit["orbit"]["parent"]]
	return body["gm"] > 0 and IntMath.dist_below(unit["pos_mm"],
		int(body["radius_mm"]) + enter_mm(ctx, unit["orbit"]["parent"]))


## Switches a unit from its orbit to stepped flight, at the same place and speed.
static func enter(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var body: int = unit["orbit"]["parent"]
	var now := OrbitMath.state_at(unit["orbit"], ctx.state["bodies"][body]["gm"], ctx.tick)
	unit["orbit"] = {}
	unit["stepped"] = body
	unit["pos_mm"] = now["r"]
	unit["vel_um_s"] = now["v"]
	unit["drift_carry"] = [0, 0, 0]
	unit["vel_carry_nm"] = [0, 0, 0]
	ctx.emit_event("stepped_entered", unit_id, { "body": body })


## Lifts a landed unit into stepped flight from where it stands, still. No body rotates yet
## (real_orbits.md section 7); a turning body would give it the ground's own speed here.
static func lift(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var body: int = unit["landed"]["body"]
	unit["landed"] = {}
	unit["stepped"] = body
	unit["vel_um_s"] = [0, 0, 0]
	unit["drift_carry"] = [0, 0, 0]
	unit["vel_carry_nm"] = [0, 0, 0]
	ctx.emit_event("stepped_entered", unit_id, { "body": body })


## One tick of gravity and motion, then ground contact and the crossing of a sphere of influence.
## Thrust comes after, from BurnSystem, and then settle().
static func step(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var body: int = unit["stepped"]
	var memo: Dictionary = ctx.ground_memo.get_or_add(unit_id, {})
	if memo.get("body", 0) != body:
		memo.clear()
		memo["body"] = body
	# The last step's gravity is this step's start, if the unit is still where it left it.
	var known: Array = memo["accel"] if memo.get("accel_at", []) == unit["pos_mm"] else []
	var next := advance(ctx, body, unit["pos_mm"], unit["vel_um_s"], unit["drift_carry"],
		unit.get("vel_carry_nm", [0, 0, 0]), known)
	unit["pos_mm"] = next["pos"]
	unit["vel_um_s"] = next["vel"]
	unit["drift_carry"] = next["carry"]
	unit["vel_carry_nm"] = next["vcarry"]
	memo["accel_at"] = next["pos"]
	memo["accel"] = next["accel"]
	var contact := ground_contact(ctx, body, next["pos"], memo)
	if contact >= 0:
		ctx.ground_memo.erase(unit_id)
		_touch_down(ctx, unit_id, body, contact)
		return
	var crossed := cross_sphere(ctx, body, unit["pos_mm"], unit["vel_um_s"], ctx.tick)
	if crossed[0] != body:
		unit["stepped"] = crossed[0]
		unit["pos_mm"] = crossed[1]
		unit["vel_um_s"] = crossed[2]
		ctx.ground_memo.erase(unit_id)
		ctx.emit_event("soi_changed", unit_id, { "from": body, "to": crossed[0] })


## After the tick's thrust: a coasting stepped unit above the ground's reach goes back onto its
## orbit, exactly where it is. One straight up or down, which no orbit record holds, stays stepped.
static func settle(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var body: int = unit["stepped"]
	if body == 0 or not unit["burn"].is_empty():
		return
	if ctx.state["bodies"][body]["gm"] > 0 and altitude_mm(ctx, body, unit["pos_mm"]) <= return_mm(ctx, body):
		return
	var orbit := OrbitMath.from_state(unit["pos_mm"], unit["vel_um_s"], ctx.state["bodies"][body]["gm"], ctx.tick)
	if orbit.is_empty():
		return
	orbit["parent"] = body
	unit["orbit"] = orbit
	unit["stepped"] = 0
	unit["vel_um_s"] = [0, 0, 0]
	unit["drift_carry"] = [0, 0, 0]
	unit["vel_carry_nm"] = [0, 0, 0]
	ctx.ground_memo.erase(unit_id)
	ctx.emit_event("stepped_left", unit_id, { "body": body })


## Gravity at a point, in nm/s^2, towards the body.
static func gravity_nm_s2(ctx: SimContext, body: int, pos: Array) -> Array[int]:
	var r := IntMath.dist(pos, [0, 0, 0])
	if r == 0:
		return [0, 0, 0]
	var gm: int = ctx.state["bodies"][body]["gm"]
	# gm * 10^18 / r^2 in two steps, so neither overflows from the surface of a moon to a star's.
	var pull := OrbitMath.smul_div(OrbitMath.smul_div(gm, 1_000_000_000_000, r), 1_000_000, r)
	var down: Array[int] = []
	for axis in 3:
		down.append(-OrbitMath.smul_div(int(pos[axis]), pull, r))
	return down


## One tick of velocity Verlet under one body's gravity, as plain values: { pos, vel, carry,
## vcarry }. Shared by the flight, the paths drawn and the flights ahead, so all agree exactly.
## `before` is the gravity at `pos` if already known (the last step's `accel`), which saves one of
## the two gravity evaluations; the result is the same either way.
static func advance(ctx: SimContext, body: int, pos: Array, vel: Array, carry: Array, vcarry: Array,
		before: Array = []) -> Dictionary:
	if before.is_empty():
		before = gravity_nm_s2(ctx, body, pos)
	var half: Array[int] = []
	var new_pos: Array[int] = []
	var new_carry: Array[int] = []
	for axis in 3:
		var v_nm: int = int(vel[axis]) * NM_PER_UM + int(vcarry[axis]) \
			+ OrbitMath.smul_div(before[axis], 1, HALF_TICKS_PER_SECOND)
		half.append(v_nm)
		# A tick moves v_nm / 10 nm, which is v_nm units of 0.1 nm.
		var total: int = int(carry[axis]) + v_nm
		var moved := _floor_div(total, STEP_PER_MM)
		new_pos.append(int(pos[axis]) + moved)
		new_carry.append(total - moved * STEP_PER_MM)
	var after := gravity_nm_s2(ctx, body, new_pos)
	var new_vel: Array[int] = []
	var new_vcarry: Array[int] = []
	for axis in 3:
		var v_nm: int = half[axis] + OrbitMath.smul_div(after[axis], 1, HALF_TICKS_PER_SECOND)
		var whole := _floor_div(v_nm, NM_PER_UM)
		new_vel.append(whole)
		new_vcarry.append(v_nm - whole * NM_PER_UM)
	return { "pos": new_pos, "vel": new_vel, "carry": new_carry, "vcarry": new_vcarry, "accel": after }


## [body, pos, vel] after crossing a sphere of influence at a tick: out of the body's own sphere
## to its parent, or into the sphere of one of its children, lowest ID first. Unchanged if neither.
static func cross_sphere(ctx: SimContext, body_id: int, pos: Array, vel: Array, tick: int) -> Array:
	var bodies: Dictionary = ctx.state["bodies"]
	var body: Dictionary = bodies[body_id]
	if int(body.get("soi_mm", 0)) > 0 and not body["orbit"].is_empty() and IntMath.dist_above(pos, body["soi_mm"]):
		var up: int = body["orbit"]["parent"]
		var carried := OrbitMath.state_at(body["orbit"], bodies[up]["gm"], tick)
		return [up, _add(pos, carried["r"], 1), _add(vel, carried["v"], 1)]
	var children: Array = []
	for id: int in bodies:
		var child: Dictionary = bodies[id]
		if not child["orbit"].is_empty() and int(child["orbit"]["parent"]) == body_id and int(child.get("soi_mm", 0)) > 0:
			children.append(id)
	children.sort()
	for id: int in children:
		var child: Dictionary = bodies[id]
		var place := OrbitMath.position_at(child["orbit"], tick)
		if IntMath.dist_below(_add(pos, place, -1), child["soi_mm"]):
			var carried := OrbitMath.state_at(child["orbit"], body["gm"], tick)
			return [id, _add(pos, carried["r"], -1), _add(vel, carried["v"], -1)]
	return [body_id, pos, vel]


static func _add(a: Array, b: Array, sign: int) -> Array[int]:
	return [int(a[0]) + sign * int(b[0]), int(a[1]) + sign * int(b[1]), int(a[2]) + sign * int(b[2])]


## The cell a point has met the ground of, or -1 if it is still above ground. Nothing is looked up
## above the body's highest possible ground, or on a body with no terrain. A `memo` kept across
## the ticks of one path, or of one unit's flight, holds the last cell found, to start the next
## search from, and each cell's ground radius; the answer is the same with or without it, so a
## drawn path meets the ground where the flown one does.
static func ground_contact(ctx: SimContext, body: int, pos: Array, memo: Dictionary) -> int:
	if not ctx.state["bodies"][body].has("planet") or altitude_mm(ctx, body, pos) > contact_gate_mm(ctx, body):
		return -1
	var cell := LandingSystem.cell_below(ctx, body, pos, memo.get("cell", -1))
	memo["cell"] = cell
	var grounds: Dictionary = memo.get_or_add("grounds", {})
	if not grounds.has(cell):
		grounds[cell] = IntMath.dist(LandingSystem.cell_mm(ctx, body, cell), [0, 0, 0])
	return cell if IntMath.dist(pos, [0, 0, 0]) <= int(grounds[cell]) else -1


## The height above the datum below which a point can meet a body's ground: its highest possible
## ground (orbital_flight.md 8, PlanetGrid.height_m), plus a margin.
static func contact_gate_mm(ctx: SimContext, body: int) -> int:
	var planet: Dictionary = ctx.state["bodies"][body].get("planet", {})
	return int(planet.get("height_range_m", 0)) * 1000 + CONTACT_MARGIN_MM


static func _touch_down(ctx: SimContext, unit_id: int, body: int, cell: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var speed := IntMath.dist(unit["vel_um_s"], [0, 0, 0])
	var gentle := speed <= touchdown_mm_s(ctx, unit_id) * 1000
	var outcome := "landed" if gentle else "crashed"
	if not unit["burn"].is_empty():
		ctx.emit_event("burn_short", unit_id, { "burn": unit["burn"]["id"], "reason": outcome,
			"dv_um_s": unit["burn"]["done_um_s"], "propellant_g": unit["burn"].get("spent_g", 0) })
		unit["burn"] = {}
		unit["op"] = { "type": Units.IDLE_OP, "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 }
	unit["stepped"] = 0
	unit["vel_carry_nm"] = [0, 0, 0]
	LandingSystem._set_down(ctx, unit_id, body, cell)
	ctx.emit_event(outcome, unit_id, { "body": body, "cell": cell, "speed_um_s": speed })


## [prograde, normal, radial] for a burn in stepped flight. Near the ground (within return_mm)
## prograde is the level part of the velocity, or east around +Y when there is none, and radial is
## straight up, for landing and hovering. Higher, it is the orbit's: prograde along the velocity.
static func basis_at(ctx: SimContext, body: int, pos: Array, vel: Array) -> Array:
	if ctx.state["bodies"][body]["gm"] > 0 and altitude_mm(ctx, body, pos) <= return_mm(ctx, body):
		return surface_basis(pos, vel)
	return state_basis(pos, vel)


## The surface basis for a unit's own position and velocity.
static func basis(unit: Dictionary) -> Array:
	return surface_basis(unit["pos_mm"], unit["vel_um_s"])


static func surface_basis(pos: Array, vel: Array) -> Array:
	var up := OrbitMath.unit(pos)
	var level: Array[int] = []
	var rise := OrbitMath.dot(vel, up)
	for axis in 3:
		level.append(int(vel[axis]) - OrbitMath.smul_div(up[axis], rise, OrbitMath.ONE))
	var prograde := OrbitMath.unit(level)
	if IntMath.dist(level, [0, 0, 0]) < 1000 or prograde == [0, 0, 0]:
		prograde = OrbitMath.unit(OrbitMath.cross([0, OrbitMath.ONE, 0], up))
		if prograde == [0, 0, 0]:
			prograde = [OrbitMath.ONE, 0, 0]
	var normal := OrbitMath.unit(OrbitMath.cross(up, prograde))
	return [prograde, normal, up]


## [prograde, normal, radial out] from a position and velocity, as an orbit's basis is.
static func state_basis(pos: Array, vel: Array) -> Array:
	var prograde := OrbitMath.unit(vel)
	if prograde == [0, 0, 0]:
		return surface_basis(pos, vel)
	var normal := OrbitMath.unit(OrbitMath.cross(OrbitMath.unit(pos), prograde))
	if normal == [0, 0, 0]:
		return surface_basis(pos, vel)
	return [prograde, normal, OrbitMath.cross(prograde, normal)]


## The path ahead of a coasting stepped unit, as predict gives it: points every `step` ticks, and
## where it meets the ground, as { points, contact }. Planned burns are flown by FlightAhead.
static func path(ctx: SimContext, unit: Dictionary, ticks: int, step: int) -> Dictionary:
	var body: int = unit["stepped"]
	var pos: Array = unit["pos_mm"]
	var vel: Array = unit["vel_um_s"]
	var carry: Array = unit["drift_carry"]
	var vcarry: Array = unit.get("vel_carry_nm", [0, 0, 0])
	var points: Array = [pos.duplicate()]
	var contact := {}
	var memo := {}
	for t in range(1, ticks + 1):
		var next := advance(ctx, body, pos, vel, carry, vcarry)
		pos = next["pos"]
		vel = next["vel"]
		carry = next["carry"]
		vcarry = next["vcarry"]
		if t % step == 0:
			points.append(pos.duplicate())
		var cell := ground_contact(ctx, body, pos, memo)
		if cell >= 0:
			contact = { "tick": ctx.state["tick"] + t, "cell": cell,
				"speed_um_s": IntMath.dist(vel, [0, 0, 0]) }
			points.append(pos.duplicate())
			break
	return { "points": points, "contact": contact }


## Division rounding towards minus infinity, so motion steps the same either way along an axis.
static func _floor_div(a: int, b: int) -> int:
	var q := a / b
	return q - 1 if (a % b != 0) and ((a < 0) != (b < 0)) else q
