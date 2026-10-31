extends Node3D
## Client root: starts the backend, wires the bridge to the overlay.

const SCENARIO := "stub"
const SEED_VALUE := 1

@onready var bridge: SimBridge = $Bridge
@onready var time_controls: TimeControls = $Overlay/TimeControls


func _ready() -> void:
	time_controls.bind(bridge)
	bridge.start(StubSim.new_game(SCENARIO, SEED_VALUE))
	ScreenshotRunner.attach_if_requested(self, OS.get_cmdline_user_args())
