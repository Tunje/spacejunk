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
	system_map.bind(bridge, local_view)
	time_controls.map_pressed.connect(toggle_map)
	time_controls.policy_pressed.connect(standing_orders.toggle)
	time_controls.fit_pressed.connect(toggle_fitting)
	time_controls.jobs_pressed.connect(toggle_industry)
	industry_screen.closed.connect(_on_side_screen_closed)
	fitting_screen.closed.connect(_on_side_screen_closed)
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
	if key.physical_keycode == KEY_M:
		toggle_map()
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


## The fitting screen works on the 3D hull, so it closes the map and takes the
## order panel's place while open.
func toggle_fitting() -> void:
	if system_map.is_open():
		toggle_map()
	if industry_screen.visible:
		industry_screen.toggle()
	fitting_screen.toggle()
	order_panel.visible = not fitting_screen.visible


## Jobs work from either view, and share the order panel's place with fitting.
func toggle_industry() -> void:
	if fitting_screen.visible:
		fitting_screen.toggle()
	industry_screen.toggle()
	order_panel.visible = not industry_screen.visible


func _on_side_screen_closed() -> void:
	order_panel.visible = not (fitting_screen.visible or industry_screen.visible)


func toggle_map() -> void:
	system_map.set_open(not system_map.is_open())
