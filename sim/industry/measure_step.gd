class_name MeasureStep
extends TaskStep
## The `measure` order (research.md section 1.1): a measurement of a body that pays science points
## when it finishes. Its kind comes from data/science.json, which says where it is taken and with
## which part. `survey` is the scan step itself. A measurement has no partial result, so an
## interrupted one pays nothing and starts again, as a scan does.
##
## A gravity field is taken over one period of the unit's orbit round the target. The op keeps the
## orbit it started on, and any change to it, such as a burn or a sphere-of-influence change, ends
## the measurement unpaid with `orbit_changed`.

const OP_MEASURING := "measuring"
const PLACE_ASTEROID := "asteroid"
const PLACE_LANDED := "landed"
const PLACE_ORBIT := "orbit"
const CAPABILITY_CORE := "ai_core"
const REASON_ORBIT_CHANGED := "orbit_changed"

var _scan := ScanStep.new()


func type() -> String:
	return "measure"


func validate(ctx: SimContext, unit_id: int, args: Dictionary) -> Dictionary:
	if typeof(args.get("target")) != TYPE_INT or typeof(args.get("kind")) != TYPE_STRING:
		return SimSystem.reject(TaskSystem.REASON_MALFORMED)
	var definition: Dictionary = ctx.defs.get("science", {}).get(args["kind"], {})
	if definition.is_empty():
		return SimSystem.reject(TaskSystem.REASON_MALFORMED)
	if args["kind"] == Science.SURVEY:
		return _scan.validate(ctx, unit_id, args)
	var target: int = args["target"]
	if not ctx.state["bodies"].has(target) or Science.base_points(ctx, args["kind"], target) < 0:
		return SimSystem.reject(TaskSystem.REASON_INVALID_TARGET)
	var unit: Dictionary = ctx.state["units"][unit_id]
	if definition["place"] == PLACE_ORBIT:
		if unit["core"] == 0:
			return SimSystem.reject(TaskSystem.REASON_NO_CORE)
		var orbit: Dictionary = unit["orbit"]
		if orbit.get("parent", 0) != target or orbit.get("hyperbolic", false) or not unit["dock"].is_empty():
			return SimSystem.reject(TaskSystem.REASON_OUT_OF_RANGE)
		return SimSystem.ok()
	var found := TaskStep.find_module(ctx, unit_id, definition["capability"])
	if found.has("reason"):
		return SimSystem.reject(found["reason"])
	if Units.module_of(ctx.state, ctx.defs, found["part"])["min_ai_tier"] > TaskSystem.tier_of(ctx, unit):
		return SimSystem.reject(TaskSystem.REASON_TIER_TOO_LOW)
	if definition["place"] == PLACE_LANDED:
		if unit["landed"].get("body", 0) != target:
			return SimSystem.reject(TaskSystem.REASON_OUT_OF_RANGE)
		return SimSystem.ok()
	if not unit["dock"].is_empty():
		return SimSystem.reject(TaskSystem.REASON_DOCKED)
	if ctx.state["bodies"][target]["kind"] != PLACE_ASTEROID:
		return SimSystem.reject(TaskSystem.REASON_INVALID_TARGET)
	if not Units.at(ctx.state, unit_id, target):
		return SimSystem.reject(TaskSystem.REASON_OUT_OF_RANGE)
	return SimSystem.ok()


func begin(ctx: SimContext, unit_id: int, args: Dictionary) -> void:
	if args["kind"] == Science.SURVEY:
		_scan.begin(ctx, unit_id, args)
		return
	var definition: Dictionary = ctx.defs["science"][args["kind"]]
	var unit: Dictionary = ctx.state["units"][unit_id]
	if definition["place"] == PLACE_ORBIT:
		var ticks: int = (unit["orbit"]["period_subticks"] + OrbitMath.SUB_TICKS - 1) / OrbitMath.SUB_TICKS
		TaskStep.set_op(ctx, unit_id, OP_MEASURING, args["target"], unit["core"], ticks)
		unit["op"]["start_orbit"] = unit["orbit"].duplicate(true)
	else:
		var part: int = TaskStep.find_module(ctx, unit_id, definition["capability"])["part"]
		var ticks: int = definition.get("ticks", 0)
		if ticks == 0:
			ticks = Units.module_of(ctx.state, ctx.defs, part)["capabilities"][ScanStep.CAPABILITY]["ticks"]
		TaskStep.set_op(ctx, unit_id, OP_MEASURING, args["target"], part, ticks)
	unit["op"]["kind"] = args["kind"]


## Coast (C17): nothing changes until the measurement's last tick. A gravity field's orbit changes
## only on a stepped tick (a burn, or a sphere-of-influence change at BurnSystem's horizon), and
## leaving a frame likewise.
func coast_ticks(ctx: SimContext, unit_id: int) -> int:
	return TaskStep.ticks_before_end(ctx, unit_id)


## Phase 5. A gravity field ends as soon as the orbit it is measuring changes.
func run(ctx: SimContext, unit_id: int, _system: SimSystem) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	if unit["op"].has("start_orbit") and unit["orbit"] != unit["op"]["start_orbit"]:
		unit["op"]["reason"] = REASON_ORBIT_CHANGED


## A part shed on the last tick did no work, so the measurement does not finish, and phase 2
## cancels it.
func end_test(ctx: SimContext, unit_id: int) -> bool:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var op: Dictionary = unit["op"]
	if op["type"] == ScanStep.OP_SCANNING:
		return _scan.end_test(ctx, unit_id)
	if ctx.tick < op["end_tick"] or op.has("reason") or not Units.can_run(ctx.state["parts"][op["part"]]):
		return false
	if op.has("start_orbit") and unit["orbit"] != op["start_orbit"]:
		return false
	Science.pay(ctx, unit_id, op["kind"], op["target"])
	return true


func references_exist(ctx: SimContext, _unit_id: int, args: Dictionary) -> bool:
	return typeof(args.get("target")) == TYPE_INT and ctx.state["bodies"].has(args["target"]) \
		and typeof(args.get("kind")) == TYPE_STRING and ctx.defs.get("science", {}).has(args["kind"])


## In a cycle, only measurements taken at an asteroid, undocked and at the target.
func needs(ctx: SimContext, args: Dictionary, place: Dictionary) -> bool:
	if ctx.defs["science"][args["kind"]]["place"] != PLACE_ASTEROID:
		return false
	return place["docked"] == 0 and place["at"] == args["target"]
