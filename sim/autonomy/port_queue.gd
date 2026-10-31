class_name PortQueue
extends RefCounted
## First come, first served for one port (autonomy.md section 8). The queue is never stored: it is
## worked out from each waiter's `since_tick`, then entity ID, so it needs nothing in a save.


## True if a task may take a port now.
static func is_next(ctx: SimContext, port: int, task_id: int) -> bool:
	var first := _first_waiter(ctx, port)
	return first.is_empty() or first["id"] == task_id


## True if a job waiting since `since` is ahead of every task waiting for this port.
static func is_free_for_job(ctx: SimContext, port: int, since: int, job_id: int) -> bool:
	var first := _first_waiter(ctx, port)
	return first.is_empty() or since < first["since"] or (since == first["since"] and job_id < first["id"])


## The earliest task waiting for a port as { since, id }, or {} if none.
static func _first_waiter(ctx: SimContext, port: int) -> Dictionary:
	var tasks: Dictionary = ctx.state["tasks"]
	var ids: Array = tasks.keys()
	ids.sort()
	var first := {}
	for id: int in ids:
		var task: Dictionary = tasks[id]
		if not _is_waiting(ctx, task, port):
			continue
		if first.is_empty() or task["since_tick"] < first["since"]:
			first = { "since": task["since_tick"], "id": id }
	return first


## A task waits for a port while it is blocked on it, or while its dock awaits its phase 4 grant.
static func _is_waiting(ctx: SimContext, task: Dictionary, port: int) -> bool:
	var step: Dictionary = task["steps"][task["step"]]
	if step["type"] != "dock" or step["args"]["target_port"] != port:
		return false
	if task["state"] == TaskSystem.STATE_BLOCKED:
		return task["reason"] == DockStep.REASON_PORT_BUSY
	var op: Dictionary = ctx.state["units"][task["owner"]]["op"]
	return op["type"] == DockStep.OP_DOCKING and not op.has("granted")
