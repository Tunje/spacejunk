class_name StubSim extends RefCounted
## Stand-in for Sim (contracts section 3) until the kernel lands.
## Same API and view shape, with just enough behaviour to drive the client.
## Commands the stub does not model are rejected with `not_in_stub`.

const TICKS_PER_SECOND := 10
const SCENARIO_ID := "stub"
## The stub scenario with extra ships, well above the slice's real craft count.
const SCENARIO_LOAD := "stub_load"
const LOAD_EXTRA_SHIPS := 11
const LOAD_SHIP_SPACING_MM := 40000
const DATA_DIR := "res://client/stub/data/"
const SAVE_HEADER := "stub-save:2\n"
const SAVE_PREFIX := "stub-save:"
const EVENT_LIMIT := 4096

const STANDOFF_MM := 150000
## C9: jobs on one facility, counting the active one.
const QUEUE_LIMIT := 16
const JOB_VIEW_FIELDS: Array[String] = [
	"unit", "facility", "recipe", "count_left", "status", "reason", "start_tick", "end_tick", "queue_pos",
]
## Statuses of an active job that move_job refuses with job_busy.
const BUSY_STATUSES: Array[String] = ["running", "paused", "cancelling"]

static var _last_error := ""

var _state: Dictionary = {}
var _defs: Dictionary = {}
var _events: Array[Dictionary] = []


static func new_game(scenario_id: String, seed_value: int) -> StubSim:
	_last_error = ""
	if scenario_id != SCENARIO_ID and scenario_id != SCENARIO_LOAD:
		_last_error = "unknown_scenario"
		return null
	var sim := StubSim.new()
	sim._defs = _load_defs()
	var extra_ships := LOAD_EXTRA_SHIPS if scenario_id == SCENARIO_LOAD else 0
	sim._state = _build_state(sim._defs, seed_value, extra_ships)
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
		"jobs": _jobs_view(),
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
	for id: int in _state["jobs"]:
		for item: String in _state["jobs"][id]["held"]:
			matter += _state["jobs"][id]["held"][item]
	return { "matter_g": matter }


# --- Scenario ---

static func _load_defs() -> Dictionary:
	return {
		"modules": _index_by_id(_convert(_read_json("modules.json"))),
		"items": _index_by_id(_convert(_read_json("items.json"))),
		"recipes": _index_by_id(_convert(_read_json("recipes.json"))),
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


static func _build_state(module_defs: Dictionary, seed_value: int, extra_ships: int) -> Dictionary:
	var scenario: Dictionary = _convert(_read_json("scenario.json"))
	var state: Dictionary = {
		"tick": 0, "seed": seed_value, "next_id": 1, "next_command": 1, "queue": [],
		"units": {}, "bodies": {}, "deposits": {}, "hidden_deposits": {}, "tasks": {}, "jobs": {},
	}
	_add_extra_ships(scenario["units"], extra_ships)
	var body_ids: Dictionary = {}
	for entry: Dictionary in scenario["bodies"]:
		var id := _next_id(state)
		body_ids[entry["ref"]] = id
		state["bodies"][id] = {
			"kind": entry["kind"], "name": "Star" if entry["kind"] == "star" else "Asteroid %d" % id,
			"pos_mm": entry["pos_mm"], "radius_mm": entry["radius_mm"],
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


static func _add_extra_ships(units: Array, count: int) -> void:
	var template: Dictionary = units[units.size() - 1]
	for index in range(count):
		var ship: Dictionary = template.duplicate(true)
		ship["name"] = "Probe %d" % (index + 2)
		ship["pos_mm"][2] += LOAD_SHIP_SPACING_MM * (index + 1)
		units.append(ship)


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
	shown["fit"] = _fit(unit)
	shown["power"] = {
		"supply_w": supply, "demand_w": demand, "stored_j": 0, "capacity_j": 0, "max_discharge_w": 0,
	}
	shown["heat"] = {
		"stored_j": unit["heat_j"], "limit_j": _capability_sum(unit, "heat_capacity", "limit_j"),
		"reject_w": reject, "input_w": waste,
	}
	return shown


## The view's `fit`, with `extra` modules counted as if fitted. `carried_g` is
## mass that arrives from another unit, matching Units.fit in the kernel.
func _fit(unit: Dictionary, extra: Array[Dictionary] = [], carried_g: int = 0) -> Dictionary:
	var modules: Array[Dictionary] = extra.duplicate()
	for part: Dictionary in _flat_parts(unit["parts"]):
		modules.append(_module(part))
	var fit: Dictionary = {
		"mass_g": _parts_mass(unit["parts"]) + carried_g, "mass_limit_g": 0,
		"power_budget_w": 0, "power_rated_w": 0, "heat_budget_w": 0, "heat_rated_w": 0,
	}
	for item: String in unit["inventory"]:
		fit["mass_g"] += unit["inventory"][item]
	for module: Dictionary in modules:
		var capabilities: Dictionary = module["capabilities"]
		fit["mass_limit_g"] += capabilities.get("max_mass_g", 0)
		fit["power_budget_w"] += capabilities.get("generate", {}).get("power_w", 0)
		fit["heat_budget_w"] += capabilities.get("radiator", {}).get("reject_w", 0)
		fit["power_rated_w"] += module["power_w"]
		fit["heat_rated_w"] += module["heat_w"]
	return fit


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
		"attach_part":
			return _validate_attach(unit, args)
		"detach_part":
			return _validate_detach(unit, args)
		"start_job":
			return _validate_queue(unit, args, true)
		"queue_job":
			return _validate_queue(unit, args, false)
		"move_job":
			return _validate_move_job(unit, args)
		"cancel_job":
			return _validate_cancel_job(unit, args)
		"copy_fit":
			return _validate_copy_fit(unit, args)
	return _result("not_in_stub")


func _partner_problem(unit: Dictionary, other: int) -> String:
	if other == unit["id"]:
		return ""
	if not _state["units"].has(other):
		return "unknown_unit"
	return "" if unit["dock"].get("target_unit", 0) == other else "not_docked"


func _validate_attach(unit: Dictionary, args: Dictionary) -> Dictionary:
	var from: int = args.get("from", 0)
	var problem := _partner_problem(unit, from)
	if not problem.is_empty():
		return _result(problem)
	return _validate_attach_parts(unit, args)


## Attach checks once the stock's unit is known to be within reach.
func _validate_attach_parts(unit: Dictionary, args: Dictionary) -> Dictionary:
	var from: int = args.get("from", 0)
	var item: String = args.get("item", "")
	if not _defs["modules"].has(item):
		return _result("invalid_target")
	var module: Dictionary = _defs["modules"][item]
	var parent := _find_part(unit, args.get("parent_part", 0))
	if parent.is_empty():
		return _result("unknown_part")
	var held: int = _state["units"][from]["inventory"].get(item, 0)
	if held < module["mass_g"]:
		return _result("missing_inputs", { "need_g": module["mass_g"], "have_g": held })
	var parent_end := _connector(_module(parent), args.get("parent_connector", ""))
	var part_end := _connector(module, args.get("part_connector", ""))
	if parent_end.is_empty() or part_end.is_empty():
		return _result("invalid_target")
	var carried: int = 0 if from == unit["id"] else module["mass_g"]
	var fit := _fit(unit, [module] as Array[Dictionary], carried)
	var failure := _fit_failure(fit, parent, parent_end, part_end, module["mass_g"])
	if failure.is_empty():
		return _result("", fit)
	var detail: Dictionary = fit.duplicate()
	detail.merge(failure["detail"])
	return _result(failure["reason"], detail)


## Same order as FittingSystem._fit_failure, so check 10 reads alike on both.
func _fit_failure(fit: Dictionary, parent: Dictionary, parent_end: Dictionary, part_end: Dictionary, mass_g: int) -> Dictionary:
	if parent_end["type"] != part_end["type"] or parent_end["type"] == "dock":
		return { "reason": "connector_type_mismatch", "detail": {} }
	if (parent_end["size"] == "core") != (part_end["size"] == "core"):
		return { "reason": "connector_size_mismatch", "detail": {} }
	for child: Dictionary in parent["children"]:
		if child["parent_connector"] == parent_end["id"]:
			return { "reason": "connector_occupied", "detail": {} }
	if mass_g > parent_end["load_limit_g"]:
		return { "reason": "over_load_limit", "detail": { "need_g": mass_g, "have_g": parent_end["load_limit_g"] } }
	if fit["mass_g"] > fit["mass_limit_g"]:
		return { "reason": "over_mass_limit", "detail": { "need_g": fit["mass_g"], "have_g": fit["mass_limit_g"] } }
	if fit["power_rated_w"] > fit["power_budget_w"]:
		return { "reason": "over_power_budget", "detail": { "need_w": fit["power_rated_w"], "have_w": fit["power_budget_w"] } }
	if fit["heat_rated_w"] > fit["heat_budget_w"]:
		return { "reason": "over_heat_budget", "detail": { "need_w": fit["heat_rated_w"], "have_w": fit["heat_budget_w"] } }
	return {}


func _connector(module: Dictionary, connector_id: String) -> Dictionary:
	for connector: Dictionary in module["connectors"]:
		if connector["id"] == connector_id:
			return connector
	return {}


func _validate_detach(unit: Dictionary, args: Dictionary) -> Dictionary:
	var to: int = args.get("to", 0)
	var problem := _partner_problem(unit, to)
	if not problem.is_empty():
		return _result(problem)
	var part := _find_part(unit, args.get("part", 0))
	if part.is_empty():
		return _result("unknown_part")
	if part["id"] == unit["parts"]["id"]:
		return _result("root_part")
	for removed: Dictionary in _flat_parts(part):
		if removed["id"] == unit["dock"].get("port", 0):
			return _result("port_busy")
		if removed["id"] == unit["op"]["part"]:
			return _result("part_busy")
	return _result("", _fit(unit))


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
	_advance_jobs()


func _apply(command: Dictionary) -> void:
	var result := _validate(command)
	if not result["ok"]:
		var is_fit_failure: bool = command.get("type", "") == "attach_part" and result["detail"].has("mass_limit_g")
		var data: Dictionary = { "command": command["id"], "reason": result["reason"], "detail": result["detail"] }
		if is_fit_failure:
			data["item"] = command["args"]["item"]
		_emit("attach_failed" if is_fit_failure else "command_rejected", command.get("unit", 0), data)
		return
	var unit: Dictionary = _state["units"][command["unit"]]
	var args: Dictionary = command.get("args", {})
	match command["type"]:
		"stop":
			_end_task(unit, "task_cancelled", "player_stop")
		"set_priority":
			_find_part(unit, args["module"])["priority"] = args["priority"]
		"attach_part":
			_apply_attach(unit, args)
		"detach_part":
			_apply_detach(unit, args)
		"start_job", "queue_job":
			_apply_queue(unit, command)
		"move_job":
			_apply_move_job(args)
		"cancel_job":
			_apply_cancel_job(args["job"])
		"copy_fit":
			var plan := _plan_copy(unit, args["source"], args["from"], true)
			_emit("fit_copied", unit["id"], {
				"source": args["source"], "attached": plan["attached"], "missing": plan["missing"], "refused": plan["refused"],
			})
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


func _apply_attach(unit: Dictionary, args: Dictionary, announce := true) -> void:
	var item: String = args["item"]
	var stock: Dictionary = _state["units"][args["from"]]["inventory"]
	stock[item] -= _defs["modules"][item]["mass_g"]
	if stock[item] == 0:
		stock.erase(item)
	var part := _build_part(_state, _defs, {
		"def": item, "parent_connector": args["parent_connector"], "connector": args["part_connector"], "children": [],
	})
	_find_part(unit, args["parent_part"])["children"].append(part)
	if announce:
		_emit("part_attached", unit["id"], { "part": part["id"] })


func _apply_detach(unit: Dictionary, args: Dictionary) -> void:
	var part := _find_part(unit, args["part"])
	var stock: Dictionary = _state["units"][args["to"]]["inventory"]
	for removed: Dictionary in _flat_parts(part):
		stock[removed["def"]] = stock.get(removed["def"], 0) + _module(removed)["mass_g"]
	for candidate: Dictionary in _flat_parts(unit["parts"]):
		candidate["children"] = candidate["children"].filter(func(child: Dictionary) -> bool: return child["id"] != part["id"])
	_emit("part_detached", unit["id"], { "part": args["part"] })


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


# --- Jobs (C9 queue, simplified: no power, and a fault only refuses new jobs) ---

func _jobs_view() -> Dictionary:
	var shown: Dictionary = {}
	for id: int in _sorted_keys(_state["jobs"]):
		var job: Dictionary = {}
		for field: String in JOB_VIEW_FIELDS:
			job[field] = _state["jobs"][id][field]
		shown[id] = job
	return shown


## The facility's jobs, the active one first, then by queue position.
func _facility_jobs(facility: int) -> Array[int]:
	var found: Array[int] = []
	for id: int in _sorted_keys(_state["jobs"]):
		if _state["jobs"][id]["facility"] == facility:
			found.append(id)
	found.sort_custom(func(a: int, b: int) -> bool: return _state["jobs"][a]["queue_pos"] < _state["jobs"][b]["queue_pos"])
	return found


func _validate_queue(unit: Dictionary, args: Dictionary, start_only: bool) -> Dictionary:
	var part := _find_part(unit, args.get("facility", 0))
	if part.is_empty():
		return _result("unknown_part")
	var facility: Dictionary = _module(part)["capabilities"].get("facility", {})
	if facility.is_empty():
		return _result("invalid_target")
	var recipe: Dictionary = _defs["recipes"].get(args.get("recipe", ""), {})
	if recipe.is_empty():
		return _result("unknown_recipe")
	if recipe["facility"] != facility["type"]:
		return _result("wrong_facility")
	var count: Variant = args.get("count", 0)
	if not count is int or count < 1:
		return _result("malformed_command")
	if part["state"] == "fault":
		return _result("module_fault")
	var queued := _facility_jobs(part["id"]).size()
	if start_only and queued > 0:
		return _result("facility_busy")
	if queued >= QUEUE_LIMIT:
		return _result("queue_full")
	return _result()


func _validate_move_job(unit: Dictionary, args: Dictionary) -> Dictionary:
	var job: Dictionary = _state["jobs"].get(args.get("job", 0), {})
	if job.is_empty() or job["unit"] != unit["id"]:
		return _result("unknown_job")
	if not args.get("position", 0) is int:
		return _result("malformed_command")
	if job["queue_pos"] == 0 and BUSY_STATUSES.has(job["status"]):
		return _result("job_busy")
	return _result()


func _validate_cancel_job(unit: Dictionary, args: Dictionary) -> Dictionary:
	var job: Dictionary = _state["jobs"].get(args.get("job", 0), {})
	return _result() if not job.is_empty() and job["unit"] == unit["id"] else _result("unknown_job")


func _apply_queue(unit: Dictionary, command: Dictionary) -> void:
	var args: Dictionary = command["args"]
	var position := _facility_jobs(args["facility"]).size()
	var id := _next_id(_state)
	_state["jobs"][id] = {
		"unit": unit["id"], "facility": args["facility"], "recipe": args["recipe"], "count_left": args["count"],
		"status": "waiting" if position == 0 else "queued", "reason": "", "start_tick": 0, "end_tick": 0,
		"queue_pos": position, "held": {}, "started": false,
	}
	_emit("job_queued", unit["id"], { "job": id, "command": command["id"], "position": position })


## Positions are 1-based among the queued jobs. Moving the active job back hands
## the facility to the first queued job.
func _apply_move_job(args: Dictionary) -> void:
	var job_id: int = args["job"]
	var order := _facility_jobs(_state["jobs"][job_id]["facility"])
	order.erase(job_id)
	if order.is_empty():
		return
	var queued: Array = order.slice(1)
	var at := clampi(args["position"], 1, queued.size() + 1)
	queued.insert(at - 1, job_id)
	_renumber([order[0]] + queued)
	_emit("job_moved", _state["jobs"][job_id]["unit"], { "job": job_id, "position": _state["jobs"][job_id]["queue_pos"] })


func _apply_cancel_job(job_id: int) -> void:
	var job: Dictionary = _state["jobs"][job_id]
	var stock: Dictionary = _state["units"][job["unit"]]["inventory"]
	for item: String in job["held"]:
		stock[item] = stock.get(item, 0) + job["held"][item]
	_state["jobs"].erase(job_id)
	_renumber(_facility_jobs(job["facility"]))
	_emit("job_cancelled", job["unit"], { "job": job_id, "recipe": job["recipe"], "facility": job["facility"] })


func _renumber(order: Array) -> void:
	for index in range(order.size()):
		var job: Dictionary = _state["jobs"][order[index]]
		job["queue_pos"] = index
		if index == 0 and job["status"] == "queued":
			job["status"] = "waiting"
		elif index > 0:
			job["status"] = "queued"
			job["reason"] = ""


## A finished job leaves its facility empty for the rest of the tick, so the next
## one starts the tick after.
func _advance_jobs() -> void:
	var emptied: Array[int] = []
	for id: int in _sorted_keys(_state["jobs"]):
		var job: Dictionary = _state["jobs"][id]
		if job["queue_pos"] != 0:
			continue
		if job["status"] == "running" and _state["tick"] >= job["end_tick"]:
			if _finish_run(id):
				emptied.append(job["facility"])
		elif job["status"] == "waiting":
			_try_start(id)
	for facility: int in emptied:
		_renumber(_facility_jobs(facility))


func _try_start(id: int) -> void:
	var job: Dictionary = _state["jobs"][id]
	var recipe: Dictionary = _defs["recipes"][job["recipe"]]
	var stock: Dictionary = _state["units"][job["unit"]]["inventory"]
	for input: Dictionary in recipe["inputs"]:
		if stock.get(input["item"], 0) < input["grams"]:
			if job["reason"] != "missing_inputs":
				job["reason"] = "missing_inputs"
				_emit("job_paused", job["unit"], { "job": id, "reason": "missing_inputs" })
			return
	for input: Dictionary in recipe["inputs"]:
		stock[input["item"]] -= input["grams"]
		if stock[input["item"]] == 0:
			stock.erase(input["item"])
		job["held"][input["item"]] = job["held"].get(input["item"], 0) + input["grams"]
	if job["reason"] == "missing_inputs":
		_emit("job_resumed", job["unit"], { "job": id, "reason": "missing_inputs" })
	job["status"] = "running"
	job["reason"] = ""
	job["start_tick"] = _state["tick"]
	job["end_tick"] = _state["tick"] + recipe["ticks"]
	if not job["started"]:
		job["started"] = true
		_emit("job_started", job["unit"], { "job": id, "command": 0 })


## True when that was the job's last run, so it has left the facility.
func _finish_run(id: int) -> bool:
	var job: Dictionary = _state["jobs"][id]
	var recipe: Dictionary = _defs["recipes"][job["recipe"]]
	var stock: Dictionary = _state["units"][job["unit"]]["inventory"]
	job["held"] = {}
	for output: Dictionary in recipe["outputs"]:
		stock[output["item"]] = stock.get(output["item"], 0) + output["grams"]
	_emit("job_finished", job["unit"], { "job": id, "recipe": job["recipe"], "facility": job["facility"] })
	job["count_left"] -= 1
	job["start_tick"] = 0
	job["end_tick"] = 0
	if job["count_left"] > 0:
		job["status"] = "waiting"
		_try_start(id)
		return false
	_state["jobs"].erase(id)
	return true


# --- Copy fit (C9) ---

func _validate_copy_fit(unit: Dictionary, args: Dictionary) -> Dictionary:
	var source_id: int = args.get("source", 0)
	if not _state["units"].has(source_id):
		return _result("unknown_unit")
	if source_id == unit["id"]:
		return _result("invalid_target")
	var from: int = args.get("from", 0)
	var problem := _partner_problem(unit, from)
	var docked_here: bool = _state["units"].get(from, {}).get("dock", {}).get("target_unit", 0) == unit["id"]
	if not problem.is_empty() and not docked_here:
		return _result(problem)
	if _state["units"][source_id]["parts"]["def"] != unit["parts"]["def"]:
		return _result("fit_mismatch")
	var plan := _plan_copy(unit, source_id, from, false)
	var missing := 0
	for item: String in plan["missing"]:
		missing += plan["missing"][item]
	return _result("", { "attach": plan["attached"].size(), "missing": missing, "refused": plan["refused"].size() })


## Walks the source's tree and fits each part this unit lacks at the same place.
## With `apply` false it works on a copy of the state, so check() changes nothing.
func _plan_copy(unit: Dictionary, source_id: int, from: int, apply: bool) -> Dictionary:
	var sim: StubSim = self
	if not apply:
		sim = StubSim.new()
		sim._defs = _defs
		sim._state = _state.duplicate(true)
	var plan: Dictionary = { "attached": [], "missing": {}, "refused": [] }
	var source: Dictionary = sim._state["units"][source_id]
	var target: Dictionary = sim._state["units"][unit["id"]]
	sim._copy_children(target, source["parts"], target["parts"], from, plan)
	return plan


func _copy_children(unit: Dictionary, source_part: Dictionary, target_part: Dictionary, from: int, plan: Dictionary) -> void:
	for child: Dictionary in source_part["children"]:
		if _module(child)["capabilities"].has("core"):
			continue
		var placed := _child_at(target_part, child["parent_connector"])
		if placed.is_empty():
			placed = _copy_one(unit, child, target_part, from, plan)
		elif placed["def"] != child["def"]:
			plan["refused"].append({ "source_part": child["id"], "item": child["def"], "reason": "connector_occupied" })
			placed = {}
		if placed.is_empty():
			_skip_subtree(child, plan)
		else:
			_copy_children(unit, child, placed, from, plan)


func _copy_one(unit: Dictionary, child: Dictionary, parent: Dictionary, from: int, plan: Dictionary) -> Dictionary:
	var args: Dictionary = {
		"item": child["def"], "from": from, "parent_part": parent["id"],
		"parent_connector": child["parent_connector"], "part_connector": child["connector"],
	}
	var result := _validate_attach_parts(unit, args)
	if result["reason"] == "missing_inputs":
		plan["missing"][child["def"]] = plan["missing"].get(child["def"], 0) + 1
		return {}
	if not result["ok"]:
		plan["refused"].append({ "source_part": child["id"], "item": child["def"], "reason": result["reason"] })
		return {}
	_apply_attach(unit, args, false)
	var added := _child_at(parent, child["parent_connector"])
	plan["attached"].append(added["id"])
	return added


## Parts below one that could not be fitted are counted as missing.
func _skip_subtree(part: Dictionary, plan: Dictionary) -> void:
	for child: Dictionary in part["children"]:
		plan["missing"][child["def"]] = plan["missing"].get(child["def"], 0) + 1
		_skip_subtree(child, plan)


func _child_at(parent: Dictionary, connector: String) -> Dictionary:
	for child: Dictionary in parent["children"]:
		if child["parent_connector"] == connector:
			return child
	return {}
