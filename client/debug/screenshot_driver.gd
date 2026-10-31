class_name ScreenshotDriver extends Node
## Puts the client into a chosen state for tools/screenshot.ps1. Each argument
## after `--` is optional:
##   --select=ship|station|asteroid  --focus=ship|station|asteroid
##   --order=<order key>             pressed after --delay frames
##   --scenario=<id>  (read by main)  --speed=1|2|4|8  --zoom=<metres>  --yaw=<radians>  --pitch=<radians>
##   --map=1                         opens the system map
##   --policy=1                      opens the standing-orders mock
##   --then=<order key>              pressed --then-delay frames after --order
##   --last=<order key>              pressed --last-delay frames after --then
##   --cycle=1                       fits a tier 2 core and starts a short cycle at once
##   --jobs=<recipe id>              opens the jobs screen and starts that recipe
##   --fit=<item>  --fit-slot=<connector>  opens fitting after the orders and picks both

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
	if parsed.has("map"):
		main.toggle_map()
		camera = main.system_map.camera
		if parsed.has("yaw"):
			camera.yaw = float(parsed["yaw"])
		if parsed.has("pitch"):
			camera.pitch = float(parsed["pitch"])
		if parsed.has("zoom"):
			camera.target_distance_m = float(parsed["zoom"])
			camera.distance_m = camera.target_distance_m
	if parsed.has("policy"):
		main.standing_orders.toggle()
	if parsed.has("order"):
		await _press_after(parsed["order"], int(parsed.get("delay", "5")))
	if parsed.has("then"):
		await _press_after(parsed["then"], int(parsed.get("then-delay", "60")))
	if parsed.has("last"):
		await _press_after(parsed["last"], int(parsed.get("last-delay", "60")))
	if parsed.has("fit"):
		await _open_fitting()
	if parsed.has("jobs"):
		await _open_jobs()
	if parsed.has("cycle"):
		await _start_demo_cycle()


## A stand-in for a hand-flown trip, which takes minutes to reach on the real Sim.
func _start_demo_cycle() -> void:
	var bridge: SimBridge = main.bridge
	var view: Dictionary = bridge.current_view
	var ship: int = main.local_view.commanded_unit
	var unit: Dictionary = view["units"][ship]
	var host: int = unit["dock"]["target_unit"]
	var mass: int = bridge.defs()["modules"]["assisted_core"]["mass_g"]
	bridge.sim._state["units"][host]["inventory"]["assisted_core"] = mass
	bridge.submit(FittingLogic.detach_command(ship, unit["core"], host))
	bridge.submit(FittingLogic.attach_command(ship, { "item": "assisted_core", "from": host }, {
		"part": unit["parts"]["id"], "connector": "core",
	}))
	for i in range(30):
		await get_tree().process_frame
	var screen: AutomationScreen = main.automation_screen
	main.toggle_automation()
	screen.assign(CyclePlan.cores(screen.unit(), screen._defs["modules"])[0]["part"])
	for i in range(30):
		await get_tree().process_frame
	var rock := 0
	for id: int in view["bodies"]:
		if view["bodies"][id]["kind"] == "asteroid":
			rock = id
	screen.note_order({ "type": "undock", "unit": ship, "args": {} })
	screen.note_order({ "type": "move_to", "unit": ship, "args": { "target": rock } })
	var home := { "type": "move_to", "unit": ship, "args": { "target": host } }
	screen.trip.append({ "type": home["type"], "args": home["args"] })
	screen.trip.append({ "type": "dock", "args": { "port": unit["dock"]["port"], "target_port": unit["dock"]["target_port"] } })
	screen.repeat_route()


func _open_jobs() -> void:
	main.toggle_industry()
	var screen: IndustryScreen = main.industry_screen
	for entry: Dictionary in IndustryLogic.facilities(main.bridge.current_view["units"][screen.unit_id], screen._defs["modules"]):
		for recipe: Dictionary in IndustryLogic.recipes_for(entry["type"], screen._defs["recipes"]):
			if recipe["id"] == parsed["jobs"]:
				screen.choose_facility(entry)
				screen.start(recipe)


func _open_fitting() -> void:
	for i in range(int(parsed.get("fit-delay", "40"))):
		await get_tree().process_frame
	main.toggle_fitting()
	var screen: FittingScreen = main.fitting_screen
	for entry: Dictionary in screen._stock:
		if entry["item"] == parsed["fit"]:
			screen.choose(entry)
	for slot: Dictionary in FittingLogic.free_slots(screen.unit(), screen._modules):
		if slot["connector"] == parsed.get("fit-slot", ""):
			screen.choose_slot(slot)


func _press_after(key: String, frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
	main.order_panel.refresh()
	if not main.order_panel.press(key):
		push_error("Order not available: %s" % key)


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
