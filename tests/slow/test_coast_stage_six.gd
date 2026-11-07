extends GutTest
## The coast soak's stage-6 seed in the gate (C22): the new start's drone, from its stage snapshot,
## flies two laps of its real cycle to Red Rock and back, stepped one way and coasted the other,
## compared at every coast return. It has its own file because it takes about 6 s.

const CoastSoak := preload("res://tests/sim/kernel/coast_soak.gd")


func test_the_stage_six_drone_coasts_exactly_as_it_steps() -> void:
	var result: Dictionary = CoastSoak.run_seed(9, CoastSoak.STAGE_SIX_TICKS)
	gut.p("seed 9: %d ticks in %d coast calls, capped by %s, events %s" % [result["ticks"], result["calls"],
		str(result["caps"]), str(result["events"])])
	assert_true(result["ok"], result["message"])
	assert_eq(result["events"].get("task_cycle_done", 0), 2, "two laps")
	assert_lt(result["calls"], 60, "the laps coast")
