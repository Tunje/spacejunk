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
		normal: Array, hit_mm: int = HIT_MM) -> Dictionary:
	var target := OrbitMath.position_at(theirs, arrive_tick)
	var radial := OrbitMath.unit(r1)
	var along := OrbitMath.unit(OrbitMath.cross(normal, radial))
	var vr := OrbitMath.dot(guess, radial)
	var vt := OrbitMath.dot(guess, along)
	var best := {}
	# The chord method (A47): the finite-difference Jacobian is worked out once and kept while each
	# step at least halves the miss, so most steps cost one propagation, not three.
	var jacobian := []
	var last_miss := -1
	for iteration in MAX_ITERATIONS:
		var here := _miss(gm, r1, radial, along, vr, vt, target, depart_tick, arrive_tick)
		if here.is_empty():
			return best
		var miss: int = IntMath.dist(here["miss"], [0, 0, 0])
		if best.is_empty() or miss < int(best["miss_mm"]):
			best = { "v": here["v"], "orbit": here["orbit"], "miss_mm": miss }
		if miss <= hit_mm:
			return best
		var e: Array = here["miss"]
		if jacobian.is_empty() or (last_miss >= 0 and miss * 2 > last_miss):
			jacobian = _jacobian(gm, r1, radial, along, vr, vt, target, depart_tick, arrive_tick, e)
			if jacobian.is_empty():
				return best
		last_miss = miss
		var h: int = jacobian[0]
		var a: int = jacobian[1]
		var b: int = jacobian[2]
		var c: int = jacobian[3]
		var d: int = jacobian[4]
		var e_x := OrbitMath.dot(e, radial)
		var e_y := OrbitMath.dot(e, along)
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
	return best if not best.is_empty() and int(best["miss_mm"]) <= hit_mm else {}


## [h, a, b, c, d]: how the miss `e` at (vr, vt) moves, in the radial and along-track directions,
## for a step h in each component, or [] if a nudged guess makes no orbit.
static func _jacobian(gm: int, r1: Array, radial: Array, along: Array, vr: int, vt: int, target: Array,
		depart_tick: int, arrive_tick: int, e: Array) -> Array:
	var h := maxi(1_000, (absi(vr) + absi(vt)) / 2_000)
	var by_r := _miss(gm, r1, radial, along, vr + h, vt, target, depart_tick, arrive_tick)
	var by_t := _miss(gm, r1, radial, along, vr, vt + h, target, depart_tick, arrive_tick)
	if by_r.is_empty() or by_t.is_empty():
		return []
	var moved_r := _minus(by_r["miss"], e)
	var moved_t := _minus(by_t["miss"], e)
	return [h, OrbitMath.dot(moved_r, radial), OrbitMath.dot(moved_t, radial), OrbitMath.dot(moved_r, along),
		OrbitMath.dot(moved_t, along)]


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


# ------------------------------------------------------------------------------ universal variables (3a)

## Bisection steps on z: its bracket is under 2^37 Q30 units wide, so 48 halvings pin it to well
## under one.
const UV_STEPS := 48
## A universal-variable trip is refined until it misses by this much or less (stage 3a).
const UV_HIT_MM := 1_000
## y / C past this makes the time of flight overflow; it is far longer than any trip.
const UV_LONG := 1_000_000
## z, in Q30, below which C and S come from their series, where 1 - cos loses its precision.
const SERIES_Z := 1 << 30
const SERIES_TERMS := 8


## The departure velocity, in um/s, for the arc from r1 to r2 in `ticks` ticks round a parent of gm,
## going round with `normal` (the transfer's sense of motion), with no whole revolutions, by the
## universal-variable form of Lambert's problem (Bate, Mueller and White; Vallado). [] if there is
## none (a straight line through the parent, or a time no conic can make). It works in units of r1's
## length and its circular time, so everything is near 1 in Q30, and finds z by bisection, so the
## answer is the same on every machine. solve_uv refines it on the rails' own propagation.
static func universal(gm: int, r1: Array, r2: Array, ticks: int, normal: Array) -> Array[int]:
	var one := OrbitMath.ONE
	var r1_mm := IntMath.dist(r1, [0, 0, 0])
	var r2_mm := IntMath.dist(r2, [0, 0, 0])
	if r1_mm == 0 or r2_mm == 0 or ticks <= 0:
		return []
	var r2n := OrbitMath.smul_div(r2_mm, one, r1_mm)
	var u1 := OrbitMath.unit(r1)
	var u2 := OrbitMath.unit(r2)
	var cos_dnu := OrbitMath.dot(u1, u2)
	# The sense of motion: the short way if r1 x r2 points along the transfer's normal.
	var short := OrbitMath.dot(OrbitMath.cross(u1, u2), normal) >= 0
	var a_n := qsqrt(OrbitMath.smul_div(r2n, maxi(0, one + cos_dnu), one))
	if not short:
		a_n = -a_n
	if absi(a_n) < 16:
		return []
	# Time in units of sqrt(r1^3 / gm): r1 over the circular speed there.
	var speed := OrbitMath.circular_speed(gm, r1_mm)
	var dt_n := OrbitMath.smul_div(OrbitMath.smul_div(ticks * one, speed[0], r1_mm * Sim.TICKS_PER_SECOND), 1, 1 << speed[1])
	var four_pi2 := OrbitMath.smul_div(OrbitMath.TWO_PI, OrbitMath.TWO_PI, one)
	var high := four_pi2 - (one >> 10)
	var low := -2 * four_pi2
	# The time rises with z, so an elliptic trip (longer than at z = 0) is bracketed from 0, and
	# only a hyperbolic one needs the lower bracket moved up past where y goes negative (A > 0).
	if _uv_time(one, r2n, a_n, 0) <= dt_n:
		low = 0
	elif a_n > 0:
		var y_low := _uv_y(one, r2n, a_n, low)
		if y_low < 0:
			var bad := low
			var good := high
			for i in UV_STEPS:
				var mid := (bad + good) / 2
				if _uv_y(one, r2n, a_n, mid) < 0:
					bad = mid
				else:
					good = mid
			low = good
	if _uv_time(one, r2n, a_n, high) < dt_n:
		return []  # longer than no-revolution arcs go
	for i in UV_STEPS:
		var mid := (low + high) / 2
		if _uv_time(one, r2n, a_n, mid) < dt_n:
			low = mid
		else:
			high = mid
	return _uv_velocity(r1, r2, r1_mm, r2n, a_n, (low + high) / 2, speed)


## As universal, for an arc of `revs` whole revolutions (stage 3a's multi-rev): for N >= 1 the
## time has one minimum between z = (2 pi N)^2 and (2 pi (N + 1))^2, with an arc either side of it,
## `low_branch` (smaller z, the higher-energy arc) or the other. [] if the time is under the
## minimum, which N revolutions can't make.
static func universal_revs(gm: int, r1: Array, r2: Array, ticks: int, normal: Array, revs: int,
		low_branch: bool) -> Array[int]:
	if revs <= 0:
		return universal(gm, r1, r2, ticks, normal)
	var one := OrbitMath.ONE
	var r1_mm := IntMath.dist(r1, [0, 0, 0])
	var r2_mm := IntMath.dist(r2, [0, 0, 0])
	if r1_mm == 0 or r2_mm == 0 or ticks <= 0:
		return []
	var r2n := OrbitMath.smul_div(r2_mm, one, r1_mm)
	var u1 := OrbitMath.unit(r1)
	var u2 := OrbitMath.unit(r2)
	var short := OrbitMath.dot(OrbitMath.cross(u1, u2), normal) >= 0
	var a_n := qsqrt(OrbitMath.smul_div(r2n, maxi(0, one + OrbitMath.dot(u1, u2)), one))
	if not short:
		a_n = -a_n
	if absi(a_n) < 16:
		return []
	var speed := OrbitMath.circular_speed(gm, r1_mm)
	var dt_n := OrbitMath.smul_div(OrbitMath.smul_div(ticks * one, speed[0], r1_mm * Sim.TICKS_PER_SECOND), 1, 1 << speed[1])
	var edge := one >> 10
	var z_low := OrbitMath.smul_div(OrbitMath.TWO_PI * revs, OrbitMath.TWO_PI * revs, one) + edge
	var z_high := OrbitMath.smul_div(OrbitMath.TWO_PI * (revs + 1), OrbitMath.TWO_PI * (revs + 1), one) - edge
	# The minimum by ternary search on the time, which falls then rises across the interval.
	var a := z_low
	var b := z_high
	for i in UV_STEPS:
		var m1 := a + (b - a) / 3
		var m2 := b - (b - a) / 3
		if _uv_time(one, r2n, a_n, m1) <= _uv_time(one, r2n, a_n, m2):
			b = m2
		else:
			a = m1
	var z_min := (a + b) / 2
	if _uv_time(one, r2n, a_n, z_min) > dt_n:
		return []
	var low := z_low if low_branch else z_min
	var high := z_min if low_branch else z_high
	for i in UV_STEPS:
		var mid := (low + high) / 2
		var shorter := _uv_time(one, r2n, a_n, mid) < dt_n
		# On the low branch the time falls with z, on the high one it rises.
		if shorter == low_branch:
			high = mid
		else:
			low = mid
	return _uv_velocity(r1, r2, r1_mm, r2n, a_n, (low + high) / 2, speed)


## v1 from z, in um/s: v1 = (r2 - f r1) / g, in units of the circular speed at r1.
static func _uv_velocity(r1: Array, r2: Array, r1_mm: int, r2n: int, a_n: int, z: int, speed: Array) -> Array[int]:
	var one := OrbitMath.ONE
	var y := _uv_y(one, r2n, a_n, z)
	if y <= 0:
		return []
	var f := one - y
	var g := OrbitMath.smul_div(a_n, qsqrt(y), one)
	if g == 0:
		return []
	var v: Array[int] = []
	for axis in 3:
		var r2_axis := OrbitMath.smul_div(int(r2[axis]), one, r1_mm)
		var r1_axis := OrbitMath.smul_div(int(r1[axis]), one, r1_mm)
		var gap := r2_axis - OrbitMath.smul_div(f, r1_axis, one)
		var v_n := OrbitMath.smul_div(gap if g > 0 else -gap, one, absi(g))
		v.append(OrbitMath.smul_div(OrbitMath.smul_div(v_n, speed[0], one), OrbitMath.UM_PER_MM, 1 << speed[1]))
	return v


static func _uv_y(r1n: int, r2n: int, a_n: int, z: int, cs: Array = []) -> int:
	if cs.is_empty():
		cs = stumpff(z)
	var root_c := qsqrt(maxi(1, cs[0]))
	return r1n + r2n + OrbitMath.smul_div(a_n, OrbitMath.smul_div(z, cs[1], OrbitMath.ONE) - OrbitMath.ONE, root_c)


## The time of flight for z, in units of sqrt(r1^3 / gm), Q30.
static func _uv_time(r1n: int, r2n: int, a_n: int, z: int) -> int:
	var one := OrbitMath.ONE
	var cs := stumpff(z)
	var y := _uv_y(r1n, r2n, a_n, z, cs)
	if y < 0:
		return -1
	# Near z = 4 pi^2, C goes to 0 and the time to infinity: past a million units it is "too long".
	if int(cs[0]) <= 0 or y > int(cs[0]) * UV_LONG:
		return 1 << 60
	var chi := qsqrt(OrbitMath.smul_div(y, one, maxi(1, cs[0])))
	var chi3 := OrbitMath.smul_div(OrbitMath.smul_div(chi, chi, one), chi, one)
	return OrbitMath.smul_div(chi3, cs[1], one) + OrbitMath.smul_div(a_n, qsqrt(y), one)


## The Stumpff functions [C(z), S(z)] in Q30: by series near 0, by the circular functions above
## and the hyperbolic ones below.
static func stumpff(z: int) -> Array[int]:
	var one := OrbitMath.ONE
	if absi(z) < SERIES_Z:
		# C = sum (-z)^k / (2k + 2)!, S = sum (-z)^k / (2k + 3)!.
		var c := 0
		var s := 0
		var power := one
		var fact_c := 2
		var fact_s := 6
		for k in SERIES_TERMS:
			c += power / fact_c
			s += power / fact_s
			power = -OrbitMath.smul_div(power, z, one)
			fact_c *= (2 * k + 3) * (2 * k + 4)
			fact_s *= (2 * k + 4) * (2 * k + 5)
		return [c, s]
	if z > 0:
		var w := qsqrt(z)
		var sc := OrbitMath.sin_cos(IntMath.mul_div(w, OrbitMath.TURN, OrbitMath.TWO_PI) & OrbitMath.ANGLE_MASK)
		var w3 := OrbitMath.smul_div(OrbitMath.smul_div(w, w, one), w, one)
		return [OrbitMath.smul_div(one - sc[1], one, z), OrbitMath.smul_div(w - sc[0], one, w3)]
	var w := qsqrt(-z)
	var sh := OrbitMath.sinh_cosh(w)
	var w3 := OrbitMath.smul_div(OrbitMath.smul_div(w, w, one), w, one)
	return [OrbitMath.smul_div(sh[1] - one, one, -z), OrbitMath.smul_div(sh[0] - w, one, w3)]


## Lambert from r1 at depart_tick to where `theirs` is at arrive_tick (3a): the universal-variable
## answer, refined by solve's shooting on the rails' own propagation to within UV_HIT_MM. {} if
## neither finds it.
static func solve_uv(gm: int, r1: Array, theirs: Dictionary, depart_tick: int, arrive_tick: int,
		normal: Array, revs: int = 0, low_branch: bool = true) -> Dictionary:
	var r2 := OrbitMath.position_at(theirs, arrive_tick)
	var guess := universal_revs(gm, r1, r2, arrive_tick - depart_tick, normal, revs, low_branch)
	if guess.is_empty():
		return {}
	return solve(gm, r1, guess, theirs, depart_tick, arrive_tick, normal, UV_HIT_MM)


## The square root of a Q30 number, in Q30, for any size the solver meets.
static func qsqrt(x: int) -> int:
	if x <= 0:
		return 0
	var scaled := OrbitMath.scaled_sqrt(x)  # sqrt(x) * 2^shift
	var shift: int = 15 - int(scaled[1])
	return int(scaled[0]) << shift if shift >= 0 else int(scaled[0]) >> -shift
