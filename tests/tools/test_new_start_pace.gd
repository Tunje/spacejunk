extends GutTest
## tools/new_start_pace.gd prices the new-start bot's route for a person, for balance.md section 9.
## The route itself is C's slow files' to test; these check the pricing.


func test_a_command_sooner_than_the_think_time_makes_the_chain_slip() -> void:
	# 4 s to think at 1x: the first order waits 4 s, and the next, 1 s of game later, 3 s more.
	var paced := NewStartPace.pace([0, 10] as Array[int], {}, 4, 1, 0, 0)
	assert_almost_eq(paced["real_s"], 8.0, 0.001)
	assert_eq(paced["slip_ticks"], 70)
	assert_eq(paced["game_ticks"], 80)


func test_a_long_wait_is_warped_after_the_set_real_time() -> void:
	# 10,000 s of game at 1x: 4 s to think, 10 s more at 1x, and the rest at 1000x.
	var paced := NewStartPace.pace([0, 100_000] as Array[int], {}, 4, 1, 1000, 10)
	assert_almost_eq(paced["real_s"], 4.0 + 14.0 + 9.986, 0.001)
	assert_almost_eq(paced["warped_s"], 9.986, 0.001)
	assert_eq(paced["slip_ticks"], 40, "only the first order was late")


func test_without_warp_a_wait_runs_at_the_chosen_speed() -> void:
	var paced := NewStartPace.pace([0, 100_000] as Array[int], {}, 4, 8, 0, 0)
	assert_almost_eq(paced["real_s"], 4.0 + 100_000 / 80.0, 0.001)
	assert_eq(paced["warped_s"], 0.0)


func test_a_goal_is_timed_from_the_start_with_the_slips() -> void:
	var paced := NewStartPace.pace([0] as Array[int], { "scan": 50 }, 4, 1, 0, 0)
	assert_almost_eq(paced["goals_real_s"]["scan"], 9.0, 0.001)


func test_the_tracker_scores_the_new_start_goals() -> void:
	var pace := NewStartPace.new()
	assert_eq(pace.tracker.goals.size(), GoalTracker.NEW_START_GOALS.size())
