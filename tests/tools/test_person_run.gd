extends GutTest
## tools/person_run.gd plays the slice for docs/design/balance.md. If data/ stops letting it reach
## all ten checks, the report's figures are stale. One run stands for both plans.

var person: PersonRun


func before_all() -> void:
	person = PersonRun.new(PersonRun.PLAN_DIRECT, 8, 4)
	person.run()


func test_a_person_reaches_all_ten_checks() -> void:
	assert_eq(person.problems, PackedStringArray())
	assert_eq(person.tracker.done_count(), GoalTracker.GOALS.size())


func test_a_person_fits_every_drone_part_after_the_hull_appears() -> void:
	assert_gt(person.marks["drone_fitted"], person.marks["drone_built"])


func test_running_the_refinery_and_fabricator_together_sheds_nothing() -> void:
	assert_eq(person.shed_events, 0)
	assert_false(person.paused_reasons.has(JobSystem.REASON_NO_POWER))
	assert_false(person.paused_reasons.has(JobSystem.REASON_OUTPUT_FULL))


func test_think_time_takes_game_ticks_at_the_chosen_speed() -> void:
	assert_eq(person.think_ticks, 4 * Sim.TICKS_PER_SECOND * 8)
	assert_eq(person.command_ticks[1] - person.command_ticks[0], person.think_ticks + 100 + 1)
