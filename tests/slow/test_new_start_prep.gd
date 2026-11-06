extends GutTest
## The new start, stage 2 (C16): research prep. Two more trips with composition measured at each
## rock, everything refined, and the station given a core, a goods container and a second solar
## panel, built in place. Runs on from the chain's shared game, so it follows
## test_new_start_chain.gd.

var bot: NewStartBot


func before_all() -> void:
	var start := NewStartBot.shared().total_ticks()
	bot = NewStartBot.shared_through(NewStartBot.STAGE_PREP)
	gut.p("research prep: ticks %d to %d" % [start, bot.total_ticks()])
	for step: Dictionary in bot.steps:
		if step["start_tick"] >= start:
			gut.p("  %s: %d ticks from %d" % [step["label"], step["ticks"], step["start_tick"]])
	for label: String in ["prep_refined", "prep_done"]:
		if bot.marks.has(label):
			var view: Dictionary = bot.marks[label]
			var cargo: Dictionary = view["units"][NewStartBot.PROBE]["cargo"]
			gut.p("  %s: tick %d, propellant %d kg, ore %d kg, goods %d kg, points %d" % [label, view["tick"],
				cargo["propellant"]["used_g"] / 1000, cargo["ore"]["used_g"] / 1000, cargo["goods"]["used_g"] / 1000,
				view["science"]["points"]])


func test_the_prep_runs_with_every_ledger_balanced() -> void:
	assert_eq(bot.problems, PackedStringArray())
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())
	assert_true(bot.marks.has("prep_done"))


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
