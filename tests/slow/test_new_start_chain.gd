extends GutTest
## The new start played by a bot up to research (C14): nothing before research can dead-end.
## One shared run; each test asserts on a part of it. Prints the chain's timings for B.

const MILESTONES: Array[String] = [
	"start", "scanned", "mined", "refined", "prospected", "ice_refined", "station_built", "fit_failed",
	"fit_fixed", "hauled", "end",
]

var bot: NewStartBot


func before_all() -> void:
	bot = NewStartBot.shared()
	gut.p("new start chain: %d ticks (%.1f game hours)" % [bot.total_ticks(), bot.total_ticks() / 36000.0])
	for step: Dictionary in bot.steps:
		gut.p("  %s: %d ticks from %d" % [step["label"], step["ticks"], step["start_tick"]])
	gut.p("  tank free before ice: %d g" % bot.marks.get("tank_free_g_before_ice", -1))
	gut.p("  probe holds at the end: %s" % str(bot.sim._state["units"][NewStartBot.PROBE]["inventory"]))
	for job: Dictionary in bot.sim._state["jobs"].values():
		gut.p("  open job: %s %s %s" % [job["recipe"], job["status"], job["reason"]])
	gut.p("  milestone: tick, propellant kg, ore kg, goods kg in the probe")
	for label: String in MILESTONES:
		if bot.marks.has(label):
			var view: Dictionary = bot.marks[label]
			var cargo: Dictionary = view["units"][NewStartBot.PROBE]["cargo"]
			gut.p("  %s: %d, %d, %d, %d" % [label, view["tick"], cargo["propellant"]["used_g"] / 1000,
				cargo["ore"]["used_g"] / 1000, cargo["goods"]["used_g"] / 1000])


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
	assert_gte(bot.marks["tank_free_g_before_ice"], 90_000, "room in the tank for a run")
	assert_eq(after["propellant"] - before["propellant"], 90_000, "one run of 90 kg")


func test_a_small_station_is_built_docked_at_the_probe() -> void:
	var station: Dictionary = bot.marks["station_built"]["units"][bot.station]
	assert_eq(station["kind"], "station")
	assert_eq(station["dock"]["target_unit"], NewStartBot.PROBE)


func test_the_bare_station_refuses_a_powered_part_until_it_has_solar_and_a_radiator() -> void:
	var reasons := bot.refused_fits.map(func(fit: Dictionary) -> String: return fit["reason"])
	assert_eq(reasons, ["over_power_budget", "over_heat_budget"])
	var defs: Array = InspectText.flatten(bot.marks["fit_fixed"]["units"][bot.station]["parts"]) \
		.map(func(part: Dictionary) -> String: return part["def"])
	assert_has(defs, "lidar_mk1")
	assert_has(defs, "solar_panel_mk1")
	assert_has(defs, "heat_radiator_mk1")


func test_ore_is_hauled_into_the_station() -> void:
	var station: Dictionary = bot.marks["hauled"]["units"][bot.station]
	assert_gt(station["inventory"].get("hematite", 0), 0)
