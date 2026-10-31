class_name ScanStep
extends TaskStep
## The `scan` order. A finished scan marks the body scanned and reveals its deposits. A scan has no
## partial result, so an interrupted one starts again from nothing.

const OP_SCANNING := "scanning"
const CAPABILITY := "scan"
const BODY_ASTEROID := "asteroid"


func type() -> String:
	return "scan"


func validate(ctx: SimContext, unit_id: int, args: Dictionary) -> Dictionary:
	if typeof(args.get("target")) != TYPE_INT:
		return SimSystem.reject(TaskSystem.REASON_MALFORMED)
	var found := TaskStep.find_module(ctx, unit_id, CAPABILITY)
	if found.has("reason"):
		return SimSystem.reject(found["reason"])
	var module := Units.module_of(ctx.state, ctx.defs, found["part"])
	var unit: Dictionary = ctx.state["units"][unit_id]
	var tier: int = Units.module_of(ctx.state, ctx.defs, unit["core"])["capabilities"]["ai_core"]["tier"]
	if module["min_ai_tier"] > tier:
		return SimSystem.reject(TaskSystem.REASON_TIER_TOO_LOW)
	if not unit["dock"].is_empty():
		return SimSystem.reject(TaskSystem.REASON_DOCKED)
	var target: int = args["target"]
	var bodies: Dictionary = ctx.state["bodies"]
	if not bodies.has(target) or bodies[target]["kind"] != BODY_ASTEROID:
		return SimSystem.reject(TaskSystem.REASON_INVALID_TARGET)
	if unit["at_target"] != target:
		return SimSystem.reject(TaskSystem.REASON_OUT_OF_RANGE)
	return SimSystem.ok()


func begin(ctx: SimContext, unit_id: int, args: Dictionary) -> void:
	var part: int = TaskStep.find_module(ctx, unit_id, CAPABILITY)["part"]
	var ticks: int = Units.module_of(ctx.state, ctx.defs, part)["capabilities"][CAPABILITY]["ticks"]
	TaskStep.set_op(ctx, unit_id, OP_SCANNING, args["target"], part, ticks)


## A part shed on the last tick did no work, so the scan does not finish, and phase 2 cancels it.
func end_test(ctx: SimContext, unit_id: int) -> bool:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	if ctx.tick < op["end_tick"] or ctx.state["parts"][op["part"]]["shed"]:
		return false
	_reveal(ctx, unit_id, op["target"])
	return true


func _reveal(ctx: SimContext, unit_id: int, body_id: int) -> void:
	var body: Dictionary = ctx.state["bodies"][body_id]
	body["scanned"] = true
	var deposits: Dictionary = ctx.state["deposits"]
	var found: Array = []
	for id: int in body["deposits"]:
		var deposit: Dictionary = deposits[id]
		if deposit["found"]:
			continue
		deposit["found"] = true
		found.append(id)
		ctx.emit_event("deposit_found", unit_id, {
			"deposit": id, "item": deposit["item"], "grams": deposit["remaining_g"],
		})
	ctx.emit_event("scan_finished", unit_id, { "target": body_id, "deposits": found })
