extends Node3D
## Client root: starts the backend and wires the bridge to the view and overlay.

const SCENARIO := "stub"
const SEED_VALUE := 1

@onready var bridge: SimBridge = $Bridge
@onready var local_view: LocalView = $LocalView
@onready var time_controls: TimeControls = %TimeControls
@onready var order_panel: OrderPanel = %OrderPanel
@onready var event_log: EventLog = %EventLog
@onready var inspection_panel: InspectionPanel = %InspectionPanel
@onready var markers: EntityMarkers = %Markers
@onready var system_map: SystemMap = $SystemMap
@onready var standing_orders: StandingOrdersScreen = %StandingOrders


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario: String = ScreenshotRunner.parse_args(args).get("scenario", SCENARIO)
	bridge.start(StubSim.new_game(scenario, SEED_VALUE))
	time_controls.bind(bridge)
	markers.local_view = local_view
	local_view.bind(bridge)
	order_panel.bind(bridge, local_view)
	event_log.bind(bridge)
	inspection_panel.bind(bridge, local_view)
	system_map.bind(bridge, local_view)
	time_controls.map_pressed.connect(toggle_map)
	time_controls.policy_pressed.connect(standing_orders.toggle)
	ScreenshotDriver.attach_if_requested(self, args)
	ScreenshotRunner.attach_if_requested(self, args)
	FrameProbe.attach_if_requested(self, args)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_M:
		toggle_map()
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


func toggle_map() -> void:
	system_map.set_open(not system_map.is_open())
