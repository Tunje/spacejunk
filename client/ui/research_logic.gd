class_name ResearchLogic extends RefCounted
## Reads C12's research state for the research panel: theories and their evidence,
## designs and their state, and a preview of a variant before it is designed. What
## is allowed stays the Sim's to say, through check; this only explains it.

const PPM := 1_000_000
const MAX_IDEAS := 4


## "locked", "prototype" or "qualified". A design missing from research.designs is
## qualified if no theory unlocks it, and locked until that theory is proven.
static func design_state(design: String, view: Dictionary, defs: Dictionary) -> String:
	var designs: Dictionary = view.get("research", {}).get("designs", {})
	if designs.has(design):
		return designs[design]
	return "locked" if ResearchLogic.unlocked_by(design, defs) != "" else "qualified"


## The theory whose proof unlocks a design, or "".
static func unlocked_by(design: String, defs: Dictionary) -> String:
	var theories: Dictionary = defs.get("theories", {})
	var ids: Array = theories.keys()
	ids.sort()
	for id: String in ids:
		if (theories[id].get("unlocks", []) as Array).has(design):
			return id
	return ""


static func is_proven(theory: String, view: Dictionary) -> bool:
	return view.get("research", {}).get("theories", {}).has(theory)


## Each evidence need of a theory, as { kind, have, need, met }.
static func evidence(theory: Dictionary, view: Dictionary) -> Array[Dictionary]:
	var counts: Dictionary = view.get("science", {}).get("evidence", {})
	var found: Array[Dictionary] = []
	for need: Dictionary in theory.get("evidence", []):
		var have := int(counts.get(need["kind"], 0))
		found.append({ "kind": need["kind"], "have": have, "need": int(need["count"]), "met": have >= int(need["count"]) })
	return found


## "Survey 2 of 3, Gravity Field 0 of 1"
static func evidence_text(theory: Dictionary, view: Dictionary) -> String:
	var lines: PackedStringArray = []
	for entry: Dictionary in ResearchLogic.evidence(theory, view):
		lines.append("%s %d of %d" % [OrderText.science_kind(entry["kind"]), mini(entry["have"], entry["need"]), entry["need"]])
	return ", ".join(lines) if not lines.is_empty() else "No evidence needed"


## One of: "Proven", "Needs <theory> first", "Gathering evidence", "Ready to prove".
static func theory_status(theory: Dictionary, view: Dictionary, defs: Dictionary) -> String:
	if ResearchLogic.is_proven(theory["id"], view):
		return "Proven"
	for required: String in theory.get("requires", []):
		if not ResearchLogic.is_proven(required, view):
			return "Needs %s first" % defs["theories"].get(required, {}).get("name", required.capitalize())
	for entry: Dictionary in ResearchLogic.evidence(theory, view):
		if not entry["met"]:
			return "Gathering evidence"
	return "Ready to prove"


## "Lab test: 80 points, 10 Processor, 10 Wiring", from the theory's test recipe.
static func test_cost(theory: Dictionary, defs: Dictionary) -> String:
	var recipe: Dictionary = defs["recipes"].get(theory.get("test", ""), {})
	if recipe.is_empty():
		return ""
	var lines: PackedStringArray = ["%d points" % int(recipe.get("points", 0))]
	for input: Dictionary in recipe.get("inputs", []):
		var amount: String = str(input["count"]) if input.has("count") else OrderText.tonnes(input["grams"])
		lines.append("%s %s" % [amount, IndustryLogic.name_of(input["item"], defs)])
	return "Lab test: %s" % ", ".join(lines)


## Every lab facility, as { unit, part }, by unit then part ID.
static func labs(view: Dictionary, defs: Dictionary) -> Array[Dictionary]:
	return ResearchLogic.facilities_of(view, defs, "lab")


## Every facility of a type ("lab", "fabricator"), as { unit, part }, by unit then part ID.
static func facilities_of(view: Dictionary, defs: Dictionary, facility_type: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var ids: Array = view["units"].keys()
	ids.sort()
	for id: int in ids:
		for entry: Dictionary in IndustryLogic.facilities(view["units"][id], defs["modules"]):
			if entry["type"] == facility_type:
				found.append({ "unit": id, "part": entry["part"] })
	return found


## What a recipe still lacks in a unit's hold, and where it is instead, as one line:
## "Assisted Core Prototype and 10 Processor are on Probe". "" when nothing lacks.
static func missing_inputs(view: Dictionary, defs: Dictionary, recipe: String, unit_id: int) -> String:
	var held: Dictionary = view["units"][unit_id]["inventory"]
	var by_place: Dictionary = {}
	var nowhere: PackedStringArray = []
	var ids: Array = view["units"].keys()
	ids.sort()
	for input: Dictionary in defs["recipes"].get(recipe, {}).get("inputs", []):
		var item: String = input["item"]
		if int(held.get(item, 0)) >= int(input["grams"]):
			continue
		var label := IndustryLogic.name_of(item, defs)
		if int(input.get("count", 1)) > 1:
			label = "%d %s" % [input["count"], label]
		var where := ""
		for id: int in ids:
			if id != unit_id and where == "" and int(view["units"][id]["inventory"].get(item, 0)) >= int(input["grams"]):
				where = view["units"][id]["name"]
		if where == "":
			nowhere.append(label)
		else:
			if not by_place.has(where):
				by_place[where] = []
			(by_place[where] as Array).append(label)
	var lines: PackedStringArray = []
	var places: Array = by_place.keys()
	places.sort()
	for where: String in places:
		var here: Array = by_place[where]
		lines.append("%s %s on %s" % [" and ".join(PackedStringArray(here)), "is" if here.size() == 1 else "are", where])
	if not nowhere.is_empty():
		lines.append("%s still to make" % " and ".join(nowhere))
	return "; ".join(lines)


## queue_job of one run of `recipe` at a lab.
static func lab_command(lab: Dictionary, recipe: String) -> Dictionary:
	return { "type": "queue_job", "unit": lab["unit"], "args": { "facility": lab["part"], "recipe": recipe, "count": 1 } }


## Designs worth listing: every one a theory unlocks, then every designed variant.
static func designs(view: Dictionary, defs: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var theories: Dictionary = defs.get("theories", {})
	var ids: Array = theories.keys()
	ids.sort()
	for id: String in ids:
		for design: String in theories[id].get("unlocks", []):
			if not found.has(design):
				found.append(design)
	var variants: Array = view.get("research", {}).get("variants", {}).keys()
	variants.sort()
	for variant: String in variants:
		found.append(variant)
	return found


## What to do next with a design, for the panel.
static func next_step(design: String, view: Dictionary, defs: Dictionary) -> String:
	match ResearchLogic.design_state(design, view, defs):
		"locked":
			var theory := ResearchLogic.unlocked_by(design, defs)
			return "Locked: prove %s" % defs["theories"].get(theory, {}).get("name", theory.capitalize())
		"prototype":
			return "Fabricate its prototype, then bench-test it at a Lab"
	return "Qualified: build it like any part"


## Qualified modules that have ideas, for the variant designer's base choice.
static func variant_bases(view: Dictionary, defs: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var ids: Array = defs["modules"].keys()
	ids.sort()
	for id: String in ids:
		if not (defs["modules"][id].get("ideas", []) as Array).is_empty() and not id.contains("+") \
				and ResearchLogic.design_state(id, view, defs) == "qualified":
			found.append(id)
	return found


## A base's ideas the player may see: hidden ones only once discovered. Each is the
## idea with `locked` added when its theory is unproven.
static func visible_ideas(base: String, view: Dictionary, defs: Dictionary) -> Array[Dictionary]:
	var discovered: Dictionary = view.get("research", {}).get("discovered", {})
	var found: Array[Dictionary] = []
	for idea: Dictionary in defs["modules"].get(base, {}).get("ideas", []):
		if idea.get("hidden", false) and not discovered.has("%s:%s" % [base, idea["id"]]):
			continue
		var shown := idea.duplicate()
		shown["locked"] = idea.has("theory") and not ResearchLogic.is_proven(idea["theory"], view)
		found.append(shown)
	return found


## The variant ID the Sim gives: base, then the ideas sorted, joined by "+".
static func variant_id(base: String, ideas: Array) -> String:
	var sorted := ideas.duplicate()
	sorted.sort()
	return "+".join(PackedStringArray([base] + sorted))


static func design_command(base: String, ideas: Array) -> Dictionary:
	var sorted := ideas.duplicate()
	sorted.sort()
	return { "type": "design_variant", "unit": 0, "args": { "base": base, "ideas": sorted } }


## What the chosen ideas would make, before asking the Sim: each changed figure from
## base to new, the complexity, the prototype's points and how much dearer the
## normal recipe gets. The Sim's own numbers come into defs once it is designed.
static func preview(base: String, ideas: Array, defs: Dictionary) -> Dictionary:
	var module: Dictionary = defs["modules"].get(base, {})
	var by_id: Dictionary = {}
	for idea: Dictionary in module.get("ideas", []):
		by_id[idea["id"]] = idea
	var ppm_by_path: Dictionary = {}
	var complexity := 0
	var points := 0
	for id: String in ideas:
		var idea: Dictionary = by_id.get(id, {})
		complexity += int(idea.get("complexity", 0))
		points += int(idea.get("points", 0))
		for path: String in idea.get("deltas", {}):
			ppm_by_path[path] = int(ppm_by_path.get(path, 0)) + int(idea["deltas"][path])
	var changes: Array[Dictionary] = []
	var paths: Array = ppm_by_path.keys()
	paths.sort()
	for path: String in paths:
		var before := ResearchLogic.value_at(module, path)
		var after: int = IntMath.mul_div(before, PPM + int(ppm_by_path[path]), PPM)
		changes.append({ "path": path, "before": before, "after": after, "ppm": int(ppm_by_path[path]) })
	complexity = maxi(0, complexity)
	return {
		"id": ResearchLogic.variant_id(base, ideas), "changes": changes, "complexity": complexity,
		"points": points, "cost_scale": float(4 + complexity) / 4.0,
	}


## A whole number at a dotted path in a module, such as "capabilities.battery.capacity_j".
static func value_at(module: Dictionary, path: String) -> int:
	var at: Variant = module
	for key in path.split("."):
		if not at is Dictionary or not (at as Dictionary).has(key):
			return 0
		at = at[key]
	return int(at) if at is int or at is float else 0


## "Capacity: +30%" or "Mass: +15%", from a change's path and ppm.
static func change_text(change: Dictionary) -> String:
	var field: String = change["path"].get_slice(".", change["path"].get_slice_count(".") - 1)
	for suffix: String in ["_j", "_w", "_g", "_ppm", "_mm", "_n"]:
		field = field.trim_suffix(suffix)
	var percent := float(change["ppm"]) / 10000.0
	return "%s: %s%s%%" % [field.capitalize(), "+" if percent >= 0.0 else "", String.num(percent, 1).trim_suffix(".0")]
