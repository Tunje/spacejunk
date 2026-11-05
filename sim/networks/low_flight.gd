class_name LowFlight
extends RefCounted
## Flight near a planet's surface, for the player's hand-flown landing (orbital_flight.md section
## 11, task A19). An orbit record can't hold the near-vertical paths a landing uses, so below
## ENTER_MM above the datum a unit flies as a position and velocity relative to the body, with
## gravity applied every tick in integers. Above LEAVE_MM it goes back to an orbit.
##
## The ground is the height of the cell below. A unit that meets it at or under its landing gear's
## touchdown speed lands; any faster and it crashes. Both leave it landed on the cell.

const ENTER_MM := 20_000_000
const LEAVE_MM := 30_000_000
## Contact is only tested below the highest ground can be, plus a margin.
const CONTACT_GATE_MM := PlanetGrid.MAX_HEIGHT_M * 1000 + 1_000_000
const GEAR := "landing_gear"
## Gravity per tick: GM in units of 1000 m^3/s^2 is 10^15 um^3/s^2... per mm^2 of radius squared,
## so the acceleration in um/s^2 is gm * 10^15 / r_mm^2.
const UM_PER_S2_FACTOR := 1_000_000_000_000_000


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


## Switches a unit from an orbit around a body with gravity to low flight, at the same place and speed.
static func enter(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var body: int = unit["orbit"]["parent"]
	var now := OrbitMath.state_at(unit["orbit"], ctx.state["bodies"][body]["gm"], ctx.tick)
	unit["orbit"] = {}
	unit["low_flight"] = body
	unit["pos_mm"] = now["r"]
	unit["vel_um_s"] = now["v"]
	unit["drift_carry"] = [0, 0, 0]
	ctx.emit_event("low_flight_entered", unit_id, { "body": body })


## Lifts a landed unit into low flight from its cell, still.
static func lift(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var body: int = unit["landed"]["body"]
	unit["landed"] = {}
	unit["low_flight"] = body
	unit["vel_um_s"] = [0, 0, 0]
	unit["drift_carry"] = [0, 0, 0]
	ctx.emit_event("low_flight_entered", unit_id, { "body": body })


## One tick of low flight: gravity, then motion, then ground contact or the climb back to orbit.
static func step(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var body: int = unit["low_flight"]
	var next := advance(ctx, body, unit["pos_mm"], unit["vel_um_s"], unit["drift_carry"])
	unit["pos_mm"] = next["pos"]
	unit["vel_um_s"] = next["vel"]
	unit["drift_carry"] = next["carry"]
	var contact := ground_contact(ctx, body, next["pos"])
	if contact >= 0:
		_touch_down(ctx, unit_id, body, contact)
		return
	if altitude_mm(ctx, body, next["pos"]) > LEAVE_MM:
		_leave(ctx, unit_id, body)


## Gravity and one tick of motion, as plain values: { pos, vel, carry }. Shared with predict, so the
## drawn path is the flown one.
static func advance(ctx: SimContext, body: int, pos: Array, vel: Array, carry: Array) -> Dictionary:
	var r := IntMath.dist(pos, [0, 0, 0])
	var gm: int = ctx.state["bodies"][body]["gm"]
	var pull := IntMath.mul_div(gm, UM_PER_S2_FACTOR, maxi(1, r) * maxi(1, r)) / Sim.TICKS_PER_SECOND
	var down := OrbitMath.unit(pos)
	var new_vel: Array[int] = []
	var new_pos: Array[int] = []
	var new_carry: Array[int] = []
	for axis in 3:
		new_vel.append(int(vel[axis]) - OrbitMath.smul_div(down[axis], pull, OrbitMath.ONE))
		var total: int = int(carry[axis]) + new_vel[axis]
		var moved := BurnSystem._floor_div(total, BurnSystem.DRIFT_PER_MM)
		new_pos.append(int(pos[axis]) + moved)
		new_carry.append(total - moved * BurnSystem.DRIFT_PER_MM)
	return { "pos": new_pos, "vel": new_vel, "carry": new_carry }


## The cell a point has met the ground of, or -1 if it is still above ground.
static func ground_contact(ctx: SimContext, body: int, pos: Array) -> int:
	if altitude_mm(ctx, body, pos) > CONTACT_GATE_MM:
		return -1
	var cell := LandingSystem.cell_below(ctx, body, pos)
	var ground := IntMath.dist(LandingSystem.cell_mm(ctx, body, cell), [0, 0, 0])
	return cell if IntMath.dist(pos, [0, 0, 0]) <= ground else -1


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
	unit["low_flight"] = 0
	LandingSystem._set_down(ctx, unit_id, body, cell)
	ctx.emit_event(outcome, unit_id, { "body": body, "cell": cell, "speed_um_s": speed })


static func _leave(ctx: SimContext, unit_id: int, body: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var orbit := OrbitMath.from_state(unit["pos_mm"], unit["vel_um_s"], ctx.state["bodies"][body]["gm"], ctx.tick)
	if orbit.is_empty():
		return  # straight up and down: stay in low flight until the path bends
	orbit["parent"] = body
	unit["orbit"] = orbit
	unit["low_flight"] = 0
	unit["vel_um_s"] = [0, 0, 0]
	unit["drift_carry"] = [0, 0, 0]
	ctx.emit_event("low_flight_left", unit_id, { "body": body })


## [prograde, normal, radial] for a burn in low flight: prograde is the level part of the velocity,
## or east around +Y when there is none, and radial is straight up.
static func basis(unit: Dictionary) -> Array:
	var up := OrbitMath.unit(unit["pos_mm"])
	var vel: Array = unit["vel_um_s"]
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


## The path ahead in low flight, as predict gives it: points every `step` ticks, and where it meets
## the ground, as { points, contact }.
static func path(ctx: SimContext, unit: Dictionary, ticks: int, step: int) -> Dictionary:
	var body: int = unit["low_flight"]
	var pos: Array = unit["pos_mm"]
	var vel: Array = unit["vel_um_s"]
	var carry: Array = unit["drift_carry"]
	var points: Array = [pos.duplicate()]
	var contact := {}
	for t in range(1, ticks + 1):
		var next := advance(ctx, body, pos, vel, carry)
		pos = next["pos"]
		vel = next["vel"]
		carry = next["carry"]
		if t % step == 0:
			points.append(pos.duplicate())
		var cell := ground_contact(ctx, body, pos)
		if cell >= 0:
			contact = { "tick": ctx.state["tick"] + t, "cell": cell,
				"speed_um_s": IntMath.dist(vel, [0, 0, 0]) }
			points.append(pos.duplicate())
			break
	return { "points": points, "contact": contact }
