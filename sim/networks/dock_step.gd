class_name DockStep
extends TaskStep
## The `dock` order. Both ports are claimed in phase 4, and CargoSystem finishes the operation.
## The operation names no part, because a dock in progress ignores faults and power. A cycle waits
## its turn for a port (autonomy.md section 8).

const OP_DOCKING := "docking"
const CAPABILITY := "port"
const REASON_PORT_BUSY := "port_busy"
const REASON_UNKNOWN_PART := "unknown_part"


func type() -> String:
	return "dock"


func validate(ctx: SimContext, unit_id: int, args: Dictionary) -> Dictionary:
	if typeof(args.get("port")) != TYPE_INT or typeof(args.get("target_port")) != TYPE_INT:
		return SimSystem.reject(TaskSystem.REASON_MALFORMED)
	if not ctx.state["units"][unit_id]["dock"].is_empty():
		return SimSystem.reject(TaskSystem.REASON_DOCKED)
	var port: int = args["port"]
	var target_port: int = args["target_port"]
	var parts: Dictionary = ctx.state["parts"]
	if not _is_port(ctx, port) or parts[port]["unit"] != unit_id or not _is_port(ctx, target_port):
		return SimSystem.reject(REASON_UNKNOWN_PART)
	if parts[port]["fault"] != "" or parts[target_port]["fault"] != "":
		return SimSystem.reject(TaskSystem.REASON_MODULE_FAULT)
	if not Units.at(ctx.state, unit_id, parts[target_port]["unit"]):
		return SimSystem.reject(TaskSystem.REASON_OUT_OF_RANGE)
	if Units.port_in_use(ctx.state, port) or Units.port_in_use(ctx.state, target_port):
		return SimSystem.reject(REASON_PORT_BUSY)
	return SimSystem.ok()


func begin(ctx: SimContext, unit_id: int, args: Dictionary) -> void:
	var module := Units.module_of(ctx.state, ctx.defs, args["port"])
	var host: int = ctx.state["parts"][args["target_port"]]["unit"]
	TaskStep.set_op(ctx, unit_id, OP_DOCKING, host, 0, module["capabilities"][CAPABILITY]["dock_ticks"])
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	op["port"] = args["port"]
	op["target_port"] = args["target_port"]


## A dock that was never granted its ports has nothing to give back.
func report_end(ctx: SimContext, unit_id: int, reason: String) -> void:
	if reason != "":
		CargoSystem.release_ports(ctx, ctx.state["units"][unit_id]["op"])


## Once its ports are granted, a dock finishes even if its task is cancelled.
func is_atomic(ctx: SimContext, unit_id: int) -> bool:
	return ctx.state["units"][unit_id]["op"].has("granted")


func queue_reason(ctx: SimContext, args: Dictionary, task_id: int) -> String:
	return "" if PortQueue.is_next(ctx, args["target_port"], task_id) else REASON_PORT_BUSY


func references_exist(ctx: SimContext, unit_id: int, args: Dictionary) -> bool:
	if typeof(args.get("port")) != TYPE_INT or typeof(args.get("target_port")) != TYPE_INT:
		return false
	var port: int = args["port"]
	return _is_port(ctx, port) and ctx.state["parts"][port]["unit"] == unit_id \
		and _is_port(ctx, args["target_port"])


func needs(ctx: SimContext, args: Dictionary, place: Dictionary) -> bool:
	return place["docked"] == 0 and place["at"] == ctx.state["parts"][args["target_port"]]["unit"]


func leaves(ctx: SimContext, args: Dictionary, _place: Dictionary) -> Dictionary:
	var host: int = ctx.state["parts"][args["target_port"]]["unit"]
	return { "docked": host, "at": host }


func end_test(ctx: SimContext, unit_id: int) -> bool:
	return not ctx.state["units"][unit_id]["dock"].is_empty()


## Coast (C20): once its ports are granted, nothing changes until CargoSystem finishes the dock on
## its end tick, which is stepped.
func coast_ticks(ctx: SimContext, unit_id: int) -> int:
	return CargoSystem.dock_horizon(ctx, unit_id)


func _is_port(ctx: SimContext, part: int) -> bool:
	return ctx.state["parts"].has(part) \
		and Units.module_of(ctx.state, ctx.defs, part)["capabilities"].has(CAPABILITY)
