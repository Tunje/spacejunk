class_name CoastBounds
extends RefCounted
## Conservative bounds for coasting (orbital_flight.md 11.22, A33). A horizon may stop a coast too
## early, which only costs speed, but never too late: each bound here is the ticks before a distance
## could close, given the most the two things can move per tick.

## A speed for anything that can't be bounded, so its horizons come out at 0.
const UNBOUNDED_UM_S := 1 << 50


## Room for integer positions and rounded speeds: a bound gives away this much of each gap and
## takes speeds as 1% faster than worked out. Positions are whole millimetres and Q30 directions
## err by well under a millimetre at these distances, so a metre is ample. It was 10 km in A33,
## which held coast at 0 for thousands of ticks either side of every shadow edge (D, A35).
const GAP_SLACK_MM := 1_000
const SPEED_SLACK_PERMILLE := 1010


## The ticks before a gap of gap_mm can close at speed_um_s, less one, or 0 if it already has.
## `slack_mm` is what the gap gives away for rounding: GAP_SLACK_MM unless the caller knows its
## own rounding better, as the shadow bound does (A46).
static func ticks_to_close(gap_mm: int, speed_um_s: int, slack_mm: int = GAP_SLACK_MM) -> int:
	var gap := gap_mm - slack_mm
	if gap <= 0:
		return 0
	var speed := IntMath.mul_div(maxi(1, speed_um_s), SPEED_SLACK_PERMILLE, 1000) + 1
	# A speed in um/s closes speed / 10_000 mm a tick.
	return maxi(0, IntMath.mul_div(gap, 10_000, speed) - 1)


## The fastest an elliptic orbit goes round its parent: its speed at periapsis.
static func orbit_max_um_s(gm: int, orbit: Dictionary) -> int:
	if orbit.get("hyperbolic", false):
		return UNBOUNDED_UM_S
	return OrbitMath.speed_um_s(gm, periapsis_mm(orbit), orbit["a_mm"]) + 1


static func periapsis_mm(orbit: Dictionary) -> int:
	return orbit["a_mm"] - OrbitMath.smul_div(orbit["a_mm"], orbit["e_q30"], OrbitMath.ONE)


## The most a body can move per second relative to the root, summed up its chain of orbits.
static func body_speed_um_s(state: Dictionary, body_id: int) -> int:
	var total := 0
	var bodies: Dictionary = state["bodies"]
	var id := body_id
	while id != 0 and not bodies[id]["orbit"].is_empty():
		var orbit: Dictionary = bodies[id]["orbit"]
		total += orbit_max_um_s(bodies[orbit["parent"]]["gm"], orbit)
		id = orbit["parent"]
	return mini(total, UNBOUNDED_UM_S)


## The most a unit and a body can close on each other per second: only the motion below the first
## body both hang from counts, since what that body does moves both alike.
static func relative_speed_um_s(state: Dictionary, unit_id: int, body_id: int) -> int:
	var base := unit_base(state, unit_id)
	if base[1] >= UNBOUNDED_UM_S:
		return UNBOUNDED_UM_S
	return mini(int(base[1]) + chain_um_s(state, base[0], body_id), UNBOUNDED_UM_S)


## The most two bodies can close per second through their orbits below the first body both hang
## from. It is the same for every unit based on `from_body`, so a horizon pass caches it (A38).
static func chain_um_s(state: Dictionary, from_body: int, body_id: int) -> int:
	var theirs := _ancestors(state, body_id)
	var total := 0
	var id := from_body
	while id != 0 and not theirs.has(id):
		total += _own_speed(state, id)
		id = _parent(state, id)
	var common := id
	id = body_id
	while id != 0 and id != common:
		total += _own_speed(state, id)
		id = _parent(state, id)
	return mini(total, UNBOUNDED_UM_S)


## [the body a unit moves round or sits on, its most speed relative to that body].
static func unit_base(state: Dictionary, unit_id: int) -> Array:
	var unit: Dictionary = state["units"][unit_id]
	if not unit["dock"].is_empty():
		return unit_base(state, unit["dock"]["target_unit"])
	if unit.get("low_flight", 0) != 0:
		return [0, UNBOUNDED_UM_S]
	if not unit["route"].is_empty():
		# A straight leg at its speed, in its frame or in the old world (A37).
		var moving := int(unit["route"]["speed_mm_s"]) * 1000 + 1
		if unit["frame"] == 0:
			return [0, moving]
		var on: Dictionary = state["frames"][unit["frame"]]
		var parent_id: int = on["orbit"]["parent"]
		var carried := orbit_max_um_s(state["bodies"][parent_id]["gm"], on["orbit"])
		return [parent_id, mini(carried + moving, UNBOUNDED_UM_S)]
	if not unit.get("landed", {}).is_empty():
		return [unit["landed"]["body"], 0]
	if not unit["orbit"].is_empty():
		var parent: int = unit["orbit"]["parent"]
		return [parent, orbit_max_um_s(state["bodies"][parent]["gm"], unit["orbit"])]
	if unit["frame"] != 0:
		if unit["vel_um_s"] != [0, 0, 0]:
			return [0, UNBOUNDED_UM_S]
		var frame: Dictionary = state["frames"][unit["frame"]]
		var parent: int = frame["orbit"]["parent"]
		return [parent, orbit_max_um_s(state["bodies"][parent]["gm"], frame["orbit"])]
	return [0, 0]


static func _ancestors(state: Dictionary, body_id: int) -> Dictionary:
	var found := {}
	var id := body_id
	while id != 0:
		found[id] = true
		id = _parent(state, id)
	return found


static func _parent(state: Dictionary, body_id: int) -> int:
	var orbit: Dictionary = state["bodies"][body_id]["orbit"]
	return 0 if orbit.is_empty() else int(orbit["parent"])


static func _own_speed(state: Dictionary, body_id: int) -> int:
	var orbit: Dictionary = state["bodies"][body_id]["orbit"]
	if orbit.is_empty():
		return 0
	return orbit_max_um_s(state["bodies"][orbit["parent"]]["gm"], orbit)
