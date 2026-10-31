class_name UnitIndex
extends RefCounted
## What a unit's fitted parts add up to, worked out once and kept until its parts change. This is
## a derived cache, held on the context and never saved. Anything live, such as a fault or a
## battery's charge, is still read from the part.


## A unit's entry, built on first use.
static func of(ctx: SimContext, unit_id: int) -> Dictionary:
	var entry: Variant = ctx.index.get(unit_id)
	if entry == null:
		entry = _build(ctx, unit_id)
		ctx.index[unit_id] = entry
	return entry


## Cargo capacity and use per class, as Units.cargo gives it.
static func cargo(ctx: SimContext, unit_id: int) -> Dictionary:
	var table: Dictionary = of(ctx, unit_id)["storage"].duplicate(true)
	Units.add_cargo_use(table, ctx.state, ctx.defs, unit_id, {})
	return table


## Declared limits and ratings, as Units.fit gives them.
static func fit(ctx: SimContext, unit_id: int) -> Dictionary:
	var entry := of(ctx, unit_id)
	return {
		"mass_g": entry["installed_g"] + Units.inventory_mass(ctx.state, unit_id),
		"mass_limit_g": entry["mass_limit_g"],
		"power_budget_w": entry["power_budget_w"], "power_rated_w": entry["power_rated_w"],
		"heat_budget_w": entry["heat_budget_w"], "heat_rated_w": entry["heat_rated_w"],
	}


## The healthy total of a list of [part, value] pairs.
static func healthy_total(ctx: SimContext, pairs: Array) -> int:
	var parts: Dictionary = ctx.state["parts"]
	var total := 0
	for pair: Array in pairs:
		if parts[pair[0]]["fault"] == "":
			total += pair[1]
	return total


static func _build(ctx: SimContext, unit_id: int) -> Dictionary:
	var entry := {
		"ids": Units.sorted_part_ids(ctx.state, unit_id),
		"generators": [], "radiators": [], "batteries": [], "always_on": [],
		"power_w": {}, "heat_w": {}, "storage": {},
		"installed_g": 0, "mass_limit_g": 0, "limit_j": 0, "capacity_j": 0, "max_discharge_w": 0,
		"power_budget_w": 0, "power_rated_w": 0, "heat_budget_w": 0, "heat_rated_w": 0,
	}
	for part_id: int in entry["ids"]:
		_add_part(entry, part_id, Units.module_of(ctx.state, ctx.defs, part_id))
	return entry


static func _add_part(entry: Dictionary, part_id: int, module: Dictionary) -> void:
	var capabilities: Dictionary = module["capabilities"]
	entry["power_w"][part_id] = module["power_w"]
	entry["heat_w"][part_id] = module["heat_w"]
	entry["installed_g"] += module["mass_g"]
	entry["power_rated_w"] += module["power_w"]
	entry["heat_rated_w"] += module["heat_w"]
	entry["mass_limit_g"] += capabilities.get("max_mass_g", 0)
	entry["limit_j"] += capabilities.get("heat_capacity", {}).get("limit_j", 0)
	if capabilities.has("generate"):
		var power_w: int = capabilities["generate"]["power_w"]
		entry["generators"].append([part_id, power_w])
		entry["power_budget_w"] += power_w
	if capabilities.has("radiator"):
		var reject_w: int = capabilities["radiator"]["reject_w"]
		entry["radiators"].append([part_id, reject_w])
		entry["heat_budget_w"] += reject_w
	if capabilities.has("battery"):
		var battery: Dictionary = capabilities["battery"]
		entry["batteries"].append([part_id, battery])
		entry["capacity_j"] += battery["capacity_j"]
		entry["max_discharge_w"] += battery["max_discharge_w"]
		entry["power_budget_w"] += battery["max_discharge_w"]
	if capabilities.get("always_on", false):
		entry["always_on"].append(part_id)
	var storage: Dictionary = capabilities.get("storage", {})
	for cargo_class: String in storage:
		var slot := Units.class_entry(entry["storage"], cargo_class)
		slot["cap_g"] += storage[cargo_class]["mass_g"]
		slot["cap_l"] += storage[cargo_class]["volume_l"]
