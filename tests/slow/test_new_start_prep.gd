extends GutTest
## The new start, stage 2 (C16): research prep. Two more trips with composition measured at each
## rock, everything refined, and the station given a core, a goods container and a second solar
## panel, built in place. Starts from the game saved after test_new_start_chain.gd's stage.

var bot: NewStartBot


func before_all() -> void:
	bot = NewStartBot.from_snapshot(NewStartBot.STAGE_CHAIN)
	var start := bot.total_ticks()
	bot.play_through(NewStartBot.STAGE_PREP)
	gut.p("research prep: ticks %d to %d" % [start, bot.total_ticks()])
	for line in bot.report(start, ["prep_refined", "prep_done"]):
		gut.p(line)


func test_the_prep_runs_with_every_ledger_balanced() -> void:
	assert_eq(bot.problems, PackedStringArray())
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())
	assert_true(bot.marks.has("prep_done"))
	assert_eq(bot.snapshot_mismatch(NewStartBot.STAGE_PREP), "", "the next file starts from here")


func test_composition_is_measured_at_three_rocks() -> void:
	var view: Dictionary = bot.marks["prep_done"]
	assert_eq(view["science"]["evidence"].get("composition", 0), 3)
	assert_eq(view["science"]["evidence"].get("survey", 0), 4, "the chain's scans")
	assert_eq(view["science"]["points"], 4 * 10 + 3 * 20)


func test_the_refining_for_the_research_route_is_done() -> void:
	var held: Dictionary = bot.marks["prep_done"]["units"][NewStartBot.PROBE]["inventory"]
	for ore in ["hematite", "chalcopyrite", "olivine"]:
		assert_eq(held.get(ore, 0), 0, "%s all refined" % ore)
	assert_gte(held.get("silicon", 0), 40 * 4_000, "silicon for the 40 processors still to make")
