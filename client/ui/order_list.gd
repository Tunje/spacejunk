class_name OrderList extends RefCounted
## Works out which orders make sense for the commanded unit and the selection.
## Whether each one is currently valid is left to Sim.check.

const SHOWN_KIND_ASTEROID := "asteroid"


static func build(view: Dictionary, modules: Dictionary, items: Dictionary, commanded: int,
		selected_kind: String, selected_id: int) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	if not view["units"].has(commanded):
		return orders
	var unit: Dictionary = view["units"][commanded]
	if selected_kind == "body" and view["bodies"].has(selected_id):
		if view["bodies"][selected_id]["kind"] == SHOWN_KIND_ASTEROID:
			_add_asteroid_orders(orders, view, modules, items, commanded, selected_id)
	elif selected_kind == "unit" and selected_id != commanded and view["units"].has(selected_id):
		_add(orders, "Move to", commanded, "move_to", { "target": selected_id })
		var port := _part_with_dock(unit["parts"], modules)
		var target_port := _part_with_dock(view["units"][selected_id]["parts"], modules)
		if port != 0 and target_port != 0:
			_add(orders, "Dock", commanded, "dock", { "port": port, "target_port": target_port })
	if not unit["dock"].is_empty():
		_add(orders, "Undock", commanded, "undock", {})
	if unit["op"]["type"] != "idle":
		_add(orders, "Stop", commanded, "stop", {})
	return orders


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


static func _part_with_dock(part: Dictionary, modules: Dictionary) -> int:
	if not CraftLayout.dock_connector(modules[part["def"]]).is_empty():
		return part["id"]
	for child: Dictionary in part["children"]:
		var found := _part_with_dock(child, modules)
		if found != 0:
			return found
	return 0
