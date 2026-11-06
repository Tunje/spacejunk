extends GutTest
## The new start, stage 6 (C16): from its low orbit round Frost, the probe flies home to the station
## in the cluster and docks. Starts from the game saved after test_new_start_lap.gd's stage.

var bot: NewStartBot


func before_all() -> void:
	bot = NewStartBot.from_snapshot(NewStartBot.STAGE_FROST_LAP)
	var start := bot.total_ticks()
	bot.play_through(NewStartBot.STAGE_RETURN)
	gut.p("home: ticks %d to %d" % [start, bot.total_ticks()])
	for line in bot.report(start, ["home"]):
		gut.p(line)


func test_the_trip_home_runs_with_every_ledger_balanced() -> void:
	assert_eq(bot.problems, PackedStringArray())
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())
	assert_true(bot.marks.has("home"))
	assert_eq(bot.snapshot_mismatch(NewStartBot.STAGE_RETURN), "", "the next file starts from here")


func test_the_probe_comes_home_and_docks_at_the_station() -> void:
	var probe: Dictionary = bot.marks["home"]["units"][NewStartBot.PROBE]
	assert_eq(probe["dock"].get("target_unit", 0), bot.station)
	assert_gt(probe["cargo"]["propellant"]["used_g"], 0, "with propellant to spare")
