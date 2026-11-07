class_name Lambert
extends RefCounted
## The orbit from a point at one tick to a point on another orbit at a later tick, round one parent
## (task A47, stage one: in the unit's plane). It is found by shooting with the same integer
## propagation the rails use: guess the departure velocity in the plane, carry the orbit it makes to
## the arrival tick with OrbitMath.from_state and position_at, measure the miss, and correct the
## guess by Newton's method on two unknowns with finite differences. Every step is integer, so the
## answer is deterministic, and the orbit found is exactly the one the unit will ride.

## A miss this small is a hit: the arrival snaps the unit to its stop point in the target's place.
const HIT_MM := 100_000
const MAX_ITERATIONS := 24


## The departure velocity, as { v: [um/s], orbit, miss_mm }, that carries a unit from r1 at
## depart_tick to where `theirs` is at arrive_tick, in the plane with unit normal `normal`, or {}
## if the search doesn't hit. `guess` is a starting velocity in that plane.
static func solve(gm: int, r1: Array, guess: Array, theirs: Dictionary, depart_tick: int, arrive_tick: int,
		normal: Array) -> Dictionary:
	var target := OrbitMath.position_at(theirs, arrive_tick)
	var radial := OrbitMath.unit(r1)
	var along := OrbitMath.unit(OrbitMath.cross(normal, radial))
	var vr := OrbitMath.dot(guess, radial)
	var vt := OrbitMath.dot(guess, along)
	var best := {}
	for iteration in MAX_ITERATIONS:
		var here := _miss(gm, r1, radial, along, vr, vt, target, depart_tick, arrive_tick)
		if here.is_empty():
			return best
		var miss: int = IntMath.dist(here["miss"], [0, 0, 0])
		if best.is_empty() or miss < int(best["miss_mm"]):
			best = { "v": here["v"], "orbit": here["orbit"], "miss_mm": miss }
		if miss <= HIT_MM:
			return best
		# Finite differences: how the miss moves for a small change of each component.
		var h := maxi(1_000, (absi(vr) + absi(vt)) / 2_000)
		var by_r := _miss(gm, r1, radial, along, vr + h, vt, target, depart_tick, arrive_tick)
		var by_t := _miss(gm, r1, radial, along, vr, vt + h, target, depart_tick, arrive_tick)
		if by_r.is_empty() or by_t.is_empty():
			return best
		var e: Array = here["miss"]
		var e_x := OrbitMath.dot(e, radial)
		var e_y := OrbitMath.dot(e, along)
		var a := OrbitMath.dot(_minus(by_r["miss"], e), radial)
		var c := OrbitMath.dot(_minus(by_r["miss"], e), along)
		var b := OrbitMath.dot(_minus(by_t["miss"], e), radial)
		var d := OrbitMath.dot(_minus(by_t["miss"], e), along)
		# Solve [a b; c d] [s t] = -[e_x e_y] for the steps s, t in units of h.
		var det := a * d - b * c
		if det == 0:
			return best
		var sign := 1 if det > 0 else -1
		var step_r := OrbitMath.smul_div(-e_x * d + e_y * b, h * sign, absi(det))
		var step_t := OrbitMath.smul_div(e_x * c - e_y * a, h * sign, absi(det))
		# No step bigger than a quarter of the speed, so a far guess can't fling the search away.
		var cap := maxi(1_000, (absi(vr) + absi(vt)) / 4)
		vr += clampi(step_r, -cap, cap)
		vt += clampi(step_t, -cap, cap)
	return best if not best.is_empty() and int(best["miss_mm"]) <= HIT_MM else {}


## { v, orbit, miss } for the velocity vr radially and vt along the motion, or {} if it makes no
## orbit that either form can hold.
static func _miss(gm: int, r1: Array, radial: Array, along: Array, vr: int, vt: int, target: Array,
		depart_tick: int, arrive_tick: int) -> Dictionary:
	var v: Array[int] = []
	for axis in 3:
		v.append(OrbitMath.smul_div(radial[axis], vr, OrbitMath.ONE) + OrbitMath.smul_div(along[axis], vt, OrbitMath.ONE))
	var orbit := OrbitMath.from_state(r1, v, gm, depart_tick)
	if orbit.is_empty():
		return {}
	var there := OrbitMath.position_at(orbit, arrive_tick)
	return { "v": v, "orbit": orbit, "miss": _minus(there, target) }


static func _minus(a: Array, b: Array) -> Array[int]:
	return [int(a[0]) - int(b[0]), int(a[1]) - int(b[1]), int(a[2]) - int(b[2])]
