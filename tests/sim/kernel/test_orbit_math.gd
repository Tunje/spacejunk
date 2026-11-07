extends GutTest
## OrbitMath (task A9). The float functions here are the reference the client draws orbits with:
## a client drawing an orbit record must match position_float within 1 m.

const Timing := preload("res://tests/sim/kernel/timing.gd")
const ONE := OrbitMath.ONE
const TURN := OrbitMath.TURN
## GM in the sim unit of 1000 m^3/s^2.
const GM_PLANET := 3_531_600_000
const GM_MOON := 65_138_398
const GM_STAR := 132_712_440_018_000_000
const AU_MM := 149_597_870_700_000

var rng := RandomNumberGenerator.new()


func before_each() -> void:
	rng.seed = 20261104


# ------------------------------------------------------------------------------ float reference

## The client's reference: position in mm of an orbit record at a tick, in double-precision floats.
## Godot's Vector3 is single precision, too coarse for this, so positions are float arrays.
static func position_float(orbit: Dictionary, tick: int) -> Array[float]:
	if orbit.get("hyperbolic", false):
		return _hyperbolic_float(orbit, tick)
	var period := float(orbit["period_subticks"]) / OrbitMath.SUB_TICKS
	var e := float(orbit["e_q30"]) / ONE
	var dt := float(tick - int(orbit["epoch_tick"]))
	var m := float(orbit["m0_angle"]) / TURN * TAU + TAU * fposmod(dt, period) / period
	var big_e := m + 0.85 * e * signf(sin(m))
	for i in 50:
		big_e -= (big_e - e * sin(big_e) - m) / (1.0 - e * cos(big_e))
	var x := float(orbit["a_mm"]) * (cos(big_e) - e)
	var y := float(orbit["b_mm"]) * sin(big_e)
	var p: Array = orbit["p_q30"]
	var q: Array = orbit["q_q30"]
	var out: Array[float] = []
	for axis in 3:
		out.append((x * p[axis] + y * q[axis]) / ONE)
	return out


## The same for a hyperbolic record: e sinh H - H = M, with M growing linearly from m0_rad.
static func _hyperbolic_float(orbit: Dictionary, tick: int) -> Array[float]:
	var e := float(orbit["e_q30"]) / ONE
	var m := (float(orbit["m0_rad"]) + float(tick - int(orbit["epoch_tick"])) * float(orbit["motion_q60"]) / pow(2.0, 30)) / ONE
	var big_h := signf(m) * log(2.0 * absf(m) / e + 1.8)
	for i in 60:
		big_h -= (e * sinh(big_h) - big_h - m) / (e * cosh(big_h) - 1.0)
	var x := float(orbit["a_mm"]) * (e - cosh(big_h))
	var y := float(orbit["b_mm"]) * sinh(big_h)
	var p: Array = orbit["p_q30"]
	var q: Array = orbit["q_q30"]
	var out: Array[float] = []
	for axis in 3:
		out.append((x * p[axis] + y * q[axis]) / ONE)
	return out


static func _gap(a: Array, b: Array) -> float:
	return sqrt(pow(float(a[0]) - float(b[0]), 2) + pow(float(a[1]) - float(b[1]), 2)
		+ pow(float(a[2]) - float(b[2]), 2))


static func _length(a: Array) -> float:
	return _gap(a, [0, 0, 0])


static func _cross(a: Array, b: Array) -> Array[float]:
	return [float(a[1]) * b[2] - float(a[2]) * b[1], float(a[2]) * b[0] - float(a[0]) * b[2],
		float(a[0]) * b[1] - float(a[1]) * b[0]]


## A random binary angle over the whole turn. randi() gives only 32 bits.
func _angle() -> int:
	return ((rng.randi() << 16) | (rng.randi() & 0xFFFF)) & OrbitMath.ANGLE_MASK


func _random_orbit(gm: int, a_mm: int, e: int, inclination: int = -1) -> Dictionary:
	var incl := inclination if inclination >= 0 else _angle() % (TURN / 2)
	var dirs := OrbitMath.directions(incl, _angle(), _angle())
	return OrbitMath.make_orbit(gm, a_mm, e, dirs[0], dirs[1], _angle(), rng.randi_range(0, 100000))


## The worst distance in mm between two orbits over one period of the first, at 48 ticks.
func _worst_gap(first: Dictionary, second: Dictionary, from_tick: int) -> int:
	var period: int = first["period_subticks"] / OrbitMath.SUB_TICKS
	var worst := 0
	for k in 49:
		var tick := from_tick + period * k / 48
		worst = maxi(worst, IntMath.dist(OrbitMath.position_at(first, tick), OrbitMath.position_at(second, tick)))
	return worst


# ------------------------------------------------------------------------------ trigonometry

func test_sine_and_cosine_match_floats() -> void:
	var worst := 0.0
	for i in 20000:
		var angle := _angle()
		var sc := OrbitMath.sin_cos(angle)
		var radians := float(angle) / TURN * TAU
		worst = maxf(worst, maxf(absf(sc[0] - sin(radians) * ONE), absf(sc[1] - cos(radians) * ONE)))
	print("ORBIT sin/cos worst error %.2f units of 2^-30" % worst)
	assert_lt(worst, 4.0)


func test_angle_of_matches_floats_at_every_magnitude() -> void:
	var worst := 0.0
	for i in 5000:
		var size: int = [3, 1000, 1 << 30, 1 << 50, 1 << 61][i % 5]
		var x := rng.randi_range(-size, size)
		var y := rng.randi_range(-size, size)
		if x == 0 and y == 0:
			continue
		var exact := fposmod(atan2(float(y), float(x)), TAU) / TAU * TURN
		var gap := absf(OrbitMath.angle_of(y, x) - exact)
		worst = maxf(worst, minf(gap, TURN - gap))
	print("ORBIT angle_of worst error %.1f binary angle units of 2^-48" % worst)
	assert_lt(worst, 4096.0)
	assert_eq(OrbitMath.angle_of(0, 0), 0)
	assert_almost_eq(OrbitMath.angle_of(0, -5), OrbitMath.HALF_TURN, 16)
	assert_almost_eq(OrbitMath.angle_of(7, 0), OrbitMath.QUARTER_TURN, 16)


func test_kepler_is_solved_for_every_eccentricity() -> void:
	for e_thousandths in [0, 1, 100, 300, 600, 900, 950, 990]:
		var e: int = ONE * e_thousandths / 1000
		var worst := 0
		for i in 500:
			var m := _angle()
			var big_e := OrbitMath.eccentric_anomaly(m, e)
			var back := big_e - OrbitMath.to_angle(OrbitMath.smul_div(e, OrbitMath.sin_cos(big_e)[0], ONE))
			var gap := ((back - m + OrbitMath.HALF_TURN) & OrbitMath.ANGLE_MASK) - OrbitMath.HALF_TURN
			worst = maxi(worst, absi(gap))
		assert_lt(worst, 1 << 20, "e = %d/1000, within 4e-9 of a turn" % e_thousandths)


# ------------------------------------------------------------------------------ positions

func test_positions_match_the_float_reference() -> void:
	for scale: Array in [[GM_MOON, 250_000_000], [GM_PLANET, 700_000_000], [GM_PLANET, 40_000_000_000],
			[GM_STAR, AU_MM]]:
		var worst_ratio := 0.0
		for i in 40:
			var orbit := _random_orbit(scale[0], scale[1], rng.randi_range(0, ONE * 9 / 10))
			for tick in [0, 777, 123457, 9_999_991]:
				var gap := _gap(OrbitMath.position_at(orbit, tick), position_float(orbit, tick))
				worst_ratio = maxf(worst_ratio, gap / scale[1])
		print("ORBIT position against floats at a = %d mm: worst %.2f parts per billion of a" % [
			scale[1], worst_ratio * 1e9])
		assert_lt(worst_ratio, 2e-8)


func test_a_circular_period_matches_the_formula() -> void:
	var orbit := OrbitMath.make_orbit(GM_PLANET, 700_000_000, 0, [ONE, 0, 0], [0, 0, -ONE], 0, 0)
	var exact := TAU * sqrt(pow(700_000.0, 3) / 3.5316e12) * Sim.TICKS_PER_SECOND * OrbitMath.SUB_TICKS
	assert_almost_eq(float(orbit["period_subticks"]), exact, exact * 1e-8)


func test_an_orbit_has_no_drift() -> void:
	var orbit := _random_orbit(GM_PLANET, 900_000_000, ONE / 5)
	var start: int = orbit["epoch_tick"]
	var whole: int = orbit["period_subticks"]
	# period_sub ticks is exactly SUB_TICKS whole periods, so the orbit is exactly back where it began.
	for k in [1, 7, 1000]:
		assert_eq(OrbitMath.position_at(orbit, start + whole * k), OrbitMath.position_at(orbit, start))
	assert_eq(OrbitMath.mean_anomaly(orbit, start + whole * 1000), orbit["m0_angle"])


func test_an_orbit_record_saves_byte_exact() -> void:
	var orbit := _random_orbit(GM_STAR, AU_MM, ONE / 50)
	var text := Canon.encode(orbit)
	var loaded: Dictionary = Canon.decode(text)
	assert_eq(Canon.encode(loaded), text)
	for tick in [0, 5_000_000, 300_000_000]:
		assert_eq(OrbitMath.position_at(loaded, tick), OrbitMath.position_at(orbit, tick))


func test_directions_put_an_equatorial_orbit_on_plus_y() -> void:
	var dirs := OrbitMath.directions(0, 0, 0)
	assert_eq(dirs[0], [ONE, 0, 0], "periapsis towards +X")
	assert_eq(dirs[1], [0, 0, -ONE], "moving towards -Z")
	var orbit := OrbitMath.make_orbit(GM_PLANET, 700_000_000, 0, dirs[0], dirs[1], 0, 0)
	var state := OrbitMath.state_at(orbit, GM_PLANET, 0)
	var h := _cross(state["r"], state["v"])
	assert_gt(h[1], 0.0, "angular momentum along +Y")
	assert_almost_eq(absf(h[0]) + absf(h[2]), 0.0, h[1] * 1e-8)


# ------------------------------------------------------------------------------ velocity

func test_velocity_matches_vis_viva_and_the_path() -> void:
	for i in 60:
		var orbit := _random_orbit(GM_PLANET, rng.randi_range(650_000_000, 5_000_000_000),
			rng.randi_range(0, ONE * 8 / 10))
		var tick := rng.randi_range(0, 1_000_000)
		var state := OrbitMath.state_at(orbit, GM_PLANET, tick)
		var r := _length(state["r"]) / 1000.0
		var a := float(orbit["a_mm"]) / 1000.0
		var exact_speed := sqrt(3.5316e12 * (2.0 / r - 1.0 / a)) * 1e6
		assert_almost_eq(_length(state["v"]), exact_speed, exact_speed * 2e-8, "speed")
		# Direction against the path: a central difference over one tick either side.
		var ahead := OrbitMath.position_at(orbit, tick + 1)
		var behind := OrbitMath.position_at(orbit, tick - 1)
		var path := []
		for axis in 3:
			path.append(float(ahead[axis] - behind[axis]) * (1000.0 * Sim.TICKS_PER_SECOND / 2.0))
		assert_lt(_gap(path, state["v"]), exact_speed * 1e-4, "direction")


# ------------------------------------------------------------------------------ burn to new orbit

## The named risk of A8: converting a position and velocity back into an orbit. The result must
## trace the same path as the original for a whole period, to within 2 m plus 3e-7 of the orbit's
## size, times ((1 + e) / (1 - e))^1.5.
##
## Where it comes from: positions and speeds are good to a few parts per billion, from Q30 sines.
## Vis-viva magnifies a speed error by up to (1 + e) / (1 - e) in the orbit's size, and a period later
## the size error has become a gap along the path about ten times larger. The extra half power is
## measured, not derived: Kepler's equation is also worse conditioned near a sharp periapsis.
func test_state_to_orbit_round_trip_is_bounded() -> void:
	var cases := [
		["moon, low", GM_MOON, 250_000_000],
		["planet, low", GM_PLANET, 700_000_000],
		["planet, high", GM_PLANET, 40_000_000_000],
		["star, 1 AU", GM_STAR, AU_MM],
	]
	for case: Array in cases:
		var worst := 0
		var worst_round := 0
		for e_thousandths: int in [0, 1, 50, 300, 700, 900]:
			var allowed := 2000.0 + float(case[2]) * 3e-7 * pow((1000.0 + e_thousandths) / (1000 - e_thousandths), 1.5)
			for inclination in [0, TURN / 8, TURN / 4, TURN / 2, -1]:
				var orbit := _random_orbit(case[1], case[2], ONE * e_thousandths / 1000, inclination)
				var tick := rng.randi_range(0, 1_000_000)
				var state := OrbitMath.state_at(orbit, case[1], tick)
				var again := OrbitMath.from_state(state["r"], state["v"], case[1], tick)
				assert_false(again.is_empty(), "%s converts" % case[0])
				if not again.is_empty():
					var gap := _worst_gap(orbit, again, tick)
					assert_lt(float(gap), allowed, "%s, e = %d/1000" % [case[0], e_thousandths])
					worst = maxi(worst, gap)
					if e_thousandths <= 300:
						worst_round = maxi(worst_round, gap)
		print("ORBIT round trip, %s (a = %d mm): worst gap over a period %d mm, %d mm for e <= 0.3" % [
			case[0], case[2], worst, worst_round])


func test_converting_every_tick_for_a_minute_stays_bounded() -> void:
	# A finite burn converts once per tick. With no thrust it wanders like a random walk of the
	# single round trip's error, so 600 conversions stay within about 25 single ones.
	var orbit := _random_orbit(GM_PLANET, 700_000_000, ONE / 100, TURN / 16)
	var current := orbit
	var start := 5000
	for tick in range(start, start + 600):
		var state := OrbitMath.state_at(current, GM_PLANET, tick)
		current = OrbitMath.from_state(state["r"], state["v"], GM_PLANET, tick)
	var worst := _worst_gap(orbit, current, start + 600)
	print("ORBIT 600 conversions in a row: worst gap over the next period %d mm" % worst)
	assert_lt(worst, 100_000)


func test_a_prograde_burn_raises_apoapsis_as_hohmann_predicts() -> void:
	var r1 := 700_000.0
	var r2 := 760_000.0
	var mu := 3.5316e12
	var dv1_m_s := sqrt(mu / r1) * (sqrt(2.0 * r2 / (r1 + r2)) - 1.0)
	var orbit := OrbitMath.make_orbit(GM_PLANET, 700_000_000, 0, [ONE, 0, 0], [0, 0, -ONE], 0, 0)
	var state := OrbitMath.state_at(orbit, GM_PLANET, 100)
	var v: Array = state["v"]
	var speed := _length(v)
	var boosted := []
	for axis in 3:
		boosted.append(v[axis] + roundi(v[axis] / speed * dv1_m_s * 1e6))
	var after := OrbitMath.from_state(state["r"], boosted, GM_PLANET, 100)
	var apoapsis := float(after["a_mm"]) * (1.0 + float(after["e_q30"]) / ONE)
	var periapsis := float(after["a_mm"]) * (1.0 - float(after["e_q30"]) / ONE)
	assert_almost_eq(apoapsis, r2 * 1000.0, 1000.0, "apoapsis within 1 m of 760 km")
	assert_almost_eq(periapsis, r1 * 1000.0, 1000.0, "periapsis stays at 700 km")
	var half := int(after["period_subticks"]) / OrbitMath.SUB_TICKS / 2
	var far := _length(OrbitMath.position_at(after, 100 + half))
	assert_almost_eq(far, r2 * 1000.0, 20_000.0, "half an orbit later it is at the apoapsis")


func test_a_degenerate_state_is_refused() -> void:
	var r := [700_000_000, 0, 0]
	var escape_um := roundi(sqrt(2.0 * 3.5316e12 / 700_000.0) * 1e6)
	assert_eq(OrbitMath.from_state(r, [0, 0, -escape_um], GM_PLANET, 0), {}, "exactly parabolic")
	assert_true(OrbitMath.from_state(r, [0, 0, -escape_um * 2], GM_PLANET, 0)["hyperbolic"], "past escape")
	assert_eq(OrbitMath.from_state(r, [1_000_000, 0, 0], GM_PLANET, 0), {}, "straight up")
	assert_eq(OrbitMath.from_state([0, 0, 0], [0, 0, 1], GM_PLANET, 0), {}, "at the centre")


# ------------------------------------------------------------------------------ propellant

func test_rocket_equation_matches_floats() -> void:
	var worst := 0.0
	for dv_m_s in range(0, 6000, 37):
		var grams := OrbitMath.burn_g(1_000_000_000, dv_m_s * 1_000_000, 3_000_000)
		var exact := 1e9 * (1.0 - exp(-dv_m_s / 3000.0))
		worst = maxf(worst, absf(grams - exact) / 1e9)
	print("ORBIT rocket equation worst relative error %.2f parts per million" % (worst * 1e6))
	assert_lt(worst, 3e-6)
	assert_eq(OrbitMath.burn_g(680_000, 0, 3_000_000), 0)


# ------------------------------------------------------------------------------ cost

func test_cost_per_call() -> void:
	var orbits: Array[Dictionary] = []
	for i in 200:
		orbits.append(_random_orbit(GM_PLANET, 900_000_000, rng.randi_range(0, ONE * 3 / 10)))
	var states: Array[Dictionary] = []
	for orbit in orbits:
		states.append(OrbitMath.state_at(orbit, GM_PLANET, 4242))
	var positions := func() -> void:
		for orbit in orbits:
			OrbitMath.position_at(orbit, 4242)
	var to_states := func() -> void:
		for orbit in orbits:
			OrbitMath.state_at(orbit, GM_PLANET, 4242)
	var to_orbits := func() -> void:
		for state in states:
			OrbitMath.from_state(state["r"], state["v"], GM_PLANET, 4242)
	# Each cost is the fastest of five runs, so a loaded machine doesn't fail it (A45).
	var position_us := float(Timing.best_usec(positions)) / orbits.size()
	var state_us := float(Timing.best_usec(to_states)) / orbits.size()
	var convert_us := float(Timing.best_usec(to_orbits)) / orbits.size()
	print("ORBIT cost: position %.1f us, state %.1f us, state to orbit %.1f us" % [position_us, state_us, convert_us])
	assert_lt(position_us, 200.0)
	assert_lt(convert_us, 1000.0)


# ------------------------------------------------------------------------------ A12: hyperbolas and SOI

func test_exp_ln_sinh_and_cosh_match_floats() -> void:
	var worst := 0.0
	for i in 400:
		var x := rng.randi_range(0, 20 * ONE)
		var got := float(OrbitMath.exp_q30(x)) / ONE
		worst = maxf(worst, absf(got / exp(float(x) / ONE) - 1.0))
	print("ORBIT exp worst relative error %.2f parts per billion" % (worst * 1e9))
	assert_lt(worst, 5e-8)
	var ln_worst := 0.0
	for value: int in [1, 2, 3, 1000, ONE, 3_531_600_000, GM_STAR, 1 << 62]:
		ln_worst = maxf(ln_worst, absf(float(OrbitMath.ln(value)) / ONE - log(float(value))))
	assert_lt(ln_worst, 1e-8)
	for x: int in [-5 * ONE, -ONE / 3, 0, ONE / 7, 2 * ONE, 15 * ONE]:
		var sh := OrbitMath.sinh_cosh(x)
		var fx := float(x) / ONE
		assert_almost_eq(float(sh[0]) / ONE, sinh(fx), absf(sinh(fx)) * 5e-8 + 1e-8)
		assert_almost_eq(float(sh[1]) / ONE, cosh(fx), cosh(fx) * 5e-8)


func test_sphere_of_influence_matches_laplace() -> void:
	# Kerbin around Kerbol, whose figures are public: about 84,159 km.
	var soi := OrbitMath.soi_mm(13_599_840_256_000, 3_531_600_000, 1_172_332_800_000_000)
	assert_almost_eq(float(soi), 84_159_286_000.0, 84_159_286_000.0 * 1e-5)


func test_hyperbolic_positions_match_the_float_reference() -> void:
	var r := [700_000_000, 0, 0]
	for factor_permille: int in [1500, 2000, 3000, 5000]:
		var v := roundi(sqrt(3.5316e12 / 700_000.0) * 1e6 * factor_permille / 1000.0)
		var orbit := OrbitMath.from_state(r, [0, 0, -v], GM_PLANET, 1000)
		assert_true(orbit.get("hyperbolic", false), "hyperbolic at %d permille" % factor_permille)
		var worst := 0.0
		for tick in [1000, 1001, 1100, 2000, 6000, 20000]:
			var gap := _gap(OrbitMath.position_at(orbit, tick), position_float(orbit, tick))
			worst = maxf(worst, gap / maxf(1.0, _length(OrbitMath.position_at(orbit, tick))))
		assert_lt(worst, 1e-7, "factor %d permille, within 100 parts per billion of the distance" % factor_permille)
		assert_lt(_gap(OrbitMath.position_at(orbit, 1000), r), 2000.0, "it starts where it was made")


func test_hyperbolic_round_trip_is_bounded() -> void:
	var r := [700_000_000, 0, 0]
	for factor_permille: int in [1500, 2000, 3000]:
		var v := roundi(sqrt(3.5316e12 / 700_000.0) * 1e6 * factor_permille / 1000.0)
		var orbit := OrbitMath.from_state(r, [0, 30_000_000, -v], GM_PLANET, 0)
		var state := OrbitMath.state_at(orbit, GM_PLANET, 500)
		var again := OrbitMath.from_state(state["r"], state["v"], GM_PLANET, 500)
		assert_true(again.get("hyperbolic", false))
		var worst := 0
		for tick in [500, 1000, 3000, 10000]:
			worst = maxi(worst, IntMath.dist(OrbitMath.position_at(orbit, tick), OrbitMath.position_at(again, tick)))
		print("ORBIT hyperbolic round trip at %d permille of circular speed: worst gap %d mm" % [factor_permille, worst])
		assert_lt(worst, 50_000)
