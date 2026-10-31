class_name Sim
extends RefCounted
## The public simulation API (contracts section 3) and the tick loop (section 4).

const TICKS_PER_SECOND := 10
const CONTRACT_VERSION := 1
const SCENARIO_EMPTY := "empty"
## Undrained events past this are dropped, oldest first.
const MAX_QUEUED_EVENTS := 65536

const ERROR_CORRUPT := "corrupt"
const ERROR_VERSION_MISMATCH := "version_mismatch"
const ERROR_DATA_MISMATCH := "data_mismatch"
const ERROR_UNKNOWN_SCENARIO := "unknown_scenario"
const REASON_UNKNOWN_COMMAND := "unknown_command"
const REASON_UNKNOWN_UNIT := "unknown_unit"
const REASON_MALFORMED := "malformed_command"
const REASON_FLOAT := "float_in_command"

static var _last_error := ""

var _state: Dictionary
var _ctx: SimContext
var _systems: Array[SimSystem] = []
var _handlers := {}
var _events: Array[Dictionary] = []
## Test runs set this to check every state range at commit.
var _strict := false
var _violations := PackedStringArray()


static func new_game(scenario_id: String, seed_value: int) -> Sim:
	if scenario_id != SCENARIO_EMPTY and not DataLoader.has_scenario(scenario_id):
		_last_error = ERROR_UNKNOWN_SCENARIO
		return null
	var definitions := _load_defs(scenario_id)
	var state := _new_state(scenario_id, seed_value, definitions)
	if definitions.is_empty() or state["data_hash"] == "":
		_last_error = ERROR_CORRUPT
		return null
	var sim := Sim.new()
	sim._setup(state, definitions)
	if scenario_id != SCENARIO_EMPTY and not sim._populate(scenario_id):
		_last_error = ERROR_CORRUPT
		return null
	_last_error = ""
	return sim


static func from_save(save_text: String) -> Sim:
	var state: Variant = Canon.decode(save_text)
	if typeof(state) != TYPE_DICTIONARY or not _has_state_shape(state):
		_last_error = ERROR_CORRUPT
		return null
	if state["contract_version"] != CONTRACT_VERSION or state["ticks_per_second"] != TICKS_PER_SECOND:
		_last_error = ERROR_VERSION_MISMATCH
		return null
	var definitions := _load_defs(state["scenario"])
	if definitions.is_empty() or state["data_hash"] != _data_hash(definitions):
		_last_error = ERROR_DATA_MISMATCH
		return null
	var sim := Sim.new()
	sim._setup(state, definitions)
	_last_error = ""
	return sim


static func last_error() -> String:
	return _last_error


## Queues a command for the next tick and returns its ID.
func submit(command: Dictionary) -> int:
	var id: int = _state["next_command_id"]
	_state["next_command_id"] = id + 1
	var queued := _normalized(command)
	queued["id"] = id
	queued["tick"] = current_tick() + 1
	_state["commands"].append(queued)
	return id


## Runs phase 1 validation with no effects. Returns { ok, reason, detail }.
func check(command: Dictionary) -> Dictionary:
	var result := _validate(_normalized(command))
	return { "ok": result["ok"], "reason": result["reason"], "detail": result["detail"] }


func step(tick_count: int = 1) -> void:
	for i in tick_count:
		_run_tick()


func current_tick() -> int:
	return _state["tick"]


## A fresh copy of the visible state, in the frozen shape of contracts section 7.
func view() -> Dictionary:
	var result := {
		"tick": _state["tick"], "seed": _state["seed"],
		"units": {}, "bodies": {}, "deposits": {}, "jobs": {}, "tasks": {},
	}
	for system in _systems:
		system.fill_view(_ctx, result)
	return result


func defs() -> Dictionary:
	return _ctx.defs.duplicate(true)


func take_events() -> Array[Dictionary]:
	var events := _events
	_events = []
	return events


## Canonical text of the whole state, or "" with a push_error if the state is not plain data.
func to_save() -> String:
	var text := Canon.encode(_state)
	if text == "":
		push_error("State is not canonical: %s" % Canon.error)
	return text


func state_hash() -> String:
	var text := to_save()
	return text.sha256_text() if text != "" else ""


## For tests only: the ledger figures after the last commit and any range violations so far.
## Systems fill the places they own. The kernel owns the sinks and the total.
func ledger() -> Dictionary:
	var sinks := _sink_totals()
	var sinks_g := 0
	for sink: String in sinks:
		sinks_g += sinks[sink]
	var matter := {
		"start_g": _state["matter_start_g"], "total_g": 0, "deposits_g": 0,
		"inventories_g": 0, "jobs_g": 0, "installed_g": 0, "sinks_g": sinks_g, "sinks": sinks,
	}
	var result := {
		"tick": _state["tick"], "matter": matter, "energy": {}, "heat": {},
		"violations": _violations.duplicate(),
	}
	for system in _systems:
		system.fill_ledger(_ctx, result)
	matter["total_g"] = matter["deposits_g"] + matter["inventories_g"] + matter["jobs_g"] \
		+ matter["installed_g"] + matter["sinks_g"]
	return result


static func _new_state(scenario_id: String, seed_value: int, defs_value: Dictionary) -> Dictionary:
	return {
		"contract_version": CONTRACT_VERSION,
		"ticks_per_second": TICKS_PER_SECOND,
		"data_hash": _data_hash(defs_value),
		"scenario": scenario_id,
		"seed": seed_value,
		"matter_start_g": 0,
		"tick": 0,
		"next_entity_id": 1,
		"next_command_id": 1,
		"rng": {},
		"commands": [],
		"units": {},
		"parts": {},
		"bodies": {},
		"deposits": {},
		"jobs": {},
		"tasks": {},
		"sinks": {},
	}


## Definitions for a game. Only the built-in `empty` scenario runs without data/.
static func _load_defs(scenario_id: String) -> Dictionary:
	if scenario_id == SCENARIO_EMPTY:
		return { "modules": {}, "items": {}, "recipes": {}, "templates": {}, "sinks": {} }
	var definitions := DataLoader.load_defs()
	if DataLoader.error != "":
		push_error("Data did not load: %s" % DataLoader.error)
	return definitions


## A hash of what the simulation reads after load, or "" if that cannot be encoded.
static func _data_hash(defs_value: Dictionary) -> String:
	var text := Canon.encode(DataLoader.read_after_load(defs_value))
	if text == "":
		push_error("Definitions are not canonical: %s" % Canon.error)
		return ""
	return text.sha256_text()


## The same systems in the same order for every game, so a loaded game has working handlers.
## The order is the phase-list order within each phase.
static func _default_systems() -> Array[SimSystem]:
	return [
		UnitSystem.new(), FittingSystem.new(), TaskSystem.new(), PowerSystem.new(), HeatSystem.new(),
	]


## A saved state must hold every field with the right type before anything reads it.
static func _has_state_shape(state: Dictionary) -> bool:
	var template := _new_state("", 0, {})
	for key: String in template:
		if not state.has(key) or typeof(state[key]) != typeof(template[key]):
			return false
	return true


## Grams per sink.
func _sink_totals() -> Dictionary:
	var totals := {}
	var sinks: Dictionary = _state["sinks"]
	for sink: String in sinks:
		var items: Dictionary = sinks[sink]
		var total := 0
		for item: String in items:
			total += items[item]
		totals[sink] = total
	return totals


func _setup(state: Dictionary, defs_value: Dictionary) -> void:
	_state = state
	_ctx = SimContext.new(state, defs_value)
	for system in _default_systems():
		_register_system(system)


## Builds a new game's entities. False if the scenario cannot be built.
func _populate(scenario_id: String) -> bool:
	var scenario := DataLoader.load_scenario(scenario_id, _ctx.defs["items"])
	if DataLoader.error != "":
		push_error("Scenario did not load: %s" % DataLoader.error)
		return false
	var problem := ScenarioBuilder.populate(_ctx, scenario, DataLoader.load_deposits())
	if problem != "":
		push_error("Scenario did not build: %s" % problem)
		return false
	return true


func _register_system(system: SimSystem) -> void:
	_systems.append(system)
	for type in system.commands():
		_handlers[type] = system


func _run_tick() -> void:
	var tick := current_tick() + 1
	_ctx.begin_tick(tick)
	_ctx.phase = 1
	_apply_commands(tick)
	_ctx.phase = 2
	for system in _systems:
		system.update_tasks(_ctx)
	_ctx.phase = 3
	for system in _systems:
		system.calculate_power(_ctx)
	_ctx.phase = 4
	for system in _systems:
		system.allocate(_ctx)
	_ctx.phase = 5
	for system in _systems:
		system.run(_ctx)
	_ctx.phase = 6
	for delta in _ctx.take_deltas():
		delta["system"].apply_delta(_ctx, delta["payload"])
	for system in _systems:
		system.update_stores(_ctx)
	_ctx.phase = 7
	for system in _systems:
		system.detect(_ctx)
	_ctx.phase = 8
	_commit(tick)


func _apply_commands(tick: int) -> void:
	var later: Array = []
	for command: Dictionary in _state["commands"]:
		if command["tick"] != tick:
			later.append(command)
			continue
		var result := _validate(command)
		if result["ok"]:
			_handlers[command["type"]].apply(_ctx, command)
		else:
			_emit_rejection(command, result)
	_state["commands"] = later


func _emit_rejection(command: Dictionary, result: Dictionary) -> void:
	var data := {
		"command": command["id"], "reason": result["reason"], "detail": result["detail"],
	}
	data.merge(result.get("data", {}))
	_ctx.emit_event(result.get("event", "command_rejected"), command["unit"], data)


func _validate(command: Dictionary) -> Dictionary:
	if command.has("invalid"):
		return SimSystem.reject(command["invalid"])
	if not _handlers.has(command["type"]):
		return SimSystem.reject(REASON_UNKNOWN_COMMAND)
	if not _state["units"].has(command["unit"]):
		return SimSystem.reject(REASON_UNKNOWN_UNIT)
	return _handlers[command["type"]].validate(_ctx, command)


## A private plain-data copy of a command. One that cannot be saved keeps only its type and unit
## and is marked invalid, so a queued command can never make the state unsaveable.
func _normalized(command: Dictionary) -> Dictionary:
	var type: Variant = command.get("type")
	var unit: Variant = command.get("unit")
	var args: Variant = command.get("args", {})
	var result := {
		"type": type if typeof(type) == TYPE_STRING else "",
		"unit": unit if typeof(unit) == TYPE_INT else 0,
		"args": {},
	}
	var problem := ""
	if typeof(type) != TYPE_STRING or typeof(unit) != TYPE_INT or typeof(args) != TYPE_DICTIONARY:
		problem = REASON_MALFORMED
	else:
		problem = _value_problem(args)
	if problem != "":
		result["invalid"] = problem
	else:
		result["args"] = args.duplicate(true)
	return result


func _value_problem(value: Variant) -> String:
	match typeof(value):
		TYPE_FLOAT:
			return REASON_FLOAT
		TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return ""
		TYPE_ARRAY:
			var values: Array = value
			for item: Variant in values:
				var problem := _value_problem(item)
				if problem != "":
					return problem
			return ""
		TYPE_DICTIONARY:
			var map: Dictionary = value
			for key: Variant in map:
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_INT:
					return REASON_MALFORMED
				var problem := _value_problem(map[key])
				if problem != "":
					return problem
			return ""
	return REASON_MALFORMED


func _commit(tick: int) -> void:
	_events.append_array(_ctx.take_events())
	if _events.size() > MAX_QUEUED_EVENTS:
		var dropped := _events.size() - MAX_QUEUED_EVENTS
		push_warning("Dropped %d undrained events" % dropped)
		_events = _events.slice(dropped)
	_state["tick"] = tick
	if _strict:
		_violations.append_array(Invariants.violations(_state))
		_violations.append_array(Units.broken_stacks(_state, _ctx.defs))
