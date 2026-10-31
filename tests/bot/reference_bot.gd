class_name ReferenceBot
extends RefCounted
## Plays the reference scenario through the public API, as a player would: each step starts when
## the one before has finished, and IDs after the start come from events and the view. It records
## what happened, so tests assert on one shared run rather than paying for the chain each time.

const SEED := 12345
const STATION := 8
const HUB := 9
const FREE_PORT := 11
const SHIP_DOCK := 12
const REFINERY := 13
const FABRICATOR := 14
const SHIP := 23
const HULL := 24
const SHIP_PORT := 28
const LASER := 35
const RED_ROCK := 2
const HEMATITE := 3
const BRASS_ROCK := 4
const CHALCOPYRITE := 5
const GREEN_ROCK := 6
const OLIVINE := 7
const LAPS := 3
## How much longer than planned a step may run before the bot gives up.
const ORDER_LIMIT_TICKS := 4000
const LAP_LIMIT_TICKS := 6000
## Range checks walk the whole state, so they run this often, not on every tick.
const RANGE_CHECK_TICKS := 100

static var _shared: ReferenceBot

var sim: Sim
var events: Array[Dictionary] = []
## Every step as { label, start_tick, ticks }.
var steps: Array[Dictionary] = []
## Views taken at named points.
var marks := {}
## Ticks at which the drone finished each lap.
var lap_ticks: Array[int] = []
var cycle_start_tick := 0
var drone := 0
var drone_body := 0
var problems := PackedStringArray()
## Commands as submitted, as { tick, command }, for replays.
var commands: Array[Dictionary] = []
var ledger_problems := PackedStringArray()
var range_problems := PackedStringArray()


## The one shared run. It is built on first use.
static func shared() -> ReferenceBot:
	if _shared == null:
		_shared = ReferenceBot.new()
		_shared.run()
	return _shared


func run() -> void:
	sim = Sim.new_game("reference", SEED)
	_part_a()
	_part_b()
	_part_c()
	_part_d()
	_part_e()


func _part_a() -> void:
	_trip_out(RED_ROCK)
	_order("scan", SHIP, { "target": RED_ROCK })
	mark("scanned")
	_mine_and_haul(HEMATITE, "hematite")
	mark("first_haul")
	_trip_out(RED_ROCK)
	_mine_and_haul(HEMATITE, "hematite")
	_trip_out(BRASS_ROCK)
	_order("scan", SHIP, { "target": BRASS_ROCK })
	_mine_and_haul(CHALCOPYRITE, "chalcopyrite")
	_trip_out(GREEN_ROCK)
	_order("scan", SHIP, { "target": GREEN_ROCK })
	_mine_and_haul(OLIVINE, "olivine")
	mark("part_a")


func _trip_out(rock: int) -> void:
	_order("undock", SHIP, {})
	_order("move_to", SHIP, { "target": rock })


func _mine_and_haul(deposit: int, item: String) -> void:
	_order("start_mining", SHIP, { "deposit": deposit, "module": LASER })
	_order("move_to", SHIP, { "target": STATION })
	_order("dock", SHIP, { "port": SHIP_PORT, "target_port": SHIP_DOCK })
	_order("unload_cargo", SHIP, { "to": STATION, "item": item })


func _part_b() -> void:
	_job(REFINERY, "refine_hematite", 26)
	mark("refined")
	_job(REFINERY, "refine_chalcopyrite", 10)
	_job(REFINERY, "refine_olivine", 6)


func _part_c() -> void:
	_job(FABRICATOR, "structural_frame", 35)
	mark("fabricated")
	_job(FABRICATOR, "wiring", 21)
	_job(FABRICATOR, "processor", 24)
	_job(FABRICATOR, "heat_radiator_mk1", 1)
	_job(FABRICATOR, "mining_laser_mk1", 1)
	_attach(SHIP, "mining_laser_mk1", HULL, "side_b_nz", "mount")
	mark("fit_failed")
	_attach(SHIP, "heat_radiator_mk1", HULL, "side_c_nx", "mount")
	_attach(SHIP, "mining_laser_mk1", HULL, "side_b_nz", "mount")
	mark("fit_fixed")


func _part_d() -> void:
	_job(FABRICATOR, "ore_storage_mk1", 1)
	_attach(STATION, "ore_storage_mk1", HUB, "side_c_px", "mount")
	mark("expanded")


func _part_e() -> void:
	_job(FABRICATOR, "mining_drone", 1)
	var created := first_event("unit_created")
	if created.is_empty():
		problems.append("no drone was built")
		return
	drone = created["data"]["unit"]
	drone_body = sim.view()["units"][drone]["parts"]["id"]
	mark("drone_built")
	_job(FABRICATOR, "basic_core", 1)
	_job(FABRICATOR, "assisted_core", 1)
	_attach(drone, "assisted_core", drone_body, "core", "mount")
	var fitted := last_event("part_attached")
	_command("assign_core", drone, { "core": fitted["data"]["part"] })
	_step()
	mark("core_assigned")
	_run_cycle()
	mark("end")


func _run_cycle() -> void:
	var id := _command("set_cycle", drone, { "steps": cycle_steps() })
	cycle_start_tick = sim.current_tick() + 1
	var limit := LAP_LIMIT_TICKS * LAPS
	while lap_ticks.size() < LAPS and limit > 0:
		limit -= 1
		for event in _step():
			if event["type"] == "task_cycle_done":
				lap_ticks.append(event["tick"])
			elif event["type"] == "command_rejected" and event["data"]["command"] == id:
				problems.append("set_cycle refused: %s" % event["data"]["reason"])
				return
	if lap_ticks.size() < LAPS:
		problems.append("the cycle stopped after %d laps" % lap_ticks.size())


func cycle_steps() -> Array:
	return [
		{ "type": "load_cargo", "args": { "from": STATION, "item": "propellant" } },
		{ "type": "undock", "args": {} },
		{ "type": "move_to", "args": { "target": RED_ROCK } },
		{ "type": "start_mining", "args": { "deposit": HEMATITE, "module": drone_body } },
		{ "type": "move_to", "args": { "target": STATION } },
		{ "type": "dock", "args": { "port": drone_body, "target_port": FREE_PORT } },
		{ "type": "unload_cargo", "args": { "to": STATION, "item": "hematite" } },
	]


func mark(label: String) -> void:
	marks[label] = sim.view()


func first_event(type: String) -> Dictionary:
	for event in events:
		if event["type"] == type:
			return event
	return {}


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


func ticks_of(label: String) -> Array:
	var found := []
	for step in steps:
		if step["label"] == label:
			found.append(step["ticks"])
	return found


## Gives an order and steps until its task ends. A failed order stops nothing else, so a run with
## a problem still reports as far as it got.
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
						steps.append({ "label": type, "start_tick": start, "ticks": event["tick"] - start })
						return
	problems.append("%s never finished" % type)


## Starts a job and steps until its last run ends.
func _job(facility: int, recipe: String, count: int) -> void:
	if not problems.is_empty():
		return
	var id := _command("start_job", STATION, { "facility": facility, "recipe": recipe, "count": count })
	var start := sim.current_tick() + 1
	var limit: int = sim.defs()["recipes"][recipe]["ticks"] * count + ORDER_LIMIT_TICKS
	var job := 0
	var left := count
	for i in limit:
		for event in _step():
			var data: Dictionary = event["data"]
			match event["type"]:
				"command_rejected":
					if data["command"] == id:
						problems.append("%s refused: %s" % [recipe, data["reason"]])
						return
				"job_started":
					if data["command"] == id:
						job = data["job"]
				"job_paused":
					if data["job"] == job or job == 0:
						problems.append("%s paused: %s" % [recipe, data["reason"]])
						return
				"job_finished":
					if data["job"] == job:
						left -= 1
						if left == 0:
							steps.append({ "label": recipe, "start_tick": start, "ticks": event["tick"] - start + 1 })
							return
	problems.append("%s never finished" % recipe)


func _attach(unit: int, item: String, parent: int, connector: String, part_connector: String) -> void:
	if not problems.is_empty():
		return
	_command("attach_part", unit, {
		"item": item, "from": STATION, "parent_part": parent,
		"parent_connector": connector, "part_connector": part_connector,
	})
	_step()


func _command(type: String, unit: int, args: Dictionary) -> int:
	var command := { "type": type, "unit": unit, "args": args }
	commands.append({ "tick": sim.current_tick(), "command": command.duplicate(true) })
	return sim.submit(command)


## One tick. The ledger is checked on every tick (accounting.md section 6).
func _step() -> Array[Dictionary]:
	sim.step()
	var new_events := sim.take_events()
	events.append_array(new_events)
	_check_ledgers(sim.ledger())
	if sim.current_tick() % RANGE_CHECK_TICKS == 0:
		range_problems.append_array(Invariants.violations(sim._state))
	return new_events


## Records any tick on which matter, energy or heat does not balance.
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


func _ledger_problem(text: String) -> void:
	if ledger_problems.size() < 10:
		ledger_problems.append(text)
