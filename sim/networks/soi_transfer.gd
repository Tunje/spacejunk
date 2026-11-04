class_name SoiTransfer
extends RefCounted
## Autopilot trips that change sphere of influence (orbital_flight.md section 11, task A18), as
## patched conics. Transfer.plan_from hands over a trip whose two orbits have different parents,
## one level apart: from an orbit around a body P out to one around its child C, or back.
##
## The trip is a list of legs, each an orbit and the tick it starts, ridden on rails:
## - Out: a Hohmann transfer around P timed to meet C. At C's sphere, a hyperbola around C shaped
##   to reach the target's radius at periapsis. A capture burn there onto that ring, then phasing to
##   the target.
## - Back: an escape hyperbola from the parking orbit, burned at the point that sends it out of C's
##   sphere along C's motion on the Hohmann window. Then the coast around P to the target's radius.
## Costs are the sum of the burns, by the rocket equation, which for one exhaust speed is exact.

const REASON_UNSUPPORTED := "unsupported_orbit"
## A planet's own orbit may be this eccentric, 0.1 in Q30. The ship's and target's must still be
## near-circular, as for Transfer.
const MAX_PLANET_E_Q30 := 107_374_182
## Coarse steps when searching for the tick a path enters a sphere.
const SEARCH_STEPS := 64
const ONE := OrbitMath.ONE
const UM_PER_MM := 1000


## The trip from orbit `mine` to orbit `theirs`, or { reason }.
static func plan(ctx: SimContext, unit_id: int, mine: Dictionary, theirs: Dictionary, target: int,
		mass_g: int, from_tick: int, found: Dictionary) -> Dictionary:
	var bodies: Dictionary = ctx.state["bodies"]
	var trip: Dictionary
	if _parent_of(bodies, theirs["parent"]) == mine["parent"]:
		trip = _outbound(ctx, mine, theirs, from_tick)
	elif _parent_of(bodies, mine["parent"]) == theirs["parent"]:
		trip = _return(ctx, mine, theirs, from_tick)
	else:
		return { "reason": REASON_UNSUPPORTED }
	if trip.has("reason"):
		return trip
	trip["kind"] = Transfer.KIND
	trip["target"] = target
	trip["ticks"] = trip["arrive_tick"] - trip["depart_tick"] + 1
	trip["cost_g"] = OrbitMath.burn_g(mass_g, trip["dv_um_s"], found["exhaust_mm_s"])
	return trip


static func _parent_of(bodies: Dictionary, body: int) -> int:
	var orbit: Dictionary = bodies.get(body, {}).get("orbit", {})
	return orbit.get("parent", 0)


static func _gm(ctx: SimContext, body: int) -> int:
	return ctx.state["bodies"][body]["gm"]


## Near-circular and in one plane with the child body's own orbit.
static func _fits(orbit: Dictionary, planet_orbit: Dictionary) -> bool:
	if orbit.get("hyperbolic", false) or planet_orbit.get("hyperbolic", false):
		return false
	if orbit["e_q30"] > Transfer.MAX_E_Q30 or planet_orbit["e_q30"] > MAX_PLANET_E_Q30:
		return false
	var normal := OrbitMath.cross(orbit["p_q30"], orbit["q_q30"])
	var planet_normal := OrbitMath.cross(planet_orbit["p_q30"], planet_orbit["q_q30"])
	return OrbitMath.dot(normal, planet_normal) >= Transfer.MIN_COPLANAR_Q30


static func _add(a: Array, b: Array, sign: int) -> Array[int]:
	return [int(a[0]) + sign * int(b[0]), int(a[1]) + sign * int(b[1]), int(a[2]) + sign * int(b[2])]


static func _scaled(v: Array, length: int) -> Array[int]:
	var direction := OrbitMath.unit(v)
	return [OrbitMath.smul_div(direction[0], length, ONE), OrbitMath.smul_div(direction[1], length, ONE),
		OrbitMath.smul_div(direction[2], length, ONE)]


## A leg: an orbit around a parent, from a tick.
static func _leg(orbit: Dictionary, parent: int, from_tick: int) -> Dictionary:
	orbit["parent"] = parent
	return { "orbit": orbit, "from_tick": from_tick }


## Ticks from a hyperbolic record's epoch to its periapsis.
static func _to_periapsis(orbit: Dictionary) -> int:
	return OrbitMath.smul_div(-int(orbit["m0_rad"]), 1 << (OrbitMath.MOTION_SHIFT - 30), orbit["motion_q60"])


# ------------------------------------------------------------------------------ out

static func _outbound(ctx: SimContext, mine: Dictionary, theirs: Dictionary, from_tick: int) -> Dictionary:
	var child: int = theirs["parent"]
	var parent: int = mine["parent"]
	var planet: Dictionary = ctx.state["bodies"][child]
	var planet_orbit: Dictionary = planet["orbit"]
	var soi: int = planet.get("soi_mm", 0)
	var ring: int = theirs["a_mm"]
	if soi <= 0 or ring >= soi or ring <= planet["radius_mm"] or not _fits(mine, planet_orbit) \
			or not _fits(theirs, planet_orbit):
		return { "reason": REASON_UNSUPPORTED }
	var gm_p := _gm(ctx, parent)
	var gm_c := _gm(ctx, child)
	var hohmann := Transfer._hohmann(ctx, mine, planet_orbit, gm_p, from_tick)
	var depart: int = hohmann["depart_tick"]
	# Leg 0: the Hohmann ellipse around the parent, from the ship's orbit at departure.
	var now := OrbitMath.state_at(mine, gm_p, depart)
	var wanted := OrbitMath.speed_um_s(gm_p, IntMath.dist(now["r"], [0, 0, 0]), hohmann["orbit_a_mm"])
	var outward := OrbitMath.from_state(now["r"], _scaled(now["v"], wanted), gm_p, depart)
	if outward.is_empty():
		return { "reason": REASON_UNSUPPORTED }
	var arrive_guess: int = depart + hohmann["ticks"] - 1
	var entry := _entry_tick(outward, planet_orbit, soi, depart, arrive_guess)
	if entry < 0:
		return { "reason": REASON_UNSUPPORTED }
	# Leg 1: a hyperbola around the child, keeping the speed at the sphere's edge but shaped so its
	# periapsis is the target's ring. The small change of direction stands for a correction burn.
	var ship := OrbitMath.state_at(outward, gm_p, entry)
	var body := OrbitMath.state_at(planet_orbit, gm_p, entry)
	var r_rel := _add(ship["r"], body["r"], -1)
	var v_rel := _add(ship["v"], body["v"], -1)
	var approach := _approach(r_rel, v_rel, gm_c, ring, planet_orbit)
	if approach.is_empty():
		return { "reason": REASON_UNSUPPORTED }
	var falling := OrbitMath.from_state(r_rel, approach, gm_c, entry)
	if not falling.get("hyperbolic", false):
		return { "reason": REASON_UNSUPPORTED }
	var periapsis := entry + maxi(1, _to_periapsis(falling))
	# Leg 2: capture onto a circle through the periapsis, then phasing to the target on that ring.
	var low := OrbitMath.state_at(falling, gm_c, periapsis)
	var r_low := IntMath.dist(low["r"], [0, 0, 0])
	var circle_speed := OrbitMath.speed_um_s(gm_c, r_low, r_low)
	var captured := OrbitMath.from_state(low["r"], _scaled(low["v"], circle_speed), gm_c, periapsis)
	if captured.is_empty():
		return { "reason": REASON_UNSUPPORTED }
	captured["parent"] = child
	var capture_dv := absi(IntMath.dist(low["v"], [0, 0, 0]) - circle_speed)
	var phase := Transfer._phasing(ctx, captured, theirs, gm_c, periapsis)
	var phasing_speed := OrbitMath.speed_um_s(gm_c, r_low, phase["orbit_a_mm"])
	var phasing := OrbitMath.from_state(low["r"], _scaled(low["v"], phasing_speed), gm_c, periapsis)
	if phasing.is_empty():
		return { "reason": REASON_UNSUPPORTED }
	return {
		"depart_tick": depart, "arrive_tick": periapsis + phase["ticks"] - 1,
		"dv_um_s": hohmann["dv1_um_s"] + capture_dv + phase["dv1_um_s"] + phase["dv2_um_s"],
		"legs": [_leg(outward, parent, depart), _leg(falling, child, entry), _leg(phasing, child, periapsis)],
	}


## The first tick the outward path is inside the sphere, by a coarse walk back from the expected
## arrival and then bisection, or -1 if it never gets there.
static func _entry_tick(path: Dictionary, planet_orbit: Dictionary, soi: int, start: int, end: int) -> int:
	var inside := func(t: int) -> bool:
		return IntMath.dist(OrbitMath.position_at(path, t), OrbitMath.position_at(planet_orbit, t)) < soi
	if not inside.call(end):
		return -1
	var step := maxi(1, (end - start) / SEARCH_STEPS)
	var hit := end
	var miss := hit - step
	while miss > start and inside.call(miss):
		hit = miss
		miss -= step
	miss = maxi(miss, start)
	while hit - miss > 1:
		var middle := (hit + miss) / 2
		if inside.call(middle):
			hit = middle
		else:
			miss = middle
	return hit


## A velocity at r_rel, inward, with the speed of v_rel, on the hyperbola around the child whose
## periapsis is `ring`. Worked in mm and mm/s, so every square stays inside 63 bits.
static func _approach(r_rel: Array, v_rel: Array, gm: int, ring: int, planet_orbit: Dictionary) -> Array:
	var r := IntMath.dist(r_rel, [0, 0, 0])
	var v_mm := IntMath.dist(v_rel, [0, 0, 0]) / UM_PER_MM
	var circular_sq := IntMath.mul_div(gm, OrbitMath.MM3_PER_GM_UNIT, r)
	var excess := v_mm * v_mm - 2 * circular_sq
	if excess <= 0:
		return []
	var a := IntMath.mul_div(gm, OrbitMath.MM3_PER_GM_UNIT, excess)
	var e := ONE + IntMath.mul_div(ring, ONE, a)
	var e2m1 := IntMath.mul_div(e, e, ONE) - ONE
	# Angular momentum squared over r^2: GM a (e^2 - 1) / r^2, the tangential speed squared at r.
	var tangential_sq := IntMath.mul_div(IntMath.mul_div(circular_sq, a, r), e2m1, ONE)
	var radial_sq := maxi(0, v_mm * v_mm - tangential_sq)
	var outward := OrbitMath.unit(r_rel)
	var normal := OrbitMath.unit(OrbitMath.cross(outward, OrbitMath.unit(v_rel)))
	if normal == [0, 0, 0]:
		normal = OrbitMath.unit(OrbitMath.cross(planet_orbit["p_q30"], planet_orbit["q_q30"]))
	var along := OrbitMath.cross(normal, outward)
	var tangential := IntMath.isqrt(tangential_sq) * UM_PER_MM
	var radial := IntMath.isqrt(radial_sq) * UM_PER_MM
	var velocity: Array[int] = []
	for axis in 3:
		velocity.append(OrbitMath.smul_div(along[axis], tangential, ONE) - OrbitMath.smul_div(outward[axis], radial, ONE))
	return velocity


# ------------------------------------------------------------------------------ back

static func _return(ctx: SimContext, mine: Dictionary, theirs: Dictionary, from_tick: int) -> Dictionary:
	var child: int = mine["parent"]
	var parent: int = theirs["parent"]
	var planet: Dictionary = ctx.state["bodies"][child]
	var planet_orbit: Dictionary = planet["orbit"]
	var soi: int = planet.get("soi_mm", 0)
	var r0: int = mine["a_mm"]
	if soi <= 0 or r0 >= soi or not _fits(mine, planet_orbit) or not _fits(theirs, planet_orbit):
		return { "reason": REASON_UNSUPPORTED }
	var gm_p := _gm(ctx, parent)
	var gm_c := _gm(ctx, child)
	var hohmann := Transfer._hohmann(ctx, planet_orbit, theirs, gm_p, from_tick)
	var window: int = hohmann["depart_tick"]
	var v_inf: int = hohmann["dv1_um_s"]
	var outward_bound: bool = theirs["a_mm"] > planet_orbit["a_mm"]
	# The escape hyperbola: speed at periapsis r0 for v_inf, and its shape.
	var v_inf_mm := v_inf / UM_PER_MM
	var circular_sq := IntMath.mul_div(gm_c, OrbitMath.MM3_PER_GM_UNIT, r0)
	var periapsis_speed := IntMath.isqrt(v_inf_mm * v_inf_mm + 2 * circular_sq) * UM_PER_MM
	var a := IntMath.mul_div(gm_c, OrbitMath.MM3_PER_GM_UNIT, maxi(1, v_inf_mm * v_inf_mm))
	var e := ONE + IntMath.mul_div(r0, ONE, a)
	var exit_ticks := _ticks_to_radius(gm_c, a, e, soi)
	# The asymptote must point along the planet's motion (or against it, going inward), so the
	# periapsis lies the asymptote's angle behind it, in the parking orbit's sense of motion.
	var body := OrbitMath.state_at(planet_orbit, gm_p, window)
	var asymptote := OrbitMath.unit(body["v"])
	if not outward_bound:
		asymptote = [-asymptote[0], -asymptote[1], -asymptote[2]]
	var normal := OrbitMath.unit(OrbitMath.cross(mine["p_q30"], mine["q_q30"]))
	var inverse := OrbitMath.smul_div(ONE, ONE, e)
	var spread := OrbitMath.angle_of(OrbitMath.smul_div(OrbitMath.sqrt_e2_minus_1(e), ONE, e), -inverse)
	var sc := OrbitMath.sin_cos(spread)
	var side := OrbitMath.cross(normal, asymptote)
	var periapsis_dir: Array[int] = []
	for axis in 3:
		periapsis_dir.append(OrbitMath.smul_div(asymptote[axis], sc[1], ONE) - OrbitMath.smul_div(side[axis], sc[0], ONE))
	# Burn when the ship passes that direction, as close as it comes to window - exit_ticks.
	var wanted := OrbitMath.angle_of(OrbitMath.dot(periapsis_dir, mine["q_q30"]), OrbitMath.dot(periapsis_dir, mine["p_q30"]))
	var period_ticks: int = mine["period_subticks"] / OrbitMath.SUB_TICKS
	var start := maxi(from_tick, window - exit_ticks - period_ticks / 2)
	var gap := (wanted - Transfer.angle_at(mine, mine, start)) & OrbitMath.ANGLE_MASK
	# TURN * SUB_TICKS is 2^64, so divide in two steps.
	var burn := start + IntMath.mul_div(gap, mine["period_subticks"], OrbitMath.TURN) / OrbitMath.SUB_TICKS
	var here := OrbitMath.state_at(mine, gm_c, burn)
	var leaving := OrbitMath.from_state(here["r"], _scaled(here["v"], periapsis_speed), gm_c, burn)
	if not leaving.get("hyperbolic", false):
		return { "reason": REASON_UNSUPPORTED }
	var exit := burn + exit_ticks
	var ship := OrbitMath.state_at(leaving, gm_c, exit)
	var carrier := OrbitMath.state_at(planet_orbit, gm_p, exit)
	# At the sphere's edge, a small correction sets the speed so the coast's far side is exactly the
	# target's radius. The exit is close to tangential, so this barely turns the path.
	var r_exit := _add(ship["r"], carrier["r"], 1)
	var v_exit := _add(ship["v"], carrier["v"], 1)
	var r_exit_mm := IntMath.dist(r_exit, [0, 0, 0])
	var coast_a: int = (r_exit_mm + theirs["a_mm"]) / 2
	var coast_speed := OrbitMath.speed_um_s(gm_p, r_exit_mm, coast_a)
	var correction := absi(IntMath.dist(v_exit, [0, 0, 0]) - coast_speed)
	var coasting := OrbitMath.from_state(r_exit, _scaled(v_exit, coast_speed), gm_p, exit)
	if coasting.is_empty():
		return { "reason": REASON_UNSUPPORTED }
	var escape_dv := periapsis_speed - OrbitMath.speed_um_s(gm_c, r0, r0) + correction
	# The escape burn waits for the ship to come round its parking orbit, so the exit can be up to
	# half that orbit off the window. Rather than arrive beside a target that has moved on, it
	# circles at the target's ring where the coast ends and phases round to it, as the way out does.
	var reach: int = exit + OrbitMath.period_sub(gm_p, coast_a) / (2 * OrbitMath.SUB_TICKS)
	var end := OrbitMath.state_at(coasting, gm_p, reach)
	var r_end := IntMath.dist(end["r"], [0, 0, 0])
	var circle_speed := OrbitMath.speed_um_s(gm_p, r_end, r_end)
	var circle := OrbitMath.from_state(end["r"], _scaled(end["v"], circle_speed), gm_p, reach)
	if circle.is_empty():
		return { "reason": REASON_UNSUPPORTED }
	circle["parent"] = parent
	var arrive_dv := absi(IntMath.dist(end["v"], [0, 0, 0]) - circle_speed)
	var phase := Transfer._phasing(ctx, circle, theirs, gm_p, reach)
	var phasing_speed := OrbitMath.speed_um_s(gm_p, r_end, phase["orbit_a_mm"])
	var phasing := OrbitMath.from_state(end["r"], _scaled(end["v"], phasing_speed), gm_p, reach)
	if phasing.is_empty():
		return { "reason": REASON_UNSUPPORTED }
	return {
		"depart_tick": burn, "arrive_tick": reach + phase["ticks"] - 1,
		"dv_um_s": escape_dv + arrive_dv + phase["dv1_um_s"] + phase["dv2_um_s"],
		"legs": [_leg(leaving, child, burn), _leg(coasting, parent, exit), _leg(phasing, parent, reach)],
	}


## Ticks from periapsis to radius r on a hyperbola with semi-axis a and eccentricity e:
## cosh H = (r / a + 1) / e, then Kepler's equation for the time.
static func _ticks_to_radius(gm: int, a: int, e: int, r: int) -> int:
	var cosh_h := IntMath.mul_div(IntMath.mul_div(r + a, ONE, a), ONE, e)
	if cosh_h <= ONE:
		return 1
	var sinh_h := OrbitMath.sqrt_e2_minus_1(cosh_h)
	var big_h := OrbitMath.ln(cosh_h + sinh_h) - 30 * OrbitMath.LN2
	var m := OrbitMath.smul_div(e, sinh_h, ONE) - big_h
	var speed := OrbitMath.circular_speed(gm, a)
	var motion := OrbitMath.smul_div(speed[0], 1 << (OrbitMath.MOTION_SHIFT - speed[1]), a * Sim.TICKS_PER_SECOND)
	return maxi(1, OrbitMath.smul_div(m, 1 << (OrbitMath.MOTION_SHIFT - 30), motion))
