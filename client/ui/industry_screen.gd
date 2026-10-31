class_name IndustryScreen extends PanelContainer
## Refinery and fabricator controls. Shows each facility's job and its recipes.
## Start stays enabled without stock, because a job may wait for ore on its way.

const WIDTH_PX := 400
const RECIPES_HEIGHT_PX := 500
const MAX_COUNT := 99

signal closed

var bridge: SimBridge
var local_view: LocalView
var unit_id := 0
var facility: Dictionary = {}
var _defs: Dictionary = {}
var _rows: Array[Dictionary] = []
var _tab_key := ""
var _recipe_key := ""
var _title: Label
var _tabs: HBoxContainer
var _job_label: Label
var _job_bar: ProgressBar
var _cancel_button: Button
var _count: SpinBox
var _recipe_box: VBoxContainer
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
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle)
	header.add_child(close)
	_tabs = HBoxContainer.new()
	column.add_child(_tabs)
	_job_label = _add_label(column)
	_job_bar = ProgressBar.new()
	_job_bar.show_percentage = false
	_job_bar.max_value = 1.0
	_job_bar.step = 0.001
	_job_bar.custom_minimum_size = Vector2(0, 8)
	column.add_child(_job_bar)
	_cancel_button = Button.new()
	_cancel_button.text = "Cancel job"
	_cancel_button.focus_mode = Control.FOCUS_NONE
	_cancel_button.pressed.connect(cancel)
	column.add_child(_cancel_button)
	column.add_child(HSeparator.new())
	var count_row := HBoxContainer.new()
	column.add_child(count_row)
	var count_label := _add_label(count_row)
	count_label.text = "Runs"
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count = SpinBox.new()
	_count.min_value = 1
	_count.max_value = MAX_COUNT
	_count.value = 1
	count_row.add_child(_count)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, RECIPES_HEIGHT_PX)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_recipe_box = VBoxContainer.new()
	_recipe_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_recipe_box)
	_message = _add_label(column)
	_message.modulate = ClientTheme.ORANGE


func bind(new_bridge: SimBridge, view: LocalView) -> void:
	bridge = new_bridge
	local_view = view
	_defs = bridge.defs()
	bridge.view_updated.connect(refresh)
	local_view.selection_changed.connect(refresh)


func toggle() -> void:
	visible = not visible
	if visible:
		facility = {}
		refresh()
	else:
		closed.emit()


func start(recipe: Dictionary) -> void:
	var command := IndustryLogic.start_command(unit_id, facility["part"], recipe, int(_count.value))
	var result: Dictionary = bridge.check(command)
	_message.text = "" if result["ok"] else OrderText.reason(result["reason"], result["detail"])
	if result["ok"]:
		bridge.submit(command)


func cancel() -> void:
	var job := IndustryLogic.job_on(bridge.current_view, facility.get("part", 0))
	if not job.is_empty():
		bridge.submit(IndustryLogic.cancel_command(unit_id, job["id"]))


func choose_facility(entry: Dictionary) -> void:
	facility = entry
	_message.text = ""
	refresh()


func refresh() -> void:
	if not visible:
		return
	var view: Dictionary = bridge.current_view
	var modules: Dictionary = _defs["modules"]
	unit_id = IndustryLogic.working_unit(view, modules, local_view.selected_kind, local_view.selected_id, local_view.commanded_unit)
	if unit_id == 0:
		_title.text = "No facilities"
		return
	var unit: Dictionary = view["units"][unit_id]
	_title.text = "Industry: %s" % unit["name"]
	var found := IndustryLogic.facilities(unit, modules)
	if not found.has(facility):
		facility = found[0]
	_sync_tabs(found)
	_sync_recipes()
	_show_job(view)
	_show_stock(unit["inventory"])


func _sync_tabs(found: Array[Dictionary]) -> void:
	var key := "%d:%s" % [unit_id, str(found)]
	if key != _tab_key:
		_tab_key = key
		_clear(_tabs)
		for entry: Dictionary in found:
			var tab := Button.new()
			tab.text = entry["name"]
			tab.toggle_mode = true
			tab.focus_mode = Control.FOCUS_NONE
			tab.pressed.connect(choose_facility.bind(entry))
			_tabs.add_child(tab)
	for index in range(found.size()):
		(_tabs.get_child(index) as Button).set_pressed_no_signal(found[index] == facility)


func _sync_recipes() -> void:
	var key: String = "%d:%s" % [facility["part"], facility["type"]]
	if key == _recipe_key:
		return
	_recipe_key = key
	_clear(_recipe_box)
	_rows.clear()
	for recipe: Dictionary in IndustryLogic.recipes_for(facility["type"], _defs["recipes"]):
		var row := VBoxContainer.new()
		var title := HBoxContainer.new()
		row.add_child(title)
		var label := _add_label(title)
		label.text = IndustryLogic.name_of(recipe["id"], _defs)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button := Button.new()
		button.text = "Start"
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(start.bind(recipe))
		title.add_child(button)
		var inputs := _add_label(row)
		var outputs := _add_label(row)
		outputs.text = "Makes %s in %s" % [
			IndustryLogic.outputs_line(recipe, _defs),
			OrderText.duration(float(recipe["ticks"]) / bridge.ticks_per_second()),
		]
		outputs.modulate = ClientTheme.MID_GREY.lightened(0.3)
		_recipe_box.add_child(row)
		_rows.append({ "recipe": recipe, "inputs": inputs, "start": button })


func _show_job(view: Dictionary) -> void:
	var job := IndustryLogic.job_on(view, facility["part"])
	_cancel_button.disabled = job.is_empty() or job["status"] == "cancelling"
	_job_bar.value = 0.0 if job.is_empty() else IndustryLogic.job_progress(job, view["tick"])
	_job_label.text = "Idle" if job.is_empty() else IndustryLogic.job_line(job, _defs)
	_job_label.modulate = ClientTheme.GOLD if not job.is_empty() and not job["reason"].is_empty() else Color.WHITE


func _show_stock(stock: Dictionary) -> void:
	for row: Dictionary in _rows:
		var label: Label = row["inputs"]
		label.text = IndustryLogic.inputs_line(row["recipe"], stock, _defs)
		label.modulate = Color.WHITE if IndustryLogic.has_inputs(row["recipe"], stock) else ClientTheme.GOLD


func _add_label(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _clear(box: Control) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
