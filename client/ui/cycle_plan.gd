class_name CyclePlan extends RefCounted
## Turns a trip flown by hand into a cycle for any craft, and describes cycles in
## words. Whether a cycle is valid is left to Sim.check.

const CYCLE_STEPS: Array[String] = ["move_to", "dock", "undock", "load_cargo", "unload_cargo", "start_mining"]
const MAX_STEPS := 16
const PROPELLANT_CLASS := "propellant"


## Adds an issued order to a trip log. Undocking starts a new trip, and a second
## move in a row replaces the first, since the player only changed their mind.
static func record(trip: Array[Dictionary], command: Dictionary) -> void:
	var type: String = command["type"]
	if not CYCLE_STEPS.has(type):
		return
	if type == "undock":
		trip.clear()
	if type == "move_to" and not trip.is_empty() and trip[trip.size() - 1]["type"] == "move_to":
		trip.pop_back()
	trip.append({ "type": type, "args": command["args"].duplicate(true) })
	if trip.size() > MAX_STEPS:
		trip.pop_front()


## Rebuilds a trip for `unit_id`: its own laser and port replace the ones the
## trip was flown with, and a propellant load is added if the trip left it out.
static func adapt(trip: Array[Dictionary], unit_id: int, view: Dictionary, defs: Dictionary) -> Array[Dictionary]:
	var unit: Dictionary = view["units"][unit_id]
	var modules: Dictionary = defs["modules"]
	var used := OrderList.ports_in_use(view)
	var own_dock: Dictionary = unit["dock"]
	if not own_dock.is_empty():
		used.erase(own_dock["port"])
		used.erase(own_dock["target_port"])
	var steps: Array[Dictionary] = []
	for step: Dictionary in trip:
		var copy: Dictionary = step.duplicate(true)
		match copy["type"]:
			"start_mining":
				copy["args"]["module"] = OrderList._part_with_capability(unit["parts"], modules, "mine")
			"dock":
				copy["args"]["port"] = OrderList.free_port(unit["parts"], modules, used)
				var host := CyclePlan.unit_of_part(view, copy["args"]["target_port"])
				if host != 0:
					copy["args"]["target_port"] = OrderList.free_port(view["units"][host]["parts"], modules, used)
		steps.append(copy)
	CyclePlan._add_propellant_load(steps, view, defs)
	return steps


static func _add_propellant_load(steps: Array[Dictionary], view: Dictionary, defs: Dictionary) -> void:
	var host := 0
	for step: Dictionary in steps:
		if step["type"] == "load_cargo" and defs["items"][step["args"]["item"]]["cargo_class"] == PROPELLANT_CLASS:
			return
		if step["type"] == "dock":
			host = CyclePlan.unit_of_part(view, step["args"]["target_port"])
	if host == 0 or steps.size() >= MAX_STEPS:
		return
	for item: String in view["units"][host]["inventory"]:
		if defs["items"].has(item) and defs["items"][item]["cargo_class"] == PROPELLANT_CLASS:
			steps.append({ "type": "load_cargo", "args": { "from": host, "item": item } })
			return


static func unit_of_part(view: Dictionary, part_id: int) -> int:
	for id: int in view["units"]:
		for part: Dictionary in InspectText.flatten(view["units"][id]["parts"]):
			if part["id"] == part_id:
				return id
	return 0


static func cycle_command(unit_id: int, steps: Array[Dictionary]) -> Dictionary:
	return { "type": "set_cycle", "unit": unit_id, "args": { "steps": steps } }


## The unit's cycle, even while an order overrides it, or {}.
static func running_cycle(unit: Dictionary, view: Dictionary) -> Dictionary:
	if unit["cycle_task"] != 0:
		return view["tasks"].get(unit["cycle_task"], {})
	var task: Dictionary = view["tasks"].get(unit["task"], {})
	return task if task.get("kind", "") == "cycle" else {}


static func step_text(step: Dictionary, view: Dictionary, defs: Dictionary) -> String:
	var args: Dictionary = step["args"]
	match step["type"]:
		"move_to":
			return "Fly to %s" % CyclePlan.target_name(args["target"], view)
		"dock":
			return "Dock at %s" % CyclePlan.target_name(CyclePlan.unit_of_part(view, args["target_port"]), view)
		"undock":
			return "Undock"
		"load_cargo":
			return "Load %s" % IndustryLogic.name_of(args["item"], defs)
		"unload_cargo":
			return "Unload %s" % IndustryLogic.name_of(args["item"], defs)
		"start_mining":
			var deposit: Dictionary = view["deposits"].get(args["deposit"], {})
			return "Mine %s" % IndustryLogic.name_of(deposit.get("item", "ore"), defs)
	return step["type"].capitalize()


static func target_name(id: int, view: Dictionary) -> String:
	if view["bodies"].has(id):
		return view["bodies"][id]["name"]
	if view["units"].has(id):
		return view["units"][id]["name"]
	return "unknown"


## Why a cycle is blocked, in words. A body fault also takes the core offline, so
## the fault that caused it is named alongside.
static func block_text(task: Dictionary, unit: Dictionary, modules: Dictionary) -> String:
	if task.get("state", "") != "blocked":
		return ""
	var text := OrderText.reason(task["reason"])
	if task["reason"] == "core_offline" or task["reason"] == "module_fault":
		var fault := CyclePlan.first_fault(unit)
		if not fault.is_empty():
			text += ": %s, %s" % [modules[fault["def"]]["name"], OrderText.reason(fault["fault"])]
	return text


static func first_fault(unit: Dictionary) -> Dictionary:
	for part: Dictionary in InspectText.flatten(unit["parts"]):
		if not part["fault"].is_empty():
			return part
	return {}


## Fitted AI cores, as { part, name, tier }.
static func cores(unit: Dictionary, modules: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for part: Dictionary in InspectText.flatten(unit["parts"]):
		var module: Dictionary = modules[part["def"]]
		if module["capabilities"].has("ai_core"):
			found.append({ "part": part["id"], "name": module["name"], "tier": module["capabilities"]["ai_core"]["tier"] })
	return found
