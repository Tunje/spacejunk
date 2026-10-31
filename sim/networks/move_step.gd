class_name MoveStep
extends TaskStep
## The `move_to` order. CargoSystem prices the trip in phase 4 and runs the route. The operation
## has no part, because once paid a route is unaffected by faults or power.

const OP_MOVING := "moving"
const REASON_NO_PROPELLANT := "no_propellant"


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


## A player order or `stop` holds the unit where it is, with no refund.
func report_end(ctx: SimContext, unit_id: int, reason: String) -> void:
	if reason != "":
		CargoSystem.halt(ctx, unit_id)


## The route ends in phase 5, so an empty route means this tick's arrival.
func end_test(ctx: SimContext, unit_id: int) -> bool:
	var unit: Dictionary = ctx.state["units"][unit_id]
	return unit["route"].is_empty() and not unit["op"].has("reason")
