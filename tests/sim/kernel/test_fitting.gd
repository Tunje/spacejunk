extends GutTest
## attach_part and detach_part, on the reference scenario's station and ship.

const STATION := 8
const SHIP := 23
const HULL := 24
const HUB := 9
const TANK := 26
const THRUSTER := 27
const PORT := 28
const PANEL := 29
const LASER := 35
const LIDAR := 36

var sim: Sim
var state: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state


## Puts whole items in a unit, and counts them as starting matter.
func _give(unit: int, item: String, count: int = 1) -> void:
	var grams: int = sim._ctx.defs["items"][item]["unit_mass_g"] * count
	Units.add_stock(state["units"][unit]["inventory"], item, grams)
	state["matter_start_g"] += grams


## Takes a unit's whole stack of an item, and counts it out of starting matter.
func _clear(unit: int, item: String) -> void:
	state["matter_start_g"] -= state["units"][unit]["inventory"][item]
	state["units"][unit]["inventory"].erase(item)


## A private copy of the definitions, safe to change in one test.
func _own_defs() -> Dictionary:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	return sim._ctx.defs


func _attach(unit: int, item: String, parent: int, connector: String, from: int = STATION) -> Dictionary:
	return {
		"type": "attach_part", "unit": unit,
		"args": { "item": item, "from": from, "parent_part": parent,
			"parent_connector": connector, "part_connector": "mount" },
	}


func _detach(unit: int, part: int, to: int = STATION) -> Dictionary:
	return { "type": "detach_part", "unit": unit, "args": { "part": part, "to": to } }


## Runs one command for a tick and returns its one event.
func _run(command: Dictionary) -> Dictionary:
	sim.submit(command)
	sim.step()
	var events := sim.take_events()
	assert_eq(events.size(), 1, str(command))
	_assert_balanced()
	return events[0] if events.size() > 0 else {}


func _assert_balanced() -> void:
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"], "matter balances")
	assert_eq(ledger["violations"], PackedStringArray())


func _assert_refused(command: Dictionary, reason: String, event_type: String = "command_rejected") -> void:
	var before := state["next_entity_id"] as int
	var checked := sim.check(command)
	assert_false(checked["ok"], reason)
	assert_eq(checked["reason"], reason)
	var event := _run(command)
	assert_eq(event["type"], event_type, reason)
	assert_eq(event["data"]["reason"], reason)
	assert_eq(state["next_entity_id"], before, "no ID issued")


func test_check_10_fails_on_heat_then_a_radiator_fixes_it() -> void:
	_give(STATION, "mining_laser_mk1")
	_give(STATION, "heat_radiator_mk1")
	var laser := _attach(SHIP, "mining_laser_mk1", HULL, "side_b_nz")
	var failed := _run(laser)
	assert_eq(failed["type"], "attach_failed")
	assert_eq(failed["data"]["reason"], "over_heat_budget")
	assert_eq(failed["data"]["item"], "mining_laser_mk1")
	assert_eq(failed["data"]["detail"]["need_w"], 280_000)
	assert_eq(failed["data"]["detail"]["have_w"], 200_000)
	assert_eq(failed["data"]["detail"]["power_rated_w"], 322_000)
	assert_eq(failed["data"]["detail"]["power_budget_w"], 420_000)
	var radiator := _run(_attach(SHIP, "heat_radiator_mk1", HULL, "side_c_nx"))
	assert_eq(radiator["type"], "part_attached")
	assert_eq(sim.view()["units"][SHIP]["fit"]["heat_budget_w"], 400_000)
	assert_eq(_run(laser)["type"], "part_attached")
	assert_eq(Units.installed_mass(state, sim._ctx.defs, SHIP), 5_180_000)


func test_check_reports_what_attach_will_do() -> void:
	_give(STATION, "heat_radiator_mk1")
	var command := _attach(SHIP, "heat_radiator_mk1", HULL, "side_c_nx")
	var before := sim.state_hash()
	var checked := sim.check(command)
	assert_true(checked["ok"])
	assert_eq(checked["detail"]["heat_budget_w"], 400_000)
	assert_eq(checked["detail"]["mass_g"], 5_580_000 + 200_000)
	assert_eq(sim.state_hash(), before)


func test_attach_moves_exactly_one_unit_and_issues_the_next_id() -> void:
	_give(STATION, "lidar_mk1", 2)
	var event := _run(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz"))
	var id: int = event["data"]["part"]
	assert_eq(id, 37)
	assert_eq(state["units"][STATION]["inventory"]["lidar_mk1"], 100_000)
	assert_eq(state["parts"][id]["unit"], SHIP)
	assert_eq(state["parts"][id]["parent"], HULL)
	assert_true(state["parts"][HULL]["children"].has(id))
	assert_eq(_run(_attach(SHIP, "lidar_mk1", HULL, "side_c_nz"))["type"], "part_attached")
	assert_false(state["units"][STATION]["inventory"].has("lidar_mk1"))


func test_attach_on_a_station_from_its_own_stock() -> void:
	_give(STATION, "ore_storage_mk1")
	var before: int = sim.view()["units"][STATION]["cargo"]["ore"]["cap_g"]
	assert_eq(_run(_attach(STATION, "ore_storage_mk1", HUB, "side_c_px", STATION))["type"], "part_attached")
	assert_eq(sim.view()["units"][STATION]["cargo"]["ore"]["cap_g"], before * 2)


func test_an_attached_part_appears_in_the_view_tree() -> void:
	_give(STATION, "lidar_mk1")
	var id: int = _run(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz"))["data"]["part"]
	var shown: Array = sim.view()["units"][SHIP]["parts"]["children"]
	assert_eq(shown[-1]["id"], id)
	assert_eq(shown[-1]["parent_connector"], "side_c_pz")


func test_connector_type_size_and_occupancy() -> void:
	_give(STATION, "lidar_mk1")
	_assert_refused(_attach(SHIP, "lidar_mk1", TANK, "stack_bottom"), "connector_type_mismatch", "attach_failed")
	_assert_refused(_attach(SHIP, "lidar_mk1", HULL, "core"), "connector_size_mismatch", "attach_failed")
	_assert_refused(_attach(SHIP, "lidar_mk1", HULL, "side_a_px"), "connector_occupied", "attach_failed")


func test_a_part_cannot_mate_to_a_dock_connector() -> void:
	_give(STATION, "docking_port_mk1")
	var command := _attach(SHIP, "docking_port_mk1", PORT, "dock")
	_assert_refused(command, "connector_type_mismatch", "attach_failed")


func test_over_mass_limit_counts_inventory() -> void:
	_give(STATION, "lidar_mk1")
	_own_defs()["modules"]["starter_hull"]["capabilities"]["max_mass_g"] = 5_600_000
	var event := sim.check(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz"))
	assert_eq(event["reason"], "over_mass_limit")
	assert_eq(event["detail"]["need_g"], 5_680_000)
	assert_eq(event["detail"]["have_g"], 5_600_000)


func test_moving_a_part_within_a_unit_does_not_add_mass() -> void:
	_give(SHIP, "lidar_mk1")
	_own_defs()["modules"]["starter_hull"]["capabilities"]["max_mass_g"] = 5_680_000
	assert_true(sim.check(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz", SHIP))["ok"])


func test_over_power_budget() -> void:
	_give(STATION, "lidar_mk1")
	var defs := _own_defs()
	defs["modules"]["battery_bank_mk1"]["capabilities"]["battery"]["max_discharge_w"] = 0
	defs["modules"]["lidar_mk1"]["power_w"] = 200_000
	defs["modules"]["lidar_mk1"]["heat_w"] = 0
	var checked := sim.check(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz"))
	assert_eq(checked["reason"], "over_power_budget")
	assert_eq(checked["detail"]["have_w"], 120_000)


func test_load_limit_on_the_joining_connector() -> void:
	_give(STATION, "lidar_mk1")
	var defs := _own_defs()
	for connector: Dictionary in defs["modules"]["starter_hull"]["connectors"]:
		connector["load_limit_g"] = 50_000
	var checked := sim.check(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz"))
	assert_eq(checked["reason"], "over_load_limit")
	assert_eq(checked["detail"]["need_g"], 100_000)


func test_load_limit_counts_every_connector_above() -> void:
	_clear(SHIP, "propellant")
	_give(STATION, "propellant_tank_mk1")
	_run(_detach(SHIP, THRUSTER))
	var defs := _own_defs()
	for connector: Dictionary in defs["modules"]["starter_hull"]["connectors"]:
		if connector["id"] == "stack_bottom":
			connector["load_limit_g"] = 300_000
	var checked := sim.check(_attach(SHIP, "propellant_tank_mk1", TANK, "stack_bottom"))
	assert_eq(checked["reason"], "over_load_limit")
	assert_eq(checked["detail"]["need_g"], 400_000)


func test_attach_refusals_that_are_not_fitting_failures() -> void:
	_give(STATION, "lidar_mk1")
	_assert_refused(_attach(SHIP, "lidar_mk1", 9999, "side_c_pz"), "unknown_part")
	_assert_refused(_attach(SHIP, "lidar_mk1", HUB, "side_c_pz"), "unknown_part")
	_assert_refused(_attach(SHIP, "hematite", HULL, "side_c_pz"), "invalid_target")
	_assert_refused(_attach(SHIP, "lidar_mk1", HULL, "no_such_connector"), "invalid_target")
	_assert_refused(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz", 9999), "unknown_unit")
	_assert_refused(_attach(SHIP, "radiator", HULL, "side_c_pz"), "invalid_target")
	_assert_refused({ "type": "attach_part", "unit": SHIP, "args": {} }, "malformed_command")


func test_attach_needs_a_whole_part_in_stock() -> void:
	var event := sim.check(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz"))
	assert_eq(event["reason"], "missing_inputs")
	assert_eq(event["detail"], { "need_g": 100_000, "have_g": 0 })


func test_attach_from_a_unit_not_docked_is_refused() -> void:
	_give(STATION, "lidar_mk1")
	state["units"][SHIP]["dock"] = {}
	_assert_refused(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz"), "not_docked")


func test_attach_to_a_faulted_parent_is_refused() -> void:
	_give(STATION, "lidar_mk1")
	state["parts"][HULL]["fault"] = "test_fault"
	_assert_refused(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz"), "module_fault")


func test_detach_of_a_subtree_goes_whole_to_the_inventory() -> void:
	_clear(SHIP, "propellant")
	var event := _run(_detach(SHIP, TANK))
	assert_eq(event["type"], "part_detached")
	assert_eq(event["data"]["part"], TANK)
	var inventory: Dictionary = state["units"][STATION]["inventory"]
	assert_eq(inventory["propellant_tank_mk1"], 200_000)
	assert_eq(inventory["chemical_thruster_mk1"], 300_000)
	assert_false(state["parts"].has(TANK))
	assert_false(state["parts"].has(THRUSTER))
	assert_false(state["parts"][HULL]["children"].has(TANK))
	assert_eq(Units.installed_mass(state, sim._ctx.defs, SHIP), 4_080_000)


func test_a_detached_subtree_can_be_refitted_under_new_ids() -> void:
	_clear(SHIP, "propellant")
	_run(_detach(SHIP, TANK))
	var tank: int = _run(_attach(SHIP, "propellant_tank_mk1", HULL, "stack_bottom"))["data"]["part"]
	var thruster: int = _run(_attach(SHIP, "chemical_thruster_mk1", tank, "stack_bottom"))["data"]["part"]
	assert_eq(tank, 37)
	assert_eq(thruster, 38)
	assert_eq(Units.installed_mass(state, sim._ctx.defs, SHIP), 4_580_000)


func test_detach_into_the_unit_itself() -> void:
	_own_defs()["modules"]["ore_container_mk1"]["capabilities"]["storage"]["goods"] = {
		"mass_g": 1_000_000, "volume_l": 1000,
	}
	assert_eq(_run(_detach(SHIP, LIDAR, SHIP))["type"], "part_detached")
	assert_eq(state["units"][SHIP]["inventory"]["lidar_mk1"], 100_000)


func test_detach_of_a_root_is_refused() -> void:
	_assert_refused(_detach(SHIP, HULL), "root_part")


func test_detach_of_a_port_in_use_is_refused_on_either_side() -> void:
	_assert_refused(_detach(SHIP, PORT), "port_busy")
	_assert_refused(_detach(STATION, 12), "port_busy")
	assert_eq(_run(_detach(STATION, 11))["type"], "part_detached")


func test_detach_of_a_part_in_use_is_refused() -> void:
	state["units"][SHIP]["op"]["part"] = LASER
	_assert_refused(_detach(SHIP, LASER), "part_busy")


func test_detach_of_a_subtree_with_a_part_in_use_is_refused() -> void:
	_clear(SHIP, "propellant")
	state["units"][SHIP]["op"]["part"] = THRUSTER
	_assert_refused(_detach(SHIP, TANK), "part_busy")


func test_detach_of_a_facility_with_a_job_is_refused() -> void:
	state["jobs"][40] = JobFixture.record(state, 13, "refine_hematite", "waiting", "missing_inputs")
	_assert_refused(_detach(STATION, 13), "part_busy")


func test_detach_is_refused_if_the_destination_has_no_room() -> void:
	state["units"][STATION]["reserved"]["goods"] = { "g": 0, "l": 40_000 }
	_assert_refused(_detach(SHIP, LIDAR), "cargo_full")


func test_detach_is_refused_if_it_would_leave_the_unit_over_capacity() -> void:
	_assert_refused(_detach(SHIP, TANK), "cargo_full")


func test_detach_counts_reserved_space_on_the_unit_left_behind() -> void:
	state["units"][SHIP]["reserved"]["ore"] = { "g": 1, "l": 0 }
	_assert_refused(_detach(SHIP, 33), "cargo_full")


func test_a_subtree_is_never_split() -> void:
	_clear(SHIP, "propellant")
	var defs := _own_defs()
	defs["modules"]["goods_storage_mk1"]["capabilities"]["storage"]["goods"]["volume_l"] = 2600
	_assert_refused(_detach(SHIP, TANK), "cargo_full")
	assert_true(state["parts"].has(TANK))
	assert_true(state["parts"].has(THRUSTER))
	assert_false(state["units"][STATION]["inventory"].has("propellant_tank_mk1"))


func test_detach_refusals_for_bad_arguments() -> void:
	_assert_refused(_detach(SHIP, 9999), "unknown_part")
	_assert_refused(_detach(SHIP, 13), "unknown_part")
	_assert_refused(_detach(SHIP, LIDAR, 9999), "unknown_unit")
	_assert_refused({ "type": "detach_part", "unit": SHIP, "args": { "part": "x", "to": 8 } }, "malformed_command")


func test_detach_to_a_unit_not_docked_is_refused() -> void:
	state["units"][SHIP]["dock"] = {}
	_assert_refused(_detach(SHIP, LIDAR), "not_docked")


func test_detaching_the_assigned_core_clears_it() -> void:
	assert_eq(_run(_detach(SHIP, 25))["type"], "part_detached")
	var ship: Dictionary = sim.view()["units"][SHIP]
	assert_eq(ship["core"], 0)
	assert_eq(ship["core_tier"], 0)


func test_detach_is_allowed_on_a_faulted_part() -> void:
	state["parts"][LIDAR]["fault"] = "test_fault"
	assert_eq(_run(_detach(SHIP, LIDAR))["type"], "part_detached")


func test_an_injected_imbalance_is_caught() -> void:
	_run(_detach(SHIP, LIDAR))
	state["units"][STATION]["inventory"]["lidar_mk1"] += 1
	var matter: Dictionary = sim.ledger()["matter"]
	assert_ne(matter["total_g"], matter["start_g"])


func test_a_broken_discrete_stack_is_a_violation() -> void:
	_give(STATION, "wiring", 2)
	state["units"][STATION]["inventory"]["wiring"] -= 1
	sim.step()
	assert_string_contains("\n".join(sim.ledger()["violations"]), "wiring")


func test_discrete_stacks_stay_whole_through_attach_and_detach() -> void:
	_give(STATION, "lidar_mk1", 2)
	_run(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz"))
	_run(_detach(SHIP, LIDAR))
	assert_eq(state["units"][STATION]["inventory"]["lidar_mk1"], 200_000)
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_save_and_load_after_a_refit_is_byte_exact() -> void:
	_give(STATION, "lidar_mk1")
	_run(_attach(SHIP, "lidar_mk1", HULL, "side_c_pz"))
	_run(_detach(SHIP, PANEL))
	var text := sim.to_save()
	var loaded := Sim.from_save(text)
	assert_eq(loaded.to_save(), text)
	assert_eq(loaded.view(), sim.view())
