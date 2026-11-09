class_name OrbitMath
extends RefCounted
## Integer orbits, for flight (orbital_flight.md sections 3 and 11). Pure functions on plain data,
## with no floats. The only stored thing is a sine table, built from integers on first use.
##
## Units:
## - Lengths are mm.
## - Velocities are um/s, so that repeated conversions don't add up rounding.
## - GM is in units of 1000 m^3/s^2.
## - Angles are binary, with 2^48 to a turn. At 2^32, one unit would be 220 km at 1 AU.
## - Ratios and directions are Q30, where 2^30 is 1.0.
##
## Orbits are relative to the parent body. The reference plane's normal is +Y, so an orbit with no
## inclination has angular momentum along +Y.
##
## An orbit record is elliptic, or hyperbolic with `"hyperbolic": true` (A12). A hyperbolic record
## keeps `a_mm` as the positive semi-axis, its mean anomaly in Q30 radians as `m0_rad`, because it
## does not wrap, and its mean motion as `motion_q60`, in radians per tick in Q60.

const TURN := 1 << 48
const ANGLE_MASK := TURN - 1
const HALF_TURN := 1 << 47
const QUARTER_TURN := 1 << 46
const ONE := 1 << 30
## 2 pi in Q30.
const TWO_PI := 6746518852
## Binary angle units per Q30 radian, times 2^16: 2^18 / (2 pi) in Q16. Keeps to_angle a plain
## multiply and shift for any |radians| under 2^31.
const ANGLE_PER_RADIAN_Q16 := 2734261102
## Mean anomaly's fraction of a turn is found 8 bits at a time, so a period may be up to 2^55
## sub-ticks, about 1700 years.
const FRACTION_STEP_BITS := 8
const TABLE_BITS := 12
const TABLE_SIZE := 1 << TABLE_BITS
const TABLE_MASK := TABLE_SIZE - 1
const FRAC_BITS := 48 - TABLE_BITS
## A period is stored in 1/65536 ticks, so the mean anomaly needs no rounding of the period.
const SUB_TICKS := 1 << 16
## Ticks from an orbit's epoch must stay under this, so `dt * SUB_TICKS` fits (about 445,000 years).
const MAX_DT := 1 << 46
const UM_PER_MM := 1000
## GM's sim unit is 1000 m^3/s^2, which is 10^12 mm^3/s^2.
const MM3_PER_GM_UNIT := 1_000_000_000_000
const KEPLER_STEPS := 40
## Newton stops once Kepler's equation holds this closely, about 3e-9 radians. Below it, rounding
## in the Q30 sine is as large as what is left, so steps would only wander.
const KEPLER_TOLERANCE := 1 << 17
## The largest orbit from_state makes, and the most it may exceed the radius it starts at. Escape
## trajectories, and orbits far outside any sphere of influence, are refused instead.
const MAX_A_MM := 1_000_000_000_000_000
const MAX_A_PER_R := 1024
## Danby's starting offset for Kepler's equation, 0.85 in Q30.
const DANBY_Q30 := 912680550
## 1 / prod(sqrt(1 + 2^-2i)) in Q60. CORDIC works in Q60 and rounds to Q30 once at the end.
const CORDIC_GAIN := 700114967507363238
## atan(2^-i) in 2^48 to a turn.
const ATAN := [35184372088832, 20770547670515, 10974586953444, 5570871696862, 2796246208089,
	1399486241028, 699913886760, 349978300884, 174991820497, 87496244017, 43748163730, 21874087080,
	10937044192, 5468522177, 2734261099, 1367130551, 683565276, 341782638, 170891319, 85445659,
	42722830, 21361415, 10680707, 5340354, 2670177, 1335088, 667544, 333772, 166886, 83443, 41722,
	20861, 10430, 5215, 2608, 1304, 652, 326, 163, 81, 41, 20, 10, 5, 3, 1, 1]
## Inputs to angle_of are shifted into this many bits before CORDIC runs.
const ATAN_INPUT_BITS := 58
## Square roots are taken with the argument scaled up to about this many bits, for precision.
const SQRT_FILL_BITS := 60
const EXP_HALVINGS := 10
const EXP_TERMS := 6
## e^n in Q30 for n = 0..20, so exp splits off its whole part exactly.
const EXP_INT := [1073741824, 2918732889, 7933938573, 21566681052, 58624317204, 159357416160,
	433178368579, 1177500887790, 3200779266274, 8700620116420, 23650737558789, 64289370135711,
	174756626602981, 475037762497685, 1291286517629302, 3510080676205891, 9541388518555713,
	25936183028257763, 70501855025300970, 191643911387929646, 520942161860624641]
const EXP_FRACTION_TERMS := 14
## ln 2 in Q30.
const LN2 := 744261118
const LN_TERMS := 14
## The largest hyperbolic anomaly kept, 20 in Q30. Past it a unit is millions of radii out, so its
## position stops there rather than overflow.
const MAX_HYPERBOLIC_ANOMALY := 20 << 30
const HYPERBOLIC_TOLERANCE := 16
## Q60 for mean motion, which can be a few millionths of a radian per tick.
const MOTION_SHIFT := 60
## Laplace's sphere of influence: a (m / M)^(2/5).
const SOI_POWER_NUMERATOR := 2
const SOI_POWER_DENOMINATOR := 5

static var _sine := PackedInt64Array()


# ------------------------------------------------------------------------------ integer helpers

## a * b / d rounded to nearest, for any signs of a and b. d is positive. Everything here rounds to
## nearest, not down: floors all lean the same way, and through a round trip they bias an orbit's size.
static func smul_div(a: int, b: int, d: int) -> int:
	var small := mini(absi(a), absi(b))
	var large := maxi(absi(a), absi(b))
	var value := (IntMath.mul_div(2 * small, large, d) + 1) >> 1
	return -value if (a < 0) != (b < 0) else value


## The square root rounded to nearest.
static func root(value: int) -> int:
	var floor_root := IntMath.isqrt(value)
	return floor_root + 1 if value - floor_root * floor_root > floor_root else floor_root


static func dot(a: Array, b: Array) -> int:
	return smul_div(a[0], b[0], ONE) + smul_div(a[1], b[1], ONE) + smul_div(a[2], b[2], ONE)


static func cross(a: Array, b: Array) -> Array[int]:
	return [
		smul_div(a[1], b[2], ONE) - smul_div(a[2], b[1], ONE),
		smul_div(a[2], b[0], ONE) - smul_div(a[0], b[2], ONE),
		smul_div(a[0], b[1], ONE) - smul_div(a[1], b[0], ONE),
	]


## The vector scaled to length ONE, or [0, 0, 0] for a zero vector.
static func unit(v: Array) -> Array[int]:
	var length := IntMath.dist(v, [0, 0, 0])
	if length == 0:
		return [0, 0, 0]
	return [smul_div(v[0], ONE, length), smul_div(v[1], ONE, length), smul_div(v[2], ONE, length)]


## [sqrt(value) * 2^shift, shift], with shift as large as keeps value * 4^shift in range.
static func scaled_sqrt(value: int) -> Array[int]:
	var shift := maxi(0, (SQRT_FILL_BITS - IntMath._bit_length(value)) / 2)
	return [root(value << (2 * shift)), shift]


# ------------------------------------------------------------------------------ trigonometry

## [cos, sin] of a binary angle in Q30, by CORDIC in Q60, rounded once at the end.
static func _cordic(angle: int) -> Array[int]:
	var a := angle & ANGLE_MASK
	if a >= HALF_TURN:
		a -= TURN
	var flip := false
	if a > QUARTER_TURN:
		a -= HALF_TURN
		flip = true
	elif a < -QUARTER_TURN:
		a += HALF_TURN
		flip = true
	var x := CORDIC_GAIN
	var y := 0
	for i in ATAN.size():
		var dx := y >> i
		var dy := x >> i
		if a >= 0:
			x -= dx
			y += dy
			a -= ATAN[i]
		else:
			x += dx
			y -= dy
			a += ATAN[i]
	var half := 1 << 29
	var c := (x + half) >> 30
	var s := (y + half) >> 30
	return [-c, -s] if flip else [c, s]


static func _table() -> PackedInt64Array:
	if _sine.is_empty():
		var table := PackedInt64Array()
		table.resize(TABLE_SIZE)
		for i in TABLE_SIZE:
			table[i] = _cordic(i << FRAC_BITS)[1]
		# Exact at the axes, so an orbit set up on an axis stays exactly on it.
		for i in 4:
			table[i * TABLE_SIZE / 4] = [0, ONE, 0, -ONE][i]
		_sine = table
	return _sine


## [sin, cos] of a binary angle, in Q30. A table step plus the angle-addition rule, with a short
## series for the small remainder, so it is accurate to the last few units of Q30.
static func sin_cos(angle: int) -> Array[int]:
	var table := _table()
	var a := angle & ANGLE_MASK
	var index := a >> FRAC_BITS
	var s0 := table[index]
	var c0 := table[(index + TABLE_SIZE / 4) & TABLE_MASK]
	# The remainder in Q30 radians. Dropping its low 8 bits first keeps the product inside 63 bits.
	var b := (((a & ((1 << FRAC_BITS) - 1)) >> 8) * TWO_PI + (1 << 39)) >> 40
	var b2 := (b * b) >> 30
	var sb := b - ((b2 * b) >> 30) / 6
	var cb := ONE - b2 / 2 + ((b2 * b2) >> 30) / 24
	var half := 1 << 29
	return [(s0 * cb + c0 * sb + half) >> 30, (c0 * cb - s0 * sb + half) >> 30]


## The binary angle of the point (x, y), by CORDIC, as atan2 gives in radians. The point (0, 0) gives 0.
## Named apart from the built-in atan2, which takes floats and would shadow it inside this class.
static func angle_of(y: int, x: int) -> int:
	if x == 0 and y == 0:
		return 0
	var bits := IntMath._bit_length(maxi(absi(x), absi(y)))
	if bits > ATAN_INPUT_BITS:
		x >>= bits - ATAN_INPUT_BITS
		y >>= bits - ATAN_INPUT_BITS
	else:
		x <<= ATAN_INPUT_BITS - bits
		y <<= ATAN_INPUT_BITS - bits
	var angle := 0
	if x < 0:
		x = -x
		y = -y
		angle = HALF_TURN
	for i in ATAN.size():
		var dx := y >> i
		var dy := x >> i
		if y > 0:
			x += dx
			y -= dy
			angle += ATAN[i]
		else:
			x -= dx
			y += dy
			angle -= ATAN[i]
	return angle & ANGLE_MASK


## A Q30 number of radians, under 2 in size, as a binary angle.
static func to_angle(radians_q30: int) -> int:
	return (radians_q30 * ANGLE_PER_RADIAN_Q16 + (1 << 15)) >> 16


## x / p as a binary angle, for 0 <= x < p, by long division a few bits at a time. A product with
## TURN would pass 63 bits, and mul_div's wide path is slow.
static func fraction_of_turn(x: int, p: int) -> int:
	var result := 0
	var rest := x
	for i in 48 / FRACTION_STEP_BITS:
		rest <<= FRACTION_STEP_BITS
		var digit := rest / p
		rest -= digit * p
		result = (result << FRACTION_STEP_BITS) | digit
	return result + (1 if 2 * rest >= p else 0)


# ------------------------------------------------------------------------------ orbits

## Circular speed at radius r, as [floor(v * 2^shift), shift] with v in mm/s.
static func circular_speed(gm: int, r_mm: int) -> Array[int]:
	return scaled_sqrt(smul_div(gm, MM3_PER_GM_UNIT, r_mm))


## Speed in um/s at radius r on an orbit with semi-major axis a, by vis-viva.
static func speed_um_s(gm: int, r_mm: int, a_mm: int) -> int:
	var squared := smul_div(gm, 2 * MM3_PER_GM_UNIT, r_mm) - smul_div(gm, MM3_PER_GM_UNIT, a_mm)
	var scaled := scaled_sqrt(maxi(0, squared))
	return smul_div(scaled[0], UM_PER_MM, 1 << scaled[1])


## The period in 1/SUB_TICKS ticks of an orbit with semi-major axis a.
static func period_sub(gm: int, a_mm: int) -> int:
	var speed := circular_speed(gm, a_mm)
	var seconds_q := smul_div(a_mm, TWO_PI, speed[0])
	return smul_div(seconds_q, Sim.TICKS_PER_SECOND * SUB_TICKS << speed[1], ONE)


## An orbit from its shape and its perifocal directions P (towards periapsis) and Q (90 degrees
## ahead), with mean anomaly m0 at tick epoch. The record is plain integer data, ready to save.
static func make_orbit(gm: int, a_mm: int, e: int, p: Array, q: Array, m0: int, epoch: int) -> Dictionary:
	assert(a_mm > 0 and e >= 0 and e < ONE, "an elliptic orbit")
	return {
		"a_mm": a_mm,
		"e_q30": e,
		"b_mm": smul_div(a_mm, root(ONE * ONE - e * e), ONE),
		"p_q30": [p[0], p[1], p[2]],
		"q_q30": [q[0], q[1], q[2]],
		"period_subticks": period_sub(gm, a_mm),
		"m0_angle": m0 & ANGLE_MASK,
		"epoch_tick": epoch,
	}


## The perifocal directions [P, Q] from inclination, longitude of the ascending node and argument
## of periapsis, all binary angles. The node is measured in the X-Z plane from +X towards -Z.
static func directions(inclination: int, node: int, periapsis: int) -> Array:
	var sc_node := sin_cos(node)
	var sc_inc := sin_cos(inclination)
	var sc_arg := sin_cos(periapsis)
	var n := [sc_node[1], 0, -sc_node[0]]
	var w := [smul_div(sc_inc[0], sc_node[0], ONE), sc_inc[1], smul_div(sc_inc[0], sc_node[1], ONE)]
	var m := cross(w, n)
	var p: Array[int] = []
	var q: Array[int] = []
	for axis in 3:
		p.append(smul_div(sc_arg[1], n[axis], ONE) + smul_div(sc_arg[0], m[axis], ONE))
		q.append(smul_div(sc_arg[1], m[axis], ONE) - smul_div(sc_arg[0], n[axis], ONE))
	return [p, q]


static func mean_anomaly(orbit: Dictionary, tick: int) -> int:
	var dt: int = tick - int(orbit["epoch_tick"])
	assert(absi(dt) < MAX_DT, "tick within range of the orbit's epoch")
	var period: int = orbit["period_subticks"]
	return (int(orbit["m0_angle"]) + fraction_of_turn(posmod(dt * SUB_TICKS, period), period)) & ANGLE_MASK


## The eccentric anomaly for mean anomaly m, by Newton's method from Danby's start. It stops when
## the equation holds within KEPLER_TOLERANCE, which in integers happens on the same step on every
## machine.
static func eccentric_anomaly(m: int, e: int) -> int:
	if e == 0:
		return m
	var sc := sin_cos(m)
	var big_e := m + to_angle(smul_div(e, DANBY_Q30, ONE) * (1 if sc[0] >= 0 else -1))
	for i in KEPLER_STEPS:
		sc = sin_cos(big_e)
		var error := big_e - to_angle(smul_div(e, sc[0], ONE)) - m
		error = ((error + HALF_TURN) & ANGLE_MASK) - HALF_TURN
		if absi(error) <= KEPLER_TOLERANCE:
			break
		big_e -= smul_div(error, ONE, ONE - smul_div(e, sc[1], ONE))
	return big_e & ANGLE_MASK


## Position in mm relative to the parent at a tick.
static func position_at(orbit: Dictionary, tick: int) -> Array[int]:
	if orbit.get("hyperbolic", false):
		return _hyperbolic_state(orbit, 0, tick, false)["r"]
	var sc := sin_cos(eccentric_anomaly(mean_anomaly(orbit, tick), orbit["e_q30"]))
	var x := smul_div(orbit["a_mm"], sc[1] - int(orbit["e_q30"]), ONE)
	var y := smul_div(orbit["b_mm"], sc[0], ONE)
	return _place(orbit, x, y)


## Position in mm and velocity in um/s relative to the parent at a tick, as { r, v }.
static func state_at(orbit: Dictionary, gm: int, tick: int) -> Dictionary:
	if orbit.get("hyperbolic", false):
		return _hyperbolic_state(orbit, gm, tick, true)
	var a: int = orbit["a_mm"]
	var e: int = orbit["e_q30"]
	var sc := sin_cos(eccentric_anomaly(mean_anomaly(orbit, tick), e))
	var x := smul_div(a, sc[1] - e, ONE)
	var y := smul_div(orbit["b_mm"], sc[0], ONE)
	var r_mm := smul_div(a, ONE - smul_div(e, sc[1], ONE), ONE)
	# Speed scale sqrt(GM a) / r: circular speed at a, times a / r.
	var speed := circular_speed(gm, a)
	var scale := smul_div(speed[0], a, r_mm)
	var to_um := UM_PER_MM
	var shift_div := 1 << speed[1]
	var vx := -smul_div(smul_div(scale, sc[0], ONE), to_um, shift_div)
	var vy := smul_div(smul_div(smul_div(scale, sc[1], ONE), smul_div(orbit["b_mm"], ONE, a), ONE),
		to_um, shift_div)
	return { "r": _place(orbit, x, y), "v": _place(orbit, vx, vy) }


static func _place(orbit: Dictionary, x: int, y: int) -> Array[int]:
	var p: Array = orbit["p_q30"]
	var q: Array = orbit["q_q30"]
	return [smul_div(x, p[0], ONE) + smul_div(y, q[0], ONE),
		smul_div(x, p[1], ONE) + smul_div(y, q[1], ONE),
		smul_div(x, p[2], ONE) + smul_div(y, q[2], ONE)]


## The orbit through position r (mm) with velocity v (um/s) at a tick: the burn-to-new-orbit
## function. Returns an elliptic or hyperbolic record, or {} for the cases it cannot hold: straight
## up and down, exactly parabolic, or an ellipse far outside any sphere of influence.
##
## Works in units where r is 1 and the circular speed at r is 1, so every quantity is near 1 in
## Q30 and no product can overflow. The periapsis angle is measured in the orbit's own plane from
## the current position, so circular and equatorial orbits need no special case.
static func from_state(r: Array, v: Array, gm: int, tick: int) -> Dictionary:
	var r_mm := IntMath.dist(r, [0, 0, 0])
	if r_mm == 0:
		return {}
	var x_axis := unit(r)
	var speed := circular_speed(gm, r_mm)
	var u: Array[int] = []
	for axis in 3:
		u.append(smul_div(v[axis], ONE << speed[1], speed[0] * UM_PER_MM))
	var u2 := dot(u, u)
	# Within a few units of escape speed the orbit is parabolic, which neither form can hold.
	if absi(u2 - 2 * ONE) <= 2:
		return {}
	var h := cross(x_axis, u)
	var w_axis := unit(h)
	if w_axis == [0, 0, 0]:
		return {}
	var y_axis := cross(w_axis, x_axis)
	var ecc := cross(u, h)
	for axis in 3:
		ecc[axis] -= x_axis[axis]
	var ex := dot(ecc, x_axis)
	var ey := dot(ecc, y_axis)
	var e := IntMath.dist([ex, ey, 0], [0, 0, 0])
	# Rounding can put e on the wrong side of 1 for an orbit within a hair of parabolic.
	if (u2 > 2 * ONE and e <= ONE) or (u2 < 2 * ONE and e >= ONE):
		return {}
	var periapsis: int = angle_of(ey, ex) if e > 0 else 0
	var sc_w := sin_cos(periapsis)
	var p: Array[int] = []
	var q: Array[int] = []
	for axis in 3:
		p.append(smul_div(sc_w[1], x_axis[axis], ONE) + smul_div(sc_w[0], y_axis[axis], ONE))
		q.append(smul_div(sc_w[1], y_axis[axis], ONE) - smul_div(sc_w[0], x_axis[axis], ONE))
	var true_anomaly := (-periapsis) & ANGLE_MASK
	var sc_nu := sin_cos(true_anomaly)
	if u2 > 2 * ONE:
		return _hyperbola(gm, smul_div(r_mm, ONE, u2 - 2 * ONE), e, p, q, sc_nu, tick)
	var big_e := angle_of(smul_div(root(ONE * ONE - e * e), sc_nu[0], ONE), e + sc_nu[1])
	var m := big_e - to_angle(smul_div(e, sin_cos(big_e)[0], ONE))
	var a_mm := smul_div(r_mm, ONE, 2 * ONE - u2)
	if a_mm > MAX_A_MM or a_mm > r_mm * MAX_A_PER_R:
		return {}
	return make_orbit(gm, a_mm, e, p, q, m, tick)


# ------------------------------------------------------------------------------ hyperbolic orbits

## A hyperbolic orbit from its semi-axis A (positive), e > 1, directions, and the sine and cosine of
## its true anomaly at tick epoch.
static func _hyperbola(gm: int, a_mm: int, e: int, p: Array, q: Array, sc_nu: Array, epoch: int) -> Dictionary:
	if a_mm <= 0 or a_mm > MAX_A_MM:
		return {}
	var root_e := sqrt_e2_minus_1(e)
	# sinh H = sqrt(e^2 - 1) sin nu / (1 + e cos nu), and H = asinh of that. Taking asinh of |sinh H|
	# avoids the cancellation that cosh H + sinh H suffers on the way in, where H is large and negative.
	var below := ONE + smul_div(e, sc_nu[1], ONE)
	if below <= 0:
		return {}
	var sinh_h := smul_div(smul_div(root_e, sc_nu[0], ONE), ONE, below)
	var size := ln(absi(sinh_h) + IntMath.dist([sinh_h, ONE, 0], [0, 0, 0])) - 30 * LN2
	var big_h := size if sinh_h >= 0 else -size
	var sh := sinh_cosh(big_h)
	var m := smul_div(e, sh[0], ONE) - big_h
	var speed := circular_speed(gm, a_mm)
	return {
		"hyperbolic": true,
		"a_mm": a_mm,
		"e_q30": e,
		"b_mm": smul_div(a_mm, root_e, ONE),
		"p_q30": [p[0], p[1], p[2]],
		"q_q30": [q[0], q[1], q[2]],
		"m0_rad": m,
		"motion_q60": smul_div(speed[0], 1 << (MOTION_SHIFT - speed[1]), a_mm * Sim.TICKS_PER_SECOND),
		"epoch_tick": epoch,
	}


## sqrt(e^2 - 1) in Q30 for e > 1, without squaring e, which may be large.
static func sqrt_e2_minus_1(e: int) -> int:
	var inverse := smul_div(ONE, ONE, e)
	return smul_div(e, root((ONE - smul_div(inverse, inverse, ONE)) * ONE), ONE)


## Position, and if wanted velocity, on a hyperbolic orbit at a tick.
static func _hyperbolic_state(orbit: Dictionary, gm: int, tick: int, with_velocity: bool) -> Dictionary:
	var a: int = orbit["a_mm"]
	var e: int = orbit["e_q30"]
	var m: int = orbit["m0_rad"] + smul_div(tick - int(orbit["epoch_tick"]), orbit["motion_q60"], 1 << MOTION_SHIFT - 30)
	var sh := sinh_cosh(hyperbolic_anomaly(m, e))
	var result := { "r": _place(orbit, smul_div(a, e - sh[1], ONE), smul_div(orbit["b_mm"], sh[0], ONE)) }
	if with_velocity:
		var r_mm := smul_div(a, smul_div(e, sh[1], ONE) - ONE, ONE)
		var speed := circular_speed(gm, a)
		var scale := smul_div(speed[0], a, r_mm)
		var shift_div := 1 << speed[1]
		var vx := -smul_div(smul_div(scale, sh[0], ONE), UM_PER_MM, shift_div)
		var vy := smul_div(smul_div(smul_div(scale, sh[1], ONE), smul_div(orbit["b_mm"], ONE, a), ONE),
			UM_PER_MM, shift_div)
		result["v"] = _place(orbit, vx, vy)
	return result


## The hyperbolic anomaly H for mean anomaly m, both Q30 radians: e sinh H - H = m, by Newton's
## method from Danby's start, stopping on the residual as the elliptic solve does.
static func hyperbolic_anomaly(m: int, e: int) -> int:
	var sign := 1 if m >= 0 else -1
	var big_h := sign * ln(smul_div(2 * absi(m), ONE, e) + ONE * 18 / 10) - sign * 30 * LN2
	for i in KEPLER_STEPS:
		big_h = clampi(big_h, -MAX_HYPERBOLIC_ANOMALY, MAX_HYPERBOLIC_ANOMALY)
		var sh := sinh_cosh(big_h)
		var error := smul_div(e, sh[0], ONE) - big_h - m
		if absi(error) <= HYPERBOLIC_TOLERANCE:
			break
		big_h -= smul_div(error, ONE, smul_div(e, sh[1], ONE) - ONE)
	return clampi(big_h, -MAX_HYPERBOLIC_ANOMALY, MAX_HYPERBOLIC_ANOMALY)


## [sinh, cosh] of x in Q30.
static func sinh_cosh(x: int) -> Array[int]:
	var up := exp_q30(absi(x))
	var down := smul_div(ONE, ONE, up)
	var s := (up - down) / 2
	return [s if x >= 0 else -s, (up + down) / 2]


## e^x in Q30 for 0 <= x <= 20, from an exact table for the whole part and a series for the rest.
## Not named exp, because the built-in float exp would shadow it inside this class.
static func exp_q30(x: int) -> int:
	var whole := mini(x >> 30, EXP_INT.size() - 1)
	var part := x - (whole << 30)
	var term := ONE
	var total := ONE
	for n in range(1, EXP_FRACTION_TERMS + 1):
		term = smul_div(term, part, ONE * n)
		total += term
	return smul_div(EXP_INT[whole], total, ONE)


## The natural log, in Q30, of a positive whole number. ln of a Q30 value is this minus 30 ln 2.
static func ln(value: int) -> int:
	assert(value > 0, "ln of a positive number")
	var k := IntMath._bit_length(value) - 1
	var m := value >> (k - 30) if k >= 30 else value << (30 - k)
	# ln m for m in [1, 2) is 2 atanh(z), z = (m - 1) / (m + 1), which is at most 1/3.
	var z := smul_div(m - ONE, ONE, m + ONE)
	var z2 := smul_div(z, z, ONE)
	var power := z
	var total := 0
	for n in LN_TERMS:
		total += power / (2 * n + 1)
		power = smul_div(power, z2, ONE)
	return k * LN2 + 2 * total


## The radius of a body's sphere of influence, from its orbit's semi-major axis and the two GMs.
static func soi_mm(a_mm: int, gm: int, gm_parent: int) -> int:
	var exponent := smul_div(ln(gm_parent) - ln(gm), SOI_POWER_NUMERATOR, SOI_POWER_DENOMINATOR)
	return smul_div(a_mm, exp_neg(exponent), ONE)


# ------------------------------------------------------------------------------ propellant

## e^-x for x >= 0 in Q30: halve, sum a short series, then square back.
static func exp_neg(x: int) -> int:
	var y := x >> EXP_HALVINGS
	var term := ONE
	var total := ONE
	for n in range(1, EXP_TERMS + 1):
		term = -smul_div(term, y, ONE * n)
		total += term
	for i in EXP_HALVINGS:
		total = smul_div(total, total, ONE)
	return total


## Grams of propellant a ship of mass_g spends for a burn of dv_um_s, by the rocket equation.
static func burn_g(mass_g: int, dv_um_s: int, exhaust_mm_s: int) -> int:
	var ratio := exp_neg(IntMath.mul_div(dv_um_s, ONE, exhaust_mm_s * UM_PER_MM))
	return IntMath.mul_div_ceil(mass_g, ONE - ratio, ONE)


# ------------------------------------------------------------------------------ apsides (A57)

## The periapsis distance from the parent's centre, in mm, for either kind of orbit.
static func periapsis_radius_mm(orbit: Dictionary) -> int:
	var a: int = orbit["a_mm"]
	if orbit.get("hyperbolic", false):
		return smul_div(a, int(orbit["e_q30"]) - ONE, ONE)
	return a - smul_div(a, orbit["e_q30"], ONE)


## The apoapsis distance from the parent's centre, in mm, or -1 for an open orbit.
static func apoapsis_radius_mm(orbit: Dictionary) -> int:
	if orbit.get("hyperbolic", false):
		return -1
	return smul_div(orbit["a_mm"], ONE + int(orbit["e_q30"]), ONE)


## The tick nearest the next time, at or after `tick`, the orbit is at the mean anomaly `angle` (0
## for periapsis, HALF_TURN for apoapsis). -1 on an open orbit already past
## periapsis, or for an apoapsis on one.
static func next_anomaly_tick(orbit: Dictionary, angle: int, tick: int) -> int:
	if orbit.get("hyperbolic", false):
		if angle != 0:
			return -1
		var m: int = orbit["m0_rad"] + smul_div(tick - int(orbit["epoch_tick"]), orbit["motion_q60"], 1 << MOTION_SHIFT - 30)
		if m > 0:
			return -1
		return tick + smul_div(-m, 1 << (MOTION_SHIFT - 30), maxi(1, int(orbit["motion_q60"])))
	var left := (angle - mean_anomaly(orbit, tick)) & ANGLE_MASK
	var sub := IntMath.mul_div(left, orbit["period_subticks"], TURN)
	return tick + (sub + SUB_TICKS / 2) / SUB_TICKS


static func next_periapsis_tick(orbit: Dictionary, tick: int) -> int:
	return next_anomaly_tick(orbit, 0, tick)


static func next_apoapsis_tick(orbit: Dictionary, tick: int) -> int:
	return next_anomaly_tick(orbit, HALF_TURN, tick)
