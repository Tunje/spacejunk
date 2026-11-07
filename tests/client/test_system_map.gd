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
	assert_eq(SystemMap.ring_label(300000.0), "300,000 km")
	assert_eq(SystemMap.ring_label(3000000.0), "3 million km")
	assert_eq(SystemMap.ring_label(0.1 * SystemMap.AU_KM), "0.1 AU")
	assert_eq(SystemMap.ring_label(SystemMap.AU_KM), "1 AU")


## D39: no ring is more than about ten times the one inside it, so the gap from the
## cluster to the planets reads in steps.
func test_rings_step_across_the_gap() -> void:
	for index in range(3, SystemMap.RINGS_KM.size()):
		var ratio := SystemMap.RINGS_KM[index] / SystemMap.RINGS_KM[index - 1]
		assert_between(ratio, 1.5, 5.1, "ring %d" % index)
	assert_eq(SystemMap.RINGS_KM[SystemMap.RINGS_KM.size() - 1], 3.0 * SystemMap.AU_KM, "past the home planet")


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


## A41a: a trip between planes says how much of it is the plane change.
func test_trip_text_names_a_plane_change() -> void:
	var quote := { "kind": "transfer", "ticks": 1200, "depart_tick": 600, "dv_um_s": 90_000_000,
		"plane_change_dv_um_s": 35_000_000 }
	assert_eq(SystemMap.trip_text(quote, 0, 10), "Departs in 1 min 0 s, 2 min 0 s trip, including a %s plane change"
		% FlightLogic.speed(35_000_000))
	quote["plane_change_dv_um_s"] = 0
	assert_eq(SystemMap.trip_text(quote, 0, 10), "Departs in 1 min 0 s, 2 min 0 s trip", "one plane: unchanged")


## D40: the trip's propellant, where its plane change is burned, and A43's faster plan.
func test_trip_text_offers_the_faster_plan() -> void:
	var quote := { "kind": "transfer", "target": 4, "ticks": 972_000, "depart_tick": 0, "arrive_tick": 972_000,
		"cost_g": 235_000, "plane_change_dv_um_s": 35_000_000, "plane_change_at": "arrival",
		"other": { "arrive_tick": 90_000, "cost_g": 401_000 } }
	assert_eq(SystemMap.trip_text(quote, 0, 10),
		"27 h 0 min trip, 235.0 kg, including a %s plane change joined to the arrival burn\nFaster: 401.0 kg, arrives in 2 h 30 min"
		% FlightLogic.speed(35_000_000))
	quote.erase("other")
	assert_false(SystemMap.trip_text(quote, 0, 10).contains("Faster"), "one plan, one line")


func test_move_to_faster_is_offered_beside_move_to() -> void:
	var quote := { "kind": "transfer", "target": 4, "arrive_tick": 972_000, "cost_g": 235_000,
		"other": { "arrive_tick": 90_000, "cost_g": 401_000 } }
	var orders: Array[Dictionary] = [
		{ "key": "Move to", "label": "Move to", "command": { "type": "move_to", "unit": 1, "args": { "target": 4 } } },
		{ "key": "Scan", "label": "Scan", "command": { "type": "start_scan", "unit": 1, "args": {} } },
	]
	TripChoice.add_fast_option(orders, quote, 0, 10)
	assert_eq(orders.size(), 3)
	assert_eq(orders[0]["label"], "Move to: 235.0 kg, arrives in 27 h 0 min")
	assert_eq(orders[1]["key"], TripChoice.FAST_KEY)
	assert_eq(orders[1]["label"], "Move to, faster: 401.0 kg, arrives in 2 h 30 min")
	assert_eq(orders[1]["command"]["args"], { "target": 4, "prefer": "fast" })
	assert_false(orders[0]["command"]["args"].has("prefer"), "Move to stays the cheap default")
	var single: Array[Dictionary] = [orders[0].duplicate(true)]
	quote.erase("other")
	TripChoice.add_fast_option(single, quote, 0, 10)
	assert_eq(single.size(), 1, "no faster plan, no second button")


## A trip already ordered is shown as such, not quoted again.
func test_a_trip_under_way_is_reported_not_quoted_again() -> void:
	var view := { "tick": 100, "units": { 1: { "op": { "type": "idle" }, "transfer": { "target": 9, "arrive_tick": 700 } } } }
	assert_eq(SystemMap.trip_under_way(view, 1, 9, 10), "On the way, arrives in 1 min 0 s")
	assert_eq(SystemMap.trip_under_way(view, 1, 8, 10), "", "elsewhere: quote it")
	view["units"][1] = { "op": { "type": "waiting", "plan": { "target": 9, "depart_tick": 400, "arrive_tick": 1300 } }, "transfer": {} }
	assert_eq(SystemMap.trip_under_way(view, 1, 9, 10), "Waiting for the window: departs in 30 s, arrives in 2 min 0 s")
