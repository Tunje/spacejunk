class_name JobSystem
extends SimSystem
## Refining, fabrication and building units: start_job and cancel_job, the job states of
## autonomy.md section 9 and the matter rules of accounting.md section 2. Jobs belong to facilities
## and need no core. A run takes its inputs and reserves its outputs in phase 4, counts down in
## phase 5 and delivers in phase 6, all at once. A run that builds a unit claims a port only on its
## last tick, so a long build never shuts other craft out.

const START := "start_job"
const CANCEL := "cancel_job"
const STATUS_WAITING := "waiting"
const STATUS_RUNNING := "running"
const STATUS_PAUSED := "paused"
const STATUS_CANCELLING := "cancelling"
const REASON_MALFORMED := "malformed_command"
const REASON_UNKNOWN_PART := "unknown_part"
const REASON_UNKNOWN_RECIPE := "unknown_recipe"
const REASON_UNKNOWN_JOB := "unknown_job"
const REASON_WRONG_FACILITY := "wrong_facility"
const REASON_FACILITY_BUSY := "facility_busy"
const REASON_MODULE_FAULT := "module_fault"
const REASON_NO_POWER := "no_power"
const REASON_MISSING_INPUTS := "missing_inputs"
const REASON_OUTPUT_FULL := "output_full"
const REASON_NO_FREE_PORT := "no_free_port"
const REASON_CARGO_FULL := "cargo_full"
const VIEW_FIELDS: Array[String] = [
	"unit", "facility", "recipe", "count_left", "status", "reason", "start_tick", "end_tick",
]


func commands() -> PackedStringArray:
	return PackedStringArray([START, CANCEL])


func validate(ctx: SimContext, command: Dictionary) -> Dictionary:
	if command["type"] == START:
		return _validate_start(ctx, command)
	var job_id: Variant = command["args"].get("job")
	if typeof(job_id) != TYPE_INT:
		return SimSystem.reject(REASON_MALFORMED)
	var jobs: Dictionary = ctx.state["jobs"]
	if not jobs.has(job_id) or jobs[job_id]["unit"] != command["unit"]:
		return SimSystem.reject(REASON_UNKNOWN_JOB)
	return SimSystem.ok()


func apply(ctx: SimContext, command: Dictionary) -> void:
	if command["type"] == START:
		_create(ctx, command)
	else:
		_cancel(ctx, ctx.state["jobs"][command["args"]["job"]])


## Runs straight after phase 1, so cancelled inputs are retried after that tick's commands.
func update_tasks(ctx: SimContext) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		if jobs[id]["status"] == STATUS_CANCELLING:
			_try_return(ctx, jobs[id])


## Phase 4. A waiting job starts its next run if it can.
func allocate(ctx: SimContext) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		var job: Dictionary = jobs[id]
		if job["status"] == STATUS_WAITING:
			var reason := _blocker(ctx, job)
			if reason == "":
				_start_run(ctx, job)
			else:
				_set_reason(ctx, job, STATUS_WAITING, reason)
		if _needs_port(ctx, job):
			_claim_port(ctx, job)


## Phase 5. Allocation has run, so a part's state is final for this tick.
func run(ctx: SimContext) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		var job: Dictionary = jobs[id]
		if job["status"] == STATUS_RUNNING or job["status"] == STATUS_PAUSED:
			_count_down(ctx, job)


## Phase 6. Delivers a finished run.
func apply_delta(ctx: SimContext, payload: Dictionary) -> void:
	var job: Dictionary = ctx.state["jobs"][payload["job"]]
	_release_outputs(ctx, job)
	var unit: Dictionary = ctx.state["units"][job["unit"]]
	for output: Dictionary in _recipe(ctx, job)["outputs"]:
		if output.has("unit_template"):
			ConstructionSystem.queue(ctx, job["unit"], job["port"], output["unit_template"], job["id"])
			_release_port(ctx, job)
		elif output.has("sink"):
			var sink: Dictionary = ctx.state["sinks"].get_or_add(output["sink"], {})
			sink[output["item"]] = sink.get(output["item"], 0) + output["grams"]
		else:
			Units.add_stock(unit["inventory"], output["item"], output["grams"])
	job["held"] = {}
	_emit_ended(ctx, job, "job_finished")
	job["count_left"] -= 1
	if job["count_left"] == 0:
		ctx.state["jobs"].erase(job["id"])
	else:
		job["status"] = STATUS_WAITING
		job["start_tick"] = 0
		job["end_tick"] = 0


func fill_view(ctx: SimContext, view: Dictionary) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		var shown := {}
		for field in VIEW_FIELDS:
			shown[field] = jobs[id][field]
		view["jobs"][id] = shown


func _validate_start(ctx: SimContext, command: Dictionary) -> Dictionary:
	var args: Dictionary = command["args"]
	if typeof(args.get("facility")) != TYPE_INT or typeof(args.get("recipe")) != TYPE_STRING \
			or typeof(args.get("count")) != TYPE_INT or args["count"] < 1:
		return SimSystem.reject(REASON_MALFORMED)
	var parts: Dictionary = ctx.state["parts"]
	var part_id: int = args["facility"]
	if not parts.has(part_id) or parts[part_id]["unit"] != command["unit"]:
		return SimSystem.reject(REASON_UNKNOWN_PART)
	var recipes: Dictionary = ctx.defs["recipes"]
	if not recipes.has(args["recipe"]):
		return SimSystem.reject(REASON_UNKNOWN_RECIPE)
	var facility: Dictionary = Units.module_of(ctx.state, ctx.defs, part_id)["capabilities"].get("facility", {})
	if facility.get("type", "") != recipes[args["recipe"]]["facility"]:
		return SimSystem.reject(REASON_WRONG_FACILITY)
	if parts[part_id]["fault"] != "":
		return SimSystem.reject(REASON_MODULE_FAULT)
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in jobs:
		if jobs[id]["facility"] == part_id:
			return SimSystem.reject(REASON_FACILITY_BUSY)
	return SimSystem.ok()


func _create(ctx: SimContext, command: Dictionary) -> void:
	var args: Dictionary = command["args"]
	var id := ctx.new_id()
	ctx.state["jobs"][id] = {
		"id": id, "unit": command["unit"], "facility": args["facility"], "recipe": args["recipe"],
		"count_left": args["count"], "status": STATUS_WAITING, "reason": "",
		"start_tick": 0, "end_tick": 0, "remaining_tick": 0, "since_tick": ctx.tick,
		"command": command["id"], "started": false, "held": {}, "reserved": {}, "port": 0,
	}


## Why a run cannot start now, or "".
func _blocker(ctx: SimContext, job: Dictionary) -> String:
	if ctx.state["parts"][job["facility"]]["fault"] != "":
		return REASON_MODULE_FAULT
	var recipe := _recipe(ctx, job)
	var inventory: Dictionary = ctx.state["units"][job["unit"]]["inventory"]
	var change := {}
	for input: Dictionary in recipe["inputs"]:
		if inventory.get(input["item"], 0) < input["grams"]:
			return REASON_MISSING_INPUTS
		change[input["item"]] = change.get(input["item"], 0) - input["grams"]
	for output: Dictionary in recipe["outputs"]:
		if _is_stored(output):
			change[output["item"]] = change.get(output["item"], 0) + output["grams"]
	var table := Units.cargo(ctx.state, ctx.defs, job["unit"], [] as Array[int], change)
	return REASON_OUTPUT_FULL if not Units.over_capacity(table).is_empty() else ""


func _start_run(ctx: SimContext, job: Dictionary) -> void:
	if job["reason"] != "":
		ctx.emit_event("job_resumed", job["unit"], { "job": job["id"], "reason": job["reason"] })
	var recipe := _recipe(ctx, job)
	var inventory: Dictionary = ctx.state["units"][job["unit"]]["inventory"]
	for input: Dictionary in recipe["inputs"]:
		Units.remove_stock(inventory, input["item"], input["grams"])
		job["held"][input["item"]] = job["held"].get(input["item"], 0) + input["grams"]
	_reserve_outputs(ctx, job, recipe)
	job["status"] = STATUS_RUNNING
	job["reason"] = ""
	job["remaining_tick"] = recipe["ticks"]
	job["start_tick"] = ctx.tick
	job["end_tick"] = ctx.tick + recipe["ticks"] - 1
	if not job["started"]:
		job["started"] = true
		ctx.emit_event("job_started", job["unit"], { "job": job["id"], "command": job["command"] })


## Reserves what the outputs add to each class, as space that stays taken until delivery.
func _reserve_outputs(ctx: SimContext, job: Dictionary, recipe: Dictionary) -> void:
	var outputs := {}
	for output: Dictionary in recipe["outputs"]:
		if _is_stored(output):
			outputs[output["item"]] = outputs.get(output["item"], 0) + output["grams"]
	var before := Units.cargo(ctx.state, ctx.defs, job["unit"])
	var after := Units.cargo(ctx.state, ctx.defs, job["unit"], [] as Array[int], outputs)
	var reserved: Dictionary = ctx.state["units"][job["unit"]]["reserved"]
	for cargo_class in Units.CLASS_ORDER:
		if not after.has(cargo_class):
			continue
		var used_before: Dictionary = before.get(cargo_class, { "used_g": 0, "used_l": 0 })
		var added_g: int = after[cargo_class]["used_g"] - used_before["used_g"]
		var added_l: int = after[cargo_class]["used_l"] - used_before["used_l"]
		if added_g == 0 and added_l == 0:
			continue
		job["reserved"][cargo_class] = { "g": added_g, "l": added_l }
		var total: Dictionary = reserved.get_or_add(cargo_class, { "g": 0, "l": 0 })
		total["g"] += added_g
		total["l"] += added_l


func _release_outputs(ctx: SimContext, job: Dictionary) -> void:
	var reserved: Dictionary = ctx.state["units"][job["unit"]]["reserved"]
	var held: Dictionary = job["reserved"]
	for cargo_class: String in held:
		var total: Dictionary = reserved[cargo_class]
		total["g"] -= held[cargo_class]["g"]
		total["l"] -= held[cargo_class]["l"]
		if total["g"] == 0 and total["l"] == 0:
			reserved.erase(cargo_class)
	job["reserved"] = {}


## True on the tick a run that builds a unit would end, if it has no port yet.
func _needs_port(ctx: SimContext, job: Dictionary) -> bool:
	return (job["status"] == STATUS_RUNNING or job["status"] == STATUS_PAUSED) \
		and job["remaining_tick"] == 1 and job["port"] == 0 and _template_of(_recipe(ctx, job)) != ""


## Takes the first free healthy port, or holds the run with its inputs until one is free.
func _claim_port(ctx: SimContext, job: Dictionary) -> void:
	var parts: Dictionary = ctx.state["parts"]
	var since: int = job["since_tick"] if job["reason"] == REASON_NO_FREE_PORT else ctx.tick
	for port: int in Units.ports(ctx.state, ctx.defs, job["unit"]):
		if parts[port]["fault"] == "" and not Units.port_in_use(ctx.state, port) \
				and PortQueue.is_free_for_job(ctx, port, since, job["id"]):
			parts[port]["claimed_by"] = job["id"]
			job["port"] = port
			if job["reason"] == REASON_NO_FREE_PORT:
				_resume(ctx, job)
			return
	if job["reason"] != REASON_NO_FREE_PORT:
		job["since_tick"] = ctx.tick
	_pause(ctx, job, REASON_NO_FREE_PORT)


func _release_port(ctx: SimContext, job: Dictionary) -> void:
	if job["port"] != 0:
		ctx.state["parts"][job["port"]].erase("claimed_by")
		job["port"] = 0


func _count_down(ctx: SimContext, job: Dictionary) -> void:
	if job["reason"] == REASON_NO_FREE_PORT:
		return
	var part: Dictionary = ctx.state["parts"][job["facility"]]
	if not Units.can_run(part):
		_pause(ctx, job, REASON_MODULE_FAULT if part["fault"] != "" else REASON_NO_POWER)
		return
	if job["status"] == STATUS_PAUSED:
		_resume(ctx, job)
	job["remaining_tick"] -= 1
	if job["remaining_tick"] == 0:
		ctx.record_delta(job["id"], self, { "job": job["id"] })


func _resume(ctx: SimContext, job: Dictionary) -> void:
	ctx.emit_event("job_resumed", job["unit"], { "job": job["id"], "reason": job["reason"] })
	job["status"] = STATUS_RUNNING
	job["reason"] = ""
	job["end_tick"] = ctx.tick + job["remaining_tick"] - 1


func _pause(ctx: SimContext, job: Dictionary, reason: String) -> void:
	job["end_tick"] = 0
	_set_reason(ctx, job, STATUS_PAUSED, reason)


## Records why a job is held, reporting only a change.
func _set_reason(ctx: SimContext, job: Dictionary, status: String, reason: String) -> void:
	if job["status"] == status and job["reason"] == reason:
		return
	job["status"] = status
	job["reason"] = reason
	ctx.emit_event("job_paused", job["unit"], { "job": job["id"], "reason": reason })


func _cancel(ctx: SimContext, job: Dictionary) -> void:
	if job["status"] == STATUS_CANCELLING:
		return
	_release_outputs(ctx, job)
	_release_port(ctx, job)
	job["end_tick"] = 0
	_try_return(ctx, job)
	if ctx.state["jobs"].has(job["id"]):
		_set_reason(ctx, job, STATUS_CANCELLING, REASON_CARGO_FULL)


## Hands all held inputs back and ends the job, or leaves them on the job if they do not fit.
func _try_return(ctx: SimContext, job: Dictionary) -> void:
	var held: Dictionary = job["held"]
	var table := Units.cargo(ctx.state, ctx.defs, job["unit"], [] as Array[int], held)
	if not Units.over_capacity(table).is_empty():
		return
	var inventory: Dictionary = ctx.state["units"][job["unit"]]["inventory"]
	for item: String in _sorted(held):
		Units.add_stock(inventory, item, held[item])
	_emit_ended(ctx, job, "job_cancelled")
	ctx.state["jobs"].erase(job["id"])


func _emit_ended(ctx: SimContext, job: Dictionary, type: String) -> void:
	ctx.emit_event(type, job["unit"], {
		"job": job["id"], "recipe": job["recipe"], "facility": job["facility"],
	})


func _recipe(ctx: SimContext, job: Dictionary) -> Dictionary:
	return ctx.defs["recipes"][job["recipe"]]


## True for an output that goes into the unit's inventory.
func _is_stored(output: Dictionary) -> bool:
	return output.has("item") and not output.has("sink")


## The unit template a recipe builds, or "".
func _template_of(recipe: Dictionary) -> String:
	for output: Dictionary in recipe["outputs"]:
		if output.has("unit_template"):
			return output["unit_template"]
	return ""


func _sorted(table: Dictionary) -> Array:
	var keys: Array = table.keys()
	keys.sort()
	return keys
