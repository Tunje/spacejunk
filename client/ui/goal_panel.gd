class_name GoalPanel extends PanelContainer
## The next thing to do, with the full list a click away. H hides it.

const WIDTH_PX := 460

var tracker := GoalTracker.new()
var _fitting: FittingScreen
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
	_build_list()


## One line a goal in the tracker's list.
func _build_list() -> void:
	for child: Node in _list.get_children():
		child.free()
	for goal: Dictionary in tracker.goals:
		_list.add_child(Label.new())


## `scenario` picks the goal list, so the new start gets its own.
func bind(new_bridge: SimBridge, log_panel: EventLog, fitting: FittingScreen, scenario := "") -> void:
	_fitting = fitting
	if scenario != "":
		tracker = GoalTracker.new(scenario)
		_build_list()
	bridge = new_bridge
	event_log = log_panel
	_defs = bridge.defs()
	_items = _defs["items"]
	bridge.defs_changed.connect(_reread_defs)
	bridge.view_updated.connect(_on_view)
	bridge.events_received.connect(_on_events)
	fitting.fit_blocked.connect(_note_fit_blocked)
	_on_view()


## A new game or a load: the start's own goal list. A load of the same start keeps
## the tracker, whose state it restores; `fresh` (a new game) always starts over.
func set_scenario(scenario: String, fresh := false) -> void:
	if not fresh and GoalTracker.goals_for(scenario) == tracker.goals:
		return
	tracker = GoalTracker.new(scenario)
	_build_list()
	refresh()


func _note_fit_blocked(item: String, reason: String) -> void:
	tracker.note_fit_blocked(item, reason)


func _reread_defs() -> void:
	_defs = bridge.defs()
	_items = _defs["items"]


func toggle_list() -> void:
	_list.visible = not _list.visible


func refresh() -> void:
	var goal := tracker.current()
	if goal.is_empty():
		_title.text = "All ten goals done" if tracker.goals.size() == 10 else "All %d goals done" % tracker.goals.size()
		_hint.text = "The base can run itself now. Keep going, or try the Policy screen."
	else:
		_title.text = "Goal %d of %d: %s" % [
			tracker.goals.find(goal) + 1, tracker.goals.size(), goal["title"],
		]
		_hint.text = goal["hint"]
	for index in range(tracker.goals.size()):
		var entry: Dictionary = tracker.goals[index]
		var line: Label = _list.get_child(index)
		var finished: bool = tracker.done.has(entry["id"])
		line.text = "%s %d. %s" % ["[x]" if finished else "[  ]", index + 1, entry["title"]]
		line.modulate = ClientTheme.MID_GREY.lightened(0.2) if finished else Color.WHITE


func _on_view() -> void:
	_announce(tracker.observe_view(bridge.current_view, _items, _defs["modules"]))
	refresh()


func _on_events(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		_announce(tracker.observe_event(event, bridge.current_view, _defs))
	refresh()


func _announce(finished: Array[String]) -> void:
	for id: String in finished:
		event_log.add_line("Goal done: %s" % tracker.title_of(id))
