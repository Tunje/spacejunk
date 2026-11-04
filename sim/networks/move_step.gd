class_name MoveStep
extends TaskStep
## The `move_to` order. CargoSystem prices the trip in phase 4 and runs the route. The operation
## has no part, because once paid a route is unaffected by faults or power.
##
## A trip between places (A13) first waits for its window with op `waiting`, whose `depart_tick`
## is saved in the op. Nothing is paid until departure, so stopping while waiting costs nothing.
## From departure the transfer is atomic and runs to arrival.

const OP_MOVING := "moving"
const OP_WAITING := "waiting"
const REASON_NO_PROPELLANT := "no_propellant"


## Holds the unit at op `waiting` until depart_tick.
static func wait_for(ctx: SimContext, unit_id: int, depart_tick: int) -> void:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	ctx.state["units"][unit_id]["op"] = {
		"type": OP_WAITING, "target": op["target"], "part": 0, "start_tick": op["start_tick"],
		"end_tick": maxi(op["start_tick"], depart_tick - 1), "depart_tick": depart_tick,
	}


func type() -> String:
	return "move_to"


func validate(ctx: SimContext, unit_id: int, args: Dictionary) -> Dictionary:
	if typeof(args.get("target")) != TYPE_INT:
		return SimSystem.reject(TaskSystem.REASON_MALFORMED)
	var unit: Dictionary = ctx.state["units"][unit_id]
	if not unit["dock"].is_empty():
		return SimSystem.reject(TaskSystem.REASON_DOCKED)
	var target: int = args["target"]
	var is_unit: bool = ctx.state["units"].has(target) and target != unit_id
	if not is_unit and not ctx.state["bodies"].has(target):
		return SimSystem.reject(TaskSystem.REASON_INVALID_TARGET)
	var quoted := Travel.quote(ctx, unit_id, target)
	if quoted.has("reason"):
		return SimSystem.reject(quoted["reason"])
	var detail := { "ticks": quoted["ticks"], "propellant_g": quoted["cost_g"] }
	if quoted["kind"] == Transfer.KIND:
		detail["depart_tick"] = quoted["depart_tick"]
		detail["arrive_tick"] = quoted["arrive_tick"]
	var have_g: int = unit["inventory"].get(Travel.PROPELLANT, 0)
	if quoted["cost_g"] > have_g:
		detail["need_g"] = quoted["cost_g"]
		detail["have_g"] = have_g
		return SimSystem.reject(REASON_NO_PROPELLANT, detail)
	var result := SimSystem.ok()
	result["detail"] = detail
	return result


func begin(ctx: SimContext, unit_id: int, args: Dictionary) -> void:
	TaskStep.set_op(ctx, unit_id, OP_MOVING, args["target"], 0, 1)


func references_exist(ctx: SimContext, unit_id: int, args: Dictionary) -> bool:
	if typeof(args.get("target")) != TYPE_INT:
		return false
	var target: int = args["target"]
	return ctx.state["bodies"].has(target) or (ctx.state["units"].has(target) and target != unit_id)


func needs(_ctx: SimContext, _args: Dictionary, place: Dictionary) -> bool:
	return place["docked"] == 0


func leaves(_ctx: SimContext, args: Dictionary, _place: Dictionary) -> Dictionary:
	return { "docked": 0, "at": args["target"] }


## A player order or `stop` holds the unit where it is, with no refund.
func report_end(ctx: SimContext, unit_id: int, reason: String) -> void:
	if reason != "":
		CargoSystem.halt(ctx, unit_id)


## The route ends in phase 5, so an empty route means this tick's arrival. A transfer is the same,
## once it has left and arrived.
func end_test(ctx: SimContext, unit_id: int) -> bool:
	var unit: Dictionary = ctx.state["units"][unit_id]
	return unit["route"].is_empty() and unit["transfer"].is_empty() and unit["op"]["type"] != OP_WAITING \
		and not unit["op"].has("reason")


## A paid transfer runs to arrival.
func is_atomic(ctx: SimContext, unit_id: int) -> bool:
	return not ctx.state["units"][unit_id]["transfer"].is_empty()


## A wait held by missing propellant takes the next window once the propellant is there.
func retry(ctx: SimContext, unit_id: int) -> void:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	if op["type"] != OP_WAITING or op.get("reason", "") != REASON_NO_PROPELLANT:
		return
	var quoted := Travel.quote_trip(ctx, unit_id, op["target"], ctx.tick)
	if quoted.has("reason") or quoted["cost_g"] > Reservations.free_stock(ctx, unit_id, Travel.PROPELLANT):
		return
	op.erase("reason")
	op["depart_tick"] = quoted["depart_tick"]
	op["end_tick"] = maxi(op["start_tick"], quoted["depart_tick"] - 1)
