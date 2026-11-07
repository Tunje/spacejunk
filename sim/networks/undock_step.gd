class_name UndockStep
extends TaskStep
## The `undock` order. CargoSystem finishes the operation.

const OP_UNDOCKING := "undocking"
const REASON_NOT_DOCKED := "not_docked"


func type() -> String:
	return "undock"


func validate(ctx: SimContext, unit_id: int, _args: Dictionary) -> Dictionary:
	if ctx.state["units"][unit_id]["dock"].is_empty():
		return SimSystem.reject(REASON_NOT_DOCKED)
	return SimSystem.ok()


func begin(ctx: SimContext, unit_id: int, _args: Dictionary) -> void:
	var dock: Dictionary = ctx.state["units"][unit_id]["dock"]
	var module := Units.module_of(ctx.state, ctx.defs, dock["port"])
	TaskStep.set_op(ctx, unit_id, OP_UNDOCKING, dock["target_unit"], 0,
		module["capabilities"][DockStep.CAPABILITY]["undock_ticks"])


func is_atomic(_ctx: SimContext, _unit_id: int) -> bool:
	return true


func needs(_ctx: SimContext, _args: Dictionary, place: Dictionary) -> bool:
	return place["docked"] != 0


func leaves(_ctx: SimContext, _args: Dictionary, place: Dictionary) -> Dictionary:
	return { "docked": 0, "at": place["docked"] }


func end_test(ctx: SimContext, unit_id: int) -> bool:
	return ctx.state["units"][unit_id]["dock"].is_empty()


## Coast (C20): nothing changes until CargoSystem finishes the undock on its end tick, which is
## stepped.
func coast_ticks(ctx: SimContext, unit_id: int) -> int:
	return CargoSystem.dock_horizon(ctx, unit_id)
