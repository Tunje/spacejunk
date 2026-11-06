extends GutTest
## The new start, stage 3 (C16): the probe builds the research lab in place on the station, whose
## core it assigns. Starts from the game saved after test_new_start_prep.gd's stage.

var bot: NewStartBot


func before_all() -> void:
	bot = NewStartBot.from_snapshot(NewStartBot.STAGE_PREP)
	var start := bot.total_ticks()
	bot.play_through(NewStartBot.STAGE_LAB)
	gut.p("the lab: ticks %d to %d" % [start, bot.total_ticks()])
	for line in bot.report(start, ["research_ready"]):
		gut.p(line)


func test_the_stage_runs_with_every_ledger_balanced() -> void:
	assert_eq(bot.problems, PackedStringArray())
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())
	assert_true(bot.marks.has("research_ready"))
	assert_eq(bot.snapshot_mismatch(NewStartBot.STAGE_LAB), "", "the next file starts from here")


func test_the_station_is_ready_for_research() -> void:
	var station: Dictionary = bot.marks["research_ready"]["units"][bot.station]
	var defs: Array = InspectText.flatten(station["parts"]).map(func(part: Dictionary) -> String: return part["def"])
	for def in ["research_lab_mk1", "goods_container_mk1", "basic_core"]:
		assert_has(defs, def, "built in place")
	assert_eq(defs.count("solar_panel_mk1"), 2)
	assert_eq(station["core"], bot.station_core)
	assert_eq(station["core_tier"], 1, "enough for an era 2 theory")
