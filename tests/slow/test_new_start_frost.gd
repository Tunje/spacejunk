extends GutTest
## The new start, stage 4 (C16): the probe leaves the station in the cluster, burns down to Frost,
## lands and takes a surface sample. Starts from the game saved after test_new_start_lab.gd's stage.

var bot: NewStartBot


func before_all() -> void:
	bot = NewStartBot.from_snapshot(NewStartBot.STAGE_LAB)
	var start := bot.total_ticks()
	bot.play_through(NewStartBot.STAGE_FROST_DOWN)
	gut.p("Frost down: ticks %d to %d" % [start, bot.total_ticks()])
	for line in bot.report(start, ["station_undocked", "left_cluster", "landed", "sampled"]):
		gut.p(line)


func test_the_stages_run_with_every_ledger_balanced() -> void:
	assert_eq(bot.problems, PackedStringArray())
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())
	assert_true(bot.marks.has("sampled"))
	assert_eq(bot.snapshot_mismatch(NewStartBot.STAGE_FROST_DOWN), "", "the next file starts from here")


func test_the_station_stays_in_the_cluster() -> void:
	var station: Dictionary = bot.marks["landed"]["units"][bot.station]
	assert_eq(station["dock"], {})
	assert_eq(station["frame"], bot.marks["station_undocked"]["units"][bot.station]["frame"], "the cluster")
	assert_ne(station["frame"], 0)


func test_the_probe_lands_on_frost_and_takes_a_surface_sample() -> void:
	var probe: Dictionary = bot.marks["sampled"]["units"][NewStartBot.PROBE]
	assert_eq(probe["landed"].get("body", 0), NewStartBot.FROST)
	var paid: Dictionary = bot.marks["sampled"]["science"]["paid"]
	assert_eq(paid.get("surface:%d:default" % NewStartBot.FROST, 0), 1)
