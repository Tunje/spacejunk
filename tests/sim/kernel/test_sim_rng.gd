extends GutTest


func _draws(rng: SimRng, stream: String, count: int) -> Array[int]:
	var values: Array[int] = []
	for i in count:
		values.append(rng.next_u32(stream))
	return values


func test_same_seed_gives_the_same_draws() -> void:
	assert_eq(_draws(SimRng.new({}, 42), "scan", 20), _draws(SimRng.new({}, 42), "scan", 20))


func test_different_seeds_and_names_differ() -> void:
	assert_ne(_draws(SimRng.new({}, 42), "scan", 20), _draws(SimRng.new({}, 43), "scan", 20))
	assert_ne(_draws(SimRng.new({}, 42), "scan", 20), _draws(SimRng.new({}, 42), "fault", 20))


func test_a_draw_in_one_stream_does_not_shift_another() -> void:
	var alone := SimRng.new({}, 42)
	var mixed := SimRng.new({}, 42)
	var expected := _draws(alone, "scan", 20)
	var got: Array[int] = []
	for i in 20:
		mixed.next_u32("fault")
		got.append(mixed.next_u32("scan"))
	assert_eq(got, expected)


func test_stream_start_does_not_depend_on_creation_order() -> void:
	var first := SimRng.new({}, 42)
	var second := SimRng.new({}, 42)
	second.next_u32("fault")
	assert_eq(first.next_u32("scan"), second.next_u32("scan"))


func test_saved_stream_map_resumes_exactly() -> void:
	var streams := {}
	var rng := SimRng.new(streams, -5)
	_draws(rng, "scan", 7)
	var resumed := SimRng.new(streams.duplicate(), -5)
	assert_eq(_draws(resumed, "scan", 50), _draws(rng, "scan", 50))


func test_below_stays_in_bounds() -> void:
	var rng := SimRng.new({}, 1)
	for i in 500:
		var value := rng.below("scan", 7)
		assert_true(value >= 0 and value < 7)
	assert_eq(rng.below("scan", 1), 0)
