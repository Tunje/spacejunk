class_name Main extends Node3D
## Client root: starts the backend and wires the bridge to the view and overlay.

const SCENARIO := "reference"
## The new start: only the probe, in the rock cluster round the icy moon Frost.
const NEW_START := "new_start"
## The real starts, chosen with `--scenario=<id>` after `--` until there is a start menu.
const STARTS: Array[String] = [SCENARIO, NEW_START]
const SEED_VALUE := 1
## Real seconds between autosaves, counted whether or not the game is paused.
const AUTOSAVE_SECONDS := 300.0

## Which start: `reference` by default, `new_start` with `--scenario=new_start` after
## `--`. The stub stays reachable for tests and tools, with `--scenario=stub`.
@export var scenario := SCENARIO

@onready var bridge: SimBridge = $Bridge
@onready var local_view: LocalView = $LocalView
@onready var time_controls: TimeControls = %TimeControls
@onready var order_panel: OrderPanel = %OrderPanel
@onready var event_log: EventLog = %EventLog
@onready var inspection_panel: InspectionPanel = %InspectionPanel
@onready var fitting_screen: FittingScreen = %FittingScreen
@onready var fitting_markers: FittingMarkers = %FittingMarkers
@onready var industry_screen: IndustryScreen = %IndustryScreen
@onready var automation_screen: AutomationScreen = %AutomationScreen
@onready var goal_panel: GoalPanel = %GoalPanel
@onready var markers: EntityMarkers = %Markers
@onready var system_map: SystemMap = $SystemMap
@onready var standing_orders: StandingOrdersScreen = %StandingOrders
@onready var flight_screen: FlightScreen = %FlightScreen
## Built here rather than in main.tscn: it sits where the industry screen does.
var research_screen: ResearchScreen

## False until a game is running, so a failed start never autosaves.
var _started := false
var _autosave_left := AUTOSAVE_SECONDS


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var parsed := ScreenshotRunner.parse_args(args)
	scenario = parsed.get("scenario", scenario)
	AsteroidField.count_override = int(parsed.get("rocks", "0"))
	var backend := _new_backend(scenario)
	if backend == null:
		push_error("Could not start scenario %s: %s" % [scenario, Sim.last_error()])
		get_tree().quit(1)
		return
	bridge.start(backend)
	time_controls.bind(bridge)
	markers.local_view = local_view
	local_view.bind(bridge)
	order_panel.bind(bridge, local_view)
	event_log.bind(bridge)
	inspection_panel.bind(bridge, local_view)
	fitting_screen.bind(bridge, local_view, fitting_markers)
	industry_screen.bind(bridge, local_view)
	automation_screen.bind(bridge, local_view, order_panel)
	goal_panel.bind(bridge, event_log, fitting_screen, scenario)
	system_map.bind(bridge, local_view)
	flight_screen.bind(bridge, local_view, system_map)
	_add_research_screen()
	time_controls.map_pressed.connect(toggle_map)
	time_controls.fly_pressed.connect(toggle_flight)
	time_controls.policy_pressed.connect(standing_orders.toggle)
	time_controls.fit_pressed.connect(toggle_fitting)
	time_controls.jobs_pressed.connect(toggle_industry)
	time_controls.research_pressed.connect(toggle_research)
	time_controls.save_pressed.connect(save_game)
	time_controls.load_pressed.connect(load_game)
	time_controls.auto_pressed.connect(toggle_automation)
	ScreenshotDriver.attach_if_requested(self, args)
	ScreenshotRunner.attach_if_requested(self, args)
	FrameProbe.attach_if_requested(self, args)
	_started = true


func _process(delta: float) -> void:
	if not _started:
		return
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		autosave()


## Closing the window autosaves first. Godot still quits on its own afterwards,
## so project.godot needs no change.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _started:
		autosave()


func _new_backend(id: String) -> RefCounted:
	if [StubSim.SCENARIO_ID, StubSim.SCENARIO_LOAD, StubSim.SCENARIO_ORBIT].has(id):
		return StubSim.new_game(id, SEED_VALUE)
	return Sim.new_game(id, SEED_VALUE)


## Planet builds run on their own threads; none may outlive the game.
func _exit_tree() -> void:
	PlanetMesh.finish_all()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_F5:
		save_game()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_F9:
		load_game()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_M:
		toggle_map()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_H:
		goal_panel.visible = not goal_panel.visible
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_K:
		toggle_automation()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_ESCAPE and automation_screen.visible:
		toggle_automation()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_B:
		toggle_flight()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_ESCAPE and flight_screen.visible:
		toggle_flight()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_O:
		local_view.set_planet_outlines(not BodyNode.show_outlines)
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_R:
		toggle_research()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_ESCAPE and research_screen.visible:
		toggle_research()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_J:
		toggle_industry()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_ESCAPE and industry_screen.visible:
		toggle_industry()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_G:
		toggle_fitting()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_ESCAPE and fitting_screen.visible:
		toggle_fitting()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_P:
		standing_orders.toggle()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_ESCAPE and standing_orders.visible:
		standing_orders.toggle()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_ESCAPE and system_map.is_open():
		toggle_map()
		get_viewport().set_input_as_handled()


## The fitting screen works on the 3D hull, so it closes the map.
func toggle_fitting() -> void:
	if system_map.is_open():
		toggle_map()
	_open_side_screen(fitting_screen)


## Jobs work from either view.
func toggle_industry() -> void:
	_open_side_screen(industry_screen)


func toggle_research() -> void:
	_open_side_screen(research_screen)


## Same place and size as the industry screen, as a sibling in the overlay.
func _add_research_screen() -> void:
	research_screen = ResearchScreen.new()
	research_screen.name = "ResearchScreen"
	industry_screen.get_parent().add_child(research_screen)
	for property: String in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "offset_left",
			"offset_top", "offset_right", "offset_bottom", "grow_horizontal", "grow_vertical"]:
		research_screen.set(property, industry_screen.get(property))
	research_screen.bind(bridge)


func toggle_automation() -> void:
	_open_side_screen(automation_screen)


## Manual flight. It draws its paths in whichever view is open, so the map stays.
func toggle_flight() -> void:
	_open_side_screen(flight_screen)


## One side screen at a time, beside the order panel, which always stays up so
## Undock and the other orders are never out of reach.
func _open_side_screen(screen: Control) -> void:
	for other: Control in [fitting_screen, industry_screen, automation_screen, flight_screen, research_screen]:
		if other != screen and other.visible:
			other.toggle()
	screen.toggle()


## Saves to the manual slot, which only F5 and the Save button write.
func save_game() -> void:
	var saved := _write_slot(SaveStore.path)
	event_log.add_line("Game saved" if saved else "Save failed: could not write the file")


## Saves to the autosave slot and restarts the timer. A failed write is reported
## and play goes on.
func autosave() -> void:
	_autosave_left = AUTOSAVE_SECONDS
	var saved := _write_slot(SaveStore.autosave_path)
	event_log.add_line("Game autosaved" if saved else "Autosave failed: could not write the file")


## Runs from input, a signal or this node's own frame, never inside a bridge
## step, so it always saves between ticks, as contracts require.
func _write_slot(at: String) -> bool:
	var client_state := {
		"goals": goal_panel.tracker.save_state(),
		"automation": automation_screen.save_state(),
	}
	return SaveStore.write(bridge.sim.to_save(), client_state, at)


## Loads whichever slot is newer. A slot that exists but cannot be loaded is
## reported, and the other one is used instead. A failed load changes nothing,
## so the game in progress carries on.
func load_game() -> void:
	var script: GDScript = bridge.sim.get_script()
	var failures: Array[String] = []
	var slots := SaveStore.read_newest_first()
	for slot: Dictionary in slots:
		if slot.has("reason") and slot["reason"] != SaveStore.REASON_NO_SAVE:
			failures.append(_load_failure_line(slot, slot["reason"]))
	for slot: Dictionary in slots:
		if slot.has("reason"):
			continue
		var loaded: RefCounted = script.from_save(slot["sim"])
		if loaded == null:
			failures.append(_load_failure_line(slot, script.last_error()))
			continue
		for line: String in failures:
			event_log.add_line(line)
		_apply_load(loaded, slot["client"])
		event_log.add_line("Autosave loaded" if slot["auto"] else "Game loaded")
		return
	if failures.is_empty():
		failures.append("Load failed: %s" % OrderText.reason(SaveStore.REASON_NO_SAVE))
	for line: String in failures:
		event_log.add_line(line)


func _load_failure_line(slot: Dictionary, reason: String) -> String:
	var text := OrderText.reason(reason)
	return ("Autosave failed to load: %s" if slot["auto"] else "Load failed: %s") % text


func _apply_load(loaded: RefCounted, client_state: Dictionary) -> void:
	_close_screens()
	bridge.start(loaded)
	local_view.rebuild()
	goal_panel.tracker.restore_state(client_state.get("goals", {}))
	automation_screen.restore_state(client_state.get("automation", {}))
	goal_panel.refresh()


func _close_screens() -> void:
	for screen: Control in [fitting_screen, industry_screen, automation_screen, flight_screen]:
		if screen.visible:
			screen.toggle()
	if standing_orders.visible:
		standing_orders.toggle()
	if system_map.is_open():
		toggle_map()


func toggle_map() -> void:
	system_map.set_open(not system_map.is_open())
