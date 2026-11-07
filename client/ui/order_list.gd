class_name OrderList extends RefCounted
## Works out which orders make sense for the commanded unit and the selection.
## Whether each one is currently valid is left to Sim.check.

const SHOWN_KIND_ASTEROID := "asteroid"
const PROPELLANT_CLASS := "propellant"
## A client-side order (D32): the measurements below, one after another, not a Sim command.
const MEASURE_ALL := "measure_all"
## Orders whose operation always runs to its end (autonomy.md section 4), and that operation.
const ATOMIC_OPS: Dictionary = { "dock": "docking", "undock": "undocking" }


static func build(view: Dictionary, modules: Dictionary, items: Dictionary, commanded: int,
		selected_kind: String, selected_id: int, science: Dictionary = {}) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	if not view["units"].has(commanded):
		return orders
	var unit: Dictionary = view["units"][commanded]
	if selected_kind == "body" and view["bodies"].has(selected_id):
		if view["bodies"][selected_id]["kind"] == SHOWN_KIND_ASTEROID:
			_add_asteroid_orders(orders, view, modules, items, commanded, selected_id)
		_add_measure_orders(orders, view["bodies"][selected_id]["kind"], science, commanded, selected_id)
		if OrderList.measure_everything(view, science, commanded, selected_id).size() > 1:
			_add(orders, "Measure everything here", commanded, MEASURE_ALL, { "target": selected_id })
	elif selected_kind == "unit" and selected_id != commanded and view["units"].has(selected_id):
		_add(orders, "Move to", commanded, "move_to", { "target": selected_id })
		var used := OrderList.ports_in_use(view)
		var port := OrderList.free_port(unit["parts"], modules, used)
		var target_port := OrderList.free_port(view["units"][selected_id]["parts"], modules, used)
		if port != 0 and target_port != 0:
			_add(orders, "Dock", commanded, "dock", { "port": port, "target_port": target_port })
	if not unit["dock"].is_empty():
		_add(orders, "Undock", commanded, "undock", {})
	var partner := OrderList.docked_partner(view, commanded)
	if partner != 0:
		_add_transfer_orders(orders, view, items, commanded, partner)
	_add_stop_order(orders, view, commanded)
	return orders


## Stop cannot end an atomic operation, so it is offered then only to end a cycle.
## Docking keeps its row with any selection, so its progress is always on show.
static func _add_stop_order(orders: Array[Dictionary], view: Dictionary, commanded: int) -> void:
	var unit: Dictionary = view["units"][commanded]
	var op_type: String = unit["op"]["type"]
	if op_type == "idle":
		return
	if not ATOMIC_OPS.values().has(op_type):
		_add(orders, "Stop", commanded, "stop", {})
		return
	if op_type == ATOMIC_OPS["dock"] and not orders.any(_is_dock_order):
		_add(orders, "Dock", commanded, "dock", {})
	if not CyclePlan.running_cycle(unit, view).is_empty():
		_add(orders, "Stop cycle", commanded, "stop", {}, "Stop")


static func _is_dock_order(order: Dictionary) -> bool:
	return order["command"]["type"] == "dock"


## Unload anything aboard, and Load anything the host holds that this unit has a hold
## for (D39b: the drone stage loads ore from the station and leaves propellant in its
## depot). Propellant comes first in each list. Amounts come from the panel's box.
static func _add_transfer_orders(orders: Array[Dictionary], view: Dictionary, items: Dictionary, commanded: int,
		host_id: int) -> void:
	var unit: Dictionary = view["units"][commanded]
	for item: String in OrderList._propellant_first(unit["inventory"], items):
		_add(orders, "Unload %s" % items[item]["name"], commanded, "unload_cargo", { "to": host_id, "item": item })
	for item: String in OrderList._propellant_first(view["units"][host_id]["inventory"], items):
		if int(unit.get("cargo", {}).get(items[item]["cargo_class"], {}).get("cap_g", 0)) > 0:
			_add(orders, "Load %s" % items[item]["name"], commanded, "load_cargo", { "from": host_id, "item": item })


## Items held, known and above zero, by ID with propellant first.
static func _propellant_first(inventory: Dictionary, items: Dictionary) -> Array[String]:
	var first: Array[String] = []
	var rest: Array[String] = []
	var ids: Array = inventory.keys()
	ids.sort()
	for item: String in ids:
		if int(inventory[item]) <= 0 or not items.has(item):
			continue
		if items[item]["cargo_class"] == PROPELLANT_CLASS:
			first.append(item)
		else:
			rest.append(item)
	return first + rest


static func _add_asteroid_orders(orders: Array[Dictionary], view: Dictionary, modules: Dictionary,
		items: Dictionary, commanded: int, body: int) -> void:
	_add(orders, "Move to", commanded, "move_to", { "target": body })
	_add(orders, "Scan", commanded, "scan", { "target": body })
	var laser := _part_with_capability(view["units"][commanded]["parts"], modules, "mine")
	var ids: Array = view["deposits"].keys()
	ids.sort()
	for id: int in ids:
		var deposit: Dictionary = view["deposits"][id]
		if deposit["body"] == body and laser != 0:
			var label := "Mine %s (%s)" % [items[deposit["item"]]["name"], OrderText.tonnes(deposit["remaining_g"])]
			var key := "Mine %d" % id
			_add(orders, label, commanded, "start_mining", { "deposit": id, "module": laser }, key)


## C12: a Measure order for each science kind whose place suits this kind of body:
## composition at a rock, gravity field and surface sample at a planet or moon.
## Survey is Scan's own. Sim.check says whether the unit is in that place now.
static func _add_measure_orders(orders: Array[Dictionary], body_kind: String, science: Dictionary,
		commanded: int, body: int) -> void:
	if body_kind != SHOWN_KIND_ASTEROID and not ["planet", "moon"].has(body_kind):
		return
	var kinds: Array = science.keys()
	kinds.sort()
	for kind: String in kinds:
		if kind == "survey":
			continue
		var place: String = science[kind].get("place", "")
		var at_rock := body_kind == SHOWN_KIND_ASTEROID
		if (place == "asteroid") == at_rock:
			var label := "Measure %s" % OrderText.science_kind(kind).to_lower()
			_add(orders, label, commanded, "measure", { "target": body, "kind": kind }, "Measure %s" % kind)


## Sets how much an Unload, Load or Mine moves: `count` whole items for an item with a
## unit mass, otherwise `count` kilograms (ore is always kilograms); 0 leaves it out,
## which moves all that fits, or mines until the hold is full (C19).
static func set_amount(command: Dictionary, count: int, items: Dictionary) -> void:
	command["args"].erase("grams")
	if count <= 0:
		return
	var unit_g: int = items.get(command["args"].get("item", ""), {}).get("unit_mass_g", 0)
	command["args"]["grams"] = count * (unit_g if unit_g > 0 else 1000)


## The unit cargo moves to and from: the one this unit is docked at, or else the
## first, by ID, docked at it (a station built at a ship's port docks to the ship).
static func docked_partner(view: Dictionary, unit_id: int) -> int:
	var dock: Dictionary = view["units"][unit_id]["dock"]
	if not dock.is_empty():
		return dock["target_unit"]
	var ids: Array = view["units"].keys()
	ids.sort()
	for id: int in ids:
		var other: Dictionary = view["units"][id]["dock"]
		if id != unit_id and not other.is_empty() and other["target_unit"] == unit_id:
			return id
	return 0


## Every measurement of a body not yet paid, as Sim commands in order: Scan (which
## pays survey) first at a rock, then each Measure kind that suits the body. Whether
## the unit is in the right place is still Sim.check's to say.
static func measure_everything(view: Dictionary, science: Dictionary, commanded: int, body: int) -> Array[Dictionary]:
	var paid: Dictionary = view.get("science", {}).get("paid", {})
	var commands: Array[Dictionary] = []
	var kind_of_body: String = view["bodies"][body]["kind"]
	if kind_of_body == SHOWN_KIND_ASTEROID and not paid.has("survey:%d" % body):
		commands.append({ "type": "scan", "unit": commanded, "args": { "target": body } })
	var orders: Array[Dictionary] = []
	_add_measure_orders(orders, kind_of_body, science, commanded, body)
	for order: Dictionary in orders:
		var kind: String = order["command"]["args"]["kind"]
		var key := "%s:%d" % [kind, body]
		var paid_already := paid.keys().any(func(paid_key: String) -> bool: return paid_key == key or paid_key.begins_with(key + ":"))
		if not paid_already:
			commands.append(order["command"])
	return commands


static func _add(orders: Array[Dictionary], label: String, unit: int, type: String, args: Dictionary, key: String = "") -> void:
	orders.append({
		"key": label if key.is_empty() else key, "label": label,
		"command": { "type": type, "unit": unit, "args": args },
	})


static func _part_with_capability(part: Dictionary, modules: Dictionary, capability: String) -> int:
	if modules[part["def"]]["capabilities"].has(capability):
		return part["id"]
	for child: Dictionary in part["children"]:
		var found := _part_with_capability(child, modules, capability)
		if found != 0:
			return found
	return 0


static func ports_in_use(view: Dictionary) -> Array[int]:
	var used: Array[int] = []
	for id: int in view["units"]:
		var dock: Dictionary = view["units"][id]["dock"]
		if not dock.is_empty():
			used.append(dock["port"])
			used.append(dock["target_port"])
	return used


## The first docking part in a tree that nothing is using.
static func free_port(part: Dictionary, modules: Dictionary, used: Array[int]) -> int:
	if not CraftLayout.dock_connector(modules[part["def"]]).is_empty() and not used.has(part["id"]):
		return part["id"]
	for child: Dictionary in part["children"]:
		var found := OrderList.free_port(child, modules, used)
		if found != 0:
			return found
	return 0
