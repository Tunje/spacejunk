class_name BurnSystem
extends SimSystem
## Burns, drift and frame changes (orbital_flight.md section 11, task A11). A burn is the only thing
## that changes an orbit: the player places burns on their own ship, and later a core's autopilot
## places the same burns for the ship it flies.
##
## A burn starts in phase 2 of its tick, fixing its direction from that tick's orbit, and holds the
## unit's operation as `burning` with the thruster as a power and heat load. From phase 5 of the same
## tick it delivers thrust / mass each tick, times its throttle, until its delta-v is done or the
## propellant runs out. Its steering (A55) keeps the start's direction, re-applies its prograde,
## normal and radial parts along the current motion, or points at a target or against the velocity
## relative to it, each tick. The turn is instant: ships have no facing yet (real_orbits.md section
## 7, orientation); a turn rate would limit how far the direction moves per tick in thrust_step.
## - On an orbit, the burn's start puts the unit in stepped flight (LowFlight, A55): position and
##   velocity stepped with gravity, each tick's thrust added to the velocity. It goes back onto an
##   exact orbit once the burn is over and it is above the ground's reach.
## - In a frame, it changes the unit's local velocity, and the unit drifts in a straight line. A
##   drifting unit leaves the frame for an orbit past leave_margin_mm beyond the frame's radius.
## - A unit on an orbit joins a frame within join_margin_mm of its radius at under JOIN_SPEED_UM_S.
##   The join margin is half the leave margin, so a slow unit at the edge cannot flap in and out.
##   Both shrink to fit a frame inside its parent's sphere of influence (A26), as a frame has no
##   gravity and a drifter must not coast past the SOI before it becomes an orbit again.
## - A unit drifting faster than LEAVE_SPEED_UM_S leaves its frame at once, onto the orbit the frame
##   and its velocity give, even mid-burn (A26). Only a slow nudge drifts in a straight line, which
##   near a small moon would otherwise carry it far off the path gravity gives.
## - A unit on an orbit changes parent on the tick it crosses a sphere of influence (A12): up to the
##   parent's parent when it passes its parent's `soi_mm`, or down to a child body inside the child's.
##
## Register after UnitSystem, whose unit views this adds to, and after TaskSystem, so a step that
## ends in phase 2 has freed the unit before a burn on the same tick looks. Register before
## PowerSystem, so a starting burn's thruster is a load in phase 4.

const PLAN := "plan_burn"
const CANCEL := "cancel_burn"
const OP_BURNING := "burning"
const DELTA_PROPELLANT := "propellant"
const REASON_NOT_FLYING := "not_flying"
const REASON_IN_PAST := "burn_in_past"
const REASON_MALFORMED := "malformed_command"
const REASON_NO_THRUSTER := "module_missing"
const REASON_INVALID := "invalid_target"
const REASON_BUSY := "part_busy"
const REASON_NO_PROPELLANT := "no_propellant"
const REASON_ESCAPE := "unsupported_orbit"
const REASON_CANCELLED := "cancelled"
const REASON_THROTTLE := "throttle_out_of_range"
const CAPABILITY := "thruster"
const FULL_THROTTLE_PPM := 1_000_000
## Steering (A55): the start's direction; the planned parts along the current motion each tick;
## towards the target; against the velocity relative to the target, ending once it is nulled.
const STEER_FIXED := "fixed"
const STEER_ORBIT := "orbit"
const STEER_TARGET := "target"
const STEER_TARGET_RETROGRADE := "target_retrograde"
const STEERING := [STEER_FIXED, STEER_ORBIT, STEER_TARGET, STEER_TARGET_RETROGRADE]
const TARGET_STEERING := [STEER_TARGET, STEER_TARGET_RETROGRADE]
## The most points check's `path` gives (A57).
const PATH_POINTS := 500
const MAX_DV_UM_S := 1_000_000_000_000
## check flies a planned burn tick by tick, as the real one will be, for up to this many ticks.
## A longer burn is previewed as one impulse, marked `approximate`.
const MAX_PREVIEW_TICKS := 20_000
## The leave margin where the parent's sphere of influence leaves room, as round the star; the join
## margin is always half the leave margin.
const LEAVE_MARGIN_MM := 2_000_000_000
## The least leave margin. ScenarioBuilder refuses a frame with less room than this in its parent's
## SOI, so the floor never puts the leave point outside it.
const MIN_LEAVE_MARGIN_MM := 2_000_000
const JOIN_SPEED_UM_S := 1_000_000
## Twice the join speed, so a unit can't flap between joining and leaving.
const LEAVE_SPEED_UM_S := 2_000_000
## Room for the stored positions to differ from freshly computed ones by rounding.
const JOIN_SLACK_MM := 1_000_000
## Drift is carried in tenths of a micrometre: velocity in um/s over a tenth of a second.
const DRIFT_PER_MM := 10_000
const MAX_PREDICT_POINTS := 10_000
## Axes for a burn in the old world, which has no orbit to take them from.
const OLD_WORLD_BASIS := [[1 << 30, 0, 0], [0, 1 << 30, 0], [0, 0, 1 << 30]]

## Units whose burn began this tick in phase 2, already at their state for this tick, so phase 5
## thrusts without stepping them. Filled and emptied within one tick, never saved.
var _entered := {}


func commands() -> PackedStringArray:
	return PackedStringArray([PLAN, CANCEL])


func validate(ctx: SimContext, command: Dictionary) -> Dictionary:
	if command["type"] == CANCEL:
		return _validate_cancel(ctx, command)
	var args: Dictionary = command["args"]
	for key: String in ["tick", "prograde_um_s", "normal_um_s", "radial_um_s"]:
		if typeof(args.get(key)) != TYPE_INT:
			return SimSystem.reject(REASON_MALFORMED)
	var unit_id: int = command["unit"]
	if not ctx.state["units"][unit_id]["dock"].is_empty():
		return SimSystem.reject(REASON_NOT_FLYING)
	if args["tick"] <= ctx.state["tick"]:
		return SimSystem.reject(REASON_IN_PAST)
	var parts := [args["prograde_um_s"], args["normal_um_s"], args["radial_um_s"]]
	if parts == [0, 0, 0] or parts.any(func(v: int) -> bool: return absi(v) > MAX_DV_UM_S):
		return SimSystem.reject(REASON_MALFORMED)
	var found := thruster(ctx, unit_id)
	if found.is_empty():
		return SimSystem.reject(REASON_NO_THRUSTER)
	var target: Variant = args.get("target")
	if target != null and (typeof(target) != TYPE_INT or target == unit_id
			or not (ctx.state["units"].has(target) or ctx.state["bodies"].has(target))):
		return SimSystem.reject(REASON_INVALID)
	var steer: Variant = args.get("steer", STEER_FIXED)
	if typeof(steer) != TYPE_STRING or not STEERING.has(steer):
		return SimSystem.reject(REASON_MALFORMED)
	if TARGET_STEERING.has(steer) and target == null:
		return SimSystem.reject(REASON_INVALID)
	var throttle: Variant = args.get("throttle_ppm", FULL_THROTTLE_PPM)
	if typeof(throttle) != TYPE_INT:
		return SimSystem.reject(REASON_MALFORMED)
	if throttle < min_throttle_ppm(ctx, found["part"]) or throttle > FULL_THROTTLE_PPM:
		return SimSystem.reject(REASON_THROTTLE)
	var result := SimSystem.ok()
	# Only check needs the flown preview. Phase 1 validation skips it: a long burn's preview costs
	# a fifth of a millisecond per burn tick, which would land inside the tick (A17).
	if ctx.phase != 1:
		result["detail"] = _preview(ctx, unit_id, args, found)
		result["detail"]["lead_ticks"] = int(result["detail"]["burn_ticks"]) / 2
		if target != null:
			result["detail"]["closest"] = _closest_after(ctx, unit_id, args, target)
	return result


## The closest approach to a target on the path after a planned burn (A54): flown from now through
## the burn, over it and one turn of the orbit it gives, or of the unit's own if that escapes.
## {} off an orbit or stepped flight.
static func _closest_after(ctx: SimContext, unit_id: int, args: Dictionary, target: int) -> Dictionary:
	var flown := _fly_candidate(ctx, unit_id, args, -1)
	if flown.is_empty():
		return {}
	return Relative.closest(ctx, { "kind": "flown", "segments": flown["segments"] }, Relative.thing_track(ctx, target),
		args["tick"], int(flown["end_tick"]) - int(args["tick"]))


## The candidate burn flown from now, alone, then on for `after_ticks` past its end: -1 is one turn
## of the orbit it ends on, or of the unit's own if that escapes, at most 50 MAX_PREVIEW_TICKS.
static func _fly_candidate(ctx: SimContext, unit_id: int, args: Dictionary, after_ticks: int) -> Dictionary:
	var burn := planned_record(0, args)
	var first := FlightAhead.fly(ctx, unit_id, [burn], int(args["tick"]) + MAX_PREVIEW_TICKS, false, true)
	if first.is_empty():
		return {}
	var extra := after_ticks
	if extra < 0:
		var orbit: Dictionary = first["final"].get("orbit", {})
		if orbit.is_empty() or orbit.get("hyperbolic", false):
			orbit = Transfer.unit_orbit(ctx, unit_id)
		if orbit.is_empty() or orbit.get("hyperbolic", false):
			extra = MAX_PREVIEW_TICKS
		else:
			extra = mini(int(orbit["period_subticks"]) / OrbitMath.SUB_TICKS, 50 * MAX_PREVIEW_TICKS)
	return FlightAhead.fly(ctx, unit_id, [burn], int(first["end_tick"]) + extra, false, false)


## A planned-burn record from plan_burn's args.
static func planned_record(id: int, args: Dictionary) -> Dictionary:
	return {
		"id": id, "tick": args["tick"], "prograde_um_s": args["prograde_um_s"],
		"normal_um_s": args["normal_um_s"], "radial_um_s": args["radial_um_s"],
		"throttle_ppm": args.get("throttle_ppm", FULL_THROTTLE_PPM), "steer": args.get("steer", STEER_FIXED),
		"target": args.get("target", 0),
	}


func apply(ctx: SimContext, command: Dictionary) -> void:
	var unit: Dictionary = ctx.state["units"][command["unit"]]
	var args: Dictionary = command["args"]
	if command["type"] == CANCEL:
		_cancel(ctx, command["unit"], args["burn"])
		return
	unit["burns"].append(planned_record(ctx.new_id(), args))
	unit["burns"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["tick"] < b["tick"] or (a["tick"] == b["tick"] and a["id"] < b["id"]))


## Phase 2: start each burn whose tick has come.
func update_tasks(ctx: SimContext) -> void:
	_entered.clear()
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		var unit: Dictionary = units[id]
		if unit["burn"].is_empty() and not unit["burns"].is_empty() and unit["burns"][0]["tick"] <= ctx.tick:
			_start(ctx, id, unit["burns"].pop_front())


## Phase 5, unit by unit: stepped flight moves (unless it began this tick, already where it is for
## this tick), then thrust, then the switch back to an orbit, drift, or frame and sphere changes.
func run(ctx: SimContext) -> void:
	var units: Dictionary = ctx.state["units"]
	# The frames and spheres each parent's orbiters are tested against, sorted and with their join
	# distances, once per tick rather than once per unit (A40).
	var near := {}
	for id: int in _sorted(units):
		var unit: Dictionary = units[id]
		if not unit["dock"].is_empty() or not unit["route"].is_empty() or not unit["transfer"].is_empty():
			if not unit["burn"].is_empty():
				_thrust(ctx, id)
			continue
		if unit["stepped"] != 0 and not _entered.has(id):
			LowFlight.step(ctx, id)
		if not unit["burn"].is_empty():
			_thrust(ctx, id)
		if unit["stepped"] != 0:
			LowFlight.settle(ctx, id)
		elif not unit["landed"].is_empty():
			continue
		elif unit["orbit"].is_empty():
			_drift(ctx, id)
			# Leaving a frame mid-burn lands on an orbit; the rest of the burn is stepped.
			if not unit["orbit"].is_empty() and not unit["burn"].is_empty():
				LowFlight.enter(ctx, id)
		elif LowFlight.should_enter(ctx, unit):
			LowFlight.enter(ctx, id)
		else:
			var parent: int = unit["orbit"]["parent"]
			if not near.has(parent):
				near[parent] = _near_of(ctx, parent)
			_cross_soi(ctx, id, near[parent]["children"])
			# A crossing this tick re-bases the orbit, and the join test then uses the new parent's
			# frames, as it always has.
			if unit["orbit"].is_empty():
				continue
			parent = unit["orbit"]["parent"]
			if not near.has(parent):
				near[parent] = _near_of(ctx, parent)
			_try_join(ctx, id, near[parent]["frames"])


## For orbiters round a parent: { children: [child IDs with a sphere], frames: [[frame ID, join
## distance]] }, each in ascending ID.
func _near_of(ctx: SimContext, parent_id: int) -> Dictionary:
	var children: Array = []
	var bodies: Dictionary = ctx.state["bodies"]
	for child_id: int in _sorted(bodies):
		var child: Dictionary = bodies[child_id]
		if child.get("soi_mm", 0) > 0 and child["orbit"].get("parent", 0) == parent_id:
			children.append(child_id)
	var frames: Array = []
	var all: Dictionary = ctx.state["frames"]
	for frame_id: int in _sorted(all):
		var frame: Dictionary = all[frame_id]
		if frame["orbit"]["parent"] == parent_id:
			frames.append([frame_id, int(frame["radius_mm"]) + join_margin_mm(ctx, frame)])
	return { "children": children, "frames": frames }


## Coast (A33): a running burn, low flight and drift in a frame change every tick, so they are
## stepped. A planned burn starts on its tick. A unit on an orbit coasts until it could reach a
## sphere of influence, a frame's join distance or low flight, by CoastBounds.
func horizon(ctx: SimContext) -> int:
	var skip := NO_LIMIT
	var now: int = ctx.state["tick"]
	var units: Dictionary = ctx.state["units"]
	# What each parent's orbiters could run into, worked out once per pass (A38).
	var neighbours := {}
	for id: int in _sorted(units):
		var unit: Dictionary = units[id]
		if not unit["burn"].is_empty():
			ctx.coast_cap = "burning"
			return 0
		if not unit["burns"].is_empty():
			skip = mini(skip, int(unit["burns"][0]["tick"]) - now - 1)
		if not unit["dock"].is_empty() or not unit["route"].is_empty() or not unit["transfer"].is_empty():
			continue
		if unit["stepped"] != 0:
			ctx.coast_cap = "stepped"
			return 0
		if not unit["landed"].is_empty():
			continue
		if unit["orbit"].is_empty():
			if unit["vel_um_s"] != [0, 0, 0]:
				ctx.coast_cap = "drifting"
				return 0
			continue
		skip = mini(skip, _orbit_horizon(ctx, unit, neighbours))
		if skip <= 0:
			ctx.coast_cap = "near_a_boundary"
			return 0
	if skip <= 0:
		ctx.coast_cap = "planned_burn"
	return maxi(skip, 0)


## The ticks a unit on an orbit can coast before it could need _cross_soi, _try_join or low flight.
func _orbit_horizon(ctx: SimContext, unit: Dictionary, neighbours: Dictionary = {}) -> int:
	var orbit: Dictionary = unit["orbit"]
	if orbit.get("hyperbolic", false):
		return 0
	var bodies: Dictionary = ctx.state["bodies"]
	var parent_id: int = orbit["parent"]
	var parent: Dictionary = bodies[parent_id]
	var periapsis := CoastBounds.periapsis_mm(orbit)
	var apoapsis := apoapsis_mm(orbit)
	if parent["gm"] > 0 and periapsis - int(parent["radius_mm"]) < LowFlight.enter_mm(ctx, parent_id):
		return 0
	var speed := CoastBounds.orbit_max_um_s(parent["gm"], orbit)
	var here: Array = unit["pos_mm"]
	var skip := NO_LIMIT
	var soi: int = parent.get("soi_mm", 0)
	if soi > 0 and not parent["orbit"].is_empty() and apoapsis >= soi:
		skip = mini(skip, CoastBounds.ticks_to_close(soi - IntMath.dist(here, [0, 0, 0]), speed))
	if not neighbours.has(parent_id):
		neighbours[parent_id] = _neighbours_of(ctx, parent_id)
	var close := []
	for near: Array in neighbours[parent_id]:
		var bound := _approach_horizon(here, periapsis, apoapsis, speed, near)
		if bound <= 0 and int(near[5]) != 0:
			close.append(near)
		else:
			skip = mini(skip, bound)
	if skip <= 0 or close.is_empty():
		return skip
	# Within a frame's join reach the bound is 0. A unit moving well faster than JOIN_SPEED_UM_S
	# relative to the frame can't join until gravity's difference across them slows it, which is
	# slow and has a bound (A50). Otherwise each coming tick is tried by _try_join's own test.
	var walk := []
	for near: Array in close:
		var by_speed := _join_speed_bound(orbit, parent["gm"], near, ctx.state["tick"])
		if by_speed > 0:
			skip = mini(skip, by_speed)
		else:
			walk.append(near)
	if skip <= 0 or walk.is_empty():
		return skip
	var limit := mini(skip, ctx.coast_limit if ctx.coast_limit > 0 else NO_LIMIT)
	return mini(skip, _join_walk(orbit, parent["gm"], walk, periapsis, apoapsis, speed, ctx.state["tick"], limit))


## The ticks a unit within a frame's reach can't join it because it moves too fast relative to it,
## or 0 if that can't be bounded (A50). Relative speed changes only by the difference of gravity
## across the two, at most 2 GM d / r^3 for a separation d at distance r from the parent: three
## times that is taken, with d up to twice the reach and r the nearer of the two less that. The
## bound holds only while they are that close, so it is also capped by the time the separation
## could take to grow that far, and by the time the speed could take to double.
static func _join_speed_bound(orbit: Dictionary, gm: int, near: Array, now: int) -> int:
	var mine := OrbitMath.state_at(orbit, gm, now)
	var theirs := OrbitMath.state_at(near[7], gm, now)
	var rel := IntMath.dist(mine["v"], theirs["v"])
	if rel < 2 * JOIN_SPEED_UM_S:
		return 0
	var apart := 2 * int(near[1])
	var separation := IntMath.dist(mine["r"], theirs["r"])
	var low := mini(IntMath.dist(mine["r"], [0, 0, 0]), IntMath.dist(theirs["r"], [0, 0, 0])) - apart
	if separation >= apart or low <= 0:
		return 0
	var gravity := IntMath.mul_div(gm, LowFlight.UM_PER_S2_FACTOR / low, low)
	var per_tick := IntMath.mul_div(3 * gravity, apart, low) / Sim.TICKS_PER_SECOND + 1
	var slowing := (rel - JOIN_SPEED_UM_S) / per_tick - 1
	var doubling := rel / per_tick
	var spreading := CoastBounds.ticks_to_close(apart - separation, 2 * rel + 1)
	return maxi(0, mini(slowing, mini(doubling, spreading)))


## The most ticks MAX_JOIN_STEPS ahead.
const MAX_JOIN_STEPS := 128


## How many coming ticks a unit on `orbit` can pass without joining any of the frames in `close`,
## each [place, reach, periapsis, apoapsis, top speed, frame ID, join distance, frame orbit] as
## _neighbours_of gives them (A50). Each tick is tried by _try_join's own arithmetic: the coarse
## distance, then the exact local distance and relative speed. Once the unit is outside every
## frame's reach, the ordinary bound from that tick adds the rest. Stops at `limit`, since more
## can't lengthen the skip, or after MAX_JOIN_STEPS.
static func _join_walk(orbit: Dictionary, gm: int, close: Array, periapsis: int, apoapsis: int, speed: int,
		now: int, limit: int) -> int:
	for k in range(1, MAX_JOIN_STEPS + 1):
		if k > limit:
			return limit
		var tick := now + k
		var unit_mm := OrbitMath.position_at(orbit, tick)
		var inside := false
		for near: Array in close:
			var frame_orbit: Dictionary = near[7]
			var join_mm: int = near[6]
			var frame_mm := OrbitMath.position_at(frame_orbit, tick)
			var gap := [unit_mm[0] - frame_mm[0], unit_mm[1] - frame_mm[1], unit_mm[2] - frame_mm[2]]
			if IntMath.dist_above(gap, int(near[1])):
				continue
			inside = true
			if IntMath.dist_above(gap, join_mm + JOIN_SLACK_MM):
				continue
			var mine := OrbitMath.state_at(orbit, gm, tick)
			var theirs := OrbitMath.state_at(frame_orbit, gm, tick)
			var local: Array[int] = []
			var rel_v: Array[int] = []
			for axis in 3:
				local.append(int(mine["r"][axis]) - int(theirs["r"][axis]))
				rel_v.append(int(mine["v"][axis]) - int(theirs["v"][axis]))
			if not IntMath.dist_above(local, join_mm) and IntMath.dist(rel_v, [0, 0, 0]) < JOIN_SPEED_UM_S:
				return k - 1
		if not inside:
			# Clear of every reach: the bound from here, against where the frames are now.
			var rest := NO_LIMIT
			for near: Array in close:
				var moved := near.duplicate()
				moved[0] = OrbitMath.position_at(near[7], tick)
				rest = mini(rest, _approach_horizon(unit_mm, periapsis, apoapsis, speed, moved))
			return mini(k + maxi(rest, 0), NO_LIMIT)
	return MAX_JOIN_STEPS


## What an orbiter round a parent could come within reach of, as [position, reach, its periapsis,
## its apoapsis, its fastest speed]: the parent's children with gravity, by their spheres, then
## the frames round it, by their join distance. Bodies first, each in ascending ID.
func _neighbours_of(ctx: SimContext, parent_id: int) -> Array:
	var result := []
	var gm: int = ctx.state["bodies"][parent_id]["gm"]
	var bodies: Dictionary = ctx.state["bodies"]
	for child_id: int in _sorted(bodies):
		var child: Dictionary = bodies[child_id]
		if child["orbit"].is_empty() or child["orbit"]["parent"] != parent_id or child["gm"] <= 0:
			continue
		result.append(_neighbour(child["pos_mm"], child["orbit"], gm, child.get("soi_mm", 0)))
	var frames: Dictionary = ctx.state["frames"]
	for frame_id: int in _sorted(frames):
		var frame: Dictionary = frames[frame_id]
		if frame["orbit"]["parent"] != parent_id:
			continue
		var join_mm: int = frame["radius_mm"] + join_margin_mm(ctx, frame)
		result.append(_neighbour(frame["pos_mm"], frame["orbit"], gm, join_mm + JOIN_SLACK_MM, frame_id, join_mm))
	return result


## [place, reach, periapsis, apoapsis, top speed, frame ID or 0, join distance, orbit].
static func _neighbour(there: Array, orbit: Dictionary, gm: int, reach: int, frame_id: int = 0,
		join_mm: int = 0) -> Array:
	return [there, reach, CoastBounds.periapsis_mm(orbit), apoapsis_mm(orbit), CoastBounds.orbit_max_um_s(gm, orbit),
		frame_id, join_mm, orbit]


## The ticks before a unit could come within reach of something on another orbit round the same
## parent: never if their distance bands from the parent can't meet, else the gap over both speeds.
static func _approach_horizon(here: Array, periapsis: int, apoapsis: int, speed: int, near: Array) -> int:
	var reach: int = near[1]
	if int(near[2]) - reach > apoapsis or int(near[3]) + reach < periapsis:
		return NO_LIMIT
	var there: Array = near[0]
	var gap := IntMath.dist([here[0] - there[0], here[1] - there[1], here[2] - there[2]], [0, 0, 0]) - reach
	return CoastBounds.ticks_to_close(gap, speed + int(near[4]))


func apply_delta(ctx: SimContext, payload: Dictionary) -> void:
	Units.remove_stock(ctx.state["units"][payload["unit"]]["inventory"], Travel.PROPELLANT, payload["grams"])
	var sink: Dictionary = ctx.state["sinks"].get_or_add(Travel.SINK, {})
	sink[Travel.PROPELLANT] = sink.get(Travel.PROPELLANT, 0) + payload["grams"]


func fill_view(ctx: SimContext, view: Dictionary) -> void:
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		var unit: Dictionary = units[id]
		var shown: Dictionary = view["units"][id]
		shown["vel_um_s"] = unit["vel_um_s"].duplicate()
		shown["stepped"] = unit["stepped"]
		shown["touchdown_mm_s"] = LowFlight.touchdown_mm_s(ctx, id)
		shown["burns"] = unit["burns"].duplicate(true)
		shown["surface_contact_tick"] = surface_contact_tick(ctx, id)
		var burn: Dictionary = unit["burn"]
		shown["burn"] = {} if burn.is_empty() else {
			"id": burn["id"], "dv_um_s": burn["dv_um_s"], "done_um_s": burn["done_um_s"],
			"start_tick": burn["start_tick"], "throttle_ppm": burn["throttle_ppm"], "steer": burn["steer"],
		}
		if not unit["orbit"].is_empty() and typeof(shown.get("orbit")) == TYPE_DICTIONARY and not shown["orbit"].is_empty():
			add_apsides(shown["orbit"], unit["orbit"], ctx.state["tick"])
	var bodies: Dictionary = ctx.state["bodies"]
	for id: int in _sorted(bodies):
		var shown_body: Dictionary = view["bodies"].get(id, {})
		if not bodies[id]["orbit"].is_empty() and typeof(shown_body.get("orbit")) == TYPE_DICTIONARY \
				and not shown_body["orbit"].is_empty():
			add_apsides(shown_body["orbit"], bodies[id]["orbit"], ctx.state["tick"])


## An orbit record's apsides for the view and check (A57): periapsis_mm and apoapsis_mm from the
## parent's centre (-1 for an open orbit's apoapsis), and the next ticks it passes them, at or after
## `tick` (-1 where there is none).
static func add_apsides(shown: Dictionary, orbit: Dictionary, tick: int) -> void:
	shown["periapsis_mm"] = OrbitMath.periapsis_radius_mm(orbit)
	shown["apoapsis_mm"] = OrbitMath.apoapsis_radius_mm(orbit)
	shown["next_periapsis_tick"] = OrbitMath.next_periapsis_tick(orbit, tick)
	shown["next_apoapsis_tick"] = OrbitMath.next_apoapsis_tick(orbit, tick)


## How far ahead surface_contact_tick looks.
const SURFACE_HORIZON_TICKS := 20_000


## The tick the unit's current path, with its planned burns flown, meets its parent's ground, or -1
## if it doesn't within SURFACE_HORIZON_TICKS (A55). A coasting orbit whose periapsis is above the
## ground's reach is -1 at once. A flight is cached on the context and reused while the unit is where
## it said the unit would be and nothing in its plan has changed.
static func surface_contact_tick(ctx: SimContext, unit_id: int) -> int:
	var unit: Dictionary = ctx.state["units"][unit_id]
	if not unit["dock"].is_empty() or not unit["landed"].is_empty() or not unit["route"].is_empty() \
			or not unit["transfer"].is_empty():
		return -1
	if unit["stepped"] == 0:
		if unit["orbit"].is_empty():
			return -1
		if unit["burns"].is_empty() and unit["burn"].is_empty():
			var body: Dictionary = ctx.state["bodies"][unit["orbit"]["parent"]]
			if body["gm"] <= 0 or OrbitMath.periapsis_radius_mm(unit["orbit"]) >= int(body["radius_mm"]) \
					+ LowFlight.enter_mm(ctx, unit["orbit"]["parent"]):
				return -1
	var plan := str([unit["burns"], unit["burn"].get("id", 0), unit["orbit"], Units.unit_mass(ctx.state, ctx.defs, unit_id),
		Reservations.free_stock(ctx, unit_id, Travel.PROPELLANT)])
	var now: int = ctx.state["tick"]
	var cached: Dictionary = ctx.flight_cache.get(unit_id, {})
	if not cached.is_empty() and cached["plan"] == plan and now <= int(cached["until"]) and _follows(unit, cached, now):
		return cached["contact"]
	var flown := FlightAhead.fly(ctx, unit_id, unit["burns"], now + SURFACE_HORIZON_TICKS)
	if flown.is_empty():
		return -1
	var contact: int = flown["contact"].get("tick", -1)
	ctx.flight_cache[unit_id] = { "plan": plan, "until": flown["end_tick"], "segments": flown["segments"],
		"contact": contact }
	return contact


## True if the unit is now where its cached flight said: on the same orbit, or at the same stepped
## state.
static func _follows(unit: Dictionary, cached: Dictionary, now: int) -> bool:
	if unit["stepped"] == 0:
		return not unit["orbit"].is_empty() and FlightAhead.segment_at(cached["segments"], now)[1] == unit["orbit"]
	var state := FlightAhead.stepped_state(cached["segments"], now)
	return not state.is_empty() and state[0] == unit["pos_mm"] and state[1] == unit["vel_um_s"] \
		and state[2] == unit["drift_carry"] and state[3] == unit.get("vel_carry_nm", [0, 0, 0])


# ------------------------------------------------------------------------------ queries

## The burn thruster: the healthy one with the most thrust, lowest part ID on a tie, as
## { part, thrust_n, exhaust_mm_s }, or {} if the unit has none with both figures.
static func thruster(ctx: SimContext, unit_id: int) -> Dictionary:
	var best := {}
	for part_id in Units.sorted_part_ids(ctx.state, unit_id):
		var stats: Dictionary = Units.module_of(ctx.state, ctx.defs, part_id)["capabilities"].get(CAPABILITY, {})
		if not stats.has("thrust_n") or not stats.has("exhaust_mm_s") or ctx.state["parts"][part_id]["fault"] != "":
			continue
		if best.is_empty() or stats["thrust_n"] > best["thrust_n"]:
			best = { "part": part_id, "thrust_n": stats["thrust_n"], "exhaust_mm_s": stats["exhaust_mm_s"] }
	return best


## Positions along a unit's path, as { place, points, world_points, ended }, from from_tick every
## `step` ticks for `ticks` ticks: -1 is one turn of its orbit, or until it leaves its parent's
## sphere, whichever is first (A57). Without with_burns the path coasts; with them its running and
## planned burns are flown (A54, A55). Points are relative to `place`; world_points are the same
## points relative to the root, so a moving parent needn't be worked out again. `ended` says what
## ended it: "ticks", "revolution", "sphere" or "ground". {} if the request is out of range.
static func predict(ctx: SimContext, unit_id: int, from_tick: int, ticks: int, step: int,
		with_burns: bool = false) -> Dictionary:
	if not ctx.state["units"].has(unit_id) or step < 1 or ticks < -1:
		return {}
	var unit: Dictionary = ctx.state["units"][unit_id]
	if not unit["dock"].is_empty():
		return predict(ctx, unit["dock"]["target_unit"], from_tick, ticks, step, with_burns)
	var ended := "ticks"
	if ticks == -1:
		var span := _one_turn(ctx, unit, from_tick)
		ticks = span[0]
		ended = span[1]
	if ticks / step >= MAX_PREDICT_POINTS:
		return {}
	if unit["stepped"] != 0 or not unit["orbit"].is_empty():
		var now: int = ctx.state["tick"]
		var burns: Array = unit["burns"] if with_burns else []
		var flown := FlightAhead.fly(ctx, unit_id, burns, maxi(now, from_tick + ticks), with_burns)
		if not flown.is_empty():
			var place_id: int = unit["stepped"] if unit["stepped"] != 0 else unit["orbit"]["parent"]
			var place := { "stepped": place_id } if unit["stepped"] != 0 else { "orbit_parent": place_id }
			var points: Array = []
			var world: Array = []
			var last := from_tick + ticks
			if not flown["contact"].is_empty():
				last = mini(last, int(flown["contact"]["tick"]))
				ended = "ground"
			for t in range(from_tick, last + 1, step):
				_add_point(ctx, flown["segments"], t, place_id, points, world)
			if ended == "ground" and (last - from_tick) % step != 0:
				_add_point(ctx, flown["segments"], last, place_id, points, world)
			var result := { "place": place, "points": points, "world_points": world, "ended": ended,
				"contact": flown["contact"] }
			if with_burns:
				result["burns"] = flown["burns"]
			return result
	var points: Array = []
	var world: Array = []
	var orbit: Dictionary = unit["orbit"]
	for t in range(from_tick, from_tick + ticks + 1, step):
		var dt: int = t - int(ctx.state["tick"])
		var point: Array[int] = []
		for axis in 3:
			point.append(int(unit["pos_mm"][axis]) + OrbitMath.smul_div(unit["vel_um_s"][axis], dt,
				Sim.TICKS_PER_SECOND * 1000))
		points.append(point)
		var place_id: int = unit["landed"]["body"] if not unit["landed"].is_empty() else unit["frame"]
		world.append(Relative.lift(ctx, [place_id, point, [0, 0, 0]], 0, t, false)[1])
	var place := { "frame": unit["frame"] }
	if not unit["landed"].is_empty():
		place = { "landed": unit["landed"]["body"] }
	var result := { "place": place, "points": points, "world_points": world, "ended": ended }
	if with_burns:
		result["burns"] = []
	return result


## A flight's point at tick t, relative to `place_id` and to the root.
static func _add_point(ctx: SimContext, segments: Array, t: int, place_id: int, points: Array, world: Array) -> void:
	var at := FlightAhead.sample(ctx, segments, t, false)
	var root := Relative.lift(ctx, at, 0, t, false)
	var base := Relative.lift(ctx, [place_id, [0, 0, 0], [0, 0, 0]], 0, t, false)
	points.append(LowFlight._add(root[1], base[1], -1))
	world.append(root[1])


## [ticks, ended] for predict's -1: one turn of the unit's orbit, or the ticks until it leaves its
## parent's sphere if sooner, found by bisection. Off an orbit, MAX_PREVIEW_TICKS.
static func _one_turn(ctx: SimContext, unit: Dictionary, from_tick: int) -> Array:
	var orbit: Dictionary = unit["orbit"]
	if orbit.is_empty():
		return [MAX_PREVIEW_TICKS, "ticks"]
	var turn := MAX_PREVIEW_TICKS * 50 if orbit.get("hyperbolic", false) \
		else int(orbit["period_subticks"]) / OrbitMath.SUB_TICKS
	var parent: Dictionary = ctx.state["bodies"][orbit["parent"]]
	var soi: int = parent.get("soi_mm", 0)
	if soi <= 0 or parent["orbit"].is_empty():
		return [turn, "revolution"]
	var apo := OrbitMath.apoapsis_radius_mm(orbit)
	if apo >= 0 and apo < soi:
		return [turn, "revolution"]
	if not IntMath.dist_above(OrbitMath.position_at(orbit, from_tick + turn), soi):
		# Leaves and comes back within the turn can't happen on one orbit; outside at the end means
		# it left, and the walk below finds when.
		var probe := from_tick
		var stride := maxi(1, turn / 64)
		while probe < from_tick + turn:
			if IntMath.dist_above(OrbitMath.position_at(orbit, probe), soi):
				break
			probe += stride
		if probe >= from_tick + turn:
			return [turn, "revolution"]
	var low := from_tick
	var high := from_tick + turn
	if IntMath.dist_above(OrbitMath.position_at(orbit, low), soi):
		return [0, "sphere"]
	while high - low > 1:
		var mid := (low + high) / 2
		if IntMath.dist_above(OrbitMath.position_at(orbit, mid), soi):
			high = mid
		else:
			low = mid
	return [high - from_tick, "sphere"]


# ------------------------------------------------------------------------------ burns

func _validate_cancel(ctx: SimContext, command: Dictionary) -> Dictionary:
	var burn: Variant = command["args"].get("burn")
	if typeof(burn) != TYPE_INT:
		return SimSystem.reject(REASON_MALFORMED)
	var unit: Dictionary = ctx.state["units"][command["unit"]]
	if unit["burn"].get("id", 0) == burn or unit["burns"].any(func(b: Dictionary) -> bool: return b["id"] == burn):
		return SimSystem.ok()
	return SimSystem.reject(REASON_INVALID)


func _cancel(ctx: SimContext, unit_id: int, burn_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	if unit["burn"].get("id", 0) == burn_id:
		_end(ctx, unit_id, REASON_CANCELLED)
		return
	unit["burns"] = unit["burns"].filter(func(b: Dictionary) -> bool: return b["id"] != burn_id)


func _start(ctx: SimContext, unit_id: int, planned: Dictionary) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var reason := ""
	var found := thruster(ctx, unit_id)
	if found.is_empty():
		reason = REASON_NO_THRUSTER
	elif not unit["dock"].is_empty():
		reason = REASON_NOT_FLYING
	elif unit["op"]["type"] != Units.IDLE_OP or not unit["route"].is_empty() or unit["task"] != 0:
		reason = REASON_BUSY
	if reason != "":
		ctx.emit_event("burn_short", unit_id, {
			"burn": planned["id"], "reason": reason, "dv_um_s": 0, "propellant_g": 0 })
		return
	if not unit["landed"].is_empty():
		LowFlight.lift(ctx, unit_id)  # a burn on the ground is a lift-off (A19)
		_entered[unit_id] = true
	var here := Relative.sample(ctx, Relative.unit_track(ctx, unit_id), ctx.tick, true)
	var vector := vector_for(ctx, planned, here, ctx.tick, not unit["orbit"].is_empty())
	if not unit["orbit"].is_empty():
		LowFlight.enter(ctx, unit_id)  # powered flight is stepped (A55)
		_entered[unit_id] = true
	unit["burn"] = new_burn(planned, vector, ctx.tick, found["part"])
	unit["op"] = { "type": OP_BURNING, "target": 0, "part": found["part"], "start_tick": ctx.tick, "end_tick": 0 }
	unit["at_target"] = 0
	CargoSystem._clear_followers(ctx, unit_id)
	ctx.emit_event("burn_started", unit_id, { "burn": planned["id"] })


## One tick of thrust, if the thruster has power and the propellant is there.
func _thrust(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var burn: Dictionary = unit["burn"]
	if unit["op"]["type"] != OP_BURNING:
		_end(ctx, unit_id, REASON_BUSY)
		return
	var part: Dictionary = ctx.state["parts"].get(burn["thruster"], {})
	if part.is_empty() or part["fault"] != "":
		_end(ctx, unit_id, REASON_NO_THRUSTER)
		return
	if not Units.can_run(part):
		return
	var stats: Dictionary = Units.module_of(ctx.state, ctx.defs, burn["thruster"])["capabilities"][CAPABILITY]
	var here := Relative.sample(ctx, Relative.unit_track(ctx, unit_id), ctx.tick, true)
	var push := thrust_step(ctx, burn, stats, mass_of(ctx, unit_id), here, ctx.tick)
	var grams: int = push["grams"]
	if grams > Reservations.free_stock(ctx, unit_id, Travel.PROPELLANT):
		_end(ctx, unit_id, REASON_NO_PROPELLANT)
		return
	for axis in 3:
		unit["vel_um_s"][axis] += push["change"][axis]
	advance_burn(burn, push)
	if grams > 0:
		Reservations.claim_stock(ctx, unit_id, Travel.PROPELLANT, grams)
		ctx.record_delta(unit_id, self, { "kind": DELTA_PROPELLANT, "unit": unit_id, "grams": grams })
	if push["finished"]:
		_end(ctx, unit_id, "")


## A unit's mass now: its parts' from the unit index, which keeps it until they change, plus its
## inventory. The same as Units.unit_mass, without walking the parts each tick.
static func mass_of(ctx: SimContext, unit_id: int) -> int:
	return int(UnitIndex.of(ctx, unit_id)["installed_g"]) + Units.inventory_mass(ctx.state, unit_id)


## A running burn from a planned one, its direction from `vector`, starting at `tick` (A55).
static func new_burn(planned: Dictionary, vector: Array, tick: int, thruster_part: int) -> Dictionary:
	return {
		"id": planned.get("id", 0), "start_tick": tick, "dir_q30": OrbitMath.unit(vector),
		"dv_um_s": IntMath.dist(vector, [0, 0, 0]), "done_um_s": 0, "thruster": thruster_part,
		"dv_remainder": 0, "flow_remainder": 0, "spent_g": 0,
		"throttle_ppm": planned.get("throttle_ppm", FULL_THROTTLE_PPM), "steer": planned.get("steer", STEER_FIXED),
		"target": planned.get("target", 0), "prograde_um_s": planned["prograde_um_s"],
		"normal_um_s": planned["normal_um_s"], "radial_um_s": planned["radial_um_s"],
	}


## One tick of a burn, from where the unit is (`here`, [place, r, v]): { change, dv_um_s, grams,
## dv_remainder, flow_remainder, finished }. Shared by the real burn and every flight ahead, so the
## two agree exactly. The direction comes from the steering; it turns at once, since ships have no
## facing yet (real_orbits.md section 7: orientation would limit the turn per tick here).
static func thrust_step(ctx: SimContext, burn: Dictionary, stats: Dictionary, mass_g: int, here: Array,
		tick: int) -> Dictionary:
	var throttled := stats.duplicate()
	throttled["thrust_n"] = IntMath.mul_div(stats["thrust_n"], burn.get("throttle_ppm", FULL_THROTTLE_PPM),
		FULL_THROTTLE_PPM)
	var step := _step(throttled, mass_g, burn)
	var dv: int = step["dv_um_s"]
	var grams: int = step["grams"]
	var direction: Array = burn["dir_q30"]
	var finished: bool = int(burn["done_um_s"]) + dv >= int(burn["dv_um_s"])
	match burn.get("steer", STEER_FIXED):
		STEER_ORBIT:
			direction = OrbitMath.unit(_along(_basis_here(ctx, here, tick), burn))
		STEER_TARGET, STEER_TARGET_RETROGRADE:
			var there := Relative.sample(ctx, Relative.thing_track(ctx, burn["target"]), tick, true)
			var seen := Relative.describe(ctx, here, there, tick)
			if burn["steer"] == STEER_TARGET:
				direction = OrbitMath.unit(seen["rel_pos_mm"])
			else:
				direction = OrbitMath.unit(seen["rel_vel_um_s"])
				var left: int = seen["speed_um_s"]
				if dv >= left:
					grams = IntMath.mul_div_ceil(grams, left, maxi(1, dv))
					dv = left
					finished = true
	if direction == [0, 0, 0]:
		direction = burn["dir_q30"]
	var change: Array[int] = []
	for axis in 3:
		change.append(OrbitMath.smul_div(direction[axis], dv, OrbitMath.ONE))
	return { "change": change, "dv_um_s": dv, "grams": grams, "dv_remainder": step["dv_remainder"],
		"flow_remainder": step["flow_remainder"], "finished": finished }


## Books one tick's thrust on a running burn.
static func advance_burn(burn: Dictionary, push: Dictionary) -> void:
	burn["dv_remainder"] = push["dv_remainder"]
	burn["flow_remainder"] = push["flow_remainder"]
	burn["done_um_s"] = int(burn["done_um_s"]) + int(push["dv_um_s"])
	burn["spent_g"] = int(burn.get("spent_g", 0)) + int(push["grams"])


## The engine's least throttle, in parts per million of full thrust (B29's min_throttle_ppm; an
## engine without it fires only at full).
static func min_throttle_ppm(ctx: SimContext, part: int) -> int:
	var stats: Dictionary = Units.module_of(ctx.state, ctx.defs, part)["capabilities"].get(CAPABILITY, {})
	return int(stats.get("min_throttle_ppm", FULL_THROTTLE_PPM))


## One tick of a burn: thrust over mass in um/s^2, and the propellant flow, each with a carried
## remainder. Shared by the real burn and every flight ahead.
static func _step(stats: Dictionary, mass_g: int, burn: Dictionary) -> Dictionary:
	var accel := IntMath.mul_div(stats["thrust_n"], 1_000_000_000, mass_g)
	var full := Rate.amount(accel, burn["dv_remainder"])
	var flow := IntMath.mul_div(stats["thrust_n"], 1_000_000, stats["exhaust_mm_s"])
	var full_g := Rate.amount(flow, burn["flow_remainder"])
	var dv := mini(full, burn["dv_um_s"] - burn["done_um_s"])
	return {
		"dv_um_s": dv, "grams": full_g if dv == full else IntMath.mul_div_ceil(full_g, dv, maxi(1, full)),
		"dv_remainder": Rate.carry(accel, burn["dv_remainder"]),
		"flow_remainder": Rate.carry(flow, burn["flow_remainder"]),
	}


## Ends the running burn. A reason makes it short; "" means it delivered its whole delta-v. An
## operation that replaced `burning` is left as it is.
func _end(ctx: SimContext, unit_id: int, reason: String) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var burn: Dictionary = unit["burn"]
	var data := { "burn": burn["id"], "dv_um_s": burn["done_um_s"], "propellant_g": burn.get("spent_g", 0) }
	if reason == "":
		ctx.emit_event("burn_done", unit_id, data)
	else:
		data["reason"] = reason
		ctx.emit_event("burn_short", unit_id, data)
	unit["burn"] = {}
	if unit["op"]["type"] == OP_BURNING:
		unit["op"] = { "type": Units.IDLE_OP, "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 }


## A planned burn's velocity change in um/s, from its prograde, normal and radial parts in the
## basis where the unit is (`here`, [place, r, v]). On an orbit (`on_orbit`) that is the orbit's own;
## in stepped flight or landed, LowFlight.basis_at; in a frame, the frame's orbit's; in the old
## world, fixed axes.
static func vector_for(ctx: SimContext, planned: Dictionary, here: Array, tick: int, on_orbit: bool) -> Array[int]:
	var basis: Array = LowFlight.state_basis(here[1], here[2]) if on_orbit else _basis_here(ctx, here, tick)
	return _along(basis, planned)


static func _along(basis: Array, planned: Dictionary) -> Array[int]:
	var vector: Array[int] = []
	for axis in 3:
		vector.append(OrbitMath.smul_div(planned["prograde_um_s"], basis[0][axis], OrbitMath.ONE)
			+ OrbitMath.smul_div(planned["normal_um_s"], basis[1][axis], OrbitMath.ONE)
			+ OrbitMath.smul_div(planned["radial_um_s"], basis[2][axis], OrbitMath.ONE))
	return vector


## [prograde, normal, radial] where a unit is that isn't on an orbit record.
static func _basis_here(ctx: SimContext, here: Array, tick: int) -> Array:
	var place: int = here[0]
	if ctx.state["frames"].has(place):
		return orbit_basis(ctx, ctx.state["frames"][place]["orbit"], tick)
	if place == 0 or not ctx.state["bodies"].has(place):
		return OLD_WORLD_BASIS
	return LowFlight.basis_at(ctx, place, here[1], here[2])


## [prograde, normal, radial out] on an orbit at a tick, in Q30.
static func orbit_basis(ctx: SimContext, orbit: Dictionary, tick: int) -> Array:
	var now := OrbitMath.state_at(orbit, ctx.state["bodies"][orbit["parent"]]["gm"], tick)
	var prograde := OrbitMath.unit(now["v"])
	var normal := OrbitMath.unit(OrbitMath.cross(OrbitMath.unit(now["r"]), prograde))
	return [prograde, normal, OrbitMath.cross(prograde, normal)]


## What check shows for a planned burn. On an orbit, in stepped flight or landed it flies the burn
## from now, alone, through the same steps as the real one (FlightAhead), assuming the thruster has
## power throughout. In a frame, or past MAX_PREVIEW_TICKS, it is one impulse. `path` (A57) is the
## flown path through the burn and one turn after, as predict gives points.
static func _preview(ctx: SimContext, unit_id: int, args: Dictionary, found: Dictionary) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var here := Relative.sample(ctx, Relative.unit_track(ctx, unit_id), ctx.state["tick"], true)
	var on_orbit: bool = not unit["orbit"].is_empty()
	if on_orbit:
		var orbit: Dictionary = unit["orbit"]
		var at := OrbitMath.state_at(orbit, ctx.state["bodies"][orbit["parent"]]["gm"], args["tick"])
		here = [orbit["parent"], at["r"], at["v"]]
	var planned := planned_record(0, args)
	var vector := vector_for(ctx, planned, here, args["tick"], on_orbit)
	var dv := IntMath.dist(vector, [0, 0, 0])
	var mass_g := Units.unit_mass(ctx.state, ctx.defs, unit_id)
	var thrust := IntMath.mul_div(found["thrust_n"], planned["throttle_ppm"], FULL_THROTTLE_PPM)
	var detail := {
		"dv_um_s": dv,
		"propellant_g": OrbitMath.burn_g(mass_g, dv, found["exhaust_mm_s"]),
		"burn_ticks": IntMath.mul_div_ceil(dv, mass_g * Sim.TICKS_PER_SECOND, maxi(1, thrust) * 1_000_000_000),
		"orbit": {}, "vel_um_s": unit["vel_um_s"].duplicate(), "leaves_frame": false,
	}
	if not on_orbit and unit["stepped"] == 0 and unit["landed"].is_empty():
		for axis in 3:
			detail["vel_um_s"][axis] += vector[axis]
		detail["leaves_frame"] = unit["frame"] != 0 and detail["vel_um_s"] != [0, 0, 0]
		return detail
	if int(detail["burn_ticks"]) > MAX_PREVIEW_TICKS:
		var gm: int = ctx.state["bodies"][here[0]]["gm"]
		var after := OrbitMath.from_state(here[1], LowFlight._add(here[2], vector, 1), gm, args["tick"])
		if not after.is_empty():
			after["parent"] = here[0]
			add_apsides(after, after, args["tick"])
		detail["orbit"] = after
		detail["approximate"] = true
		return detail
	var flown := _fly_candidate(ctx, unit_id, args, -1)
	if flown.is_empty():
		return detail
	var record: Dictionary = {}
	for entry: Dictionary in flown["burns"]:
		if entry["id"] == 0:
			record = entry
	if not record.is_empty():
		detail["propellant_g"] = record["propellant_g"]
		detail["dv_um_s"] = record["dv_um_s"]
		var end_tick: int = record["end_tick"]
		detail["burn_ticks"] = maxi(0, end_tick - int(record["start_tick"]) + 1) if end_tick >= 0 else MAX_PREVIEW_TICKS
		if record["reason"] != "":
			detail["short"] = record["reason"]
		if end_tick >= 0 and (flown["contact"].is_empty() or int(flown["contact"]["tick"]) > end_tick):
			var at := FlightAhead.sample(ctx, flown["segments"], end_tick, true)
			var gm: int = ctx.state["bodies"][at[0]]["gm"]
			var after := OrbitMath.from_state(at[1], at[2], gm, end_tick)
			if not after.is_empty():
				after["parent"] = at[0]
				add_apsides(after, after, end_tick)
			detail["orbit"] = after
	if not flown["contact"].is_empty():
		detail["contact"] = flown["contact"]
	detail["path"] = _path_of(ctx, unit_id, flown)
	return detail


## A flight as predict's points, at most PATH_POINTS of them, from now to its end.
static func _path_of(ctx: SimContext, unit_id: int, flown: Dictionary) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var now: int = ctx.state["tick"]
	var last: int = flown["end_tick"]
	if not flown["contact"].is_empty():
		last = mini(last, int(flown["contact"]["tick"]))
	var step := maxi(1, IntMath.mul_div_ceil(last - now, 1, PATH_POINTS))
	var place_id: int = unit["stepped"] if unit["stepped"] != 0 else (unit["landed"]["body"]
		if not unit["landed"].is_empty() else unit["orbit"]["parent"])
	var points: Array = []
	var world: Array = []
	for t in range(now, last + 1, step):
		_add_point(ctx, flown["segments"], t, place_id, points, world)
	if (last - now) % step != 0:
		_add_point(ctx, flown["segments"], last, place_id, points, world)
	var place := { "stepped": place_id } if unit["stepped"] != 0 else ({ "landed": place_id }
		if not unit["landed"].is_empty() else { "orbit_parent": place_id })
	return { "place": place, "points": points, "world_points": world, "step": step,
		"ended": "ground" if not flown["contact"].is_empty() else "ticks", "contact": flown["contact"] }


# ------------------------------------------------------------------------------ drift and frames

## Straight-line drift inside a frame, then leaving it past the margin.
func _drift(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var vel: Array = unit["vel_um_s"]
	if vel == [0, 0, 0]:
		return
	var carry: Array = unit["drift_carry"]
	for axis in 3:
		var total: int = carry[axis] + vel[axis]
		var moved := _floor_div(total, DRIFT_PER_MM)
		unit["pos_mm"][axis] += moved
		carry[axis] = total - moved * DRIFT_PER_MM
	var frame_id: int = unit["frame"]
	if frame_id == 0:
		return
	var frame: Dictionary = ctx.state["frames"][frame_id]
	if IntMath.dist(vel, [0, 0, 0]) > LEAVE_SPEED_UM_S \
			or IntMath.dist(unit["pos_mm"], [0, 0, 0]) > frame["radius_mm"] + leave_margin_mm(ctx, frame):
		_leave(ctx, unit_id, frame_id)


## How far past its radius a drifting unit leaves a frame: LEAVE_MARGIN_MM, or less, so the leave
## point stays inside the parent's sphere of influence with as much room again to spare. The room is
## the SOI less the frame's apoapsis and radius, halved, and never under MIN_LEAVE_MARGIN_MM.
static func leave_margin_mm(ctx: SimContext, frame: Dictionary) -> int:
	var soi: int = ctx.state["bodies"][frame["orbit"]["parent"]].get("soi_mm", 0)
	if soi <= 0:
		return LEAVE_MARGIN_MM
	var room := (soi - apoapsis_mm(frame["orbit"]) - int(frame["radius_mm"])) / 2
	return clampi(room, MIN_LEAVE_MARGIN_MM, LEAVE_MARGIN_MM)


## How far past its radius a unit on an orbit joins a frame: half the leave margin.
static func join_margin_mm(ctx: SimContext, frame: Dictionary) -> int:
	return leave_margin_mm(ctx, frame) / 2


## The farthest an elliptic orbit gets from its parent.
static func apoapsis_mm(orbit: Dictionary) -> int:
	return OrbitMath.smul_div(orbit["a_mm"], OrbitMath.ONE + int(orbit["e_q30"]), OrbitMath.ONE)


func _leave(ctx: SimContext, unit_id: int, frame_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var frame: Dictionary = ctx.state["frames"][frame_id]
	var parent: int = frame["orbit"]["parent"]
	var gm: int = ctx.state["bodies"][parent]["gm"]
	var carried := OrbitMath.state_at(frame["orbit"], gm, ctx.tick)
	var r: Array[int] = []
	var v: Array[int] = []
	for axis in 3:
		r.append(int(carried["r"][axis]) + int(unit["pos_mm"][axis]))
		v.append(int(carried["v"][axis]) + int(unit["vel_um_s"][axis]))
	var orbit := OrbitMath.from_state(r, v, gm, ctx.tick)
	if orbit.is_empty():
		return
	orbit["parent"] = parent
	unit["orbit"] = orbit
	unit["frame"] = 0
	unit["pos_mm"] = r
	unit["vel_um_s"] = [0, 0, 0]
	unit["drift_carry"] = [0, 0, 0]
	unit["at_target"] = 0
	ctx.emit_event("frame_left", unit_id, { "frame": frame_id })


## Joins the first frame, in ID order, that the unit is inside and nearly at rest in.
## `candidates` are [frame ID, join distance] for the frames round the unit's parent, by ID.
func _try_join(ctx: SimContext, unit_id: int, candidates: Array) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var orbit: Dictionary = unit["orbit"]
	var frames: Dictionary = ctx.state["frames"]
	for candidate: Array in candidates:
		var frame_id: int = candidate[0]
		var frame: Dictionary = frames[frame_id]
		# Positions are already this tick's, so test distance first and leave the dearer velocities
		# to the rare unit that is close (A17).
		var unit_mm: Array = unit["pos_mm"]
		var frame_mm: Array = frame["pos_mm"]
		var near := [unit_mm[0] - frame_mm[0], unit_mm[1] - frame_mm[1], unit_mm[2] - frame_mm[2]]
		var join_mm: int = candidate[1]
		if IntMath.dist_above(near, join_mm + JOIN_SLACK_MM):
			continue
		var gm: int = ctx.state["bodies"][orbit["parent"]]["gm"]
		var mine := OrbitMath.state_at(orbit, gm, ctx.tick)
		var theirs := OrbitMath.state_at(frame["orbit"], gm, ctx.tick)
		var local: Array[int] = []
		var rel_v: Array[int] = []
		for axis in 3:
			local.append(int(mine["r"][axis]) - int(theirs["r"][axis]))
			rel_v.append(int(mine["v"][axis]) - int(theirs["v"][axis]))
		if IntMath.dist(local, [0, 0, 0]) > join_mm:
			continue
		if IntMath.dist(rel_v, [0, 0, 0]) >= JOIN_SPEED_UM_S:
			continue
		unit["orbit"] = {}
		unit["frame"] = frame_id
		unit["pos_mm"] = local
		unit["vel_um_s"] = rel_v
		unit["drift_carry"] = [0, 0, 0]
		ctx.emit_event("frame_joined", unit_id, { "frame": frame_id })
		return


## Moves a unit's orbit to a new parent body if it has crossed a sphere of influence this tick.
## Checked every tick, so the change happens on the first tick past the boundary, whatever the speed.
## `children` are the IDs of the parent's children with a sphere, ascending.
func _cross_soi(ctx: SimContext, unit_id: int, children: Array) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var bodies: Dictionary = ctx.state["bodies"]
	var parent_id: int = unit["orbit"]["parent"]
	var parent: Dictionary = bodies[parent_id]
	var pos: Array = unit["pos_mm"]
	if parent.get("soi_mm", 0) > 0 and not parent["orbit"].is_empty() \
			and IntMath.dist_above(pos, parent.get("soi_mm", 0)):
		var up: int = parent["orbit"]["parent"]
		var carried := OrbitMath.state_at(parent["orbit"], bodies[up]["gm"], ctx.tick)
		_rebase(ctx, unit_id, up, carried, 1)
		return
	for child_id: int in children:
		var child: Dictionary = bodies[child_id]
		var gap: Array = child["pos_mm"]
		if IntMath.dist_below([pos[0] - gap[0], pos[1] - gap[1], pos[2] - gap[2]], child["soi_mm"]):
			_rebase(ctx, unit_id, child_id, OrbitMath.state_at(child["orbit"], parent["gm"], ctx.tick), -1)
			return


## Re-expresses the unit's orbit around new_parent, given the old and new parents' relative state.
## sign is 1 going up a level (add the old parent's motion) and -1 going down (take the child's away).
func _rebase(ctx: SimContext, unit_id: int, new_parent: int, between: Dictionary, sign: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var old_parent: int = unit["orbit"]["parent"]
	var gm_old: int = ctx.state["bodies"][old_parent]["gm"]
	var mine := OrbitMath.state_at(unit["orbit"], gm_old, ctx.tick)
	var r: Array[int] = []
	var v: Array[int] = []
	for axis in 3:
		r.append(int(mine["r"][axis]) + sign * int(between["r"][axis]))
		v.append(int(mine["v"][axis]) + sign * int(between["v"][axis]))
	var orbit := OrbitMath.from_state(r, v, ctx.state["bodies"][new_parent]["gm"], ctx.tick)
	if orbit.is_empty():
		return
	orbit["parent"] = new_parent
	unit["orbit"] = orbit
	unit["pos_mm"] = r
	ctx.emit_event("soi_changed", unit_id, { "from": old_parent, "to": new_parent })


## Division rounding towards minus infinity, so drift steps the same either way along an axis.
static func _floor_div(a: int, b: int) -> int:
	var q := a / b
	return q - 1 if (a % b != 0) and ((a < 0) != (b < 0)) else q


func _sorted(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids
