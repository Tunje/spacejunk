class_name IndustryLogic extends RefCounted
## Works out facilities, recipes and job text from the view and defs. Starting
## and cancelling stay Sim commands; nothing here decides what is allowed.
## Sinks that take a lab or prototype run's spent inputs, which aren't products.
const TEST_SINKS: Array[String] = ["test_consumed", "fab_scrap"]

## C9: jobs on one facility, counting the active one.
const QUEUE_LIMIT := 16
const STATUS_TEXT: Dictionary = {
	"queued": "Queued",
	"waiting": "Waiting",
	"running": "Running",
	"paused": "Paused",
	"cancelling": "Cancelling",
}


## Facility parts on a unit, as { part, name, type, rate }, where rate is the
## facility's work_per_tick.
static func facilities(unit: Dictionary, modules: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for part: Dictionary in InspectText.flatten(unit["parts"]):
		var module: Dictionary = modules[part["def"]]
		if module["capabilities"].has("facility"):
			var capability: Dictionary = module["capabilities"]["facility"]
			found.append({ "part": part["id"], "name": module["name"], "type": capability["type"],
				"rate": int(capability.get("work_per_tick", 0)) })
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
## `install_to`, when given, builds the part straight onto a unit (C15).
static func start_command(unit_id: int, facility_part: int, recipe: Dictionary, count: int, idle := true,
		install_to: Dictionary = {}) -> Dictionary:
	var args := { "facility": facility_part, "recipe": recipe["id"], "count": count }
	if not install_to.is_empty():
		args["install_to"] = install_to
	return { "type": "start_job" if idle else "queue_job", "unit": unit_id, "args": args }


## C15: the module a recipe makes, if its one stored output is a module with count
## 1, so it can be built straight onto a unit; otherwise "".
static func module_output(recipe: Dictionary, defs: Dictionary) -> String:
	var stored: Array = recipe.get("outputs", []).filter(func(output: Dictionary) -> bool:
		return output.has("item") and not output.has("sink"))
	if stored.size() != 1 or int(stored[0].get("count", 1)) != 1:
		return ""
	return stored[0]["item"] if defs["modules"].has(stored[0]["item"]) else ""


## Units a part made here can be built onto: this unit, then any docked to it
## either way, in ID order.
static func install_units(view: Dictionary, unit_id: int) -> Array[int]:
	var found: Array[int] = [unit_id]
	var ids: Array = view["units"].keys()
	ids.sort()
	var own_dock: Dictionary = view["units"][unit_id]["dock"]
	for id: int in ids:
		if id == unit_id:
			continue
		var dock: Dictionary = view["units"][id]["dock"]
		if (not dock.is_empty() and dock["target_unit"] == unit_id) or (not own_dock.is_empty() and own_dock["target_unit"] == id):
			found.append(id)
	return found


## The job's install_to for a free slot on a unit, mating the new part by its mount.
static func install_to(unit_id: int, slot: Dictionary) -> Dictionary:
	return { "unit": unit_id, "parent_part": slot["part"], "parent_connector": slot["connector"],
		"part_connector": FittingLogic.ROOT_MOUNT }


## Moves a job to a 1-based place among the queued jobs. Out of range is clamped.
static func move_command(unit_id: int, job_id: int, position: int) -> Dictionary:
	return { "type": "move_job", "unit": unit_id, "args": { "job": job_id, "position": position } }


static func cancel_command(unit_id: int, job_id: int) -> Dictionary:
	return { "type": "cancel_job", "unit": unit_id, "args": { "job": job_id } }


## A recipe or item's display name, whichever definition holds it.
static func name_of(id: String, defs: Dictionary) -> String:
	if id.begins_with("qualify:"):
		return "Bench Test: %s" % IndustryLogic.name_of(id.trim_prefix("qualify:"), defs)
	if id.contains("+"):
		return OrderText.variant_name(id, defs["items"])
	for section: String in ["items", "modules", "templates"]:
		if defs[section].has(id):
			return defs[section][id]["name"]
	return id.capitalize()


## "Iron 2.0 t of 5.0 t" for each input, against this unit's stock, and a lab
## recipe's science points against the points banked (when known).
static func inputs_line(recipe: Dictionary, stock: Dictionary, defs: Dictionary, points := -1) -> String:
	var lines: PackedStringArray = []
	if recipe.has("points"):
		lines.append("Science %d of %d points" % [points, recipe["points"]] if points >= 0 else "Science %d points" % recipe["points"])
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
		if TEST_SINKS.has(output.get("sink", "")):
			continue
		if output.has("grams"):
			lines.append("%s %s" % [OrderText.tonnes(output["grams"]), IndustryLogic.name_of(output.get("item", output.get("unit", "")), defs)])
		elif output.has("theory"):
			lines.append("proof of %s" % defs.get("theories", {}).get(output["theory"], {}).get("name", String(output["theory"]).capitalize()))
		elif output.has("qualifies"):
			lines.append("a qualified %s design" % IndustryLogic.name_of(output["qualifies"], defs))
		else:
			lines.append(IndustryLogic.name_of(output.get("item", output.get("unit", "")), defs))
	return ", ".join(lines)


## Whether a job may move: a queued one, or an active one still waiting to begin.
static func can_move(job: Dictionary) -> bool:
	return job.get("queue_pos", 0) > 0 or job["status"] == "waiting"


## `units`, the view's units, names where a job builds its part (C15).
static func job_line(job: Dictionary, defs: Dictionary, ticks_per_second: float, units: Dictionary = {}) -> String:
	var line := "%s: %s" % [IndustryLogic.name_of(job["recipe"], defs), STATUS_TEXT.get(job["status"], job["status"].capitalize())]
	var target: Dictionary = job.get("install_to", {})
	if not target.is_empty():
		line = "%s into %s: %s" % [IndustryLogic.name_of(job["recipe"], defs),
			units.get(target["unit"], {}).get("name", "unit %d" % target["unit"]), STATUS_TEXT.get(job["status"], job["status"].capitalize())]
	if not job["reason"].is_empty():
		line += ", %s" % OrderText.reason(job["reason"])
	if job["count_left"] > 1:
		line += " (%d left)" % job["count_left"]
	var held := IndustryLogic.limit_text(job)
	if not held.is_empty():
		line += ", %s" % held
	var left := IndustryLogic.seconds_left(job, ticks_per_second)
	if left > 0.0:
		line += ", about %s" % OrderText.duration(left)
	return line


## Words for C30's limit on a running job: which of power, radiator heat headroom
## and the machine's own throughput holds it, at its rate now; or that its inputs
## are still coming through the docks. "" when the job isn't running or says none.
static func limit_text(job: Dictionary) -> String:
	if job.get("status", "") != "running":
		return ""
	var rate := InspectText.watts(int(job.get("rate_w", 0)))
	match job.get("limit", ""):
		"power":
			return "held to %s by power" % rate
		"heat":
			return "held to %s by radiator headroom" % rate
		"throughput":
			return "at the machine's full %s" % rate
		"feed":
			return "waiting on inputs through the docks"
	return ""


## A queued job's row: being in the queue says it is queued, so the line is the
## recipe, its runs and their time.
static func queue_line(job: Dictionary, defs: Dictionary, ticks_per_second: float) -> String:
	var line := IndustryLogic.name_of(job["recipe"], defs)
	if job["count_left"] > 1:
		line += " (%d left)" % job["count_left"]
	# Queued, it has no rate yet: at the machine's full speed is the best it can do.
	var left := IndustryLogic.seconds_left(job, ticks_per_second)
	if left > 0.0:
		line += ", at least %s" % OrderText.duration(left)
	return line


## How far the current run is, from its energy (C30), or work points before. A paused
## run keeps its place.
static func job_progress(job: Dictionary) -> float:
	var total := int(job.get("energy_j", job.get("work", 0)))
	var left := int(job.get("energy_left_j", job.get("work_left", 0)))
	if total <= 0 or left <= 0:
		return 0.0
	return 1.0 - float(left) / float(total)


## Ticks for `work` points at `rate` a tick: the facility does its rate each tick,
## and the last tick's spare work is lost.
static func run_ticks(work: int, rate: int) -> int:
	return ceili(float(work) / float(rate)) if rate > 0 else 0


## Seconds until the active run delivers, or, for a queued job, all its runs. 0 when
## nothing is under way or the time isn't known.
## C30: a running run's time is its energy left at its rate now (W is J a second), and
## unknown while it is fed through the docks at no rate. A queued job is put at the
## machine's full speed, the best it can do.
static func seconds_left(job: Dictionary, ticks_per_second: float) -> float:
	var rate: int = job.get("work_per_tick", 0)
	if job.get("queue_pos", 0) > 0:
		return job["count_left"] * IndustryLogic.run_ticks(job.get("energy_j", job.get("work", 0)), rate) / ticks_per_second
	if job["status"] != "running":
		return 0.0
	if job.has("rate_w"):
		var watts := int(job["rate_w"])
		return float(job["energy_left_j"]) / watts if watts > 0 else 0.0
	return IndustryLogic.run_ticks(job["work_left"], rate) / ticks_per_second
