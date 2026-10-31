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


## Phase 5. One tick of work, recorded as deltas against `system`.
func run(_ctx: SimContext, _unit_id: int, _system: SimSystem) -> void:
	pass


## Phase 6. Applies a delta this step recorded. The payload names the step in `step`.
func apply_delta(_ctx: SimContext, _payload: Dictionary) -> void:
	pass


## Phase 6, after deltas. True on the tick the operation ends.
func end_test(_ctx: SimContext, _unit_id: int) -> bool:
	return false


## Reports the end of an operation that started, before it is cleared. `reason` is "" when the step
## completed, otherwise why it was cancelled.
func report_end(_ctx: SimContext, _unit_id: int, _reason: String) -> void:
	pass


## True once the operation must run to its end, even if its task is cancelled.
func is_atomic(_ctx: SimContext, _unit_id: int) -> bool:
	return false


## Phase 2, on a blocked cycle. Clears a held operation's own block if it no longer applies.
func retry(_ctx: SimContext, _unit_id: int) -> void:
	pass


## Why the step must wait its turn, or "". Only a cycle step waits.
func queue_reason(_ctx: SimContext, _args: Dictionary, _task_id: int) -> String:
	return ""


## True if a step's arguments name things that exist. Placement is not tested here, so this holds
## wherever the unit is. `set_cycle` tests it for every step.
func references_exist(_ctx: SimContext, _unit_id: int, _args: Dictionary) -> bool:
	return true


## True if the step can run from a placement, given as { docked, at } with 0 for neither.
func needs(_ctx: SimContext, _args: Dictionary, _place: Dictionary) -> bool:
	return true


## The placement the step leaves behind.
func leaves(_ctx: SimContext, _args: Dictionary, place: Dictionary) -> Dictionary:
	return place


## Sets a unit's operation to run for `ticks`, from this tick (networks.md section 6). An operation
## with no fixed length passes 0 and ends through end_test.
static func set_op(ctx: SimContext, unit_id: int, op_type: String, target: int, part: int, ticks: int) -> void:
	ctx.state["units"][unit_id]["op"] = {
		"type": op_type, "target": target, "part": part,
		"start_tick": ctx.tick, "end_tick": ctx.tick + ticks - 1 if ticks > 0 else 0,
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
