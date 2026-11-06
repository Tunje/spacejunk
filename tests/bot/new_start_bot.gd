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
const WAIT_LIMIT_TICKS := 200_000
## Pauses a queued job may take: waiting for another job's output, or a short power shed.
const ALLOWED_PAUSES: Array[String] = ["missing_inputs", "no_power"]
## Ore mined on the second trip, in grams, beyond the first trip's full hold of hematite.
## 400 kg of that hematite is refined; the other 300 kg is hauled into the station.
const SECOND_TRIP_G := {
	"hematite": 700_000, "chalcopyrite": 500_000, "olivine": 300_000, "water_ice": 200_000,
}
## Runs of each refining recipe, sized to the parts below.
const REFINE_RUNS := {
	"refine_hematite": 24, "refine_chalcopyrite": 5, "refine_olivine": 3, "refine_water_ice": 2,
}

static var _shared: NewStartBot

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
## Queued jobs by command ID until job_queued names them, then by job ID until their last run.
var _pending_commands := {}
var _jobs := {}


static func shared() -> NewStartBot:
	if _shared == null:
		_shared = NewStartBot.new()
		_shared.run()
	return _shared


func run() -> void:
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
		[fabricator, "structural_frame", 6], [fabricator, "wiring", 15], [fabricator, "processor", 4],
		[fabricator, "small_station", 1], [fabricator, "lidar_mk1", 1], [fabricator, "solar_panel_mk1", 1],
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
	var created := last_event("unit_created")
	if created.is_empty() or created["data"]["def"] != "small_station":
		problems.append("no station was built")
		return
	station = created["data"]["unit"]
	station_hub = sim.view()["units"][station]["parts"]["id"]
	mark("station_built")


## Fits the station from the probe's hold: the LIDAR first, which the unpowered station refuses,
## then a solar panel, then the LIDAR again. Then an ore container, made once the hold has room.
func _fit_station() -> void:
	if not problems.is_empty():
		return
	var refusal := _attach_refused(station, "lidar_mk1", station_hub, "side_a_px")
	if refusal == "":
		problems.append("the unpowered station took the LIDAR")
		return
	refused_fits.append({ "item": "lidar_mk1", "reason": refusal })
	mark("fit_failed")
	_attach(station, "solar_panel_mk1", station_hub, "side_a_nx")
	_attach(station, "lidar_mk1", station_hub, "side_a_px")
	mark("fit_fixed")
	_queue([[fabricator, "ore_container_mk1", 1]])
	_wait_for([])
	_attach(station, "ore_container_mk1", station_hub, "side_a_pz")


func _haul() -> void:
	_order("unload_cargo", PROBE, { "to": station, "item": "hematite" })
	mark("hauled")


func mark(label: String) -> void:
	marks[label] = sim.view()


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


## Gives an order and steps until its task ends.
func _order(type: String, unit: int, args: Dictionary) -> void:
	if not problems.is_empty():
		return
	var id := _command(type, unit, args)
	var start := sim.current_tick() + 1
	var task := 0
	for i in ORDER_LIMIT_TICKS:
		for event in _step():
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


## Queues jobs on the probe's facilities, each as [facility, recipe, count], in order. A job that
## waits for inputs another job is making is the plan, not a problem.
func _queue(jobs: Array) -> void:
	for entry: Array in jobs:
		if not problems.is_empty():
			return
		var id := _command("queue_job", PROBE, { "facility": entry[0], "recipe": entry[1], "count": entry[2] })
		_pending_commands[id] = { "recipe": entry[1], "left": entry[2] }


## Steps until every queued job of these recipes has finished, or every queued job if [].
func _wait_for(recipes: Array) -> void:
	for i in WAIT_LIMIT_TICKS:
		if not problems.is_empty() or not _is_waiting_for(recipes):
			return
		_step()
	problems.append("jobs never finished: %s" % str(_open_recipes()))


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
		if event["type"] == "command_rejected" and event["data"]["command"] == id:
			problems.append("%s refused: %s" % [item, event["data"]["reason"]])
	return 0


## Attaches a part that should be refused, and returns the reason, or "" if it fitted.
func _attach_refused(unit: int, item: String, parent: int, connector: String) -> String:
	var id := _command("attach_part", unit, _attach_args(item, parent, connector))
	for event in _step():
		if event["type"] == "command_rejected" and event["data"]["command"] == id:
			return event["data"]["reason"]
	return ""


func _attach_args(item: String, parent: int, connector: String) -> Dictionary:
	return {
		"item": item, "from": PROBE, "parent_part": parent,
		"parent_connector": connector, "part_connector": "mount",
	}


func _record(label: String, start: int) -> void:
	steps.append({ "label": label, "start_tick": start, "ticks": sim.current_tick() - start + 1 })


func _command(type: String, unit: int, args: Dictionary) -> int:
	return sim.submit({ "type": type, "unit": unit, "args": args })


func _step() -> Array[Dictionary]:
	sim.step()
	var new_events := sim.take_events()
	events.append_array(new_events)
	for event in new_events:
		_on_job_event(event)
	_check_ledgers(sim.ledger())
	if sim.current_tick() % RANGE_CHECK_TICKS == 0:
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
