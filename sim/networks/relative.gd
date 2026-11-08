class_name Relative
extends RefCounted
## Relative state between a unit and a target (real_orbits.md sections 3.2 and 3.5, task A54): the
## readouts a player flies a rendezvous by. Everything is exact integers from the same paths the
## simulation moves things on, so no frame or approximation comes in beyond theirs.
##
## A path ("track") is one of:
## - rails: orbit segments, each from a tick on. A unit's own orbit, then its transfer's legs, or
##   the orbits its planned burns would give, flown tick by tick.
## - line: a point moving in a straight line in a place (a frame, a body, or the root of
##   everything). A unit drifting in a frame, a rock in a frame, a landed unit, the old world.
##   Landed units are fixed to the body because no body rotates yet (real_orbits.md section 7,
##   planet rotation); when bodies spin, a landed unit's track gains the body's turn.
## - route: today's straight-line trip inside a frame.
## - low: low flight, known only now and stepped tick by tick with the flight's own integrator.
##
## Two tracks are compared in their nearest shared place: the lowest body or frame both are inside.
## Places above it add the same integers to both, so leaving them out changes nothing.

const REASON_UNKNOWN_UNIT := "unknown_unit"
const REASON_INVALID := "invalid_target"
## Range samples over a closest-approach horizon on rails, before refining each dip.
const CLOSEST_SAMPLES := 256
## Low flight is stepped every tick, so its closest-approach horizon is capped here.
const MAX_STEPPED_TICKS := 20_000
## Placeholder capture limits until the port data carries them (A54; B adds capture_range_m and
## capture_speed_m_s to the port capability). Readouts only until stage 4 enforces them.
const DEFAULT_CAPTURE_RANGE_MM := 2_000
const DEFAULT_CAPTURE_SPEED_UM_S := 200_000
const MDEG_PER_TURN := 360_000
const FAR_PAST := -(1 << 60)
const UM_PER_MM := 1000


## The relative state of `target` seen from `unit` at from_tick, with closest approach over the
## horizon (0 for one turn of the unit's orbit), as contracts section 3 gives it.
static func query(ctx: SimContext, unit_id: int, target: int, from_tick: int, horizon_ticks: int) -> Dictionary:
	if not ctx.state["units"].has(unit_id):
		return { "reason": REASON_UNKNOWN_UNIT }
	if target == unit_id or not (ctx.state["units"].has(target) or ctx.state["bodies"].has(target)):
		return { "reason": REASON_INVALID }
	var mine := unit_track(ctx, unit_id)
	var theirs := thing_track(ctx, target)
	var tick := maxi(from_tick, int(ctx.state["tick"])) if _is_low(mine) or _is_low(theirs) else from_tick
	var now := state_between(ctx, mine, theirs, tick)
	var result := now.duplicate()
	result["tick"] = tick
	var horizon := horizon_ticks if horizon_ticks > 0 else _default_horizon(ctx, unit_id)
	result["closest"] = closest(ctx, mine, theirs, tick, horizon)
	result["closest_planned"] = {}
	var unit: Dictionary = ctx.state["units"][unit_id]
	if not unit["burns"].is_empty() or not unit["burn"].is_empty():
		var planned := planned_track(ctx, unit_id, [])
		if not planned.is_empty():
			result["closest_planned"] = closest(ctx, planned["track"], theirs, tick, horizon)
	var orbits := _orbits(ctx, unit_id, target)
	result["plane"] = _plane(orbits, tick)
	result["phase_mdeg"] = _phase(orbits, tick)
	result["window"] = _window(ctx, orbits, tick)
	result["stop"] = _stop(ctx, unit_id, int(now["speed_um_s"]))
	result["dock"] = _dock(ctx, unit_id, target, now)
	return result


# ------------------------------------------------------------------------------ tracks

## The track a unit moves on now, ignoring planned burns. A docked unit moves as its host.
static func unit_track(ctx: SimContext, unit_id: int) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var now: int = ctx.state["tick"]
	if not unit["dock"].is_empty():
		return unit_track(ctx, unit["dock"]["target_unit"])
	if unit["low_flight"] != 0:
		return { "kind": "low", "body": unit["low_flight"], "pos": unit["pos_mm"].duplicate(),
			"vel": unit["vel_um_s"].duplicate(), "carry": unit["drift_carry"].duplicate(), "tick": now }
	if not unit["landed"].is_empty():
		return _line(unit["landed"]["body"], unit["pos_mm"], [0, 0, 0], now)
	if not unit["orbit"].is_empty():
		var segments: Array = [[FAR_PAST, unit["orbit"]]]
		for leg: Dictionary in unit["transfer"].get("legs", []):
			segments.append([int(leg["from_tick"]), leg["orbit"]])
		return { "kind": "rails", "segments": segments }
	if not unit["route"].is_empty():
		var route: Dictionary = unit["route"]
		return { "kind": "route", "place": unit["frame"], "from": route["from_mm"], "to": route["to_mm"],
			"length": route["length_mm"], "speed": route["speed_mm_s"], "progress": route["progress_mm"],
			"tick": now }
	return _line(unit["frame"], unit["pos_mm"], unit["vel_um_s"], now)


## The track of a unit or a body.
static func thing_track(ctx: SimContext, id: int) -> Dictionary:
	if ctx.state["units"].has(id):
		return unit_track(ctx, id)
	var body: Dictionary = ctx.state["bodies"][id]
	if not body["orbit"].is_empty():
		return { "kind": "rails", "segments": [[FAR_PAST, body["orbit"]]] }
	return _line(body["frame"], body["pos_mm"], [0, 0, 0], ctx.state["tick"])


## The unit's path with its planned burns (and the one running) flown tick by tick through the
## burn's own steps, plus `extra` burns not yet placed, as { track, burns: [{ id, start_tick,
## end_tick }] }. {} unless the unit is on an orbit with no transfer.
static func planned_track(ctx: SimContext, unit_id: int, extra: Array) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][unit_id]
	if not unit["dock"].is_empty() or unit["orbit"].is_empty() or not unit["transfer"].is_empty():
		return {}
	var burns: Array = unit["burns"].duplicate(true)
	burns.append_array(extra)
	burns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["tick"] < b["tick"] or (a["tick"] == b["tick"] and a.get("id", 0) < b.get("id", 0)))
	return fly(ctx, unit_id, burns)


## Flies a unit's running burn, then `burns` in order, from its orbit now, as the simulation would:
## each starts at its tick or the tick after the one before ends, fixes its direction from the orbit
## at its start, and thrusts thrust / mass each tick until done or out of propellant. Power is
## assumed throughout, as check assumes. A burn longer than BurnSystem.MAX_PREVIEW_TICKS is flown
## as one impulse, as check previews it.
static func fly(ctx: SimContext, unit_id: int, burns: Array) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var found := BurnSystem.thruster(ctx, unit_id)
	var orbit: Dictionary = unit["orbit"]
	var segments: Array = [[FAR_PAST, orbit]]
	var flown: Array = []
	var mass_g := Units.unit_mass(ctx.state, ctx.defs, unit_id)
	var left_g := Reservations.free_stock(ctx, unit_id, Travel.PROPELLANT)
	var tick: int = int(ctx.state["tick"]) + 1
	var queue: Array = []
	if not unit["burn"].is_empty():
		var running: Dictionary = unit["burn"]
		queue.append({ "id": running["id"], "start": tick, "dir": running["dir_q30"], "dv": running["dv_um_s"],
			"done": running["done_um_s"], "dv_remainder": running["dv_remainder"],
			"flow_remainder": running["flow_remainder"], "held": running["held_um_s"], "running": true })
	for planned: Dictionary in burns:
		queue.append(planned)
	if found.is_empty():
		return { "track": { "kind": "rails", "segments": segments }, "burns": flown }
	var stats: Dictionary = Units.module_of(ctx.state, ctx.defs, found["part"])["capabilities"][BurnSystem.CAPABILITY]
	for entry: Dictionary in queue:
		var start: int = entry["start"] if entry.has("running") else maxi(int(entry["tick"]), tick)
		var burn := { "dv_um_s": 0, "done_um_s": entry.get("done", 0), "dv_remainder": entry.get("dv_remainder", 0),
			"flow_remainder": entry.get("flow_remainder", 0) }
		var direction: Array = entry.get("dir", [])
		if not entry.has("running"):
			var vector := _vector_on(ctx, orbit, entry, start)
			burn["dv_um_s"] = IntMath.dist(vector, [0, 0, 0])
			direction = OrbitMath.unit(vector)
		else:
			burn["dv_um_s"] = entry["dv"]
		var held: Array = entry.get("held", [0, 0, 0])
		var ticks_needed := IntMath.mul_div_ceil(int(burn["dv_um_s"]) - int(burn["done_um_s"]),
			mass_g * Sim.TICKS_PER_SECOND, int(found["thrust_n"]) * 1_000_000_000)
		var t := start
		if ticks_needed > BurnSystem.MAX_PREVIEW_TICKS:
			var change: Array[int] = []
			var rest: int = int(burn["dv_um_s"]) - int(burn["done_um_s"])
			for axis in 3:
				change.append(OrbitMath.smul_div(direction[axis], rest, OrbitMath.ONE))
			var result := BurnSystem._apply(ctx, orbit, t, change, held)
			if result.is_empty():
				break
			orbit = result["orbit"]
			segments.append([t + 1, orbit])
			var grams := OrbitMath.burn_g(mass_g, rest, found["exhaust_mm_s"])
			mass_g -= grams
			left_g -= grams
			flown.append({ "id": entry.get("id", 0), "start_tick": t, "end_tick": t })
			tick = t + 1
			continue
		while burn["done_um_s"] < burn["dv_um_s"]:
			var step := BurnSystem._step(stats, mass_g, burn)
			if int(step["grams"]) > left_g:
				break
			var change: Array[int] = []
			for axis in 3:
				change.append(OrbitMath.smul_div(direction[axis], step["dv_um_s"], OrbitMath.ONE))
			var result := BurnSystem._apply(ctx, orbit, t, change, held)
			if result.is_empty():
				break
			if result["orbit"] != orbit:
				orbit = result["orbit"]
				segments.append([t + 1, orbit])
			held = result["held"]
			burn["dv_remainder"] = step["dv_remainder"]
			burn["flow_remainder"] = step["flow_remainder"]
			burn["done_um_s"] += step["dv_um_s"]
			mass_g -= int(step["grams"])
			left_g -= int(step["grams"])
			t += 1
		flown.append({ "id": entry.get("id", 0), "start_tick": start, "end_tick": t - 1 })
		tick = t
	return { "track": { "kind": "rails", "segments": segments }, "burns": flown }


static func _vector_on(ctx: SimContext, orbit: Dictionary, planned: Dictionary, tick: int) -> Array[int]:
	var basis := BurnSystem.orbit_basis(ctx, orbit, tick)
	var vector: Array[int] = []
	for axis in 3:
		vector.append(OrbitMath.smul_div(planned["prograde_um_s"], basis[0][axis], OrbitMath.ONE)
			+ OrbitMath.smul_div(planned["normal_um_s"], basis[1][axis], OrbitMath.ONE)
			+ OrbitMath.smul_div(planned["radial_um_s"], basis[2][axis], OrbitMath.ONE))
	return vector


static func _line(place: int, pos: Array, vel: Array, tick: int) -> Dictionary:
	return { "kind": "line", "place": place, "pos": pos.duplicate(), "vel": vel.duplicate(), "tick": tick }


static func _is_low(track: Dictionary) -> bool:
	return track["kind"] == "low"


## Where a track is at a tick, as [place, r_mm, v_um_s]. v is [0, 0, 0] unless asked for. A low
## track is only known at its own tick.
static func sample(ctx: SimContext, track: Dictionary, tick: int, with_v: bool) -> Array:
	match track["kind"]:
		"rails":
			var orbit := _segment(track["segments"], tick)
			if with_v:
				var now := OrbitMath.state_at(orbit, ctx.state["bodies"][orbit["parent"]]["gm"], tick)
				return [orbit["parent"], now["r"], now["v"]]
			return [orbit["parent"], OrbitMath.position_at(orbit, tick), [0, 0, 0]]
		"line":
			var dt: int = tick - int(track["tick"])
			var pos: Array[int] = []
			for axis in 3:
				pos.append(int(track["pos"][axis]) + OrbitMath.smul_div(track["vel"][axis], dt,
					Sim.TICKS_PER_SECOND * UM_PER_MM))
			return [track["place"], pos, track["vel"].duplicate()]
		"route":
			var length: int = track["length"]
			var gone := mini(length, int(track["progress"]) + IntMath.mul_div(int(track["speed"]),
				maxi(0, tick - int(track["tick"])), Sim.TICKS_PER_SECOND))
			var pos: Array[int] = []
			var vel: Array[int] = [0, 0, 0]
			for axis in 3:
				pos.append(Travel.along(track["from"][axis], track["to"][axis], gone, maxi(1, length)))
			if gone < length and with_v:
				var direction := OrbitMath.unit([int(track["to"][0]) - int(track["from"][0]),
					int(track["to"][1]) - int(track["from"][1]), int(track["to"][2]) - int(track["from"][2])])
				for axis in 3:
					vel[axis] = OrbitMath.smul_div(direction[axis], int(track["speed"]) * UM_PER_MM, OrbitMath.ONE)
			return [track["place"], pos, vel]
		_:
			return [track["body"], track["pos"].duplicate(), track["vel"].duplicate()]


static func _segment(segments: Array, tick: int) -> Dictionary:
	var low := 0
	var high := segments.size() - 1
	while low < high:
		var mid := (low + high + 1) / 2
		if int(segments[mid][0]) <= tick:
			low = mid
		else:
			high = mid - 1
	return segments[low][1]


# ------------------------------------------------------------------------------ places

## The place a body or frame sits in: a body's orbit parent or frame, a frame's orbit parent, or 0
## for the root of everything.
static func place_parent(ctx: SimContext, place: int) -> int:
	if ctx.state["frames"].has(place):
		return ctx.state["frames"][place]["orbit"]["parent"]
	var body: Dictionary = ctx.state["bodies"].get(place, {})
	if body.is_empty():
		return 0
	if not body["orbit"].is_empty():
		return body["orbit"]["parent"]
	return body["frame"]


## A place's position and velocity in its own parent place at a tick, as [r, v].
static func place_offset(ctx: SimContext, place: int, tick: int, with_v: bool) -> Array:
	var orbit: Dictionary = {}
	var fixed: Array = [0, 0, 0]
	if ctx.state["frames"].has(place):
		orbit = ctx.state["frames"][place]["orbit"]
	else:
		var body: Dictionary = ctx.state["bodies"][place]
		orbit = body["orbit"]
		fixed = body["pos_mm"]
	if orbit.is_empty():
		return [fixed.duplicate(), [0, 0, 0]]
	if with_v:
		var now := OrbitMath.state_at(orbit, ctx.state["bodies"][orbit["parent"]]["gm"], tick)
		return [now["r"], now["v"]]
	return [OrbitMath.position_at(orbit, tick), [0, 0, 0]]


static func _chain(ctx: SimContext, place: int) -> Array[int]:
	var chain: Array[int] = [place]
	while place != 0:
		place = place_parent(ctx, place)
		chain.append(place)
	return chain


## The nearest place two places share.
static func shared_place(ctx: SimContext, a: int, b: int) -> int:
	if a == b:
		return a
	var theirs := _chain(ctx, b)
	for place in _chain(ctx, a):
		if theirs.has(place):
			return place
	return 0


## A sample moved up into an enclosing place.
static func lift(ctx: SimContext, at: Array, to_place: int, tick: int, with_v: bool) -> Array:
	var place: int = at[0]
	var r: Array = at[1].duplicate()
	var v: Array = at[2].duplicate()
	while place != to_place and place != 0:
		var offset := place_offset(ctx, place, tick, with_v)
		for axis in 3:
			r[axis] = int(r[axis]) + int(offset[0][axis])
			v[axis] = int(v[axis]) + int(offset[1][axis])
		place = place_parent(ctx, place)
	return [place, r, v]


# ------------------------------------------------------------------------------ relative state

## Target minus unit at a tick, both from tracks known at that tick: { parent, rel_pos_mm,
## rel_vel_um_s, range_mm, speed_um_s, closing_um_s, lateral_um_s }.
static func state_between(ctx: SimContext, mine: Dictionary, theirs: Dictionary, tick: int) -> Dictionary:
	return describe(ctx, sample(ctx, mine, tick, true), sample(ctx, theirs, tick, true), tick)


static func describe(ctx: SimContext, a: Array, b: Array, tick: int) -> Dictionary:
	var place := shared_place(ctx, a[0], b[0])
	var here := lift(ctx, a, place, tick, true)
	var there := lift(ctx, b, place, tick, true)
	var pos: Array[int] = []
	var vel: Array[int] = []
	for axis in 3:
		pos.append(int(there[1][axis]) - int(here[1][axis]))
		vel.append(int(there[2][axis]) - int(here[2][axis]))
	var parts := split_speed(pos, vel)
	return {
		"parent": place, "rel_pos_mm": pos, "rel_vel_um_s": vel, "range_mm": IntMath.dist(pos, [0, 0, 0]),
		"speed_um_s": IntMath.dist(vel, [0, 0, 0]), "closing_um_s": parts[0], "lateral_um_s": parts[1],
	}


## [closing, lateral] speed of a relative velocity along and across the line of a relative
## position: closing is positive while the range shrinks. At zero range all of it is lateral.
static func split_speed(pos: Array, vel: Array) -> Array[int]:
	var line := OrbitMath.unit(pos)
	if line == [0, 0, 0]:
		return [0, IntMath.dist(vel, [0, 0, 0])]
	var along := OrbitMath.dot(line, vel)
	var across: Array[int] = []
	for axis in 3:
		across.append(int(vel[axis]) - OrbitMath.smul_div(line[axis], along, OrbitMath.ONE))
	return [-along, IntMath.dist(across, [0, 0, 0])]


## The range between two tracks at a tick, from positions only.
static func range_at(ctx: SimContext, mine: Dictionary, theirs: Dictionary, tick: int) -> int:
	var a := sample(ctx, mine, tick, false)
	var b := sample(ctx, theirs, tick, false)
	var place := shared_place(ctx, a[0], b[0])
	return IntMath.dist(lift(ctx, a, place, tick, false)[1], lift(ctx, b, place, tick, false)[1])


## The closest approach of two tracks over [from_tick, from_tick + horizon], as { tick, range_mm,
## speed_um_s }. On rails and lines it samples the range CLOSEST_SAMPLES times and refines every
## dip to the tick by ternary search: a dip between two samples always leaves a sampled local
## minimum beside it, so none is skipped. A low track is stepped every tick, up to
## MAX_STEPPED_TICKS or the ground.
static func closest(ctx: SimContext, mine: Dictionary, theirs: Dictionary, from_tick: int, horizon: int) -> Dictionary:
	if _is_low(mine) or _is_low(theirs):
		return _closest_stepped(ctx, mine, theirs, from_tick, mini(horizon, MAX_STEPPED_TICKS))
	horizon = maxi(0, horizon)
	var step := maxi(1, horizon / CLOSEST_SAMPLES)
	var ticks: Array[int] = []
	var ranges: Array[int] = []
	var t := from_tick
	while t < from_tick + horizon:
		ticks.append(t)
		ranges.append(range_at(ctx, mine, theirs, t))
		t += step
	ticks.append(from_tick + horizon)
	ranges.append(range_at(ctx, mine, theirs, from_tick + horizon))
	var best_tick := ticks[0]
	var best := ranges[0]
	var count := ticks.size()
	for i in count:
		var dip := (i == 0 or ranges[i] <= ranges[i - 1]) and (i == count - 1 or ranges[i] <= ranges[i + 1])
		if not dip:
			continue
		var found := _refine(ctx, mine, theirs, ticks[maxi(0, i - 1)], ticks[mini(count - 1, i + 1)])
		if found[1] < best or (found[1] == best and found[0] < best_tick):
			best_tick = found[0]
			best = found[1]
	var at := state_between(ctx, mine, theirs, best_tick)
	return { "tick": best_tick, "range_mm": best, "speed_um_s": at["speed_um_s"] }


## [tick, range] of the least range in [low, high], by ternary search down to a few ticks.
static func _refine(ctx: SimContext, mine: Dictionary, theirs: Dictionary, low: int, high: int) -> Array[int]:
	while high - low > 3:
		var m1 := low + (high - low) / 3
		var m2 := high - (high - low) / 3
		if range_at(ctx, mine, theirs, m1) <= range_at(ctx, mine, theirs, m2):
			high = m2
		else:
			low = m1
	var best_tick := low
	var best := range_at(ctx, mine, theirs, low)
	for t in range(low + 1, high + 1):
		var r := range_at(ctx, mine, theirs, t)
		if r < best:
			best = r
			best_tick = t
	return [best_tick, best]


static func _closest_stepped(ctx: SimContext, mine: Dictionary, theirs: Dictionary, from_tick: int,
		horizon: int) -> Dictionary:
	var a := mine.duplicate(true)
	var b := theirs.duplicate(true)
	var memos := [{}, {}]
	var best := {}
	for t in range(from_tick, from_tick + horizon + 1):
		if t > from_tick:
			var grounded := false
			for which in 2:
				var track: Dictionary = a if which == 0 else b
				if _is_low(track):
					var next := LowFlight.advance(ctx, track["body"], track["pos"], track["vel"], track["carry"])
					track["pos"] = next["pos"]
					track["vel"] = next["vel"]
					track["carry"] = next["carry"]
					grounded = grounded or LowFlight.ground_contact(ctx, track["body"], next["pos"], memos[which]) >= 0
			if grounded:
				break
		var now := describe(ctx, sample(ctx, a, t, true), sample(ctx, b, t, true), t)
		if best.is_empty() or int(now["range_mm"]) < int(best["range_mm"]):
			best = { "tick": t, "range_mm": now["range_mm"], "speed_um_s": now["speed_um_s"] }
	return best


static func _default_horizon(ctx: SimContext, unit_id: int) -> int:
	var orbit := Transfer.unit_orbit(ctx, unit_id)
	if orbit.is_empty() or orbit.get("hyperbolic", false):
		return MAX_STEPPED_TICKS
	return maxi(1, int(orbit["period_subticks"]) / OrbitMath.SUB_TICKS)


# ------------------------------------------------------------------------------ plane and timing

## The unit's and the target's orbits, if both are round the same parent: [mine, theirs], or [].
static func _orbits(ctx: SimContext, unit_id: int, target: int) -> Array:
	var mine := Transfer.unit_orbit(ctx, unit_id)
	var unit: Dictionary = ctx.state["units"][unit_id]
	if unit["low_flight"] != 0 or not unit["landed"].is_empty():
		mine = {}
	var theirs := {}
	if ctx.state["units"].has(target):
		var other: Dictionary = ctx.state["units"][target]
		if other["low_flight"] == 0 and other["landed"].is_empty():
			theirs = Transfer.unit_orbit(ctx, target)
	else:
		var body: Dictionary = ctx.state["bodies"][target]
		theirs = body["orbit"] if not body["orbit"].is_empty() \
			else (ctx.state["frames"][body["frame"]]["orbit"] if body["frame"] != 0 else {})
	if mine.is_empty() or theirs.is_empty() or mine["parent"] != theirs["parent"]:
		return []
	return [mine, theirs]


static func normal_of(orbit: Dictionary) -> Array[int]:
	return OrbitMath.unit(OrbitMath.cross(orbit["p_q30"], orbit["q_q30"]))


static func to_mdeg(angle: int) -> int:
	return IntMath.mul_div(angle & OrbitMath.ANGLE_MASK, MDEG_PER_TURN, OrbitMath.TURN)


## { inclination_mdeg, ascending_tick, descending_tick }: the angle between the planes, and the
## next ticks the unit crosses the target's plane towards and away from the side its normal points
## to, or -1 for none within two turns. {} unless both orbit one parent.
static func _plane(orbits: Array, tick: int) -> Dictionary:
	if orbits.is_empty():
		return {}
	var mine: Dictionary = orbits[0]
	var normal_mine := normal_of(mine)
	var normal_theirs := normal_of(orbits[1])
	var across := IntMath.dist(OrbitMath.cross(normal_mine, normal_theirs), [0, 0, 0])
	var result := { "inclination_mdeg": to_mdeg(OrbitMath.angle_of(across, OrbitMath.dot(normal_mine, normal_theirs))),
		"ascending_tick": -1, "descending_tick": -1 }
	if across == 0 or mine.get("hyperbolic", false):
		return result
	var first := Transfer.node_tick(mine, normal_theirs, tick)
	if first < 0:
		return result
	var second := Transfer.node_tick(mine, normal_theirs, first + 1)
	var rising := Transfer._above(mine, normal_theirs, first)
	result["ascending_tick"] = first if rising else second
	result["descending_tick"] = second if rising else first
	return result


## How far the target is ahead of the unit round the unit's plane, 0 to 359999 mdeg, or -1.
static func _phase(orbits: Array, tick: int) -> int:
	if orbits.is_empty():
		return -1
	var mine: Dictionary = orbits[0]
	return to_mdeg(Transfer.angle_at(orbits[1], mine, tick) - Transfer.angle_at(mine, mine, tick))


## The next Hohmann window between near-circular orbits of different sizes in one plane round one
## parent, as { depart_tick, ticks }, or {}. The geometry only: quote prices the real trip.
static func _window(ctx: SimContext, orbits: Array, tick: int) -> Dictionary:
	if orbits.is_empty() or not Transfer._near_circular(orbits[0], orbits[1]) \
			or not Transfer._coplanar(orbits[0], orbits[1]):
		return {}
	if int(orbits[0]["period_subticks"]) == int(orbits[1]["period_subticks"]):
		return {}
	var gm: int = ctx.state["bodies"][orbits[0]["parent"]]["gm"]
	var plan := Transfer._hohmann(ctx, orbits[0], orbits[1], gm, tick)
	return { "depart_tick": plan["depart_tick"], "ticks": plan["ticks"] }


## What nulling a relative speed takes at the unit's thrust and mass now: { burn_ticks,
## lead_ticks, propellant_g }, or {} with no thruster.
static func _stop(ctx: SimContext, unit_id: int, speed_um_s: int) -> Dictionary:
	var found := BurnSystem.thruster(ctx, unit_id)
	if found.is_empty():
		return {}
	var mass_g := Units.unit_mass(ctx.state, ctx.defs, unit_id)
	var ticks := IntMath.mul_div_ceil(speed_um_s, mass_g * Sim.TICKS_PER_SECOND, int(found["thrust_n"]) * 1_000_000_000)
	return { "burn_ticks": ticks, "lead_ticks": ticks / 2,
		"propellant_g": OrbitMath.burn_g(mass_g, speed_um_s, found["exhaust_mm_s"]) }


# ------------------------------------------------------------------------------ docking

## The docking condition against a target unit: { range_mm, speed_um_s, capture_range_mm,
## capture_speed_um_s, reason }, or {} for a body. The limits are the tighter of the two ports'
## (placeholders until the port data has them), and are readouts only until stage 4. `reason` is
## what the dock step's own check gives now between the lowest free ports, "" if it would pass, or
## module_missing if either side has no free port.
static func _dock(ctx: SimContext, unit_id: int, target: int, now: Dictionary) -> Dictionary:
	if not ctx.state["units"].has(target):
		return {}
	var port := _free_port(ctx, unit_id)
	var target_port := _free_port(ctx, target)
	var result := { "range_mm": now["range_mm"], "speed_um_s": now["speed_um_s"],
		"capture_range_mm": DEFAULT_CAPTURE_RANGE_MM, "capture_speed_um_s": DEFAULT_CAPTURE_SPEED_UM_S,
		"reason": TaskSystem.REASON_MODULE_MISSING }
	var limits := [port, target_port]
	for part: int in limits:
		if part == 0:
			continue
		var stats: Dictionary = Units.module_of(ctx.state, ctx.defs, part)["capabilities"][DockStep.CAPABILITY]
		result["capture_range_mm"] = mini(result["capture_range_mm"], stats.get("capture_range_mm", DEFAULT_CAPTURE_RANGE_MM))
		result["capture_speed_um_s"] = mini(result["capture_speed_um_s"],
			int(stats.get("capture_speed_mm_s", DEFAULT_CAPTURE_SPEED_UM_S / UM_PER_MM)) * UM_PER_MM)
	if port != 0 and target_port != 0:
		result["reason"] = DockStep.new().validate(ctx, unit_id, { "port": port, "target_port": target_port })["reason"]
	return result


static func _free_port(ctx: SimContext, unit_id: int) -> int:
	for part in Units.ports(ctx.state, ctx.defs, unit_id):
		if ctx.state["parts"][part]["fault"] == "" and not Units.port_in_use(ctx.state, part):
			return part
	return 0


# ------------------------------------------------------------------------------ for systems (A59)

## The tick "now" is for a system: the tick being run during phases 2 to 7, when rails have placed
## everything at it, and the last completed tick otherwise (a view, a check, after a load).
static func now_tick(ctx: SimContext) -> int:
	return ctx.tick if ctx.phase >= 2 and ctx.phase <= 7 else int(ctx.state["tick"])


## Tracks of a unit and a target as they are now: a straight line or a route is where its state
## says, not moved on by a tick, since mid-tick its state may already be this tick's.
static func _tracks_now(ctx: SimContext, unit_id: int, target: int, tick: int) -> Array:
	var mine := unit_track(ctx, unit_id)
	var theirs := thing_track(ctx, target)
	for track: Dictionary in [mine, theirs]:
		if track.has("tick"):
			track["tick"] = tick
	return [mine, theirs]


static func _valid(ctx: SimContext, unit_id: int, target: int) -> bool:
	return ctx.state["units"].has(unit_id) and target != unit_id \
		and (ctx.state["units"].has(target) or ctx.state["bodies"].has(target))


## The target, a unit or a body, as seen from the unit now, for systems to call as they call
## RailSystem.world_mm (A59, for C's Reach): { parent, rel_pos_mm, rel_vel_um_s, range_mm, speed_um_s,
## closing_um_s, lateral_um_s }, as Sim.relative gives them, from the same code. {} for an unknown
## unit or target. A docked unit is measured as its host; a body's range is to its centre.
static func now_between(ctx: SimContext, unit_id: int, target: int) -> Dictionary:
	if not _valid(ctx, unit_id, target):
		return {}
	var tick := now_tick(ctx)
	var tracks := _tracks_now(ctx, unit_id, target, tick)
	return state_between(ctx, tracks[0], tracks[1], tick)


## The range from the unit to the target now, in mm, from positions only, or -1 if either is unknown.
static func range_now_mm(ctx: SimContext, unit_id: int, target: int) -> int:
	if not _valid(ctx, unit_id, target):
		return -1
	var tick := now_tick(ctx)
	var tracks := _tracks_now(ctx, unit_id, target, tick)
	return range_at(ctx, tracks[0], tracks[1], tick)


## The ticks before the range from the unit to the target could cross limit_mm, either way, for a
## coast horizon (A59, for Reach.horizon): the gap to the limit over the most the two can close or
## open per tick, by CoastBounds. 0 when either moves in a way no bound holds (stepped flight, a
## drift in a frame, an open orbit), so the caller steps.
static func range_horizon(ctx: SimContext, unit_id: int, target: int, limit_mm: int) -> int:
	var range_mm := range_now_mm(ctx, unit_id, target)
	if range_mm < 0:
		return 0
	var gap := absi(range_mm - limit_mm)
	var place := RailSystem.unit_place(ctx.state, unit_id)
	if place > 0 and place == RailSystem.target_place(ctx.state, target):
		var local := _local_um_s(ctx.state, unit_id) + _local_um_s(ctx.state, target)
		return 0 if local >= CoastBounds.UNBOUNDED_UM_S else CoastBounds.ticks_to_close(gap, local)
	var mine := _pull_bound(ctx.state, unit_id)
	var theirs := _pull_bound(ctx.state, target)
	if mine[1] >= 0 and theirs[1] >= 0 and mine[0] == theirs[0]:
		var seen := now_between(ctx, unit_id, target)
		return _ticks_under_pull(gap, int(seen["speed_um_s"]), int(mine[1]) + int(theirs[1]))
	var speed := _closing_bound_um_s(ctx, unit_id, target)
	if speed >= CoastBounds.UNBOUNDED_UM_S:
		return 0
	return CoastBounds.ticks_to_close(gap, speed)


## [the body a thing falls round, the most its acceleration can be in um/s^2], for things whose
## only acceleration is that body's pull: an elliptic orbit (the pull at periapsis), a frame and
## what sits still in it (the frame's orbit), or nothing for the landed. [0, -1] for anything else:
## thrust, a drift, a route, an open orbit.
static func _pull_bound(state: Dictionary, id: int) -> Array:
	var orbit: Dictionary = {}
	if state["units"].has(id):
		var unit: Dictionary = state["units"][id]
		if not unit["dock"].is_empty():
			return _pull_bound(state, unit["dock"]["target_unit"])
		if not unit.get("landed", {}).is_empty():
			return [unit["landed"]["body"], 0]
		if not unit["burn"].is_empty() or unit.get("low_flight", unit.get("stepped", 0)) != 0 				or not unit["route"].is_empty() or not unit["transfer"].is_empty():
			return [0, -1]
		if not unit["orbit"].is_empty():
			orbit = unit["orbit"]
		elif unit["frame"] != 0 and unit["vel_um_s"] == [0, 0, 0]:
			orbit = state["frames"][unit["frame"]]["orbit"]
	else:
		var body: Dictionary = state["bodies"][id]
		if not body["orbit"].is_empty():
			orbit = body["orbit"]
		elif body["frame"] != 0:
			orbit = state["frames"][body["frame"]]["orbit"]
	if orbit.is_empty() or orbit.get("hyperbolic", false):
		return [0, -1]
	var parent: int = orbit["parent"]
	var periapsis := maxi(1, CoastBounds.periapsis_mm(orbit))
	var gm: int = state["bodies"][parent]["gm"]
	var pull_nm := OrbitMath.smul_div(OrbitMath.smul_div(gm, 1_000_000_000_000, periapsis), 1_000_000, periapsis)
	return [parent, pull_nm / 1000 + 1]


## The ticks before a gap can close or open, from a relative speed now and the most the relative
## acceleration can be: v t + a t^2 / 2 <= gap, solved for t and rounded down, less a tick. Speeds and
## the gap take CoastBounds' slack.
static func _ticks_under_pull(gap_mm: int, speed_um_s: int, accel_um_s2: int) -> int:
	var gap_um := (gap_mm - CoastBounds.GAP_SLACK_MM) * 1000
	if gap_um <= 0:
		return 0
	var v := IntMath.mul_div(speed_um_s, CoastBounds.SPEED_SLACK_PERMILLE, 1000) + 1
	var a := maxi(1, IntMath.mul_div(accel_um_s2, CoastBounds.SPEED_SLACK_PERMILLE, 1000))
	# 100 (v^2 + 2 a gap), capped so it stays in range; a smaller gap only shortens the answer.
	var limit := 90_000_000_000_000_000
	var squared := mini(v, 3_000_000_000) * mini(v, 3_000_000_000)
	var room := maxi(0, limit - squared) / (2 * a)
	var disc := squared + 2 * a * mini(gap_um, room)
	var ticks := (IntMath.isqrt(100 * disc) - 10 * v) / a
	return clampi(ticks - 1, 0, SimSystem.NO_LIMIT)


## The most the unit and the target can close or open per second: each one's own motion below the
## first body both hang from, as CoastBounds bounds a unit against a body.
static func _closing_bound_um_s(ctx: SimContext, unit_id: int, target: int) -> int:
	var state := ctx.state
	# Two things in one frame move with it alike: only their own motion in it counts.
	var place := RailSystem.unit_place(state, unit_id)
	if place > 0 and place == RailSystem.target_place(state, target):
		return mini(_local_um_s(state, unit_id) + _local_um_s(state, target), CoastBounds.UNBOUNDED_UM_S)
	var mine := CoastBounds.unit_base(state, unit_id)
	if int(mine[1]) >= CoastBounds.UNBOUNDED_UM_S:
		return CoastBounds.UNBOUNDED_UM_S
	var base: int = mine[0]
	var speed: int = mine[1]
	if state["units"].has(target):
		var theirs := CoastBounds.unit_base(state, target)
		if int(theirs[1]) >= CoastBounds.UNBOUNDED_UM_S:
			return CoastBounds.UNBOUNDED_UM_S
		speed += int(theirs[1])
		if base == 0 or int(theirs[0]) == 0:
			return speed if base == int(theirs[0]) else CoastBounds.UNBOUNDED_UM_S
		return mini(speed + CoastBounds.chain_um_s(state, base, theirs[0]), CoastBounds.UNBOUNDED_UM_S)
	var body: Dictionary = state["bodies"][target]
	if body["orbit"].is_empty() and body["frame"] != 0:
		# A rock in a frame moves with the frame's orbit round the frame's parent.
		var frame: Dictionary = state["frames"][body["frame"]]
		var parent: int = frame["orbit"]["parent"]
		var carried := CoastBounds.orbit_max_um_s(state["bodies"][parent]["gm"], frame["orbit"])
		if base == 0:
			return CoastBounds.UNBOUNDED_UM_S
		return mini(speed + carried + CoastBounds.chain_um_s(state, base, parent), CoastBounds.UNBOUNDED_UM_S)
	if base == 0:
		return speed if body["orbit"].is_empty() else CoastBounds.UNBOUNDED_UM_S
	return CoastBounds.relative_speed_um_s(state, unit_id, target)


## The most a thing moves within its frame per second: a route's speed, nothing for something still
## or a body, unbounded for a drift.
static func _local_um_s(state: Dictionary, id: int) -> int:
	if not state["units"].has(id):
		return 0
	var unit: Dictionary = state["units"][id]
	if not unit["dock"].is_empty():
		return _local_um_s(state, unit["dock"]["target_unit"])
	if not unit["route"].is_empty():
		return int(unit["route"]["speed_mm_s"]) * 1000 + 1
	return 0 if unit["vel_um_s"] == [0, 0, 0] else CoastBounds.UNBOUNDED_UM_S
