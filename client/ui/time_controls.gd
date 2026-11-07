class_name TimeControls extends PanelContainer
## Pause and speed controls with the mission clock. Space pauses; keys 1 to 4
## pick a speed. These are raw keys so project.godot needs no input map.

signal map_pressed
signal fly_pressed
signal policy_pressed
signal fit_pressed
signal jobs_pressed
signal research_pressed
## A fresh game of a start (Main.STARTS), from the New menu.
signal new_game_pressed(scenario: String)
signal auto_pressed
signal save_pressed
signal load_pressed

## Left edge of the warp readout, past the inspection panel under the bar.
const WARP_LABEL_LEFT_PX := 350.0

var bridge: SimBridge

var _pause_button: Button
var _speed_buttons: Dictionary = {}
var _clock: Label
## Above 8×: the speed reached and why it's held back. Below the toolbar row.
var warp_label: Label
var _through_jobs: CheckBox
## Toolbar buttons greyed until useful, by ToolbarGates gate name (D39).
var gate_buttons: Dictionary = {}
## "Warp past jobs" shows once a job exists, and stays (D39). A clock that goes
## back (a new game, a load) starts over.
var _jobs_seen := false
var _last_tick := 0


func _ready() -> void:
	theme = ClientTheme.build()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	_pause_button = Button.new()
	_pause_button.custom_minimum_size = Vector2(84, 0)
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.pressed.connect(func() -> void: bridge.set_paused(not bridge.paused))
	row.add_child(_pause_button)
	for value: int in SimBridge.SPEEDS:
		var button := Button.new()
		button.text = WarpLogic.speed_label(value)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: bridge.set_speed(value))
		row.add_child(button)
		_speed_buttons[value] = button
	var map_button := Button.new()
	map_button.text = "Map"
	map_button.focus_mode = Control.FOCUS_NONE
	map_button.pressed.connect(func() -> void: map_pressed.emit())
	row.add_child(map_button)
	var fly_button := Button.new()
	fly_button.text = "Fly"
	fly_button.focus_mode = Control.FOCUS_NONE
	fly_button.pressed.connect(func() -> void: fly_pressed.emit())
	row.add_child(fly_button)
	var fit_button := Button.new()
	fit_button.text = "Fit"
	fit_button.focus_mode = Control.FOCUS_NONE
	fit_button.pressed.connect(func() -> void: fit_pressed.emit())
	row.add_child(fit_button)
	var jobs_button := Button.new()
	jobs_button.text = "Jobs"
	jobs_button.focus_mode = Control.FOCUS_NONE
	jobs_button.pressed.connect(func() -> void: jobs_pressed.emit())
	row.add_child(jobs_button)
	var research_button := Button.new()
	research_button.text = "Research"
	research_button.focus_mode = Control.FOCUS_NONE
	research_button.pressed.connect(func() -> void: research_pressed.emit())
	row.add_child(research_button)
	gate_buttons["research"] = research_button
	var auto_button := Button.new()
	auto_button.text = "Auto"
	auto_button.focus_mode = Control.FOCUS_NONE
	auto_button.pressed.connect(func() -> void: auto_pressed.emit())
	row.add_child(auto_button)
	gate_buttons["auto"] = auto_button
	var policy_button := Button.new()
	policy_button.text = "Policy"
	policy_button.focus_mode = Control.FOCUS_NONE
	policy_button.pressed.connect(func() -> void: policy_pressed.emit())
	row.add_child(policy_button)
	gate_buttons["policy"] = policy_button
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.pressed.connect(func() -> void: save_pressed.emit())
	row.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "Load"
	load_button.focus_mode = Control.FOCUS_NONE
	load_button.pressed.connect(func() -> void: load_pressed.emit())
	row.add_child(load_button)
	var new_button := MenuButton.new()
	new_button.text = "New"
	new_button.focus_mode = Control.FOCUS_NONE
	new_button.flat = false
	for index in range(Main.STARTS.size()):
		new_button.get_popup().add_item(Main.START_NAMES[Main.STARTS[index]], index)
	new_button.get_popup().id_pressed.connect(func(index: int) -> void: new_game_pressed.emit(Main.STARTS[index]))
	row.add_child(new_button)
	_clock = Label.new()
	_clock.custom_minimum_size = Vector2(190, 0)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_clock)
	warp_label = Label.new()
	warp_label.modulate = ClientTheme.MID_GREY.lightened(0.35)
	warp_label.visible = false
	warp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	warp_label.add_theme_constant_override("outline_size", 6)
	# A child the bar's container doesn't lay out: it floats just under the bar,
	# clear of the panel at the left, and is freed with the bar.
	warp_label.top_level = true
	add_child(warp_label)
	_through_jobs = CheckBox.new()
	_through_jobs.text = "Warp past jobs"
	_through_jobs.tooltip_text = "Above 8×, keep warping when a job finishes instead of dropping to 1×"
	_through_jobs.focus_mode = Control.FOCUS_NONE
	_through_jobs.toggled.connect(func(on: bool) -> void: bridge.warp_through_jobs = on)
	row.add_child(_through_jobs)


## Greys a gated button, with a tooltip saying when it helps, or opens it.
func set_gate(gate: String, open: bool) -> void:
	var button: Button = gate_buttons[gate]
	button.disabled = not open
	button.tooltip_text = "" if open else ToolbarGates.GATES[gate]["tip"]


func bind(new_bridge: SimBridge) -> void:
	bridge = new_bridge
	bridge.time_changed.connect(_refresh)
	bridge.view_updated.connect(_refresh)
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_SPACE:
		bridge.set_paused(not bridge.paused)
		get_viewport().set_input_as_handled()
		return
	var index: int = key.physical_keycode - KEY_1
	if index >= 0 and index < SimBridge.SPEEDS.size():
		bridge.set_speed(SimBridge.SPEEDS[index])
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	_pause_button.text = "Resume" if bridge.paused else "Pause"
	for value: int in _speed_buttons:
		_speed_buttons[value].set_pressed_no_signal(value == bridge.speed)
	_clock.text = WarpLogic.clock_text(floori(bridge.game_seconds()))
	var tick := int(bridge.current_view.get("tick", 0))
	if tick < _last_tick:
		_jobs_seen = false
	_last_tick = tick
	_jobs_seen = _jobs_seen or not bridge.current_view.get("jobs", {}).is_empty()
	_through_jobs.visible = _jobs_seen or _through_jobs.button_pressed
	warp_label.visible = bridge.speed > WarpLogic.STEP_MAX and not bridge.paused
	if warp_label.visible:
		warp_label.global_position = global_position + Vector2(WARP_LABEL_LEFT_PX, size.y + 6)
		var cap := bridge.shown_cap()
		warp_label.text = "Warp %s%s" % [WarpLogic.achieved_text(bridge.achieved_speed),
			"" if cap.is_empty() else ", held back: %s" % WarpLogic.cap_text(cap)]
	_clock.modulate = ClientTheme.ORANGE if bridge.paused else Color.WHITE
