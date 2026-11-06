extends GutTest
## The new start played by a bot up to research (C14): nothing before research can dead-end.
## One shared run; each test asserts on a part of it. Prints the chain's timings for B.

var bot: NewStartBot


func before_all() -> void:
	bot = NewStartBot.shared()
	gut.p("new start chain: %d ticks (%.1f game hours)" % [bot.total_ticks(), bot.total_ticks() / 36000.0])
	for step: Dictionary in bot.steps:
		gut.p("  %s: %d ticks from %d" % [step["label"], step["ticks"], step["start_tick"]])
	gut.p("  tank free before ice: %d g" % bot.marks.get("tank_free_g_before_ice", -1))


func test_the_chain_runs_to_the_end_with_every_ledger_balanced() -> void:
	assert_eq(bot.problems, PackedStringArray(), "the bot finished every step")
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())
	assert_true(bot.marks.has("end"))


func test_the_probe_scans_and_mines_every_rock() -> void:
	var found := bot.events_of("deposit_found").map(func(event: Dictionary) -> String: return event["data"]["item"])
	found.sort()
	assert_eq(found, ["chalcopyrite", "hematite", "olivine", "water_ice"])


func test_ice_refines_into_propellant() -> void:
	var before: Dictionary = bot.marks["prospected"]["units"][NewStartBot.PROBE]["inventory"]
	var after: Dictionary = bot.marks["ice_refined"]["units"][NewStartBot.PROBE]["inventory"]
	assert_gte(bot.marks["tank_free_g_before_ice"], 180_000, "room in the tank for two runs")
	assert_eq(after["propellant"] - before["propellant"], 180_000, "two runs of 90 kg")


func test_a_small_station_is_built_docked_at_the_probe() -> void:
	var station: Dictionary = bot.marks["station_built"]["units"][bot.station]
	assert_eq(station["kind"], "station")
	assert_eq(station["dock"]["target_unit"], NewStartBot.PROBE)


func test_the_unpowered_station_refuses_a_powered_part_until_it_has_solar() -> void:
	assert_eq(bot.refused_fits.size(), 1)
	assert_true(bot.refused_fits[0]["reason"] in ["over_power_budget", "over_heat_budget"], bot.refused_fits[0]["reason"])
	var defs: Array = InspectText.flatten(bot.marks["fit_fixed"]["units"][bot.station]["parts"]) \
		.map(func(part: Dictionary) -> String: return part["def"])
	assert_has(defs, "lidar_mk1")
	assert_has(defs, "solar_panel_mk1")


func test_ore_is_hauled_into_the_station() -> void:
	var station: Dictionary = bot.marks["hauled"]["units"][bot.station]
	assert_gt(station["inventory"].get("hematite", 0), 0)
