extends GutTest
## The Fit screen's connector rings on the smallest craft, measured with real mouse clicks.

const SETTLE_FRAMES := 5
const SETTLE_STEPS := 200
const PART := "small_ore_container_mk1"

var main: Node
var bridge: SimBridge
var view: LocalView
var screen: FittingScreen
var window: Window
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


func _open_on_drone(fitted: int) -> int:
	var drone := ScreenshotDriver.build_drone(bridge, fitted)
	ScreenshotDriver.stock_part(bridge, PART)
	view.refresh(0.0)
	view.select("unit", drone, 0)
	main.toggle_fitting()
	for entry: Dictionary in screen._stock:
		if entry["item"] == PART:
			screen.choose(entry)
	await _settle()
	return drone


## Headless frames are too short for the camera's glide or a new craft easing into
## its dock, so both are run on by hand.
func _settle() -> void:
	for i in range(SETTLE_STEPS):
		view.refresh(0.016)
	view.camera.distance_m = view.camera.target_distance_m
	view._pivot_offset = Vector3.ZERO
	await wait_process_frames(SETTLE_FRAMES)


func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	window.push_input(motion, true)
	await wait_process_frames(2)
	for down: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		click.position = at
		click.global_position = at
		window.push_input(click, true)
		await wait_process_frames(2)


func _ring_of(slot: Dictionary) -> Dictionary:
	for entry: Dictionary in screen.markers._shown:
		if entry["slot"] == slot:
			return entry
	return {}


## Clicks the centre of every ring and returns those that did not pick themselves.
func _missed_rings(drone: int) -> Array[String]:
	var slots: Array = screen.markers._shown.map(func(entry: Dictionary) -> Dictionary: return entry["slot"])
	assert_gt(slots.size(), 0, "rings are showing")
	var wrong: Array[String] = []
	for slot: Dictionary in slots:
		screen.slot = {}
		await _click(_ring_of(slot)["at"])
		if screen.slot != slot:
			wrong.append("%s -> %s" % [slot["connector"], screen.slot.get("connector", "nothing")])
			view.select("unit", drone, 0)
			await _settle()
	return wrong


func test_every_ring_on_a_bare_craft_can_be_clicked_from_all_round() -> void:
	var drone := await _open_on_drone(0)
	for step in range(12):
		view.camera.yaw = step * TAU / 12.0
		await _settle()
		assert_eq(await _missed_rings(drone), [] as Array[String], "yaw step %d" % step)


func test_every_ring_left_on_a_finished_drone_can_be_clicked() -> void:
	var drone := await _open_on_drone(6)
	assert_eq(await _missed_rings(drone), [] as Array[String])
