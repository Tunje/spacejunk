extends GutTest
## D11: "Fit like this one" (C9 copy_fit) on the stub's many-ship scenario,
## through the real Fit screen.

const LASER := "stub_laser"

var main: Node
var bridge: SimBridge
var view: LocalView
var screen: FittingScreen
var sim: StubSim
var ships: Array[int] = []
var station := 0


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = StubSim.SCENARIO_LOAD
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.set_speed(1)
	sim = bridge.sim
	# The stub ship runs over its heat budget by design, which refuses every
	# attach. A cooler laser here puts it inside, so a copy can fit something.
	sim._defs["modules"][LASER]["heat_w"] = 50000
	view = main.get_node("LocalView")
	screen = main.fitting_screen
	ships.clear()
	var state := bridge.current_view
	var ids: Array = state["units"].keys()
	ids.sort()
	for id: int in ids:
		if state["units"][id]["kind"] == "ship":
			ships.append(id)
		else:
			station = id


func _ticks(count: int) -> void:
	bridge.set_paused(false)
	for i in range(count):
		bridge.advance(1.0 / bridge.ticks_per_second())
	bridge.set_paused(true)
	view.refresh(0.016)


func _part_with(unit_id: int, def: String) -> int:
	for part: Dictionary in InspectText.flatten(bridge.current_view["units"][unit_id]["parts"]):
		if part["def"] == def:
			return part["id"]
	return 0


## Takes the laser off a ship into its own hold, as a craft missing one part.
func _strip_laser(ship: int) -> void:
	bridge.submit(FittingLogic.detach_command(ship, _part_with(ship, LASER), ship))
	_ticks(1)
	assert_eq(_part_with(ship, LASER), 0)


func _open_on(ship: int) -> void:
	view.select("unit", ship, 0)
	main.toggle_fitting()


func _row_for(source: int) -> Dictionary:
	for row: Dictionary in screen._copy_rows:
		if row["source"] == source:
			return row
	return {}


func test_sources_are_other_craft_on_the_same_hull() -> void:
	var sources := FittingLogic.copy_sources(bridge.current_view, ships[0])
	assert_eq(sources.size(), ships.size() - 1)
	assert_false(sources.has(ships[0]), "not the craft itself")
	assert_false(sources.has(station), "not a different hull")


func test_the_screen_lists_each_source_with_a_preview() -> void:
	_strip_laser(ships[0])
	_open_on(ships[0])
	assert_true(screen._copy_heading.visible)
	assert_eq(screen._copy_rows.size(), ships.size() - 1)
	var button: Button = _row_for(ships[1])["button"]
	assert_eq(button.text, "Fit like Probe 2: Will fit 1")
	assert_false(button.disabled)


func test_a_craft_already_fitted_alike_has_nothing_to_copy() -> void:
	_open_on(ships[0])
	var button: Button = _row_for(ships[1])["button"]
	assert_eq(button.text, "Fit like Probe 2: Will fit 0")
	assert_true(button.disabled)


func test_copying_fits_the_missing_part_and_logs_it() -> void:
	_strip_laser(ships[0])
	_open_on(ships[0])
	_row_for(ships[1])["button"].pressed.emit()
	_ticks(1)
	assert_ne(_part_with(ships[0], LASER), 0)
	assert_false(bridge.current_view["units"][ships[0]]["inventory"].has(LASER), "the part came out of stock")
	assert_eq(main.event_log.lines[-1], "First Probe: fitted 1 part")


func test_a_part_not_in_stock_is_reported_missing() -> void:
	_strip_laser(ships[0])
	sim._state["units"][ships[0]]["inventory"].erase(LASER)
	_open_on(ships[0])
	var button: Button = _row_for(ships[1])["button"]
	assert_eq(button.text, "Fit like Probe 2: Will fit 0, missing 1")
	assert_eq(bridge.check(FittingLogic.copy_command(ships[0], ships[1], ships[0]))["detail"],
		{ "attach": 0, "missing": 1, "refused": 1 }, "a missing part is also refused, as in C9")
	assert_true(button.disabled)
	bridge.submit(FittingLogic.copy_command(ships[0], ships[1], ships[0]))
	_ticks(1)
	assert_eq(main.event_log.lines[-1], "First Probe: fitted 0 parts. Missing Mining Laser x1")


func test_a_part_in_the_way_is_refused() -> void:
	var laser := _part_with(ships[0], LASER)
	var slot: String = sim._find_part(sim._state["units"][ships[0]], laser)["parent_connector"]
	_strip_laser(ships[0])
	sim._state["units"][ships[0]]["inventory"]["stub_radiator"] = 260000
	var hull: int = bridge.current_view["units"][ships[0]]["parts"]["id"]
	bridge.submit(FittingLogic.attach_command(ships[0], { "item": "stub_radiator", "from": ships[0] },
		{ "part": hull, "connector": slot }))
	_ticks(1)
	var result: Dictionary = bridge.check(FittingLogic.copy_command(ships[0], ships[1], ships[0]))
	assert_true(result["ok"])
	assert_eq(result["detail"], { "attach": 0, "missing": 0, "refused": 1 })
	bridge.submit(FittingLogic.copy_command(ships[0], ships[1], ships[0]))
	_ticks(1)
	assert_eq(main.event_log.lines[-1], "First Probe: fitted 0 parts. Mining Laser: That connector is already in use")


func test_a_different_hull_is_a_fit_mismatch() -> void:
	var result: Dictionary = bridge.check(FittingLogic.copy_command(ships[0], station, ships[0]))
	assert_eq(result["reason"], "fit_mismatch")
	assert_eq(OrderText.reason("fit_mismatch"), "Only a craft on the same hull can be copied")


func test_copying_from_itself_is_refused() -> void:
	assert_eq(bridge.check(FittingLogic.copy_command(ships[0], ships[0], ships[0]))["reason"], "invalid_target")


func test_a_check_changes_nothing() -> void:
	_strip_laser(ships[0])
	var before := sim.state_hash()
	assert_true(bridge.check(FittingLogic.copy_command(ships[0], ships[1], ships[0]))["ok"])
	assert_eq(sim.state_hash(), before)


func test_stock_comes_from_the_docked_host_first() -> void:
	var units: Array[int] = FittingLogic.copy_stock_units(bridge.current_view, ships[0])
	assert_eq(units, [ships[0]] as Array[int], "undocked: its own hold")
	sim._state["units"][ships[0]]["dock"] = { "port": 1, "target_unit": station, "target_port": 2 }
	bridge.start(sim)
	units = FittingLogic.copy_stock_units(bridge.current_view, ships[0])
	assert_eq(units, [station, ships[0]] as Array[int])


func test_the_summary_text() -> void:
	assert_eq(FittingLogic.copy_summary({ "attach": 5, "missing": 1, "refused": 1 }), "Will fit 5, missing 1")
	assert_eq(FittingLogic.copy_summary({ "attach": 2, "missing": 0, "refused": 1 }), "Will fit 2, 1 won't fit")
	assert_eq(FittingLogic.copy_summary({ "attach": 0, "missing": 1, "refused": 3 }), "Will fit 0, missing 1, 2 won't fit")


func test_parts_on_an_unfitted_part_are_refused_as_parent_not_fitted() -> void:
	var tank := _part_with(ships[0], "stub_tank")
	var source_tank := _part_with(ships[1], "stub_tank")
	assert_ne(tank, 0)
	sim._find_part(sim._state["units"][ships[0]], sim._state["units"][ships[0]]["parts"]["id"])["children"] = 		sim._state["units"][ships[0]]["parts"]["children"].filter(func(p: Dictionary) -> bool: return p["id"] != tank)
	bridge.start(sim)
	var result: Dictionary = bridge.check(FittingLogic.copy_command(ships[0], ships[1], ships[0]))
	assert_eq(result["detail"], { "attach": 0, "missing": 2, "refused": 2 }, "the tank and the thruster on it")
	bridge.submit(FittingLogic.copy_command(ships[0], ships[1], ships[0]))
	_ticks(1)
	assert_string_contains(main.event_log.lines[-1], "The part it sits on was not fitted")
	assert_ne(source_tank, 0)
