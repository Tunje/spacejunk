class_name PersonRun
extends RefCounted
## Plays the reference scenario as a person would, for docs/design/balance.md. ReferenceBot runs one
## step at a time, so its times are a ceiling. This run keeps the ship, the refinery and the
## fabricator all busy at once, but it has one pair of hands: every command takes a think time, in
## real seconds, during which the game keeps running at the chosen speed. Progress is scored by the
## client's own GoalTracker, so a "check" means the same here as on the player's screen.

const STATION := ReferenceBot.STATION
const HUB := ReferenceBot.HUB
const FREE_PORT := ReferenceBot.FREE_PORT
const REFINERY := ReferenceBot.REFINERY
const FABRICATOR := ReferenceBot.FABRICATOR
const SHIP := ReferenceBot.SHIP
const HULL := ReferenceBot.HULL
const LASER := ReferenceBot.LASER
const SHIP_PORT := ReferenceBot.SHIP_PORT
const SHIP_DOCK := ReferenceBot.SHIP_DOCK
const LIMIT_TICKS := 400000
const ROCKS: Array[int] = [ReferenceBot.RED_ROCK, ReferenceBot.BRASS_ROCK, ReferenceBot.GREEN_ROCK]
const HEMATITE_TRIP := { "rock": ReferenceBot.RED_ROCK, "deposit": ReferenceBot.HEMATITE, "item": "hematite" }
const COPPER_TRIP := { "rock": ReferenceBot.BRASS_ROCK, "deposit": ReferenceBot.CHALCOPYRITE, "item": "chalcopyrite" }
const SILICON_TRIP := { "rock": ReferenceBot.GREEN_ROCK, "deposit": ReferenceBot.OLIVINE, "item": "olivine" }

## What a drone needs fitted, in an order the power and heat budgets allow. `on` names the part to
## fit to, if it is not the hull.
const DRONE_FITS: Array[Dictionary] = [
	{ "item": "small_solar_panel_mk1", "at": "side_a_px" },
	{ "item": "small_heat_radiator_mk1", "at": "side_a_nx" },
	{ "item": "small_propellant_tank_mk1", "at": "stack_bottom" },
	{ "item": "small_chemical_thruster_mk1", "at": "stack_bottom", "on": "small_propellant_tank_mk1" },
	{ "item": "small_ore_container_mk1", "at": "side_a_pz" },
	{ "item": "small_mining_laser_mk1", "at": "side_a_nz" },
	{ "item": "assisted_core", "at": "core" },
]

## Reads the recipes ahead: one hematite trip, the cheapest module first, a small expansion.
const PLAN_DIRECT := {
	"trips": [HEMATITE_TRIP, COPPER_TRIP, SILICON_TRIP],
	"refine": [
		{ "recipe": "refine_hematite", "item": "hematite", "runs": 9 },
		{ "recipe": "refine_chalcopyrite", "item": "chalcopyrite", "runs": 10 },
		{ "recipe": "refine_olivine", "item": "olivine", "runs": 6 },
		{ "recipe": "refine_hematite", "item": "hematite", "runs": 11 },
	],
	"make": [
		"ore_container_mk1", "ore_container_mk1", "heat_radiator_mk1", "mining_laser_mk1",
		"small_craft", "small_solar_panel_mk1", "small_heat_radiator_mk1",
		"small_propellant_tank_mk1", "small_chemical_thruster_mk1", "small_ore_container_mk1",
		"small_mining_laser_mk1", "basic_core", "assisted_core",
	],
	"fits": [
		{ "unit": SHIP, "item": "ore_container_mk1", "parent": HULL, "at": "side_c_pz", "after": [] },
		{ "unit": STATION, "item": "ore_container_mk1", "parent": HUB, "at": "side_c_px", "after": [] },
		{ "unit": SHIP, "item": "mining_laser_mk1", "parent": HULL, "at": "side_b_nz", "after": [] },
		{ "unit": SHIP, "item": "heat_radiator_mk1", "parent": HULL, "at": "side_c_nx", "after": [2] },
		{ "unit": SHIP, "item": "mining_laser_mk1", "parent": HULL, "at": "side_b_nz", "after": [3] },
	],
}
## Follows the reference chain's shopping list, with no reading ahead.
const PLAN_CHAIN := {
	"trips": [HEMATITE_TRIP, HEMATITE_TRIP, COPPER_TRIP, SILICON_TRIP],
	"refine": [
		{ "recipe": "refine_hematite", "item": "hematite", "runs": 26 },
		{ "recipe": "refine_chalcopyrite", "item": "chalcopyrite", "runs": 10 },
		{ "recipe": "refine_olivine", "item": "olivine", "runs": 6 },
	],
	"make": [
		"heat_radiator_mk1", "mining_laser_mk1", "ore_storage_mk1",
		"small_craft", "small_solar_panel_mk1", "small_heat_radiator_mk1",
		"small_propellant_tank_mk1", "small_chemical_thruster_mk1", "small_ore_container_mk1",
		"small_mining_laser_mk1", "basic_core", "assisted_core",
	],
	"fits": [
		{ "unit": SHIP, "item": "mining_laser_mk1", "parent": HULL, "at": "side_b_nz", "after": [] },
		{ "unit": SHIP, "item": "heat_radiator_mk1", "parent": HULL, "at": "side_c_nx", "after": [0] },
		{ "unit": SHIP, "item": "mining_laser_mk1", "parent": HULL, "at": "side_b_nz", "after": [1] },
		{ "unit": STATION, "item": "ore_storage_mk1", "parent": HUB, "at": "side_c_px", "after": [] },
	],
}

var sim: Sim
var speed: int
var think_ticks: int
var tracker := GoalTracker.new()
## Tick each check finished, by goal ID.
var goal_ticks := {}
## Ticks of module_built, module_fitted, drone_built, drone_fitted, expanded and hauling_done.
var marks := {}
## Tick of every command given.
var command_ticks: Array[int] = []
var problems := PackedStringArray()
var shed_events := 0
var paused_reasons := {}
var refinery_ticks := 0
var fabricator_ticks := 0
var end_view := {}

var _defs: Dictionary
var _items: Dictionary
var _recipes: Dictionary
var _ship_steps: Array[Dictionary] = []
var _ship_command := 0
var _ship_task := 0
var _refine: Array = []
var _make: Array = []
var _fits: Array = []
var _fit_done := {}
var _drone := 0
var _drone_body := 0
var _drone_stage := 0
var _armed_at := -1
var _dirty := true
var _scanned := {}


## `rock_scale` is { num, den } for moving the rocks, for trying an option. It changes this run only.
func _init(plan: Dictionary, speed_value: int, think_seconds: int, rock_scale := { "num": 1, "den": 1 }) -> void:
	speed = speed_value
	think_ticks = think_seconds * Sim.TICKS_PER_SECOND * speed
	sim = Sim.new_game("reference", ReferenceBot.SEED)
	PersonRun.scale_rocks(sim, rock_scale)
	_defs = sim.defs()
	_items = _defs["items"]
	_recipes = _defs["recipes"]
	_refine = plan["refine"].duplicate(true)
	_make = plan["make"].duplicate()
	_fits = plan["fits"].duplicate(true)
	for trip: Dictionary in plan["trips"]:
		_add_trip(trip)


static func scale_rocks(target: Sim, rock_scale: Dictionary) -> void:
	for rock in ROCKS:
		var pos: Array = target._state["bodies"][rock]["pos_mm"]
		for axis in pos.size():
			var size := IntMath.mul_div(absi(pos[axis]), rock_scale["num"], rock_scale["den"])
			pos[axis] = size if pos[axis] >= 0 else -size


func run() -> void:
	while tracker.done_count() < GoalTracker.GOALS.size() and sim.current_tick() < LIMIT_TICKS:
		if not problems.is_empty():
			return
		_act()
		_step()
	if tracker.done_count() < GoalTracker.GOALS.size():
		problems.append("only %d checks after %d ticks" % [tracker.done_count(), sim.current_tick()])
	end_view = sim.view()


## One command at a time: an available command waits out the think time, then goes in.
func _act() -> void:
	if not _dirty and _armed_at < 0:
		return
	var tick := sim.current_tick()
	if _armed_at >= 0 and tick < _armed_at:
		return
	var action := _next_action()
	_dirty = false
	if action.is_empty():
		_armed_at = -1
	elif _armed_at < 0:
		_armed_at = tick + think_ticks
	else:
		_armed_at = -1
		_dirty = true
		_give(action)


## The fitting screen refuses a bad fit before it is sent, so that action has no command.
func _give(action: Dictionary) -> void:
	command_ticks.append(sim.current_tick())
	if action.has("command"):
		var id := sim.submit(action["command"])
		if action.has("ship"):
			_ship_command = id
	if action.has("done"):
		(action["done"] as Callable).call()


func _step() -> void:
	sim.step()
	var view := {}
	var events := sim.take_events()
	if not events.is_empty():
		view = sim.view()
		_dirty = true
		_observe(tracker.observe_view(view, _items, _defs["modules"]))
	for event in events:
		_on_event(event, view)
	for job: Dictionary in sim._state["jobs"].values():
		if job["status"] == JobSystem.STATUS_RUNNING:
			if job["facility"] == REFINERY:
				refinery_ticks += 1
			else:
				fabricator_ticks += 1


func _observe(finished: Array[String]) -> void:
	for id in finished:
		goal_ticks[id] = sim.current_tick()


func _on_event(event: Dictionary, view: Dictionary) -> void:
	var data: Dictionary = event["data"]
	_observe(tracker.observe_event(event, view, _defs))
	match event["type"]:
		"command_rejected":
			problems.append("tick %d: command %d refused: %s" % [event["tick"], data["command"], data["reason"]])
		"task_started":
			if data["command"] == _ship_command:
				_ship_task = data["task"]
		"task_finished":
			if data["task"] == _ship_task:
				_ship_task = 0
				_ship_command = 0
				if _ship_steps.is_empty():
					marks["hauling_done"] = event["tick"]
		"task_cancelled":
			if data["task"] == _ship_task:
				problems.append("ship order cancelled: %s" % data["reason"])
		"power_shed":
			shed_events += 1
		"job_paused":
			paused_reasons[data["reason"]] = paused_reasons.get(data["reason"], 0) + 1
		"job_finished":
			if _defs["modules"].has(data["recipe"]) and not marks.has("module_built"):
				marks["module_built"] = event["tick"]
		"part_attached":
			if not marks.has("module_fitted"):
				marks["module_fitted"] = event["tick"]
			if event["unit"] == STATION and not marks.has("expanded"):
				marks["expanded"] = event["tick"]
			if event["unit"] == _drone and data["part"] == _drone_part("small_mining_laser_mk1", view):
				marks["drone_fitted"] = event["tick"]
		"unit_created":
			_drone = data["unit"]
			_drone_body = view["units"][_drone]["parts"]["id"]
			if not marks.has("drone_built"):
				marks["drone_built"] = event["tick"]


## What the person does next, most urgent first, or {}.
func _next_action() -> Dictionary:
	var view := sim.view()
	var action := _fit_action()
	if action.is_empty():
		action = _drone_action()
	if action.is_empty():
		action = _refine_action(view)
	if action.is_empty():
		action = _fabricate_action(view)
	if action.is_empty():
		action = _ship_action()
	return action


func _fit_action() -> Dictionary:
	for index in _fits.size():
		var fit: Dictionary = _fits[index]
		if _fit_done.has(index) or not _fits_ready(fit):
			continue
		var command := { "type": "attach_part", "unit": fit["unit"], "args": {
			"item": fit["item"], "from": STATION, "parent_part": fit["parent"],
			"parent_connector": fit["at"], "part_connector": "mount",
		} }
		var result := sim.check(command)
		# C30: a fit over a limit is allowed with a warning, which the tracker sees on
		# part_attached; the radiator after it brings the ship back within (D48).
		if result["ok"]:
			return { "command": command, "done": func() -> void: _fit_done[index] = true }
	return {}


func _fits_ready(fit: Dictionary) -> bool:
	for index: int in fit["after"]:
		if not _fit_done.has(index):
			return false
	return true


func _drone_action() -> Dictionary:
	if _drone == 0:
		return {}
	var view := sim.view()
	if _drone_stage < DRONE_FITS.size():
		var fit: Dictionary = DRONE_FITS[_drone_stage]
		var command := { "type": "attach_part", "unit": _drone, "args": {
			"item": fit["item"], "from": STATION,
			"parent_part": _drone_part(fit["on"], view) if fit.has("on") else _drone_body,
			"parent_connector": fit["at"], "part_connector": "mount",
		} }
		if sim.check(command)["ok"]:
			return { "command": command, "done": func() -> void: _drone_stage += 1 }
		return {}
	if _drone_stage == DRONE_FITS.size():
		var core := _drone_part("assisted_core", view)
		if core != 0:
			return { "command": { "type": "assign_core", "unit": _drone, "args": { "core": core } },
				"done": func() -> void: _drone_stage += 1 }
	elif _drone_stage == DRONE_FITS.size() + 1:
		return { "command": { "type": "set_cycle", "unit": _drone, "args": { "steps": _cycle_steps(view) } },
			"done": func() -> void: _drone_stage += 1 }
	return {}


## The drone's part of a definition, or 0.
func _drone_part(def: String, view: Dictionary) -> int:
	for part: Dictionary in InspectText.flatten(view["units"][_drone]["parts"]):
		if part["def"] == def:
			return part["id"]
	return 0


func _cycle_steps(view: Dictionary) -> Array:
	return [
		{ "type": "load_cargo", "args": { "from": STATION, "item": "propellant" } },
		{ "type": "undock", "args": {} },
		{ "type": "move_to", "args": { "target": ReferenceBot.RED_ROCK } },
		{ "type": "start_mining", "args": { "deposit": ReferenceBot.HEMATITE, "module": _drone_part("small_mining_laser_mk1", view) } },
		{ "type": "move_to", "args": { "target": STATION } },
		{ "type": "dock", "args": { "port": _drone_part("small_docking_port_mk1", view), "target_port": FREE_PORT } },
		{ "type": "unload_cargo", "args": { "to": STATION, "item": "hematite" } },
	]


func _add_trip(trip: Dictionary) -> void:
	_ship_steps.append({ "type": "undock", "args": {} })
	_ship_steps.append({ "type": "move_to", "args": { "target": trip["rock"] } })
	if not _scanned.has(trip["rock"]):
		_scanned[trip["rock"]] = true
		_ship_steps.append({ "type": "scan", "args": { "target": trip["rock"] } })
	_ship_steps.append({ "type": "start_mining", "args": { "deposit": trip["deposit"], "module": LASER } })
	_ship_steps.append({ "type": "move_to", "args": { "target": STATION } })
	_ship_steps.append({ "type": "dock", "args": { "port": SHIP_PORT, "target_port": SHIP_DOCK } })
	_ship_steps.append({ "type": "unload_cargo", "args": { "to": STATION, "item": trip["item"] } })


func _ship_action() -> Dictionary:
	if _ship_steps.is_empty() or _ship_command != 0:
		return {}
	var step: Dictionary = _ship_steps[0]
	return { "ship": true, "command": { "type": step["type"], "unit": SHIP, "args": step["args"] },
		"done": func() -> void: _ship_steps.pop_front() }


func _refine_action(view: Dictionary) -> Dictionary:
	if _is_busy(view, REFINERY):
		return {}
	var stock: Dictionary = view["units"][STATION]["inventory"]
	for entry: Dictionary in _refine:
		var per_run: int = _recipes[entry["recipe"]]["inputs"][0]["grams"]
		var runs := mini(entry["runs"], stock.get(entry["item"], 0) / per_run)
		if runs > 0:
			return { "command": _job(REFINERY, entry["recipe"], runs), "done": func() -> void:
				entry["runs"] -= runs
				if entry["runs"] == 0:
					_refine.erase(entry) }
	return {}


## Stock goes to the wanted modules in order. The first one short of a part it can make from what
## is here gets that part started; a module with all its inputs gets started itself.
func _fabricate_action(view: Dictionary) -> Dictionary:
	if _is_busy(view, FABRICATOR):
		return {}
	var stock: Dictionary = view["units"][STATION]["inventory"].duplicate()
	for index in _make.size():
		var target: String = _make[index]
		var short := false
		for input: Dictionary in _recipes[target]["inputs"]:
			var item: String = input["item"]
			var used: int = mini(stock.get(item, 0), input["grams"])
			stock[item] = stock.get(item, 0) - used
			if used == input["grams"]:
				continue
			short = true
			if _recipes.has(item) and _can_start(item, stock):
				return { "command": _job(FABRICATOR, item, _runs_for(item, input["grams"] - used)) }
		if not short:
			return { "command": _job(FABRICATOR, target, 1), "done": func() -> void: _make.remove_at(index) }
	return {}


func _can_start(recipe: String, stock: Dictionary) -> bool:
	for input: Dictionary in _recipes[recipe]["inputs"]:
		if stock.get(input["item"], 0) < input["grams"]:
			return false
	return true


func _runs_for(recipe: String, grams: int) -> int:
	var each: int = _recipes[recipe]["outputs"][0]["grams"]
	return IntMath.mul_div(grams + each - 1, 1, each)


func _is_busy(view: Dictionary, facility: int) -> bool:
	for id: int in view["jobs"]:
		if view["jobs"][id]["facility"] == facility:
			return true
	return false


func _job(facility: int, recipe: String, count: int) -> Dictionary:
	return { "type": "start_job", "unit": STATION, "args": { "facility": facility, "recipe": recipe, "count": count } }


## Ticks between commands, longest first.
func longest_waits() -> Array:
	var gaps := []
	for index in range(1, command_ticks.size()):
		gaps.append(command_ticks[index] - command_ticks[index - 1])
	gaps.sort()
	gaps.reverse()
	return gaps
