class_name FittingScreen extends PanelContainer
## Fit parts to the commanded craft on its 3D hull: pick a part, pick a connector
## on the craft, read what the fit would do, then attach. Every verdict is from
## Sim.check, and limits come from the view's `fit`.

const WIDTH_PX := 340
const SLOT_RADIUS_PX := 8.0
const OVER_RATIO := 1.0

signal closed

var bridge: SimBridge
var local_view: LocalView
var markers: FittingMarkers
var chosen: Dictionary = {}
var slot: Dictionary = {}
var _modules: Dictionary = {}
var _stock: Array[Dictionary] = []
var _stock_key := ""

var _title: Label
var _mass_label: Label
var _mass_bar: ProgressBar
var _power_label: Label
var _power_bar: ProgressBar
var _heat_label: Label
var _heat_bar: ProgressBar
var _stock_box: VBoxContainer
var _verdict: Label
var _attach_button: Button
var _remove_button: Button


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
	_mass_label = _add_label(column)
	_mass_bar = _add_bar(column)
	_power_label = _add_label(column)
	_power_bar = _add_bar(column)
	_heat_label = _add_label(column)
	_heat_bar = _add_bar(column)
	column.add_child(HSeparator.new())
	var heading := _add_label(column)
	heading.text = "Parts available"
	heading.modulate = ClientTheme.MID_GREY.lightened(0.35)
	_stock_box = VBoxContainer.new()
	_stock_box.add_theme_constant_override("separation", 4)
	column.add_child(_stock_box)
	_verdict = _add_label(column)
	_attach_button = _add_button(column, "Attach")
	_attach_button.pressed.connect(attach)
	_remove_button = _add_button(column, "Remove selected part")
	_remove_button.pressed.connect(remove_selected)


func bind(new_bridge: SimBridge, view: LocalView, new_markers: FittingMarkers) -> void:
	bridge = new_bridge
	local_view = view
	markers = new_markers
	markers.screen = self
	_modules = bridge.defs()["modules"]
	bridge.view_updated.connect(refresh)
	local_view.selection_changed.connect(refresh)


func toggle() -> void:
	visible = not visible
	markers.visible = visible
	chosen = {}
	slot = {}
	if visible:
		local_view.focus_on("unit", local_view.commanded_unit)
		refresh()
	else:
		closed.emit()


func unit() -> Dictionary:
	return bridge.current_view["units"].get(local_view.commanded_unit, {})


func choose(entry: Dictionary) -> void:
	chosen = entry
	refresh()


func choose_slot(new_slot: Dictionary) -> void:
	slot = new_slot
	refresh()


func pending_command() -> Dictionary:
	if chosen.is_empty() or slot.is_empty():
		return {}
	return FittingLogic.attach_command(local_view.commanded_unit, chosen, slot)


## Whether a slot would take the chosen part, for the markers.
func slot_ok(candidate: Dictionary) -> bool:
	if chosen.is_empty():
		return true
	return bridge.check(FittingLogic.attach_command(local_view.commanded_unit, chosen, candidate))["ok"]


func attach() -> void:
	var command := pending_command()
	if command.is_empty():
		return
	bridge.submit(command)
	chosen = {}
	slot = {}
	refresh()


func remove_selected() -> void:
	var command := _remove_command()
	if not command.is_empty():
		bridge.submit(command)
		refresh()


func refresh() -> void:
	if not visible or unit().is_empty():
		return
	var shown := unit()
	_title.text = "Fitting: %s" % shown["name"]
	var result := _check_pending()
	_show_limits(shown["fit"], result.get("detail", {}))
	_sync_stock()
	_show_verdict(result)
	_attach_button.disabled = not result.get("ok", false)
	var remove := _remove_command()
	_remove_button.disabled = remove.is_empty() or not bridge.check(remove)["ok"]


func _check_pending() -> Dictionary:
	var command := pending_command()
	return {} if command.is_empty() else bridge.check(command)


func _remove_command() -> Dictionary:
	var part: int = local_view.selected_part
	if local_view.selected_kind != "unit" or local_view.selected_id != local_view.commanded_unit or part == 0:
		return {}
	var view: Dictionary = bridge.current_view
	return FittingLogic.detach_command(local_view.commanded_unit, part, FittingLogic.detach_target(view, local_view.commanded_unit))


func _show_limits(fit: Dictionary, projected: Dictionary) -> void:
	var has_projection := projected.has("mass_g")
	var mass_after: String = OrderText.tonnes(projected["mass_g"]) if has_projection else ""
	var power_after: String = InspectText.watts(projected["power_rated_w"]) if has_projection else ""
	var heat_after: String = InspectText.watts(projected["heat_rated_w"]) if has_projection else ""
	var shown: Dictionary = projected if has_projection else fit
	_mass_label.text = FittingLogic.limit_line("Mass", OrderText.tonnes(fit["mass_g"]), OrderText.tonnes(fit["mass_limit_g"]), mass_after)
	_set_bar(_mass_bar, shown["mass_g"], fit["mass_limit_g"])
	_power_label.text = FittingLogic.limit_line("Power", InspectText.watts(fit["power_rated_w"]), InspectText.watts(shown["power_budget_w"]), power_after)
	_set_bar(_power_bar, shown["power_rated_w"], shown["power_budget_w"])
	_heat_label.text = FittingLogic.limit_line("Heat", InspectText.watts(fit["heat_rated_w"]), InspectText.watts(shown["heat_budget_w"]), heat_after)
	_set_bar(_heat_bar, shown["heat_rated_w"], shown["heat_budget_w"])


func _set_bar(bar: ProgressBar, value: int, limit: int) -> void:
	bar.value = InspectText.ratio(value, limit)
	bar.modulate = ClientTheme.ORANGE if limit > 0 and value > limit else Color.WHITE


func _sync_stock() -> void:
	_stock = FittingLogic.stock(bridge.current_view, local_view.commanded_unit, _modules)
	var key := str(_stock.map(func(entry: Dictionary) -> String: return "%s:%d:%d" % [entry["item"], entry["from"], entry["count"]]))
	if key == _stock_key:
		return
	_stock_key = key
	for child: Node in _stock_box.get_children():
		_stock_box.remove_child(child)
		child.queue_free()
	if _stock.is_empty():
		var none := _add_label(_stock_box)
		none.text = "No parts in stock here"
		none.modulate = ClientTheme.MID_GREY.lightened(0.2)
	for entry: Dictionary in _stock:
		var button := _add_button(_stock_box, "%s x%d (%s)" % [entry["name"], entry["count"], entry["source"]])
		button.pressed.connect(choose.bind(entry))


func _show_verdict(result: Dictionary) -> void:
	if chosen.is_empty():
		_verdict.text = "Choose a part, then a connector on the craft."
		_verdict.modulate = ClientTheme.MID_GREY.lightened(0.35)
	elif slot.is_empty():
		_verdict.text = "%s: choose a connector." % chosen["name"]
		_verdict.modulate = ClientTheme.MID_GREY.lightened(0.35)
	elif result["ok"]:
		_verdict.text = "%s fits here." % chosen["name"]
		_verdict.modulate = ClientTheme.OFF_WHITE
	else:
		_verdict.text = OrderText.reason(result["reason"], result["detail"])
		_verdict.modulate = ClientTheme.ORANGE


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


func _add_button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(button)
	return button
