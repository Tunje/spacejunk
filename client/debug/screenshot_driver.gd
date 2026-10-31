class_name ScreenshotDriver extends Node
## Puts the client into a chosen state for tools/screenshot.ps1. Each argument
## after `--` is optional:
##   --select=ship|station|asteroid  --focus=ship|station|asteroid
##   --order=<order key>             pressed after --delay frames
##   --speed=1|2|4|8  --zoom=<metres>  --yaw=<radians>  --pitch=<radians>

var main: Node3D
var parsed: Dictionary = {}


static func attach_if_requested(parent: Node3D, args: PackedStringArray) -> void:
	var parsed_args := ScreenshotRunner.parse_args(args)
	if parsed_args.is_empty():
		return
	var driver := ScreenshotDriver.new()
	driver.main = parent
	driver.parsed = parsed_args
	parent.add_child(driver)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var view: LocalView = main.local_view
	var camera: OrbitCamera = view.camera
	if parsed.has("speed"):
		main.bridge.set_speed(int(parsed["speed"]))
	if parsed.has("select"):
		var target := _entity(parsed["select"])
		view.select(target[0], target[1], 0)
	if parsed.has("focus"):
		var target := _entity(parsed["focus"])
		view.focus_on(target[0], target[1])
	if parsed.has("yaw"):
		camera.yaw = float(parsed["yaw"])
	if parsed.has("pitch"):
		camera.pitch = float(parsed["pitch"])
	if parsed.has("zoom"):
		camera.target_distance_m = float(parsed["zoom"])
		camera.distance_m = camera.target_distance_m
	if parsed.has("order"):
		for i in range(int(parsed.get("delay", "5"))):
			await get_tree().process_frame
		main.order_panel.refresh()
		if not main.order_panel.press(parsed["order"]):
			push_error("Order not available: %s" % parsed["order"])


func _entity(name_value: String) -> Array:
	var view: Dictionary = main.bridge.current_view
	if name_value == "asteroid":
		var ids: Array = view["bodies"].keys()
		ids.sort()
		for id: int in ids:
			if view["bodies"][id]["kind"] == "asteroid":
				return ["body", id]
	var units: Array = view["units"].keys()
	units.sort()
	for id: int in units:
		if view["units"][id]["kind"] == name_value:
			return ["unit", id]
	return ["", 0]
