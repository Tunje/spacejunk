extends GutTest
## The start state of docs/design/reference_scenario.md section 1.

const STATION := 8
const SHIP := 23
const START_G := 374_510_000

var sim: Sim


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true


func _part_defs(unit: int) -> Array:
	var names: Array = []
	for id in Units.part_ids(sim._state, unit):
		names.append(sim._state["parts"][id]["def"])
	return names


func test_reference_loads() -> void:
	assert_not_null(sim)
	assert_eq(Sim.last_error(), "")


func test_unknown_scenarios_fail_with_a_reason() -> void:
	for bad: String in ["no_such_scenario", "../modules", ""]:
		assert_null(Sim.new_game(bad, 1), bad)
		assert_eq(Sim.last_error(), "unknown_scenario", bad)


func test_entity_ids_follow_the_document() -> void:
	var state := sim._state
	assert_eq(state["bodies"].keys(), [1, 2, 4, 6])
	assert_eq(state["deposits"].keys(), [3, 5, 7])
	assert_eq(state["units"].keys(), [STATION, SHIP])
	assert_eq(state["next_entity_id"], 37)
	assert_eq(state["deposits"][3]["body"], 2)
	assert_eq(state["bodies"][2]["deposits"], [3])


func test_station_parts_follow_the_document() -> void:
	assert_eq(Units.part_ids(sim._state, STATION),
		[9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22] as Array[int])
	assert_eq(_part_defs(STATION), [
		"command_hub", "basic_core", "docking_port_mk1", "docking_port_mk1", "ore_refinery_mk1",
		"fabricator_mk1", "ore_storage_mk1", "goods_storage_mk1", "solar_farm_mk1", "battery_bank_mk1",
		"heat_radiator_mk1", "heat_radiator_mk1", "propellant_tank_mk1", "propellant_tank_mk1",
	])


func test_ship_parts_follow_the_document() -> void:
	assert_eq(Units.part_ids(sim._state, SHIP),
		[24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36] as Array[int])
	assert_eq(_part_defs(SHIP), [
		"starter_hull", "basic_core", "propellant_tank_mk1", "chemical_thruster_mk1", "docking_port_mk1",
		"solar_panel_mk1", "solar_panel_mk1", "battery_bank_mk1", "battery_bank_mk1", "ore_container_mk1",
		"heat_radiator_mk1", "mining_laser_mk1", "lidar_mk1",
	])
	assert_eq(sim._state["parts"][27]["parent"], 26)
	assert_eq(sim._state["parts"][26]["children"], [27])


func test_ship_starts_docked_and_at_its_host() -> void:
	var ship: Dictionary = sim.view()["units"][SHIP]
	assert_eq(ship["dock"], { "port": 28, "target_unit": STATION, "target_port": 12 })
	assert_eq(ship["at_target"], STATION)
	assert_eq(ship["pos_mm"], [0, 0, 0])
	assert_true(Units.are_docked(sim._state, SHIP, STATION))
	assert_true(Units.port_in_use(sim._state, 12))
	assert_false(Units.port_in_use(sim._state, 11))


func test_starting_stock_and_cores() -> void:
	var view := sim.view()
	assert_eq(view["units"][STATION]["inventory"], { "propellant": 4_000_000 })
	assert_eq(view["units"][SHIP]["inventory"], { "propellant": 1_000_000 })
	assert_eq(view["units"][STATION]["core"], 10)
	assert_eq(view["units"][SHIP]["core"], 25)
	assert_eq(view["units"][SHIP]["core_tier"], 1)


func test_batteries_start_full_and_heat_at_zero() -> void:
	var ship: Dictionary = sim.view()["units"][SHIP]
	assert_eq(ship["power"]["stored_j"], 720_000_000)
	assert_eq(ship["power"]["capacity_j"], 720_000_000)
	assert_eq(ship["power"]["max_discharge_w"], 300_000)
	assert_eq(ship["heat"]["stored_j"], 0)
	assert_eq(ship["heat"]["limit_j"], 20_000_000)


func test_ship_figures_match_the_document() -> void:
	var ship: Dictionary = sim.view()["units"][SHIP]
	assert_eq(ship["mass_g"], 4_580_000 + 1_000_000)
	assert_eq(ship["fit"]["power_rated_w"], 172_000)
	assert_eq(ship["fit"]["power_budget_w"], 420_000)
	assert_eq(ship["fit"]["heat_rated_w"], 160_000)
	assert_eq(ship["fit"]["heat_budget_w"], 200_000)
	assert_eq(ship["fit"]["mass_limit_g"], 12_000_000)
	assert_eq(ship["cargo"]["ore"]["cap_g"], 2_000_000)
	assert_eq(ship["cargo"]["ore"]["cap_l"], 750)
	assert_eq(ship["cargo"]["propellant"]["used_g"], 1_000_000)
	assert_eq(ship["cargo"]["propellant"]["used_l"], 1000)


func test_station_capacity_covers_step_39() -> void:
	var goods: Dictionary = sim.view()["units"][STATION]["cargo"]["goods"]
	assert_eq(goods["cap_l"], 40_000)
	assert_eq(sim.view()["units"][STATION]["cargo"]["propellant"]["used_g"],
		sim.view()["units"][STATION]["cargo"]["propellant"]["cap_g"])


func test_all_deposits_start_unfound_and_hidden() -> void:
	assert_eq(sim.view()["deposits"], {})
	sim._state["deposits"][3]["found"] = true
	var deposit: Dictionary = sim.view()["deposits"][3]
	assert_eq(deposit, { "body": 2, "item": "hematite", "remaining_g": 200_000_000, "hardness": 6 })


func test_bodies_are_in_the_view() -> void:
	var rock: Dictionary = sim.view()["bodies"][2]
	assert_eq(rock["pos_mm"], [50_000_000, 0, 0])
	assert_eq(rock["radius_mm"], 500_000)
	assert_eq(rock["kind"], "asteroid")
	assert_false(rock["scanned"])


func test_view_part_tree_matches_the_template() -> void:
	var root: Dictionary = sim.view()["units"][SHIP]["parts"]
	assert_eq(root["id"], 24)
	assert_eq(root["state"], "on")
	assert_eq(root["children"].size(), 11)
	var tank: Dictionary = root["children"][1]
	assert_eq(tank["def"], "propellant_tank_mk1")
	assert_eq(tank["parent_connector"], "stack_bottom")
	assert_eq(tank["connector"], "mount")
	assert_eq(tank["children"][0]["def"], "chemical_thruster_mk1")


func test_start_matter_matches_the_document() -> void:
	var matter: Dictionary = sim.ledger()["matter"]
	assert_eq(matter["start_g"], START_G)
	assert_eq(matter["total_g"], matter["start_g"])
	assert_eq(matter["deposits_g"], 350_000_000)
	assert_eq(matter["inventories_g"], 5_000_000)
	assert_eq(matter["installed_g"], 19_510_000)
	assert_eq(matter["jobs_g"], 0)
	assert_eq(matter["sinks_g"], 0)
	assert_eq(matter["sinks"], {})


func test_ledger_gives_each_sink_separately() -> void:
	sim._state["sinks"]["slag_vent"] = { "slag": 5 }
	sim._state["sinks"]["propellant_exhaust"] = { "propellant": 7 }
	var matter: Dictionary = sim.ledger()["matter"]
	assert_eq(matter["sinks"], { "slag_vent": 5, "propellant_exhaust": 7 })
	assert_eq(matter["sinks_g"], 12)


func test_idle_ticks_keep_matter_and_ranges() -> void:
	for i in 20:
		sim.step()
		var ledger := sim.ledger()
		assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
		assert_eq(ledger["violations"], PackedStringArray())


func test_a_round_trip_is_byte_exact_on_real_entities() -> void:
	sim.step(5)
	var text := sim.to_save()
	var loaded := Sim.from_save(text)
	assert_not_null(loaded)
	assert_eq(loaded.to_save(), text)
	assert_eq(loaded.view(), sim.view())


func test_a_loaded_game_has_the_same_systems_in_the_same_order() -> void:
	var loaded := Sim.from_save(sim.to_save())
	var names := func(game: Sim) -> Array:
		return game._systems.map(func(system: SimSystem) -> String:
			return system.get_script().get_global_name())
	assert_eq(names.call(loaded), names.call(sim))
	assert_eq(loaded._handlers.keys(), sim._handlers.keys())


func test_a_loaded_game_runs_commands_like_the_original() -> void:
	var loaded := Sim.from_save(sim.to_save())
	var command := { "type": "detach_part", "unit": SHIP, "args": { "part": 36, "to": STATION } }
	loaded.submit(command)
	sim.submit(command)
	loaded.step()
	sim.step()
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_eq(loaded.take_events()[0]["type"], "part_detached")


func test_a_changed_definition_refuses_the_save() -> void:
	var state: Dictionary = sim._state.duplicate(true)
	state["data_hash"] = "changed"
	assert_null(Sim.from_save(Canon.encode(state)))
	assert_eq(Sim.last_error(), "data_mismatch")


func test_seed_comes_from_the_argument() -> void:
	var view := Sim.new_game("reference", 99).view()
	assert_eq(view["seed"], 99)
