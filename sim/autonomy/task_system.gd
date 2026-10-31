class_name TaskSystem
extends SimSystem
## Runs tasks: the state machine of autonomy.md section 3, for one-step orders. A step's own
## behaviour lives in its TaskStep.

const STOP := "stop"
const KIND_ORDER := "order"
const STATE_RUNNING := "running"
const REASON_MALFORMED := "malformed_command"
const REASON_INVALID_TARGET := "invalid_target"
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
const ATOMIC_OPS: Array[String] = ["docking", "undocking"]

## The fields a task shows in the view. `op_ended` stays internal.
const VIEW_FIELDS: Array[String] = [
	"id", "owner", "kind", "state", "reason", "hold", "steps", "step", "cycle", "since_tick", "command",
]

var _steps := {}


func _init() -> void:
	for step: TaskStep in [ScanStep.new()]:
		_steps[step.type()] = step


func commands() -> PackedStringArray:
	var types := PackedStringArray([STOP])
	for type: String in _steps:
		types.append(type)
	return types


func validate(ctx: SimContext, command: Dictionary) -> Dictionary:
	if command["type"] == STOP:
		return SimSystem.ok()
	var unit_id: int = command["unit"]
	var unit: Dictionary = ctx.state["units"][unit_id]
	if unit["core"] == 0:
		return SimSystem.reject(REASON_NO_CORE)
	if _core_offline(ctx, unit):
		return SimSystem.reject(REASON_CORE_OFFLINE)
	if ATOMIC_OPS.has(unit["op"]["type"]):
		return SimSystem.reject(REASON_BUSY_DOCKING)
	var step: TaskStep = _steps[command["type"]]
	return step.validate(ctx, unit_id, command["args"])


func apply(ctx: SimContext, command: Dictionary) -> void:
	var unit_id: int = command["unit"]
	var unit: Dictionary = ctx.state["units"][unit_id]
	if command["type"] == STOP:
		if unit["task"] != 0:
			_cancel(ctx, unit, REASON_PLAYER_STOP)
		return
	if unit["task"] != 0:
		_cancel(ctx, unit, REASON_PLAYER_ORDER)
	var id := ctx.new_id()
	ctx.state["tasks"][id] = {
		"id": id, "owner": unit_id, "kind": KIND_ORDER, "state": STATE_RUNNING, "reason": "", "hold": false,
		"steps": [{ "type": command["type"], "args": command["args"].duplicate(true) }],
		"step": 0, "cycle": 0, "since_tick": ctx.tick, "command": command["id"], "op_ended": false,
	}
	unit["task"] = id
	ctx.emit_event("task_started", unit_id, { "task": id, "command": command["id"] })


## Phase 2, in ascending unit ID. A step that started last tick or earlier either completes here,
## is interrupted, or carries on.
func update_tasks(ctx: SimContext) -> void:
	var units: Dictionary = ctx.state["units"]
	for unit_id: int in _sorted(units):
		var unit: Dictionary = units[unit_id]
		if unit["task"] == 0:
			continue
		var task: Dictionary = ctx.state["tasks"][unit["task"]]
		if task["op_ended"]:
			_finish(ctx, unit)
			continue
		var reason := _interruption(ctx, unit)
		if reason != "":
			_cancel(ctx, unit, reason)
		elif unit["op"]["type"] == Units.IDLE_OP:
			var current: Dictionary = task["steps"][task["step"]]
			var step: TaskStep = _steps[current["type"]]
			step.begin(ctx, unit_id, current["args"])


## Phase 6, after deltas. Each operation tests its own end.
func update_stores(ctx: SimContext) -> void:
	var units: Dictionary = ctx.state["units"]
	for unit_id: int in _sorted(units):
		var unit: Dictionary = units[unit_id]
		if unit["task"] == 0 or unit["op"]["type"] == Units.IDLE_OP:
			continue
		var task: Dictionary = ctx.state["tasks"][unit["task"]]
		var step: TaskStep = _steps[task["steps"][task["step"]]["type"]]
		if step.end_test(ctx, unit_id):
			task["op_ended"] = true


func fill_view(ctx: SimContext, view: Dictionary) -> void:
	var tasks: Dictionary = ctx.state["tasks"]
	for id: int in _sorted(tasks):
		var shown := {}
		for field in VIEW_FIELDS:
			shown[field] = tasks[id][field]
		view["tasks"][id] = shown.duplicate(true)


## What stops an order, or "". Precedence follows autonomy.md section 3.
func _interruption(ctx: SimContext, unit: Dictionary) -> String:
	if unit["core"] == 0:
		return REASON_NO_CORE
	if _core_offline(ctx, unit):
		return REASON_CORE_OFFLINE
	var part_id: int = unit["op"]["part"]
	if part_id == 0:
		return ""
	var part: Dictionary = ctx.state["parts"][part_id]
	if part["fault"] != "":
		return REASON_MODULE_FAULT
	return REASON_NO_POWER if part["shed"] else ""


func _core_offline(ctx: SimContext, unit: Dictionary) -> bool:
	var core: Dictionary = ctx.state["parts"][unit["core"]]
	return core["fault"] != "" or core["shed"]


func _finish(ctx: SimContext, unit: Dictionary) -> void:
	var id: int = unit["task"]
	_end(ctx, unit)
	ctx.emit_event("task_finished", unit["id"], { "task": id })


func _cancel(ctx: SimContext, unit: Dictionary, reason: String) -> void:
	var id: int = unit["task"]
	_end(ctx, unit)
	ctx.emit_event("task_cancelled", unit["id"], { "task": id, "reason": reason })


func _end(ctx: SimContext, unit: Dictionary) -> void:
	ctx.state["tasks"].erase(unit["task"])
	unit["task"] = 0
	unit["op"] = { "type": Units.IDLE_OP, "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 }


func _sorted(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids
