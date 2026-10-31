class_name GoalPanel extends PanelContainer
## The next thing to do, with the full list a click away. H hides it.

const WIDTH_PX := 460

var tracker := GoalTracker.new()
var bridge: SimBridge
var event_log: EventLog
var _items: Dictionary = {}
var _defs: Dictionary = {}
var _title: Label
var _hint: Label
var _list: VBoxContainer
var _list_button: Button


func _ready() -> void:
	theme = ClientTheme.build()
	custom_minimum_size = Vector2(WIDTH_PX, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.modulate = ClientTheme.ORANGE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_list_button = Button.new()
	_list_button.text = "All goals"
	_list_button.focus_mode = Control.FOCUS_NONE
	_list_button.pressed.connect(toggle_list)
	header.add_child(_list_button)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)
	_list = VBoxContainer.new()
	_list.visible = false
	column.add_child(_list)
	for goal: Dictionary in GoalTracker.GOALS:
		var line := Label.new()
		_list.add_child(line)


func bind(new_bridge: SimBridge, log_panel: EventLog, fitting: FittingScreen) -> void:
	bridge = new_bridge
	event_log = log_panel
	_defs = bridge.defs()
	_items = _defs["items"]
	bridge.view_updated.connect(_on_view)
	bridge.events_received.connect(_on_events)
	fitting.fit_blocked.connect(tracker.note_fit_blocked)
	_on_view()


func toggle_list() -> void:
	_list.visible = not _list.visible


func refresh() -> void:
	var goal := tracker.current()
	if goal.is_empty():
		_title.text = "All ten goals done"
		_hint.text = "The base can run itself now. Keep going, or try the Policy screen."
	else:
		_title.text = "Goal %d of %d: %s" % [
			GoalTracker.GOALS.find(goal) + 1, GoalTracker.GOALS.size(), goal["title"],
		]
		_hint.text = goal["hint"]
	for index in range(GoalTracker.GOALS.size()):
		var entry: Dictionary = GoalTracker.GOALS[index]
		var line: Label = _list.get_child(index)
		var finished: bool = tracker.done.has(entry["id"])
		line.text = "%s %d. %s" % ["[x]" if finished else "[  ]", index + 1, entry["title"]]
		line.modulate = ClientTheme.MID_GREY.lightened(0.2) if finished else Color.WHITE


func _on_view() -> void:
	_announce(tracker.observe_view(bridge.current_view, _items))
	refresh()


func _on_events(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		_announce(tracker.observe_event(event, bridge.current_view, _defs))
	refresh()


func _announce(finished: Array[String]) -> void:
	for id: String in finished:
		event_log.add_line("Goal done: %s" % GoalTracker.title_of(id))
