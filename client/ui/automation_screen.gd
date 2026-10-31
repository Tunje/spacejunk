class_name AutomationScreen extends PanelContainer
## The handover: pick a core, then repeat a trip flown by hand as a cycle. Shows
## each step of a running cycle and why it is blocked. All rules are the Sim's.

const WIDTH_PX := 400
const CURRENT_MARK := "> "
const OTHER_MARK := "   "

signal closed

var bridge: SimBridge
var local_view: LocalView
var trip: Array[Dictionary] = []
var trip_unit := 0
var _defs: Dictionary = {}
var _core_key := ""
var _trip_key := ""
var _title: Label
var _core_label: Label
var _core_box: VBoxContainer
var _trip_box: VBoxContainer
var _repeat_button: Button
var _cycle_title: Label
var _cycle_box: VBoxContainer
var _block_label: Label
var _stop_button: Button
var _resume_button: Button
var _message: Label


func _ready() -> void:
	theme = ClientTheme.build()
	add_theme_stylebox_override("panel", ClientTheme.solid_panel())
	custom_minimum_size = Vector2(WIDTH_PX, 0)
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = _add_label(header)
	_title.modulate = ClientTheme.ORANGE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := _add_button(header, "Close")
	close.pressed.connect(toggle)
	_core_label = _add_label(column)
	_core_box = _add_box(column)
	column.add_child(HSeparator.new())
	_add_heading(column, "Last trip flown by hand")
	_trip_box = _add_box(column)
	_repeat_button = _add_button(column, "Repeat this route")
	_repeat_button.pressed.connect(repeat_route)
	column.add_child(HSeparator.new())
	_cycle_title = _add_label(column)
	_cycle_box = _add_box(column)
	_block_label = _add_label(column)
	_block_label.modulate = ClientTheme.ORANGE
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_stop_button = _add_button(buttons, "Stop cycle")
	_stop_button.pressed.connect(stop_cycle)
	_resume_button = _add_button(buttons, "Resume last cycle")
	_resume_button.pressed.connect(resume_cycle)
	_message = _add_label(column)
	_message.modulate = ClientTheme.GOLD


func bind(new_bridge: SimBridge, view: LocalView, orders: OrderPanel) -> void:
	bridge = new_bridge
	local_view = view
	_defs = bridge.defs()
	orders.order_issued.connect(note_order)
	bridge.view_updated.connect(refresh)
	local_view.selection_changed.connect(refresh)


func toggle() -> void:
	visible = not visible
	if visible:
		_message.text = ""
		refresh()
	else:
		closed.emit()


## Called for every order the player gives through the panel.
func note_order(command: Dictionary) -> void:
	if command["unit"] != trip_unit:
		trip_unit = command["unit"]
		trip.clear()
	CyclePlan.record(trip, command)


func save_state() -> Dictionary:
	return { "trip": trip.duplicate(true), "trip_unit": trip_unit }


func restore_state(state: Dictionary) -> void:
	trip.assign(state.get("trip", []))
	trip_unit = state.get("trip_unit", 0)
	_trip_key = ""
	_core_key = ""


func unit() -> Dictionary:
	return bridge.current_view["units"].get(local_view.commanded_unit, {})


func planned_steps() -> Array[Dictionary]:
	return CyclePlan.adapt(trip, local_view.commanded_unit, bridge.current_view, _defs)


func repeat_route() -> void:
	_send(CyclePlan.cycle_command(local_view.commanded_unit, planned_steps()), planned_steps())


func remove_trip_step(index: int) -> void:
	trip.remove_at(index)
	_trip_key = ""
	refresh()


func assign(core_part: int) -> void:
	_send({ "type": "assign_core", "unit": local_view.commanded_unit, "args": { "core": core_part } }, [])


func stop_cycle() -> void:
	bridge.submit({ "type": "stop", "unit": local_view.commanded_unit, "args": {} })


func resume_cycle() -> void:
	var steps: Array[Dictionary] = []
	steps.assign(unit()["last_cycle"])
	_send(CyclePlan.cycle_command(local_view.commanded_unit, steps), steps)


## Checks first, so a refusal is explained. `bad_cycle` names the step at fault.
func _send(command: Dictionary, steps: Array[Dictionary]) -> void:
	var result: Dictionary = bridge.check(command)
	_message.text = "" if result["ok"] else _refusal(result, steps)
	if result["ok"]:
		bridge.submit(command)


func _refusal(result: Dictionary, steps: Array[Dictionary]) -> String:
	var text := OrderText.reason(result["reason"])
	var index: int = result["detail"].get("step", -1)
	if result["reason"] == "bad_cycle" and index >= 0 and index < steps.size():
		text += ": step %d, %s" % [index + 1, CyclePlan.step_text(steps[index], bridge.current_view, _defs)]
	return text


func refresh() -> void:
	if not visible or unit().is_empty():
		return
	var shown := unit()
	var view: Dictionary = bridge.current_view
	_title.text = "Automation: %s" % shown["name"]
	_show_cores(shown)
	_show_trip(view)
	_show_cycle(shown, view)


func _show_cores(shown: Dictionary) -> void:
	var cores := CyclePlan.cores(shown, _defs["modules"])
	_core_label.text = InspectText.core(shown)
	var key := "%s:%d" % [str(cores), shown["core"]]
	if key == _core_key:
		return
	_core_key = key
	_clear(_core_box)
	if cores.is_empty():
		_add_label(_core_box).text = "No core fitted. Fit one with the Fit screen."
	for core: Dictionary in cores:
		var button := _add_button(_core_box, "Use %s (tier %d)" % [core["name"], core["tier"]])
		button.disabled = core["part"] == shown["core"]
		button.pressed.connect(assign.bind(core["part"]))


func _show_trip(view: Dictionary) -> void:
	var key := str(trip)
	_repeat_button.disabled = trip.is_empty()
	if key == _trip_key:
		return
	_trip_key = key
	_clear(_trip_box)
	if trip.is_empty():
		_add_label(_trip_box).text = "Fly a trip with orders first: undock, mine, return, unload."
	for index in range(trip.size()):
		var row := HBoxContainer.new()
		_trip_box.add_child(row)
		var label := _add_label(row)
		label.text = "%d. %s" % [index + 1, CyclePlan.step_text(trip[index], view, _defs)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var remove := _add_button(row, "Remove")
		remove.pressed.connect(remove_trip_step.bind(index))


func _show_cycle(shown: Dictionary, view: Dictionary) -> void:
	var task := CyclePlan.running_cycle(shown, view)
	var running := not task.is_empty()
	_stop_button.disabled = not running
	_resume_button.disabled = running or shown["last_cycle"].is_empty()
	_clear(_cycle_box)
	if not running:
		_cycle_title.text = "No cycle running"
		_block_label.visible = false
		return
	_cycle_title.text = "Cycle running, %d lap%s done" % [task["cycle"], "" if task["cycle"] == 1 else "s"]
	for index in range(task["steps"].size()):
		var label := _add_label(_cycle_box)
		var mark: String = CURRENT_MARK if index == task["step"] else OTHER_MARK
		label.text = "%s%d. %s" % [mark, index + 1, CyclePlan.step_text(task["steps"][index], view, _defs)]
		label.modulate = ClientTheme.ORANGE if index == task["step"] else Color.WHITE
	_block_label.text = CyclePlan.block_text(task, shown, _defs["modules"])
	_block_label.visible = not _block_label.text.is_empty()


func _add_label(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _add_heading(parent: Control, text: String) -> void:
	var heading := _add_label(parent)
	heading.text = text
	heading.modulate = ClientTheme.MID_GREY.lightened(0.35)


func _add_box(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	parent.add_child(box)
	return box


func _add_button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button


func _clear(box: Control) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
