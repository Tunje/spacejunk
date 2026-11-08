class_name FittingSystem
extends SimSystem
## attach_part and detach_part: the attachment contract of contracts section 5, with the matter
## rules of accounting.md section 2. Both apply instantly in phase 1. Mass, connector load, power
## and heat only warn (C30): an attach that goes over them is allowed, and check's detail and
## part_attached carry the warnings. Only connectors that cannot mate, or are taken, refuse.

const ATTACH := "attach_part"
const DETACH := "detach_part"
const FAILED_EVENT := "attach_failed"
const SIZE_CORE := "core"
const REASON_INVALID_TARGET := "invalid_target"
const REASON_UNKNOWN_PART := "unknown_part"
const REASON_UNKNOWN_UNIT := "unknown_unit"
const REASON_MALFORMED := "malformed_command"
const REASON_NOT_DOCKED := "not_docked"
const REASON_MODULE_FAULT := "module_fault"
const REASON_MISSING_ITEM := "missing_inputs"
const REASON_PORT_BUSY := "port_busy"
const REASON_ROOT := "root_part"
const REASON_BUSY := "part_busy"
const REASON_CARGO_FULL := "cargo_full"
const WARN_POWER := "over_power_budget"
const WARN_HEAT := "over_heat_budget"
const WARN_MASS := "over_mass_limit"
const WARN_LOAD := "over_load_limit"


func commands() -> PackedStringArray:
	return PackedStringArray([ATTACH, DETACH])


func validate(ctx: SimContext, command: Dictionary) -> Dictionary:
	if command["type"] == ATTACH:
		return _validate_attach(ctx, command)
	return _validate_detach(ctx, command)


func apply(ctx: SimContext, command: Dictionary) -> void:
	if command["type"] == ATTACH:
		_apply_attach(ctx, command)
	else:
		_apply_detach(ctx, command)


func _validate_attach(ctx: SimContext, command: Dictionary) -> Dictionary:
	var args: Dictionary = command["args"]
	if not _has_types(args, { "item": TYPE_STRING, "from": TYPE_INT, "parent_part": TYPE_INT,
			"parent_connector": TYPE_STRING, "part_connector": TYPE_STRING }):
		return SimSystem.reject(REASON_MALFORMED)
	var state := ctx.state
	var unit: int = command["unit"]
	var problem := _check_group_partner(state, unit, args["from"])
	if problem != "":
		return SimSystem.reject(problem)
	var item: String = args["item"]
	var modules: Dictionary = ctx.defs["modules"]
	if not modules.has(item):
		return SimSystem.reject(REASON_INVALID_TARGET)
	var module: Dictionary = modules[item]
	var parent: int = args["parent_part"]
	if not state["parts"].has(parent) or state["parts"][parent]["unit"] != unit:
		return SimSystem.reject(REASON_UNKNOWN_PART)
	if state["parts"][parent]["fault"] != "":
		return SimSystem.reject(REASON_MODULE_FAULT)
	var held_g: int = state["units"][args["from"]]["inventory"].get(item, 0)
	if held_g < module["mass_g"]:
		return SimSystem.reject(REASON_MISSING_ITEM, { "need_g": module["mass_g"], "have_g": held_g })
	var parent_end := Units.connector_of(Units.module_of(state, ctx.defs, parent), args["parent_connector"])
	var part_end := Units.connector_of(module, args["part_connector"])
	if parent_end.is_empty() or part_end.is_empty():
		return SimSystem.reject(REASON_INVALID_TARGET)
	var carried_g: int = 0 if args["from"] == unit else module["mass_g"]
	var fit := Units.fit(state, ctx.defs, unit, [module] as Array[Dictionary], carried_g)
	var failure := _fit_failure(ctx, parent, parent_end, part_end)
	if failure.is_empty():
		var result := SimSystem.ok()
		result["detail"] = fit
		fit["warnings"] = _load_warnings(ctx, parent, parent_end, module["mass_g"]) + fit_warnings(fit)
		return result
	var detail: Dictionary = fit.duplicate()
	detail.merge(failure["detail"])
	return SimSystem.reject(failure["reason"], detail, FAILED_EVENT, { "item": item })


## The first fitting rule broken, as { reason, detail }, or {}. Only what cannot be done refuses:
## connectors that do not mate, or one already taken (C30).
func _fit_failure(ctx: SimContext, parent: int, parent_end: Dictionary, part_end: Dictionary) -> Dictionary:
	if parent_end["type"] != part_end["type"] or parent_end["type"] == "dock":
		return { "reason": "connector_type_mismatch", "detail": {} }
	if (parent_end["size"] == SIZE_CORE) != (part_end["size"] == SIZE_CORE):
		return { "reason": "connector_size_mismatch", "detail": {} }
	if Units.child_at(ctx.state, parent, parent_end["id"]) != 0:
		return { "reason": "connector_occupied", "detail": {} }
	return {}


## Owner's rulings, 2026-11-07 (C30): no hard checks on what a fit can carry, draw or shed. A fit over
## its hull's mass limit, or that could draw more than the unit makes, or give off more heat than
## its radiators reject, goes through with these warnings. Running short of power or radiators is
## handled in play, as factories slow and loads shed; what too much mass does comes with A's
## structure work.
static func fit_warnings(fit: Dictionary) -> Array[Dictionary]:
	var warnings: Array[Dictionary] = []
	if fit["mass_g"] > fit["mass_limit_g"]:
		warnings.append({ "code": WARN_MASS, "need_g": fit["mass_g"], "have_g": fit["mass_limit_g"] })
	if fit["power_rated_w"] > fit["power_budget_w"]:
		warnings.append({ "code": WARN_POWER, "need_w": fit["power_rated_w"], "have_w": fit["power_budget_w"] })
	if fit["heat_rated_w"] > fit["heat_budget_w"]:
		warnings.append({ "code": WARN_HEAT, "need_w": fit["heat_rated_w"], "have_w": fit["heat_budget_w"] })
	return warnings


## Tests the new mass against the connector it joins and every connector above it, warning at the
## first that it overloads (C30).
func _load_warnings(ctx: SimContext, parent: int, parent_end: Dictionary, mass_g: int) -> Array[Dictionary]:
	var state := ctx.state
	var below_g := mass_g
	var end := parent_end
	var current := parent
	while true:
		if below_g > end["load_limit_g"]:
			return [{ "code": WARN_LOAD, "need_g": below_g, "have_g": end["load_limit_g"] }] as Array[Dictionary]
		var part: Dictionary = state["parts"][current]
		if part["parent"] == 0:
			break
		below_g = Units.subtree_mass(state, ctx.defs, current) + mass_g
		end = Units.connector_of(Units.module_of(state, ctx.defs, part["parent"]), part["parent_connector"])
		current = part["parent"]
	return [] as Array[Dictionary]


func _apply_attach(ctx: SimContext, command: Dictionary) -> void:
	var args: Dictionary = command["args"]
	var unit: int = command["unit"]
	var item: String = args["item"]
	var mass_g: int = ctx.defs["modules"][item]["mass_g"]
	var parent_end := Units.connector_of(Units.module_of(ctx.state, ctx.defs, args["parent_part"]), args["parent_connector"])
	var warnings := _load_warnings(ctx, args["parent_part"], parent_end, mass_g)
	Units.remove_stock(ctx.state["units"][args["from"]]["inventory"], item, mass_g)
	var id := Units.add_part(ctx, unit, item, args["parent_part"], args["parent_connector"], args["part_connector"])
	ctx.state["parts"][args["parent_part"]]["children"].append(id)
	var data := { "part": id }
	warnings.append_array(fit_warnings(Units.fit(ctx.state, ctx.defs, unit)))
	if not warnings.is_empty():
		data["warnings"] = warnings
	ctx.emit_event("part_attached", unit, data)


func _validate_detach(ctx: SimContext, command: Dictionary) -> Dictionary:
	var args: Dictionary = command["args"]
	if not _has_types(args, { "part": TYPE_INT, "to": TYPE_INT }):
		return SimSystem.reject(REASON_MALFORMED)
	var state := ctx.state
	var unit: int = command["unit"]
	var problem := _check_partner(state, unit, args["to"])
	if problem != "":
		return SimSystem.reject(problem)
	var part_id: int = args["part"]
	if not state["parts"].has(part_id) or state["parts"][part_id]["unit"] != unit:
		return SimSystem.reject(REASON_UNKNOWN_PART)
	if state["parts"][part_id]["parent"] == 0:
		return SimSystem.reject(REASON_ROOT)
	var removed := Units.subtree(state, part_id)
	for id in removed:
		if Units.port_in_use(state, id):
			return SimSystem.reject(REASON_PORT_BUSY)
	if _subtree_busy(state, unit, removed):
		return SimSystem.reject(REASON_BUSY)
	var over := _over_capacity_after(ctx, unit, args["to"], removed)
	if not over.is_empty():
		return SimSystem.reject(REASON_CARGO_FULL, over)
	var result := SimSystem.ok()
	result["detail"] = Units.fit(state, ctx.defs, unit)
	result["detail"]["warnings"] = fit_warnings(_fit_without(ctx, unit, removed))
	return result


## The unit's fit figures once `removed` is gone, for the warnings a detach would leave (C30).
func _fit_without(ctx: SimContext, unit: int, removed: Array[int]) -> Dictionary:
	var after := Units.fit(ctx.state, ctx.defs, unit)
	for id in removed:
		var module: Dictionary = Units.module_of(ctx.state, ctx.defs, id)
		var capabilities: Dictionary = module["capabilities"]
		after["power_rated_w"] -= module["power_w"]
		after["heat_rated_w"] -= module["heat_w"]
		after["power_budget_w"] -= capabilities.get("generate", {}).get("power_w", 0) \
			+ capabilities.get("battery", {}).get("max_discharge_w", 0)
		after["heat_budget_w"] -= capabilities.get("radiator", {}).get("reject_w", 0)
	return after


func _subtree_busy(state: Dictionary, unit: int, removed: Array[int]) -> bool:
	if removed.has(state["units"][unit]["op"]["part"]):
		return true
	var jobs: Dictionary = state["jobs"]
	for id: int in jobs:
		if removed.has(jobs[id]["facility"]):
			return true
	return false


## What would be over capacity after a detach, on either unit, or {}.
func _over_capacity_after(ctx: SimContext, unit: int, to: int, removed: Array[int]) -> Dictionary:
	var stock := {}
	for id in removed:
		Units.add_stock(stock, ctx.state["parts"][id]["def"], Units.module_of(ctx.state, ctx.defs, id)["mass_g"])
	var over := Units.over_capacity(Units.cargo(ctx.state, ctx.defs, to, removed if to == unit else ([] as Array[int]), stock))
	if over.is_empty() and to != unit:
		over = Units.over_capacity(Units.cargo(ctx.state, ctx.defs, unit, removed))
	return over


func _apply_detach(ctx: SimContext, command: Dictionary) -> void:
	var args: Dictionary = command["args"]
	var state := ctx.state
	var unit: Dictionary = state["units"][command["unit"]]
	var part_id: int = args["part"]
	var parts: Dictionary = state["parts"]
	ctx.index.erase(command["unit"])
	var parent: Dictionary = parts[parts[part_id]["parent"]]
	parent["children"].erase(part_id)
	var inventory: Dictionary = state["units"][args["to"]]["inventory"]
	for id in Units.subtree(state, part_id):
		var module: Dictionary = Units.module_of(state, ctx.defs, id)
		Units.add_stock(inventory, parts[id]["def"], module["mass_g"])
		if unit["core"] == id:
			unit["core"] = 0
	for id in Units.subtree(state, part_id):
		parts.erase(id)
	ctx.emit_event("part_detached", command["unit"], { "part": part_id })


## "" if `other` is this unit or docked to it, otherwise the reason it is not usable.
func _check_partner(state: Dictionary, unit: int, other: int) -> String:
	if other == unit:
		return ""
	if not state["units"].has(other):
		return REASON_UNKNOWN_UNIT
	return "" if Units.are_docked(state, unit, other) else REASON_NOT_DOCKED


## "" if `other` is this unit or in its docked group, otherwise the reason it is not usable. Only an
## attach's `from` takes the group (C21); everything else is _check_partner's direct dock.
func _check_group_partner(state: Dictionary, unit: int, other: int) -> String:
	if other == unit:
		return ""
	if not state["units"].has(other):
		return REASON_UNKNOWN_UNIT
	return "" if Units.docked_group(state, unit).has(other) else REASON_NOT_DOCKED


func _has_types(args: Dictionary, types: Dictionary) -> bool:
	for key: String in types:
		if typeof(args.get(key)) != types[key]:
			return false
	return true


## Coast (A33): this system only acts on commands, which the kernel's own horizon steps for.
func horizon(_ctx: SimContext) -> int:
	return NO_LIMIT
