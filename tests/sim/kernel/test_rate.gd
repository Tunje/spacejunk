extends GutTest


func test_a_rate_delivers_exactly_over_one_second() -> void:
	for rate: int in [0, 1, 7, 9, 10, 15, 1234567]:
		var remainder := 0
		var total := 0
		for i in Sim.TICKS_PER_SECOND:
			total += Rate.amount(rate, remainder)
			remainder = Rate.carry(rate, remainder)
		assert_eq(total, rate, "rate %d" % rate)
		assert_eq(remainder, 0, "rate %d" % rate)


func test_small_rate_waits_for_a_whole_unit() -> void:
	assert_eq(Rate.amount(1, 0), 0)
	assert_eq(Rate.carry(1, 0), 1)
	assert_eq(Rate.amount(1, Sim.TICKS_PER_SECOND - 1), 1)
	assert_eq(Rate.carry(1, Sim.TICKS_PER_SECOND - 1), 0)


func test_remainder_stays_below_the_tick_rate_at_the_top_of_the_range() -> void:
	var rate := 1_000_000_000_000
	assert_eq(Rate.amount(rate, Sim.TICKS_PER_SECOND - 1), rate / Sim.TICKS_PER_SECOND)
	assert_lt(Rate.carry(rate + 3, Sim.TICKS_PER_SECOND - 1), Sim.TICKS_PER_SECOND)
