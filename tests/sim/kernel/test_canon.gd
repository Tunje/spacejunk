extends GutTest


func test_scalars() -> void:
	assert_eq(Canon.encode(120), "\"120\"")
	assert_eq(Canon.encode(-1), "\"-1\"")
	assert_eq(Canon.encode("hematite"), "\"s:hematite\"")
	assert_eq(Canon.encode(true), "true")
	assert_eq(Canon.encode(false), "false")


func test_full_int_range_is_exact() -> void:
	assert_eq(Canon.encode(9223372036854775807), "\"9223372036854775807\"")
	assert_eq(Canon.encode(-9223372036854775807 - 1), "\"-9223372036854775808\"")


func test_a_number_and_its_text_stay_distinct() -> void:
	assert_ne(Canon.encode(7), Canon.encode("7"))
	assert_ne(Canon.encode({ 7: 1 }), Canon.encode({ "7": 1 }))
	var both := { 7: 1, "7": 2 }
	assert_eq(Canon.encode(both), "{\"7\":\"1\",\"s:7\":\"2\"}")


func test_map_keys_sort_numerically_then_by_code_point() -> void:
	var map := { "b": 1, 10: 2, "B": 3, 9: 4, "a_b": 5, "ab": 6, -1: 7 }
	assert_eq(
		Canon.encode(map),
		"{\"-1\":\"7\",\"9\":\"4\",\"10\":\"2\",\"s:B\":\"3\",\"s:a_b\":\"5\",\"s:ab\":\"6\",\"s:b\":\"1\"}"
	)


func test_insertion_order_never_shows() -> void:
	var forward := {}
	var backward := {}
	for i in 50:
		forward[i] = i
		backward[49 - i] = 49 - i
	assert_eq(Canon.encode(forward), Canon.encode(backward))


func test_arrays_keep_their_order() -> void:
	assert_eq(Canon.encode([3, 1, 2]), "[\"3\",\"1\",\"2\"]")


func test_strings_escape() -> void:
	assert_eq(Canon.encode("a\"b\\c"), "\"s:a\\\"b\\\\c\"")
	assert_eq(Canon.encode("a\nb"), "\"s:a\\u000ab\"")


func test_a_float_is_a_hard_error_with_a_path() -> void:
	assert_eq(Canon.encode({ "units": { 7: { "mass": 1.0 } } }), "")
	assert_string_contains(Canon.error, "$.units.7.mass")
	assert_string_contains(Canon.error, "float")


func test_other_types_are_hard_errors() -> void:
	for bad: Variant in [null, Vector3i(1, 2, 3), &"name", RefCounted.new()]:
		assert_eq(Canon.encode([bad]), "", str(bad))
	assert_eq(Canon.encode({ 1.5: 1 }), "")


func test_error_clears_after_a_success() -> void:
	Canon.encode(1.5)
	Canon.encode(1)
	assert_eq(Canon.error, "")
