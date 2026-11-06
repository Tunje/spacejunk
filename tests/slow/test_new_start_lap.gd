extends GutTest
## The new start, stage 4 (C18): the probe, docked at the station inside the cluster, maps Frost's
## gravity field over one lap of the cluster's own orbit round Frost, warped (C17). Starts from the
## game saved after test_new_start_lab.gd's stage.

var bot: NewStartBot


func before_all() -> void:
	bot = NewStartBot.from_snapshot(NewStartBot.STAGE_LAB)
	var start := bot.total_ticks()
	bot.play_through(NewStartBot.STAGE_LAP)
	gut.p("the lap: ticks %d to %d" % [start, bot.total_ticks()])
	for line in bot.report(start, ["gravity_mapped"]):
		gut.p(line)


func test_the_lap_runs_with_every_ledger_balanced() -> void:
	assert_eq(bot.problems, PackedStringArray())
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())
	assert_true(bot.marks.has("gravity_mapped"))
	assert_eq(bot.snapshot_mismatch(NewStartBot.STAGE_LAP), "", "the next file starts from here")


func test_one_lap_of_the_cluster_maps_frosts_gravity_field() -> void:
	var view: Dictionary = bot.marks["gravity_mapped"]
	var probe: Dictionary = bot.sim._state["units"][NewStartBot.PROBE]
	assert_true(probe["landed"].is_empty(), "no landing")
	assert_ne(probe["frame"], 0, "still in the cluster")
	var frame: Dictionary = bot.sim._state["frames"][probe["frame"]]
	assert_eq(frame["orbit"]["parent"], NewStartBot.FROST)
	var period: int = (frame["orbit"]["period_subticks"] + OrbitMath.SUB_TICKS - 1) / OrbitMath.SUB_TICKS
	var lap: Array = bot.steps.filter(func(step: Dictionary) -> bool: return step["label"] == "measure")
	assert_eq(lap.size(), 1)
	assert_eq(lap[0]["ticks"], period + 1, "one lap, then the task ends on the next tick")
	assert_eq(view["science"]["paid"].get("gravity_field:%d" % NewStartBot.FROST, 0), 1)
	assert_eq(view["science"]["points"], 4 * 10 + 3 * 20 + 40, "surveys, compositions and the lap")
