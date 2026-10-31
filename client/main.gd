extends Node3D
## Client root: starts the backend and wires the bridge to the view and overlay.

const SCENARIO := "reference"
const SEED_VALUE := 1

## The stub stays reachable for tests and tools, with `--scenario=stub` after `--`.
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
	goal_panel.bind(bridge, event_log, fitting_screen)
	system_map.bind(bridge, local_view)
	time_controls.map_pressed.connect(toggle_map)
	time_controls.policy_pressed.connect(standing_orders.toggle)
	time_controls.fit_pressed.connect(toggle_fitting)
	time_controls.jobs_pressed.connect(toggle_industry)
	time_controls.save_pressed.connect(save_game)
	time_controls.load_pressed.connect(load_game)
	time_controls.auto_pressed.connect(toggle_automation)
	ScreenshotDriver.attach_if_requested(self, args)
	ScreenshotRunner.attach_if_requested(self, args)
	FrameProbe.attach_if_requested(self, args)


func _new_backend(id: String) -> RefCounted:
	if id == StubSim.SCENARIO_ID or id == StubSim.SCENARIO_LOAD:
		return StubSim.new_game(id, SEED_VALUE)
	return Sim.new_game(id, SEED_VALUE)


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


func toggle_automation() -> void:
	_open_side_screen(automation_screen)


## One side screen at a time, beside the order panel, which always stays up so
## Undock and the other orders are never out of reach.
func _open_side_screen(screen: Control) -> void:
	for other: Control in [fitting_screen, industry_screen, automation_screen]:
		if other != screen and other.visible:
			other.toggle()
	screen.toggle()


## Saves between ticks, after the bridge has drained events, as contracts require.
func save_game() -> void:
	var client_state := {
		"goals": goal_panel.tracker.save_state(),
		"automation": automation_screen.save_state(),
	}
	var saved := SaveStore.write(bridge.sim.to_save(), client_state)
	event_log.add_line("Game saved" if saved else "Save failed: could not write the file")


## A failed load changes nothing, so the game in progress carries on.
func load_game() -> void:
	var slot := SaveStore.read()
	if slot.has("reason"):
		_report_load_failure(slot["reason"])
		return
	var script: GDScript = bridge.sim.get_script()
	var loaded: RefCounted = script.from_save(slot["sim"])
	if loaded == null:
		_report_load_failure(script.last_error())
		return
	_close_screens()
	bridge.start(loaded)
	local_view.rebuild()
	goal_panel.tracker.restore_state(slot["client"].get("goals", {}))
	automation_screen.restore_state(slot["client"].get("automation", {}))
	goal_panel.refresh()
	event_log.add_line("Game loaded")


func _report_load_failure(reason: String) -> void:
	event_log.add_line("Load failed: %s" % OrderText.reason(reason))


func _close_screens() -> void:
	for screen: Control in [fitting_screen, industry_screen, automation_screen]:
		if screen.visible:
			screen.toggle()
	if standing_orders.visible:
		standing_orders.toggle()
	if system_map.is_open():
		toggle_map()


func toggle_map() -> void:
	system_map.set_open(not system_map.is_open())
