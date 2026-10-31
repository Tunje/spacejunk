class_name StubSim extends RefCounted
## Stand-in for Sim (contracts section 3) until the kernel lands.
## Same API and view shape, with just enough behaviour to drive the client.
## Commands the stub does not model are rejected with `not_in_stub`.

const TICKS_PER_SECOND := 10
const SCENARIO_ID := "stub"
const DATA_DIR := "res://client/stub/data/"
const SAVE_HEADER := "stub-save:1\n"
const SAVE_PREFIX := "stub-save:"
const EVENT_LIMIT := 4096

const STANDOFF_MM := 150000

static var _last_error := ""

var _state: Dictionary = {}
var _defs: Dictionary = {}
var _events: Array[Dictionary] = []


static func new_game(scenario_id: String, seed_value: int) -> StubSim:
	_last_error = ""
	if scenario_id != SCENARIO_ID:
		_last_error = "unknown_scenario"
		return null
	var sim := StubSim.new()
	sim._defs = _load_defs()
	sim._state = _build_state(sim._defs, seed_value)
	return sim


static func from_save(save_text: String) -> StubSim:
	_last_error = ""
	if not save_text.begins_with(SAVE_PREFIX):
		_last_error = "corrupt"
		return null
	if not save_text.begins_with(SAVE_HEADER):
		_last_error = "version_mismatch"
		return null
	var state: Variant = str_to_var(save_text.trim_prefix(SAVE_HEADER))
	if not state is Dictionary:
		_last_error = "corrupt"
		return null
	var sim := StubSim.new()
	sim._defs = _load_defs()
	sim._state = state
	return sim


static func last_error() -> String:
	return _last_error


func submit(command: Dictionary) -> int:
	var queued: Dictionary = command.duplicate(true)
	queued["id"] = _state["next_command"]
	queued["tick"] = current_tick() + 1
	_state["next_command"] += 1
	_state["queue"].append(queued)
	return queued["id"]


func check(command: Dictionary) -> Dictionary:
	return _validate(command)


func step(tick_count: int = 1) -> void:
	for i in range(tick_count):
		_run_tick()


func current_tick() -> int:
	return _state["tick"]


func view() -> Dictionary:
	var units: Dictionary = {}
	for id: int in _sorted_keys(_state["units"]):
		units[id] = _unit_view(_state["units"][id])
	return {
		"tick": _state["tick"],
		"seed": _state["seed"],
		"units": units,
		"bodies": _state["bodies"].duplicate(true),
		"deposits": _state["deposits"].duplicate(true),
		"jobs": {},
		"tasks": _state["tasks"].duplicate(true),
	}


func defs() -> Dictionary:
	return _defs.duplicate(true)


func take_events() -> Array[Dictionary]:
	var taken := _events
	_events = []
	return taken


func to_save() -> String:
	return SAVE_HEADER + var_to_str(_state)


func state_hash() -> String:
	return to_save().sha256_text()


func ledger() -> Dictionary:
	var matter := 0
	for id: int in _state["deposits"]:
		matter += _state["deposits"][id]["remaining_g"]
	for id: int in _state["hidden_deposits"]:
		matter += _state["hidden_deposits"][id]["remaining_g"]
	for id: int in _state["units"]:
		var unit: Dictionary = _state["units"][id]
		matter += _parts_mass(unit["parts"])
		for item: String in unit["inventory"]:
			matter += unit["inventory"][item]
	return { "matter_g": matter }


# --- Scenario ---

static func _load_defs() -> Dictionary:
	return {
		"modules": _index_by_id(_convert(_read_json("modules.json"))),
		"items": _index_by_id(_convert(_read_json("items.json"))),
		"recipes": {},
		"templates": _templates(),
		"sinks": {},
	}


static func _templates() -> Dictionary:
	var templates: Dictionary = {}
	for entry: Dictionary in _read_json("scenario.json")["units"]:
		templates[entry["def"]] = { "id": entry["def"], "kind": entry["kind"], "name": entry["name"] }
	return templates


static func _read_json(file_name: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(DATA_DIR + file_name))


static func _index_by_id(entries: Array) -> Dictionary:
	var indexed: Dictionary = {}
	for entry: Dictionary in entries:
		indexed[entry["id"]] = entry
	return indexed


## Converts data units to sim units by field name (schemas section 2). JSON
## floats become ints.
static func _convert(value: Variant) -> Variant:
	if value is float:
		return roundi(value)
	if value is Array:
		var converted: Array = []
		for entry: Variant in value:
			converted.append(_convert(entry))
		return converted
	if value is Dictionary:
		var converted: Dictionary = {}
		for key: String in value:
			var factor := 1
			var new_key := key
			if key.ends_with("_kg_m3"):
				new_key = key.trim_suffix("_kg_m3") + "_g_l"
			elif key.ends_with("_kg_per_s"):
				new_key = key.trim_suffix("_kg_per_s") + "_g_per_s"
				factor = 1000
			elif key.ends_with("_m_s"):
				new_key = key.trim_suffix("_m_s") + "_mm_s"
				factor = 1000
			elif key.ends_with("seconds"):
				new_key = key.trim_suffix("seconds") + "ticks"
				factor = TICKS_PER_SECOND
			elif key.ends_with("_kg"):
				new_key = key.trim_suffix("_kg") + "_g"
				factor = 1000
			elif key.ends_with("_kw"):
				new_key = key.trim_suffix("_kw") + "_w"
				factor = 1000
			elif key.ends_with("_kj"):
				new_key = key.trim_suffix("_kj") + "_j"
				factor = 1000
			elif key.ends_with("_m3"):
				new_key = key.trim_suffix("_m3") + "_l"
				factor = 1000
			var entry: Variant = _convert(value[key])
			converted[new_key] = entry * factor if entry is int else entry
		return converted
	return value


static func _build_state(module_defs: Dictionary, seed_value: int) -> Dictionary:
	var scenario: Dictionary = _convert(_read_json("scenario.json"))
	var state: Dictionary = {
		"tick": 0, "seed": seed_value, "next_id": 1, "next_command": 1, "queue": [],
		"units": {}, "bodies": {}, "deposits": {}, "hidden_deposits": {}, "tasks": {},
	}
	var body_ids: Dictionary = {}
	for entry: Dictionary in scenario["bodies"]:
		var id := _next_id(state)
		body_ids[entry["ref"]] = id
		state["bodies"][id] = {
			"kind": entry["kind"], "pos_mm": entry["pos_mm"], "radius_mm": entry["radius_mm"],
			"visual_seed": absi(seed_value * 31 + id * 2654435761) % 2147483647, "scanned": false,
		}
	for entry: Dictionary in scenario["deposits"]:
		state["hidden_deposits"][_next_id(state)] = {
			"body": body_ids[entry["body"]], "item": entry["item"],
			"remaining_g": entry["grams"], "hardness": entry["hardness"],
		}
	for entry: Dictionary in scenario["units"]:
		var id := _next_id(state)
		state["units"][id] = {
			"id": id, "def": entry["def"], "kind": entry["kind"], "name": entry["name"],
			"pos_mm": entry["pos_mm"], "at_target": _unit_named(state, entry.get("at", "")), "core": 0, "core_tier": 0, "task": 0,
			"cycle_task": 0, "last_cycle": [], "heat_j": 0,
			"op": _idle_op(), "route": {}, "dock": {},
			"parts": _build_part(state, module_defs, entry["parts"]),
			"inventory": entry["inventory"],
		}
	return state


static func _unit_named(state: Dictionary, unit_name: String) -> int:
	for id: int in state["units"]:
		if state["units"][id]["name"] == unit_name:
			return id
	return 0


static func _build_part(state: Dictionary, module_defs: Dictionary, entry: Dictionary) -> Dictionary:
	var children: Array = []
	var part: Dictionary = {
		"id": _next_id(state), "def": entry["def"],
		"parent_connector": entry.get("parent_connector", ""), "connector": entry.get("connector", ""),
		"state": "on", "fault": "", "draw_w": 0,
		"priority": module_defs["modules"][entry["def"]]["priority"], "children": children,
	}
	for child: Dictionary in entry["children"]:
		children.append(_build_part(state, module_defs, child))
	return part


static func _next_id(state: Dictionary) -> int:
	var id: int = state["next_id"]
	state["next_id"] = id + 1
	return id


static func _idle_op() -> Dictionary:
	return { "type": "idle", "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 }


static func _sorted_keys(entries: Dictionary) -> Array:
	var keys: Array = entries.keys()
	keys.sort()
	return keys


# --- Parts and derived figures ---

func _module(part: Dictionary) -> Dictionary:
	return _defs["modules"][part["def"]]


func _flat_parts(part: Dictionary) -> Array[Dictionary]:
	var parts: Array[Dictionary] = [part]
	for child: Dictionary in part["children"]:
		parts.append_array(_flat_parts(child))
	return parts


func _find_part(unit: Dictionary, part_id: int) -> Dictionary:
	for part: Dictionary in _flat_parts(unit["parts"]):
		if part["id"] == part_id:
			return part
	return {}


func _part_with(unit: Dictionary, capability: String) -> Dictionary:
	for part: Dictionary in _flat_parts(unit["parts"]):
		if _module(part)["capabilities"].has(capability):
			return part
	return {}


func _parts_mass(part: Dictionary) -> int:
	var total := 0
	for each: Dictionary in _flat_parts(part):
		total += _module(each)["mass_g"]
	return total


func _capability_sum(unit: Dictionary, capability: String, field: String) -> int:
	var total := 0
	for part: Dictionary in _flat_parts(unit["parts"]):
		total += _module(part)["capabilities"].get(capability, {}).get(field, 0)
	return total


func _unit_view(unit: Dictionary) -> Dictionary:
	var shown: Dictionary = unit.duplicate(true)
	shown.erase("id")
	shown.erase("heat_j")
	var demand := 0
	var waste := 0
	var rated_power := 0
	var rated_heat := 0
	for part: Dictionary in _flat_parts(shown["parts"]):
		var module := _module(part)
		rated_power += module["power_w"]
		rated_heat += module["heat_w"]
		var active: bool = not module["capabilities"].has("mine") or part["id"] == unit["op"]["part"]
		part["draw_w"] = module["power_w"] if active else 0
		demand += part["draw_w"]
		waste += module["heat_w"] if active else 0
	var supply := _capability_sum(unit, "generate", "power_w")
	var reject := _capability_sum(unit, "radiator", "reject_w")
	var mass := _parts_mass(unit["parts"])
	var limit := 0
	for part: Dictionary in _flat_parts(unit["parts"]):
		limit += _module(part)["capabilities"].get("max_mass_g", 0)
	for item: String in unit["inventory"]:
		mass += unit["inventory"][item]
	shown["mass_g"] = mass
	shown["cargo"] = _cargo_view(unit)
	shown["fit"] = {
		"mass_g": mass, "mass_limit_g": limit, "power_budget_w": supply, "power_rated_w": rated_power,
		"heat_budget_w": reject, "heat_rated_w": rated_heat,
	}
	shown["power"] = {
		"supply_w": supply, "demand_w": demand, "stored_j": 0, "capacity_j": 0, "max_discharge_w": 0,
	}
	shown["heat"] = {
		"stored_j": unit["heat_j"], "limit_j": _capability_sum(unit, "heat_capacity", "limit_j"),
		"reject_w": reject, "input_w": waste,
	}
	return shown


func _cargo_view(unit: Dictionary) -> Dictionary:
	var cargo: Dictionary = {}
	for part: Dictionary in _flat_parts(unit["parts"]):
		var storage: Dictionary = _module(part)["capabilities"].get("storage", {})
		for cargo_class: String in storage:
			var entry: Dictionary = cargo.get_or_add(cargo_class, {
				"used_g": 0, "cap_g": 0, "used_l": 0, "cap_l": 0, "reserved_g": 0, "reserved_l": 0,
			})
			entry["cap_g"] += storage[cargo_class]["mass_g"]
			entry["cap_l"] += storage[cargo_class]["volume_l"]
	for item: String in unit["inventory"]:
		var item_def: Dictionary = _defs["items"][item]
		if cargo.has(item_def["cargo_class"]):
			var entry: Dictionary = cargo[item_def["cargo_class"]]
			var grams: int = unit["inventory"][item]
			entry["used_g"] += grams
			entry["used_l"] += ceili(float(grams) / item_def["density_g_l"])
	return cargo


func _space_left_g(unit: Dictionary, item: String) -> int:
	var cargo := _cargo_view(unit)
	var cargo_class: String = _defs["items"][item]["cargo_class"]
	if not cargo.has(cargo_class):
		return 0
	var entry: Dictionary = cargo[cargo_class]
	var by_mass: int = entry["cap_g"] - entry["used_g"]
	var by_volume: int = (entry["cap_l"] - entry["used_l"]) * _defs["items"][item]["density_g_l"]
	return maxi(0, mini(by_mass, by_volume))


# --- Geometry ---

func _distance_mm(a: Array, b: Array) -> int:
	return IntMath.dist(a, b)


func _target_pos(target: int) -> Array:
	if _state["bodies"].has(target):
		return _state["bodies"][target]["pos_mm"]
	if _state["units"].has(target):
		return _state["units"][target]["pos_mm"]
	return []


func _target_radius(target: int) -> int:
	return _state["bodies"][target]["radius_mm"] if _state["bodies"].has(target) else 0


func _arrival_point(from_mm: Array, target: int) -> Array:
	var target_mm := _target_pos(target)
	var gap: int = _distance_mm(from_mm, target_mm)
	var standoff := _target_radius(target) + STANDOFF_MM
	if gap <= standoff:
		return from_mm.duplicate()
	var arrival: Array = []
	for axis in range(3):
		arrival.append(target_mm[axis] + (from_mm[axis] - target_mm[axis]) * standoff / gap)
	return arrival


func _travel_ticks(unit: Dictionary, target: int) -> int:
	var speed: int = _module(_part_with(unit, "thruster"))["capabilities"]["thruster"]["speed_mm_s"]
	var gap: int = _distance_mm(unit["pos_mm"], _arrival_point(unit["pos_mm"], target))
	return maxi(1, ceili(float(gap) * TICKS_PER_SECOND / speed))


# --- Validation ---

func _result(reason: String = "", detail: Dictionary = {}) -> Dictionary:
	return { "ok": reason.is_empty(), "reason": reason, "detail": detail }


func _has_float(value: Variant) -> bool:
	if value is float:
		return true
	if value is Array:
		return value.any(_has_float)
	if value is Dictionary:
		return value.values().any(_has_float)
	return false


func _validate(command: Dictionary) -> Dictionary:
	if _has_float(command):
		return _result("float_in_command")
	if not _state["units"].has(command.get("unit", 0)):
		return _result("unknown_unit")
	var unit: Dictionary = _state["units"][command["unit"]]
	var args: Dictionary = command.get("args", {})
	match command.get("type", ""):
		"move_to":
			return _validate_move(unit, args)
		"scan":
			return _validate_scan(unit, args)
		"dock":
			return _validate_dock(unit, args)
		"undock":
			return _result() if not unit["dock"].is_empty() else _result("not_docked")
		"start_mining":
			return _validate_mining(unit, args)
		"stop":
			return _result()
		"set_priority":
			return _result() if not _find_part(unit, args.get("module", 0)).is_empty() else _result("unknown_part")
	return _result("not_in_stub")


func _validate_move(unit: Dictionary, args: Dictionary) -> Dictionary:
	var target: int = args.get("target", 0)
	if _part_with(unit, "thruster").is_empty():
		return _result("module_missing")
	if not unit["dock"].is_empty():
		return _result("docked")
	if _target_pos(target).is_empty() or target == unit["id"]:
		return _result("invalid_target")
	if _state["bodies"].get(target, {}).get("kind", "") == "star":
		return _result("invalid_target")
	return _result("", { "ticks": _travel_ticks(unit, target), "propellant_g": 0 })


func _validate_scan(unit: Dictionary, args: Dictionary) -> Dictionary:
	var target: int = args.get("target", 0)
	if _part_with(unit, "scan").is_empty():
		return _result("module_missing")
	if not unit["dock"].is_empty():
		return _result("docked")
	if not _state["bodies"].has(target) or _state["bodies"][target]["kind"] != "asteroid":
		return _result("invalid_target")
	return _at(unit, target)


## "At" is what arrival recorded, never geometry (networks section 6).
func _at(unit: Dictionary, target: int) -> Dictionary:
	return _result() if unit["at_target"] == target else _result("out_of_range")


func _validate_dock(unit: Dictionary, args: Dictionary) -> Dictionary:
	if not unit["dock"].is_empty():
		return _result("docked")
	var port := _find_part(unit, args.get("port", 0))
	var owner := _unit_of_part(args.get("target_port", 0))
	if port.is_empty() or owner.is_empty() or owner["id"] == unit["id"]:
		return _result("invalid_target")
	if _dock_connector(port).is_empty() or _dock_connector(_find_part(owner, args["target_port"])).is_empty():
		return _result("invalid_target")
	var placement := _at(unit, owner["id"])
	if not placement["ok"]:
		return placement
	for id: int in _state["units"]:
		if _state["units"][id]["dock"].get("target_port", 0) == args["target_port"]:
			return _result("connector_occupied")
	return _result()


func _validate_mining(unit: Dictionary, args: Dictionary) -> Dictionary:
	var deposit: int = args.get("deposit", 0)
	var laser := _find_part(unit, args.get("module", 0))
	if not _state["deposits"].has(deposit):
		return _result("unknown_deposit")
	if laser.is_empty() or not _module(laser)["capabilities"].has("mine"):
		return _result("module_missing")
	if not unit["dock"].is_empty():
		return _result("docked")
	var placement := _at(unit, _state["deposits"][deposit]["body"])
	if not placement["ok"]:
		return placement
	if _space_left_g(unit, _state["deposits"][deposit]["item"]) <= 0:
		return _result("cargo_full")
	return _result()


func _unit_of_part(part_id: int) -> Dictionary:
	for id: int in _sorted_keys(_state["units"]):
		if not _find_part(_state["units"][id], part_id).is_empty():
			return _state["units"][id]
	return {}


func _dock_connector(part: Dictionary) -> Dictionary:
	for connector: Dictionary in _module(part)["connectors"]:
		if connector["type"] == "dock":
			return connector
	return {}


# --- Tick ---

func _run_tick() -> void:
	_state["tick"] += 1
	var waiting: Array = []
	for command: Dictionary in _state["queue"]:
		if command["tick"] <= _state["tick"]:
			_apply(command)
		else:
			waiting.append(command)
	_state["queue"] = waiting
	for id: int in _sorted_keys(_state["units"]):
		_advance_unit(_state["units"][id])


func _apply(command: Dictionary) -> void:
	var result := _validate(command)
	if not result["ok"]:
		_emit("command_rejected", command.get("unit", 0), {
			"command": command["id"], "reason": result["reason"], "detail": result["detail"],
		})
		return
	var unit: Dictionary = _state["units"][command["unit"]]
	var args: Dictionary = command.get("args", {})
	match command["type"]:
		"stop":
			_end_task(unit, "task_cancelled", "player_stop")
		"set_priority":
			_find_part(unit, args["module"])["priority"] = args["priority"]
		"move_to":
			_begin(unit, command, "moving", args["target"], 0, _travel_ticks(unit, args["target"]))
			unit["at_target"] = 0
			unit["route"] = {
				"target": args["target"], "from_mm": unit["pos_mm"].duplicate(),
				"to_mm": _arrival_point(unit["pos_mm"], args["target"]), "eta_tick": unit["op"]["end_tick"],
			}
		"scan":
			var scanner := _part_with(unit, "scan")
			_begin(unit, command, "scanning", args["target"], scanner["id"], _module(scanner)["capabilities"]["scan"]["ticks"])
		"dock":
			var ticks: int = _module(_find_part(unit, args["port"]))["capabilities"]["port"]["dock_ticks"]
			_begin(unit, command, "docking", args["target_port"], args["port"], ticks)
		"undock":
			var ticks: int = _module(_find_part(unit, unit["dock"]["port"]))["capabilities"]["port"]["undock_ticks"]
			_begin(unit, command, "undocking", unit["dock"]["target_port"], unit["dock"]["port"], ticks)
		"start_mining":
			_begin(unit, command, "mining", args["deposit"], args["module"], 0)


func _begin(unit: Dictionary, command: Dictionary, op_type: String, target: int, part: int, ticks: int) -> void:
	_end_task(unit, "task_cancelled", "player_order")
	var task := _next_id(_state)
	_state["tasks"][task] = {
		"id": task, "owner": unit["id"], "kind": "order", "state": "running", "reason": "", "hold": false,
		"steps": [{ "type": command["type"], "args": command.get("args", {}).duplicate(true) }],
		"step": 0, "cycle": 0, "since_tick": _state["tick"], "command": command["id"],
	}
	unit["task"] = task
	var now: int = _state["tick"]
	unit["op"] = {
		"type": op_type, "target": target, "part": part, "start_tick": now,
		"end_tick": now + ticks if ticks > 0 else 0,
	}
	_emit("task_started", unit["id"], { "task": task, "command": command["id"] })


func _end_task(unit: Dictionary, event_type: String, reason: String = "") -> void:
	if unit["task"] == 0:
		return
	var task: int = unit["task"]
	var data: Dictionary = { "task": task }
	if event_type == "task_cancelled":
		data["reason"] = reason
	_state["tasks"].erase(task)
	unit["task"] = 0
	unit["op"] = _idle_op()
	unit["route"] = {}
	_emit(event_type, unit["id"], data)


## Not the real heat model: just enough to drive radiator glow.
func _advance_heat(unit: Dictionary) -> void:
	var heat: Dictionary = _unit_view(unit)["heat"]
	var change: int = (heat["input_w"] - heat["reject_w"]) / TICKS_PER_SECOND
	unit["heat_j"] = clampi(unit["heat_j"] + change, 0, heat["limit_j"])


func _advance_unit(unit: Dictionary) -> void:
	_advance_heat(unit)
	var op: Dictionary = unit["op"]
	match op["type"]:
		"moving":
			_advance_move(unit)
		"mining":
			_advance_mining(unit)
		"idle":
			return
		_:
			if _state["tick"] >= op["end_tick"]:
				_finish_timed_op(unit)


func _advance_move(unit: Dictionary) -> void:
	var op: Dictionary = unit["op"]
	var route: Dictionary = unit["route"]
	var done: int = _state["tick"] - op["start_tick"]
	var total: int = op["end_tick"] - op["start_tick"]
	for axis in range(3):
		var span: int = route["to_mm"][axis] - route["from_mm"][axis]
		unit["pos_mm"][axis] = route["from_mm"][axis] + span * mini(done, total) / total
	if done >= total:
		var target: int = route["target"]
		unit["at_target"] = target
		_end_task(unit, "task_finished")
		_emit("arrived", unit["id"], { "target": target })


func _advance_mining(unit: Dictionary) -> void:
	var op: Dictionary = unit["op"]
	var deposit: Dictionary = _state["deposits"][op["target"]]
	var item: String = deposit["item"]
	var rate: int = _module(_find_part(unit, op["part"]))["capabilities"]["mine"]["rate_g_per_s"]
	var amount: int = mini(rate / TICKS_PER_SECOND, mini(deposit["remaining_g"], _space_left_g(unit, item)))
	deposit["remaining_g"] -= amount
	unit["inventory"][item] = unit["inventory"].get(item, 0) + amount
	var reason := ""
	if deposit["remaining_g"] == 0:
		reason = "deposit_exhausted"
	elif _space_left_g(unit, item) <= 0:
		reason = "cargo_full"
	if not reason.is_empty():
		var deposit_id: int = op["target"]
		_end_task(unit, "task_finished")
		_emit("mining_stopped", unit["id"], { "deposit": deposit_id, "grams": amount, "reason": reason })


func _finish_timed_op(unit: Dictionary) -> void:
	var op: Dictionary = unit["op"]
	match op["type"]:
		"scanning":
			_finish_scan(unit, op["target"])
		"docking":
			var owner := _unit_of_part(op["target"])
			unit["dock"] = { "port": op["part"], "target_unit": owner["id"], "target_port": op["target"] }
			unit["pos_mm"] = owner["pos_mm"].duplicate()
			_end_task(unit, "task_finished")
			_emit("docked", unit["id"], { "target": owner["id"] })
		"undocking":
			var target: int = unit["dock"]["target_unit"]
			unit["dock"] = {}
			var host: Array = _state["units"][target]["pos_mm"]
			unit["pos_mm"] = [host[0] + STANDOFF_MM, host[1], host[2]]
			_end_task(unit, "task_finished")
			_emit("undocked", unit["id"], { "target": target })


func _finish_scan(unit: Dictionary, body: int) -> void:
	var found: Array = []
	_state["bodies"][body]["scanned"] = true
	for id: int in _sorted_keys(_state["hidden_deposits"]):
		var deposit: Dictionary = _state["hidden_deposits"][id]
		if deposit["body"] == body:
			_state["deposits"][id] = deposit
			_state["hidden_deposits"].erase(id)
			found.append(id)
			_emit("deposit_found", unit["id"], { "deposit": id, "item": deposit["item"], "grams": deposit["remaining_g"] })
	_end_task(unit, "task_finished")
	_emit("scan_finished", unit["id"], { "target": body, "deposits": found })


func _emit(event_type: String, unit: int, data: Dictionary) -> void:
	if _events.size() >= EVENT_LIMIT:
		_events.pop_front()
	_events.append({ "tick": _state["tick"], "type": event_type, "unit": unit, "data": data })
