extends GutTest
## Real mouse events on the 3D view while the Fit screen is open, on a drone docked
## beside the station. A click that misses a ring must leave the fit where it is.

const GRID_PX := 20
const SETTLE_STEPS := 200

var main: Node
var bridge: SimBridge
var view: LocalView
var screen: FittingScreen
var window: Window
var drone: int
var station: int
var _runner_filters: Dictionary = {}


func before_all() -> void:
	for found: Node in get_window().find_children("*", "Control", true, false):
		_runner_filters[found] = (found as Control).mouse_filter
		(found as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func after_all() -> void:
	for control: Control in _runner_filters:
		control.mouse_filter = _runner_filters[control]


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	view = main.get_node("LocalView")
	screen = main.fitting_screen
	window = main.get_window()
	await wait_process_frames(3)
	drone = ScreenshotDriver.build_drone(bridge, 6)
	station = ScreenshotDriver._unit_of_kind(bridge.current_view, "station")
	view.refresh(0.0)
	view.select("unit", drone, 0)
	main.toggle_fitting()
	await _settle()


## Headless frames are too short for the camera's glide or a new craft easing into
## its dock, so both are run on by hand.
func _settle() -> void:
	for i in range(SETTLE_STEPS):
		view.refresh(0.016)
	view.camera.distance_m = view.camera.target_distance_m
	view._pivot_offset = Vector3.ZERO
	await wait_process_frames(5)
	await wait_physics_frames(3)


func _move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	window.push_input(motion, true)
	await wait_process_frames(2)


func _button(at: Vector2, index: MouseButton, down: bool) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = index
	click.pressed = down
	click.button_mask = (1 << (index - 1)) if down else 0
	click.position = at
	click.global_position = at
	window.push_input(click, true)
	await wait_process_frames(2)


func _click(at: Vector2) -> void:
	await _move(at)
	await _button(at, MOUSE_BUTTON_LEFT, true)
	await _button(at, MOUSE_BUTTON_LEFT, false)
	await wait_physics_frames(3)


## A spot on the 3D view with no ring, no name marker and no panel over it, whose
## ray hit passes `wanted`.
func _spot(wanted: Callable) -> Vector2:
	var size := window.get_visible_rect().size
	await get_tree().physics_frame
	var spots: Array[Vector2] = []
	for x in range(GRID_PX, int(size.x), GRID_PX):
		for y in range(GRID_PX, int(size.y), GRID_PX):
			var at := Vector2(x, y)
			var ray := view.camera.project_ray_normal(at)
			if wanted.call(view.pick_ray(view.camera.project_ray_origin(at), ray)) and _is_clear(at):
				spots.append(at)
	for at: Vector2 in spots:
		await _move(at)
		if window.gui_get_hovered_control() == screen.markers:
			return at
	fail_test("no clear spot on screen")
	return Vector2.ZERO


func _is_clear(at: Vector2) -> bool:
	return screen.markers.pick(at).is_empty() and view.markers.pick(at).is_empty()


func _on_station(hit: Dictionary) -> bool:
	return hit.get("kind", "") == "unit" and hit["id"] == station


func _on_drone(hit: Dictionary) -> bool:
	return hit.get("kind", "") == "unit" and hit["id"] == drone


func _on_nothing(hit: Dictionary) -> bool:
	return hit.is_empty()


func _on_container(hit: Dictionary) -> bool:
	if not _on_drone(hit):
		return false
	for part: Dictionary in InspectText.flatten(bridge.current_view["units"][drone]["parts"]):
		if part["id"] == hit["part"]:
			return part["def"] == "small_ore_container_mk1"
	return false


func _assert_fit_unmoved() -> void:
	assert_eq(view.selected_kind, "unit")
	assert_eq(view.selected_id, drone)
	assert_eq(screen.fit_unit(), drone)
	assert_eq(screen._title.text, "Fitting: Small Craft")


func test_a_stray_click_on_the_station_changes_nothing() -> void:
	await _click(await _spot(_on_station))
	_assert_fit_unmoved()


func test_a_stray_click_on_empty_space_changes_nothing() -> void:
	await _click(await _spot(_on_nothing))
	_assert_fit_unmoved()


func test_a_stray_click_keeps_the_chosen_part_and_slot() -> void:
	ScreenshotDriver.stock_part(bridge, "small_heat_radiator_mk1")
	ScreenshotDriver._step(bridge)
	screen.refresh()
	screen.choose(screen._stock[0])
	var ring: Dictionary = screen.markers._shown[0]
	await _click(ring["at"])
	assert_eq(screen.slot, ring["slot"])
	await _click(await _spot(_on_station))
	assert_eq(screen.slot, ring["slot"])
	assert_false(screen.chosen.is_empty())
	_assert_fit_unmoved()


func test_clicking_a_part_of_the_craft_selects_it_for_removal() -> void:
	assert_true(screen._remove_button.disabled, "nothing picked yet")
	await _click(await _spot(_on_container))
	assert_eq(view.selected_id, drone)
	assert_ne(view.selected_part, 0)
	assert_false(screen._remove_button.disabled)


func test_a_stray_click_keeps_a_part_selected_for_removal() -> void:
	await _click(await _spot(_on_container))
	var part := view.selected_part
	await _click(await _spot(_on_station))
	assert_eq(view.selected_part, part)
	assert_false(screen._remove_button.disabled)


func test_a_ring_still_works_after_a_stray_click() -> void:
	await _click(await _spot(_on_station))
	var ring: Dictionary = screen.markers._shown[0]
	await _click(ring["at"])
	assert_eq(screen.slot, ring["slot"])


func test_right_drag_still_orbits_the_camera() -> void:
	var at := await _spot(_on_nothing)
	var yaw := view.camera.yaw
	await _move(at)
	await _button(at, MOUSE_BUTTON_RIGHT, true)
	var motion := InputEventMouseMotion.new()
	motion.position = at + Vector2(40, 0)
	motion.global_position = motion.position
	motion.relative = Vector2(40, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	window.push_input(motion, true)
	await wait_process_frames(2)
	await _button(at + Vector2(40, 0), MOUSE_BUTTON_RIGHT, false)
	assert_ne(view.camera.yaw, yaw)
	_assert_fit_unmoved()


func test_the_wheel_still_zooms() -> void:
	var at := await _spot(_on_nothing)
	var distance := view.camera.target_distance_m
	await _button(at, MOUSE_BUTTON_WHEEL_DOWN, true)
	await _button(at, MOUSE_BUTTON_WHEEL_DOWN, false)
	assert_gt(view.camera.target_distance_m, distance)


func test_clicks_select_as_usual_once_fit_is_closed() -> void:
	var at := await _spot(_on_station)
	main.toggle_fitting()
	await wait_process_frames(2)
	await _click(at)
	assert_eq(view.selected_id, station)
