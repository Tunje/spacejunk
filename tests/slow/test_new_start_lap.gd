extends GutTest
## The new start, stage 5 (C16): the probe takes off from Frost to a low orbit and maps Frost's
## gravity field over one lap. Starts from the game saved after test_new_start_frost.gd's stage.

var bot: NewStartBot


func before_all() -> void:
	bot = NewStartBot.from_snapshot(NewStartBot.STAGE_FROST_DOWN)
	var start := bot.total_ticks()
	bot.play_through(NewStartBot.STAGE_FROST_LAP)
	gut.p("the lap: ticks %d to %d" % [start, bot.total_ticks()])
	for line in bot.report(start, ["low_orbit", "gravity_mapped"]):
		gut.p(line)


func test_the_lap_runs_with_every_ledger_balanced() -> void:
	assert_eq(bot.problems, PackedStringArray())
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())
	assert_true(bot.marks.has("gravity_mapped"))
	assert_eq(bot.snapshot_mismatch(NewStartBot.STAGE_FROST_LAP), "", "the next file starts from here")


func test_one_lap_maps_frosts_gravity_field() -> void:
	var probe: Dictionary = bot.marks["gravity_mapped"]["units"][NewStartBot.PROBE]
	assert_eq(probe["orbit"].get("parent", 0), NewStartBot.FROST)
	var science: Dictionary = bot.marks["gravity_mapped"]["science"]
	assert_eq(science["paid"].get("gravity_field:%d" % NewStartBot.FROST, 0), 1)
	assert_eq(science["points"], 4 * 10 + 3 * 20 + 50 + 40, "surveys, compositions, the sample and the lap")
