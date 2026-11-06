class_name NewStartBot
extends RefCounted
## Plays new_start.json through the public API as far as the game goes before research (C14): the
## probe alone scans and mines the cluster's rocks, refines on board, builds a small station
## docked at itself, fits it through a refused fit, and hauls ore into it. Each step starts when
## the one before has ended. IDs come from the start state, events and the view. It records
## steps and marks, so tests assert on one shared run and B gets the chain's timings.

const SCENARIO := "new_start"
const SEED := 12345
## Starting IDs, which new_start.json fixes. They are checked against the names at the start.
const PROBE := 13
const RED_ROCK := 4
const BRASS_ROCK := 6
const GREEN_ROCK := 8
const WHITE_ROCK := 10
## How much longer than planned a step may run before the bot gives up.
const ORDER_LIMIT_TICKS := 6000
const RANGE_CHECK_TICKS := 100
const WAIT_LIMIT_TICKS := 100_000
## Pauses a queued job may take: waiting for another job's output, a short power shed, or a full
## hold until the station is built and takes its goods.
const ALLOWED_PAUSES: Array[String] = ["missing_inputs", "no_power", "output_full"]
## Ore mined on the second trip, in grams, beyond the first trip's full hold of hematite.
## 600 kg of that hematite is refined; the other 150 kg is hauled into the station. It all fits
## the probe's 2 t ore hold with room for the mining stop's overshoot.
const SECOND_TRIP_G := {
	"hematite": 750_000, "chalcopyrite": 800_000, "olivine": 300_000, "water_ice": 100_000,
}
## Propellant from one run of refine_water_ice.
const ICE_RUN_PROPELLANT_G := 90_000
## Holds of ice mined at most to top up the tank before Frost.
const ICE_HOLDS := 2
## Olivine refined in stage 2, for the research route's processors and solar panel.
const OLIVINE_RUNS := 16
## Runs of each refining recipe, sized to the parts below.
const REFINE_RUNS := {
	"refine_hematite": 26, "refine_chalcopyrite": 8, "refine_olivine": 3, "refine_water_ice": 1,
}

## The stages after the chain to the station (C16), each a slow test file of its own, run in order
## on one shared game: research prep, the Frost trip, research.
const STAGE_CHAIN := 1
const STAGE_PREP := 2
const STAGE_LAB := 3
const STAGE_FROST_DOWN := 4
const STAGE_FROST_LAP := 5
const STAGE_RETURN := 6
const STAGE_RESEARCH := 7
const FROST := 3
## The low orbit the gravity field is mapped from, just above the low-flight band.
const LAP_ALTITUDE_MM := 35_000_000
## Leaving the cluster: a small retrograde burn drops the probe onto an orbit round Frost.
const LEAVE_BURN_UM_S := -20_000_000
const FLIGHT_LIMIT_TICKS := 200_000
## Waiting on jobs steps this many ticks between looks, as a player at speed would.
const WAIT_BATCH_TICKS := 10

## Each slow file starts from the game saved at the end of the stage before it, so no file replays
## earlier stages. tests/bot/new_start_snapshots.gd writes them; a file whose stage no longer ends
## in its committed snapshot fails, and says to regenerate.
const SNAPSHOT_DIR := "res://tests/slow/new_start/"
const REGENERATE := "regenerate with: godot --headless --path . -s tests/bot/new_start_snapshots.gd"

var sim: Sim
var events: Array[Dictionary] = []
## Every step as { label, start_tick, ticks }.
var steps: Array[Dictionary] = []
## Views taken at named points.
var marks := {}
var problems := PackedStringArray()
var ledger_problems := PackedStringArray()
var range_problems := PackedStringArray()
## Refusals the bot meant to provoke, as { item, reason }.
var refused_fits: Array[Dictionary] = []
var deposits := {}
var refinery := 0
var fabricator := 0
var laser := 0
var station := 0
var station_hub := 0
var station_core := 0
var lab := 0
## The last stage run.
var stage := 0
## Queued jobs by command ID until job_queued names them, then by job ID until their last run.
var _pending_commands := {}
## The last hundred-tick block whose state ranges were checked.
var _range_checked := 0
var _jobs := {}


static func snapshot_path(after_stage: int) -> String:
	return SNAPSHOT_DIR + "stage_%d.save" % after_stage


## A bot on the game saved after `after_stage`, its IDs and open jobs found again from the state. A
## missing or stale snapshot leaves a problem saying so.
static func from_snapshot(after_stage: int) -> NewStartBot:
	var bot := NewStartBot.new()
	var text := FileAccess.get_file_as_string(snapshot_path(after_stage))
	bot.sim = Sim.from_save(text) if text != "" else null
	if bot.sim == null:
		bot.problems.append("snapshot after stage %d does not load (%s); %s" % [after_stage,
			Sim.last_error() if text != "" else "missing", REGENERATE])
		return bot
	bot.stage = after_stage
	bot._range_checked = bot.sim.current_tick() / RANGE_CHECK_TICKS
	bot._find_start()
	bot._find_station()
	for id: int in bot.sim._state["jobs"].keys():
		var job: Dictionary = bot.sim._state["jobs"][id]
		bot._jobs[id] = { "recipe": job["recipe"], "left": job["count_left"] }
	return bot


## Plays stages after the bot's last one, through `last`.
func play_through(last: int) -> void:
	while stage < last and problems.is_empty():
		stage += 1
		match stage:
			STAGE_CHAIN:
				run()
			STAGE_PREP:
				_prepare_research()
			STAGE_LAB:
				_build_lab()
			STAGE_FROST_DOWN:
				_frost_down()
			STAGE_FROST_LAP:
				_frost_lap()
			STAGE_RETURN:
				_return_home()
			STAGE_RESEARCH:
				_research()


## "" if the game is where the committed snapshot after `after_stage` says, otherwise why not.
func snapshot_mismatch(after_stage: int) -> String:
	var text := FileAccess.get_file_as_string(snapshot_path(after_stage))
	var saved := Sim.from_save(text) if text != "" else null
	if saved == null:
		return "snapshot after stage %d does not load; %s" % [after_stage, REGENERATE]
	if saved.state_hash() != sim.state_hash():
		return "the game after stage %d is not its snapshot; %s" % [after_stage, REGENERATE]
	return ""


## Stage 1, the chain to the station, from a new game.
func run() -> void:
	stage = STAGE_CHAIN
	sim = Sim.new_game(SCENARIO, SEED)
	if sim == null:
		problems.append("new_start did not load: %s" % Sim.last_error())
		return
	_find_start()
	if not problems.is_empty():
		return
	_first_trip()
	_queue([[refinery, "refine_hematite", 20], [fabricator, "structural_frame", 27]])
	_wait_for(["refine_hematite"])
	mark("refined")
	_second_trip()
	marks["tank_free_g_before_ice"] = _cargo("propellant")["cap_g"] - _cargo("propellant")["used_g"]
	_queue([
		[refinery, "refine_hematite", REFINE_RUNS["refine_hematite"] - 20],
		[refinery, "refine_chalcopyrite", REFINE_RUNS["refine_chalcopyrite"]],
		[refinery, "refine_olivine", REFINE_RUNS["refine_olivine"]],
		[refinery, "refine_water_ice", REFINE_RUNS["refine_water_ice"]],
		# The station takes only frames and wiring, and building it empties most of the goods hold,
		# so it goes before the processors, whose silicon the refinery can't store until then.
		[fabricator, "structural_frame", 8], [fabricator, "wiring", 15], [fabricator, "small_station", 1],
		[fabricator, "processor", 4], [fabricator, "lidar_mk1", 1], [fabricator, "solar_panel_mk1", 1],
	])
	_wait_for(["refine_water_ice"])
	mark("ice_refined")
	_wait_for([])
	_find_station()
	_fit_station()
	_haul()
	mark("end")


## Finds the probe's facilities and laser and each rock's deposit, by definition and name.
func _find_start() -> void:
	var state := sim._state
	for rock: int in [RED_ROCK, BRASS_ROCK, GREEN_ROCK, WHITE_ROCK]:
		for deposit: int in state["bodies"][rock]["deposits"]:
			deposits[state["deposits"][deposit]["item"]] = deposit
	if state["units"].get(PROBE, {}).get("name", "") != "Probe":
		problems.append("unit %d is not the probe" % PROBE)
		return
	for part: int in Units.sorted_part_ids(state, PROBE):
		var capabilities: Dictionary = Units.module_of(state, sim.defs(), part)["capabilities"]
		match capabilities.get("facility", {}).get("type", ""):
			"refinery":
				refinery = part
			"fabricator":
				fabricator = part
		if capabilities.has("mine"):
			laser = part
	for item in ["hematite", "chalcopyrite", "olivine", "water_ice"]:
		if not deposits.has(item):
			problems.append("no %s deposit" % item)
	if refinery == 0 or fabricator == 0 or laser == 0:
		problems.append("the probe lacks a refinery, fabricator or laser")
	mark("start")


## A full hold of hematite from Red Rock.
func _first_trip() -> void:
	_order("move_to", PROBE, { "target": RED_ROCK })
	_order("scan", PROBE, { "target": RED_ROCK })
	mark("scanned")
	_mine("hematite", 0)
	mark("mined")


## A mixed hold: the rest of the hematite, then the other three rocks, while the fabricator works.
func _second_trip() -> void:
	_mine("hematite", SECOND_TRIP_G["hematite"])
	for rock_and_item: Array in [[BRASS_ROCK, "chalcopyrite"], [GREEN_ROCK, "olivine"], [WHITE_ROCK, "water_ice"]]:
		_order("move_to", PROBE, { "target": rock_and_item[0] })
		_order("scan", PROBE, { "target": rock_and_item[0] })
		_mine(rock_and_item[1], SECOND_TRIP_G[rock_and_item[1]])
	mark("prospected")


func _find_station() -> void:
	if not problems.is_empty():
		return
	for id: int in _sorted_ids(sim._state["units"]):
		if sim._state["units"][id]["kind"] == "station":
			station = id
	if station == 0:
		if stage == STAGE_CHAIN:
			problems.append("no station was built")
		return
	station_hub = sim._state["units"][station]["root"]
	station_core = sim._state["units"][station]["core"]
	if stage == STAGE_CHAIN:
		mark("station_built")


static func _sorted_ids(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids


## Fits the station from the probe's hold, as a player learns its limits: the bare station refuses
## the LIDAR for power, then with a solar panel for heat, and takes it once a radiator is on. Each
## fix is fitted as soon as it is made, since parts are bulky in the probe's goods hold. Then an ore
## container, made once the hold has room.
func _fit_station() -> void:
	if not problems.is_empty():
		return
	for fix: Array in [["solar_panel_mk1", "side_a_nx"], ["heat_radiator_mk1", "side_a_nz"]]:
		var refusal := _attach_refused(station, "lidar_mk1", station_hub, "side_a_px")
		if refusal == "":
			problems.append("the station took the LIDAR before %s" % fix[0])
			return
		refused_fits.append({ "item": "lidar_mk1", "reason": refusal })
		mark("fit_failed")
		if sim._state["units"][PROBE]["inventory"].get(fix[0], 0) == 0:
			_queue([[fabricator, fix[0], 1]])
			_wait_for([])
		_attach(station, fix[0], station_hub, fix[1])
	_attach(station, "lidar_mk1", station_hub, "side_a_px")
	mark("fit_fixed")
	# Built in place (C15): at 6000 L, ore_container_mk1 could never pass through the probe's
	# 4000 L goods hold.
	_queue([[fabricator, "ore_container_mk1", 1, _on_station("side_a_pz")]])
	_wait_for([])


## Stage 2: two more trips for the research route's goods, with composition measured at each rock,
## all of it refined, and the station given a core, a goods container and a second solar panel, each
## built in place. The fabricator runs on into stage 3.
func _prepare_research() -> void:
	_order("move_to", PROBE, { "target": RED_ROCK })
	_order("measure", PROBE, { "target": RED_ROCK, "kind": "composition" })
	_mine("hematite", 0)
	_queue([[refinery, "refine_hematite", 20], [fabricator, "structural_frame", 27], [fabricator, "wiring", 30]])
	_wait_for(["refine_hematite"])
	mark("prep_refined")
	for rock_and_item: Array in [[BRASS_ROCK, "chalcopyrite", 1_100_000], [GREEN_ROCK, "olivine", 0]]:
		_order("move_to", PROBE, { "target": rock_and_item[0] })
		_order("measure", PROBE, { "target": rock_and_item[0], "kind": "composition" })
		_mine(rock_and_item[1], rock_and_item[2])
	var olivine_runs: int = sim._state["units"][PROBE]["inventory"].get("olivine", 0) / 100_000
	_queue([
		[refinery, "refine_chalcopyrite", 11], [refinery, "refine_olivine", olivine_runs],
		[fabricator, "processor", 24], [fabricator, "basic_core", 1, _on_station("core")],
		[fabricator, "goods_container_mk1", 1, _on_station("side_b_nx")],
		[fabricator, "solar_panel_mk1", 1, _on_station("side_b_pz")],
	])
	_wait_for(["refine_olivine"])
	_mine("olivine", (OLIVINE_RUNS - olivine_runs) * 100_000)
	_queue([[refinery, "refine_olivine", OLIVINE_RUNS - olivine_runs]])
	_wait_for(["refine_olivine"])
	mark("prep_done")


## Stage 3: once the second solar panel is on, the lab, too big for any hold, is built in place, and
## the station's core assigned. Then the processors and cores for the test, the prototype and the
## bench test are queued, to run on through the Frost trip.
func _build_lab() -> void:
	# A full tank for Frost: landing from the cluster's orbit costs about 900 kg and the climb back
	# to a low orbit about 620, so the probe tops up from White Rock's ice first. Ice is bulky: about
	# 690 kg fills the ore hold's 750 L, so it takes holds until the tank is nearly full.
	_order("move_to", PROBE, { "target": WHITE_ROCK })
	for i in ICE_HOLDS:
		var free_g: int = _cargo("propellant")["cap_g"] - _cargo("propellant")["used_g"]
		if free_g < ICE_RUN_PROPELLANT_G:
			break
		_mine("water_ice", 0)
		var held_g: int = sim._state["units"][PROBE]["inventory"].get("water_ice", 0)
		var runs := mini(free_g / ICE_RUN_PROPELLANT_G, held_g / 100_000)
		_queue([[refinery, "refine_water_ice", runs]])
		_wait_for(["refine_water_ice"])
	mark("tank_topped_up")
	_wait_for(["solar_panel_mk1"])
	_queue([[fabricator, "research_lab_mk1", 1, _on_station("side_b_px")]])
	_wait_for(["research_lab_mk1"])
	if not problems.is_empty():
		return
	station_core = Units.child_at(sim._state, station_hub, "core")
	_command("assign_core", station, { "core": station_core })
	_step()
	_queue([[fabricator, "processor", 40], [fabricator, "basic_core", 2]])
	mark("research_ready")


## Stage 4: the station undocks to stay in the cluster, and the probe burns out of it onto an orbit
## round Frost, lands and takes a surface sample. Its fabricator runs on throughout.
func _frost_down() -> void:
	_order("undock", station, {})
	mark("station_undocked")
	_order("move_to", PROBE, { "target": RED_ROCK })
	if not problems.is_empty():
		return
	_command("plan_burn", PROBE, { "tick": sim.current_tick() + 1, "prograde_um_s": LEAVE_BURN_UM_S,
		"normal_um_s": 0, "radial_um_s": 0 })
	_until("burn_done", PROBE, 1000)
	if sim._state["units"][PROBE]["orbit"].get("parent", 0) != FROST:
		problems.append("the burn did not leave the probe on an orbit round Frost")
		return
	mark("left_cluster")
	var cell := LandingSystem.cell_below(sim._ctx, FROST, sim._state["units"][PROBE]["pos_mm"])
	var land := { "type": "land", "unit": PROBE, "args": { "body": FROST, "cell": cell } }
	var checked := sim.check(land)
	if not checked["ok"]:
		problems.append("land refused: %s" % checked["reason"])
		return
	_command("land", PROBE, land["args"])
	_until("landed", PROBE, checked["detail"]["ticks"] + 1000, WAIT_BATCH_TICKS)
	mark("landed")
	_order("measure", PROBE, { "target": FROST, "kind": "surface" })
	mark("sampled")


## Stage 5: up to a low orbit, and one lap of it to map Frost's gravity field.
func _frost_lap() -> void:
	var take_off := { "type": "take_off", "unit": PROBE, "args": { "altitude_mm": LAP_ALTITUDE_MM } }
	var checked := sim.check(take_off)
	if not checked["ok"]:
		problems.append("take_off refused: %s %s" % [checked["reason"], str(checked["detail"])])
		return
	marks["take_off_quote"] = checked["detail"]
	_command("take_off", PROBE, take_off["args"])
	_until("took_off", PROBE, FLIGHT_LIMIT_TICKS, WAIT_BATCH_TICKS)
	mark("low_orbit")
	_order("measure", PROBE, { "target": FROST, "kind": "gravity_field" }, FLIGHT_LIMIT_TICKS, WAIT_BATCH_TICKS)
	mark("gravity_mapped")


## Stage 6: back to the station in the cluster, and docked at the port it left from.
func _return_home() -> void:
	_order("move_to", PROBE, { "target": station }, FLIGHT_LIMIT_TICKS, WAIT_BATCH_TICKS)
	_order("dock", PROBE, { "port": _probe_port(), "target_port": _free_station_port() })
	mark("home")


## Stage 7: the theory proven at the station's lab, then the Assisted Core prototyped on the probe
## and bench-tested at the lab, as research.md section 5 lays out.
func _research() -> void:
	for part: int in Units.sorted_part_ids(sim._state, station):
		if sim._state["parts"][part]["def"] == "research_lab_mk1":
			lab = part
	_wait_for([])
	_unload_to_station({ "processor": 10, "wiring": 10 })
	_queue_on(station, [[lab, "prove_autonomous_navigation", 1]])
	_wait_for([])
	mark("proven")
	_queue([[fabricator, "prototype:assisted_core", 1]])
	_wait_for([])
	mark("prototyped")
	_unload_to_station({ "prototype:assisted_core": 1, "processor": 10 })
	_queue_on(station, [[lab, "qualify:assisted_core", 1]])
	_wait_for([])
	mark("qualified")


## Moves whole items from the probe's hold into the station's, by count.
func _unload_to_station(counts: Dictionary) -> void:
	var items: Array = counts.keys()
	items.sort()
	for item: String in items:
		var grams: int = counts[item] * sim.defs()["items"][item]["unit_mass_g"]
		_order("unload_cargo", PROBE, { "to": station, "item": item, "grams": grams })


func _free_station_port() -> int:
	for port: int in Units.ports(sim._state, sim.defs(), station):
		if not Units.port_in_use(sim._state, port):
			return port
	return 0


func _probe_port() -> int:
	return Units.ports(sim._state, sim.defs(), PROBE)[0]


## Steps until `type` happens to `unit`, or the limit. A crash is a problem.
func _until(type: String, unit: int, limit: int, batch: int = 1) -> Dictionary:
	for i in limit / batch:
		if not problems.is_empty():
			return {}
		for event in _step(batch):
			if event["unit"] != unit:
				continue
			if event["type"] == type:
				return event
			if event["type"] in ["crashed", "burn_short"]:
				problems.append("%s while waiting for %s" % [event["type"], type])
				return {}
	problems.append("no %s within %d ticks" % [type, limit])
	return {}


func _haul() -> void:
	_order("unload_cargo", PROBE, { "to": station, "item": "hematite" })
	mark("hauled")


func mark(label: String) -> void:
	marks[label] = sim.view()


## Lines for B's chain figures: each step since `from_tick`, then the probe at each named mark.
func report(from_tick: int, labels: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	for step: Dictionary in steps:
		if step["start_tick"] >= from_tick:
			lines.append("  %s: %d ticks from %d" % [step["label"], step["ticks"], step["start_tick"]])
	for label: String in labels:
		if marks.has(label):
			var view: Dictionary = marks[label]
			var cargo: Dictionary = view["units"][PROBE]["cargo"]
			lines.append("  %s: tick %d, propellant %d kg, ore %d kg, goods %d kg, points %d, spent %d" % [label,
				view["tick"], cargo["propellant"]["used_g"] / 1000, cargo["ore"]["used_g"] / 1000,
				cargo["goods"]["used_g"] / 1000, view["science"]["points"], view["science"]["spent"]])
	return lines


func last_event(type: String) -> Dictionary:
	for i in range(events.size() - 1, -1, -1):
		if events[i]["type"] == type:
			return events[i]
	return {}


func events_of(type: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in events:
		if event["type"] == type:
			found.append(event)
	return found


func total_ticks() -> int:
	return sim.current_tick()


func _cargo(cargo_class: String) -> Dictionary:
	return sim.view()["units"][PROBE]["cargo"][cargo_class]


## Mines `item` until the hold holds `target_g` of it, or until the hold is full when 0.
func _mine(item: String, target_g: int) -> void:
	if not problems.is_empty():
		return
	var id := _command("start_mining", PROBE, { "deposit": deposits[item], "module": laser })
	var start := sim.current_tick() + 1
	var task := 0
	var stopping := false
	for i in ORDER_LIMIT_TICKS:
		for event in _step():
			var data: Dictionary = event["data"]
			match event["type"]:
				"command_rejected":
					if data["command"] == id:
						problems.append("mining %s refused: %s" % [item, data["reason"]])
						return
				"task_started":
					if data["command"] == id:
						task = data["task"]
				"task_cancelled":
					if data["task"] == task:
						if not stopping:
							problems.append("mining %s cancelled: %s" % [item, data["reason"]])
						else:
							_record("mine " + item, start)
						return
				"task_finished":
					if data["task"] == task:
						_record("mine " + item, start)
						return
		var held: int = sim._state["units"][PROBE]["inventory"].get(item, 0)
		if target_g > 0 and held >= target_g and not stopping:
			stopping = true
			_command("stop", PROBE, {})
	problems.append("mining %s never finished" % item)


## Gives an order and steps until its task ends, `batch` ticks at a time for a long one.
func _order(type: String, unit: int, args: Dictionary, limit: int = ORDER_LIMIT_TICKS, batch: int = 1) -> void:
	if not problems.is_empty():
		return
	var id := _command(type, unit, args)
	var start := sim.current_tick() + 1
	var task := 0
	for i in limit / batch:
		for event in _step(batch):
			var data: Dictionary = event["data"]
			match event["type"]:
				"command_rejected":
					if data["command"] == id:
						problems.append("%s refused: %s" % [type, data["reason"]])
						return
				"task_started":
					if data["command"] == id:
						task = data["task"]
				"task_cancelled":
					if data["task"] == task:
						problems.append("%s cancelled: %s" % [type, data["reason"]])
						return
				"task_finished":
					if data["task"] == task:
						_record(type, start)
						return
	problems.append("%s never finished" % type)


## Where a part is built in place on the station's hub (C15).
func _on_station(connector: String) -> Dictionary:
	return { "unit": station, "parent_part": station_hub, "parent_connector": connector, "part_connector": "mount" }


## Queues jobs on the probe's facilities, each as [facility, recipe, count] or with a fourth
## element, where to build the part in place, in order. A job that
## waits for inputs another job is making is the plan, not a problem.
func _queue(jobs: Array) -> void:
	_queue_on(PROBE, jobs)


## As _queue, for the facilities of another unit, such as the station's lab.
func _queue_on(unit: int, jobs: Array) -> void:
	for entry: Array in jobs:
		if not problems.is_empty():
			return
		var args := { "facility": entry[0], "recipe": entry[1], "count": entry[2] }
		if entry.size() > 3:
			args["install_to"] = entry[3]
		var id := _command("queue_job", unit, args)
		_pending_commands[id] = { "recipe": entry[1], "left": entry[2] }


## Steps until every queued job of these recipes has finished, or every queued job if [].
func _wait_for(recipes: Array) -> void:
	for i in WAIT_LIMIT_TICKS / WAIT_BATCH_TICKS:
		if not problems.is_empty() or not _is_waiting_for(recipes):
			return
		_step(WAIT_BATCH_TICKS)
	var open := PackedStringArray()
	for job: Dictionary in sim._state["jobs"].values():
		open.append("%s %s %s" % [job["recipe"], job["status"], job["reason"]])
	problems.append("jobs never finished: %s; open: %s" % [str(_open_recipes()), ", ".join(open)])


func _is_waiting_for(recipes: Array) -> bool:
	for recipe: String in _open_recipes():
		if recipes.is_empty() or recipes.has(recipe):
			return true
	return false


func _open_recipes() -> Array:
	var open := []
	for table: Dictionary in [_pending_commands, _jobs]:
		var keys: Array = table.keys()
		keys.sort()
		for key: int in keys:
			open.append(table[key]["recipe"])
	return open


func _on_job_event(event: Dictionary) -> void:
	var data: Dictionary = event["data"]
	match event["type"]:
		"command_rejected":
			if _pending_commands.has(data["command"]):
				problems.append("%s refused: %s" % [_pending_commands[data["command"]]["recipe"], data["reason"]])
				_pending_commands.erase(data["command"])
		"job_queued":
			if _pending_commands.has(data["command"]):
				_jobs[data["job"]] = _pending_commands[data["command"]]
				_pending_commands.erase(data["command"])
		"job_started":
			if _jobs.has(data["job"]):
				_jobs[data["job"]]["start"] = event["tick"]
		"job_paused":
			if _jobs.has(data["job"]) and not ALLOWED_PAUSES.has(data["reason"]):
				problems.append("%s paused: %s" % [_jobs[data["job"]]["recipe"], data["reason"]])
		"job_finished":
			if _jobs.has(data["job"]):
				var job: Dictionary = _jobs[data["job"]]
				job["left"] -= 1
				if job["left"] == 0:
					var start: int = job.get("start", event["tick"])
					steps.append({ "label": job["recipe"], "start_tick": start, "ticks": event["tick"] - start + 1 })
					_jobs.erase(data["job"])


## Attaches a part from the probe's hold, which must fit, and returns its ID.
func _attach(unit: int, item: String, parent: int, connector: String) -> int:
	if not problems.is_empty():
		return 0
	var id := _command("attach_part", unit, _attach_args(item, parent, connector))
	for event in _step():
		if event["type"] == "part_attached":
			return event["data"]["part"]
		if _is_refusal(event, id):
			problems.append("%s refused: %s" % [item, event["data"]["reason"]])
	return 0


## Attaches a part that should be refused, and returns the reason, or "" if it fitted.
func _attach_refused(unit: int, item: String, parent: int, connector: String) -> String:
	var id := _command("attach_part", unit, _attach_args(item, parent, connector))
	for event in _step():
		if _is_refusal(event, id):
			return event["data"]["reason"]
	return ""


## attach_part reports a refusal as attach_failed, with the command's ID like command_rejected.
func _is_refusal(event: Dictionary, id: int) -> bool:
	return event["type"] in ["command_rejected", FittingSystem.FAILED_EVENT] and event["data"]["command"] == id


func _attach_args(item: String, parent: int, connector: String) -> Dictionary:
	return {
		"item": item, "from": PROBE, "parent_part": parent,
		"parent_connector": connector, "part_connector": "mount",
	}


func _record(label: String, start: int) -> void:
	steps.append({ "label": label, "start_tick": start, "ticks": sim.current_tick() - start + 1 })


func _command(type: String, unit: int, args: Dictionary) -> int:
	return sim.submit({ "type": type, "unit": unit, "args": args })


func _step(ticks: int = 1) -> Array[Dictionary]:
	sim.step(ticks)
	var new_events := sim.take_events()
	events.append_array(new_events)
	for event in new_events:
		_on_job_event(event)
	_check_ledgers(sim.ledger())
	if sim.current_tick() / RANGE_CHECK_TICKS != _range_checked:
		_range_checked = sim.current_tick() / RANGE_CHECK_TICKS
		range_problems.append_array(Invariants.violations(sim._state))
	return new_events


func _check_ledgers(ledger: Dictionary) -> void:
	var tick := sim.current_tick()
	var matter: Dictionary = ledger["matter"]
	if matter["total_g"] != matter["start_g"]:
		_ledger_problem("tick %d: matter %d of %d" % [tick, matter["total_g"], matter["start_g"]])
	var energy: Dictionary = ledger["energy"]
	for unit: int in energy:
		var flow: Dictionary = energy[unit]
		if flow["generated_w"] + flow["discharged_w"] \
				!= flow["consumed_w"] + flow["charged_w"] + flow["curtailed_w"]:
			_ledger_problem("tick %d: unit %d energy" % [tick, unit])
	var heat: Dictionary = ledger["heat"]
	for unit: int in heat:
		var loop: Dictionary = heat[unit]
		if loop["after_j"] - loop["before_j"] != loop["added_j"] - loop["rejected_j"]:
			_ledger_problem("tick %d: unit %d heat" % [tick, unit])
	if ledger["violations"].size() > 0:
		_ledger_problem("tick %d: %s" % [tick, ledger["violations"][0]])


func _ledger_problem(text: String) -> void:
	if ledger_problems.size() < 10:
		ledger_problems.append(text)
