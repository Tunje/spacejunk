class_name ScenarioBuilder
extends RefCounted
## Builds a new game's entities from a scenario, issuing IDs in the order of schemas.md section
## 14: each body, then its deposits, then each unit, then its parts.

const MAX_WORLD_G := 9_000_000_000_000_000_000


## Fills the state from a scenario in sim units. Returns "" or what is wrong with it.
static func populate(ctx: SimContext, scenario: Dictionary, deposits: Dictionary) -> String:
	var keys := {}
	for body: Dictionary in scenario["bodies"]:
		_add_body(ctx, body, deposits, keys)
	for entry: Dictionary in scenario["units"]:
		_add_unit(ctx, entry, keys)
	for entry: Dictionary in scenario["units"]:
		if entry["dock"] != null:
			var problem := _dock(ctx, entry, keys)
			if problem != "":
				return problem
	return _set_world_total(ctx)


static func _add_body(ctx: SimContext, entry: Dictionary, deposits: Dictionary, keys: Dictionary) -> void:
	var id := ctx.new_id()
	keys[entry["key"]] = id
	var deposit_ids: Array[int] = []
	var body := {
		"id": id, "name": entry["name"], "kind": entry["kind"], "pos_mm": entry["pos_mm"].duplicate(),
		"radius_mm": entry["radius_mm"], "visual_seed": entry["visual_seed"], "scanned": false,
	}
	ctx.state["bodies"][id] = body
	for def: String in entry["deposits"]:
		var deposit: Dictionary = deposits[def]
		var deposit_id := ctx.new_id()
		deposit_ids.append(deposit_id)
		ctx.state["deposits"][deposit_id] = {
			"id": deposit_id, "body": id, "item": deposit["item"], "remaining_g": deposit["mass_g"],
			"hardness": deposit["hardness"], "found": false,
		}
	body["deposits"] = Array(deposit_ids)


static func _add_unit(ctx: SimContext, entry: Dictionary, keys: Dictionary) -> void:
	var id := Units.create(ctx, entry["template"], entry["name"], entry["pos_mm"])
	keys[entry["key"]] = id
	var inventory: Dictionary = ctx.state["units"][id]["inventory"]
	for stock: Dictionary in entry["inventory"]:
		Units.add_stock(inventory, stock["item"], stock["grams"])


## Docks a unit at the start, in the state it would have after arrival and docking.
static func _dock(ctx: SimContext, entry: Dictionary, keys: Dictionary) -> String:
	var plan: Dictionary = entry["dock"]
	var id: int = keys[entry["key"]]
	var host: int = keys[plan["host"]]
	var ports := Units.ports(ctx.state, ctx.defs, id)
	var host_ports := Units.ports(ctx.state, ctx.defs, host)
	if plan["port"] >= ports.size() or plan["host_port"] >= host_ports.size():
		return "%s docks at a port that does not exist" % entry["key"]
	var unit: Dictionary = ctx.state["units"][id]
	unit["dock"] = {
		"port": ports[plan["port"]], "target_unit": host, "target_port": host_ports[plan["host_port"]],
	}
	unit["at_target"] = host
	return ""


## Records the matter total and checks the world limit (contracts section 1).
static func _set_world_total(ctx: SimContext) -> String:
	var total := 0
	var units: Dictionary = ctx.state["units"]
	for id: int in units:
		var unit_g := Units.unit_mass(ctx.state, ctx.defs, id)
		if unit_g > MAX_WORLD_G - total:
			return "world matter is over the limit"
		total += unit_g
	var deposits: Dictionary = ctx.state["deposits"]
	for id: int in deposits:
		var deposit_g: int = deposits[id]["remaining_g"]
		if deposit_g > MAX_WORLD_G - total:
			return "world matter is over the limit"
		total += deposit_g
	ctx.state["matter_start_g"] = total
	return ""
