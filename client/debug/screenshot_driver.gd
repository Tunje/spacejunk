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
##   --jobs=<recipe id>[,<id>...]    opens the jobs screen and starts or queues each recipe
##   --jobs-run=<seconds>            then runs about that many game seconds, to show a run part done
##   --fly=<m/s>[,<normal>,<radial>]  opens flight on the commanded craft with that burn typed in
##   --fly-at=peri|apo|<seconds>     places it at an apsis or so many seconds ahead
##   --fly-delay=<frames>            waits first, such as for an undock to finish
##   --fly-plan=<frames>             plans the burn, then runs that many frames
##   --outlines=1                    shows the hex outlines on planets
##   --planet-wait=1                 waits for every planet's terrain before the rest
##   --transfer-demo=<seconds>       (reference) a planet with two frames on the real Sim, the ship
##                                   sent to the far one's rock, run that long past departure
##   --propellant=<kg>               the landing demo's propellant, 1000 by default
##   --landing-demo=pick|landed      (reference) a small planet on the real Sim with the probe in
##                                   orbit: choosing a hex with Land's cost, or after landing on it
##   --soi-demo=<fraction>           (reference) A18's compact system on the real Sim, the ship sent
##                                   to the moon's ring; -1 shows it waiting, else that far through
##   --descent-demo=<m/s>,<seconds>  (reference) a light 250 km world on the real Sim: the probe, with
##                                   legs, lifts off straight up at that speed and flies that long
##   --snapshot=<res:// save>        (real Sim) loads that save first, such as a bot stage's
##   --prove=<theory>                (real Sim) marks it proven and its designs prototype, as a lab test would
##   --run=<seconds>                 (real Sim) steps the game that long first, such as out of a shadow
##   --set-down=<body name>,<cell>   (real Sim) puts the commanded craft down on that hex as a landing
##                                   ends, for a landed shot where it can't yet fly down
##   --look-at=<body name>           turns the camera so that body is behind the craft (after --pitch)
##   --build-into=<recipe id>        opens Jobs on the facility that makes it, then its "Build into…" picker
##   --research=1                    opens the research screen
##   --research-ideas=<base>:<idea>[,<idea>...]  then picks that base and those ideas in its designer
##   --copy=1                        (stub_load) strips two parts off the first ship and
##                                   opens fitting there, to show "Fit like this one"
##   --fit=<item>  --fit-slot=<connector>  opens fitting after the orders and picks both
##   --drone=<0 to 6>                builds a small craft with that many parts fitted, and selects it
##   --drone-fly=1                   then gives it a core and propellant, and sends it to a rock
##   --drone-fit=<item>              then opens fitting on it with that part chosen and in stock
##   --goals-done=<count>            marks the first goals done, to show a later hint
##   --autosave=1                    autosaves to a side file, never the player's, and loads it

const DRONE_FITS: Array[Dictionary] = [
	{ "item": "small_solar_panel_mk1", "at": "side_a_px" },
	{ "item": "small_heat_radiator_mk1", "at": "side_a_nx" },
	{ "item": "small_propellant_tank_mk1", "at": "stack_bottom" },
	{ "item": "small_chemical_thruster_mk1", "at": "stack_bottom" },
	{ "item": "small_ore_container_mk1", "at": "side_a_pz" },
	{ "item": "small_mining_laser_mk1", "at": "side_a_nz" },
]
const RUN_STEP_S := 0.1
const SHOT_SAVE_PATH := "user://screenshot.save"
const SHOT_AUTOSAVE_PATH := "user://screenshot_autosave.save"

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
	if parsed.has("transfer-demo"):
		_transfer_demo(float(parsed["transfer-demo"]))
	if parsed.has("soi-demo"):
		_soi_demo(float(parsed["soi-demo"]))
	if parsed.has("descent-demo"):
		await _descent_demo(parsed["descent-demo"])
	if parsed.has("landing-demo"):
		await _landing_demo(parsed["landing-demo"])
	if parsed.has("snapshot"):
		var loaded := Sim.from_save(FileAccess.get_file_as_string(parsed["snapshot"]))
		if loaded != null:
			main.bridge.start(loaded)
			main.local_view.rebuild()
	if parsed.has("prove"):
		var research: Dictionary = main.bridge.sim._state["research"]
		research["theories"][parsed["prove"]] = main.bridge.current_view["tick"]
		for design: String in main.bridge.defs()["theories"][parsed["prove"]]["unlocks"]:
			research["designs"][design] = "prototype"
		main.bridge.start(main.bridge.sim)
	if parsed.has("run"):
		(main.bridge.sim as Sim).step(roundi(float(parsed["run"]) * Sim.TICKS_PER_SECOND))
		main.bridge.start(main.bridge.sim)
	if parsed.has("set-down"):
		_set_down(parsed["set-down"])
	if parsed.has("planet-wait"):
		while PlanetMesh.busy():
			await get_tree().process_frame
	if parsed.has("outlines"):
		view.set_planet_outlines(true)
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
	if parsed.has("look-at"):
		await _look_at(parsed["look-at"], float(parsed.get("pitch", "0")))
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
	if parsed.has("build-into"):
		main.toggle_industry()
		var screen: IndustryScreen = main.industry_screen
		var recipe: Dictionary = main.bridge.defs()["recipes"][parsed["build-into"]]
		for entry: Dictionary in IndustryLogic.facilities(main.bridge.current_view["units"][screen.unit_id], screen._defs["modules"]):
			if entry["type"] == recipe["facility"]:
				screen.choose_facility(entry)
		screen.refresh()
		screen.open_picker(recipe)
	if parsed.has("research"):
		main.toggle_research()
		if parsed.has("research-designs"):
			await get_tree().process_frame
			await get_tree().process_frame
			main.research_screen.scroll_to_designs()
		if parsed.has("research-ideas"):
			var spec: PackedStringArray = parsed["research-ideas"].split(":")
			main.research_screen.choose_base(spec[0])
			for idea: String in spec[1].split(","):
				main.research_screen.toggle_idea(idea, true)
			main.research_screen._key = ""
			main.research_screen.refresh()
			# Down to the designer, once the list has its size.
			await get_tree().process_frame
			await get_tree().process_frame
			main.research_screen.scroll_to_designs()
	if parsed.has("cycle"):
		await _start_demo_cycle()
	if parsed.has("copy"):
		_open_copy_fit()
	if parsed.has("fly"):
		await _open_flight()
	if parsed.has("drone"):
		_show_demo_drone()
	if parsed.has("goals-done"):
		for index in range(int(parsed["goals-done"])):
			main.goal_panel.tracker.complete(main.goal_panel.tracker.goals[index]["id"])
		main.goal_panel.refresh()
	if parsed.has("autosave"):
		SaveStore.path = SHOT_SAVE_PATH
		SaveStore.autosave_path = SHOT_AUTOSAVE_PATH
		main.save_game()
		main.autosave()
		main.load_game()


func _show_demo_drone() -> void:
	var bridge: SimBridge = main.bridge
	var view: LocalView = main.local_view
	var drone := ScreenshotDriver.build_drone(bridge, int(parsed["drone"]))
	view.refresh(0.0)
	view.select("unit", drone, 0)
	view.focus_on("unit", drone)
	view.camera.distance_m = view.camera.target_distance_m
	if parsed.has("drone-fit"):
		ScreenshotDriver.stock_part(bridge, parsed["drone-fit"])
		ScreenshotDriver._step(bridge)
		main.toggle_fitting()
		var screen: FittingScreen = main.fitting_screen
		for entry: Dictionary in FittingLogic.stock(bridge.current_view, drone, screen._modules):
			if entry["item"] == parsed["drone-fit"]:
				screen.choose(entry)
	if parsed.has("drone-fly"):
		ScreenshotDriver.send_drone_out(bridge, drone)


## A stand-in for hours of play: stock is written in, then the real job and attaches run.
static func build_drone(bridge: SimBridge, fitted: int) -> int:
	var view: Dictionary = bridge.current_view
	var station := ScreenshotDriver._unit_of_kind(view, "station")
	var defs: Dictionary = bridge.defs()
	var stock: Dictionary = bridge.sim._state["units"][station]["inventory"]
	stock["structural_frame"] = stock.get("structural_frame", 0) + 2 * defs["items"]["structural_frame"]["unit_mass_g"]
	stock["wiring"] = stock.get("wiring", 0) + 2 * defs["items"]["wiring"]["unit_mass_g"]
	var fabricator := 0
	for entry: Dictionary in IndustryLogic.facilities(view["units"][station], defs["modules"]):
		if entry["type"] == "fabricator":
			fabricator = entry["part"]
	bridge.submit(IndustryLogic.start_command(station, fabricator, defs["recipes"]["small_craft"], 1))
	var drone := 0
	while drone == 0:
		ScreenshotDriver._step(bridge)
		drone = ScreenshotDriver._unit_of_kind(bridge.current_view, "drone")
	for index in range(fitted):
		ScreenshotDriver._fit_part(bridge, drone, DRONE_FITS[index]["item"], DRONE_FITS[index]["at"])
	return drone


static func stock_part(bridge: SimBridge, item: String) -> void:
	var station := ScreenshotDriver._unit_of_kind(bridge.current_view, "station")
	bridge.sim._state["units"][station]["inventory"][item] = bridge.defs()["modules"][item]["mass_g"]


## Fits a Basic Core, fills the tank, undocks and starts for the first asteroid.
static func send_drone_out(bridge: SimBridge, drone: int) -> void:
	ScreenshotDriver._fit_part(bridge, drone, "basic_core", "core")
	var unit: Dictionary = bridge.current_view["units"][drone]
	var core := 0
	for part: Dictionary in InspectText.flatten(unit["parts"]):
		if part["def"] == "basic_core":
			core = part["id"]
	bridge.submit({ "type": "assign_core", "unit": drone, "args": { "core": core } })
	ScreenshotDriver._step(bridge)
	var host: int = unit["dock"]["target_unit"]
	bridge.submit({ "type": "load_cargo", "unit": drone, "args": { "from": host, "item": "propellant" } })
	ScreenshotDriver._run_until_idle(bridge, drone)
	bridge.submit({ "type": "undock", "unit": drone, "args": {} })
	ScreenshotDriver._run_until_idle(bridge, drone)
	var view: Dictionary = bridge.current_view
	var ids: Array = view["bodies"].keys()
	ids.sort()
	for id: int in ids:
		if view["bodies"][id]["kind"] == "asteroid":
			bridge.submit({ "type": "move_to", "unit": drone, "args": { "target": id } })
			break
	for i in range(8):
		ScreenshotDriver._step(bridge)


static func _fit_part(bridge: SimBridge, drone: int, item: String, connector: String) -> void:
	ScreenshotDriver.stock_part(bridge, item)
	var station := ScreenshotDriver._unit_of_kind(bridge.current_view, "station")
	var unit: Dictionary = bridge.current_view["units"][drone]
	for slot: Dictionary in FittingLogic.free_slots(unit, bridge.defs()["modules"]):
		if slot["connector"] == connector:
			bridge.submit(FittingLogic.attach_command(drone, { "item": item, "from": station }, slot))
			break
	ScreenshotDriver._step(bridge)


static func _step(bridge: SimBridge) -> void:
	var was_paused := bridge.paused
	bridge.set_paused(false)
	bridge.set_speed(WarpLogic.STEP_MAX)
	bridge.advance(RUN_STEP_S)
	bridge.set_paused(was_paused)


static func _run_until_idle(bridge: SimBridge, unit_id: int) -> void:
	ScreenshotDriver._step(bridge)
	while bridge.current_view["units"][unit_id]["op"]["type"] != "idle":
		ScreenshotDriver._step(bridge)


static func _unit_of_kind(view: Dictionary, kind: String) -> int:
	var ids: Array = view["units"].keys()
	ids.sort()
	for id: int in ids:
		if view["units"][id]["kind"] == kind:
			return id
	return 0


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
		for wanted: String in parsed["jobs"].split(","):
			for recipe: Dictionary in IndustryLogic.recipes_for(entry["type"], screen._defs["recipes"]):
				if recipe["id"] == wanted:
					screen.choose_facility(entry)
					screen.start(recipe)
	ScreenshotDriver._step(main.bridge)
	for i in roundi(float(parsed.get("jobs-run", "0")) / (RUN_STEP_S * WarpLogic.STEP_MAX)):
		ScreenshotDriver._step(main.bridge)
	main.bridge.set_paused(true)
	screen.refresh()


## Puts the camera on the far side of the craft from a body, so both are in view;
## `extra_pitch` then tips it up or down. Waits for the camera's up to settle first.
func _look_at(name: String, extra_pitch: float) -> void:
	for i in 30:
		await get_tree().process_frame
	var view: LocalView = main.local_view
	var body := 0
	for id: int in main.bridge.current_view["bodies"]:
		if main.bridge.current_view["bodies"][id]["name"] == name:
			body = id
	if not view.bodies.has(body) or not view.crafts.has(view.commanded_unit):
		return
	var towards: Vector3 = (view.bodies[body] as Node3D).global_position - (view.crafts[view.commanded_unit] as Node3D).global_position
	var camera: OrbitCamera = view.camera
	var tilt := Basis(Quaternion(Vector3.UP, camera.up_dir.normalized())) if not camera.up_dir.is_equal_approx(Vector3.UP) else Basis.IDENTITY
	var away := (tilt.inverse() * -towards).normalized()
	camera.yaw = atan2(away.x, away.z)
	camera.pitch = -asin(clampf(away.y, -1.0, 1.0)) + extra_pitch


## Sets the commanded craft down on a hex through the sim's own landing end, then
## restarts the bridge on the changed state so the view rebuilds round it.
func _set_down(spec: String) -> void:
	var parts := spec.split(",")
	var sim: Sim = main.bridge.sim
	var body := 0
	for id: int in sim._state["bodies"]:
		if sim._state["bodies"][id]["name"] == parts[0]:
			body = id
	var unit: int = main.local_view.commanded_unit
	LandingSystem._set_down(sim._ctx, unit, body, int(parts[1]))
	sim._ctx.index.clear()
	sim.step(1)
	main.bridge.start(sim)
	main.local_view.rebuild()
	main.local_view.focus_on("unit", unit)


## The descent test's world: 250 km, light enough (0.16 m/s^2) for the starter ship to
## lift off, with the probe on hex 4321 with legs.
func _descent_demo(spec: String) -> void:
	var parts := spec.split(",")
	var up_m_s := float(parts[0])
	var seconds := float(parts[1]) if parts.size() > 1 else 20.0
	var defs := DataLoader.load_defs()
	var sim := Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": 132_712_440_018_000_000 },
			{ "key": "planet", "name": "Grit", "kind": "planet", "radius_mm": 250_000_000, "visual_seed": 2,
				"deposits": [], "gm": 10_000_000, "orbit": { "parent": "star", "a_mm": 149_597_870_700_000 },
				"planet": { "seed": 48213, "height_range_m": 6000 } },
		],
		"units": [{ "key": "ship", "template": "starter_ship", "name": "Probe", "pos_mm": [0, 0, 0],
			"inventory": [{ "item": "propellant", "grams": 1_900_000 }], "dock": null }],
	}, {})
	var ship := 0
	var planet := 0
	for id: int in sim._state["units"]:
		ship = id
	for id: int in sim._state["bodies"]:
		if sim._state["bodies"][id]["kind"] == "planet":
			planet = id
	LandingLegs.fit(sim, ship)
	var n := PlanetGrid.n_for_radius(250_000_000)
	var height := PlanetGrid.height_m(48213, PlanetGrid.direction(4321, n), PlanetMesh.DEFAULT_WEIGHTS, 6000)
	var unit: Dictionary = sim._state["units"][ship]
	unit["orbit"] = {}
	unit["landed"] = { "body": planet, "cell": 4321 }
	unit["pos_mm"] = PlanetGrid.centre_mm(4321, n, 250_000_000, height)
	sim._ctx.index.clear()
	sim.submit({ "type": "plan_burn", "unit": ship, "args": { "tick": sim.current_tick() + 1,
		"prograde_um_s": 0, "normal_um_s": 0, "radial_um_s": roundi(up_m_s * 1_000_000) } })
	sim.step(roundi(seconds * Sim.TICKS_PER_SECOND))
	main.bridge.start(sim)
	main.bridge.set_paused(true)
	main.local_view.rebuild()
	main.local_view.focus_on("unit", ship)
	while PlanetMesh.busy():
		await get_tree().process_frame
	main.toggle_flight()


## A18's test world: a heavy central body, a home frame at 20,000 km, and a moon at
## 30,000 km with a ring frame round it. The ship is sent to the ring's rock.
func _soi_demo(fraction: float) -> void:
	var defs := DataLoader.load_defs()
	var sim := Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "root", "name": "Root", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 5_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": 100_000_000_000_000 },
			{ "key": "moon", "name": "Moon", "kind": "planet", "radius_mm": 100_000_000, "visual_seed": 2,
				"deposits": [], "gm": 10_000_000_000, "orbit": { "parent": "root", "a_mm": 30_000_000_000, "mean_anomaly_mdeg": 40_000 } },
			{ "key": "moon_rock", "name": "Moon Rock", "kind": "asteroid", "frame": "ring", "pos_mm": [20_000_000, 0, 0],
				"radius_mm": 300_000, "visual_seed": 4, "deposits": [] },
		],
		"frames": [
			{ "key": "home", "name": "Home", "radius_mm": 1_000_000, "orbit": { "parent": "root", "a_mm": 20_000_000_000 } },
			{ "key": "ring", "name": "Ring", "radius_mm": 1_000_000,
				"orbit": { "parent": "moon", "a_mm": 300_000_000, "mean_anomaly_mdeg": 200_000 } },
		],
		"units": [{ "key": "ship", "template": "starter_ship", "name": "Ship", "pos_mm": [150_000, 0, 0], "frame": "home",
			"inventory": [{ "item": "propellant", "grams": 4_000_000_000 }], "dock": null }],
	}, {})
	var ship := 0
	var rock := 0
	for id: int in sim._state["units"]:
		ship = id
	for id: int in sim._state["bodies"]:
		if sim._state["bodies"][id]["name"] == "Moon Rock":
			rock = id
	sim.submit({ "type": "move_to", "unit": ship, "args": { "target": rock } })
	sim.step(2)
	var plan: Dictionary = sim._state["units"][ship]["op"].get("plan", {})
	if fraction >= 0.0 and not plan.is_empty():
		var span: int = plan["arrive_tick"] - plan["depart_tick"]
		sim.step(plan["depart_tick"] - sim.current_tick() + roundi(span * fraction))
	main.bridge.start(sim)
	main.bridge.set_paused(true)
	main.local_view.rebuild()
	main.local_view.select("body", rock, 0)


## A13's test world, built on the real Sim: a planet with frames at 700 and 900 km.
func _transfer_demo(seconds_after_departure: float) -> void:
	var defs := DataLoader.load_defs()
	var sim := Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	var frame := func(key: String, a_mm: int, mean_mdeg: int) -> Dictionary:
		return { "key": key, "name": key.capitalize(), "radius_mm": 1_000_000,
			"orbit": { "parent": "planet", "a_mm": a_mm, "mean_anomaly_mdeg": mean_mdeg } }
	ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": 132_712_440_018_000_000 },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": 3_531_600_000, "orbit": { "parent": "star", "a_mm": 149_597_870_700_000 } },
			{ "key": "rock", "name": "Rock", "kind": "asteroid", "frame": "far", "pos_mm": [20_000_000, 0, 0],
				"radius_mm": 500_000, "visual_seed": 3, "deposits": [] },
		],
		"frames": [frame.call("home", 700_000_000, 0), frame.call("far", 900_000_000, 123_000)],
		"units": [{ "key": "ship", "template": "starter_ship", "name": "Ship", "pos_mm": [150_000, 0, 0],
			"frame": "home", "inventory": [{ "item": "propellant", "grams": 1_000_000 }], "dock": null }],
	}, {})
	var ship := 0
	var rock := 0
	for id: int in sim._state["units"]:
		ship = id
	for id: int in sim._state["bodies"]:
		if sim._state["bodies"][id]["name"] == "Rock":
			rock = id
	sim.submit({ "type": "move_to", "unit": ship, "args": { "target": rock } })
	sim.step(2)
	var depart: int = sim._state["units"][ship]["op"].get("depart_tick", 2)
	sim.step(depart - sim.current_tick() + roundi(seconds_after_departure * Sim.TICKS_PER_SECOND))
	main.bridge.start(sim)
	main.bridge.set_paused(true)
	main.local_view.rebuild()
	main.local_view.select("body", rock, 0)


## A 250 km airless planet with terrain and the ship 50 km up, as test_landing_ui has.
func _landing_demo(stage: String) -> void:
	var defs := DataLoader.load_defs()
	var sim := Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": 132_712_440_018_000_000 },
			{ "key": "planet", "name": "Grit", "kind": "planet", "radius_mm": 250_000_000, "visual_seed": 2,
				"deposits": [], "gm": 65_138_398, "orbit": { "parent": "star", "a_mm": 149_597_870_700_000 },
				"planet": { "seed": 48213, "height_range_m": 6000 } },
		],
		"units": [{ "key": "ship", "template": "starter_ship", "name": "Probe", "pos_mm": [0, 0, 0],
			"inventory": [{ "item": "propellant", "grams": roundi(float(parsed.get("propellant", "1000")) * 1000.0) }],
			"dock": null }],
	}, {})
	var ship := 0
	var planet := 0
	for id: int in sim._state["units"]:
		ship = id
	for id: int in sim._state["bodies"]:
		if sim._state["bodies"][id]["kind"] == "planet":
			planet = id
	var orbit := OrbitMath.from_state([300_000_000, 0, 0], [0, 0, -466_000_000], 65_138_398, 0)
	orbit["parent"] = planet
	LandingLegs.fit(sim, ship)
	sim._state["units"][ship]["orbit"] = orbit
	sim._state["units"][ship]["pos_mm"] = OrbitMath.position_at(orbit, 0)
	sim._ctx.index.clear()
	# Near the north pole when landed, so the ground lies flat for the camera, which
	# keeps world +Y up; under the ship when choosing.
	var cell := 2 if stage == "landed" else PlanetGrid.cell_count(PlanetGrid.n_for_radius(250_000_000)) / 2
	if stage == "landed":
		var plan: Dictionary = sim.check({ "type": "land", "unit": ship, "args": { "body": planet, "cell": cell } })
		sim.submit({ "type": "land", "unit": ship, "args": { "body": planet, "cell": cell } })
		sim.step(plan["detail"]["ticks"] + 3)
	main.bridge.start(sim)
	main.bridge.set_paused(true)
	main.local_view.rebuild()
	main.local_view.focus_on("unit", ship)
	while PlanetMesh.busy():
		await get_tree().process_frame
	main.toggle_flight()
	if stage == "pick":
		var screen: FlightScreen = main.flight_screen
		screen.set_picking(true)
		var body: BodyNode = main.local_view.bodies[planet]
		screen.choose_cell(PlanetMesh.nearest_cell(body.planet, Vector3(1, 0, 0)))


func _open_flight() -> void:
	for i in range(int(parsed.get("fly-delay", "0"))):
		await get_tree().process_frame
	main.toggle_flight()
	var screen: FlightScreen = main.flight_screen
	var values: PackedFloat64Array = []
	for part: String in parsed["fly"].split(","):
		values.append(float(part))
	while values.size() < 3:
		values.append(0.0)
	match parsed.get("fly-at", ""):
		"peri":
			screen.burn_at_apsis(0.0)
		"apo":
			screen.burn_at_apsis(PI)
		"":
			screen.burn_now()
		var seconds:
			screen.burn_tick = main.bridge.current_view["tick"] + 1 + roundi(float(seconds) * main.bridge.ticks_per_second())
	screen.set_components(values[0], values[1], values[2])
	if parsed.has("fly-plan"):
		screen.plan()
		for i in range(int(parsed["fly-plan"])):
			await get_tree().process_frame
		screen.set_components(values[0], values[1], values[2])


## Takes the laser and solar slab off the first ship into its own hold, so another
## ship's fit has something to give back, then opens fitting on it.
func _open_copy_fit() -> void:
	var bridge: SimBridge = main.bridge
	var ship := ScreenshotDriver._unit_of_kind(bridge.current_view, "ship")
	for part: Dictionary in InspectText.flatten(bridge.current_view["units"][ship]["parts"]):
		if part["def"] in ["stub_laser", "stub_solar"]:
			bridge.submit(FittingLogic.detach_command(ship, part["id"], ship))
	ScreenshotDriver._step(bridge)
	main.local_view.select("unit", ship, 0)
	main.toggle_fitting()


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
