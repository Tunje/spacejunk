extends GutTest

const MAX := 9223372036854775807

# Exact results from System.Numerics.BigInteger: a, b, d, floor(a * b / d).
const MUL_DIV_VECTORS := [
	[31186043429910, 22143792215362885, 1059929356195831, 651531407913585],
	[32581342613079213, 650001080330, 151836394548922006, 139478469309],
	[1792501734391, 402656933354991, 11626861045090193, 62077223474],
	[1825919775425, 7268238029603, 2354994922, 5635349540149944],
	[909609104282, 137316477584039, 523074152837076481, 238788931],
	[8540757435145, 5882201779068779915, 184312812904011212, 272571709953602],
	[4589138180184, 292678657017967, 127723397809, 10516027779457382],
	[16738672761948080, 1106881399326298, 26732500942808, 693078644951650205],
	[560651416457, 8684342800600, 2452490726636345, 1985283385],
	[2112122600987382, 2385641196270848, 966137699620893, 5215371153063809],
	[2928988184803409666, 3348995402319, 1074529557669, 9128802362247280365],
	[70013359899674, 1476126490356267, 2812617763607846285, 36744621528],
	[312102361691719220, 754045410803, 282153183458711994, 834083637297],
	[1696761603078386, 11683068475591, 7381715994352, 2685470696879408],
	[4071124681920812410, 3215357864154, 123343722631680634, 106127190607455],
	[1330492943098, 4087236106459903, 74139812250, 73348429560128091],
]

# Exact results from System.Numerics.BigInteger: dx, dy, dz, floor(sqrt(dx^2 + dy^2 + dz^2)).
const DIST_VECTORS := [
	[1709363855451779253, 1113430307545635256, 935691098026603010, 2244363979173692136],
	[294417706690474208, 2203265520336562164, 1022236057846026250, 2446635914286677115],
	[1700326240234670931, 2071499708371823476, 1197454113788839235, 2935322251413792545],
	[704157603398344830, 1085128249596678337, 1755319591349317455, 2180478873154057082],
	[2099276108322891088, 656276855601554957, 2105418113681754661, 3044740534691388931],
	[1779546844584478678, 56897109872859812, 2223752189552088686, 2848701116951402390],
	[2177994654702632947, 1490662203635535789, 165055355218303059, 2644423905418159899],
	[1956736190336142271, 1864312092858310955, 648644204165675392, 2779427171513342139],
	[1073620648968497926, 1453380131230072213, 1584179225008296135, 2403039517089506026],
	[975833593810458200, 518066027033115115, 1104034648624183802, 1561901442645353240],
]


func test_mul_div_matches_big_integer_results() -> void:
	for row: Array in MUL_DIV_VECTORS:
		assert_eq(IntMath.mul_div(row[0], row[1], row[2]), row[3], str(row))
		assert_eq(IntMath.mul_div(row[1], row[0], row[2]), row[3], "swapped %s" % str(row))


func test_mul_div_at_the_limits() -> void:
	assert_eq(IntMath.mul_div(MAX, MAX, MAX), MAX)
	assert_eq(IntMath.mul_div(MAX, 1, 1), MAX)
	assert_eq(IntMath.mul_div(MAX, MAX - 1, MAX), MAX - 1)
	assert_eq(IntMath.mul_div(1_000_000_000_000_000, 1_000_000_000_000, 1_000_000_000_000), 1_000_000_000_000_000)
	assert_eq(IntMath.mul_div(0, MAX, 1), 0)


func test_mul_div_floors() -> void:
	assert_eq(IntMath.mul_div(7, 1, 2), 3)
	assert_eq(IntMath.mul_div(10, 10, 3), 33)


func test_mul_div_reports_an_unrepresentable_result() -> void:
	assert_eq(IntMath.mul_div(MAX, 2, 1), MAX)
	assert_push_error("does not fit")


func test_isqrt() -> void:
	assert_eq(IntMath.isqrt(0), 0)
	assert_eq(IntMath.isqrt(1), 1)
	assert_eq(IntMath.isqrt(15), 3)
	assert_eq(IntMath.isqrt(16), 4)
	assert_eq(IntMath.isqrt(MAX), 3037000499)


func test_dist_matches_big_integer_results() -> void:
	for row: Array in DIST_VECTORS:
		assert_eq(IntMath.dist([0, 0, 0], [row[0], row[1], row[2]]), row[3], str(row))


func test_dist_uses_differences_and_ignores_sign() -> void:
	assert_eq(IntMath.dist([1, 2, 3], [4, 6, 3]), 5)
	assert_eq(IntMath.dist([4, 6, 3], [1, 2, 3]), 5)
	assert_eq(IntMath.dist([-3, 0, 0], [0, -4, 0]), 5)


func test_dist_is_exact_either_side_of_a_wide_square() -> void:
	var side := 3_000_000_000_000_000_000
	assert_eq(IntMath.dist([0, 0, 0], [side, 0, 0]), side)
	assert_eq(IntMath.dist([0, 0, 0], [side, 1, 0]), side)
	# (3k, 4k, 0) is a whole-number length, and one less on an axis falls just below it.
	var k := 400_000_000_000_000_000
	assert_eq(IntMath.dist([0, 0, 0], [3 * k, 4 * k, 0]), 5 * k)
	assert_eq(IntMath.dist([0, 0, 0], [3 * k - 1, 4 * k, 0]), 5 * k - 1)


func test_dist_across_the_narrow_and_wide_paths_agrees() -> void:
	var near := IntMath.NARROW_AXIS_LIMIT
	assert_eq(IntMath.dist([0, 0, 0], [near, 0, 0]), near)
	assert_eq(IntMath.dist([0, 0, 0], [near + 1, 0, 0]), near + 1)


func test_dist_at_the_position_limit_along_one_axis() -> void:
	var limit := 4_000_000_000_000_000_000
	assert_eq(IntMath.dist([-limit, 0, 0], [limit, 0, 0]), 2 * limit)


func test_dist_reports_a_length_past_63_bits() -> void:
	var limit := 4_000_000_000_000_000_000
	assert_eq(IntMath.dist([-limit, -limit, -limit], [limit, limit, limit]), MAX)
	assert_push_error("does not fit")
