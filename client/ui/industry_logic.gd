class_name IndustryLogic extends RefCounted
## Works out facilities, recipes and job text from the view and defs. Starting
## and cancelling stay Sim commands; nothing here decides what is allowed.

## C9: jobs on one facility, counting the active one.
const QUEUE_LIMIT := 16
const STATUS_TEXT: Dictionary = {
	"queued": "Queued",
	"waiting": "Waiting",
	"running": "Running",
	"paused": "Paused",
	"cancelling": "Cancelling",
}


## Facility parts on a unit, as { part, name, type }.
static func facilities(unit: Dictionary, modules: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for part: Dictionary in InspectText.flatten(unit["parts"]):
		var module: Dictionary = modules[part["def"]]
		if module["capabilities"].has("facility"):
			found.append({ "part": part["id"], "name": module["name"], "type": module["capabilities"]["facility"]["type"] })
	return found


## The unit the panel should work on: the selected one if it has facilities,
## then the commanded craft's dock host, then the lowest ID that has any.
static func working_unit(view: Dictionary, modules: Dictionary, selected_kind: String, selected_id: int, commanded: int) -> int:
	if selected_kind == "unit" and _has_facility(view, modules, selected_id):
		return selected_id
	var dock: Dictionary = view["units"].get(commanded, {}).get("dock", {})
	if not dock.is_empty() and _has_facility(view, modules, dock["target_unit"]):
		return dock["target_unit"]
	var ids: Array = view["units"].keys()
	ids.sort()
	for id: int in ids:
		if _has_facility(view, modules, id):
			return id
	return 0


static func _has_facility(view: Dictionary, modules: Dictionary, unit_id: int) -> bool:
	return view["units"].has(unit_id) and not IndustryLogic.facilities(view["units"][unit_id], modules).is_empty()


static func recipes_for(facility_type: String, recipes: Dictionary) -> Array[Dictionary]:
	var ids: Array = recipes.keys()
	ids.sort()
	var found: Array[Dictionary] = []
	for id: String in ids:
		if recipes[id]["facility"] == facility_type:
			found.append(recipes[id])
	return found


## The facility's active job, at queue position 0, or {} when it is idle.
static func job_on(view: Dictionary, facility_part: int) -> Dictionary:
	var jobs := IndustryLogic.queue_on(view, facility_part)
	return jobs[0] if not jobs.is_empty() and jobs[0].get("queue_pos", 0) == 0 else {}


## Every job on the facility with its `id`, the active one first, then the queue
## in order. A view from before C9 has no `queue_pos`, and only ever one job.
static func queue_on(view: Dictionary, facility_part: int) -> Array[Dictionary]:
	var ids: Array = view["jobs"].keys()
	ids.sort()
	var jobs: Array[Dictionary] = []
	for id: int in ids:
		if view["jobs"][id]["facility"] == facility_part:
			var job: Dictionary = view["jobs"][id].duplicate()
			job["id"] = id
			jobs.append(job)
	jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("queue_pos", 0) < b.get("queue_pos", 0))
	return jobs


## queue_job adds to the end of the queue and starts an idle facility.
## start_job is the pre-C9 order, kept for a Sim without the queue.
static func start_command(unit_id: int, facility_part: int, recipe: Dictionary, count: int, idle := true) -> Dictionary:
	var args := { "facility": facility_part, "recipe": recipe["id"], "count": count }
	return { "type": "start_job" if idle else "queue_job", "unit": unit_id, "args": args }


## Moves a job to a 1-based place among the queued jobs. Out of range is clamped.
static func move_command(unit_id: int, job_id: int, position: int) -> Dictionary:
	return { "type": "move_job", "unit": unit_id, "args": { "job": job_id, "position": position } }


static func cancel_command(unit_id: int, job_id: int) -> Dictionary:
	return { "type": "cancel_job", "unit": unit_id, "args": { "job": job_id } }


## A recipe or item's display name, whichever definition holds it.
static func name_of(id: String, defs: Dictionary) -> String:
	for section: String in ["items", "modules", "templates"]:
		if defs[section].has(id):
			return defs[section][id]["name"]
	return id.capitalize()


## "Iron 2.0 t of 5.0 t" for each input, against this unit's stock.
static func inputs_line(recipe: Dictionary, stock: Dictionary, defs: Dictionary) -> String:
	var lines: PackedStringArray = []
	for input: Dictionary in recipe["inputs"]:
		var have: int = stock.get(input["item"], 0)
		lines.append("%s %s of %s" % [IndustryLogic.name_of(input["item"], defs), OrderText.tonnes(have), OrderText.tonnes(input["grams"])])
	return ", ".join(lines)


static func has_inputs(recipe: Dictionary, stock: Dictionary) -> bool:
	for input: Dictionary in recipe["inputs"]:
		if stock.get(input["item"], 0) < input["grams"]:
			return false
	return true


static func outputs_line(recipe: Dictionary, defs: Dictionary) -> String:
	var lines: PackedStringArray = []
	for output: Dictionary in recipe["outputs"]:
		if output.has("grams"):
			lines.append("%s %s" % [OrderText.tonnes(output["grams"]), IndustryLogic.name_of(output.get("item", output.get("unit", "")), defs)])
		else:
			lines.append(IndustryLogic.name_of(output.get("item", output.get("unit", "")), defs))
	return ", ".join(lines)


## Whether a job may move: a queued one, or an active one still waiting to begin.
static func can_move(job: Dictionary) -> bool:
	return job.get("queue_pos", 0) > 0 or job["status"] == "waiting"


static func job_line(job: Dictionary, defs: Dictionary) -> String:
	var line := "%s: %s" % [IndustryLogic.name_of(job["recipe"], defs), STATUS_TEXT.get(job["status"], job["status"].capitalize())]
	if not job["reason"].is_empty():
		line += ", %s" % OrderText.reason(job["reason"])
	if job["count_left"] > 1:
		line += " (%d left)" % job["count_left"]
	return line


static func job_progress(job: Dictionary, tick: int) -> float:
	if job["status"] != "running" or job["end_tick"] <= job["start_tick"]:
		return 0.0
	return InspectText.ratio(tick - job["start_tick"], job["end_tick"] - job["start_tick"])
