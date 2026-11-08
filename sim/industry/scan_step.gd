class_name ScanStep
extends TaskStep
## The `scan` order, in steps (C34, stage4_gameplay_rules.md section 2). An instrument lists what
## each of its steps reveals and the range it works at: a LIDAR's `shape`, a spectrometer's `class`
## and `grade`. A step runs only within its range of the body, judged by real relative distance
## (Reach), and only while it stays there: leaving range ends it with out_of_range, and it starts
## again from nothing, as any interrupted scan does. A docked unit scans from where it really is.
##
## - `shape` marks the body scanned: its size and shape are known, nothing about its minerals.
## - `class` finds its deposits: each one's mineral, not how much. Mining needs no more.
## - `grade` finds them and grades them: grams and hardness too.
## Each finished step pays the science kind that names it in `reveals`, when the data has one.
##
## An instrument whose data still gives one `ticks` and no steps (before B30) has one step that
## reveals all three, within LEGACY_RANGE_M, and pays `survey`, as scanning did before C34.
##
## `scan { target, reveals? }` runs the step named, or with none the deepest any healthy instrument
## can do from here. In a cycle (C28), a step already done on that body passes in one tick,
## revealing and paying nothing, so a lap that scans its rock does not stall on later laps.

const OP_SCANNING := "scanning"
const CAPABILITY := "scan"
const BODY_ASTEROID := "asteroid"
const SHAPE := "shape"
const CLASS := "class"
const GRADE := "grade"
## Shallowest first, so a later index is a deeper step.
const REVEALS: Array[String] = [SHAPE, CLASS, GRADE]
## The range of an instrument with no steps in its data: close enough that a unit flown to the
## body, which stands at its centre until stage 4, is always within it.
const LEGACY_RANGE_M := 1000
const LEGACY := "legacy"


func type() -> String:
	return "scan"


func validate(ctx: SimContext, unit_id: int, args: Dictionary) -> Dictionary:
	if typeof(args.get("target")) != TYPE_INT:
		return SimSystem.reject(TaskSystem.REASON_MALFORMED)
	if args.has("reveals") and (typeof(args["reveals"]) != TYPE_STRING or not REVEALS.has(args["reveals"])):
		return SimSystem.reject(TaskSystem.REASON_MALFORMED)
	var target: int = args["target"]
	var bodies: Dictionary = ctx.state["bodies"]
	var offered := offers(ctx, unit_id, args.get("reveals", ""))
	if offered.is_empty():
		# None healthy: a faulted instrument still says so.
		return SimSystem.reject(TaskStep.find_module(ctx, unit_id, CAPABILITY).get("reason",
			TaskSystem.REASON_MODULE_MISSING))
	if not bodies.has(target) or bodies[target]["kind"] != BODY_ASTEROID:
		return SimSystem.reject(TaskSystem.REASON_INVALID_TARGET)
	var chosen := pick(ctx, unit_id, target, offered)
	if chosen.has("reason"):
		return SimSystem.reject(chosen["reason"], chosen["detail"])
	var unit: Dictionary = ctx.state["units"][unit_id]
	if Units.module_of(ctx.state, ctx.defs, chosen["part"])["min_ai_tier"] > TaskSystem.tier_of(ctx, unit):
		return SimSystem.reject(TaskSystem.REASON_TIER_TOO_LOW)
	return SimSystem.ok()


func begin(ctx: SimContext, unit_id: int, args: Dictionary) -> void:
	var target: int = args["target"]
	var chosen := pick(ctx, unit_id, target, offers(ctx, unit_id, args.get("reveals", "")))
	var step: Dictionary = chosen["step"]
	var unit: Dictionary = ctx.state["units"][unit_id]
	# Only a cycle's scan passes: a scan order, or a survey measure, still scans again and pays.
	var in_cycle: bool = unit["task"] != 0 \
		and ctx.state["tasks"][unit["task"]]["kind"] == TaskSystem.KIND_CYCLE
	var passes: bool = in_cycle and done(ctx, target, step["reveals"])
	TaskStep.set_op(ctx, unit_id, OP_SCANNING, target, chosen["part"], 1 if passes else step["ticks"])
	var op: Dictionary = unit["op"]
	op["reveals"] = step["reveals"]
	op["range_mm"] = Reach.mm_of_m(step["range_m"])
	if passes:
		op["already_scanned"] = true


## The scan steps of a unit's healthy instruments, as [{ part, step }] by part ID and then the
## part's own order, keeping only those that reveal `reveals` when it is given.
static func offers(ctx: SimContext, unit_id: int, reveals: String = "") -> Array:
	var found: Array = []
	for part_id: int in Units.sorted_part_ids(ctx.state, unit_id):
		var module := Units.module_of(ctx.state, ctx.defs, part_id)
		if not module["capabilities"].has(CAPABILITY) or ctx.state["parts"][part_id]["fault"] != "":
			continue
		for step: Dictionary in steps_of(module):
			if reveals == "" or step["reveals"] == reveals or step["reveals"] == LEGACY:
				found.append({ "part": part_id, "step": step })
	return found


## A scanning module's steps, each { reveals, range_m, ticks }. Data with no steps gives one
## legacy step that reveals everything (before B30).
static func steps_of(module: Dictionary) -> Array:
	var capability: Dictionary = module["capabilities"][CAPABILITY]
	if capability.has("steps"):
		return capability["steps"]
	return [{ "reveals": LEGACY, "range_m": LEGACY_RANGE_M, "ticks": capability["ticks"] }]


## Of the steps offered, the deepest whose range reaches the target now, then the lowest part ID.
## { part, step }, or { reason: out_of_range, detail: { range_m, need_m } } with the longest range
## on offer when none reaches.
static func pick(ctx: SimContext, unit_id: int, target: int, offered: Array) -> Dictionary:
	var range_mm := Reach.range_mm(ctx, unit_id, target)
	var best := {}
	var longest := 0
	for entry: Dictionary in offered:
		var step: Dictionary = entry["step"]
		longest = maxi(longest, step["range_m"])
		if range_mm > Reach.mm_of_m(step["range_m"]):
			continue
		if best.is_empty() or _depth(step["reveals"]) > _depth(best["step"]["reveals"]):
			best = entry
	if best.is_empty():
		return { "reason": TaskSystem.REASON_OUT_OF_RANGE,
			"detail": { "range_m": range_mm / Reach.MM_PER_M, "need_m": longest } }
	return best


## True when the body already has what `reveals` gives: scanned for shape, every deposit found for
## class, and graded too for grade or a legacy step.
static func done(ctx: SimContext, body_id: int, reveals: String) -> bool:
	var body: Dictionary = ctx.state["bodies"][body_id]
	if reveals == SHAPE:
		return body.get("scanned", false)
	if reveals == LEGACY and not body.get("scanned", false):
		return false
	for id: int in body["deposits"]:
		var deposit: Dictionary = ctx.state["deposits"][id]
		if not deposit["found"] or (reveals != CLASS and not deposit.get("graded", true)):
			return false
	return true


static func _depth(reveals: String) -> int:
	return REVEALS.size() if reveals == LEGACY else REVEALS.find(reveals)


## A cycle's scan names a known asteroid (C28).
func references_exist(ctx: SimContext, _unit_id: int, args: Dictionary) -> bool:
	return typeof(args.get("target")) == TYPE_INT and ctx.state["bodies"].has(args["target"]) \
		and ctx.state["bodies"][args["target"]]["kind"] == BODY_ASTEROID


## Cycle placement stays on the "at" flag until stage 4 (stage4_gameplay_rules.md section 5).
func needs(_ctx: SimContext, args: Dictionary, place: Dictionary) -> bool:
	return place["docked"] == 0 and place["at"] == args["target"]


## Phase 5: a step held within range ends on the first tick the target is out of it.
func run(ctx: SimContext, unit_id: int, _system: SimSystem) -> void:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	if not op.has("reason") and not Reach.within(ctx, unit_id, op["target"], op["range_mm"]):
		op["reason"] = TaskSystem.REASON_OUT_OF_RANGE


## Coast (C17, C34): nothing changes until the scan's last tick, as long as the range holds.
func coast_ticks(ctx: SimContext, unit_id: int) -> int:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	return mini(TaskStep.ticks_before_end(ctx, unit_id), Reach.horizon(ctx, unit_id, op["target"], op["range_mm"]))


## A part shed on the last tick did no work, so the scan does not finish, and phase 2 cancels it.
func end_test(ctx: SimContext, unit_id: int) -> bool:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	if ctx.tick < op["end_tick"] or op.has("reason") or not Units.can_run(ctx.state["parts"][op["part"]]):
		return false
	if not op.get("already_scanned", false):
		_reveal(ctx, unit_id, op["target"], op["reveals"])
	return true


func _reveal(ctx: SimContext, unit_id: int, body_id: int, reveals: String) -> void:
	var body: Dictionary = ctx.state["bodies"][body_id]
	var found: Array = []
	if reveals == SHAPE or reveals == LEGACY:
		body["scanned"] = true
	if reveals != SHAPE:
		var grades := reveals != CLASS
		var deposits: Dictionary = ctx.state["deposits"]
		for id: int in body["deposits"]:
			var deposit: Dictionary = deposits[id]
			if not deposit["found"]:
				deposit["found"] = true
				deposit["graded"] = grades
				found.append(id)
				var data := { "deposit": id, "item": deposit["item"] }
				if grades:
					data["grams"] = deposit["remaining_g"]
				ctx.emit_event("deposit_found", unit_id, data)
			elif grades and not deposit.get("graded", true):
				deposit["graded"] = true
				ctx.emit_event("deposit_graded", unit_id, {
					"deposit": id, "item": deposit["item"], "grams": deposit["remaining_g"],
				})
	ctx.emit_event("scan_finished", unit_id, { "target": body_id, "deposits": found, "reveals": reveals })
	Science.pay(ctx, unit_id, science_kind(ctx, reveals), body_id)


## The science kind a step pays: the one whose `reveals` names it, or survey for a legacy step.
static func science_kind(ctx: SimContext, reveals: String) -> String:
	var science: Dictionary = ctx.defs.get("science", {})
	var ids: Array = science.keys()
	ids.sort()
	for id: String in ids:
		if science[id].get("reveals", "") == reveals:
			return id
	return Science.SURVEY
