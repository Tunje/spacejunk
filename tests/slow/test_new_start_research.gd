extends GutTest
## The new start, stage 5 (C16): research.md section 5's route at the station:
## Autonomous Navigation proven at the station's lab, the Assisted Core prototyped on the probe and
## bench-tested, so it is qualified. Starts from the game saved after test_new_start_lap.gd's stage.

var bot: NewStartBot


func before_all() -> void:
	bot = NewStartBot.from_snapshot(NewStartBot.STAGE_LAP)
	var start := bot.total_ticks()
	bot.play_through(NewStartBot.STAGE_RESEARCH)
	gut.p("research: ticks %d to %d (%.1f game hours in all)" % [start, bot.total_ticks(),
		bot.total_ticks() / 36000.0])
	for line in bot.report(start, ["proven", "prototyped", "qualified"]):
		gut.p(line)


func test_research_runs_with_every_ledger_balanced() -> void:
	assert_eq(bot.problems, PackedStringArray())
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())
	assert_true(bot.marks.has("qualified"))
	assert_eq(bot.snapshot_mismatch(NewStartBot.STAGE_RESEARCH), "", "the snapshot regenerates the same")


func test_autonomous_navigation_is_proven_with_80_points() -> void:
	var view: Dictionary = bot.marks["proven"]
	assert_true(view["research"]["theories"].has("autonomous_navigation"))
	assert_eq(view["research"]["designs"].get("assisted_core"), "prototype")
	assert_eq(view["science"]["spent"], 80)


func test_the_assisted_core_is_prototyped_and_qualified() -> void:
	assert_eq(bot.marks["qualified"]["research"]["designs"].get("assisted_core"), "qualified")
	var check := bot.sim.check({ "type": "start_job", "unit": NewStartBot.PROBE,
		"args": { "facility": bot.fabricator, "recipe": "assisted_core", "count": 1 } })
	assert_ne(check["reason"], "design_unqualified", "its normal recipe is open")
	assert_ne(check["reason"], "theory_locked")
