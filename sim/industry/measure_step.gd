class_name MeasureStep
extends TaskStep
## The `measure` order (research.md section 1.1): a measurement of a body that pays science points
## when it finishes. Its kind comes from data/science.json, which says where it is taken and with
## which part. `survey` is the scan step itself. A measurement has no partial result, so an
## interrupted one pays nothing and starts again, as a scan does.
##
## A gravity field is taken over one period of the unit's orbit round the target, or while docked of
## its host's (C34), so a probe docked to a station measures on the station's orbit. The op keeps
## the orbit it started on, and any change to it, such as a burn, a dock or undock, or a
## sphere-of-influence change, ends the measurement unpaid with `orbit_changed`. A unit in a frame
## whose own orbit is round the target takes it over one period of the frame's orbit instead (C18),
## and leaving the frame ends it; that branch goes with the frames at A53's stage 4.
##
## A measurement at an asteroid runs within its instrument's longest scan range of it, docked or
## not, and ends with out_of_range on the first tick it is out of that range (C34). A kind that
## names a scan step in `reveals`, or survey, is that scan step.

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
	if _is_scan(definition, args["kind"]):
		return _scan.validate(ctx, unit_id, _scan_args(definition, args))
	var target: int = args["target"]
	if not ctx.state["bodies"].has(target) or Science.base_points(ctx, args["kind"], target) < 0:
		return SimSystem.reject(TaskSystem.REASON_INVALID_TARGET)
	var unit: Dictionary = ctx.state["units"][unit_id]
	if definition["place"] == PLACE_ORBIT:
		if unit["core"] == 0:
			return SimSystem.reject(TaskSystem.REASON_NO_CORE)
		if not _on_orbit_round(ctx, unit_id, target) and _frame_round(ctx, unit_id, target) == 0:
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
	if ctx.state["bodies"][target]["kind"] != PLACE_ASTEROID:
		return SimSystem.reject(TaskSystem.REASON_INVALID_TARGET)
	# At an asteroid, within the instrument's longest range of it, docked or not (C34).
	var reach_m := _reach_m(ctx, found["part"])
	var range_mm := Reach.range_mm(ctx, unit_id, target)
	if range_mm > Reach.mm_of_m(reach_m):
		return SimSystem.reject(TaskSystem.REASON_OUT_OF_RANGE,
			{ "range_m": range_mm / Reach.MM_PER_M, "need_m": reach_m })
	return SimSystem.ok()


## A measurement that is a scan step: survey, before B30, or a kind that names the step it pays
## for in `reveals` (C34).
static func _is_scan(definition: Dictionary, kind: String) -> bool:
	return kind == Science.SURVEY or definition.has("reveals")


static func _scan_args(definition: Dictionary, args: Dictionary) -> Dictionary:
	var scan := { "target": args["target"] }
	if definition.has("reveals"):
		scan["reveals"] = definition["reveals"]
	return scan


## The longest range of any scan step on the part, in metres.
func _reach_m(ctx: SimContext, part_id: int) -> int:
	var module := Units.module_of(ctx.state, ctx.defs, part_id)
	if not module["capabilities"].has(ScanStep.CAPABILITY):
		return ScanStep.LEGACY_RANGE_M
	var longest := 0
	for step: Dictionary in ScanStep.steps_of(module):
		longest = maxi(longest, step["range_m"])
	return longest


## The unit that carries this one's orbit: itself, or the host it is docked to, all the way down.
## A docked probe measures on its station's orbit (C34).
static func _carrier(ctx: SimContext, unit_id: int) -> int:
	var units: Dictionary = ctx.state["units"]
	var id := unit_id
	while not units[id]["dock"].is_empty():
		id = units[id]["dock"]["target_unit"]
	return id


## True when the unit, or its host, is on a closed orbit round `target`.
static func _on_orbit_round(ctx: SimContext, unit_id: int, target: int) -> bool:
	var orbit: Dictionary = ctx.state["units"][_carrier(ctx, unit_id)]["orbit"]
	return orbit.get("parent", 0) == target and not orbit.get("hyperbolic", false) and orbit.has("period_subticks")


func begin(ctx: SimContext, unit_id: int, args: Dictionary) -> void:
	var definition: Dictionary = ctx.defs["science"][args["kind"]]
	if _is_scan(definition, args["kind"]):
		_scan.begin(ctx, unit_id, _scan_args(definition, args))
		return
	var unit: Dictionary = ctx.state["units"][unit_id]
	if definition["place"] == PLACE_ORBIT:
		var carrier := _carrier(ctx, unit_id)
		var on_orbit := _on_orbit_round(ctx, unit_id, args["target"])
		var frame := 0 if on_orbit else _frame_round(ctx, unit_id, args["target"])
		var orbit: Dictionary = ctx.state["units"][carrier]["orbit"] if frame == 0 else ctx.state["frames"][frame]["orbit"]
		var ticks: int = (orbit["period_subticks"] + OrbitMath.SUB_TICKS - 1) / OrbitMath.SUB_TICKS
		TaskStep.set_op(ctx, unit_id, OP_MEASURING, args["target"], unit["core"], ticks)
		if frame == 0:
			unit["op"]["start_orbit"] = orbit.duplicate(true)
			unit["op"]["carrier"] = carrier
		else:
			unit["op"]["start_frame"] = frame
	else:
		var part: int = TaskStep.find_module(ctx, unit_id, definition["capability"])["part"]
		var ticks: int = definition.get("ticks", 0)
		if ticks == 0:
			var steps := ScanStep.steps_of(Units.module_of(ctx.state, ctx.defs, part))
			ticks = steps[steps.size() - 1]["ticks"]
		TaskStep.set_op(ctx, unit_id, OP_MEASURING, args["target"], part, ticks)
		if definition["place"] == PLACE_ASTEROID:
			unit["op"]["range_mm"] = Reach.mm_of_m(_reach_m(ctx, part))
	unit["op"]["kind"] = args["kind"]


## Coast (C17): nothing changes until the measurement's last tick. A gravity field's orbit changes
## only on a stepped tick (a burn, a dock, or a sphere-of-influence change at BurnSystem's horizon),
## and leaving a frame likewise. A measurement held within range coasts while the range holds (C34).
func coast_ticks(ctx: SimContext, unit_id: int) -> int:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	var ticks := TaskStep.ticks_before_end(ctx, unit_id)
	if op.has("range_mm"):
		ticks = mini(ticks, Reach.horizon(ctx, unit_id, op["target"], op["range_mm"]))
	return ticks


## Phase 5. A gravity field ends as soon as the orbit it is measuring changes, or the unit leaves
## the frame it is measuring from. One at an asteroid ends when it is out of range (C34).
func run(ctx: SimContext, unit_id: int, _system: SimSystem) -> void:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	if op["type"] == ScanStep.OP_SCANNING:
		_scan.run(ctx, unit_id, _system)
		return
	if _moved_off(ctx, unit_id):
		op["reason"] = REASON_ORBIT_CHANGED
	elif op.has("range_mm") and not op.has("reason") and not Reach.within(ctx, unit_id, op["target"], op["range_mm"]):
		op["reason"] = TaskSystem.REASON_OUT_OF_RANGE


## A part shed on the last tick did no work, so the measurement does not finish, and phase 2
## cancels it.
func end_test(ctx: SimContext, unit_id: int) -> bool:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var op: Dictionary = unit["op"]
	if op["type"] == ScanStep.OP_SCANNING:
		return _scan.end_test(ctx, unit_id)
	if ctx.tick < op["end_tick"] or op.has("reason") or not Units.can_run(ctx.state["parts"][op["part"]]):
		return false
	if _moved_off(ctx, unit_id):
		return false
	Science.pay(ctx, unit_id, op["kind"], op["target"])
	return true


## True when a gravity field's unit is no longer on the orbit, or in the frame, it started from.
func _moved_off(ctx: SimContext, unit_id: int) -> bool:
	var unit: Dictionary = ctx.state["units"][unit_id]
	var op: Dictionary = unit["op"]
	if op.has("start_orbit"):
		# The orbit measured is the carrier's: the unit's own, or its host's while docked. Docking
		# or undocking changes the carrier, which ends it too.
		var carrier := _carrier(ctx, unit_id)
		return carrier != op.get("carrier", unit_id) or ctx.state["units"][carrier]["orbit"] != op["start_orbit"]
	if op.has("start_frame"):
		return RailSystem.unit_place(ctx.state, unit_id) != op["start_frame"]
	return false


## The frame the unit is in, or is docked within, if that frame's own orbit is an ellipse round
## `target`, otherwise 0.
func _frame_round(ctx: SimContext, unit_id: int, target: int) -> int:
	var frame := RailSystem.unit_place(ctx.state, unit_id)
	if not ctx.state["frames"].has(frame):
		return 0
	var orbit: Dictionary = ctx.state["frames"][frame]["orbit"]
	if orbit.get("parent", 0) != target or orbit.get("hyperbolic", false) or not orbit.has("period_subticks"):
		return 0
	return frame


func references_exist(ctx: SimContext, _unit_id: int, args: Dictionary) -> bool:
	return typeof(args.get("target")) == TYPE_INT and ctx.state["bodies"].has(args["target"]) \
		and typeof(args.get("kind")) == TYPE_STRING and ctx.defs.get("science", {}).has(args["kind"])


## In a cycle, only measurements taken at an asteroid, undocked and at the target.
func needs(ctx: SimContext, args: Dictionary, place: Dictionary) -> bool:
	if ctx.defs["science"][args["kind"]]["place"] != PLACE_ASTEROID:
		return false
	return place["docked"] == 0 and place["at"] == args["target"]
