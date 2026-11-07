class_name JobSystem
extends SimSystem
## Refining, fabrication and building units: start_job and cancel_job, the job states of
## autonomy.md section 9 and the matter rules of accounting.md section 2. Jobs belong to facilities
## and need no core. A run takes its inputs and reserves its outputs in phase 4, works in phase 5
## and delivers in phase 6, all at once. A run needs its recipe's `work` points, and its facility
## does its `work_per_tick` each tick it runs, so a slower facility takes longer at the same recipe.
## Work left over on the last tick is lost. A run that builds a unit claims a port only on its last
## tick, so a long build never shuts other craft out.
##
## Lab jobs follow research's rules (ResearchRules): a recipe may need a proven theory or a qualified
## design to start, a test needs its evidence and science points to run, and a finished run may
## prove a theory or qualify a design. A run holds its points as it holds its inputs. The player's
## design_variant command lives here too, since it makes recipes for these jobs.
##
## A job whose recipe makes a module may be built in place (C15): `install_to` names a connector on
## the facility's unit or one docked to it, and the finished part is attached there instead of going
## into a hold, so a part too big for any hold can still be made. A fit that fails at delivery holds
## the part on the job, paused with install_blocked, and is tried again each phase 6.
##
## A facility holds an ordered queue of jobs. The job at queue_pos 0 is active and has the states
## above. The rest are queued at 1..n, hold nothing, and wait their turn. When the active job ends,
## the next one becomes active straight away and can start its first run in the next phase 4.
##
## A run draws its inputs from the docked group (C26): its own unit first, then the other units
## joined to it by dock records, by ID, as attach_part takes parts (C21). Outputs, held inputs and
## anything handed back stay with the job's own unit.
##
## A starved queue skips (C24): while the active job waits on missing_inputs or output_full and the
## facility has no run in progress, the queued job with the lowest queue_pos that can start a run
## goes ahead for one run, with job_went_ahead. It keeps its place, goes back to queued when the run
## ends, and the next phase 4 scans from queue_pos 0 again, so the active job takes the facility
## back as soon as it can start. A run in progress is never broken.

const START := "start_job"
const CANCEL := "cancel_job"
const QUEUE := "queue_job"
const MOVE := "move_job"
const QUEUE_LIMIT := 16
const STATUS_QUEUED := "queued"
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
const REASON_QUEUE_FULL := "queue_full"
const REASON_JOB_BUSY := "job_busy"
const REASON_INSTALL_BLOCKED := "install_blocked"
const REASON_NOT_DOCKED := "not_docked"
const REASON_CONNECTOR_OCCUPIED := "connector_occupied"
## The active job's reasons a queued job may go ahead of (C24).
const STARVED_REASONS: Array[String] = [REASON_MISSING_INPUTS, REASON_OUTPUT_FULL]
const INSTALL_FIELDS := {
	"unit": TYPE_INT, "parent_part": TYPE_INT, "parent_connector": TYPE_STRING, "part_connector": TYPE_STRING,
}
const VIEW_FIELDS: Array[String] = [
	"unit", "facility", "recipe", "count_left", "status", "reason", "start_tick", "queue_pos", "work_left",
	"points_held", "install_to",
]

## Builds in place through attach_part's own rules.
var _fitter := FittingSystem.new()


func commands() -> PackedStringArray:
	return PackedStringArray([START, CANCEL, QUEUE, MOVE, ResearchRules.DESIGN_VARIANT])


func unitless_commands() -> PackedStringArray:
	return PackedStringArray([ResearchRules.DESIGN_VARIANT])


func validate(ctx: SimContext, command: Dictionary) -> Dictionary:
	if command["type"] == ResearchRules.DESIGN_VARIANT:
		return ResearchRules.validate_variant(ctx, command)
	if command["type"] == START or command["type"] == QUEUE:
		return _validate_start(ctx, command)
	var job_id: Variant = command["args"].get("job")
	if typeof(job_id) != TYPE_INT:
		return SimSystem.reject(REASON_MALFORMED)
	var jobs: Dictionary = ctx.state["jobs"]
	if not jobs.has(job_id) or jobs[job_id]["unit"] != command["unit"]:
		return SimSystem.reject(REASON_UNKNOWN_JOB)
	if command["type"] == MOVE:
		if typeof(command["args"].get("position")) != TYPE_INT:
			return SimSystem.reject(REASON_MALFORMED)
		if _has_run(jobs[job_id]):
			return SimSystem.reject(REASON_JOB_BUSY)
	elif jobs[job_id]["reason"] == REASON_INSTALL_BLOCKED:
		# Cancelling hands the built part back; refused rather than overfill the hold.
		var table := Units.cargo(ctx.state, ctx.defs, jobs[job_id]["unit"], [] as Array[int], jobs[job_id]["held"])
		if not Units.over_capacity(table).is_empty():
			return SimSystem.reject(REASON_CARGO_FULL)
	return SimSystem.ok()


func apply(ctx: SimContext, command: Dictionary) -> void:
	match command["type"]:
		START, QUEUE:
			_create(ctx, command)
		MOVE:
			_move(ctx, ctx.state["jobs"][command["args"]["job"]], command["args"]["position"])
		ResearchRules.DESIGN_VARIANT:
			ResearchRules.apply_variant(ctx, command)
		_:
			_cancel(ctx, ctx.state["jobs"][command["args"]["job"]])


## Runs straight after phase 1, so cancelled inputs are retried after that tick's commands.
func update_tasks(ctx: SimContext) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		if jobs[id]["status"] == STATUS_CANCELLING:
			_try_return(ctx, jobs[id])


## Phase 4. A waiting job starts its next run if it can. A lab job whose theory or design another
## job has already proven or qualified leaves the queue instead, holding nothing.
func allocate(ctx: SimContext) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		if not jobs.has(id):
			continue
		var job: Dictionary = jobs[id]
		if job["status"] == STATUS_WAITING:
			var done := ResearchRules.done_reason(ctx, _recipe(ctx, job))
			if done != "":
				_emit_ended(ctx, job, "job_cancelled", done)
				_remove(ctx, job)
				continue
			# A queued job that went ahead (C24) keeps the facility until its run ends; the active
			# job keeps the reason it starved on until then.
			if _facility_has_run(ctx, job["facility"]):
				continue
			var reason := _blocker(ctx, job)
			if reason == "":
				_start_run(ctx, job)
			else:
				_set_reason(ctx, job, STATUS_WAITING, reason)
	_skip_starved(ctx)
	for id: int in _sorted(jobs):
		if _needs_port(ctx, jobs[id]):
			_claim_port(ctx, jobs[id])


## C24. For each facility, by part ID, whose active job waits starved with no run in progress: the
## first queued job, by queue_pos, that can start a run now starts one.
func _skip_starved(ctx: SimContext) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	var facilities := {}
	for id: int in _sorted(jobs):
		facilities[jobs[id]["facility"]] = true
	for facility: int in _sorted(facilities):
		var queue := _queue_of(ctx, facility)
		var head: Dictionary = jobs[queue[0]]
		if head["status"] != STATUS_WAITING or not STARVED_REASONS.has(head["reason"]):
			continue
		if _facility_has_run(ctx, facility):
			continue
		for position in range(1, queue.size()):
			var job: Dictionary = jobs[queue[position]]
			if job["status"] != STATUS_QUEUED or ResearchRules.done_reason(ctx, _recipe(ctx, job)) != "" \
					or _blocker(ctx, job) != "":
				continue
			_start_run(ctx, job)
			ctx.emit_event("job_went_ahead", job["unit"], {
				"job": job["id"], "ahead_of": head["id"], "reason": head["reason"],
			})
			break


## Phase 5. Allocation has run, so a part's state is final for this tick.
func run(ctx: SimContext) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		var job: Dictionary = jobs[id]
		if (job["status"] == STATUS_RUNNING or job["status"] == STATUS_PAUSED) \
				and job["reason"] != REASON_INSTALL_BLOCKED:
			_count_down(ctx, job)


## Phase 6, after deliveries: a built part held by a blocked install is fitted once it can be.
func update_stores(ctx: SimContext) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		var job: Dictionary = jobs[id]
		if job["reason"] != REASON_INSTALL_BLOCKED:
			continue
		var item: String = job["held"].keys()[0]
		var attach := _install_command(job, item)
		Units.add_stock(ctx.state["units"][job["unit"]]["inventory"], item, job["held"][item])
		if _fitter.validate(ctx, attach)["ok"]:
			job["held"] = {}
			_resume(ctx, job)
			_fitter.apply(ctx, attach)
			_end_run(ctx, job)
		else:
			Units.remove_stock(ctx.state["units"][job["unit"]]["inventory"], item, job["held"][item])


## Phase 6. Delivers a finished run.
func apply_delta(ctx: SimContext, payload: Dictionary) -> void:
	var job: Dictionary = ctx.state["jobs"][payload["job"]]
	_release_outputs(ctx, job)
	var unit: Dictionary = ctx.state["units"][job["unit"]]
	for output: Dictionary in _recipe(ctx, job)["outputs"]:
		if output.has("unit_template"):
			ConstructionSystem.queue(ctx, job["unit"], job["port"], output["unit_template"], job["id"])
			_release_port(ctx, job)
		elif output.has("theory"):
			ResearchRules.prove(ctx, job["unit"], output["theory"])
		elif output.has("qualifies"):
			ResearchRules.qualify(ctx, job["unit"], output["qualifies"])
		elif output.has("sink"):
			var sink: Dictionary = ctx.state["sinks"].get_or_add(output["sink"], {})
			sink[output["item"]] = sink.get(output["item"], 0) + output["grams"]
		else:
			Units.add_stock(unit["inventory"], output["item"], output["grams"])
	job["held"] = {}
	if not job["install_to"].is_empty() and not _install(ctx, job):
		return
	_end_run(ctx, job)


## Fits a just-built part where the job names, from the facility unit's hold where delivery put it.
## Returns false, with the part held on the job and the job paused, if the fit is refused.
func _install(ctx: SimContext, job: Dictionary) -> bool:
	var item := _module_output(ctx, _recipe(ctx, job))
	var attach := _install_command(job, item)
	var result := _fitter.validate(ctx, attach)
	if result["ok"]:
		_fitter.apply(ctx, attach)
		return true
	var mass_g: int = ctx.defs["modules"][item]["mass_g"]
	Units.remove_stock(ctx.state["units"][job["unit"]]["inventory"], item, mass_g)
	job["held"] = { item: mass_g }
	job["status"] = STATUS_PAUSED
	job["reason"] = REASON_INSTALL_BLOCKED
	ctx.emit_event("job_paused", job["unit"], {
		"job": job["id"], "reason": REASON_INSTALL_BLOCKED, "detail": result["reason"],
	})
	return false


func _install_command(job: Dictionary, item: String) -> Dictionary:
	var target: Dictionary = job["install_to"]
	return {
		"id": job["command"], "tick": 0, "type": FittingSystem.ATTACH, "unit": target["unit"],
		"args": {
			"item": item, "from": job["unit"], "parent_part": target["parent_part"],
			"parent_connector": target["parent_connector"], "part_connector": target["part_connector"],
		},
	}


## Ends a delivered run: points spent, job_finished, and the next run or the end of the job.
func _end_run(ctx: SimContext, job: Dictionary) -> void:
	ctx.state["science"]["spent"] += job["points_held"]
	job["points_held"] = 0
	_emit_ended(ctx, job, "job_finished")
	job["count_left"] -= 1
	if job["count_left"] == 0:
		_remove(ctx, job)
	else:
		# A job that went ahead (C24) goes back to its place in the queue.
		job["status"] = STATUS_WAITING if job["queue_pos"] == 0 else STATUS_QUEUED
		job["start_tick"] = 0


func fill_view(ctx: SimContext, view: Dictionary) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		var shown := {}
		for field in VIEW_FIELDS:
			shown[field] = jobs[id][field]
		shown["work"] = _recipe(ctx, jobs[id])["work"]
		shown["work_per_tick"] = work_per_tick(ctx, jobs[id]["facility"])
		view["jobs"][id] = shown
	ResearchRules.fill_view(ctx, view)


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
	var refusal := ResearchRules.start_refusal(ctx, command["unit"], recipes[args["recipe"]])
	if refusal != "":
		return SimSystem.reject(refusal)
	var queued := _queue_of(ctx, part_id).size()
	if command["type"] == START and queued > 0:
		return SimSystem.reject(REASON_FACILITY_BUSY)
	if queued >= QUEUE_LIMIT:
		return SimSystem.reject(REASON_QUEUE_FULL, { "need": queued + 1, "have": QUEUE_LIMIT })
	if args.has("install_to"):
		return _validate_install(ctx, command, recipes[args["recipe"]])
	return SimSystem.ok()


## install_to (C15): a module recipe run once, onto a free connector of this unit or one docked to
## it, where attach_part would accept the finished part. The fit is dry-run on a throwaway state
## that already holds the part.
func _validate_install(ctx: SimContext, command: Dictionary, recipe: Dictionary) -> Dictionary:
	var target: Variant = command["args"]["install_to"]
	if typeof(target) != TYPE_DICTIONARY or command["args"]["count"] != 1:
		return SimSystem.reject(REASON_MALFORMED)
	for field: String in INSTALL_FIELDS:
		if typeof(target.get(field)) != INSTALL_FIELDS[field]:
			return SimSystem.reject(REASON_MALFORMED)
	var item := _module_output(ctx, recipe)
	if item == "":
		return SimSystem.reject(REASON_MALFORMED)
	var unit: int = command["unit"]
	if target["unit"] != unit and not Units.are_docked(ctx.state, unit, target["unit"]):
		return SimSystem.reject(REASON_NOT_DOCKED)
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		var other: Dictionary = jobs[id]["install_to"]
		if other.get("parent_part", 0) == target["parent_part"] \
				and other.get("parent_connector", "") == target["parent_connector"]:
			return SimSystem.reject(REASON_CONNECTOR_OCCUPIED)
	var trial := SimContext.new(ctx.state.duplicate(true), ctx.defs)
	Units.add_stock(trial.state["units"][unit]["inventory"], item, ctx.defs["modules"][item]["mass_g"])
	var fake_job := { "command": command.get("id", 0), "unit": unit, "install_to": target }
	var result := _fitter.validate(trial, _install_command(fake_job, item))
	if not result["ok"]:
		# A plain refusal of this command: attach_part's own attach_failed event is not this one's.
		return SimSystem.reject(result["reason"], result["detail"])
	return SimSystem.ok()


## The module a recipe makes, when it is the recipe's one stored output, or "".
func _module_output(ctx: SimContext, recipe: Dictionary) -> String:
	var stored: Array = recipe["outputs"].filter(func(output: Dictionary) -> bool: return _is_stored(output))
	if stored.size() != 1 or recipe["outputs"].any(func(output: Dictionary) -> bool: return output.has("unit_template")):
		return ""
	var item: String = stored[0]["item"]
	return item if ctx.defs["modules"].has(item) else ""


func _create(ctx: SimContext, command: Dictionary) -> void:
	var args: Dictionary = command["args"]
	var id := ctx.new_id()
	var position := _queue_of(ctx, args["facility"]).size()
	ctx.state["jobs"][id] = {
		"id": id, "unit": command["unit"], "facility": args["facility"], "recipe": args["recipe"],
		"count_left": args["count"], "status": STATUS_WAITING if position == 0 else STATUS_QUEUED,
		"reason": "", "start_tick": 0, "work_left": 0, "since_tick": ctx.tick,
		"command": command["id"], "started": false, "held": {}, "reserved": {}, "port": 0, "points_held": 0,
		"queue_pos": position, "install_to": args.get("install_to", {}).duplicate(),
	}
	if command["type"] == QUEUE:
		ctx.emit_event("job_queued", command["unit"], {
			"job": id, "command": command["id"], "position": position,
		})


## A facility's job IDs in queue order. The active job, if any, comes first.
func _queue_of(ctx: SimContext, facility: int) -> Array[int]:
	var jobs: Dictionary = ctx.state["jobs"]
	var queue: Array[int] = []
	for id: int in _sorted(jobs):
		if jobs[id]["facility"] == facility:
			queue.append(id)
	queue.sort_custom(func(a: int, b: int) -> bool:
		return jobs[a]["queue_pos"] < jobs[b]["queue_pos"])
	return queue


## True for a job with a run in progress, which holds matter and cannot be moved or overtaken.
func _has_run(job: Dictionary) -> bool:
	var status: String = job["status"]
	return status == STATUS_RUNNING or status == STATUS_PAUSED or status == STATUS_CANCELLING


## Moves a job to a queue position, clamped so it never passes a run in progress.
func _move(ctx: SimContext, job: Dictionary, position: int) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	var queue := _queue_of(ctx, job["facility"])
	var first := 1 if _has_run(jobs[queue[0]]) else 0
	var target := clampi(position, first, queue.size() - 1)
	if target == job["queue_pos"]:
		return
	queue.erase(job["id"])
	queue.insert(target, job["id"])
	_renumber(ctx, queue)
	ctx.emit_event("job_moved", job["unit"], { "job": job["id"], "position": target })


## Ends a job and moves the rest of its facility's queue up.
func _remove(ctx: SimContext, job: Dictionary) -> void:
	ctx.state["jobs"].erase(job["id"])
	_renumber(ctx, _queue_of(ctx, job["facility"]))


## Numbers a queue 0..n-1 in the given order. The job at 0 becomes active, and an active job moved
## back becomes queued, leaving waiting as job_resumed says.
func _renumber(ctx: SimContext, queue: Array[int]) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	for position in queue.size():
		var job: Dictionary = jobs[queue[position]]
		job["queue_pos"] = position
		if position == 0 and job["status"] == STATUS_QUEUED:
			job["status"] = STATUS_WAITING
			job["since_tick"] = ctx.tick
		elif position > 0 and job["status"] == STATUS_WAITING:
			if job["reason"] != "":
				ctx.emit_event("job_resumed", job["unit"], { "job": job["id"], "reason": job["reason"] })
			job["status"] = STATUS_QUEUED
			job["reason"] = ""


## Why a run cannot start now, or "".
func _blocker(ctx: SimContext, job: Dictionary) -> String:
	if ctx.state["parts"][job["facility"]]["fault"] != "":
		return REASON_MODULE_FAULT
	var recipe := _recipe(ctx, job)
	var research := ResearchRules.run_blocker(ctx, job["unit"], recipe)
	if research != "":
		return research
	var sources := _sources(ctx, job)
	var inventory: Dictionary = ctx.state["units"][job["unit"]]["inventory"]
	var change := {}
	for input: Dictionary in recipe["inputs"]:
		var item: String = input["item"]
		if _group_stock(ctx, sources, item) < input["grams"]:
			return REASON_MISSING_INPUTS
		# Only what comes out of the job's own unit frees room there for the outputs.
		change[item] = change.get(item, 0) - mini(input["grams"], inventory.get(item, 0))
	for output: Dictionary in recipe["outputs"]:
		if _takes_space(job, output):
			change[output["item"]] = change.get(output["item"], 0) + output["grams"]
	var table := Units.cargo(ctx.state, ctx.defs, job["unit"], [] as Array[int], change)
	return REASON_OUTPUT_FULL if not Units.over_capacity(table).is_empty() else ""


func _start_run(ctx: SimContext, job: Dictionary) -> void:
	if job["reason"] != "":
		ctx.emit_event("job_resumed", job["unit"], { "job": job["id"], "reason": job["reason"] })
	var recipe := _recipe(ctx, job)
	var sources := _sources(ctx, job)
	for input: Dictionary in recipe["inputs"]:
		var item: String = input["item"]
		var left: int = input["grams"]
		for source: int in sources:
			var stock: Dictionary = ctx.state["units"][source]["inventory"]
			var taken := mini(left, stock.get(item, 0))
			if taken > 0:
				Units.remove_stock(stock, item, taken)
				left -= taken
		job["held"][item] = job["held"].get(item, 0) + input["grams"]
	_reserve_outputs(ctx, job, recipe)
	job["points_held"] = recipe.get("points", 0)
	ctx.state["science"]["points"] -= job["points_held"]
	job["status"] = STATUS_RUNNING
	job["reason"] = ""
	job["work_left"] = recipe["work"]
	job["start_tick"] = ctx.tick
	if not job["started"]:
		job["started"] = true
		ctx.emit_event("job_started", job["unit"], { "job": job["id"], "command": job["command"] })


## Reserves what the outputs add to each class, as space that stays taken until delivery.
func _reserve_outputs(ctx: SimContext, job: Dictionary, recipe: Dictionary) -> void:
	var outputs := {}
	for output: Dictionary in recipe["outputs"]:
		if _takes_space(job, output):
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
	return (job["status"] == STATUS_RUNNING or job["status"] == STATUS_PAUSED) and job["port"] == 0 \
		and job["work_left"] <= work_per_tick(ctx, job["facility"]) and _template_of(_recipe(ctx, job)) != ""


## Takes the first free healthy port, or holds the run with its inputs until one is free.
func _claim_port(ctx: SimContext, job: Dictionary) -> void:
	var parts: Dictionary = ctx.state["parts"]
	var since: int = job["since_tick"] if job["reason"] == REASON_NO_FREE_PORT else ctx.tick
	for port: int in _build_ports(ctx, job["unit"]):
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


## Ports a built unit may dock at: the builder's own, then those of the units docked with it, either
## way, by ID, so a probe and its station build onto the station's spare port whichever of them
## holds the dock record (start_and_build.md section 5; C22: the new start's station is docked to
## the probe).
func _build_ports(ctx: SimContext, unit_id: int) -> Array[int]:
	var ports := Units.ports(ctx.state, ctx.defs, unit_id)
	var units: Dictionary = ctx.state["units"]
	for other: int in _sorted(units):
		if other != unit_id and Units.are_docked(ctx.state, unit_id, other):
			ports.append_array(Units.ports(ctx.state, ctx.defs, other))
	return ports


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
	job["work_left"] = maxi(0, job["work_left"] - work_per_tick(ctx, job["facility"]))
	if job["work_left"] == 0:
		ctx.record_delta(job["id"], self, { "job": job["id"] })


func _resume(ctx: SimContext, job: Dictionary) -> void:
	ctx.emit_event("job_resumed", job["unit"], { "job": job["id"], "reason": job["reason"] })
	job["status"] = STATUS_RUNNING
	job["reason"] = ""


func _pause(ctx: SimContext, job: Dictionary, reason: String) -> void:
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
	job["work_left"] = 0
	ctx.state["science"]["points"] += job["points_held"]
	job["points_held"] = 0
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
	_remove(ctx, job)


## A job's end. `reason` is set only when the sim cancels a job itself (contracts section 6).
func _emit_ended(ctx: SimContext, job: Dictionary, type: String, reason: String = "") -> void:
	var data := { "job": job["id"], "recipe": job["recipe"], "facility": job["facility"] }
	if reason != "":
		data["reason"] = reason
	ctx.emit_event(type, job["unit"], data)


## The work points a facility part does per tick it runs.
static func work_per_tick(ctx: SimContext, facility: int) -> int:
	return Units.module_of(ctx.state, ctx.defs, facility)["capabilities"]["facility"]["work_per_tick"]


func _recipe(ctx: SimContext, job: Dictionary) -> Dictionary:
	return ctx.defs["recipes"][job["recipe"]]


## True for an output that goes into the unit's inventory.
func _is_stored(output: Dictionary) -> bool:
	return output.has("item") and not output.has("sink")


## True for an output that needs hold space: a stored output, unless it is the part built in place.
func _takes_space(job: Dictionary, output: Dictionary) -> bool:
	return _is_stored(output) and job["install_to"].is_empty()


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


## Coast (A33, C17). A running job works work_per_tick a tick, so it coasts until its run's last
## tick, which is stepped, and with it a build's port claim. A queued, paused or cancelling job, or a
## waiting one held for a reason, changes nothing until something else does, which is stepped. But
## a job about to start its next run (waiting, no reason) steps, and so does any held job whose
## unit, or install target, has stores coasting in closed form (C20): mined ore could clear
## missing_inputs mid-skip, and a transfer could bring inputs or free room.
func horizon(ctx: SimContext) -> int:
	var skip := NO_LIMIT
	var jobs: Dictionary = ctx.state["jobs"]
	var moving := {}
	var checked := false
	var busy := {}
	for id: int in _sorted(jobs):
		var job: Dictionary = jobs[id]
		match job["status"]:
			STATUS_RUNNING:
				var rate := work_per_tick(ctx, job["facility"])
				skip = mini(skip, (job["work_left"] + rate - 1) / rate - 1)
			STATUS_QUEUED:
				# A queued job may go ahead of a starved active job (C24), once its own stores let it,
				# on an idle facility only.
				if not checked:
					moving = _stores_moving(ctx)
					checked = true
				if busy.is_empty():
					busy = _busy_facilities(ctx)
				if not busy.has(job["facility"]) and _stores_wait_on(ctx, job, moving):
					skip = 0
			_:
				# A held job waits on its unit's stores, or an install target's (C15). If they are
				# changing in closed form, mined or transferred, it could go on mid-skip (C20).
				if job["status"] == STATUS_WAITING and job["reason"] == "":
					skip = 0
				else:
					if not checked:
						moving = _stores_moving(ctx)
						checked = true
					if _stores_wait_on(ctx, job, moving):
						skip = 0
		if skip <= 0:
			ctx.coast_cap = "jobs"
			return 0
	return skip


## The units a run draws its inputs from, in order: the job's own, then the rest of its docked
## group by ID (C26).
func _sources(ctx: SimContext, job: Dictionary) -> Array[int]:
	var unit: int = job["unit"]
	var sources: Array[int] = [unit]
	for id: int in Units.docked_group(ctx.state, unit):
		if id != unit:
			sources.append(id)
	return sources


func _group_stock(ctx: SimContext, sources: Array[int], item: String) -> int:
	var grams := 0
	for source: int in sources:
		grams += ctx.state["units"][source]["inventory"].get(item, 0)
	return grams


## True when the stores a held or queued job waits on are moving in closed form: its group's, from
## which it draws (C26), or its install target's.
func _stores_wait_on(ctx: SimContext, job: Dictionary, moving: Dictionary) -> bool:
	if moving.has(job["install_to"].get("unit", 0)):
		return true
	for id: int in _sources(ctx, job):
		if moving.has(id):
			return true
	return false


## True when any job of the facility has a run in progress.
func _facility_has_run(ctx: SimContext, facility: int) -> bool:
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _queue_of(ctx, facility):
		if _has_run(jobs[id]):
			return true
	return false


## Facilities with a run in progress, plus a key of 0 so the table is never empty once built.
func _busy_facilities(ctx: SimContext) -> Dictionary:
	var busy := { 0: true }
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		if _has_run(jobs[id]):
			busy[jobs[id]["facility"]] = true
	return busy


## Units whose stores coast changes in closed form: miners, and both ends of a transfer.
func _stores_moving(ctx: SimContext) -> Dictionary:
	var moving := {}
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		var op: Dictionary = units[id]["op"]
		if op["type"] == MiningStep.OP_MINING:
			moving[id] = true
		elif op["type"] in [TransferStep.OP_LOADING, TransferStep.OP_UNLOADING]:
			moving[op["from"]] = true
			moving[op["to"]] = true
	return moving


## Coast (C17): each running job does its work for the skipped ticks.
func coast(ctx: SimContext, ticks: int) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	for id: int in _sorted(jobs):
		var job: Dictionary = jobs[id]
		if job["status"] == STATUS_RUNNING:
			job["work_left"] -= ticks * work_per_tick(ctx, job["facility"])
