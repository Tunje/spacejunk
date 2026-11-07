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
## How a move_to or quote picks between two ways to fly a trip (A43).
const PREFER_CHEAP := "cheap"
const PREFER_FAST := "fast"
const PREFERENCES := [PREFER_CHEAP, PREFER_FAST]
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
static func plan(ctx: SimContext, unit_id: int, target: int, from_tick: int, prefer: String = PREFER_CHEAP,
		compare: bool = false) -> Dictionary:
	return plan_from(ctx, unit_id, unit_orbit(ctx, unit_id), target,
		Units.unit_mass(ctx.state, ctx.defs, unit_id), from_tick, prefer, compare)


## As plan, from any orbit at any mass, for pricing a leg the unit has not reached yet.
static func plan_from(ctx: SimContext, unit_id: int, mine: Dictionary, target: int, mass_g: int,
		from_tick: int, prefer: String = PREFER_CHEAP, compare: bool = false) -> Dictionary:
	return plan_between(ctx, unit_id, mine, target_orbit(ctx, target), target, mass_g, from_tick, prefer, compare)


## As plan_from, onto a given orbit, such as a frame's, which `target` only names (A39).
## - Between planes there are two ways to fly it (A41b), and `prefer` picks, as _better says:
##   PREFER_CHEAP the lower cost and PREFER_FAST the earlier arrival (A43).
## - In one plane, PREFER_CHEAP is the window's plan and never searches a Lambert arc. PREFER_FAST
##   also plans the arc that leaves at once, and takes the earlier arrival (A47).
## - `compare` plans the arc for a cheap trip too, only to show it. It is opt-in, since the arc's
##   search costs about a hundred times the window's; cores and cycles never set it.
## The plan not taken is summarised in `other` as { arrive_tick, cost_g }, with `timed: true` when
## it is the arc.
static func plan_between(ctx: SimContext, unit_id: int, mine: Dictionary, theirs: Dictionary, target: int,
		mass_g: int, from_tick: int, prefer: String = PREFER_CHEAP, compare: bool = false) -> Dictionary:
	if mine.is_empty() or theirs.is_empty():
		return { "reason": REASON_UNSUPPORTED }
	var found := BurnSystem.thruster(ctx, unit_id)
	if found.is_empty():
		return { "reason": REASON_NO_THRUSTER }
	if mine["parent"] != theirs["parent"]:
		var crossing := SoiTransfer.plan(ctx, unit_id, mine, theirs, target, mass_g, from_tick, found)
		if not crossing.has("reason"):
			crossing["plane_change_dv_um_s"] = 0
			crossing["plane_change_at"] = ""
		return crossing
	if not _near_circular(mine, theirs):
		return { "reason": REASON_UNSUPPORTED }
	var gm: int = ctx.state["bodies"][mine["parent"]]["gm"]
	if not _coplanar(mine, theirs):
		# Both ways of changing plane are planned, and `prefer` picks one (A41b, A43).
		var low := _plane_change_plan(mine, theirs, target, gm, mass_g, from_tick, found)
		var high := _combined_plan(mine, theirs, target, gm, mass_g, from_tick, found)
		if high.has("reason"):
			return low
		if low.has("reason"):
			return high
		var take_low := _better(low, high, prefer)
		var chosen := low if take_low else high
		var other := high if take_low else low
		chosen["other"] = { "arrive_tick": other["arrive_tick"], "cost_g": other["cost_g"] }
		return chosen
	var plan := _coplanar_plan(mine, theirs, target, gm, mass_g, from_tick, found)
	plan["plane_change_dv_um_s"] = 0
	plan["plane_change_at"] = ""
	# The arc that leaves at once is only planned when it can be chosen or is asked for (A47).
	if prefer != PREFER_FAST and not compare:
		return plan
	var timed := _timed_plan(mine, theirs, target, gm, mass_g, from_tick, found, ctx.state["bodies"][mine["parent"]],
		int(plan["arrive_tick"]))
	if timed.has("reason"):
		return plan
	# Fast takes the earlier arrival, ties to the lower cost; cheap keeps the window's plan.
	var take_window := prefer != PREFER_FAST or _better(plan, timed, PREFER_FAST)
	var chosen := plan if take_window else timed
	var other := timed if take_window else plan
	chosen["other"] = { "arrive_tick": other["arrive_tick"], "cost_g": other["cost_g"] }
	if other.get("timed", false):
		chosen["other"]["timed"] = true
	return chosen


## Flight times the timed plan tries, in eighths of the Hohmann transfer's (A47).
const TIMED_EIGHTHS := [4, 5, 6, 7, 9, 10, 12, 14, 16]


## A trip that leaves at from_tick instead of waiting for a window (A47): a Lambert arc from where
## the unit is to where the target will be, for each flight time in TIMED_EIGHTHS of the Hohmann
## transfer's, keeping the cheapest. An arc must be elliptic, stay above the height where low flight
## starts and inside the parent's sphere. The burns are the exact velocity differences at each end.
## Only arcs that arrive before `window_arrive`, the window plan's arrival, are tried, since leaving
## at once is for arriving sooner; with the window under an eighth of a Hohmann time away there are
## none worth the search. Each flight time starts from the last one's answer.
static func _timed_plan(mine: Dictionary, theirs: Dictionary, target: int, gm: int, mass_g: int,
		from_tick: int, found: Dictionary, parent: Dictionary, window_arrive: int) -> Dictionary:
	var now := OrbitMath.state_at(mine, gm, from_tick)
	var r1: Array = now["r"]
	var r1_mm := IntMath.dist(r1, [0, 0, 0])
	var r2_mm: int = theirs["a_mm"]
	var a_hohmann := (r1_mm + r2_mm) / 2
	var hohmann_ticks := maxi(1, OrbitMath.period_sub(gm, a_hohmann) / (2 * OrbitMath.SUB_TICKS))
	var normal := OrbitMath.unit(OrbitMath.cross(mine["p_q30"], mine["q_q30"]))
	var radial := OrbitMath.unit(r1)
	var along := OrbitMath.unit(OrbitMath.cross(normal, radial))
	var floor_mm: int = int(parent["radius_mm"]) + LowFlight.LEAVE_MM
	var soi: int = parent.get("soi_mm", 0)
	var best := {}
	if window_arrive - from_tick - hohmann_ticks < hohmann_ticks / 8:
		return { "reason": REASON_UNSUPPORTED }
	var speed := OrbitMath.speed_um_s(gm, r1_mm, a_hohmann)
	var guess: Array[int] = []
	for axis in 3:
		guess.append(OrbitMath.smul_div(along[axis], speed, OrbitMath.ONE))
	for eighths: int in TIMED_EIGHTHS:
		var ticks: int = maxi(2, hohmann_ticks * eighths / 8)
		var arrive := from_tick + ticks
		if arrive >= window_arrive:
			break
		var hit := Lambert.solve(gm, r1, guess, theirs, from_tick, arrive, normal)
		if hit.is_empty():
			continue
		guess = hit["v"]
		var arc: Dictionary = hit["orbit"]
		if arc.get("hyperbolic", false) or CoastBounds.periapsis_mm(arc) < floor_mm \
				or (soi > 0 and BurnSystem.apoapsis_mm(arc) >= soi):
			continue
		var dv1 := IntMath.dist(hit["v"], now["v"])
		var dv2 := IntMath.dist(OrbitMath.state_at(theirs, gm, arrive)["v"], OrbitMath.state_at(arc, gm, arrive)["v"])
		var first_g := OrbitMath.burn_g(mass_g, dv1, found["exhaust_mm_s"])
		var cost := first_g + OrbitMath.burn_g(mass_g - first_g, dv2, found["exhaust_mm_s"])
		if best.is_empty() or cost < int(best["cost_g"]):
			arc["parent"] = mine["parent"]
			best = {
				"kind": KIND, "target": target, "depart_tick": from_tick, "arrive_tick": arrive, "ticks": ticks + 1,
				"cost_g": cost, "dv_um_s": dv1 + dv2, "orbit_a_mm": arc["a_mm"], "plane_change_dv_um_s": 0,
				"plane_change_at": "", "timed": true, "legs": [{ "orbit": arc, "from_tick": from_tick }],
			}
	return best if not best.is_empty() else { "reason": REASON_UNSUPPORTED }


## A trip between near-circular orbits in one plane round one parent: a Hohmann transfer, or a
## phasing orbit on one ring.
static func _coplanar_plan(mine: Dictionary, theirs: Dictionary, target: int, gm: int, mass_g: int,
		from_tick: int, found: Dictionary) -> Dictionary:
	var r1: int = mine["a_mm"]
	var r2: int = theirs["a_mm"]
	var leg: Dictionary
	if absi(r2 - r1) * SAME_RING_DIVISOR <= r1:
		leg = _phasing(null, mine, theirs, gm, from_tick)
	else:
		leg = _hohmann(null, mine, theirs, gm, from_tick)
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


## Whether plan `a`, A41a's, is to be taken over `b`, A41b's. PREFER_CHEAP takes the lower cost,
## ties to `a` (A41b). PREFER_FAST takes the earlier arrival, ties to the lower cost, then `a` (A43).
static func _better(a: Dictionary, b: Dictionary, prefer: String) -> bool:
	if prefer == PREFER_FAST and int(a["arrive_tick"]) != int(b["arrive_tick"]):
		return int(a["arrive_tick"]) < int(b["arrive_tick"])
	return int(a["cost_g"]) <= int(b["cost_g"])


static func _compatible(mine: Dictionary, theirs: Dictionary) -> bool:
	return mine["parent"] == theirs["parent"] and _near_circular(mine, theirs) and _coplanar(mine, theirs)


static func _near_circular(mine: Dictionary, theirs: Dictionary) -> bool:
	if mine.get("hyperbolic", false) or theirs.get("hyperbolic", false):
		return false
	return mine["e_q30"] <= MAX_E_Q30 and theirs["e_q30"] <= MAX_E_Q30


static func _coplanar(mine: Dictionary, theirs: Dictionary) -> bool:
	var normal_mine := OrbitMath.cross(mine["p_q30"], mine["q_q30"])
	var normal_theirs := OrbitMath.cross(theirs["p_q30"], theirs["q_q30"])
	return OrbitMath.dot(normal_mine, normal_theirs) >= MIN_COPLANAR_Q30


## A trip between near-circular orbits round one parent in planes more than a degree apart (A41):
## ride the unit's orbit to where it next crosses the target's plane, burn onto the circle in that
## plane through the point, then the coplanar trip from there, all as legs. The point is the
## unit's position on the node tick moved into the plane, at most one tick's motion off it, so the
## leg starts up to a few metres from where the unit was. Every burn is in the price.
static func _plane_change_plan(mine: Dictionary, theirs: Dictionary, target: int, gm: int, mass_g: int,
		from_tick: int, found: Dictionary) -> Dictionary:
	var normal := OrbitMath.unit(OrbitMath.cross(theirs["p_q30"], theirs["q_q30"]))
	var node := node_tick(mine, normal, from_tick)
	if node < 0:
		return { "reason": REASON_UNSUPPORTED }
	var now := OrbitMath.state_at(mine, gm, node)
	var ring := _ring_through(now["r"], normal, gm, mine["parent"], node)
	var circle: Dictionary = ring[0]
	var change := IntMath.dist(now["v"], ring[1])
	var change_g := OrbitMath.burn_g(mass_g, change, found["exhaust_mm_s"])
	var rest := _coplanar_plan(circle, theirs, target, gm, mass_g - change_g, node + 1, found)
	var ellipse := launch_orbit(circle, gm, rest["orbit_a_mm"], rest["depart_tick"])
	if ellipse.is_empty():
		return { "reason": REASON_UNSUPPORTED }
	return {
		"kind": KIND, "target": target, "depart_tick": node, "arrive_tick": rest["arrive_tick"],
		"ticks": rest["arrive_tick"] - node + 1, "cost_g": change_g + rest["cost_g"],
		"dv_um_s": change + rest["dv_um_s"], "orbit_a_mm": rest["orbit_a_mm"],
		"plane_change_dv_um_s": change, "plane_change_at": "start",
		"legs": [{ "orbit": circle, "from_tick": node }, { "orbit": ellipse, "from_tick": rest["depart_tick"] }],
	}


## [the circle round the parent in the plane with this normal through point r moved into it, the
## circle's velocity there]: the point is at most a tick's motion off the plane, so the circle starts
## up to a few metres from it (A41a, A41b).
static func _ring_through(r: Array, normal: Array, gm: int, parent: int, tick: int) -> Array:
	var off := OrbitMath.dot(r, normal)
	var flat: Array[int] = []
	for axis in 3:
		flat.append(int(r[axis]) - OrbitMath.smul_div(normal[axis], off, OrbitMath.ONE))
	var radius := IntMath.dist(flat, [0, 0, 0])
	var p := OrbitMath.unit(flat)
	var q := OrbitMath.unit(OrbitMath.cross(normal, p))
	var circle := OrbitMath.make_orbit(gm, radius, 0, p, q, 0, tick)
	circle["parent"] = parent
	var speed := OrbitMath.speed_um_s(gm, radius, radius)
	var velocity: Array[int] = []
	for axis in 3:
		velocity.append(OrbitMath.smul_div(q[axis], speed, OrbitMath.ONE))
	return [circle, velocity]


## The cheaper way to change plane when the radius changes too (A41b): leave on the node on a
## Hohmann half-ellipse, so its far end is on the other node, and make the plane change at the high
## end, where the speed is lowest. Going up it joins the far burn, onto the target's ring; going down
## it joins the departure burn. The unit then sits on the target's ring at the far node at whatever
## phase, so a phasing orbit on that ring brings it to the target. Each burn is the exact difference
## of velocities, and every burn is in the price.
static func _combined_plan(mine: Dictionary, theirs: Dictionary, target: int, gm: int, mass_g: int,
		from_tick: int, found: Dictionary) -> Dictionary:
	var normal := OrbitMath.unit(OrbitMath.cross(theirs["p_q30"], theirs["q_q30"]))
	var node := node_tick(mine, normal, from_tick)
	if node < 0:
		return { "reason": REASON_UNSUPPORTED }
	var parent: int = mine["parent"]
	var now := OrbitMath.state_at(mine, gm, node)
	var r1 := IntMath.dist(now["r"], [0, 0, 0])
	var r2: int = theirs["a_mm"]
	var a_t := (r1 + r2) / 2
	var going_up := r2 > r1
	var ellipse: Dictionary
	var first_dv: int
	var at := "arrival" if going_up else "departure"
	var coplanar_first := absi(OrbitMath.speed_um_s(gm, r1, a_t) - OrbitMath.speed_um_s(gm, r1, r1))
	if going_up:
		ellipse = launch_orbit(mine, gm, a_t, node)
		first_dv = coplanar_first
	else:
		# The departure burn turns into the target's plane too: the ellipse leaves from the point
		# moved into the plane, along the ring's direction there, at the ellipse's speed.
		var ring := _ring_through(now["r"], normal, gm, parent, node)
		var circle: Dictionary = ring[0]
		var start := OrbitMath.position_at(circle, node)
		var speed := OrbitMath.speed_um_s(gm, int(circle["a_mm"]), a_t)
		var along: Array[int] = []
		for axis in 3:
			along.append(OrbitMath.smul_div(circle["q_q30"][axis], speed, OrbitMath.ONE))
		ellipse = OrbitMath.from_state(start, along, gm, node)
		first_dv = IntMath.dist(now["v"], along)
	if ellipse.is_empty():
		return { "reason": REASON_UNSUPPORTED }
	ellipse["parent"] = parent
	var half := maxi(1, (OrbitMath.period_sub(gm, a_t) + OrbitMath.SUB_TICKS) / (2 * OrbitMath.SUB_TICKS))
	var arrive := node + half
	var there := OrbitMath.state_at(ellipse, gm, arrive)
	var ring := _ring_through(there["r"], normal, gm, parent, arrive)
	var on_ring: Dictionary = ring[0]
	var second_dv := IntMath.dist(there["v"], ring[1])
	var coplanar_second := absi(OrbitMath.speed_um_s(gm, r2, r2) - OrbitMath.speed_um_s(gm, r2, a_t))
	var phase := _phasing(null, on_ring, theirs, gm, arrive + 1)
	var phasing := launch_orbit(on_ring, gm, phase["orbit_a_mm"], phase["depart_tick"])
	if phasing.is_empty():
		return { "reason": REASON_UNSUPPORTED }
	var burns: Array[int] = [first_dv, second_dv, phase["dv1_um_s"], phase["dv2_um_s"]]
	var mass := mass_g
	var cost := 0
	var dv := 0
	for burn: int in burns:
		var grams := OrbitMath.burn_g(mass, burn, found["exhaust_mm_s"])
		cost += grams
		mass -= grams
		dv += burn
	var extra := (second_dv - coplanar_second) if going_up else (first_dv - coplanar_first)
	var arrive_tick: int = phase["depart_tick"] + phase["ticks"] - 1
	return {
		"kind": KIND, "target": target, "depart_tick": node, "arrive_tick": arrive_tick,
		"ticks": arrive_tick - node + 1, "cost_g": cost, "dv_um_s": dv, "orbit_a_mm": a_t,
		"plane_change_dv_um_s": maxi(0, extra), "plane_change_at": at,
		"legs": [{ "orbit": ellipse, "from_tick": node }, { "orbit": on_ring, "from_tick": arrive },
			{ "orbit": phasing, "from_tick": phase["depart_tick"] }],
	}


## The first tick at or after from_tick on which an orbit has crossed the plane with this normal
## since the tick before, or -1 if it never does within two turns. A coarse walk, a 64th of a turn
## at a time so it can't step over a crossing, then bisection.
static func node_tick(orbit: Dictionary, normal: Array, from_tick: int) -> int:
	var before := _above(orbit, normal, from_tick - 1)
	var step := maxi(1, int(orbit["period_subticks"]) / OrbitMath.SUB_TICKS / 64)
	var low := from_tick - 1
	var high := from_tick
	var limit := from_tick + 128 * step
	while _above(orbit, normal, high) == before:
		if high > limit:
			return -1
		low = high
		high += step
	while high - low > 1:
		var mid := (low + high) / 2
		if _above(orbit, normal, mid) == before:
			low = mid
		else:
			high = mid
	return high


static func _above(orbit: Dictionary, normal: Array, tick: int) -> bool:
	return OrbitMath.dot(OrbitMath.position_at(orbit, tick), normal) >= 0


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
	if mine.is_empty():
		return {}
	return launch_orbit(mine, ctx.state["bodies"][mine["parent"]]["gm"], quoted["orbit_a_mm"], tick)


## The orbit from a point on `mine` at a tick, with the speed there scaled for semi-major axis a_mm.
static func launch_orbit(mine: Dictionary, gm: int, a_mm: int, tick: int) -> Dictionary:
	var now := OrbitMath.state_at(mine, gm, tick)
	var r: Array = now["r"]
	var v: Array = now["v"]
	var speed := IntMath.dist(v, [0, 0, 0])
	var wanted := OrbitMath.speed_um_s(gm, IntMath.dist(r, [0, 0, 0]), a_mm)
	var scaled: Array[int] = []
	for axis in 3:
		scaled.append(OrbitMath.smul_div(v[axis], wanted, speed))
	var orbit := OrbitMath.from_state(r, scaled, gm, tick)
	if not orbit.is_empty():
		orbit["parent"] = mine["parent"]
	return orbit
