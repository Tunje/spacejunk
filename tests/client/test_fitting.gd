extends GutTest

var main: Node
var bridge: SimBridge
var view: LocalView
var screen: FittingScreen
var ship: int
var station: int


func before_each() -> void:
	main = add_child_autofree(load("res://client/main.tscn").instantiate())
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	view = main.get_node("LocalView")
	screen = main.fitting_screen
	var state := bridge.current_view
	for id: int in state["units"]:
		if state["units"][id]["kind"] == "ship":
			ship = id
		else:
			station = id


func _run_ticks(ticks: int) -> void:
	bridge.set_paused(false)
	bridge.set_speed(8)
	for i in range(ceili(ticks / 8.0)):
		bridge.advance(0.1)
	bridge.set_paused(true)
	view.refresh(0.016)


func _dock() -> void:
	view.select("unit", station, 0)
	assert_true(main.order_panel.press("Dock"))
	_run_ticks(28)
	view.select("unit", ship, 0)


func _open_docked() -> void:
	_dock()
	main.toggle_fitting()


func _entry(item: String) -> Dictionary:
	for entry: Dictionary in screen._stock:
		if entry["item"] == item:
			return entry
	return {}


func _slot(connector: String) -> Dictionary:
	var slots := FittingLogic.free_slots(bridge.current_view["units"][ship], bridge.defs()["modules"])
	for slot: Dictionary in slots:
		if slot["connector"] == connector:
			return slot
	return {}


func _fit_item(item: String, connector: String) -> void:
	screen.choose(_entry(item))
	screen.choose_slot(_slot(connector))


func test_stock_needs_a_dock_to_reach_the_station() -> void:
	var modules: Dictionary = bridge.defs()["modules"]
	assert_true(FittingLogic.stock(bridge.current_view, ship, modules).is_empty())
	_dock()
	var stock := FittingLogic.stock(bridge.current_view, ship, modules)
	assert_eq(stock.size(), 3)
	assert_eq(stock[1]["item"], "stub_radiator")
	assert_eq(stock[1]["count"], 2)
	assert_eq(stock[1]["source"], "Foothold")


func test_ore_is_not_offered_as_a_part() -> void:
	_dock()
	for entry: Dictionary in FittingLogic.stock(bridge.current_view, ship, bridge.defs()["modules"]):
		assert_ne(entry["item"], "hematite")


func test_free_slots_skip_mounts_docks_and_used_connectors() -> void:
	var slots := FittingLogic.free_slots(bridge.current_view["units"][ship], bridge.defs()["modules"])
	var names: Array = slots.map(func(slot: Dictionary) -> String: return slot["connector"])
	assert_has(names, "ext_a")
	assert_does_not_have(names, "mount")
	assert_does_not_have(names, "dock")
	assert_does_not_have(names, "side_px")


func test_limit_lines_show_the_projection_only_when_there_is_one() -> void:
	assert_eq(FittingLogic.limit_line("Heat", "131 kW", "100 kW", ""), "Heat: 131 kW of 100 kW")
	assert_eq(FittingLogic.limit_line("Heat", "131 kW", "100 kW", "251 kW"), "Heat: 131 kW, then 251 kW, of 100 kW")


func test_reasons_show_their_numbers() -> void:
	assert_eq(OrderText.reason("over_heat_budget", { "need_w": 251000, "have_w": 100000 }),
		"Over the heat budget: needs 251 kW, has 100 kW")
	assert_eq(OrderText.reason("missing_inputs", { "need_g": 400000, "have_g": 0 }),
		"Missing inputs: needs 400.0 kg, has 0.0 kg")


func test_detach_goes_to_the_docked_host() -> void:
	assert_eq(FittingLogic.detach_target(bridge.current_view, ship), ship)
	_dock()
	assert_eq(FittingLogic.detach_target(bridge.current_view, ship), station)


func test_check_10_fails_on_a_limit_then_is_fixed_by_fitting_another_part() -> void:
	_open_docked()
	_fit_item("stub_laser", "ext_a")
	assert_true(screen._attach_button.disabled)
	assert_string_contains(screen._verdict.text, "Over the power budget")
	assert_eq(screen._power_bar.modulate, ClientTheme.ORANGE)
	_fit_item("stub_solar", "ext_a")
	assert_true(screen._attach_button.disabled, "the heat budget was already over")
	assert_string_contains(screen._verdict.text, "Over the heat budget")
	_fit_item("stub_radiator", "ext_a")
	assert_false(screen._attach_button.disabled)
	screen.attach()
	_run_ticks(8)
	screen.refresh()
	_fit_item("stub_radiator", "ext_b")
	assert_false(screen._attach_button.disabled)
	screen.attach()
	_run_ticks(8)
	screen.refresh()
	_fit_item("stub_solar", "ext_c")
	assert_false(screen._attach_button.disabled, "two radiators now cover the heat")


func test_attaching_moves_stock_and_shows_on_the_craft() -> void:
	_open_docked()
	var parts_before: int = view.crafts[ship].part_transforms.size()
	var hold_before: int = bridge.current_view["units"][station]["inventory"]["stub_radiator"]
	_fit_item("stub_radiator", "ext_a")
	screen.attach()
	_run_ticks(8)
	assert_eq(view.crafts[ship].part_transforms.size(), parts_before + 1)
	assert_true(view.crafts[ship].is_growing(), "the new part grows in")
	assert_eq(bridge.current_view["units"][station]["inventory"]["stub_radiator"], hold_before - 260000)
	assert_true(screen.chosen.is_empty())


func test_attach_conserves_matter() -> void:
	var matter: int = bridge.sim.ledger()["matter_g"]
	_open_docked()
	_fit_item("stub_radiator", "ext_a")
	screen.attach()
	_run_ticks(8)
	assert_eq(bridge.sim.ledger()["matter_g"], matter)


func test_a_failed_submit_emits_attach_failed_with_the_item() -> void:
	_open_docked()
	bridge.sim.take_events()
	var command := FittingLogic.attach_command(ship, { "item": "stub_laser", "from": station }, _slot("ext_a"))
	bridge.sim.submit(command)
	bridge.sim.step(1)
	var events: Array[Dictionary] = bridge.sim.take_events()
	assert_eq(events[0]["type"], "attach_failed")
	assert_eq(events[0]["data"]["item"], "stub_laser")
	assert_eq(events[0]["data"]["reason"], "over_power_budget")


func test_removing_a_part_returns_it_to_the_host() -> void:
	_open_docked()
	var state: Dictionary = bridge.current_view["units"][ship]
	var radiator := 0
	for part: Dictionary in InspectText.flatten(state["parts"]):
		if part["def"] == "stub_radiator":
			radiator = part["id"]
	view.select("unit", ship, radiator)
	assert_false(screen._remove_button.disabled)
	screen.remove_selected()
	_run_ticks(8)
	assert_eq(bridge.current_view["units"][station]["inventory"]["stub_radiator"], 780000)
	assert_false(view.crafts[ship].part_transforms.has(radiator))


func test_the_root_and_the_docked_port_cannot_be_removed() -> void:
	_open_docked()
	var state: Dictionary = bridge.current_view["units"][ship]
	view.select("unit", ship, state["parts"]["id"])
	assert_true(screen._remove_button.disabled)
	view.select("unit", ship, state["dock"]["port"])
	assert_true(screen._remove_button.disabled)


func test_nothing_selected_means_nothing_to_remove() -> void:
	_open_docked()
	assert_true(screen._remove_button.disabled)


func test_opening_swaps_the_panels_and_closing_restores_them() -> void:
	main.toggle_fitting()
	assert_true(screen.visible)
	assert_true(main.fitting_markers.visible)
	assert_false(main.order_panel.visible)
	main.toggle_fitting()
	assert_false(screen.visible)
	assert_false(main.fitting_markers.visible)
	assert_true(main.order_panel.visible)


func test_fitting_closes_the_map() -> void:
	main.toggle_map()
	main.toggle_fitting()
	assert_false(main.system_map.is_open())


func test_escape_closes_fitting() -> void:
	main.toggle_fitting()
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_ESCAPE
	main._unhandled_key_input(key)
	assert_false(screen.visible)


func test_markers_mark_every_free_slot_and_clicks_pick_one() -> void:
	_open_docked()
	main.fitting_markers.update_slots()
	var shown: Array[Dictionary] = main.fitting_markers._shown
	assert_gt(shown.size(), 0)
	assert_eq(main.fitting_markers.pick(shown[0]["at"]), shown[0]["slot"])
	assert_true(main.fitting_markers.pick(Vector2(-500, -500)).is_empty())


func test_markers_turn_orange_for_a_slot_that_would_fail() -> void:
	_open_docked()
	screen.choose(_entry("stub_laser"))
	main.fitting_markers.update_slots()
	assert_false(main.fitting_markers._shown[0]["ok"])


func test_part_labels_show_only_for_the_hovered_or_selected_part() -> void:
	var craft: CraftNode = view.crafts[ship]
	var parts: Array = craft.part_transforms.keys()
	for id: int in parts:
		assert_false(craft._labels[id].visible)
	craft.hover(parts[1])
	assert_true(craft._labels[parts[1]].visible)
	assert_false(craft._labels[parts[2]].visible)
	craft.hover(0)
	assert_false(craft._labels[parts[1]].visible)
	view.select("unit", ship, parts[2])
	assert_true(craft._labels[parts[2]].visible)


func test_hover_follows_the_mouse_through_the_ray() -> void:
	view.camera.distance_m = 40.0
	view.camera.target_distance_m = 40.0
	view.refresh(0.0)
	await wait_physics_frames(3)
	var at: Vector2 = view.camera.unproject_position(view.crafts[ship].position + Vector3(0, 2, 0))
	view.hover_at(at)
	assert_gt(view.crafts[ship]._hovered_part, 0)
	view.hover_at(Vector2(2, 2))
	assert_eq(view.crafts[ship]._hovered_part, 0)


func test_real_sim_check_gives_the_same_detail_keys_as_the_stub() -> void:
	_dock()
	var stub_result: Dictionary = bridge.check(FittingLogic.attach_command(
		ship, { "item": "stub_radiator", "from": station }, _slot("ext_a")))
	var real := Sim.new_game("reference", 1)
	var state := real.view()
	var unit_id := 0
	var from_id := 0
	for id: int in state["units"]:
		if state["units"][id]["kind"] == "ship":
			unit_id = id
		else:
			from_id = id
	var real_result := real.check(FittingLogic.detach_command(unit_id, state["units"][unit_id]["parts"]["children"][0]["id"], from_id))
	for key: String in stub_result["detail"]:
		assert_true(real_result["detail"].has(key), key)
