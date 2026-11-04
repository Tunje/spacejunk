class_name OrderPanel extends PanelContainer
## Shows the commanded craft and the selection, with the orders available.
## Buttons are kept across ticks so a click is never lost to a rebuild.

const WIDTH_PX := 300

signal order_issued(command: Dictionary)

var bridge: SimBridge
var local_view: LocalView
var _modules: Dictionary = {}
var _items: Dictionary = {}
var _orders: Array[Dictionary] = []
var _buttons: Dictionary = {}
## An atomic order just pressed, shown as started until the next tick runs it.
var _clicked_key := ""
var _clicked_tick := 0

var _commanded_label: Label
var _status_label: Label
var _selection_label: Label
var _detail_label: Label
var _button_box: VBoxContainer
var _why_label: Label


func _ready() -> void:
	theme = ClientTheme.build()
	custom_minimum_size = Vector2(WIDTH_PX, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	_commanded_label = _add_label(column)
	_commanded_label.modulate = ClientTheme.ORANGE
	_status_label = _add_label(column)
	column.add_child(HSeparator.new())
	_selection_label = _add_label(column)
	_detail_label = _add_label(column)
	_detail_label.modulate = ClientTheme.MID_GREY.lightened(0.3)
	_button_box = VBoxContainer.new()
	_button_box.add_theme_constant_override("separation", 4)
	column.add_child(_button_box)
	_why_label = _add_label(column)
	_why_label.modulate = ClientTheme.GOLD


func bind(new_bridge: SimBridge, view: LocalView) -> void:
	bridge = new_bridge
	local_view = view
	var defs: Dictionary = bridge.defs()
	_modules = defs["modules"]
	_items = defs["items"]
	bridge.view_updated.connect(refresh)
	local_view.selection_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var view: Dictionary = bridge.current_view
	var commanded: int = local_view.commanded_unit
	var unit: Dictionary = view["units"].get(commanded, {})
	if view["tick"] != _clicked_tick:
		_clicked_key = ""
	_commanded_label.text = "Orders: %s" % unit.get("name", "no craft")
	_status_label.text = _status_of(unit)
	_selection_label.text = _selection_title(view)
	_detail_label.text = _selection_detail(view)
	_detail_label.visible = not _detail_label.text.is_empty()
	_orders = OrderList.build(view, _modules, _items, commanded, local_view.selected_kind, local_view.selected_id)
	_sync_buttons()


func press(key: String) -> bool:
	if not _buttons.has(key) or _buttons[key].disabled:
		return false
	_issue(key)
	return true


func button_for(key: String) -> Button:
	return _buttons.get(key)


func _sync_buttons() -> void:
	var wanted: Array = _orders.map(func(order: Dictionary) -> String: return order["key"])
	for key: String in _buttons.keys():
		if not wanted.has(key):
			_buttons[key].queue_free()
			_buttons.erase(key)
	var why := ""
	for index in range(_orders.size()):
		var order: Dictionary = _orders[index]
		var key: String = order["key"]
		if not _buttons.has(key):
			var button := Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.pressed.connect(_issue.bind(key))
			_button_box.add_child(button)
			_buttons[key] = button
		var shown: Button = _buttons[key]
		var progress := _progress_text(order)
		_show_running(shown, not progress.is_empty())
		_button_box.move_child(shown, index)
		if not progress.is_empty():
			shown.text = progress
			shown.disabled = true
			shown.tooltip_text = ""
			continue
		var check: Dictionary = bridge.check(order["command"])
		shown.text = order["label"]
		shown.disabled = not check["ok"]
		shown.tooltip_text = "" if check["ok"] else _refusal_text(check)
		if why.is_empty() and not check["ok"]:
			why = shown.tooltip_text
	_why_label.text = why
	_why_label.visible = not why.is_empty()


func _refusal_text(check: Dictionary) -> String:
	if check["reason"] == "busy_docking":
		return OrderText.busy(bridge.current_view["units"][local_view.commanded_unit]["op"]["type"])
	return OrderText.reason(check["reason"], check["detail"])


## What an atomic order's button reads while it runs, or "" for any other order.
func _progress_text(order: Dictionary) -> String:
	var op_type: String = OrderList.ATOMIC_OPS.get(order["command"]["type"], "")
	if op_type.is_empty():
		return ""
	var unit: Dictionary = bridge.current_view["units"][local_view.commanded_unit]
	if unit["op"]["type"] == op_type:
		return _op_text(unit)
	return "%s 0%%" % OrderText.operation(op_type) if order["key"] == _clicked_key else ""


## A refused button is grey, so one that is running has to look different.
func _show_running(button: Button, running: bool) -> void:
	if running:
		button.add_theme_stylebox_override("disabled", ClientTheme.running_button())
		button.add_theme_color_override("font_disabled_color", ClientTheme.ORANGE)
	else:
		button.remove_theme_stylebox_override("disabled")
		button.remove_theme_color_override("font_disabled_color")


func _issue(key: String) -> void:
	for order: Dictionary in _orders:
		if order["key"] == key:
			bridge.submit(order["command"])
			order_issued.emit(order["command"])
			if OrderList.ATOMIC_OPS.has(order["command"]["type"]):
				_clicked_key = key
				_clicked_tick = bridge.current_view["tick"]
				refresh()
			return


func _add_label(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _status_of(unit: Dictionary) -> String:
	if unit.is_empty():
		return ""
	var text := _op_text(unit)
	if not unit["dock"].is_empty():
		text += ", docked"
	return text


func _op_text(unit: Dictionary) -> String:
	return InspectText.op_line(unit, bridge.current_view["tick"], bridge.ticks_per_second())


func _selection_title(view: Dictionary) -> String:
	match local_view.selected_kind:
		"unit":
			var unit: Dictionary = view["units"].get(local_view.selected_id, {})
			if local_view.selected_part != 0:
				var part := _find_part(unit.get("parts", {}), local_view.selected_part)
				if not part.is_empty():
					return "%s: %s" % [unit["name"], _modules[part["def"]]["name"]]
			return unit.get("name", "")
		"body":
			return view["bodies"].get(local_view.selected_id, {}).get("name", "")
	return "Nothing selected"


func _selection_detail(view: Dictionary) -> String:
	if local_view.selected_kind == "body" and view["bodies"].has(local_view.selected_id):
		var body: Dictionary = view["bodies"][local_view.selected_id]
		if body["kind"] == "asteroid":
			return "Scanned" if body["scanned"] else "Not scanned"
	return ""


func _find_part(part: Dictionary, part_id: int) -> Dictionary:
	if part.is_empty() or part["id"] == part_id:
		return part
	for child: Dictionary in part["children"]:
		var found := _find_part(child, part_id)
		if not found.is_empty():
			return found
	return {}
