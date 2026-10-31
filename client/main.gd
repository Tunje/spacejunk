extends Node3D
## Client root: starts the backend and wires the bridge to the view and overlay.

const SCENARIO := "stub"
const SEED_VALUE := 1

@onready var bridge: SimBridge = $Bridge
@onready var local_view: LocalView = $LocalView
@onready var time_controls: TimeControls = %TimeControls
@onready var order_panel: OrderPanel = %OrderPanel
@onready var event_log: EventLog = %EventLog
@onready var markers: EntityMarkers = %Markers


func _ready() -> void:
	bridge.start(StubSim.new_game(SCENARIO, SEED_VALUE))
	time_controls.bind(bridge)
	markers.local_view = local_view
	local_view.bind(bridge)
	order_panel.bind(bridge, local_view)
	event_log.bind(bridge)
	var args := OS.get_cmdline_user_args()
	ScreenshotDriver.attach_if_requested(self, args)
	ScreenshotRunner.attach_if_requested(self, args)
