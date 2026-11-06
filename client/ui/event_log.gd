class_name EventLog extends PanelContainer
## The last few things that happened, newest at the bottom.

const MAX_LINES := 6

var bridge: SimBridge
var lines: PackedStringArray = []
var _items: Dictionary = {}
var _label: Label


func _ready() -> void:
	theme = ClientTheme.build()
	custom_minimum_size = Vector2(380, 0)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	visible = false


func bind(new_bridge: SimBridge) -> void:
	bridge = new_bridge
	_items = bridge.defs()["items"]
	bridge.defs_changed.connect(func() -> void: _items = bridge.defs()["items"])
	bridge.events_received.connect(_on_events)


func add_line(line: String) -> void:
	lines.append(line)
	_show()


func _on_events(events: Array[Dictionary]) -> void:
	for entry: Dictionary in events:
		var unit: Dictionary = bridge.current_view["units"].get(entry["unit"], {})
		var line := OrderText.event(entry, unit.get("name", "Order"), _items, bridge.current_view["bodies"])
		if not line.is_empty():
			lines.append(line)
	_show()


func _show() -> void:
	if lines.size() > MAX_LINES:
		lines = lines.slice(lines.size() - MAX_LINES)
	_label.text = "\n".join(lines)
	visible = not lines.is_empty()
