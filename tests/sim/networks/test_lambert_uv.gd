extends GutTest
## The universal-variable Lambert solver (stage 3a, docs/design/stage3_plan.md section 1). Its
## acceptance: the 50 km trip in 30 minutes on the cluster's own circle, which A47's shooting
## missed by kilometres, now hits within 1 m with the delta-v of the float answer, and so do other
## arcs, in under a millisecond or so.

const ONE := OrbitMath.ONE
const Timing := preload("res://tests/sim/kernel/timing.gd")

var gm := 0
var cluster: Dictionary
var frost := 0


func before_all() -> void:
	var game := Sim.new_game("new_start", 1)
	for id: int in game._state["bodies"]:
		if game._state["bodies"][id]["name"] == "Frost":
			frost = id
	gm = game._state["bodies"][frost]["gm"]
	for id: int in game._state["frames"]:
		cluster = game._state["frames"][id]["orbit"].duplicate(true)
	cluster["parent"] = frost


func _ahead(metres: int) -> Dictionary:
	var ahead := cluster.duplicate(true)
	ahead["m0_angle"] = (int(cluster["m0_angle"]) + IntMath.mul_div(OrbitMath.TURN, metres * 1000,
		IntMath.mul_div(int(cluster["a_mm"]), OrbitMath.TWO_PI, ONE))) & OrbitMath.ANGLE_MASK
	return ahead


## The same problem in doubles, by the same universal-variable equations, for the delta-v check.
func _float_v1(r1: Array, r2: Array, seconds: float, mu: float) -> Array:
	var a := Vector3(r1[0], r1[1], r1[2]) / 1000.0
	var b := Vector3(r2[0], r2[1], r2[2]) / 1000.0
	var ra := a.length()
	var rb := b.length()
	var cos_dnu := a.dot(b) / (ra * rb)
	var big_a := sqrt(ra * rb * (1.0 + cos_dnu))
	var stump := func(z: float) -> Array:
		if z > 1e-6:
			return [(1.0 - cos(sqrt(z))) / z, (sqrt(z) - sin(sqrt(z))) / pow(sqrt(z), 3)]
		if z < -1e-6:
			return [(cosh(sqrt(-z)) - 1.0) / -z, (sinh(sqrt(-z)) - sqrt(-z)) / pow(sqrt(-z), 3)]
		return [0.5, 1.0 / 6.0]
	var low := -4.0 * PI * PI
	var high := 4.0 * PI * PI
	var y_of := func(z: float) -> float:
		var cs: Array = stump.call(z)
		return ra + rb + big_a * (z * cs[1] - 1.0) / sqrt(cs[0])
	for i in 200:
		var mid := (low + high) / 2.0
		var y: float = y_of.call(mid)
		var t := -1.0
		if y >= 0.0:
			var cs: Array = stump.call(mid)
			var chi := sqrt(y / cs[0])
			t = (chi * chi * chi * cs[1] + big_a * sqrt(y)) / sqrt(mu)
		if t < seconds:
			low = mid
		else:
			high = mid
	var y_final: float = y_of.call((low + high) / 2.0)
	var f := 1.0 - y_final / ra
	var g := big_a * sqrt(y_final / mu)
	var v := (b - f * a) / g
	return [v.x * 1e6, v.y * 1e6, v.z * 1e6]


func test_stumpff_at_zero_and_across_the_series_edge() -> void:
	var at_zero := Lambert.stumpff(0)
	assert_almost_eq(at_zero[0], ONE / 2, 2)
	assert_almost_eq(at_zero[1], ONE / 6, 2)
	for edge: int in [Lambert.SERIES_Z, -Lambert.SERIES_Z]:
		var inside := Lambert.stumpff(edge - (1 if edge > 0 else -1))
		var outside := Lambert.stumpff(edge + (1 if edge > 0 else -1))
		assert_almost_eq(inside[0], outside[0], 64, "C is continuous at %d" % edge)
		assert_almost_eq(inside[1], outside[1], 64, "S is continuous at %d" % edge)


## The case stage 0 found A47 missing: 50 km ahead on the cluster's circle, in 30 minutes.
func test_the_cluster_rendezvous_hits_within_a_metre() -> void:
	var target := _ahead(50_000)
	var now := OrbitMath.state_at(cluster, gm, 0)
	var normal := Relative.normal_of(cluster)
	var hit := Lambert.solve_uv(gm, now["r"], target, 0, 18_000, normal)
	assert_false(hit.is_empty(), "it hits")
	assert_lte(hit["miss_mm"], 1_000, "within a metre")
	var expected := _float_v1(now["r"], OrbitMath.position_at(target, 18_000), 1800.0, gm * 1000.0)
	var dv := IntMath.dist([hit["v"][0] - now["v"][0], hit["v"][1] - now["v"][1], hit["v"][2] - now["v"][2]], [0, 0, 0])
	var dv_float := Vector3(expected[0] - now["v"][0], expected[1] - now["v"][1], expected[2] - now["v"][2]).length()
	print("UV Lambert, 50 km in 30 min: miss %d mm, dv %d um/s (float %.0f)" % [hit["miss_mm"], dv, dv_float])
	assert_almost_eq(float(dv), dv_float, dv_float * 0.01, "the float answer's delta-v, to 1%")


func test_a_range_of_arcs_hits_within_a_metre() -> void:
	var now := OrbitMath.state_at(cluster, gm, 0)
	var normal := Relative.normal_of(cluster)
	var period := int(cluster["period_subticks"]) / OrbitMath.SUB_TICKS
	# Rendezvous of 5 to 100 km, and quarter and near-half turns, short and long in time.
	for case: Array in [[5_000, 6_000], [50_000, 3_000], [50_000, 60_000], [100_000, 36_000],
			[470_000, period / 4], [900_000, period * 2 / 5]]:
		var target := _ahead(case[0])
		var hit := Lambert.solve_uv(gm, now["r"], target, 0, case[1], normal)
		assert_false(hit.is_empty(), "%d m in %d ticks" % case)
		if not hit.is_empty():
			assert_lte(hit["miss_mm"], 1_000, "%d m in %d ticks: %d mm" % [case[0], case[1], hit["miss_mm"]])


func test_a_solve_costs_about_a_millisecond_at_most() -> void:
	var target := _ahead(50_000)
	var now := OrbitMath.state_at(cluster, gm, 0)
	var normal := Relative.normal_of(cluster)
	var took: int = Timing.best_usec(func() -> void: Lambert.solve_uv(gm, now["r"], target, 0, 18_000, normal))
	var r2 := OrbitMath.position_at(target, 18_000)
	var guess_only: int = Timing.best_usec(func() -> void: Lambert.universal(gm, now["r"], r2, 18_000, normal))
	print("PERF UV Lambert solve: %d us, of which the universal-variable answer %d us" % [took, guess_only])
	assert_lt(took, 5_000, "a few ms at worst on a loaded machine")


## A trip of one and a half turns to a point 50 km ahead: one whole revolution on either arc.
func test_one_revolution_arcs_hit_on_both_branches() -> void:
	var now := OrbitMath.state_at(cluster, gm, 0)
	var normal := Relative.normal_of(cluster)
	var period := int(cluster["period_subticks"]) / OrbitMath.SUB_TICKS
	var target := _ahead(50_000)
	var arrive := period * 3 / 2
	var costs: Array[int] = []
	for low_branch: bool in [true, false]:
		var hit := Lambert.solve_uv(gm, now["r"], target, 0, arrive, normal, 1, low_branch)
		assert_false(hit.is_empty(), "branch %s" % low_branch)
		if hit.is_empty():
			continue
		assert_lte(hit["miss_mm"], 1_000)
		costs.append(IntMath.dist([hit["v"][0] - now["v"][0], hit["v"][1] - now["v"][1], hit["v"][2] - now["v"][2]], [0, 0, 0]))
	if costs.size() == 2:
		assert_ne(costs[0], costs[1], "two different arcs")
	assert_eq(Lambert.universal_revs(gm, now["r"], OrbitMath.position_at(target, period / 2), period / 2, normal, 1, true), [],
		"half a turn can't hold a whole revolution")
