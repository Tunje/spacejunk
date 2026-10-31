extends GutTest

func test_64_bit_integers_keep_exact_values() -> void:
	var near_limit: int = 9_007_199_254_740_993
	assert_eq(near_limit + 1, 9_007_199_254_740_994)

func test_client_scene_loads() -> void:
	assert_not_null(load("res://client/main.tscn"))
