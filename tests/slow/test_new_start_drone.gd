extends GutTest
## The new start, stage 6 (C22, new_start_chain.md Parts E and F): the probe builds and fits the
## first drone at the station's spare port, fills a propellant depot on the station, and hands Red
## Rock's hematite over to the drone's cycle for three laps of 500 kg; then a second ore store is
## built on the station from the ore it brought. Starts from the game saved after
## test_new_start_research.gd's stage.

var bot: NewStartBot


func before_all() -> void:
	bot = NewStartBot.from_snapshot(NewStartBot.STAGE_RESEARCH)
	var start := bot.total_ticks()
	bot.play_through(NewStartBot.STAGE_DRONE)
	gut.p("the drone: ticks %d to %d (%.1f game hours in all)" % [start, bot.total_ticks(),
		bot.total_ticks() / 36000.0])
	for line in bot.report(start, ["drone_ore", "drone_fitted", "drone_ready", "lap_1", "lap_2", "lap_3",
			"drone_stopped", "store_added"]):
		gut.p(line)
	for label: String in ["drone_ready", "lap_1", "lap_2", "lap_3"]:
		if bot.marks.has(label):
			var view: Dictionary = bot.marks[label]
			gut.p("  %s: drone propellant %d g, station hematite %d g, depot %d g" % [label,
				view["units"][bot.drone]["cargo"]["propellant"]["used_g"],
				view["units"][bot.station]["inventory"].get("hematite", 0),
				view["units"][bot.station]["inventory"].get("propellant", 0)])


func test_the_stage_runs_with_every_ledger_balanced() -> void:
	assert_eq(bot.problems, PackedStringArray())
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())
	assert_true(bot.marks.has("store_added"))
	assert_eq(bot.snapshot_mismatch(NewStartBot.STAGE_DRONE), "", "the snapshot regenerates the same")


func test_the_drone_is_built_at_the_stations_spare_port_and_fitted() -> void:
	var drone: Dictionary = bot.marks["drone_fitted"]["units"][bot.drone]
	assert_eq(bot.sim._state["units"][bot.drone]["dock"].get("target_unit", 0), bot.station,
		"docked at the station after its laps")
	var defs: Array = InspectText.flatten(drone["parts"]).map(func(part: Dictionary) -> String: return part["def"])
	for fit: Array in NewStartBot.DRONE_FIT:
		assert_has(defs, fit[0])
	assert_ne(int(drone["core"]), 0, "its Assisted Core assigned")


func test_three_laps_each_bring_500_kg() -> void:
	var laps: Array = bot.steps.filter(func(step: Dictionary) -> bool: return step["label"].begins_with("drone lap "))
	assert_eq(laps.size(), NewStartBot.DRONE_LAPS)
	var before: int = bot.marks["drone_ready"]["units"][bot.station]["inventory"].get("hematite", 0)
	for lap in NewStartBot.DRONE_LAPS:
		var after: int = bot.marks["lap_%d" % (lap + 1)]["units"][bot.station]["inventory"].get("hematite", 0)
		assert_eq(after - before, NewStartBot.DRONE_LAP_G, "lap %d" % (lap + 1))
		before = after


func test_a_second_ore_store_is_built_on_the_station() -> void:
	var station: Dictionary = bot.marks["store_added"]["units"][bot.station]
	var defs: Array = InspectText.flatten(station["parts"]).map(func(part: Dictionary) -> String: return part["def"])
	assert_eq(defs.count("ore_container_mk1"), 2)
	assert_has(defs, "propellant_tank_mk1", "the depot")
