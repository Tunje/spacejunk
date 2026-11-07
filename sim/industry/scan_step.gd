class_name ScanStep
extends TaskStep
## The `scan` order. A finished scan marks the body scanned, reveals its deposits and pays survey
## points (research.md section 1). A scan has no partial result, so an interrupted one starts again
## from nothing. In a cycle (C28), a scan of a body already scanned passes as done in one tick,
## revealing and paying nothing, so a lap that scans its rock does not stall on later laps.

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
	if module["min_ai_tier"] > TaskSystem.tier_of(ctx, unit):
		return SimSystem.reject(TaskSystem.REASON_TIER_TOO_LOW)
	if not unit["dock"].is_empty():
		return SimSystem.reject(TaskSystem.REASON_DOCKED)
	var target: int = args["target"]
	var bodies: Dictionary = ctx.state["bodies"]
	if not bodies.has(target) or bodies[target]["kind"] != BODY_ASTEROID:
		return SimSystem.reject(TaskSystem.REASON_INVALID_TARGET)
	if not Units.at(ctx.state, unit_id, target):
		return SimSystem.reject(TaskSystem.REASON_OUT_OF_RANGE)
	return SimSystem.ok()


func begin(ctx: SimContext, unit_id: int, args: Dictionary) -> void:
	var part: int = TaskStep.find_module(ctx, unit_id, CAPABILITY)["part"]
	var ticks: int = Units.module_of(ctx.state, ctx.defs, part)["capabilities"][CAPABILITY]["ticks"]
	# Only a cycle's scan passes: a scan order, or a survey measure, still scans again and pays.
	var unit: Dictionary = ctx.state["units"][unit_id]
	var in_cycle: bool = unit["task"] != 0 \
		and ctx.state["tasks"][unit["task"]]["kind"] == TaskSystem.KIND_CYCLE
	var passes: bool = in_cycle and ctx.state["bodies"][args["target"]].get("scanned", false)
	TaskStep.set_op(ctx, unit_id, OP_SCANNING, args["target"], part, 1 if passes else ticks)
	if passes:
		unit["op"]["already_scanned"] = true


## A cycle's scan names a known asteroid, and runs there undocked (C28).
func references_exist(ctx: SimContext, _unit_id: int, args: Dictionary) -> bool:
	return typeof(args.get("target")) == TYPE_INT and ctx.state["bodies"].has(args["target"]) \
		and ctx.state["bodies"][args["target"]]["kind"] == BODY_ASTEROID


func needs(_ctx: SimContext, args: Dictionary, place: Dictionary) -> bool:
	return place["docked"] == 0 and place["at"] == args["target"]


## Coast (C17): nothing changes until the scan's last tick.
func coast_ticks(ctx: SimContext, unit_id: int) -> int:
	return TaskStep.ticks_before_end(ctx, unit_id)


## A part shed on the last tick did no work, so the scan does not finish, and phase 2 cancels it.
func end_test(ctx: SimContext, unit_id: int) -> bool:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	if ctx.tick < op["end_tick"] or not Units.can_run(ctx.state["parts"][op["part"]]):
		return false
	if not op.get("already_scanned", false):
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
	Science.pay(ctx, unit_id, Science.SURVEY, body_id)
