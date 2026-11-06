class_name ResearchScreen extends PanelContainer
## Research (C12): science points, theories with their evidence and lab cost,
## designs and their state, and a variant designer. Proving a theory, making a
## prototype and bench-testing it are jobs, run from Jobs (J) at a Lab or the
## Fabricator; this screen says what each needs. R opens it.

const WIDTH_PX := 430
const LIST_HEIGHT_PX := 520

signal closed

var bridge: SimBridge
var base := ""
var chosen: Array[String] = []
var _defs: Dictionary = {}
var _key := ""
var _title: Label
var _points: Label
var _body: VBoxContainer
var _base_picker: OptionButton
var _ideas_box: VBoxContainer
var _preview: Label
var _design_button: Button
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
	_title = _add_label(header, "Research")
	_title.modulate = ClientTheme.ORANGE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle)
	header.add_child(close)
	_points = _add_label(column, "")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT_PX)
	column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)


func bind(new_bridge: SimBridge) -> void:
	bridge = new_bridge
	_defs = bridge.defs()
	bridge.defs_changed.connect(func() -> void:
		_defs = bridge.defs()
		_key = "")
	bridge.view_updated.connect(refresh)


func toggle() -> void:
	visible = not visible
	if visible:
		_key = ""
		refresh()
	else:
		closed.emit()


## Rebuilt only when science, research or the defs change, so a running game
## doesn't churn the controls every tick.
func refresh() -> void:
	if not visible or bridge == null:
		return
	var view: Dictionary = bridge.current_view
	var science: Dictionary = view.get("science", {})
	_points.text = "Science: %d points (earned %d, spent %d)" % [
		int(science.get("points", 0)), int(science.get("earned", 0)), int(science.get("spent", 0))]
	var key := "%s|%s|%d|%s|%s" % [str(science), str(view.get("research", {})), _defs["modules"].size(), base, str(chosen)]
	if key == _key:
		return
	_key = key
	_rebuild(view)


func _rebuild(view: Dictionary) -> void:
	for child: Node in _body.get_children():
		child.free()
	_heading("Theories")
	var theories: Dictionary = _defs.get("theories", {})
	var ids: Array = theories.keys()
	ids.sort()
	if ids.is_empty():
		_add_label(_body, "No theories in this game.")
	for id: String in ids:
		var theory: Dictionary = theories[id]
		var status := ResearchLogic.theory_status(theory, view, _defs)
		var name_line := _add_label(_body, "%s: %s" % [theory["name"], status])
		name_line.modulate = ClientTheme.GOLD if status == "Ready to prove" else Color.WHITE
		_add_detail("Evidence: %s" % ResearchLogic.evidence_text(theory, view))
		if status != "Proven":
			_add_detail("%s. Run it at a Lab in Jobs (J)." % ResearchLogic.test_cost(theory, _defs))
	_heading("Designs")
	for design: String in ResearchLogic.designs(view, _defs):
		_add_label(_body, IndustryLogic.name_of(design, _defs))
		_add_detail(ResearchLogic.next_step(design, view, _defs))
	_build_designer(view)


func _build_designer(view: Dictionary) -> void:
	_heading("Variant designer")
	var bases := ResearchLogic.variant_bases(view, _defs)
	if bases.is_empty():
		_add_detail("No qualified part has ideas to try yet.")
		return
	if not bases.has(base):
		base = bases[0]
		chosen.clear()
	_base_picker = OptionButton.new()
	_base_picker.focus_mode = Control.FOCUS_NONE
	for index in range(bases.size()):
		_base_picker.add_item(IndustryLogic.name_of(bases[index], _defs), index)
		if bases[index] == base:
			_base_picker.select(index)
	_base_picker.item_selected.connect(func(index: int) -> void: choose_base(bases[index]))
	_body.add_child(_base_picker)
	_ideas_box = VBoxContainer.new()
	_body.add_child(_ideas_box)
	for idea: Dictionary in ResearchLogic.visible_ideas(base, view, _defs):
		var box := CheckBox.new()
		box.focus_mode = Control.FOCUS_NONE
		box.text = "%s (complexity %+d, %d points)" % [idea["name"], int(idea.get("complexity", 0)), int(idea.get("points", 0))]
		box.button_pressed = chosen.has(idea["id"])
		box.disabled = idea["locked"]
		if idea["locked"]:
			box.tooltip_text = "Prove %s first" % _defs["theories"].get(idea["theory"], {}).get("name", idea["theory"])
		var id: String = idea["id"]
		box.toggled.connect(func(on: bool) -> void: toggle_idea(id, on))
		_ideas_box.add_child(box)
	_preview = _add_detail("")
	_design_button = Button.new()
	_design_button.text = "Design variant"
	_design_button.focus_mode = Control.FOCUS_NONE
	_design_button.pressed.connect(design)
	_body.add_child(_design_button)
	_message = _add_detail("")
	_message.modulate = ClientTheme.GOLD
	_show_preview()


func choose_base(new_base: String) -> void:
	base = new_base
	chosen.clear()
	_key = ""
	refresh()


func toggle_idea(idea: String, on: bool) -> void:
	if on and not chosen.has(idea):
		chosen.append(idea)
	elif not on:
		chosen.erase(idea)
	_show_preview()


## The preview, and whether the Sim would take it, before anything is sent.
func _show_preview() -> void:
	if _preview == null:
		return
	if chosen.is_empty():
		_preview.text = "Pick up to %d ideas." % ResearchLogic.MAX_IDEAS
		_design_button.disabled = true
		_message.text = ""
		return
	var shown := ResearchLogic.preview(base, chosen, _defs)
	var lines: PackedStringArray = []
	for change: Dictionary in shown["changes"]:
		lines.append(ResearchLogic.change_text(change))
	lines.append("Complexity %d: the part costs about %s× the inputs and work. Its prototype takes %d points." % [
		shown["complexity"], String.num(shown["cost_scale"], 2), shown["points"]])
	_preview.text = "\n".join(lines)
	var check := bridge.check(ResearchLogic.design_command(base, chosen))
	_design_button.disabled = not check["ok"]
	_message.text = "" if check["ok"] else OrderText.reason(check["reason"], check.get("detail", {}))


func design() -> void:
	if chosen.is_empty():
		return
	bridge.submit(ResearchLogic.design_command(base, chosen))
	chosen.clear()


func _heading(text: String) -> void:
	var label := _add_label(_body, text)
	label.modulate = ClientTheme.ORANGE.lightened(0.2)


func _add_detail(text: String) -> Label:
	var label := _add_label(_body, text)
	label.modulate = ClientTheme.MID_GREY.lightened(0.35)
	return label


func _add_label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
