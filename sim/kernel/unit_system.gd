class_name UnitSystem
extends SimSystem
## The view and matter ledger of units, parts, bodies and deposits.


## Shadow casters for the view being filled, worked out once per view rather than per unit.
var _casters: Array = []
## Casters on coming ticks for this view's sun_tick walks, by tick, shared across units (A51).
var _casters_ahead := {}


func fill_view(ctx: SimContext, view: Dictionary) -> void:
	_casters = RailSystem.shadow_casters(ctx.state)
	_casters_ahead = {}
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		view["units"][id] = _unit_view(ctx, id)
	var bodies: Dictionary = ctx.state["bodies"]
	for id: int in _sorted(bodies):
		var body: Dictionary = bodies[id]
		view["bodies"][id] = {
			"name": body["name"], "kind": body["kind"], "pos_mm": body["pos_mm"].duplicate(),
			"radius_mm": body["radius_mm"], "visual_seed": body["visual_seed"], "scanned": body["scanned"],
			"frame": body["frame"], "orbit": body["orbit"].duplicate(true), "gm": body["gm"],
			"soi_mm": body.get("soi_mm", 0), "planet": body.get("planet", {}).duplicate(),
			"world_mm": RailSystem.world_mm(ctx.state, "bodies", id),
		}
	var deposits: Dictionary = ctx.state["deposits"]
	for id: int in _sorted(deposits):
		var deposit: Dictionary = deposits[id]
		if deposit["found"]:
			# Found by a class scan, its mineral is known but not how much or how hard: -1 for
			# each until a grade scan (C34).
			var graded: bool = deposit.get("graded", true)
			view["deposits"][id] = {
				"body": deposit["body"], "item": deposit["item"],
				"remaining_g": deposit["remaining_g"] if graded else -1,
				"hardness": deposit["hardness"] if graded else -1,
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
		"frame": maxi(0, RailSystem.unit_place(state, id)), "orbit": unit["orbit"].duplicate(true),
		"transfer": unit["transfer"].duplicate(),
		"world_mm": RailSystem.world_mm(state, "units", id),
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
	var shadow: bool = not index["generators"].is_empty() and not _casters.is_empty() \
		and RailSystem.in_shadow(ctx.state, id, _casters)
	return {
		"supply_w": 0 if shadow else UnitIndex.healthy_total(ctx, index["generators"]), "in_shadow": shadow,
		"demand_w": ctx.state["units"][id]["demand_w"], "stored_j": stored_j,
		"capacity_j": index["capacity_j"], "max_discharge_w": index["max_discharge_w"],
		# While in shadow, the first tick it is lit again, or -1 if that can't be foreseen; 0 if lit (A48).
		"sun_tick": _sun_tick(ctx, id) if shadow else 0,
	}


## PowerSystem.sun_tick, kept between views while the unit's motion is unchanged (A48): a view a
## frame would otherwise walk every unit in shadow every frame.
func _sun_tick(ctx: SimContext, id: int) -> int:
	var key := _motion_key(ctx.state, id)
	var memo: Dictionary = ctx.sun_memo.get(id, {})
	if not memo.is_empty() and memo["key"] == key and int(memo["tick"]) > int(ctx.state["tick"]):
		return memo["tick"]
	var tick := PowerSystem.sun_tick(ctx.state, id, _casters_ahead)
	if tick > 0:
		ctx.sun_memo[id] = { "key": key, "tick": tick }
	else:
		ctx.sun_memo.erase(id)
	return tick


## What a unit's place on coming ticks follows from: its host's if docked, its orbit's elements and
## any transfer legs, its landed cell, its spot in a frame, or its route as it stands.
static func _motion_key(state: Dictionary, id: int) -> Array:
	var unit: Dictionary = state["units"][id]
	if not unit["dock"].is_empty():
		return ["docked", _motion_key(state, unit["dock"]["target_unit"])]
	if not unit["route"].is_empty():
		var route: Dictionary = unit["route"]
		# A route's progress moves every tick, but by a closed form fixed when it set out.
		return ["route", unit["frame"], route["from_mm"], route["to_mm"], route["length_mm"], route["speed_mm_s"],
			route["eta_tick"]]
	if not unit["orbit"].is_empty():
		# The whole record, copied: a hyperbola keeps different fields from an ellipse.
		return ["orbit", unit["orbit"].duplicate(true), unit["transfer"].get("legs", []).size(), unit["stepped"]]
	if not unit.get("landed", {}).is_empty():
		return ["landed", unit["landed"]["body"], unit["landed"]["cell"]]
	return ["frame", unit["frame"], unit["pos_mm"], unit["vel_um_s"], unit["stepped"]]


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


## Coast (A33): this system only acts on commands, which the kernel's own horizon steps for.
func horizon(_ctx: SimContext) -> int:
	return NO_LIMIT
