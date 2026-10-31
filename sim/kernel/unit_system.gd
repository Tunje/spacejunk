class_name UnitSystem
extends SimSystem
## The view and matter ledger of units, parts, bodies and deposits.


func fill_view(ctx: SimContext, view: Dictionary) -> void:
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		view["units"][id] = _unit_view(ctx, id)
	var bodies: Dictionary = ctx.state["bodies"]
	for id: int in _sorted(bodies):
		var body: Dictionary = bodies[id]
		view["bodies"][id] = {
			"name": body["name"], "kind": body["kind"], "pos_mm": body["pos_mm"].duplicate(),
			"radius_mm": body["radius_mm"], "visual_seed": body["visual_seed"], "scanned": body["scanned"],
		}
	var deposits: Dictionary = ctx.state["deposits"]
	for id: int in _sorted(deposits):
		var deposit: Dictionary = deposits[id]
		if deposit["found"]:
			view["deposits"][id] = {
				"body": deposit["body"], "item": deposit["item"],
				"remaining_g": deposit["remaining_g"], "hardness": deposit["hardness"],
			}


func fill_ledger(ctx: SimContext, ledger: Dictionary) -> void:
	var matter: Dictionary = ledger["matter"]
	var state := ctx.state
	var units: Dictionary = state["units"]
	for id: int in units:
		matter["inventories_g"] += Units.inventory_mass(state, id)
		matter["installed_g"] += Units.installed_mass(state, ctx.defs, id)
	var deposits: Dictionary = state["deposits"]
	for id: int in deposits:
		matter["deposits_g"] += deposits[id]["remaining_g"]
	var jobs: Dictionary = state["jobs"]
	for id: int in jobs:
		var held: Dictionary = jobs[id]["held"]
		for item: String in held:
			matter["jobs_g"] += held[item]


func _unit_view(ctx: SimContext, id: int) -> Dictionary:
	var state := ctx.state
	var defs := ctx.defs
	var unit: Dictionary = state["units"][id]
	var core: int = unit["core"]
	var tier: int = 0
	if core != 0:
		tier = Units.module_of(state, defs, core)["capabilities"]["ai_core"]["tier"]
	var route: Dictionary = unit["route"]
	var shown_route := {}
	if not route.is_empty():
		shown_route = {
			"target": route["target"], "from_mm": route["from_mm"].duplicate(),
			"to_mm": route["to_mm"].duplicate(), "eta_tick": route["eta_tick"],
		}
	var fit := UnitIndex.fit(ctx, id)
	var index := UnitIndex.of(ctx, id)
	var result := {
		"def": unit["def"], "kind": unit["kind"], "name": unit["name"],
		"pos_mm": unit["pos_mm"].duplicate(), "at_target": unit["at_target"],
		"core": core, "core_tier": tier, "task": unit["task"], "cycle_task": unit["cycle_task"],
		"last_cycle": unit["last_cycle"].duplicate(true),
		"op": unit["op"].duplicate(), "route": shown_route, "dock": unit["dock"].duplicate(),
		"parts": _part_view(ctx, unit["root"]), "inventory": unit["inventory"].duplicate(),
		"mass_g": fit["mass_g"], "cargo": UnitIndex.cargo(ctx, id), "fit": fit,
		"power": _power_view(ctx, id),
		"heat": {
			"stored_j": unit["heat_stored_j"],
			"limit_j": index["limit_j"],
			"reject_w": UnitIndex.healthy_total(ctx, index["radiators"]), "input_w": unit["heat_input_w"],
		},
	}
	return result


func _power_view(ctx: SimContext, id: int) -> Dictionary:
	var index := UnitIndex.of(ctx, id)
	var stored_j := 0
	for battery: Array in index["batteries"]:
		stored_j += ctx.state["parts"][battery[0]]["stored_j"]
	return {
		"supply_w": UnitIndex.healthy_total(ctx, index["generators"]),
		"demand_w": ctx.state["units"][id]["demand_w"], "stored_j": stored_j,
		"capacity_j": index["capacity_j"], "max_discharge_w": index["max_discharge_w"],
	}


## The part tree. A unit with no parts shows an empty Dictionary.
func _part_view(ctx: SimContext, part_id: int) -> Dictionary:
	if part_id == 0:
		return {}
	var part: Dictionary = ctx.state["parts"][part_id]
	var state := Units.STATE_ON
	if part["fault"] != "":
		state = Units.STATE_FAULT
	elif part["shed"]:
		state = Units.STATE_SHED
	var children: Array = []
	for child: int in part["children"]:
		children.append(_part_view(ctx, child))
	return {
		"id": part_id, "def": part["def"], "parent_connector": part["parent_connector"],
		"connector": part["connector"], "state": state, "fault": part["fault"],
		"draw_w": part["draw_w"], "priority": part["priority"], "children": children,
	}


func _sorted(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids
