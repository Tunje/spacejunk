class_name IndustryScreen extends PanelContainer
## Refinery and fabricator controls. Shows each facility's active job, its queue
## and its recipes. Start stays enabled without stock, because a job may wait for
## ore on its way; on a busy facility it becomes Queue.

const WIDTH_PX := 400
const RECIPES_HEIGHT_PX := 250
const MAX_COUNT := 99
const QUEUE_ROW_PX := 38
const QUEUE_ROWS_SHOWN := 4

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
var _back_button: Button
var _queue_heading: Label
var _queue_scroll: ScrollContainer
var _queue_box: VBoxContainer
var _queue_key := ""
var _queue_rows: Array[Dictionary] = []
var _count: SpinBox
var _recipe_box: VBoxContainer
var _message: Label
## C15's "Build into…" picker: the recipe being placed, and its slot buttons.
var picking: Dictionary = {}
var _picker: VBoxContainer
var _picker_scroll: ScrollContainer
var _recipe_scroll: ScrollContainer
var _slot_buttons: Array[Dictionary] = []


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
	var job_buttons := HBoxContainer.new()
	column.add_child(job_buttons)
	_cancel_button = _add_button(job_buttons, "Cancel job")
	_cancel_button.pressed.connect(cancel)
	_back_button = _add_button(job_buttons, "Move back")
	_back_button.tooltip_text = "Let the next queued job go first"
	_back_button.pressed.connect(move_active_back)
	_queue_heading = _add_label(column)
	_queue_heading.modulate = ClientTheme.MID_GREY.lightened(0.35)
	_queue_scroll = ScrollContainer.new()
	_queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_queue_scroll)
	_queue_box = VBoxContainer.new()
	_queue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_scroll.add_child(_queue_box)
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
	_recipe_scroll = ScrollContainer.new()
	_recipe_scroll.custom_minimum_size = Vector2(0, RECIPES_HEIGHT_PX)
	_recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_recipe_scroll)
	_recipe_box = VBoxContainer.new()
	_recipe_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_box.add_theme_constant_override("separation", 8)
	_recipe_scroll.add_child(_recipe_box)
	# The picker takes the recipes' place while open, so the screen keeps its size.
	_picker_scroll = ScrollContainer.new()
	_picker_scroll.custom_minimum_size = Vector2(0, RECIPES_HEIGHT_PX)
	_picker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_picker_scroll.visible = false
	column.add_child(_picker_scroll)
	_picker = VBoxContainer.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_scroll.add_child(_picker)
	_message = _add_label(column)
	_message.modulate = ClientTheme.ORANGE


func bind(new_bridge: SimBridge, view: LocalView) -> void:
	bridge = new_bridge
	local_view = view
	_defs = bridge.defs()
	bridge.defs_changed.connect(_reread_defs)
	bridge.view_updated.connect(refresh)
	local_view.selection_changed.connect(refresh)


func toggle() -> void:
	visible = not visible
	if visible:
		facility = {}
		refresh()
	else:
		closed.emit()


## Always queue_job, which also starts an idle facility, so two quick presses in
## one tick both count. A Sim from before C9 does not know it, so it gets start_job.
func start(recipe: Dictionary) -> void:
	var command := IndustryLogic.start_command(unit_id, facility["part"], recipe, int(_count.value), false)
	if bridge.check(command)["reason"] in ["unknown_command", "not_in_stub"]:
		command = IndustryLogic.start_command(unit_id, facility["part"], recipe, int(_count.value), true)
	_send(command)


## C15: lists every free connector on this unit and each unit docked to it, each
## checked by the Sim, so a spot that can't take the part is greyed with its reason.
func open_picker(recipe: Dictionary) -> void:
	picking = recipe
	_clear(_picker)
	_slot_buttons.clear()
	var view: Dictionary = bridge.current_view
	var modules: Dictionary = _defs["modules"]
	var heading := _add_label(_picker)
	heading.text = "Build %s into:" % IndustryLogic.name_of(IndustryLogic.module_output(recipe, _defs), _defs)
	heading.modulate = ClientTheme.ORANGE.lightened(0.2)
	for target: int in IndustryLogic.install_units(view, unit_id):
		var unit: Dictionary = view["units"][target]
		var names: Dictionary = {}
		for part: Dictionary in InspectText.flatten(unit["parts"]):
			names[part["id"]] = modules[part["def"]]["name"]
		var slots := FittingLogic.free_slots(unit, modules)
		if slots.is_empty():
			continue
		_add_label(_picker).text = unit["name"]
		for slot: Dictionary in slots:
			var command := IndustryLogic.start_command(unit_id, facility["part"], recipe, 1, false,
				IndustryLogic.install_to(target, slot))
			var check := bridge.check(command)
			var button := _add_button(_picker, "%s: %s (%s, %s)" % [names[slot["part"]], slot["connector"], slot["type"], slot["size"]])
			button.disabled = not check["ok"]
			button.tooltip_text = "" if check["ok"] else OrderText.reason(check["reason"], check.get("detail", {}))
			button.pressed.connect(_send_and_close.bind(command))
			_slot_buttons.append({ "slot": slot, "unit": target, "button": button, "command": command })
	var close_button := _add_button(_picker, "Cancel")
	close_button.pressed.connect(close_picker)
	_picker.move_child(close_button, 1)
	_picker.visible = true
	_picker_scroll.visible = true
	_recipe_scroll.visible = false


func close_picker() -> void:
	picking = {}
	_picker.visible = false
	_picker_scroll.visible = false
	_recipe_scroll.visible = true


func _send_and_close(command: Dictionary) -> void:
	_send(command)
	close_picker()


func cancel() -> void:
	var job := IndustryLogic.job_on(bridge.current_view, facility.get("part", 0))
	if not job.is_empty():
		bridge.submit(IndustryLogic.cancel_command(unit_id, job["id"]))


## Moves a job to a 1-based place among the queued jobs.
func move(job_id: int, position: int) -> void:
	_send(IndustryLogic.move_command(unit_id, job_id, position))


## Ends a queued job at once; nothing of it has been taken from stock yet.
func remove(job_id: int) -> void:
	_send(IndustryLogic.cancel_command(unit_id, job_id))


## A waiting active job, such as one short of ore, lets the next one go first.
func move_active_back() -> void:
	var job := IndustryLogic.job_on(bridge.current_view, facility.get("part", 0))
	if not job.is_empty():
		move(job["id"], 1)


func _send(command: Dictionary) -> void:
	var result: Dictionary = bridge.check(command)
	_message.text = "" if result["ok"] else OrderText.reason(result["reason"], result["detail"])
	if result["ok"]:
		bridge.submit(command)


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
	_show_queue(view)
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


## A designed variant brings its recipes, so the recipe list is built again.
func _reread_defs() -> void:
	_defs = bridge.defs()
	_recipe_key = ""


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
		if IndustryLogic.module_output(recipe, _defs) != "":
			var into := Button.new()
			into.text = "Build into…"
			into.focus_mode = Control.FOCUS_NONE
			into.tooltip_text = "Build it straight onto a free connector here or on a docked craft"
			into.pressed.connect(open_picker.bind(recipe))
			title.add_child(into)
		var inputs := _add_label(row)
		var outputs := _add_label(row)
		outputs.text = "Makes %s in %s" % [
			IndustryLogic.outputs_line(recipe, _defs),
			OrderText.duration(IndustryLogic.run_ticks(recipe["work"], facility["rate"]) / bridge.ticks_per_second()),
		]
		outputs.modulate = ClientTheme.MID_GREY.lightened(0.3)
		_recipe_box.add_child(row)
		_rows.append({ "recipe": recipe, "inputs": inputs, "start": button })


func _show_job(view: Dictionary) -> void:
	var job := IndustryLogic.job_on(view, facility["part"])
	_cancel_button.disabled = job.is_empty() or job["status"] == "cancelling"
	var queued := IndustryLogic.queue_on(view, facility["part"]).size() - (0 if job.is_empty() else 1)
	_back_button.disabled = job.is_empty() or queued == 0 or not IndustryLogic.can_move(job)
	for row: Dictionary in _rows:
		(row["start"] as Button).text = "Start" if job.is_empty() and queued == 0 else "Queue"
	_job_bar.value = 0.0 if job.is_empty() else IndustryLogic.job_progress(job)
	_job_label.text = "Idle" if job.is_empty() else IndustryLogic.job_line(job, _defs, bridge.ticks_per_second(), bridge.current_view["units"])
	_job_label.modulate = ClientTheme.GOLD if not job.is_empty() and not job["reason"].is_empty() else Color.WHITE


## Queued jobs below the active one, each with Up, Down and Remove.
func _show_queue(view: Dictionary) -> void:
	var jobs := IndustryLogic.queue_on(view, facility["part"])
	var queued: Array[Dictionary] = []
	for job: Dictionary in jobs:
		if job.get("queue_pos", 0) > 0:
			queued.append(job)
	_queue_heading.text = "Queue: %d of %d" % [jobs.size(), IndustryLogic.QUEUE_LIMIT] if not jobs.is_empty() else "Queue empty"
	var key := str(queued.map(func(job: Dictionary) -> int: return job["id"]))
	if key != _queue_key:
		_queue_key = key
		_build_queue_rows(queued)
	for index in range(queued.size()):
		var row: Dictionary = _queue_rows[index]
		var label: Label = row["label"]
		label.text = "%d. %s" % [index + 1, IndustryLogic.queue_line(queued[index], _defs, bridge.ticks_per_second())]
		label.tooltip_text = label.text
		(row["up"] as Button).disabled = index == 0
		(row["down"] as Button).disabled = index == queued.size() - 1
	_queue_scroll.custom_minimum_size = Vector2(0, mini(queued.size(), QUEUE_ROWS_SHOWN) * QUEUE_ROW_PX)
	_queue_scroll.visible = not queued.is_empty()


func _build_queue_rows(queued: Array[Dictionary]) -> void:
	_clear(_queue_box)
	_queue_rows.clear()
	for index in range(queued.size()):
		var job_id: int = queued[index]["id"]
		var row := HBoxContainer.new()
		_queue_box.add_child(row)
		var label := _add_label(row)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# One line a row: a long name trims, and the whole line is in the tooltip.
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		var up := _add_button(row, "Up")
		up.pressed.connect(func() -> void: move(job_id, index))
		var down := _add_button(row, "Down")
		down.pressed.connect(func() -> void: move(job_id, index + 2))
		var remove_button := _add_button(row, "Remove")
		remove_button.pressed.connect(remove.bind(job_id))
		_queue_rows.append({ "job": job_id, "label": label, "up": up, "down": down, "remove": remove_button })


func _show_stock(stock: Dictionary) -> void:
	for row: Dictionary in _rows:
		var label: Label = row["inputs"]
		label.text = IndustryLogic.inputs_line(row["recipe"], stock, _defs, int(bridge.current_view.get("science", {}).get("points", -1)))
		label.modulate = Color.WHITE if IndustryLogic.has_inputs(row["recipe"], stock) else ClientTheme.GOLD


func _add_label(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


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
