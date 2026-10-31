class_name TaskSystem
extends SimSystem
## Runs tasks: the state machine of autonomy.md section 3. An order is a one-step task that ends
## when interrupted. A cycle repeats its steps, blocks when interrupted and resumes by itself. Tier
## needs no rules of its own, because tier 1 can only run orders. A step's own behaviour lives in
## its TaskStep.

const STOP := "stop"
const ASSIGN_CORE := "assign_core"
const SET_CYCLE := "set_cycle"
const KIND_ORDER := "order"
const KIND_CYCLE := "cycle"
const STATE_RUNNING := "running"
const STATE_BLOCKED := "blocked"
const CYCLE_TIER := 2
const MIN_CYCLE_STEPS := 2
const MAX_CYCLE_STEPS := 16
const MINING_STEP := "start_mining"
const MOVE_STEP := "move_to"
const CYCLE_STEPS: Array[String] = [
	MOVE_STEP, "dock", "undock", "load_cargo", "unload_cargo", MINING_STEP,
]
const REASON_MALFORMED := "malformed_command"
const REASON_INVALID_TARGET := "invalid_target"
const REASON_UNKNOWN_PART := "unknown_part"
const REASON_NO_CORE := "no_core"
const REASON_CORE_OFFLINE := "core_offline"
const REASON_TIER_TOO_LOW := "tier_too_low"
const REASON_BUSY_DOCKING := "busy_docking"
const REASON_MODULE_FAULT := "module_fault"
const REASON_MODULE_MISSING := "module_missing"
const REASON_NO_POWER := "no_power"
const REASON_DOCKED := "docked"
const REASON_OUT_OF_RANGE := "out_of_range"
const REASON_PLAYER_ORDER := "player_order"
const REASON_PLAYER_STOP := "player_stop"
const REASON_BAD_CYCLE := "bad_cycle"
const REASON_NO_SAFE_STEP := "no_safe_step"
const ATOMIC_OPS: Array[String] = ["docking", "undocking"]

## The fields a task shows in the view. `op_ended`, `enter` and `moved_g` stay internal.
const VIEW_FIELDS: Array[String] = [
	"id", "owner", "kind", "state", "reason", "hold", "steps", "step", "cycle", "since_tick", "command",
]

var _steps := {}


func _init() -> void:
	for step: TaskStep in [
		ScanStep.new(), MiningStep.new(), MoveStep.new(), DockStep.new(), UndockStep.new(),
		LoadCargoStep.new(), UnloadCargoStep.new(),
	]:
		_steps[step.type()] = step


## True if a unit has a task and it is not blocked.
static func is_running(ctx: SimContext, unit: Dictionary) -> bool:
	return unit["task"] != 0 and ctx.state["tasks"][unit["task"]]["state"] == STATE_RUNNING


## The tier of a unit's assigned core, or 0.
static func tier_of(ctx: SimContext, unit: Dictionary) -> int:
	if unit["core"] == 0:
		return 0
	return Units.module_of(ctx.state, ctx.defs, unit["core"])["capabilities"]["ai_core"]["tier"]


func commands() -> PackedStringArray:
	var types := PackedStringArray([STOP, ASSIGN_CORE, SET_CYCLE])
	for type: String in _steps:
		types.append(type)
	return types


func validate(ctx: SimContext, command: Dictionary) -> Dictionary:
	if command["type"] == STOP:
		return SimSystem.ok()
	if command["type"] == ASSIGN_CORE:
		return _validate_assign(ctx, command)
	var unit_id: int = command["unit"]
	var unit: Dictionary = ctx.state["units"][unit_id]
	if unit["core"] == 0:
		return SimSystem.reject(REASON_NO_CORE)
	if _core_offline(ctx, unit):
		return SimSystem.reject(REASON_CORE_OFFLINE)
	if ATOMIC_OPS.has(unit["op"]["type"]):
		return SimSystem.reject(REASON_BUSY_DOCKING)
	if command["type"] == SET_CYCLE:
		return _validate_cycle(ctx, command)
	var step: TaskStep = _steps[command["type"]]
	return step.validate(ctx, unit_id, command["args"])


func apply(ctx: SimContext, command: Dictionary) -> void:
	var unit: Dictionary = ctx.state["units"][command["unit"]]
	match command["type"]:
		STOP:
			_cancel_all(ctx, unit, REASON_PLAYER_STOP)
		ASSIGN_CORE:
			_apply_assign(ctx, unit, command["args"]["core"])
		SET_CYCLE:
			_cancel_all(ctx, unit, REASON_PLAYER_ORDER)
			unit["last_cycle"] = command["args"]["steps"].duplicate(true)
			_create(ctx, unit, command, KIND_CYCLE, command["args"]["steps"])
		_:
			_interrupt_for_order(ctx, unit)
			_create(ctx, unit, command, KIND_ORDER, [{ "type": command["type"], "args": command["args"] }])


## Phase 2, in ascending unit ID. A step that ended last tick completes here, and the next starts.
func update_tasks(ctx: SimContext) -> void:
	var units: Dictionary = ctx.state["units"]
	for unit_id: int in _sorted(units):
		var unit: Dictionary = units[unit_id]
		if unit["task"] == 0:
			_settle_atomic(unit)
		elif unit["core"] == 0:
			_cancel_all(ctx, unit, REASON_NO_CORE)
		elif ctx.state["tasks"][unit["task"]]["kind"] == KIND_ORDER:
			_update_order(ctx, unit)
		else:
			_update_cycle(ctx, unit)


## Phase 5. Each running operation does its tick of work, as deltas. A held one waits.
func run(ctx: SimContext) -> void:
	var units: Dictionary = ctx.state["units"]
	for unit_id: int in _sorted(units):
		if _has_working_op(ctx, units[unit_id]):
			_current_step(ctx, units[unit_id]).run(ctx, unit_id, self)


func apply_delta(ctx: SimContext, payload: Dictionary) -> void:
	var step: TaskStep = _steps[payload["step"]]
	step.apply_delta(ctx, payload)


## Phase 6, after deltas. Each operation tests its own end.
func update_stores(ctx: SimContext) -> void:
	var units: Dictionary = ctx.state["units"]
	for unit_id: int in _sorted(units):
		if _has_working_op(ctx, units[unit_id]) and _current_step(ctx, units[unit_id]).end_test(ctx, unit_id):
			ctx.state["tasks"][units[unit_id]["task"]]["op_ended"] = true


func fill_view(ctx: SimContext, view: Dictionary) -> void:
	var tasks: Dictionary = ctx.state["tasks"]
	for id: int in _sorted(tasks):
		var shown := {}
		for field in VIEW_FIELDS:
			shown[field] = tasks[id][field]
		view["tasks"][id] = shown.duplicate(true)


func _validate_assign(ctx: SimContext, command: Dictionary) -> Dictionary:
	var core: Variant = command["args"].get("core")
	if typeof(core) != TYPE_INT:
		return SimSystem.reject(REASON_MALFORMED)
	if core == 0:
		return SimSystem.ok()
	var parts: Dictionary = ctx.state["parts"]
	if not parts.has(core) or parts[core]["unit"] != command["unit"] \
			or not Units.module_of(ctx.state, ctx.defs, core)["capabilities"].has("ai_core"):
		return SimSystem.reject(REASON_UNKNOWN_PART)
	if parts[core]["fault"] != "":
		return SimSystem.reject(REASON_MODULE_FAULT)
	return SimSystem.ok()


func _apply_assign(ctx: SimContext, unit: Dictionary, core: int) -> void:
	unit["core"] = core
	if core == 0:
		_cancel_all(ctx, unit, REASON_NO_CORE)
	elif tier_of(ctx, unit) < CYCLE_TIER:
		_cancel_cycle(ctx, unit, REASON_TIER_TOO_LOW)


func _validate_cycle(ctx: SimContext, command: Dictionary) -> Dictionary:
	var unit_id: int = command["unit"]
	if tier_of(ctx, ctx.state["units"][unit_id]) < CYCLE_TIER:
		return SimSystem.reject(REASON_TIER_TOO_LOW)
	var steps: Variant = command["args"].get("steps")
	if typeof(steps) != TYPE_ARRAY or steps.size() < MIN_CYCLE_STEPS or steps.size() > MAX_CYCLE_STEPS:
		return _bad_cycle(0)
	var first_move := -1
	for i: int in steps.size():
		if not _is_cycle_step(ctx, unit_id, steps[i]):
			return _bad_cycle(i)
		if first_move < 0 and steps[i]["type"] == MOVE_STEP:
			first_move = i
	if first_move < 0:
		return _bad_cycle(0)
	return _validate_closure(ctx, steps, first_move)


func _is_cycle_step(ctx: SimContext, unit_id: int, entry: Variant) -> bool:
	if typeof(entry) != TYPE_DICTIONARY or not CYCLE_STEPS.has(entry.get("type")) \
			or typeof(entry.get("args")) != TYPE_DICTIONARY:
		return false
	var step: TaskStep = _steps[entry["type"]]
	return step.references_exist(ctx, unit_id, entry["args"])


## Walks once around the cycle. A move's end does not depend on where it began, so the walk starts
## just after one and ends by testing that move.
func _validate_closure(ctx: SimContext, steps: Array, first_move: int) -> Dictionary:
	var count := steps.size()
	var place: Dictionary = _steps[MOVE_STEP].leaves(ctx, steps[first_move]["args"], {})
	for offset: int in range(1, count + 1):
		var index := (first_move + offset) % count
		var step: TaskStep = _steps[steps[index]["type"]]
		if not step.needs(ctx, steps[index]["args"], place):
			return _bad_cycle(index)
		place = step.leaves(ctx, steps[index]["args"], place)
	return SimSystem.ok()


func _bad_cycle(step: int) -> Dictionary:
	return SimSystem.reject(REASON_BAD_CYCLE, { "step": step })


func _create(ctx: SimContext, unit: Dictionary, command: Dictionary, kind: String, steps: Array) -> void:
	var id := ctx.new_id()
	ctx.state["tasks"][id] = {
		"id": id, "owner": unit["id"], "kind": kind, "state": STATE_RUNNING, "reason": "", "hold": false,
		"steps": steps.duplicate(true), "step": 0, "cycle": 0, "since_tick": ctx.tick,
		"command": command["id"], "op_ended": false, "enter": kind == KIND_CYCLE,
	}
	unit["task"] = id
	ctx.emit_event("task_started", unit["id"], { "task": id, "command": command["id"] })


## Clears the way for a new order. A running order ends, and a cycle steps aside until it is done.
func _interrupt_for_order(ctx: SimContext, unit: Dictionary) -> void:
	if unit["task"] == 0:
		return
	var task: Dictionary = ctx.state["tasks"][unit["task"]]
	if task["kind"] == KIND_ORDER:
		_cancel(ctx, unit, REASON_PLAYER_ORDER)
		return
	if _has_op(unit):
		_current_step(ctx, unit).report_end(ctx, unit["id"], REASON_PLAYER_ORDER)
		_clear_op(unit)
	_set_blocked(ctx, unit, task, REASON_PLAYER_ORDER)
	unit["cycle_task"] = task["id"]
	unit["task"] = 0


func _update_order(ctx: SimContext, unit: Dictionary) -> void:
	var task: Dictionary = ctx.state["tasks"][unit["task"]]
	var reason := "" if task["op_ended"] else _interruption(ctx, unit)
	if task["op_ended"]:
		_finish(ctx, unit)
	elif reason != "":
		_cancel(ctx, unit, reason)
	elif not _has_op(unit):
		var current: Dictionary = task["steps"][task["step"]]
		var step: TaskStep = _steps[current["type"]]
		step.begin(ctx, unit["id"], current["args"])
		return
	else:
		return
	_resume_suspended_cycle(ctx, unit)


## When an overriding order ends, however it ends, its cycle comes back through re-entry.
func _resume_suspended_cycle(ctx: SimContext, unit: Dictionary) -> void:
	if unit["cycle_task"] == 0:
		return
	var task: Dictionary = ctx.state["tasks"][unit["cycle_task"]]
	unit["task"] = task["id"]
	unit["cycle_task"] = 0
	task["enter"] = true
	_update_cycle(ctx, unit)


func _update_cycle(ctx: SimContext, unit: Dictionary) -> void:
	var task: Dictionary = ctx.state["tasks"][unit["task"]]
	if task["op_ended"]:
		_complete_step(ctx, unit, task)
	if task["enter"] and not _reenter(ctx, unit, task):
		_block(ctx, unit, task, REASON_NO_SAFE_STEP)
		return
	if task["state"] == STATE_BLOCKED and _has_op(unit):
		_current_step(ctx, unit).retry(ctx, unit["id"])
	var reason := _interruption(ctx, unit)
	if reason == "" and not _has_op(unit):
		reason = _start_blocker(ctx, task)
	if reason != "":
		_block(ctx, unit, task, reason)
		return
	if task["state"] == STATE_BLOCKED:
		ctx.emit_event("task_resumed", unit["id"], { "task": task["id"], "reason": task["reason"] })
		task["state"] = STATE_RUNNING
		task["reason"] = ""
		task["hold"] = false
		task["since_tick"] = ctx.tick
	if not _has_op(unit):
		var current: Dictionary = task["steps"][task["step"]]
		var step: TaskStep = _steps[current["type"]]
		step.begin(ctx, unit["id"], current["args"])


func _complete_step(ctx: SimContext, unit: Dictionary, task: Dictionary) -> void:
	_current_step(ctx, unit).report_end(ctx, unit["id"], "")
	_clear_op(unit)
	task["op_ended"] = false
	task.erase("moved_g")
	task["step"] += 1
	if task["step"] == task["steps"].size():
		task["step"] = 0
		task["cycle"] += 1
		ctx.emit_event("task_cycle_done", unit["id"], { "task": task["id"], "cycle": task["cycle"] })


## Walks back from the current step to the nearest one the unit is placed for (autonomy.md section
## 5). False if there is none.
func _reenter(ctx: SimContext, unit: Dictionary, task: Dictionary) -> bool:
	var place := {
		"docked": unit["dock"].get("target_unit", 0), "at": unit["at_target"],
	}
	var steps: Array = task["steps"]
	for back: int in steps.size():
		var index: int = (task["step"] - back + steps.size()) % steps.size()
		var step: TaskStep = _steps[steps[index]["type"]]
		if step.needs(ctx, steps[index]["args"], place):
			task["step"] = index
			task["enter"] = false
			task.erase("moved_g")
			return true
	return false


## Why a cycle's current step cannot start, or "".
func _start_blocker(ctx: SimContext, task: Dictionary) -> String:
	if task["step"] == 0 and not _deposits_have_ore(ctx, task):
		return MiningStep.REASON_EXHAUSTED
	var current: Dictionary = task["steps"][task["step"]]
	var step: TaskStep = _steps[current["type"]]
	var reason: String = step.validate(ctx, task["owner"], current["args"])["reason"]
	return reason if reason != "" else step.queue_reason(ctx, current["args"], task["id"])


## The lap gate: a lap never starts for a deposit that is empty.
func _deposits_have_ore(ctx: SimContext, task: Dictionary) -> bool:
	for entry: Dictionary in task["steps"]:
		if entry["type"] == MINING_STEP and ctx.state["deposits"][entry["args"]["deposit"]]["remaining_g"] == 0:
			return false
	return true


## What stops a step now, or "". Precedence follows autonomy.md section 3. A paid trip and an atomic
## operation are interrupted only by their own failure to start.
func _interruption(ctx: SimContext, unit: Dictionary) -> String:
	var op: Dictionary = unit["op"]
	if op["type"] == MoveStep.OP_MOVING or ATOMIC_OPS.has(op["type"]):
		return op.get("reason", "")
	if _core_offline(ctx, unit):
		return REASON_CORE_OFFLINE
	if op.has("reason"):
		return op["reason"]
	var part_id: int = op["part"]
	if part_id == 0:
		return ""
	var part: Dictionary = ctx.state["parts"][part_id]
	if part["fault"] != "":
		return REASON_MODULE_FAULT
	return REASON_NO_POWER if part["shed"] else ""


## Blocks a cycle. An operation that never got going is dropped, and one under way is held in place.
func _block(ctx: SimContext, unit: Dictionary, task: Dictionary, reason: String) -> void:
	var op: Dictionary = unit["op"]
	if op["type"] == MoveStep.OP_MOVING or ATOMIC_OPS.has(op["type"]):
		_current_step(ctx, unit).report_end(ctx, unit["id"], reason)
		_clear_op(unit)
	if task["state"] != STATE_BLOCKED or task["reason"] != reason:
		_set_blocked(ctx, unit, task, reason)


func _set_blocked(ctx: SimContext, unit: Dictionary, task: Dictionary, reason: String) -> void:
	if task["state"] != STATE_BLOCKED:
		task["since_tick"] = ctx.tick
	task["state"] = STATE_BLOCKED
	task["reason"] = reason
	task["hold"] = _has_op(unit)
	ctx.emit_event("task_blocked", unit["id"], { "task": task["id"], "reason": reason })


func _core_offline(ctx: SimContext, unit: Dictionary) -> bool:
	var core: Dictionary = ctx.state["parts"][unit["core"]]
	return core["fault"] != "" or core["shed"]


func _has_op(unit: Dictionary) -> bool:
	return unit["op"]["type"] != Units.IDLE_OP


func _has_working_op(ctx: SimContext, unit: Dictionary) -> bool:
	return is_running(ctx, unit) and _has_op(unit)


func _current_step(ctx: SimContext, unit: Dictionary) -> TaskStep:
	var task: Dictionary = ctx.state["tasks"][unit["task"]]
	return _steps[task["steps"][task["step"]]["type"]]


func _finish(ctx: SimContext, unit: Dictionary) -> void:
	var id: int = unit["task"]
	_current_step(ctx, unit).report_end(ctx, unit["id"], "")
	_clear_op(unit)
	_forget(ctx, unit)
	ctx.emit_event("task_finished", unit["id"], { "task": id })


func _cancel(ctx: SimContext, unit: Dictionary, reason: String) -> void:
	var id: int = unit["task"]
	if _has_op(unit):
		var step := _current_step(ctx, unit)
		if not step.is_atomic(ctx, unit["id"]):
			step.report_end(ctx, unit["id"], reason)
			_clear_op(unit)
	_forget(ctx, unit)
	ctx.emit_event("task_cancelled", unit["id"], { "task": id, "reason": reason })


## Ends every task on a unit, in ascending task ID.
func _cancel_all(ctx: SimContext, unit: Dictionary, reason: String) -> void:
	var cycle: int = unit["cycle_task"]
	if cycle != 0 and cycle < unit["task"]:
		_cancel_suspended(ctx, unit, reason)
	if unit["task"] != 0:
		_cancel(ctx, unit, reason)
	if unit["cycle_task"] != 0:
		_cancel_suspended(ctx, unit, reason)


## Ends a unit's cycle, running or suspended. An order continues.
func _cancel_cycle(ctx: SimContext, unit: Dictionary, reason: String) -> void:
	if unit["cycle_task"] != 0:
		_cancel_suspended(ctx, unit, reason)
	elif unit["task"] != 0 and ctx.state["tasks"][unit["task"]]["kind"] == KIND_CYCLE:
		_cancel(ctx, unit, reason)


func _cancel_suspended(ctx: SimContext, unit: Dictionary, reason: String) -> void:
	var id: int = unit["cycle_task"]
	ctx.state["tasks"].erase(id)
	unit["cycle_task"] = 0
	ctx.emit_event("task_cancelled", unit["id"], { "task": id, "reason": reason })


## An atomic operation left behind by `stop` runs on alone, and the unit goes idle when it ends.
func _settle_atomic(unit: Dictionary) -> void:
	var op_type: String = unit["op"]["type"]
	if op_type == DockStep.OP_DOCKING and not unit["dock"].is_empty():
		_clear_op(unit)
	elif op_type == UndockStep.OP_UNDOCKING and unit["dock"].is_empty():
		_clear_op(unit)


func _forget(ctx: SimContext, unit: Dictionary) -> void:
	ctx.state["tasks"].erase(unit["task"])
	unit["task"] = 0


func _clear_op(unit: Dictionary) -> void:
	unit["op"] = { "type": Units.IDLE_OP, "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 }


func _sorted(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids
