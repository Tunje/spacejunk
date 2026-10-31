extends GutTest
## The golden test: the reference scenario's chain and the ten acceptance checks, from one shared
## run of ReferenceBot. Figures are the hand-worked ones in docs/design/reference_scenario.md.

const STATION := ReferenceBot.STATION
const SHIP := ReferenceBot.SHIP
const KG := 1000

var bot: ReferenceBot


func before_all() -> void:
	bot = ReferenceBot.shared()


func _units(mark: String) -> Dictionary:
	return bot.marks[mark]["units"]


func _station_stock(mark: String, item: String) -> int:
	return _units(mark)[STATION]["inventory"].get(item, 0)


func test_the_chain_runs_to_the_end_with_nothing_failing() -> void:
	assert_eq(bot.problems, PackedStringArray())
	assert_true(bot.marks.has("end"))


func test_matter_balances_on_every_tick() -> void:
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())


func test_no_load_is_shed_and_no_part_faults() -> void:
	assert_eq(bot.events_of("power_shed").size(), 0)
	assert_eq(bot.events_of("fault").size(), 0)


func test_order_durations_match_the_page() -> void:
	assert_eq(bot.ticks_of("move_to"), [984, 984, 984, 984, 988, 986, 634, 629])
	assert_eq(bot.ticks_of("undock"), [100, 100, 100, 100])
	assert_eq(bot.ticks_of("scan"), [300, 300, 300])
	assert_eq(bot.ticks_of("start_mining"), [1000, 1000, 1000, 1000])
	assert_eq(bot.ticks_of("dock"), [200, 200, 200, 200])
	assert_eq(bot.ticks_of("unload_cargo"), [400, 400, 400, 400])


func test_job_durations_match_the_page() -> void:
	var expected := {
		"refine_hematite": 15600, "refine_chalcopyrite": 6000, "refine_olivine": 5400,
		"structural_frame": 10500, "wiring": 4200, "processor": 14400, "heat_radiator_mk1": 900,
		"mining_laser_mk1": 1800, "ore_storage_mk1": 3000, "mining_drone": 3000, "basic_core": 1200,
		"assisted_core": 3000,
	}
	for recipe: String in expected:
		assert_eq(bot.ticks_of(recipe), [expected[recipe]], recipe)


func test_check_1_a_scan_identifies_each_deposit() -> void:
	var found := bot.events_of("deposit_found").map(func(event: Dictionary) -> Dictionary:
		return event["data"])
	assert_eq(found, [
		{ "deposit": 3, "item": "hematite", "grams": 200000000 },
		{ "deposit": 5, "item": "chalcopyrite", "grams": 100000000 },
		{ "deposit": 7, "item": "olivine", "grams": 50000000 },
	])
	assert_eq(_units("scanned")[SHIP]["pos_mm"], [49350000, 0, 0])
	assert_eq(_units("scanned")[SHIP]["at_target"], ReferenceBot.RED_ROCK)


func test_check_2_the_laser_fills_the_hold() -> void:
	assert_eq(bot.first_event("mining_stopped")["data"], {
		"deposit": ReferenceBot.HEMATITE, "grams": 2000 * KG, "reason": "cargo_full",
	})


func test_check_3_ore_is_hauled_into_storage() -> void:
	assert_eq(_station_stock("first_haul", "hematite"), 2000 * KG)
	assert_eq(_units("first_haul")[SHIP]["inventory"].get("hematite", 0), 0)
	assert_eq(_units("first_haul")[SHIP]["inventory"]["propellant"], 871045)
	assert_eq(_station_stock("part_a", "hematite"), 4000 * KG)
	assert_eq(_station_stock("part_a", "chalcopyrite"), 2000 * KG)
	assert_eq(_station_stock("part_a", "olivine"), 2000 * KG)
	assert_eq(_units("part_a")[SHIP]["inventory"]["propellant"], 542252)


func test_check_4_ore_is_refined_into_metal() -> void:
	assert_eq(_station_stock("refined", "iron"), 1794 * KG)
	assert_eq(_station_stock("refined", "slag"), 0)


func test_check_5_a_component_is_fabricated() -> void:
	assert_eq(_station_stock("fabricated", "structural_frame"), 35 * 50 * KG)


func test_check_10_a_fitting_fails_on_heat() -> void:
	var failed := bot.first_event("attach_failed")
	assert_eq(failed["unit"], SHIP)
	assert_eq(failed["data"]["reason"], "over_heat_budget")
	assert_eq(failed["data"]["detail"]["need_w"], 280000)
	assert_eq(failed["data"]["detail"]["have_w"], 200000)
	assert_eq(_station_stock("fit_failed", "mining_laser_mk1"), 400 * KG, "the part stays in stock")


func test_checks_6_and_10_a_radiator_fixes_the_fit_and_the_part_installs() -> void:
	var ship: Dictionary = _units("fit_fixed")[SHIP]
	assert_eq(ship["heat"]["reject_w"], 400000)
	assert_eq(ship["fit"]["heat_rated_w"], 280000)
	assert_eq(ship["fit"]["power_rated_w"], 322000)
	assert_eq(ship["fit"]["power_budget_w"], 420000)
	assert_eq(ship["mass_g"] - ship["inventory"]["propellant"], 5180 * KG)
	assert_eq(_station_stock("fit_fixed", "mining_laser_mk1"), 0)


func test_check_9_the_output_expands_the_station() -> void:
	assert_eq(_units("expanded")[STATION]["cargo"]["ore"]["cap_g"], 100000 * KG)


func test_check_7_a_drone_is_built() -> void:
	var drone: Dictionary = _units("drone_built")[bot.drone]
	assert_eq(drone["kind"], "drone")
	assert_eq(drone["core"], 0)
	assert_eq(drone["inventory"], {})
	assert_eq(drone["dock"]["target_port"], ReferenceBot.FREE_PORT)
	assert_eq(drone["at_target"], STATION)


func test_check_8_a_core_runs_the_cycle_unaided() -> void:
	assert_eq(_units("core_assigned")[bot.drone]["core_tier"], 2)
	assert_eq(bot.commands.back()["command"]["type"], "set_cycle", "nothing is ordered after it")
	assert_eq(bot.lap_ticks.size(), ReferenceBot.LAPS)
	assert_eq(bot.lap_ticks[0] - bot.cycle_start_tick, 5356)
	assert_eq(bot.lap_ticks[1] - bot.lap_ticks[0], 5340)
	assert_eq(bot.lap_ticks[2] - bot.lap_ticks[1], 5340)


func test_the_end_state_matches_the_page() -> void:
	var end: Dictionary = bot.marks["end"]
	var deposits: Dictionary = end["deposits"]
	assert_eq(deposits[ReferenceBot.HEMATITE]["remaining_g"], 194500 * KG)
	assert_eq(deposits[ReferenceBot.CHALCOPYRITE]["remaining_g"], 98000 * KG)
	assert_eq(deposits[ReferenceBot.OLIVINE]["remaining_g"], 48000 * KG)
	assert_eq(end["units"][STATION]["inventory"], {
		"hematite": 2900 * KG, "chalcopyrite": 1000 * KG, "olivine": 1400 * KG,
		"iron": 44 * KG, "copper": 6 * KG, "silicon": 18 * KG, "propellant": 3858524,
	})
	assert_eq(end["units"][SHIP]["inventory"], { "propellant": 542252 })
	assert_eq(end["units"][bot.drone]["inventory"], { "propellant": 86762 })


func test_installed_parts_and_sinks_match_the_page() -> void:
	var end: Dictionary = bot.marks["end"]
	for id: int in [STATION, SHIP, bot.drone]:
		var expected: int = { STATION: 15930 * KG, SHIP: 5180 * KG, bot.drone: 580 * KG }[id]
		var carried := 0
		for item: String in end["units"][id]["inventory"]:
			carried += end["units"][id]["inventory"][item]
		assert_eq(end["units"][id]["mass_g"] - carried, expected, "unit %d" % id)
	var matter: Dictionary = bot.sim.ledger()["matter"]
	assert_eq(matter["sinks"], { "slag_vent": 1952 * KG, "propellant_exhaust": 512462 })
	assert_eq(matter["start_g"], 374510 * KG)
	assert_eq(matter["total_g"], 374510 * KG)


func test_the_drone_has_begun_its_fourth_lap_on_the_stop_tick() -> void:
	var end: Dictionary = bot.marks["end"]
	var drone: Dictionary = end["units"][bot.drone]
	assert_eq(drone["op"]["type"], "loading")
	var task: Dictionary = end["tasks"][drone["task"]]
	assert_eq(task["step"], 0)
	assert_eq(task["cycle"], 3)
