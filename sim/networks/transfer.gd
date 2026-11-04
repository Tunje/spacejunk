class_name Transfer
extends RefCounted
## The autopilot's trip planner (orbital_flight.md section 11, task A13): trips between orbits around
## the same parent body. A core-flown `move_to` across places waits for the window this gives, then
## rides the transfer orbit on rails and arrives in the target's place.
##
## This first planner takes near-circular orbits in one plane:
## - Different radii: a Hohmann transfer, leaving when the phase angle is right, which comes round
##   once per synodic period.
## - The same ring, where Hohmann windows would be very rare: a phasing orbit that returns to the
##   start point just as the target arrives there, leaving at once.
## Anything else is refused with `unsupported_orbit`. Both burns are paid at departure, as a route is.

const REASON_UNSUPPORTED := "unsupported_orbit"
const REASON_NO_THRUSTER := "module_missing"
const REASON_NO_WINDOW := "no_window"
const KIND := "transfer"
## Orbits more eccentric than this, 0.01 in Q30, are refused.
const MAX_E_Q30 := 10_737_418
## cos 1 degree in Q30: orbit planes must be within a degree of each other.
const MIN_COPLANAR_Q30 := 1_073_578_288
## Radii within 1/15 of each other count as one ring: their windows would be over 10 orbits apart.
const SAME_RING_DIVISOR := 15
## A phasing orbit changes its period by at most a tenth per orbit flown.
const PHASING_STEP := 10


## The trip from unit to target leaving at the first chance at or after from_tick, as
## { kind, target, depart_tick, arrive_tick, ticks, cost_g, dv_um_s, orbit_a_mm, speed_um_s } or
## { reason }. `ticks` counts from departure to arrival inclusive, as a route's does.
static func plan(ctx: SimContext, unit_id: int, target: int, from_tick: int) -> Dictionary:
	return plan_from(ctx, unit_id, unit_orbit(ctx, unit_id), target,
		Units.unit_mass(ctx.state, ctx.defs, unit_id), from_tick)


## As plan, from any orbit at any mass, for pricing a leg the unit has not reached yet.
static func plan_from(ctx: SimContext, unit_id: int, mine: Dictionary, target: int, mass_g: int,
		from_tick: int) -> Dictionary:
	var theirs := target_orbit(ctx, target)
	if mine.is_empty() or theirs.is_empty() or not _compatible(mine, theirs):
		return { "reason": REASON_UNSUPPORTED }
	var found := BurnSystem.thruster(ctx, unit_id)
	if found.is_empty():
		return { "reason": REASON_NO_THRUSTER }
	var gm: int = ctx.state["bodies"][mine["parent"]]["gm"]
	var r1: int = mine["a_mm"]
	var r2: int = theirs["a_mm"]
	var leg: Dictionary
	if absi(r2 - r1) * SAME_RING_DIVISOR <= r1:
		leg = _phasing(ctx, mine, theirs, gm, from_tick)
	else:
		leg = _hohmann(ctx, mine, theirs, gm, from_tick)
	var first_g := OrbitMath.burn_g(mass_g, leg["dv1_um_s"], found["exhaust_mm_s"])
	var second_g := OrbitMath.burn_g(mass_g - first_g, leg["dv2_um_s"], found["exhaust_mm_s"])
	return {
		"kind": KIND, "target": target, "depart_tick": leg["depart_tick"],
		"arrive_tick": leg["depart_tick"] + leg["ticks"] - 1, "ticks": leg["ticks"],
		"cost_g": first_g + second_g, "dv_um_s": leg["dv1_um_s"] + leg["dv2_um_s"],
		"orbit_a_mm": leg["orbit_a_mm"],
	}


## The orbit a unit travels from: its own, its frame's, or its host's. {} in the old world.
static func unit_orbit(ctx: SimContext, unit_id: int) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][unit_id]
	if not unit["dock"].is_empty():
		return unit_orbit(ctx, unit["dock"]["target_unit"])
	if not unit["orbit"].is_empty():
		return unit["orbit"]
	if unit["frame"] != 0:
		return ctx.state["frames"][unit["frame"]]["orbit"]
	return {}


## The orbit a target travels on. A body with gravity is a place to orbit or land, not a
## rendezvous, so it has none here.
static func target_orbit(ctx: SimContext, target: int) -> Dictionary:
	if ctx.state["units"].has(target):
		return unit_orbit(ctx, target)
	var body: Dictionary = ctx.state["bodies"].get(target, {})
	if body.is_empty() or body["gm"] > 0:
		return {}
	if not body["orbit"].is_empty():
		return body["orbit"]
	if body["frame"] != 0:
		return ctx.state["frames"][body["frame"]]["orbit"]
	return {}


static func _compatible(mine: Dictionary, theirs: Dictionary) -> bool:
	if mine.get("hyperbolic", false) or theirs.get("hyperbolic", false):
		return false
	if mine["parent"] != theirs["parent"]:
		return false
	if mine["e_q30"] > MAX_E_Q30 or theirs["e_q30"] > MAX_E_Q30:
		return false
	var normal_mine := OrbitMath.cross(mine["p_q30"], mine["q_q30"])
	var normal_theirs := OrbitMath.cross(theirs["p_q30"], theirs["q_q30"])
	return OrbitMath.dot(normal_mine, normal_theirs) >= MIN_COPLANAR_Q30


## Where an orbit is at a tick, as a binary angle in the plane of `frame_orbit`.
static func angle_at(orbit: Dictionary, frame_orbit: Dictionary, tick: int) -> int:
	var pos := OrbitMath.position_at(orbit, tick)
	return OrbitMath.angle_of(OrbitMath.dot(pos, frame_orbit["q_q30"]), OrbitMath.dot(pos, frame_orbit["p_q30"]))


## How far an orbit turns in a number of ticks, as a binary angle.
static func turn_in(orbit: Dictionary, ticks: int) -> int:
	var period: int = orbit["period_subticks"]
	return OrbitMath.fraction_of_turn(posmod(ticks * OrbitMath.SUB_TICKS, period), period)


static func _hohmann(_ctx: SimContext, mine: Dictionary, theirs: Dictionary, gm: int, from_tick: int) -> Dictionary:
	var r1: int = mine["a_mm"]
	var r2: int = theirs["a_mm"]
	var a_t := (r1 + r2) / 2
	var ticks := maxi(1, (OrbitMath.period_sub(gm, a_t) + OrbitMath.SUB_TICKS) / (2 * OrbitMath.SUB_TICKS))
	# The target must lead by half a turn less what it moves during the flight.
	var needed := (OrbitMath.HALF_TURN - turn_in(theirs, ticks)) & OrbitMath.ANGLE_MASK
	var now := (angle_at(theirs, mine, from_tick) - angle_at(mine, mine, from_tick)) & OrbitMath.ANGLE_MASK
	var p_mine: int = mine["period_subticks"]
	var p_theirs: int = theirs["period_subticks"]
	# The phase changes at TURN (1/p_theirs - 1/p_mine) per sub-tick, so waiting for a gap of
	# `left` takes left * p_mine * p_theirs / (TURN * |p_mine - p_theirs|) sub-ticks.
	var left := (needed - now) & OrbitMath.ANGLE_MASK if p_theirs < p_mine \
		else (now - needed) & OrbitMath.ANGLE_MASK
	var partial := IntMath.mul_div(left, p_theirs, OrbitMath.SUB_TICKS * absi(p_mine - p_theirs))
	var wait := IntMath.mul_div_ceil(partial, p_mine, OrbitMath.TURN)
	return {
		"depart_tick": from_tick + wait, "ticks": ticks, "orbit_a_mm": a_t,
		"dv1_um_s": absi(OrbitMath.speed_um_s(gm, r1, a_t) - OrbitMath.speed_um_s(gm, r1, r1)),
		"dv2_um_s": absi(OrbitMath.speed_um_s(gm, r2, r2) - OrbitMath.speed_um_s(gm, r2, a_t)),
	}


## One or more turns of a phasing orbit that brings the unit back to where it left just as the
## target gets there, then a small change to the target's ring.
static func _phasing(_ctx: SimContext, mine: Dictionary, theirs: Dictionary, gm: int, from_tick: int) -> Dictionary:
	var r1: int = mine["a_mm"]
	var r2: int = theirs["a_mm"]
	var ahead := (angle_at(theirs, mine, from_tick) - angle_at(mine, mine, from_tick)) & OrbitMath.ANGLE_MASK
	var gap := mini(ahead, OrbitMath.TURN - ahead)
	var turns := maxi(1, IntMath.mul_div_ceil(gap, PHASING_STEP, OrbitMath.TURN))
	var period: int = mine["period_subticks"]
	# A target ahead is caught on a shorter, lower orbit; one behind waits on a longer, higher one.
	var change := IntMath.mul_div(period, gap, OrbitMath.TURN * turns)
	var phasing := period - change if ahead <= OrbitMath.HALF_TURN else period + change
	var a_p := _semi_major_for_period(r1, period, phasing)
	var ticks := maxi(1, (phasing * turns + OrbitMath.SUB_TICKS / 2) / OrbitMath.SUB_TICKS)
	var one_way := absi(OrbitMath.speed_um_s(gm, r1, a_p) - OrbitMath.speed_um_s(gm, r1, r1))
	var ring_change := absi(OrbitMath.speed_um_s(gm, r2, r2) - OrbitMath.speed_um_s(gm, r1, r1))
	return {
		"depart_tick": from_tick, "ticks": ticks, "orbit_a_mm": a_p,
		"dv1_um_s": one_way, "dv2_um_s": one_way + ring_change,
	}


## a * (new_period / period)^(2/3), by Kepler's third law, through the integer ln and exp.
static func _semi_major_for_period(a_mm: int, period: int, new_period: int) -> int:
	var log_ratio := OrbitMath.ln(new_period) - OrbitMath.ln(period)
	var scaled := OrbitMath.smul_div(log_ratio, 2, 3)
	var factor := OrbitMath.exp_q30(scaled) if scaled >= 0 else OrbitMath.exp_neg(-scaled)
	return OrbitMath.smul_div(a_mm, factor, OrbitMath.ONE)


## The orbit the unit rides from its departure tick: its own orbit's position there, with the speed
## that puts the far side of the orbit at the target's radius.
static func departure_orbit(ctx: SimContext, unit_id: int, quoted: Dictionary, tick: int) -> Dictionary:
	var mine := unit_orbit(ctx, unit_id)
	var gm: int = ctx.state["bodies"][mine["parent"]]["gm"]
	var now := OrbitMath.state_at(mine, gm, tick)
	var r: Array = now["r"]
	var v: Array = now["v"]
	var speed := IntMath.dist(v, [0, 0, 0])
	var wanted := OrbitMath.speed_um_s(gm, IntMath.dist(r, [0, 0, 0]), quoted["orbit_a_mm"])
	var scaled: Array[int] = []
	for axis in 3:
		scaled.append(OrbitMath.smul_div(v[axis], wanted, speed))
	var orbit := OrbitMath.from_state(r, scaled, gm, tick)
	if not orbit.is_empty():
		orbit["parent"] = mine["parent"]
	return orbit
