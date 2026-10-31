class_name TransferStep
extends TaskStep
## The shared half of `load_cargo` and `unload_cargo`. Progress stays on the task, so it survives
## a hold. CargoSystem moves the matter each tick, and this tests the end after that tick's delta.

const OP_LOADING := "loading"
const OP_UNLOADING := "unloading"
const REASON_NOT_WHOLE := "not_whole_unit"
const REASON_CARGO_FULL := "cargo_full"
const REASON_NOT_DOCKED := "not_docked"
const REASON_UNKNOWN_UNIT := "unknown_unit"
const OPEN_KEY := "open_transfer"


## The unit field naming the other side of the transfer, `from` or `to`.
func partner_field() -> String:
	return ""


func op_type() -> String:
	return ""


func validate(ctx: SimContext, unit_id: int, args: Dictionary) -> Dictionary:
	var field := partner_field()
	if typeof(args.get(field)) != TYPE_INT or typeof(args.get("item")) != TYPE_STRING:
		return SimSystem.reject(TaskSystem.REASON_MALFORMED)
	if args.has("grams") and (typeof(args["grams"]) != TYPE_INT or args["grams"] <= 0):
		return SimSystem.reject(TaskSystem.REASON_MALFORMED)
	var other: int = args[field]
	if not ctx.state["units"].has(other):
		return SimSystem.reject(REASON_UNKNOWN_UNIT)
	if other == unit_id or not Units.are_docked(ctx.state, unit_id, other):
		return SimSystem.reject(REASON_NOT_DOCKED)
	var item: String = args["item"]
	if not ctx.defs["items"].has(item):
		return SimSystem.reject(TaskSystem.REASON_INVALID_TARGET)
	var unit_mass_g: int = ctx.defs["items"][item].get("unit_mass_g", 0)
	if unit_mass_g != 0 and args.has("grams") and args["grams"] % unit_mass_g != 0:
		return SimSystem.reject(REASON_NOT_WHOLE)
	return SimSystem.ok()


func begin(ctx: SimContext, unit_id: int, args: Dictionary) -> void:
	var other: int = args[partner_field()]
	var from: int = other if op_type() == OP_LOADING else unit_id
	var to: int = unit_id if op_type() == OP_LOADING else other
	TaskStep.set_op(ctx, unit_id, op_type(), other, _own_port(ctx, unit_id, other), 0)
	var unit: Dictionary = ctx.state["units"][unit_id]
	var op: Dictionary = unit["op"]
	op["from"] = from
	op["to"] = to
	op["item"] = args["item"]
	op["limit_g"] = args.get("grams", 0)
	unit[OPEN_KEY] = { "from": from, "to": to, "item": args["item"], "grams": 0 }


func references_exist(ctx: SimContext, _unit_id: int, args: Dictionary) -> bool:
	var field := partner_field()
	return typeof(args.get(field)) == TYPE_INT and typeof(args.get("item")) == TYPE_STRING \
		and ctx.state["units"].has(args[field]) and ctx.defs["items"].has(args["item"])


func needs(_ctx: SimContext, args: Dictionary, place: Dictionary) -> bool:
	return place["docked"] == args[partner_field()]


## A blocked unload goes on when its destination has room again.
func retry(ctx: SimContext, unit_id: int) -> void:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	if op.get("reason", "") == REASON_CARGO_FULL \
			and Units.grams_that_fit(ctx.state, ctx.defs, op["to"], op["item"]) > 0:
		op.erase("reason")


## An interrupted transfer still reports what it moved.
func report_end(ctx: SimContext, unit_id: int, _reason: String) -> void:
	CargoSystem.close_transfer(ctx, unit_id)


func end_test(ctx: SimContext, unit_id: int) -> bool:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var op: Dictionary = unit["op"]
	var task: Dictionary = ctx.state["tasks"][unit["task"]]
	var item: String = op["item"]
	if op["limit_g"] != 0 and task.get("moved_g", 0) >= op["limit_g"]:
		CargoSystem.close_transfer(ctx, unit_id)
		return true
	if ctx.state["units"][op["from"]]["inventory"].get(item, 0) == 0:
		CargoSystem.close_transfer(ctx, unit_id)
		return true
	if Units.grams_that_fit(ctx.state, ctx.defs, op["to"], item) > 0:
		return false
	if op["type"] == OP_LOADING:
		CargoSystem.close_transfer(ctx, unit_id)
		return true
	op["reason"] = REASON_CARGO_FULL
	return false


## The port on this unit that the transfer runs through.
func _own_port(ctx: SimContext, unit_id: int, other: int) -> int:
	var dock: Dictionary = ctx.state["units"][unit_id]["dock"]
	if dock.get("target_unit", 0) == other:
		return dock["port"]
	return ctx.state["units"][other]["dock"]["target_port"]
