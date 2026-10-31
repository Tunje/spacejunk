class_name DockStep
extends TaskStep
## The `dock` order. Both ports are claimed in phase 4, and CargoSystem finishes the operation.
## The operation names no part, because a dock in progress ignores faults and power.

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


## Until `stop` can leave an atomic dock running (C5), a cancelled dock gives its ports back.
func report_end(ctx: SimContext, unit_id: int, reason: String) -> void:
	if reason != "":
		CargoSystem.release_ports(ctx, ctx.state["units"][unit_id]["op"])


func end_test(ctx: SimContext, unit_id: int) -> bool:
	return not ctx.state["units"][unit_id]["dock"].is_empty()


func _is_port(ctx: SimContext, part: int) -> bool:
	return ctx.state["parts"].has(part) \
		and Units.module_of(ctx.state, ctx.defs, part)["capabilities"].has(CAPABILITY)
