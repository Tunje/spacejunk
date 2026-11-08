class_name RendezvousPanel extends PanelContainer
## The rendezvous readouts (D46), in their own panel at the top of the view while
## flying with a target: the flight screen beside it keeps the burn controls, and
## the readouts stay in sight of the craft and the markers. It shows what the flight
## screen fetched from Sim.relative; it asks nothing itself.

const WIDTH_PX := 470
const LEFT_PX := 352.0
const TOP_PX := 76.0

var flight: FlightScreen
var _title: Label
var _lines: VBoxContainer


func _ready() -> void:
	theme = ClientTheme.build()
	custom_minimum_size = Vector2(WIDTH_PX, 0)
	position = Vector2(LEFT_PX, TOP_PX)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	_title = Label.new()
	_title.modulate = ClientTheme.ORANGE
	column.add_child(_title)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 1)
	column.add_child(_lines)


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	visible = flight != null and flight.visible and flight.target_id != 0
	if not visible:
		return
	var view: Dictionary = flight.bridge.current_view
	_title.text = "Target: %s" % flight.target_name(view)
	var lines := RendezvousLogic.lines(flight.rendezvous, view["tick"], flight.bridge.ticks_per_second())
	if lines.is_empty():
		lines.append("The Sim gives no relative state for this target yet")
	# One label a line, kept between frames; only their text changes.
	while _lines.get_child_count() > lines.size():
		var extra := _lines.get_child(_lines.get_child_count() - 1)
		_lines.remove_child(extra)
		extra.queue_free()
	while _lines.get_child_count() < lines.size():
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lines.add_child(label)
	for index in range(lines.size()):
		(_lines.get_child(index) as Label).text = lines[index]
	# Fit the height to the lines, not to the tallest it has been.
	size = Vector2(WIDTH_PX, 0)


## The lines as shown, for tests.
func shown_lines() -> PackedStringArray:
	var shown := PackedStringArray()
	for child: Node in _lines.get_children():
		shown.append((child as Label).text)
	return shown
