extends "res://tests/sim/kernel/coast_fixture.gd"
## The coast time warp's long cases (A33, moved here in A35): a whole lap through the moon's shadow,
## and a landing's half ellipse, each stepped one way and coasted the other.


func test_a_lap_through_the_shadow_coasts_exactly_as_it_steps() -> void:
	var stepped := _game()
	var coasted := _copy(stepped)
	# The lap's reference copy runs unchecked, to keep the file quick: strict stepping is covered by
	# the shorter cases.
	var calls := _same_both_ways(stepped, coasted, LAP_TICKS, false)
	print("COAST a %d-tick lap with batteries and a shadow: %d coast calls" % [LAP_TICKS, calls])
	print("PERF coast: %.2f ms a call over the lap, %.0f ms in all (budget 2 ms a jump at slice size)" % [
		_last_coast_ms / calls, _last_coast_ms])
	assert_lt(calls, LAP_TICKS / 20, "most of the lap was skipped")
	assert_lt(_last_coast_ms / calls, 20.0, "ten times the budget fails; the PERF line is the measure")


func test_a_landing_coasts_to_its_touchdown() -> void:
	var stepped := _game()
	var cell := LandingSystem.cell_below(stepped._ctx, keys["Moon"], stepped._state["units"][keys["Probe"]]["pos_mm"])
	var land := { "type": "land", "unit": keys["Probe"], "args": { "body": keys["Moon"], "cell": cell } }
	var checked := stepped.check(land)
	assert_true(checked["ok"], str(checked))
	stepped.submit(land)
	var coasted := _copy(stepped)
	var calls := _same_both_ways(stepped, coasted, checked["detail"]["ticks"] + 50)
	assert_false(stepped._state["units"][keys["Probe"]]["landed"].is_empty(), "landed")
	assert_lt(calls, 20, "the half ellipse was skipped")
