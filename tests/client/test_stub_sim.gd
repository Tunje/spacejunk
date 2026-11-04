extends GutTest

const SCAN_TICKS := 30
const DOCK_TICKS := 20

var sim: StubSim
var ship: int
var station: int
var rock: int


func before_each() -> void:
	sim = StubSim.new_game("stub", 7)
	var view := sim.view()
	for id: int in view["units"]:
		if view["units"][id]["kind"] == "ship":
			ship = id
		else:
			station = id
	for id: int in view["bodies"]:
		if view["bodies"][id]["kind"] == "asteroid":
			rock = id
			break


func _order(type: String, args: Dictionary = {}) -> int:
	return sim.submit({ "type": type, "unit": ship, "args": args })


func _event_types() -> Array:
	return sim.take_events().map(func(event: Dictionary) -> String: return event["type"])


func _part_with_def(part: Dictionary, def_id: String) -> int:
	if part["def"] == def_id:
		return part["id"]
	for child: Dictionary in part["children"]:
		var found := _part_with_def(child, def_id)
		if found != 0:
			return found
	return 0


func _fly_to(target: int) -> void:
	_order("move_to", { "target": target })
	sim.step(sim.check({ "type": "move_to", "unit": ship, "args": { "target": target } })["detail"]["ticks"] + 1)


func test_unknown_scenario_fails_with_a_reason() -> void:
	assert_null(StubSim.new_game("nope", 1))
	assert_eq(StubSim.last_error(), "unknown_scenario")


func test_bad_saves_fail_with_a_reason() -> void:
	assert_null(StubSim.from_save("garbage"))
	assert_eq(StubSim.last_error(), "corrupt")
	assert_null(StubSim.from_save("stub-save:999\n{}"))
	assert_eq(StubSim.last_error(), "version_mismatch")


func test_defs_are_in_sim_units_with_connectors_collision_and_visual() -> void:
	var hull: Dictionary = sim.defs()["modules"]["stub_hull"]
	assert_eq(hull["mass_g"], 2000000)
	assert_true(hull["power_w"] is int)
	assert_false(hull.has("mass_kg"))
	var top := _connector(hull, "top")
	assert_eq(top["load_limit_g"], 2000000)
	assert_eq(top["pos_mm"], [0, 4000, 0])
	var thrust: Dictionary = sim.defs()["modules"]["stub_thruster"]["capabilities"]["thruster"]
	assert_eq(thrust["speed_mm_s"], 500000)
	var port: Dictionary = sim.defs()["modules"]["stub_port"]["capabilities"]["port"]
	assert_eq(port["dock_ticks"], 2 * StubSim.TICKS_PER_SECOND)
	assert_eq(hull["collision"]["shape"], "cylinder")
	assert_true(hull["visual"].has("model"))


func test_same_seed_and_commands_give_same_hash() -> void:
	var other := StubSim.new_game("stub", 7)
	for each: StubSim in [sim, other]:
		each.submit({ "type": "move_to", "unit": ship, "args": { "target": rock } })
		each.step(40)
	assert_eq(sim.state_hash(), other.state_hash())


func test_move_reaches_route_end_and_reports_arrival() -> void:
	_order("move_to", { "target": rock })
	sim.step(1)
	var moving: Dictionary = sim.view()["units"][ship]
	assert_eq(moving["op"]["type"], "moving")
	assert_eq(moving["route"]["target"], rock)
	sim.step(moving["route"]["eta_tick"] - sim.current_tick())
	var arrived: Dictionary = sim.view()["units"][ship]
	assert_eq(arrived["op"]["type"], "idle")
	assert_true(arrived["route"].is_empty())
	assert_eq(arrived["pos_mm"], moving["route"]["to_mm"])
	assert_eq(arrived["at_target"], rock)
	var types := _event_types()
	assert_has(types, "task_started")
	assert_has(types, "task_finished")
	assert_has(types, "arrived")


func test_star_is_not_a_move_target() -> void:
	var view := sim.view()
	for id: int in view["bodies"]:
		if view["bodies"][id]["kind"] == "star":
			var result := sim.check({ "type": "move_to", "unit": ship, "args": { "target": id } })
			assert_eq(result["reason"], "invalid_target")


func test_scan_reveals_deposits_only_after_finishing() -> void:
	assert_true(sim.view()["deposits"].is_empty())
	_fly_to(rock)
	_order("scan", { "target": rock })
	sim.step(SCAN_TICKS)
	assert_true(sim.view()["deposits"].is_empty())
	sim.step(1)
	var view := sim.view()
	assert_false(view["deposits"].is_empty())
	assert_true(view["bodies"][rock]["scanned"])
	var types := _event_types()
	assert_has(types, "deposit_found")
	assert_has(types, "scan_finished")


func test_mining_moves_ore_and_conserves_matter() -> void:
	var matter: int = sim.ledger()["matter_g"]
	_fly_to(rock)
	_order("scan", { "target": rock })
	sim.step(SCAN_TICKS + 1)
	var view := sim.view()
	var deposit: int = view["deposits"].keys()[0]
	var laser := _part_with_def(view["units"][ship]["parts"], "stub_laser")
	_order("start_mining", { "deposit": deposit, "module": laser })
	sim.step(20)
	view = sim.view()
	assert_eq(view["units"][ship]["op"]["type"], "mining")
	assert_eq(view["units"][ship]["cargo"]["ore"]["used_g"], 40000, "20 kg/s for 2 s")
	assert_eq(sim.ledger()["matter_g"], matter)


func test_scan_away_from_the_body_is_rejected_with_numbers() -> void:
	var result := sim.check({ "type": "scan", "unit": ship, "args": { "target": rock } })
	assert_eq(result["reason"], "out_of_range")


func test_station_has_no_thruster() -> void:
	var result := sim.check({ "type": "move_to", "unit": station, "args": { "target": rock } })
	assert_eq(result["reason"], "module_missing")


func test_mining_away_from_the_body_is_rejected() -> void:
	_fly_to(rock)
	_order("scan", { "target": rock })
	sim.step(SCAN_TICKS + 1)
	_fly_to(station)
	var view := sim.view()
	var laser := _part_with_def(view["units"][ship]["parts"], "stub_laser")
	var args := { "deposit": view["deposits"].keys()[0], "module": laser }
	var result := sim.check({ "type": "start_mining", "unit": ship, "args": args })
	assert_eq(result["reason"], "out_of_range")


func test_route_stops_at_the_stand_off_from_a_surface() -> void:
	_fly_to(rock)
	var view := sim.view()
	var gap := IntMath.dist(view["units"][ship]["pos_mm"], view["bodies"][rock]["pos_mm"])
	assert_almost_eq(gap, view["bodies"][rock]["radius_mm"] + StubSim.STANDOFF_MM, 2)


func test_route_stops_at_the_stand_off_from_a_unit() -> void:
	_fly_to(rock)
	_fly_to(station)
	var view := sim.view()
	var gap := IntMath.dist(view["units"][ship]["pos_mm"], view["units"][station]["pos_mm"])
	assert_almost_eq(gap, StubSim.STANDOFF_MM, 2)


func test_starting_a_route_clears_at_target() -> void:
	assert_eq(sim.view()["units"][ship]["at_target"], station)
	_order("move_to", { "target": rock })
	sim.step(1)
	assert_eq(sim.view()["units"][ship]["at_target"], 0)


func test_a_halted_unit_is_at_nothing() -> void:
	_order("move_to", { "target": rock })
	sim.step(3)
	_order("stop")
	sim.step(1)
	assert_eq(sim.view()["units"][ship]["at_target"], 0)


func test_dock_and_undock_cycle() -> void:
	var view := sim.view()
	var port := _part_with_def(view["units"][ship]["parts"], "stub_port")
	var target_port := _part_with_def(view["units"][station]["parts"], "stub_station_port")
	_order("dock", { "port": port, "target_port": target_port })
	sim.step(DOCK_TICKS + 1)
	var docked: Dictionary = sim.view()["units"][ship]["dock"]
	assert_eq(docked, { "port": port, "target_unit": station, "target_port": target_port })
	assert_eq(sim.view()["units"][ship]["pos_mm"], sim.view()["units"][station]["pos_mm"], "takes the host position")
	assert_eq(sim.view()["units"][ship]["at_target"], station)
	assert_eq(sim.check({ "type": "move_to", "unit": ship, "args": { "target": rock } })["reason"], "docked")
	_order("undock")
	sim.step(DOCK_TICKS + 1)
	assert_true(sim.view()["units"][ship]["dock"].is_empty())
	assert_eq(sim.view()["units"][ship]["pos_mm"], [StubSim.STANDOFF_MM, 0, 0], "leaves along +X")
	assert_eq(sim.view()["units"][ship]["at_target"], station)
	var types := _event_types()
	assert_has(types, "docked")
	assert_has(types, "undocked")


func test_stop_cancels_the_order_with_a_reason() -> void:
	_order("move_to", { "target": rock })
	sim.step(1)
	_order("stop")
	sim.step(1)
	assert_eq(sim.view()["units"][ship]["op"]["type"], "idle")
	var cancelled: Array = sim.take_events().filter(func(event: Dictionary) -> bool: return event["type"] == "task_cancelled")
	assert_eq(cancelled[0]["data"]["reason"], "player_stop")


func test_new_order_replaces_the_running_one() -> void:
	_order("move_to", { "target": rock })
	sim.step(2)
	_order("move_to", { "target": station })
	sim.step(1)
	assert_eq(sim.view()["units"][ship]["route"]["target"], station)
	assert_eq(sim.view()["tasks"].size(), 1)


func test_float_in_command_is_rejected() -> void:
	_order("move_to", { "target": 1.0 })
	sim.step(1)
	var events := sim.take_events()
	assert_eq(events[0]["type"], "command_rejected")
	assert_eq(events[0]["data"]["reason"], "float_in_command")


func test_unmodelled_commands_are_rejected_clearly() -> void:
	assert_eq(sim.check({ "type": "assign_core", "unit": station, "args": {} })["reason"], "not_in_stub")


func test_set_priority_shows_in_view() -> void:
	var laser := _part_with_def(sim.view()["units"][ship]["parts"], "stub_laser")
	_order("set_priority", { "module": laser, "priority": 1 })
	sim.step(1)
	var hull: Dictionary = sim.view()["units"][ship]["parts"]
	for child: Dictionary in hull["children"]:
		if child["id"] == laser:
			assert_eq(child["priority"], 1)


func test_fixture_connectors_mate_by_contract_rule() -> void:
	var modules: Dictionary = sim.defs()["modules"]
	var view := sim.view()
	for id: int in view["units"]:
		var pending: Array = [view["units"][id]["parts"]]
		while not pending.is_empty():
			var parent: Dictionary = pending.pop_back()
			for child: Dictionary in parent["children"]:
				var a := _connector(modules[parent["def"]], child["parent_connector"])
				var b := _connector(modules[child["def"]], child["connector"])
				assert_false(a.is_empty() or b.is_empty(), "%s has its connectors" % child["def"])
				assert_eq(b["id"], "mount", "%s mates by its mount" % child["def"])
				var child_frame := CraftLayout.mate(a, b) * CraftLayout.connector_transform(b)
				var parent_frame := CraftLayout.connector_transform(a)
				assert_almost_eq(child_frame.basis.z.distance_to(-parent_frame.basis.z), 0.0, 0.0001, child["def"])
				assert_almost_eq(child_frame.basis.y.distance_to(parent_frame.basis.y), 0.0, 0.0001, child["def"])
				pending.append(child)


func _connector(module: Dictionary, connector_id: String) -> Dictionary:
	for connector: Dictionary in module["connectors"]:
		if connector["id"] == connector_id:
			return connector
	return {}
