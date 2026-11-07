class_name NewStartPlayer extends RefCounted
## D31: plays the new start through research in the real client, pressing only what
## a player can press: the order panel, Jobs and its Build into… picker, Fit, Auto,
## Flight and Research, with the time warp between steps. It follows C16's bot route
## (tests/bot/new_start_bot.gd) stage by stage, each stage starting from the bot's
## snapshot before it. What a player would find awkward goes in `friction`.

const PROBE_NAME := "Probe"
## Warp between steps, as a player would; a test allows a bigger frame budget.
const WARP := 10000
const FRAME_SECONDS := 0.5
const TEST_FRAME_BUDGET_MS := 200.0
const MAX_FRAMES := 400

var main: Node
var bridge: SimBridge
var view: LocalView
var orders: OrderPanel
var industry: IndustryScreen
var fitting: FittingScreen
var flight: FlightScreen
var probe := 0
var station := 0
var frost := 0
var rocks: Dictionary = {}
var problems := PackedStringArray()
## What a player would find awkward, noted once each.
var friction := PackedStringArray()
## Warp drops to 1× that the player had to resume from, by event type.
var drops: Dictionary = {}


## A player on the game saved after `after_stage` (0 for a new game).
func _init(new_main: Node, after_stage: int) -> void:
	main = new_main
	bridge = main.get_node("Bridge")
	view = main.local_view
	orders = main.order_panel
	industry = main.industry_screen
	fitting = main.fitting_screen
	flight = main.flight_screen
	bridge.set_paused(true)
	bridge.frame_budget_ms = TEST_FRAME_BUDGET_MS
	if after_stage > 0:
		var text := FileAccess.get_file_as_string(NewStartBot.snapshot_path(after_stage))
		var sim := Sim.from_save(text) if text != "" else null
		if sim == null:
			problems.append("snapshot after stage %d does not load" % after_stage)
			return
		bridge.start(sim)
		view.rebuild()
	_find()


func _find() -> void:
	var state: Dictionary = bridge.current_view
	for id: int in state["units"]:
		if state["units"][id]["name"] == PROBE_NAME:
			probe = id
		elif state["units"][id]["kind"] == "station":
			station = id
	for id: int in state["bodies"]:
		rocks[state["bodies"][id]["name"]] = id
	frost = rocks.get("Frost", 0)


func unit(id: int) -> Dictionary:
	return bridge.current_view["units"].get(id, {})


func held(id: int, item: String) -> int:
	return int(unit(id).get("inventory", {}).get(item, 0))


func _problem(text: String) -> void:
	problems.append("tick %d: %s" % [bridge.current_view["tick"], text])


func note(text: String) -> void:
	if not friction.has(text):
		friction.append(text)


# --- Time ---

## Warps until `done`, as a player would: at WARP, picking the speed up again after
## each drop to 1× (each one is a press for the player, so they are counted).
func warp_until(done: Callable, label: String, speed := WARP, max_frames := MAX_FRAMES) -> bool:
	print("PLAYER %s from tick %d" % [label, bridge.current_view["tick"]])
	bridge.set_speed(speed)
	bridge.set_paused(false)
	var frames := 0
	var seen := 0
	var collect := func(events: Array[Dictionary]) -> void:
		seen = events.size()
		for event: Dictionary in events:
			if bridge.speed == 1 and WarpLogic.needs_attention([event], bridge.warp_through_jobs, bridge.current_view.get("jobs", {}), bridge.previous_view):
				drops[event["type"]] = int(drops.get(event["type"], 0)) + 1
	bridge.events_received.connect(collect)
	while not done.call() and frames < max_frames:
		if bridge.speed != speed:
			bridge.set_speed(speed)
		bridge.advance(FRAME_SECONDS)
		frames += 1
	bridge.events_received.disconnect(collect)
	bridge.set_paused(true)
	view.refresh(0.016)
	orders.refresh()
	if frames >= max_frames:
		var open := PackedStringArray()
		for id: int in bridge.current_view["jobs"]:
			var job: Dictionary = bridge.current_view["jobs"][id]
			open.append("%s %s %s" % [job["recipe"], job["status"], job["reason"]])
		_problem("timed out: %s; jobs: %s; probe holds %s" % [label, ", ".join(open), str(unit(probe).get("inventory", {}))])
		return false
	return true


func _idle(id: int) -> bool:
	return unit(id).get("op", {}).get("type", "") == "idle" and int(unit(id).get("task", 0)) == 0


# --- Orders ---

func select(kind: String, id: int) -> void:
	view.select(kind, id, 0)
	orders.refresh()


## Gives orders to this unit: a ship by selecting it, a station through Take command.
func take_command(id: int) -> void:
	select("unit", id)
	if view.commanded_unit != id:
		orders.take_command.pressed.emit()
		orders.refresh()


func press(key: String) -> bool:
	if not orders.press(key):
		var why: String = orders.button_for(key).tooltip_text if orders.button_for(key) != null else "not offered"
		_problem("order %s: %s" % [key, why])
		return false
	return true


## One tick at 1×, so a pressed order has started before anything waits on it.
func _kick() -> void:
	bridge.set_speed(1)
	bridge.set_paused(false)
	bridge.advance(0.1)
	bridge.set_paused(true)


## Presses an order and warps until the commanded unit is idle again.
func order(key: String) -> void:
	var id: int = view.commanded_unit
	if press(key):
		_kick()
		warp_until(_idle.bind(id), key)


func fly_to(target_kind: String, target: int) -> void:
	take_command(probe)
	select(target_kind, target)
	order("Move to")


func scan(rock: String) -> void:
	select("body", rocks[rock])
	if not bridge.current_view["bodies"][rocks[rock]].get("scanned", false):
		order("Scan")


func measure(body: int, kind: String) -> void:
	select("body", body)
	order("Measure %s" % kind)


## Mines until the hold holds `target_g` of the item, or until the hold fills for 0:
## the order panel's amount box sets Mine's grams (C19), as a player would.
func mine(rock: String, item: String, target_g: int) -> void:
	select("body", rocks[rock])
	var deposit := 0
	for id: int in bridge.current_view["deposits"]:
		var shown: Dictionary = bridge.current_view["deposits"][id]
		if shown["body"] == rocks[rock] and shown["item"] == item:
			deposit = id
	if deposit == 0:
		_problem("no %s deposit shown on %s" % [item, rock])
		return
	var to_mine := target_g - held(probe, item) if target_g > 0 else 0
	if target_g > 0 and to_mine <= 0:
		return
	orders.amount.value = ceili(to_mine / 1000.0)
	orders.refresh()
	order("Mine %d" % deposit)
	orders.amount.value = 0


func unload(item_name: String, count: int) -> void:
	transfer("Unload", item_name, count)


## Load from the docked host: `count` items, or kilograms of bulk cargo, 0 for all that fits.
func load_from_host(item_name: String, count: int) -> void:
	transfer("Load", item_name, count)


func transfer(verb: String, item_name: String, count: int, id := 0) -> void:
	take_command(id if id != 0 else probe)
	select("", 0)
	orders.amount.value = count
	orders.refresh()
	order("%s %s" % [verb, item_name])
	orders.amount.value = 0


# --- Jobs ---

## Queues runs of a recipe at a facility on `on`, through Jobs; `into` = [unit,
## connector] builds the part there with Build into….
func queue(on: int, facility_type: String, recipe: String, runs: int, into: Array = []) -> void:
	select("unit", on)
	if not industry.visible:
		main.toggle_industry()
	industry.refresh()
	var found := false
	for entry: Dictionary in IndustryLogic.facilities(unit(on), bridge.defs()["modules"]):
		if entry["type"] == facility_type:
			industry.choose_facility(entry)
			found = true
	if not found:
		_problem("no %s on %s" % [facility_type, unit(on).get("name", on)])
		return
	industry.refresh()
	var row := {}
	for candidate: Dictionary in industry._rows:
		if candidate["recipe"]["id"] == recipe:
			row = candidate
	if row.is_empty():
		_problem("no %s row" % recipe)
		return
	if into.is_empty():
		industry._count.value = runs
		(row["start"] as Button).pressed.emit()
	else:
		industry.open_picker(row["recipe"])
		var pressed := false
		# A connector of "" takes the first spot on offer on that unit, as a player would.
		for slot: Dictionary in industry._slot_buttons:
			if pressed or (into[1] == "" and (slot["button"] as Button).disabled):
				continue
			if slot["unit"] == into[0] and (into[1] == "" or slot["slot"]["connector"] == into[1]):
				if (slot["button"] as Button).disabled:
					_problem("Build %s into %s refused: %s" % [recipe, into[1], (slot["button"] as Button).tooltip_text])
				else:
					(slot["button"] as Button).pressed.emit()
					pressed = true
		if not pressed and problems.is_empty():
			_problem("no Build into spot %s for %s" % [into[1], recipe])
	if not industry._message.text.is_empty():
		_problem("%s: %s" % [recipe, industry._message.text])
	main.toggle_industry()
	bridge.set_paused(false)
	bridge.advance(0.1)
	bridge.set_paused(true)


## Warps until no job of these recipes is left (every job, for []).
func wait_jobs(recipes: Array = []) -> void:
	var open := func() -> bool:
		for id: int in bridge.current_view["jobs"]:
			if recipes.is_empty() or recipes.has(bridge.current_view["jobs"][id]["recipe"]):
				return false
		return true
	warp_until(open, "jobs %s" % str(recipes))


# --- Fitting ---

## Fits a part from the docked group's holds onto a unit (the station by default) with
## Fit, on `connector` of the part made from `parent_def` (any, for ""), and returns
## the verdict when it's refused ("" when it fitted).
func fit(item: String, connector: String, on := 0, parent_def := "") -> String:
	select("unit", on if on != 0 else station)
	main.toggle_fitting()
	fitting.refresh()
	var name_text: String = bridge.defs()["modules"][item]["name"]
	var picked := false
	for button: Node in fitting._stock_box.get_children():
		if not picked and button is Button and (button as Button).text.begins_with(name_text):
			(button as Button).pressed.emit()
			picked = true
	if not picked:
		_problem("no %s in Fit's stock" % item)
		main.toggle_fitting()
		return "missing"
	var defs_by_part: Dictionary = {}
	for part: Dictionary in InspectText.flatten(fitting.unit()["parts"]):
		defs_by_part[part["id"]] = part["def"]
	for slot: Dictionary in FittingLogic.free_slots(fitting.unit(), fitting._modules):
		if slot["connector"] == connector and (parent_def == "" or defs_by_part[slot["part"]] == parent_def):
			fitting.choose_slot(slot)
	var refused := ""
	if fitting._attach_button.disabled:
		refused = fitting._verdict.text
	else:
		fitting._attach_button.pressed.emit()
		bridge.set_paused(false)
		bridge.advance(0.1)
		bridge.set_paused(true)
	main.toggle_fitting()
	return refused


# --- The stages, as the bot plays them ---

## Stage 1: the chain to the station.
func stage_chain() -> void:
	fly_to("body", rocks["Red Rock"])
	scan("Red Rock")
	mine("Red Rock", "hematite", 0)
	queue(probe, "refinery", "refine_hematite", 20)
	queue(probe, "fabricator", "structural_frame", 27)
	wait_jobs(["refine_hematite"])
	mine("Red Rock", "hematite", 750_000)
	for trip: Array in [["Brass Rock", "chalcopyrite", 800_000], ["Green Rock", "olivine", 300_000], ["White Rock", "water_ice", 100_000]]:
		fly_to("body", rocks[trip[0]])
		scan(trip[0])
		mine(trip[0], trip[1], trip[2])
	for job: Array in [["refinery", "refine_hematite", 6], ["refinery", "refine_chalcopyrite", 8],
			["refinery", "refine_olivine", 3], ["refinery", "refine_water_ice", 1], ["fabricator", "structural_frame", 8],
			["fabricator", "wiring", 15], ["fabricator", "small_station", 1], ["fabricator", "processor", 4],
			["fabricator", "lidar_mk1", 1], ["fabricator", "solar_panel_mk1", 1]]:
		queue(probe, job[0], job[1], job[2])
	wait_jobs()
	_find()
	if station == 0:
		_problem("no station was built")
		return
	for fix: Array in [["solar_panel_mk1", "side_a_nx"], ["heat_radiator_mk1", "side_a_nz"]]:
		if fit("lidar_mk1", "side_a_px") == "":
			_problem("the station took the LIDAR before %s" % fix[0])
			return
		if held(probe, fix[0]) == 0:
			queue(probe, "fabricator", fix[0], 1)
			wait_jobs()
		if fit(fix[0], fix[1]) != "":
			_problem("%s refused" % fix[0])
	if fit("lidar_mk1", "side_a_px") != "":
		_problem("the LIDAR still refused")
	queue(probe, "fabricator", "ore_container_mk1", 1, [station, "side_a_pz"])
	note("A built station docks at the probe's port, so the dock is the station's: before D31, Unload and Load were offered only on the station.")
	wait_jobs()
	unload(bridge.defs()["items"]["hematite"]["name"], 0)


func _station_part(def: String) -> int:
	for part: Dictionary in InspectText.flatten(unit(station).get("parts", {})):
		if part["def"] == def:
			return part["id"]
	return 0


func _cargo_free(cargo_class: String) -> int:
	var cargo: Dictionary = unit(probe)["cargo"][cargo_class]
	return int(cargo["cap_g"]) - int(cargo["used_g"])


## Stage 2: composition at each rock, everything refined, and the station's core,
## goods container and second solar panel built in place.
func stage_prep() -> void:
	fly_to("body", rocks["Red Rock"])
	measure(rocks["Red Rock"], "composition")
	mine("Red Rock", "hematite", 0)
	queue(probe, "refinery", "refine_hematite", 20)
	queue(probe, "fabricator", "structural_frame", 27)
	queue(probe, "fabricator", "wiring", 30)
	wait_jobs(["refine_hematite"])
	for trip: Array in [["Brass Rock", "chalcopyrite", 1_100_000], ["Green Rock", "olivine", 0]]:
		fly_to("body", rocks[trip[0]])
		measure(rocks[trip[0]], "composition")
		mine(trip[0], trip[1], trip[2])
	var olivine_runs := held(probe, "olivine") / 100_000
	queue(probe, "refinery", "refine_chalcopyrite", 11)
	queue(probe, "refinery", "refine_olivine", olivine_runs)
	queue(probe, "fabricator", "processor", 24)
	queue(probe, "fabricator", "basic_core", 1, [station, "core"])
	queue(probe, "fabricator", "goods_container_mk1", 1, [station, "side_b_nx"])
	queue(probe, "fabricator", "solar_panel_mk1", 1, [station, "side_b_pz"])
	wait_jobs(["refine_olivine"])
	mine("Green Rock", "olivine", (16 - olivine_runs) * 100_000)
	queue(probe, "refinery", "refine_olivine", 16 - olivine_runs)
	wait_jobs(["refine_olivine"])


## Stage 3: the lab built into the station once its second solar panel is on, and the
## station's core assigned through Auto; the processors and cores for research queued.
func stage_lab() -> void:
	wait_jobs(["solar_panel_mk1"])
	queue(probe, "fabricator", "research_lab_mk1", 1, [station, "side_b_px"])
	wait_jobs(["research_lab_mk1"])
	take_command(station)
	main.automation_screen.assign(_station_part("basic_core"))
	_kick()
	if int(unit(station)["core"]) == 0:
		_problem("the station's core was not assigned")
	queue(probe, "fabricator", "processor", 40)
	queue(probe, "fabricator", "basic_core", 2)


## Stage 4 (C18b): Frost's gravity field mapped from the cluster, docked at the station,
## over one lap of the cluster's orbit, warped; the fabricator runs on meanwhile.
func stage_lap() -> void:
	take_command(probe)
	measure(frost, "gravity_field")


## Stage 5: the theory proven at the station's lab, the Assisted Core prototyped on
## the probe and bench-tested at the lab.
func stage_research() -> void:
	wait_jobs()
	var names: Dictionary = bridge.defs()["items"]
	unload(names["processor"]["name"], 10)
	unload(names["wiring"]["name"], 10)
	queue(station, "lab", "prove_autonomous_navigation", 1)
	wait_jobs()
	queue(probe, "fabricator", "prototype:assisted_core", 1)
	wait_jobs()
	unload(names["prototype:assisted_core"]["name"], 1)
	unload(names["processor"]["name"], 10)
	queue(station, "lab", "qualify:assisted_core", 1)
	wait_jobs()


## Stage 6 (C22): ore gathered and refined, the drone's parts and hull built (the hull
## at a free port of the group), fitted from the probe's hold with Fit, its Assisted
## Core assigned in Auto, one lap flown by hand and repeated with Auto, three laps run
## and stopped; then Part F's second ore store built into the station.
const DRONE_ORE := [["Red Rock", "hematite", 900_000, "refine_hematite", 9],
	["Brass Rock", "chalcopyrite", 400_000, "refine_chalcopyrite", 4],
	["Green Rock", "olivine", 200_000, "refine_olivine", 2]]
const DRONE_FIT := [["small_solar_panel_mk1", "side_a_px", ""], ["small_heat_radiator_mk1", "side_a_nx", ""],
	["small_propellant_tank_mk1", "stack_bottom", "small_hull"],
	["small_chemical_thruster_mk1", "stack_bottom", "small_propellant_tank_mk1"],
	["small_ore_container_mk1", "side_a_pz", ""], ["small_mining_laser_mk1", "side_a_nz", ""],
	["small_battery_bank_mk1", "side_b_nx", ""], ["assisted_core", "core", ""]]
const DEPOT_KG := 500
const LAP_KG := 500
const DRONE_LAPS := 3
## The last lap in step mode, so the warp stops within a few ticks of its end, still
## docked; a lap at this speed needs up to LAST_LAP_FRAMES.
const LAST_LAP_SPEED := 4
const LAST_LAP_FRAMES := 1000

var drone := 0
var laps := 0


func stage_drone() -> void:
	var names: Dictionary = bridge.defs()["items"]
	load_from_host(names["hematite"]["name"], 0)
	for trip: Array in DRONE_ORE:
		fly_to("body", rocks[trip[0]])
		mine(trip[0], trip[1], trip[2])
		queue(probe, "refinery", trip[3], trip[4])
	for job: Array in [["structural_frame", 11], ["wiring", 11], ["processor", 14], ["basic_core", 1], ["assisted_core", 1]]:
		queue(probe, "fabricator", job[0], job[1])
	for entry: Array in DRONE_FIT:
		if entry[0] != "assisted_core":
			queue(probe, "fabricator", entry[0], 1)
	queue(probe, "fabricator", "small_craft", 1)
	queue(probe, "fabricator", "propellant_tank_mk1", 1, [station, ""])
	wait_jobs()
	for id: int in bridge.current_view["units"]:
		if unit(id)["kind"] == "drone":
			drone = id
	if drone == 0:
		_problem("no drone was built")
		return
	for entry: Array in DRONE_FIT:
		var refused := fit(entry[0], entry[1], drone, entry[2])
		if refused != "":
			_problem("Fit %s on the drone refused: %s" % [entry[0], refused])
			return
	take_command(drone)
	if not main.automation_screen.visible:
		main.toggle_automation()
	main.automation_screen.refresh()
	for core: Dictionary in CyclePlan.cores(unit(drone), bridge.defs()["modules"]):
		main.automation_screen.assign(core["part"])
	_kick()
	if int(unit(drone)["core_tier"]) < 2:
		_problem("the drone's Assisted Core was not assigned: %s" % main.automation_screen._message.text)
	main.toggle_automation()
	unload(names["propellant"]["name"], DEPOT_KG)
	_fly_drone_lap_by_hand(names)
	_repeat_with_auto()


## The lap a player flies once so Auto can repeat it: fuel, out to Red Rock, mine a
## hold's worth, back, dock and unload.
func _fly_drone_lap_by_hand(names: Dictionary) -> void:
	transfer("Load", names["propellant"]["name"], 0, drone)
	order("Undock")
	select("body", rocks["Red Rock"])
	order("Move to")
	var deposit := 0
	for id: int in bridge.current_view["deposits"]:
		var shown: Dictionary = bridge.current_view["deposits"][id]
		if shown["body"] == rocks["Red Rock"] and shown["item"] == "hematite":
			deposit = id
	orders.amount.value = LAP_KG
	orders.refresh()
	order("Mine %d" % deposit)
	orders.amount.value = 0
	select("unit", station)
	order("Move to")
	select("unit", station)
	order("Dock")
	transfer("Unload", names["hematite"]["name"], 0, drone)


## Auto's Repeat this route, three laps warped, then Stop cycle while docked.
func _repeat_with_auto() -> void:
	take_command(drone)
	main.toggle_automation()
	main.automation_screen.refresh()
	main.automation_screen.repeat_route()
	_kick()
	main.toggle_automation()
	if CyclePlan.running_cycle(unit(drone), bridge.current_view).is_empty():
		_problem("Repeat this route did not start a cycle: %s" % main.automation_screen._message.text)
		return
	var count := func(events: Array[Dictionary]) -> void:
		for event: Dictionary in events:
			if event["unit"] == drone and event["type"] == "task_cycle_done":
				laps += 1
			if event["unit"] == drone and ["task_blocked", "task_cancelled"].has(event["type"]):
				_problem("the drone's cycle %s: %s" % [event["type"], event["data"].get("reason", "")])
	bridge.events_received.connect(count)
	warp_until(func() -> bool: return laps >= DRONE_LAPS - 1 or not problems.is_empty(), "drone laps")
	warp_until(func() -> bool: return laps >= DRONE_LAPS or not problems.is_empty(), "last lap", LAST_LAP_SPEED, LAST_LAP_FRAMES)
	bridge.events_received.disconnect(count)
	take_command(drone)
	select("", 0)
	press("Stop")
	_kick()


## Part F: ore from the station refined into a second ore store, built into the station.
func stage_part_f() -> void:
	var names: Dictionary = bridge.defs()["items"]
	load_from_host(names["hematite"]["name"], 500)
	queue(probe, "refinery", "refine_hematite", 5)
	queue(probe, "fabricator", "structural_frame", 6)
	queue(probe, "fabricator", "ore_container_mk1", 1, [station, ""])
	wait_jobs()
