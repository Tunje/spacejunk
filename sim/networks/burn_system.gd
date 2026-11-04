class_name BurnSystem
extends SimSystem
## Burns, drift and frame changes (orbital_flight.md section 11, task A11). A burn is the only thing
## that changes an orbit: the player places burns on their own ship, and later a core's autopilot
## places the same burns for the ship it flies.
##
## A burn starts in phase 2 of its tick, fixing its direction from that tick's orbit, and holds the
## unit's operation as `burning` with the thruster as a power and heat load. From phase 5 of the same
## tick it delivers thrust / mass each tick until its delta-v is done or the propellant runs out.
## - On an orbit, each tick's delta-v makes a new orbit through OrbitMath.from_state.
## - In a frame, it changes the unit's local velocity, and the unit drifts in a straight line. A
##   drifting unit leaves the frame for an orbit past LEAVE_MARGIN_MM beyond the frame's radius.
## - A unit on an orbit joins a frame within JOIN_MARGIN_MM of its radius at under JOIN_SPEED_UM_S.
##   The two margins differ so a slow unit at the edge cannot flap in and out.
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
const CAPABILITY := "thruster"
const MAX_DV_UM_S := 1_000_000_000_000
## Near escape speed lies a band of orbits OrbitMath can't hold: exactly parabolic, or ellipses far
## larger than any sphere of influence. A burn crossing it carries each tick's change forward until
## the sum lands outside the band, up to this much, rather than stopping just short of escape.
const MAX_HELD_UM_S := 50_000_000
## check flies a planned burn tick by tick, as the real one will be, for up to this many ticks.
## A longer burn is previewed as one impulse, marked `approximate`.
const MAX_PREVIEW_TICKS := 20_000
const JOIN_MARGIN_MM := 1_000_000_000
const LEAVE_MARGIN_MM := 2_000_000_000
const JOIN_SPEED_UM_S := 1_000_000
## Drift is carried in tenths of a micrometre: velocity in um/s over a tenth of a second.
const DRIFT_PER_MM := 10_000
const MAX_PREDICT_POINTS := 10_000
## Axes for a burn in the old world, which has no orbit to take them from.
const OLD_WORLD_BASIS := [[1 << 30, 0, 0], [0, 1 << 30, 0], [0, 0, 1 << 30]]


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
	if not ctx.state["units"][unit_id]["dock"].is_empty() or not ctx.state["units"][unit_id]["landed"].is_empty():
		return SimSystem.reject(REASON_NOT_FLYING)
	if args["tick"] <= ctx.state["tick"]:
		return SimSystem.reject(REASON_IN_PAST)
	var parts := [args["prograde_um_s"], args["normal_um_s"], args["radial_um_s"]]
	if parts == [0, 0, 0] or parts.any(func(v: int) -> bool: return absi(v) > MAX_DV_UM_S):
		return SimSystem.reject(REASON_MALFORMED)
	var found := thruster(ctx, unit_id)
	if found.is_empty():
		return SimSystem.reject(REASON_NO_THRUSTER)
	var result := SimSystem.ok()
	result["detail"] = _preview(ctx, unit_id, args, found)
	return result


func apply(ctx: SimContext, command: Dictionary) -> void:
	var unit: Dictionary = ctx.state["units"][command["unit"]]
	var args: Dictionary = command["args"]
	if command["type"] == CANCEL:
		_cancel(ctx, command["unit"], args["burn"])
		return
	unit["burns"].append({
		"id": ctx.new_id(), "tick": args["tick"], "prograde_um_s": args["prograde_um_s"],
		"normal_um_s": args["normal_um_s"], "radial_um_s": args["radial_um_s"],
	})
	unit["burns"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["tick"] < b["tick"] or (a["tick"] == b["tick"] and a["id"] < b["id"]))


## Phase 2: start each burn whose tick has come.
func update_tasks(ctx: SimContext) -> void:
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		var unit: Dictionary = units[id]
		if unit["burn"].is_empty() and not unit["burns"].is_empty() and unit["burns"][0]["tick"] <= ctx.tick:
			_start(ctx, id, unit["burns"].pop_front())


## Phase 5: thrust, then drift, then frame changes.
func run(ctx: SimContext) -> void:
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		if not units[id]["burn"].is_empty():
			_thrust(ctx, id)
	for id: int in _sorted(units):
		var unit: Dictionary = units[id]
		if not unit["dock"].is_empty() or not unit["route"].is_empty() or not unit["transfer"].is_empty():
			continue
		if unit["orbit"].is_empty():
			_drift(ctx, id)
		else:
			_cross_soi(ctx, id)
			_try_join(ctx, id)


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
		shown["burns"] = unit["burns"].duplicate(true)
		var burn: Dictionary = unit["burn"]
		shown["burn"] = {} if burn.is_empty() else {
			"id": burn["id"], "dv_um_s": burn["dv_um_s"], "done_um_s": burn["done_um_s"],
			"start_tick": burn["start_tick"],
		}


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


## Positions along a unit's current path, ignoring planned burns, as { place, points }: relative to
## the orbit's parent body, or local to the unit's frame. {} if the request is out of range.
static func predict(ctx: SimContext, unit_id: int, from_tick: int, ticks: int, step: int) -> Dictionary:
	if not ctx.state["units"].has(unit_id) or step < 1 or ticks < 0 or ticks / step >= MAX_PREDICT_POINTS:
		return {}
	var unit: Dictionary = ctx.state["units"][unit_id]
	if not unit["dock"].is_empty():
		return predict(ctx, unit["dock"]["target_unit"], from_tick, ticks, step)
	var points: Array = []
	var orbit: Dictionary = unit["orbit"]
	for t in range(from_tick, from_tick + ticks + 1, step):
		if not orbit.is_empty():
			points.append(OrbitMath.position_at(orbit, t))
		else:
			var dt: int = t - int(ctx.state["tick"])
			var point: Array[int] = []
			for axis in 3:
				point.append(int(unit["pos_mm"][axis]) + OrbitMath.smul_div(unit["vel_um_s"][axis], dt,
					Sim.TICKS_PER_SECOND * 1000))
			points.append(point)
	var place := { "orbit_parent": orbit["parent"] } if not orbit.is_empty() else { "frame": unit["frame"] }
	if not unit["landed"].is_empty():
		place = { "landed": unit["landed"]["body"] }
	return { "place": place, "points": points }


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
	elif not unit["dock"].is_empty() or not unit["landed"].is_empty():
		reason = REASON_NOT_FLYING
	elif unit["op"]["type"] != Units.IDLE_OP or not unit["route"].is_empty() or unit["task"] != 0:
		reason = REASON_BUSY
	if reason != "":
		ctx.emit_event("burn_short", unit_id, {
			"burn": planned["id"], "reason": reason, "dv_um_s": 0, "propellant_g": 0 })
		return
	var vector := _burn_vector(ctx, unit_id, planned, ctx.tick)
	var dv := IntMath.dist(vector, [0, 0, 0])
	unit["burn"] = {
		"id": planned["id"], "start_tick": ctx.tick, "dir_q30": OrbitMath.unit(vector), "dv_um_s": dv,
		"done_um_s": 0, "thruster": found["part"], "dv_remainder": 0, "flow_remainder": 0,
		"held_um_s": [0, 0, 0],
	}
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
	var step := _step(stats, Units.unit_mass(ctx.state, ctx.defs, unit_id), burn)
	var dv: int = step["dv_um_s"]
	var grams: int = step["grams"]
	if grams > Reservations.free_stock(ctx, unit_id, Travel.PROPELLANT):
		_end(ctx, unit_id, REASON_NO_PROPELLANT)
		return
	var change: Array[int] = []
	for axis in 3:
		change.append(OrbitMath.smul_div(burn["dir_q30"][axis], dv, OrbitMath.ONE))
	if not _change_velocity(ctx, unit_id, change):
		_end(ctx, unit_id, REASON_ESCAPE)
		return
	burn["dv_remainder"] = step["dv_remainder"]
	burn["flow_remainder"] = step["flow_remainder"]
	if grams > 0:
		Reservations.claim_stock(ctx, unit_id, Travel.PROPELLANT, grams)
		ctx.record_delta(unit_id, self, { "kind": DELTA_PROPELLANT, "unit": unit_id, "grams": grams })
	burn["done_um_s"] += dv
	burn["spent_g"] = burn.get("spent_g", 0) + grams
	if burn["done_um_s"] >= burn["dv_um_s"]:
		var held: int = IntMath.dist(burn["held_um_s"], [0, 0, 0])
		if held > 0:
			# It finished inside the band: the change still held could not be delivered.
			burn["done_um_s"] -= held
			_end(ctx, unit_id, REASON_ESCAPE)
		else:
			_end(ctx, unit_id, "")


## One tick of a burn: thrust over mass in um/s^2, and the propellant flow, each with a carried
## remainder. Shared by the real burn and check's preview, so the two give the same orbit.
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


## A velocity change on an orbit, with any change held from earlier ticks, as { orbit, held }:
## the new orbit, or the same orbit and a larger held change inside the band near escape. {} once
## the held change passes MAX_HELD_UM_S.
static func _apply(ctx: SimContext, orbit: Dictionary, tick: int, change: Array, held: Array) -> Dictionary:
	var total: Array[int] = []
	for axis in 3:
		total.append(int(change[axis]) + int(held[axis]))
	var gm: int = ctx.state["bodies"][orbit["parent"]]["gm"]
	var now := OrbitMath.state_at(orbit, gm, tick)
	var v: Array = now["v"]
	var after := OrbitMath.from_state(now["r"], [v[0] + total[0], v[1] + total[1], v[2] + total[2]], gm, tick)
	if after.is_empty():
		if IntMath.dist(total, [0, 0, 0]) > MAX_HELD_UM_S:
			return {}
		return { "orbit": orbit, "held": total }
	after["parent"] = orbit["parent"]
	return { "orbit": after, "held": [0, 0, 0] }


## Adds a velocity change in um/s, with any change held from earlier ticks. Inside the band near
## escape it holds the change for later instead. False once the held change passes MAX_HELD_UM_S.
func _change_velocity(ctx: SimContext, unit_id: int, change: Array) -> bool:
	var unit: Dictionary = ctx.state["units"][unit_id]
	if unit["orbit"].is_empty():
		for axis in 3:
			unit["vel_um_s"][axis] += change[axis]
		return true
	var result := _apply(ctx, unit["orbit"], ctx.tick, change, unit["burn"]["held_um_s"])
	if result.is_empty():
		return false
	unit["orbit"] = result["orbit"]
	unit["burn"]["held_um_s"] = result["held"]
	return true


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


## The burn's velocity change in um/s, from prograde, normal and radial along the unit's orbit at
## a tick. A unit in a frame takes the frame's orbit, and the old world takes fixed axes.
static func _burn_vector(ctx: SimContext, unit_id: int, planned: Dictionary, tick: int) -> Array[int]:
	var basis := _basis(ctx, unit_id, tick)
	var vector: Array[int] = []
	for axis in 3:
		vector.append(OrbitMath.smul_div(planned["prograde_um_s"], basis[0][axis], OrbitMath.ONE)
			+ OrbitMath.smul_div(planned["normal_um_s"], basis[1][axis], OrbitMath.ONE)
			+ OrbitMath.smul_div(planned["radial_um_s"], basis[2][axis], OrbitMath.ONE))
	return vector


## [prograde, normal, radial out] unit vectors in Q30.
static func _basis(ctx: SimContext, unit_id: int, tick: int) -> Array:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var orbit: Dictionary = unit["orbit"]
	if orbit.is_empty() and unit["frame"] != 0:
		orbit = ctx.state["frames"][unit["frame"]]["orbit"]
	if orbit.is_empty():
		return OLD_WORLD_BASIS
	var now := OrbitMath.state_at(orbit, ctx.state["bodies"][orbit["parent"]]["gm"], tick)
	var prograde := OrbitMath.unit(now["v"])
	var normal := OrbitMath.unit(OrbitMath.cross(OrbitMath.unit(now["r"]), prograde))
	return [prograde, normal, OrbitMath.cross(prograde, normal)]


## What check shows for a planned burn. On an orbit it flies the burn tick by tick from its tick,
## through the same _step and _apply as the real one, assuming the thruster has power throughout.
## In a frame, or past MAX_PREVIEW_TICKS, it is one impulse.
static func _preview(ctx: SimContext, unit_id: int, args: Dictionary, found: Dictionary) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var vector := _burn_vector(ctx, unit_id, args, args["tick"])
	var dv := IntMath.dist(vector, [0, 0, 0])
	var mass_g := Units.unit_mass(ctx.state, ctx.defs, unit_id)
	var detail := {
		"dv_um_s": dv,
		"propellant_g": OrbitMath.burn_g(mass_g, dv, found["exhaust_mm_s"]),
		"burn_ticks": IntMath.mul_div_ceil(dv, mass_g * Sim.TICKS_PER_SECOND, found["thrust_n"] * 1_000_000_000),
		"orbit": {}, "vel_um_s": unit["vel_um_s"].duplicate(), "leaves_frame": false,
	}
	var orbit: Dictionary = unit["orbit"]
	if orbit.is_empty():
		for axis in 3:
			detail["vel_um_s"][axis] += vector[axis]
		detail["leaves_frame"] = unit["frame"] != 0 and detail["vel_um_s"] != [0, 0, 0]
		return detail
	if detail["burn_ticks"] <= MAX_PREVIEW_TICKS:
		return _fly_preview(ctx, orbit, vector, dv, mass_g, args["tick"], found, detail)
	var gm: int = ctx.state["bodies"][orbit["parent"]]["gm"]
	var at := OrbitMath.state_at(orbit, gm, args["tick"])
	var v: Array = at["v"]
	var after := OrbitMath.from_state(at["r"], [v[0] + vector[0], v[1] + vector[1], v[2] + vector[2]], gm, args["tick"])
	if not after.is_empty():
		after["parent"] = orbit["parent"]
	detail["orbit"] = after
	detail["approximate"] = true
	return detail


static func _fly_preview(ctx: SimContext, orbit: Dictionary, vector: Array, dv: int, mass_g: int,
		tick: int, found: Dictionary, detail: Dictionary) -> Dictionary:
	var stats: Dictionary = Units.module_of(ctx.state, ctx.defs, found["part"])["capabilities"][CAPABILITY]
	var direction := OrbitMath.unit(vector)
	var burn := { "dv_um_s": dv, "done_um_s": 0, "dv_remainder": 0, "flow_remainder": 0 }
	var held: Array = [0, 0, 0]
	var spent := 0
	var ticks := 0
	while burn["done_um_s"] < dv:
		var step := _step(stats, mass_g - spent, burn)
		var change: Array[int] = []
		for axis in 3:
			change.append(OrbitMath.smul_div(direction[axis], step["dv_um_s"], OrbitMath.ONE))
		var result := _apply(ctx, orbit, tick + ticks, change, held)
		if result.is_empty():
			detail["orbit"] = {}
			return detail
		orbit = result["orbit"]
		held = result["held"]
		burn["dv_remainder"] = step["dv_remainder"]
		burn["flow_remainder"] = step["flow_remainder"]
		burn["done_um_s"] += step["dv_um_s"]
		spent += step["grams"]
		ticks += 1
	detail["orbit"] = orbit if held == [0, 0, 0] else {}
	detail["propellant_g"] = spent
	detail["burn_ticks"] = ticks
	return detail


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
	if IntMath.dist(unit["pos_mm"], [0, 0, 0]) > frame["radius_mm"] + LEAVE_MARGIN_MM:
		_leave(ctx, unit_id, frame_id)


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
func _try_join(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var orbit: Dictionary = unit["orbit"]
	var frames: Dictionary = ctx.state["frames"]
	for frame_id: int in _sorted(frames):
		var frame: Dictionary = frames[frame_id]
		if frame["orbit"]["parent"] != orbit["parent"]:
			continue
		var gm: int = ctx.state["bodies"][orbit["parent"]]["gm"]
		var mine := OrbitMath.state_at(orbit, gm, ctx.tick)
		var theirs := OrbitMath.state_at(frame["orbit"], gm, ctx.tick)
		var local: Array[int] = []
		var rel_v: Array[int] = []
		for axis in 3:
			local.append(int(mine["r"][axis]) - int(theirs["r"][axis]))
			rel_v.append(int(mine["v"][axis]) - int(theirs["v"][axis]))
		if IntMath.dist(local, [0, 0, 0]) > frame["radius_mm"] + JOIN_MARGIN_MM:
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
func _cross_soi(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var bodies: Dictionary = ctx.state["bodies"]
	var parent_id: int = unit["orbit"]["parent"]
	var parent: Dictionary = bodies[parent_id]
	var pos: Array = unit["pos_mm"]
	if parent.get("soi_mm", 0) > 0 and not parent["orbit"].is_empty() \
			and IntMath.dist(pos, [0, 0, 0]) > parent.get("soi_mm", 0):
		var up: int = parent["orbit"]["parent"]
		var carried := OrbitMath.state_at(parent["orbit"], bodies[up]["gm"], ctx.tick)
		_rebase(ctx, unit_id, up, carried, 1)
		return
	for child_id: int in _sorted(bodies):
		var child: Dictionary = bodies[child_id]
		if child.get("soi_mm", 0) <= 0 or child["orbit"].get("parent", 0) != parent_id:
			continue
		var gap: Array = child["pos_mm"]
		if IntMath.dist([pos[0] - gap[0], pos[1] - gap[1], pos[2] - gap[2]], [0, 0, 0]) < child["soi_mm"]:
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
