extends GutTest
## Drives the real main scene with mouse events through the viewport, so a button
## that is covered or dead fails here. OrderPanel.press cannot see either. Events
## are in local coordinates on purpose: the buttons report those in get_global_rect.

var main: Node
var bridge: SimBridge
var view: LocalView
var panel: OrderPanel
var window: Window
var _runner_filters: Dictionary = {}


func before_all() -> void:
	_set_runner_clickable(false)


func after_all() -> void:
	_set_runner_clickable(true)


## GUT's own output window covers the screen, even headless. Only that is let through.
func _set_runner_clickable(clickable: bool) -> void:
	if clickable:
		for control: Control in _runner_filters:
			control.mouse_filter = _runner_filters[control]
		return
	for found: Node in get_window().find_children("*", "Control", true, false):
		_runner_filters[found] = (found as Control).mouse_filter
		(found as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = "reference"
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	view = main.get_node("LocalView")
	panel = main.order_panel
	window = main.get_window()
	await wait_process_frames(3)


func _move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	window.push_input(motion, true)
	await wait_process_frames(2)


func _click(at: Vector2) -> void:
	await _move(at)
	for down: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		click.position = at
		click.global_position = at
		window.push_input(click, true)
		await wait_process_frames(2)


## A button scrolled out of its list has no pixels to reach, so it is left out.
func _on_screen(button: Button) -> bool:
	if not button.is_visible_in_tree():
		return false
	var parent := button.get_parent()
	while parent is Control:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().has_point(button.get_global_rect().get_center()):
			return false
		parent = parent.get_parent()
	return true


## Hovers every button showing and returns those the mouse could not reach.
func _unreachable() -> Array[String]:
	var missed: Array[String] = []
	for found: Node in main.find_children("*", "Button", true, false):
		var button := found as Button
		if _on_screen(button):
			await _move(button.get_global_rect().get_center())
			if not button.is_hovered():
				missed.append("%s under %s" % [button.text, window.gui_get_hovered_control()])
	return missed


func _sweep(label: String) -> void:
	var count := 0
	for found: Node in main.find_children("*", "Button", true, false):
		if _on_screen(found as Button):
			count += 1
	assert_gt(count, 0, "%s shows buttons" % label)
	assert_eq(await _unreachable(), [] as Array[String], label)


func _rock() -> int:
	var state: Dictionary = bridge.current_view
	for id: int in state["bodies"]:
		if state["bodies"][id]["kind"] == "asteroid":
			return id
	return 0


func test_every_button_on_the_opening_screen_is_reachable() -> void:
	await _sweep("opening screen")


func test_every_button_with_a_rock_selected_is_reachable() -> void:
	view.select("body", _rock(), 0)
	await wait_process_frames(2)
	await _sweep("rock selected")


func test_every_button_on_the_side_screens_is_reachable() -> void:
	for toggle: Callable in [main.toggle_fitting, main.toggle_industry, main.toggle_automation]:
		toggle.call()
		await wait_process_frames(2)
		await _sweep(toggle.get_method())
		toggle.call()
		await wait_process_frames(2)


func test_every_button_on_the_map_is_reachable() -> void:
	main.toggle_map()
	await wait_process_frames(2)
	await _sweep("map")


func test_clicking_undock_starts_the_undock() -> void:
	var ship: int = view.commanded_unit
	var button := panel.button_for("Undock")
	await _click(button.get_global_rect().get_center())
	assert_eq(button.text, "Undocking 0%", "the click shows before any tick")
	bridge.set_paused(false)
	bridge.advance(0.2)
	bridge.set_paused(true)
	assert_eq(bridge.current_view["units"][ship]["op"]["type"], "undocking")
