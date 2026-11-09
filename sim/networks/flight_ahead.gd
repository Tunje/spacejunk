class_name FlightAhead
extends RefCounted
## One unit's flight played ahead on a copy of its own motion (real_orbits.md section 4.2, tasks
## A55 and A57). Bodies and other units are on rails and known at every tick, so only this unit is
## moved. Each tick does what the simulation does to it, in the same order and through the same
## functions: a planned burn starts in phase 2, converting an orbit to stepped flight or lifting off
## the ground; in phase 5 a stepped unit is moved (LowFlight.advance), meets the ground or crosses a
## sphere, then thrusts (BurnSystem.thrust_step), then goes back onto an orbit once it coasts above
## the ground's reach. So check, predict, relative and the view's surface contact are the flight.
##
## Two things are assumed, as check always has: the engine has power throughout, and the unit
## isn't given other orders. A coasting orbit's sphere crossings and frame joins are not played
## (the unit stays on its orbit); stepped flight's sphere crossings are.
##
## Coasting on an orbit is skipped in one jump to the next burn, or to where the orbit comes
## within the ground's reach, found by bisection between apoapsis and periapsis.
##
## The result is { segments, burns, contact, end_tick, ended, final }:
## - segments: [from_tick, entry] in tick order, each valid from its tick to the next one's. An
##   entry is an orbit record; { stepped: body, states: PackedInt64Array } with STRIDE values
##   per tick from from_tick (pos, vel, carry, vcarry); or { landed: body, pos }. Each tick's state
##   is the unit's after that tick.
## - burns: [{ id, start_tick, end_tick, dv_um_s, done_um_s, propellant_g, reason }]: reason ""
##   when it delivered its delta-v, otherwise why it stopped.
## - contact: { tick, cell, speed_um_s, outcome } where it met the ground, or {}.
## - ended: "horizon", "contact" or "burns_done" (with stop_after_burns).
## - final: the motion at end_tick: { orbit } or { stepped, pos, vel } or { landed, pos }.

const STRIDE := 12
const SUPPORTED := ["rails", "stepped", "landed"]


## Plays the unit ahead from the current tick to until_tick. `burns` are planned-burn records
## ({ id, tick, prograde_um_s, normal_um_s, radial_um_s, throttle_ppm, steer, target }), flown in
## tick order. With `running`, a burn already running carries on first. With stop_after_burns it
## stops on the first tick after the last burn ends at which the unit is back on an orbit, or
## landed. {} if the unit is docked, on a route or transfer, or in a frame.
static func fly(ctx: SimContext, unit_id: int, burns: Array, until_tick: int, running: bool = true,
		stop_after_burns: bool = false) -> Dictionary:
	var unit: Dictionary = ctx.state["units"][unit_id]
	if not unit["dock"].is_empty() or not unit["route"].is_empty() or not unit["transfer"].is_empty():
		return {}
	var now: int = ctx.state["tick"]
	var s := {}
	if unit["stepped"] != 0:
		s = { "mode": "stepped", "body": unit["stepped"], "pos": unit["pos_mm"].duplicate(),
			"vel": unit["vel_um_s"].duplicate(), "carry": unit["drift_carry"].duplicate(),
			"vcarry": unit.get("vel_carry_nm", [0, 0, 0]).duplicate() }
	elif not unit["landed"].is_empty():
		s = { "mode": "landed", "body": unit["landed"]["body"], "pos": unit["pos_mm"].duplicate() }
	elif not unit["orbit"].is_empty():
		s = { "mode": "rails", "orbit": unit["orbit"] }
	else:
		return {}
	var found := BurnSystem.thruster(ctx, unit_id)
	var stats: Dictionary = {} if found.is_empty() else \
		Units.module_of(ctx.state, ctx.defs, found["part"])["capabilities"][BurnSystem.CAPABILITY]
	var mass_g := BurnSystem.mass_of(ctx, unit_id)
	# What each propellant item has left, as the burn spends it in its engine's mixture (A61).
	var mixture: Dictionary = Propellant.LEGACY if found.is_empty() else Propellant.mixture_of_part(ctx, found["part"])
	var left := {}
	for item: String in Propellant.items_of(mixture):
		left[item] = Reservations.free_stock(ctx, unit_id, item)
	var queue: Array = burns.duplicate(true)
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["tick"] < b["tick"] or (a["tick"] == b["tick"] and a.get("id", 0) < b.get("id", 0)))
	var burn: Dictionary = unit["burn"].duplicate(true) if running and not unit["burn"].is_empty() else {}
	var out := { "segments": [], "burns": [], "contact": {}, "end_tick": now, "ended": "horizon", "final": {} }
	var record: Dictionary = {} if burn.is_empty() else _burn_record(burn, burn["start_tick"])
	_open_segment(out, s, now)
	if s["mode"] == "stepped":
		_record(out, s, now)
	var memo := {}
	var t := now + 1
	while t <= until_tick:
		# Coasting on an orbit with nothing to do: jump to the next burn or the ground's reach.
		if s["mode"] == "rails" and burn.is_empty():
			var next_burn: int = queue[0]["tick"] if not queue.is_empty() else until_tick + 1
			var reach := _reach_tick(ctx, s["orbit"], t, mini(next_burn, until_tick + 1))
			var jump_to := mini(mini(next_burn, reach), until_tick + 1)
			if jump_to > t:
				t = jump_to
				if t > until_tick:
					break
		var entered := false
		# Phase 2: a planned burn starts.
		if burn.is_empty() and not queue.is_empty() and int(queue[0]["tick"]) <= t:
			var planned: Dictionary = queue.pop_front()
			if found.is_empty():
				out["burns"].append({ "id": planned.get("id", 0), "start_tick": t, "end_tick": t - 1, "dv_um_s": 0,
					"done_um_s": 0, "propellant_g": 0, "reason": BurnSystem.REASON_NO_THRUSTER })
			else:
				if s["mode"] == "landed":
					s = { "mode": "stepped", "body": s["body"], "pos": s["pos"], "vel": [0, 0, 0], "carry": [0, 0, 0],
						"vcarry": [0, 0, 0] }
					entered = true
				var vector := BurnSystem.vector_for(ctx, planned, _here(ctx, s, t), t, s["mode"] == "rails")
				if s["mode"] == "rails":
					var orbit: Dictionary = s["orbit"]
					var at := OrbitMath.state_at(orbit, ctx.state["bodies"][orbit["parent"]]["gm"], t)
					s = { "mode": "stepped", "body": orbit["parent"], "pos": at["r"], "vel": at["v"], "carry": [0, 0, 0],
						"vcarry": [0, 0, 0] }
					entered = true
				burn = BurnSystem.new_burn(planned, vector, t, found["part"])
				record = _burn_record(burn, t)
				if entered:
					_open_segment(out, s, t)
		# Phase 5: motion, ground and sphere.
		if s["mode"] == "stepped" and not entered:
			var known: Array = s.get("accel", []) if s.get("accel_at", []) == s["pos"] else []
			var next := LowFlight.advance(ctx, s["body"], s["pos"], s["vel"], s["carry"], s["vcarry"], known)
			s["accel_at"] = next["pos"]
			s["accel"] = next["accel"]
			s["pos"] = next["pos"]
			s["vel"] = next["vel"]
			s["carry"] = next["carry"]
			s["vcarry"] = next["vcarry"]
			var cell := LowFlight.ground_contact(ctx, s["body"], s["pos"], memo)
			if cell >= 0:
				var speed := IntMath.dist(s["vel"], [0, 0, 0])
				var gentle := speed <= LowFlight.touchdown_mm_s(ctx, unit_id) * 1000
				out["contact"] = { "tick": t, "cell": cell, "speed_um_s": speed, "outcome": "landed" if gentle else "crashed" }
				if not burn.is_empty():
					record["end_tick"] = t - 1
					record["reason"] = out["contact"]["outcome"]
					out["burns"].append(record)
					burn = {}
				s = { "mode": "landed", "body": s["body"], "pos": LandingSystem.cell_mm(ctx, s["body"], cell) }
				_open_segment(out, s, t)
				out["end_tick"] = t
				out["ended"] = "contact"
				break
			var crossed := LowFlight.cross_sphere(ctx, s["body"], s["pos"], s["vel"], t)
			if crossed[0] != s["body"]:
				s["body"] = crossed[0]
				s["pos"] = crossed[1]
				s["vel"] = crossed[2]
				memo = {}
				_open_segment(out, s, t)
		# Phase 5: thrust.
		if not burn.is_empty():
			var push := BurnSystem.thrust_step(ctx, burn, stats, mass_g, _here(ctx, s, t), t)
			var shares := Propellant.split(int(push["grams"]), mixture)
			var short := false
			for item: String in Propellant.items_of(mixture):
				short = short or int(shares[item]) > int(left[item])
			if short:
				record["end_tick"] = t - 1
				record["reason"] = BurnSystem.REASON_NO_PROPELLANT
				out["burns"].append(record)
				burn = {}
			else:
				for axis in 3:
					s["vel"][axis] = int(s["vel"][axis]) + int(push["change"][axis])
				BurnSystem.advance_burn(burn, push)
				mass_g -= int(push["grams"])
				for item: String in Propellant.items_of(mixture):
					left[item] = int(left[item]) - int(shares[item])
				record["done_um_s"] = burn["done_um_s"]
				record["propellant_g"] = int(record["propellant_g"]) + int(push["grams"])
				if push["finished"]:
					record["end_tick"] = t
					out["burns"].append(record)
					burn = {}
		# Phase 5: back onto an orbit, or down into stepped flight.
		if s["mode"] == "stepped":
			_record(out, s, t)
			if burn.is_empty():
				var orbit := _settled(ctx, s, t)
				if not orbit.is_empty():
					s = { "mode": "rails", "orbit": orbit }
					_open_segment(out, s, t + 1)
		elif s["mode"] == "rails":
			var orbit: Dictionary = s["orbit"]
			var body: Dictionary = ctx.state["bodies"][orbit["parent"]]
			var pos := OrbitMath.position_at(orbit, t)
			if body["gm"] > 0 and IntMath.dist_below(pos, int(body["radius_mm"]) + LowFlight.enter_mm(ctx, orbit["parent"])):
				var at := OrbitMath.state_at(orbit, body["gm"], t)
				s = { "mode": "stepped", "body": orbit["parent"], "pos": at["r"], "vel": at["v"], "carry": [0, 0, 0],
					"vcarry": [0, 0, 0] }
				_open_segment(out, s, t)
				_record(out, s, t)
		out["end_tick"] = t
		if stop_after_burns and burn.is_empty() and queue.is_empty() and s["mode"] != "stepped":
			out["ended"] = "burns_done"
			break
		t += 1
	if out["ended"] == "horizon":
		out["end_tick"] = until_tick
	if not burn.is_empty():
		record["end_tick"] = -1
		record["reason"] = "running"
		out["burns"].append(record)
	out["final"] = _final(s)
	return out


static func _burn_record(burn: Dictionary, start: int) -> Dictionary:
	return { "id": burn["id"], "start_tick": start, "end_tick": -1, "dv_um_s": burn["dv_um_s"],
		"done_um_s": burn["done_um_s"], "propellant_g": burn.get("spent_g", 0), "reason": "" }


## [place, r, v] of the copy now, as Relative.sample gives it.
static func _here(ctx: SimContext, s: Dictionary, t: int) -> Array:
	match s["mode"]:
		"rails":
			var orbit: Dictionary = s["orbit"]
			var at := OrbitMath.state_at(orbit, ctx.state["bodies"][orbit["parent"]]["gm"], t)
			return [orbit["parent"], at["r"], at["v"]]
		"stepped":
			return [s["body"], s["pos"].duplicate(), s["vel"].duplicate()]
		_:
			return [s["body"], s["pos"].duplicate(), [0, 0, 0]]


## The orbit a coasting stepped copy goes back onto at tick t, as LowFlight.settle decides, or {}.
static func _settled(ctx: SimContext, s: Dictionary, t: int) -> Dictionary:
	var body: int = s["body"]
	if ctx.state["bodies"][body]["gm"] > 0 and LowFlight.altitude_mm(ctx, body, s["pos"]) <= LowFlight.return_mm(ctx, body):
		return {}
	var orbit := OrbitMath.from_state(s["pos"], s["vel"], ctx.state["bodies"][body]["gm"], t)
	if not orbit.is_empty():
		orbit["parent"] = body
	return orbit


## The first tick in [from, before) at which a coasting orbit is within the ground's reach, or
## `before` if it isn't. Between apoapsis and periapsis the distance only falls, so the entry is
## found by bisection there; an orbit whose periapsis is above the reach never enters.
static func _reach_tick(ctx: SimContext, orbit: Dictionary, from: int, before: int) -> int:
	var body: Dictionary = ctx.state["bodies"][orbit["parent"]]
	if body["gm"] <= 0:
		return before
	var reach := int(body["radius_mm"]) + LowFlight.enter_mm(ctx, orbit["parent"])
	if OrbitMath.periapsis_radius_mm(orbit) >= reach:
		return before
	if IntMath.dist_below(OrbitMath.position_at(orbit, from), reach):
		return from
	var t := from
	while t < before:
		var peri := OrbitMath.next_periapsis_tick(orbit, t)
		if peri < 0:
			return before
		var low := t
		if not orbit.get("hyperbolic", false):
			var apo := OrbitMath.next_apoapsis_tick(orbit, t)
			if apo < peri:
				low = apo
		if low >= before:
			return before
		if IntMath.dist_below(OrbitMath.position_at(orbit, peri), reach):
			# Outside at `low`, inside at `peri`: the first tick inside.
			var high := peri
			if IntMath.dist_below(OrbitMath.position_at(orbit, low), reach):
				return mini(low, before)
			while high - low > 1:
				var mid := (low + high) / 2
				if IntMath.dist_below(OrbitMath.position_at(orbit, mid), reach):
					high = mid
				else:
					low = mid
			return mini(high, before)
		t = peri + 1
	return before


static func _open_segment(out: Dictionary, s: Dictionary, from: int) -> void:
	var segments: Array = out["segments"]
	if not segments.is_empty() and int(segments[segments.size() - 1][0]) == from:
		segments.pop_back()
	match s["mode"]:
		"rails":
			segments.append([from, s["orbit"]])
		"stepped":
			segments.append([from, { "stepped": s["body"], "states": PackedInt64Array() }])
		_:
			segments.append([from, { "landed": s["body"], "pos": s["pos"].duplicate() }])


static func _record(out: Dictionary, s: Dictionary, t: int) -> void:
	var segments: Array = out["segments"]
	var entry: Dictionary = segments[segments.size() - 1][1]
	var states: PackedInt64Array = entry["states"]
	var expected := int(segments[segments.size() - 1][0]) + states.size() / STRIDE
	if expected != t:
		return
	for key: String in ["pos", "vel", "carry", "vcarry"]:
		for axis in 3:
			states.append(int(s[key][axis]))
	entry["states"] = states


static func _final(s: Dictionary) -> Dictionary:
	match s["mode"]:
		"rails":
			return { "orbit": s["orbit"] }
		"stepped":
			return { "stepped": s["body"], "pos": s["pos"], "vel": s["vel"] }
		_:
			return { "landed": s["body"], "pos": s["pos"] }


# ------------------------------------------------------------------------------ reading a flight

static func segment_at(segments: Array, tick: int) -> Array:
	var low := 0
	var high := segments.size() - 1
	while low < high:
		var mid := (low + high + 1) / 2
		if int(segments[mid][0]) <= tick:
			low = mid
		else:
			high = mid - 1
	return segments[low]


## Where a flight is at a tick, as [place, r, v] (v [0, 0, 0] unless asked for). Before the first
## segment it reads the first; past the last stepped state it holds the last.
static func sample(ctx: SimContext, segments: Array, tick: int, with_v: bool) -> Array:
	var segment := segment_at(segments, tick)
	var entry: Dictionary = segment[1]
	if entry.has("stepped"):
		var states: PackedInt64Array = entry["states"]
		var count := states.size() / STRIDE
		if count == 0:
			return [entry["stepped"], [0, 0, 0], [0, 0, 0]]
		var i := clampi(tick - int(segment[0]), 0, count - 1) * STRIDE
		return [entry["stepped"], [states[i], states[i + 1], states[i + 2]],
			[states[i + 3], states[i + 4], states[i + 5]] if with_v else [0, 0, 0]]
	if entry.has("landed"):
		return [entry["landed"], entry["pos"].duplicate(), [0, 0, 0]]
	if with_v:
		var now := OrbitMath.state_at(entry, ctx.state["bodies"][entry["parent"]]["gm"], tick)
		return [entry["parent"], now["r"], now["v"]]
	return [entry["parent"], OrbitMath.position_at(entry, tick), [0, 0, 0]]


## The full stepped state at a tick, [pos, vel, carry, vcarry], or [] if the flight isn't stepped
## there (for checking a cached flight against the unit).
static func stepped_state(segments: Array, tick: int) -> Array:
	var segment := segment_at(segments, tick)
	var entry: Dictionary = segment[1]
	if not entry.has("stepped"):
		return []
	var states: PackedInt64Array = entry["states"]
	var i := (tick - int(segment[0])) * STRIDE
	if i < 0 or i + STRIDE > states.size():
		return []
	var out: Array = []
	for k in 4:
		out.append([states[i + 3 * k], states[i + 3 * k + 1], states[i + 3 * k + 2]])
	return out
