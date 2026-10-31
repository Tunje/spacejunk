class_name TaskStep
extends RefCounted
## One kind of unit order. TaskSystem runs the task around it, and a step keeps nothing of its own,
## since all saved state belongs in ctx.state.


## The command type this step answers to.
func type() -> String:
	return ""


## Tests the step against current state. Must not change anything. Phase 1 and Sim.check share it.
func validate(_ctx: SimContext, _unit_id: int, _args: Dictionary) -> Dictionary:
	return SimSystem.ok()


## Phase 2. Starts the step's operation.
func begin(_ctx: SimContext, _unit_id: int, _args: Dictionary) -> void:
	pass


## Phase 6, after deltas. True on the tick the operation ends.
func end_test(_ctx: SimContext, _unit_id: int) -> bool:
	return false


## Sets a unit's operation to run for `ticks`, from this tick (networks.md section 6).
static func set_op(ctx: SimContext, unit_id: int, op_type: String, target: int, part: int, ticks: int) -> void:
	ctx.state["units"][unit_id]["op"] = {
		"type": op_type, "target": target, "part": part,
		"start_tick": ctx.tick, "end_tick": ctx.tick + ticks - 1,
	}


## The first healthy part with a capability, as { part } or { reason }.
static func find_module(ctx: SimContext, unit_id: int, capability: String) -> Dictionary:
	var ids := Units.part_ids(ctx.state, unit_id)
	ids.sort()
	var reason := TaskSystem.REASON_MODULE_MISSING
	for id in ids:
		if not Units.module_of(ctx.state, ctx.defs, id)["capabilities"].has(capability):
			continue
		if ctx.state["parts"][id]["fault"] == "":
			return { "part": id }
		reason = TaskSystem.REASON_MODULE_FAULT
	return { "reason": reason }
