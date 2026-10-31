class_name InspectionPanel extends PanelContainer
## Shows the selected craft's status, cargo, power, heat and parts, or the
## commanded craft when nothing is selected. Every figure comes from the view.

const WIDTH_PX := 330
const PARTS_HEIGHT_PX := 170
const FULL_RATIO := 0.85
const CLASS_NAMES: Dictionary = { "ore": "Ore", "goods": "Goods", "propellant": "Propellant" }

var bridge: SimBridge
var local_view: LocalView
var _modules: Dictionary = {}
var _items: Dictionary = {}
var _signature := ""
var _cargo_rows: Dictionary = {}

var _title: Label
var _status: Label
var _core: Label
var _cargo_box: VBoxContainer
var _items_label: Label
var _power_bar: ProgressBar
var _power_label: Label
var _battery_bar: ProgressBar
var _battery_label: Label
var _heat_bar: ProgressBar
var _heat_label: Label
var _parts_box: VBoxContainer


func _ready() -> void:
	theme = ClientTheme.build()
	custom_minimum_size = Vector2(WIDTH_PX, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	_title = _add_label(column)
	_title.modulate = ClientTheme.ORANGE
	_status = _add_label(column)
	_core = _add_label(column)
	_core.modulate = ClientTheme.MID_GREY.lightened(0.3)
	column.add_child(HSeparator.new())
	_cargo_box = VBoxContainer.new()
	_cargo_box.add_theme_constant_override("separation", 3)
	column.add_child(_cargo_box)
	_items_label = _add_label(column)
	_items_label.modulate = ClientTheme.MID_GREY.lightened(0.3)
	_power_label = _add_label(column)
	_power_bar = _add_bar(column)
	_battery_label = _add_label(column)
	_battery_bar = _add_bar(column)
	_heat_label = _add_label(column)
	_heat_bar = _add_bar(column)
	column.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, PARTS_HEIGHT_PX)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_parts_box = VBoxContainer.new()
	_parts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_parts_box)


func bind(new_bridge: SimBridge, view: LocalView) -> void:
	bridge = new_bridge
	local_view = view
	var defs: Dictionary = bridge.defs()
	_modules = defs["modules"]
	_items = defs["items"]
	bridge.view_updated.connect(refresh)
	local_view.selection_changed.connect(refresh)
	refresh()


func shown_unit() -> int:
	if local_view.selected_kind == "unit":
		return local_view.selected_id
	return local_view.commanded_unit


func refresh() -> void:
	var view: Dictionary = bridge.current_view
	var unit: Dictionary = view["units"].get(shown_unit(), {})
	visible = not unit.is_empty()
	if unit.is_empty():
		return
	_title.text = unit["name"]
	_status.text = InspectText.status(unit, view)
	_core.text = InspectText.core(unit)
	_refresh_cargo(unit)
	_refresh_power(unit)
	_refresh_heat(unit)
	_refresh_parts(unit)


func _refresh_cargo(unit: Dictionary) -> void:
	var classes: Array = unit["cargo"].keys()
	classes.sort()
	if classes != _cargo_rows.keys():
		_rebuild_cargo_rows(classes)
	for cargo_class: String in classes:
		var entry: Dictionary = unit["cargo"][cargo_class]
		var row: Dictionary = _cargo_rows[cargo_class]
		row["label"].text = "%s: %s" % [CLASS_NAMES.get(cargo_class, cargo_class.capitalize()), InspectText.cargo_line(entry)]
		_set_bar(row["bar"], InspectText.cargo_ratio(entry))
	_items_label.text = InspectText.inventory(unit["inventory"], _items)
	_items_label.visible = not _items_label.text.is_empty()


func _rebuild_cargo_rows(classes: Array) -> void:
	_clear(_cargo_box)
	_cargo_rows.clear()
	for cargo_class: String in classes:
		_cargo_rows[cargo_class] = { "label": _add_label(_cargo_box), "bar": _add_bar(_cargo_box) }


func _refresh_power(unit: Dictionary) -> void:
	var power: Dictionary = unit["power"]
	_power_label.text = "Power: %s of %s" % [InspectText.watts(power["demand_w"]), InspectText.watts(power["supply_w"])]
	_set_bar(_power_bar, InspectText.ratio(power["demand_w"], power["supply_w"]))
	var has_battery: bool = power["capacity_j"] > 0
	_battery_label.visible = has_battery
	_battery_bar.visible = has_battery
	if has_battery:
		_battery_label.text = "Battery: %s of %s" % [InspectText.joules(power["stored_j"]), InspectText.joules(power["capacity_j"])]
		_battery_bar.value = InspectText.ratio(power["stored_j"], power["capacity_j"])


func _refresh_heat(unit: Dictionary) -> void:
	var heat: Dictionary = unit["heat"]
	_heat_label.text = "Heat: %s of %s, in %s, out %s" % [
		InspectText.joules(heat["stored_j"]), InspectText.joules(heat["limit_j"]),
		InspectText.watts(heat["input_w"]), InspectText.watts(heat["reject_w"]),
	]
	_set_bar(_heat_bar, InspectText.ratio(heat["stored_j"], heat["limit_j"]))


func _refresh_parts(unit: Dictionary) -> void:
	var parts := InspectText.flatten(unit["parts"])
	var signature := str(parts.map(func(part: Dictionary) -> int: return part["id"]))
	if signature != _signature:
		_signature = signature
		_clear(_parts_box)
		for part: Dictionary in parts:
			_add_label(_parts_box)
	for index in range(parts.size()):
		var part: Dictionary = parts[index]
		var label: Label = _parts_box.get_child(index)
		label.text = InspectText.part_line(part, _modules[part["def"]])
		label.modulate = InspectText.part_colour(part)


func part_line_count() -> int:
	return _parts_box.get_child_count()


func _set_bar(bar: ProgressBar, ratio: float) -> void:
	bar.value = ratio
	bar.modulate = ClientTheme.ORANGE if ratio >= FULL_RATIO else Color.WHITE


func _add_label(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _add_bar(parent: Control) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.001
	bar.custom_minimum_size = Vector2(0, 8)
	parent.add_child(bar)
	return bar


func _clear(box: Control) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
