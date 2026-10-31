extends GutTest
## Runs the real scene headless: placement, picking and the order panel.

var main: Node
var bridge: SimBridge
var view: LocalView
var panel: OrderPanel
var ship: int
var station: int
var rock: int


func before_each() -> void:
	main = add_child_autofree(load("res://client/main.tscn").instantiate())
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	view = main.get_node("LocalView")
	panel = main.order_panel
	var state := bridge.current_view
	for id: int in state["units"]:
		if state["units"][id]["kind"] == "ship":
			ship = id
		else:
			station = id
	var bodies: Array = state["bodies"].keys()
	bodies.sort()
	rock = bodies[1]


func _run_ticks(ticks: int) -> void:
	bridge.set_paused(false)
	bridge.set_speed(8)
	for i in range(ceili(ticks / 8.0)):
		bridge.advance(0.1)
	bridge.set_paused(true)
	view.refresh(0.016)


func _sim_ship_ticks_to(target: int) -> int:
	return bridge.check({ "type": "move_to", "unit": ship, "args": { "target": target } })["detail"]["ticks"]


func test_every_entity_gets_a_node() -> void:
	assert_eq(view.crafts.size(), bridge.current_view["units"].size())
	assert_eq(view.bodies.size(), bridge.current_view["bodies"].size())


func test_focus_starts_on_the_ship_at_the_render_origin() -> void:
	assert_eq(view.focus_id, ship)
	assert_almost_eq(view.crafts[ship].position.length(), 0.0, 0.0001)


func test_other_entities_sit_at_their_relative_position() -> void:
	var state := bridge.current_view
	var expected := FloatingOrigin.relative_m(
		state["units"][station]["pos_mm"], state["units"][station]["pos_mm"],
		state["units"][ship]["pos_mm"], state["units"][ship]["pos_mm"], 0.0)
	assert_almost_eq(view.crafts[station].position.distance_to(expected), 0.0, 0.001)


func test_star_is_compressed_inside_the_camera_range() -> void:
	for id: int in view.bodies:
		if view.bodies[id].kind == "star":
			assert_lt(view.bodies[id].position.length(), view.camera.far)
			assert_gt(view.bodies[id].scale.x, 1.0)


func test_click_ray_picks_a_part() -> void:
	await wait_physics_frames(3)
	var hit := view.pick_ray(Vector3(0, 2, 40), Vector3(0, 0, -1))
	assert_eq(hit["kind"], "unit")
	assert_eq(hit["id"], ship)
	assert_gt(hit["part"], 0)


func test_click_ray_picks_an_asteroid() -> void:
	await wait_physics_frames(3)
	var node: BodyNode = view.bodies[rock]
	var from: Vector3 = node.position + Vector3(0, 0, node.radius_m + 100.0)
	var hit := view.pick_ray(from, Vector3(0, 0, -1))
	assert_eq(hit, { "kind": "body", "id": rock, "part": 0 })


func test_click_ray_misses_empty_space() -> void:
	await wait_physics_frames(3)
	assert_true(view.pick_ray(Vector3(0, 900, 0), Vector3(0, 1, 0)).is_empty())


func _mouse(button_index: MouseButton, pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.position = at
	view._unhandled_input(event)


func test_left_click_selects_through_the_input_path() -> void:
	view.camera.target_distance_m = 5000.0
	view.camera.distance_m = 5000.0
	view.refresh(0.0)
	await wait_physics_frames(3)
	var at: Vector2 = view.camera.unproject_position(view.bodies[rock].position)
	_mouse(MOUSE_BUTTON_LEFT, true, at)
	_mouse(MOUSE_BUTTON_LEFT, false, at)
	await wait_physics_frames(2)
	assert_eq(view.selected_kind, "body")
	assert_eq(view.selected_id, rock)


func test_left_drag_is_not_a_click() -> void:
	view.select("unit", station, 0)
	_mouse(MOUSE_BUTTON_LEFT, true, Vector2(100, 100))
	_mouse(MOUSE_BUTTON_LEFT, false, Vector2(160, 100))
	await wait_physics_frames(2)
	assert_eq(view.selected_id, station)


func test_clicking_empty_space_clears_the_selection() -> void:
	view.camera.yaw = 0.0
	view.camera.pitch = 1.4
	view.refresh(0.0)
	await wait_physics_frames(3)
	_mouse(MOUSE_BUTTON_LEFT, true, Vector2(2, 2))
	_mouse(MOUSE_BUTTON_LEFT, false, Vector2(2, 2))
	await wait_physics_frames(2)
	assert_eq(view.selected_kind, "")
	assert_eq(panel._selection_label.text, "Nothing selected")


func test_right_drag_orbits_and_wheel_zooms() -> void:
	var yaw := view.camera.yaw
	_mouse(MOUSE_BUTTON_RIGHT, true, Vector2(100, 100))
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(50, 0)
	view._unhandled_input(drag)
	_mouse(MOUSE_BUTTON_RIGHT, false, Vector2(150, 100))
	assert_ne(view.camera.yaw, yaw)
	yaw = view.camera.yaw
	view._unhandled_input(drag)
	assert_eq(view.camera.yaw, yaw, "released button stops orbiting")
	var distance := view.camera.target_distance_m
	_mouse(MOUSE_BUTTON_WHEEL_UP, true, Vector2.ZERO)
	assert_lt(view.camera.target_distance_m, distance)


func test_tab_cycles_craft_and_focuses() -> void:
	var tab := InputEventKey.new()
	tab.pressed = true
	tab.physical_keycode = KEY_TAB
	view._unhandled_input(tab)
	assert_eq(view.focus_id, station)
	assert_eq(view.selected_id, station)


func test_selecting_a_part_highlights_only_that_part() -> void:
	var parts: Array = view.crafts[ship].part_transforms.keys()
	view.select("unit", ship, parts[1])
	assert_true(view.crafts[ship]._materials[parts[1]].emission_enabled)
	assert_false(view.crafts[ship]._materials[parts[2]].emission_enabled)


func test_selecting_a_station_keeps_the_commanded_ship() -> void:
	view.select("unit", station, 0)
	assert_eq(view.commanded_unit, ship)


func test_focus_change_glides_instead_of_snapping() -> void:
	view.select("body", rock, 0)
	var ship_from_pivot: Vector3 = view.crafts[ship].position - view.camera.pivot
	view.focus_on_selection()
	view.refresh(0.0)
	var shift: Vector3 = view.crafts[ship].position - view.camera.pivot - ship_from_pivot
	assert_lt(shift.length(), 0.01, "the scene does not jump relative to the camera")
	for i in range(300):
		view.refresh(0.016)
	assert_almost_eq(view.camera.pivot.distance_to(view.bodies[rock].position), 0.0, 0.01)


func test_ship_turns_nose_first_towards_its_route() -> void:
	view.select("body", rock, 0)
	assert_true(panel.press("Move to"))
	_run_ticks(8)
	for i in range(200):
		view.refresh(0.016)
	var unit: Dictionary = bridge.current_view["units"][ship]
	var route := CraftLayout.to_metres(unit["route"]["to_mm"]) - CraftLayout.to_metres(unit["route"]["from_mm"])
	var nose: Vector3 = view.crafts[ship].basis * Vector3.UP
	assert_almost_eq(nose.distance_to(route.normalized()), 0.0, 0.001)


func test_docked_ship_sits_on_the_station_port() -> void:
	view.select("unit", station, 0)
	assert_true(panel.press("Dock"))
	_run_ticks(28)
	for i in range(80):
		view.refresh(0.016)
	var dock: Dictionary = bridge.current_view["units"][ship]["dock"]
	assert_false(dock.is_empty())
	var host: CraftNode = view.crafts[station]
	var craft: CraftNode = view.crafts[ship]
	var modules: Dictionary = bridge.defs()["modules"]
	var host_point: Vector3 = host.transform * host.part_transforms[dock["target_port"]] \
		* CraftLayout.to_metres(CraftLayout.dock_connector(modules["stub_station_port"])["pos_mm"])
	var own_point: Vector3 = craft.transform * craft.part_transforms[dock["port"]] \
		* CraftLayout.to_metres(CraftLayout.dock_connector(modules["stub_port"])["pos_mm"])
	assert_almost_eq(host_point.distance_to(own_point), 0.0, 0.01)


func test_panel_offers_orders_for_an_asteroid_and_greys_invalid_ones() -> void:
	view.select("body", rock, 0)
	assert_not_null(panel.button_for("Move to"))
	assert_false(panel.button_for("Move to").disabled)
	assert_not_null(panel.button_for("Scan"))


func test_scan_then_mine_through_the_panel() -> void:
	view.select("body", rock, 0)
	assert_true(panel.button_for("Scan").disabled, "too far away to scan")
	assert_string_contains(panel.button_for("Scan").tooltip_text, "Out of range")
	assert_true(panel.press("Move to"))
	_run_ticks(_sim_ship_ticks_to(rock) + 8)
	assert_true(panel.press("Scan"))
	_run_ticks(38)
	view.select("body", rock, 0)
	assert_eq(panel._detail_label.text, "Scanned")
	var deposit: int = bridge.current_view["deposits"].keys()[0]
	var mine := panel.button_for("Mine %d" % deposit)
	assert_not_null(mine)
	assert_false(mine.disabled)
	assert_true(panel.press("Mine %d" % deposit))
	_run_ticks(8)
	assert_eq(bridge.current_view["units"][ship]["op"]["type"], "mining")
	assert_not_null(panel.button_for("Stop"))


func test_buttons_survive_ticks_so_clicks_are_not_lost() -> void:
	view.select("body", rock, 0)
	var button := panel.button_for("Move to")
	panel.refresh()
	panel.refresh()
	assert_same(panel.button_for("Move to"), button)


func test_rejection_reaches_the_event_log() -> void:
	bridge.submit({ "type": "undock", "unit": ship, "args": {} })
	_run_ticks(8)
	assert_string_contains(main.event_log.lines[-1], "Not docked")


func test_unknown_reason_codes_still_read_cleanly() -> void:
	assert_eq(OrderText.reason("some_new_reason"), "Some New Reason")


func test_range_details_show_numbers() -> void:
	assert_eq(OrderText.reason("out_of_range", { "need_mm": 500000, "have_mm": 3200000 }), "Out of range (3.2 km, needs 500 m)")
