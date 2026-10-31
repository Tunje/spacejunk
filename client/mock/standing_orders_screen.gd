class_name StandingOrdersScreen extends PanelContainer
## Mock policy screen: the player sets rules and permissions rather than orders,
## and reads what the core would do. It sends no commands.

const STATE_COLOURS: Dictionary = {
	"ok": ClientTheme.OFF_WHITE,
	"limited": ClientTheme.GOLD,
	"blocked": ClientTheme.ORANGE,
}
const STATE_MARKS: Dictionary = { "ok": "OK", "limited": "LIMITED", "blocked": "BLOCKED" }

var rules: Array[Dictionary] = StandingOrdersMock.new_rules()
var grants: Array[Dictionary] = StandingOrdersMock.new_grants()

var _rule_box: VBoxContainer
var _grant_box: VBoxContainer
var _projection_box: VBoxContainer


func _ready() -> void:
	theme = ClientTheme.build()
	add_theme_stylebox_override("panel", ClientTheme.solid_panel())
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Standing orders: Mining Core"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.modulate = ClientTheme.ORANGE
	header.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: visible = false)
	header.add_child(close)

	var banner := Label.new()
	banner.text = "Concept mock. These settings do not affect the simulation."
	banner.modulate = ClientTheme.GOLD
	column.add_child(banner)

	var sections := HBoxContainer.new()
	sections.add_theme_constant_override("separation", 26)
	column.add_child(sections)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	left.add_theme_constant_override("separation", 6)
	sections.add_child(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(430, 0)
	right.add_theme_constant_override("separation", 6)
	sections.add_child(right)

	_add_heading(left, "Rules, highest priority first")
	_rule_box = _add_box(left)
	left.add_child(HSeparator.new())
	_add_heading(left, "What the core may do without asking")
	_grant_box = _add_box(left)
	_add_heading(right, "What the core would do")
	_projection_box = _add_box(right)
	refresh()


func toggle() -> void:
	visible = not visible


func move_rule(index: int, offset: int) -> void:
	var target := index + offset
	if target < 0 or target >= rules.size():
		return
	var rule: Dictionary = rules[index]
	rules[index] = rules[target]
	rules[target] = rule
	refresh.call_deferred()


func refresh() -> void:
	_clear(_rule_box)
	_clear(_grant_box)
	_clear(_projection_box)
	for index in range(rules.size()):
		_add_rule_row(index)
	for grant: Dictionary in grants:
		var box := CheckBox.new()
		box.text = grant["text"]
		box.button_pressed = grant["on"]
		box.focus_mode = Control.FOCUS_NONE
		box.toggled.connect(_on_grant_toggled.bind(grant))
		_grant_box.add_child(box)
	_refresh_projection()


func _refresh_projection() -> void:
	_clear(_projection_box)
	for line: Dictionary in StandingOrdersMock.project(rules, grants):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var mark := Label.new()
		mark.text = STATE_MARKS[line["state"]]
		mark.custom_minimum_size = Vector2(76, 0)
		mark.modulate = STATE_COLOURS[line["state"]]
		row.add_child(mark)
		var text := Label.new()
		text.text = line["text"]
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		_projection_box.add_child(row)


func _add_rule_row(index: int) -> void:
	var rule: Dictionary = rules[index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var enabled := CheckBox.new()
	enabled.button_pressed = rule["on"]
	enabled.focus_mode = Control.FOCUS_NONE
	enabled.toggled.connect(_on_rule_toggled.bind(rule))
	row.add_child(enabled)
	var text := Label.new()
	text.text = rule["text"]
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var amount := SpinBox.new()
	amount.max_value = rule["max"]
	amount.step = rule["step"]
	amount.value = rule["value"]
	amount.suffix = rule["unit"]
	amount.custom_minimum_size = Vector2(150, 0)
	amount.value_changed.connect(_on_value_changed.bind(rule))
	row.add_child(amount)
	for offset: int in [-1, 1]:
		var shift := Button.new()
		shift.text = "Up" if offset < 0 else "Down"
		shift.focus_mode = Control.FOCUS_NONE
		shift.disabled = index + offset < 0 or index + offset >= rules.size()
		shift.pressed.connect(move_rule.bind(index, offset))
		row.add_child(shift)
	_rule_box.add_child(row)


func _on_rule_toggled(on: bool, rule: Dictionary) -> void:
	rule["on"] = on
	_refresh_projection()


func _on_grant_toggled(on: bool, grant: Dictionary) -> void:
	grant["on"] = on
	_refresh_projection()


func _on_value_changed(value: float, rule: Dictionary) -> void:
	rule["value"] = roundi(value)
	_refresh_projection()


func _add_heading(parent: Control, text: String) -> void:
	var heading := Label.new()
	heading.text = text
	heading.modulate = ClientTheme.MID_GREY.lightened(0.35)
	parent.add_child(heading)


func _add_box(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	return box


func _clear(box: Control) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
