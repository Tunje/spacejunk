extends GutTest

var main: Node
var bridge: SimBridge
var view: LocalView
var map: SystemMap
var panel: OrderPanel
var ship: int
var station: int
var rock: int


func before_each() -> void:
	main = add_child_autofree(StubScene.build())
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	view = main.get_node("LocalView")
	map = main.get_node("SystemMap")
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


func _entry(kind: String, id: int) -> Dictionary:
	for entry: Dictionary in map.entries:
		if entry["kind"] == kind and entry["id"] == id:
			return entry
	return {}


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = code
	main._unhandled_key_input(event)


func test_projection_keeps_the_centre_and_direction() -> void:
	assert_eq(SystemMap.project(Vector3.ZERO), Vector3.ZERO)
	var direction := Vector3(3, 0, 4)
	var projected := SystemMap.project(direction * 1000.0)
	assert_almost_eq(projected.normalized().distance_to(direction.normalized()), 0.0, 0.0001)


func test_map_radius_always_grows_with_distance() -> void:
	var previous := -1.0
	for distance: float in [0.0, 500.0, 3000.0, 90000.0, 110000.0, 5e7, 1.5e11, 3e15]:
		var radius := SystemMap.map_radius(distance)
		assert_gt(radius, previous)
		previous = radius


func test_map_radius_is_continuous_where_the_scale_changes() -> void:
	var edge := (pow(10.0, SystemMap.NEAR_DECADES) - 1.0) * SystemMap.KM_IN_M
	assert_almost_eq(SystemMap.map_radius(edge * 0.9999), SystemMap.map_radius(edge * 1.0001), 0.01)


func test_star_and_asteroids_share_one_frame() -> void:
	assert_lt(SystemMap.map_radius(1.5e11), 40.0)
	assert_gt(SystemMap.map_radius(3000.0), 3.0)


func test_ring_labels_read_cleanly() -> void:
	assert_eq(SystemMap.ring_label(10.0), "10 km")
	assert_eq(SystemMap.ring_label(100000000.0), "100 million km")


func test_map_starts_closed() -> void:
	assert_false(map.is_open())
	assert_true(view.camera.current)


func test_m_toggles_between_views() -> void:
	_key(KEY_M)
	assert_true(map.is_open())
	assert_false(view.visible)
	assert_false(view.markers.visible)
	assert_true(map.camera.current)
	_key(KEY_M)
	assert_false(map.is_open())
	assert_true(view.visible)
	assert_true(view.camera.current)


func test_escape_closes_the_map_only() -> void:
	_key(KEY_ESCAPE)
	assert_false(map.is_open())
	_key(KEY_M)
	_key(KEY_ESCAPE)
	assert_false(map.is_open())


func test_the_map_button_opens_the_map() -> void:
	main.time_controls.map_pressed.emit()
	assert_true(map.is_open())


func test_every_body_and_unit_is_on_the_map_and_the_commanded_craft_is_central() -> void:
	main.toggle_map()
	var state := bridge.current_view
	assert_eq(map.entries.size(), state["units"].size() + state["bodies"].size())
	assert_eq(_entry("unit", ship)["map_pos"], Vector3.ZERO)
	assert_gt(_entry("body", rock)["map_pos"].length(), 0.0)


func test_clicking_a_marker_shares_the_selection_with_the_local_view() -> void:
	main.toggle_map()
	await wait_process_frames(2)
	var at: Vector2 = map.camera.unproject_position(_entry("body", rock)["map_pos"])
	map.click_at(at)
	assert_eq(view.selected_kind, "body")
	assert_eq(view.selected_id, rock)
	assert_not_null(panel.button_for("Move to"))


func test_clicking_nothing_clears_the_selection() -> void:
	main.toggle_map()
	view.select("body", rock, 0)
	await wait_process_frames(2)
	map.click_at(Vector2(3, 890))
	assert_eq(view.selected_kind, "")


func test_local_view_ignores_input_while_the_map_is_open() -> void:
	main.toggle_map()
	var yaw := view.camera.yaw
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	view._unhandled_input(press)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(80, 0)
	view._unhandled_input(drag)
	assert_eq(view.camera.yaw, yaw)


func test_map_orbits_with_its_own_camera() -> void:
	main.toggle_map()
	var yaw := map.camera.yaw
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	map._unhandled_input(press)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(80, 0)
	map._unhandled_input(drag)
	assert_ne(map.camera.yaw, yaw)


func test_selection_shows_a_route_preview_and_travel_time() -> void:
	main.toggle_map()
	assert_eq(map.routes.mesh.get_surface_count(), 0)
	view.select("body", rock, 0)
	map.refresh(0.0)
	assert_eq(map.routes.mesh.get_surface_count(), 1)
	assert_ne(map.eta_text, "")


func test_invalid_move_shows_no_travel_time() -> void:
	main.toggle_map()
	var state := bridge.current_view
	for id: int in state["bodies"]:
		if state["bodies"][id]["kind"] == "star":
			view.select("body", id, 0)
	map.refresh(0.0)
	assert_eq(map.eta_text, "")


func test_ordering_from_the_map_draws_the_live_route() -> void:
	main.toggle_map()
	view.select("body", rock, 0)
	assert_true(panel.press("Move to"))
	bridge.set_paused(false)
	bridge.advance(0.2)
	bridge.set_paused(true)
	map.refresh(0.0)
	assert_eq(bridge.current_view["units"][ship]["op"]["type"], "moving")
	assert_eq(map.routes.mesh.get_surface_count(), 1, "the route replaces the preview")


func test_durations_read_cleanly() -> void:
	assert_eq(OrderText.duration(12.2), "13 s")
	assert_eq(OrderText.duration(125.0), "2 min 5 s")
	assert_eq(OrderText.duration(7320.0), "2 h 2 min")
