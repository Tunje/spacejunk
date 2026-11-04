class_name Units
extends RefCounted
## Unit and part records in the state, and every figure derived from them. All of this is plain
## functions over the state, so tasks, networks and the view share one version of each answer.

const IDLE_OP := "idle"
const STATE_ON := "on"
const STATE_SHED := "shed"
const STATE_FAULT := "fault"
const CLASS_ORDER: Array[String] = ["goods", "ore", "propellant"]


## Creates a unit and its parts from a template, issuing IDs unit first, then parents before
## children in listed order. A core in the template is assigned.
static func create(ctx: SimContext, template_id: String, unit_name: String, pos_mm: Array) -> int:
	var template: Dictionary = ctx.defs["templates"][template_id]
	var id := ctx.new_id()
	var unit := new_record(id, template_id, template["kind"], unit_name, pos_mm)
	ctx.state["units"][id] = unit
	unit["root"] = _create_part(ctx, id, 0, "", "", template["root"])
	for part_id: int in part_ids(ctx.state, id):
		if module_of(ctx.state, ctx.defs, part_id)["capabilities"].has("ai_core"):
			unit["core"] = part_id
	return id


## A unit with no parts.
static func new_record(id: int, def: String, kind: String, unit_name: String, pos_mm: Array) -> Dictionary:
	return {
		"id": id, "def": def, "kind": kind, "name": unit_name, "pos_mm": pos_mm.duplicate(),
		"frame": 0, "orbit": {}, "at_target": 0, "root": 0, "core": 0, "task": 0, "cycle_task": 0, "last_cycle": [],
		"op": { "type": IDLE_OP, "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 },
		"route": {}, "dock": {}, "inventory": {}, "reserved": {},
		"demand_w": 0, "heat_stored_j": 0, "heat_input_w": 0,
		"heat_in_remainder": 0, "heat_out_remainder": 0,
	}


static func _create_part(
	ctx: SimContext, unit: int, parent: int, parent_connector: String, connector: String, node: Dictionary
) -> int:
	var id := add_part(ctx, unit, node["part"], parent, parent_connector, connector)
	for child: Dictionary in node["children"]:
		ctx.state["parts"][id]["children"].append(
			_create_part(ctx, unit, id, child["parent_connector"], child["connector"], child))
	return id


## Issues a part ID and adds the part's record. A new battery is empty.
static func add_part(
	ctx: SimContext, unit: int, def: String, parent: int, parent_connector: String, connector: String
) -> int:
	var id := ctx.new_id()
	ctx.index.erase(unit)
	var module: Dictionary = ctx.defs["modules"][def]
	var part := {
		"id": id, "unit": unit, "def": def, "parent": parent,
		"parent_connector": parent_connector, "connector": connector, "children": [],
		"fault": "", "priority": module["priority"], "shed": false, "shed_until_tick": 0, "draw_w": 0,
	}
	if module["capabilities"].has("battery"):
		part["stored_j"] = 0
		part["charge_remainder"] = 0
		part["discharge_remainder"] = 0
	ctx.state["parts"][id] = part
	return id


## True if a part is allowed to work this tick. Read this from phase 5 on, after allocation.
static func can_run(part: Dictionary) -> bool:
	return part["fault"] == "" and not part["shed"]


## A unit's part IDs in ascending ID order.
static func sorted_part_ids(state: Dictionary, unit_id: int) -> Array[int]:
	var ids := part_ids(state, unit_id)
	ids.sort()
	return ids


static func module_of(state: Dictionary, defs: Dictionary, part_id: int) -> Dictionary:
	return defs["modules"][state["parts"][part_id]["def"]]


## A unit's part IDs, parents before children.
static func part_ids(state: Dictionary, unit_id: int) -> Array[int]:
	var root: int = state["units"][unit_id]["root"]
	return subtree(state, root) if root != 0 else ([] as Array[int])


## A part and everything below it, parents before children.
static func subtree(state: Dictionary, part_id: int) -> Array[int]:
	var result: Array[int] = [part_id]
	for child: int in state["parts"][part_id]["children"]:
		result.append_array(subtree(state, child))
	return result


static func installed_mass(state: Dictionary, defs: Dictionary, unit_id: int) -> int:
	var total := 0
	for part_id in part_ids(state, unit_id):
		total += module_of(state, defs, part_id)["mass_g"]
	return total


static func subtree_mass(state: Dictionary, defs: Dictionary, part_id: int) -> int:
	var total := 0
	for id in subtree(state, part_id):
		total += module_of(state, defs, id)["mass_g"]
	return total


static func inventory_mass(state: Dictionary, unit_id: int) -> int:
	var total := 0
	var inventory: Dictionary = state["units"][unit_id]["inventory"]
	for item: String in inventory:
		total += inventory[item]
	return total


static func unit_mass(state: Dictionary, defs: Dictionary, unit_id: int) -> int:
	return installed_mass(state, defs, unit_id) + inventory_mass(state, unit_id)


## Volume of a stack. Recalculated from its grams each time, never accumulated.
static func litres(grams: int, density_g_l: int) -> int:
	return (grams + density_g_l - 1) / density_g_l


## Capacity and use per cargo class. `without` lists parts to leave out, and `extra` lists stock
## to count as if it were in the inventory, so a change can be tested before it happens.
static func cargo(
	state: Dictionary, defs: Dictionary, unit_id: int, without: Array[int] = [], extra: Dictionary = {}
) -> Dictionary:
	var result := {}
	for part_id in part_ids(state, unit_id):
		if without.has(part_id):
			continue
		var storage: Dictionary = module_of(state, defs, part_id)["capabilities"].get("storage", {})
		for cargo_class: String in storage:
			var entry := class_entry(result, cargo_class)
			entry["cap_g"] += storage[cargo_class]["mass_g"]
			entry["cap_l"] += storage[cargo_class]["volume_l"]
	add_cargo_use(result, state, defs, unit_id, extra)
	return result


## Adds a unit's stock and reserved space to a table of cargo classes.
static func add_cargo_use(
	table: Dictionary, state: Dictionary, defs: Dictionary, unit_id: int, extra: Dictionary
) -> void:
	var unit: Dictionary = state["units"][unit_id]
	var inventory: Dictionary = unit["inventory"]
	if not extra.is_empty():
		inventory = inventory.duplicate()
		for item: String in extra:
			inventory[item] = inventory.get(item, 0) + extra[item]
	for item: String in inventory:
		var item_def: Dictionary = defs["items"][item]
		var entry := class_entry(table, item_def["cargo_class"])
		entry["used_g"] += inventory[item]
		entry["used_l"] += litres(inventory[item], item_def["density_g_l"])
	var reserved: Dictionary = unit["reserved"]
	for cargo_class: String in reserved:
		var entry := class_entry(table, cargo_class)
		entry["reserved_g"] = reserved[cargo_class]["g"]
		entry["reserved_l"] = reserved[cargo_class]["l"]


static func class_entry(table: Dictionary, cargo_class: String) -> Dictionary:
	return table.get_or_add(cargo_class, {
		"used_g": 0, "cap_g": 0, "used_l": 0, "cap_l": 0, "reserved_g": 0, "reserved_l": 0,
	})


## The first class over capacity, counting reserved space, as { need_g, have_g }, or {} if none.
static func over_capacity(table: Dictionary) -> Dictionary:
	for cargo_class in CLASS_ORDER:
		if not table.has(cargo_class):
			continue
		var entry: Dictionary = table[cargo_class]
		if entry["used_g"] + entry["reserved_g"] > entry["cap_g"]:
			return { "need_g": entry["used_g"] + entry["reserved_g"], "have_g": entry["cap_g"] }
		if entry["used_l"] + entry["reserved_l"] > entry["cap_l"]:
			return { "need_l": entry["used_l"] + entry["reserved_l"], "have_l": entry["cap_l"] }
	return {}


## Declared limits and ratings, with the modules in `extra` added and `carried_g` more mass, so
## fitting can test a change first. Mass counts the inventory.
static func fit(
	state: Dictionary, defs: Dictionary, unit_id: int, extra: Array[Dictionary] = [],
	carried_g: int = 0
) -> Dictionary:
	var modules: Array[Dictionary] = extra.duplicate()
	for part_id in part_ids(state, unit_id):
		modules.append(module_of(state, defs, part_id))
	var result := {
		"mass_g": unit_mass(state, defs, unit_id) + carried_g, "mass_limit_g": 0,
		"power_budget_w": 0, "power_rated_w": 0, "heat_budget_w": 0, "heat_rated_w": 0,
	}
	for module: Dictionary in modules:
		var capabilities: Dictionary = module["capabilities"]
		result["mass_limit_g"] += capabilities.get("max_mass_g", 0)
		result["power_rated_w"] += module["power_w"]
		result["heat_rated_w"] += module["heat_w"]
		result["power_budget_w"] += capabilities.get("generate", {}).get("power_w", 0) \
			+ capabilities.get("battery", {}).get("max_discharge_w", 0)
		result["heat_budget_w"] += capabilities.get("radiator", {}).get("reject_w", 0)
	return result


static func connector_of(module: Dictionary, connector_id: String) -> Dictionary:
	for connector: Dictionary in module["connectors"]:
		if connector["id"] == connector_id:
			return connector
	return {}


## The child mated to a connector, or 0.
static func child_at(state: Dictionary, part_id: int, connector_id: String) -> int:
	for child: int in state["parts"][part_id]["children"]:
		if state["parts"][child]["parent_connector"] == connector_id:
			return child
	return 0


static func are_docked(state: Dictionary, a: int, b: int) -> bool:
	var units: Dictionary = state["units"]
	return units[a]["dock"].get("target_unit", 0) == b or units[b]["dock"].get("target_unit", 0) == a


## True if a unit is at a body or unit. This is the one test of placement (networks.md section 6).
static func at(state: Dictionary, unit_id: int, target: int) -> bool:
	return target != 0 and state["units"][unit_id]["at_target"] == target


## True if a port part has a unit docked at it, on either side of the dock, or is promised to one.
static func port_in_use(state: Dictionary, part_id: int) -> bool:
	if state["parts"][part_id].get("claimed_by", 0) != 0:
		return true
	var units: Dictionary = state["units"]
	for id: int in units:
		var dock: Dictionary = units[id]["dock"]
		if dock.get("port", 0) == part_id or dock.get("target_port", 0) == part_id:
			return true
	return false


## A unit's parts with the `port` capability, in part ID order.
static func ports(state: Dictionary, defs: Dictionary, unit_id: int) -> Array[int]:
	var result: Array[int] = []
	for part_id in part_ids(state, unit_id):
		if module_of(state, defs, part_id)["capabilities"].has("port"):
			result.append(part_id)
	result.sort()
	return result


## How many grams of an item a unit can still take (networks.md section 5). `incoming` lists stock
## already promised to the unit this tick.
static func grams_that_fit(
	state: Dictionary, defs: Dictionary, unit_id: int, item: String, incoming: Dictionary = {}
) -> int:
	var item_def: Dictionary = defs["items"][item]
	var table := cargo(state, defs, unit_id, [] as Array[int], incoming)
	var entry: Dictionary = table.get(item_def["cargo_class"], {})
	if entry.is_empty():
		return 0
	var density: int = item_def["density_g_l"]
	var held_g: int = state["units"][unit_id]["inventory"].get(item, 0) + incoming.get(item, 0)
	var litres_left: int = entry["cap_l"] - entry["used_l"] - entry["reserved_l"] + litres(held_g, density)
	var by_volume := IntMath.mul_div(maxi(0, litres_left), density, 1) - held_g
	var fits := maxi(0, mini(entry["cap_g"] - entry["used_g"] - entry["reserved_g"], by_volume))
	var unit_mass_g: int = item_def.get("unit_mass_g", 0)
	return fits - fits % unit_mass_g if unit_mass_g != 0 else fits


## Moves grams into a stack.
static func add_stock(inventory: Dictionary, item: String, grams: int) -> void:
	inventory[item] = inventory.get(item, 0) + grams


## Moves grams out of a stack. An empty stack leaves the inventory.
static func remove_stock(inventory: Dictionary, item: String, grams: int) -> void:
	inventory[item] -= grams
	if inventory[item] == 0:
		inventory.erase(item)


## Discrete stacks that are not a whole multiple of their unit mass.
static func broken_stacks(state: Dictionary, defs: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	var units: Dictionary = state["units"]
	for id: int in units:
		var inventory: Dictionary = units[id]["inventory"]
		for item: String in inventory:
			var unit_mass_g: int = defs["items"].get(item, {}).get("unit_mass_g", 0)
			if unit_mass_g != 0 and inventory[item] % unit_mass_g != 0:
				found.append("unit %d holds part of a unit of %s" % [id, item])
	return found
