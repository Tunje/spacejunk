class_name ResearchDefs
extends RefCounted
## The definitions research derives (contracts section 10, research.md sections 3 and 4): each
## theory-unlocked design's prototype item, prototype recipe and bench test, and each variant's
## module, item and recipes. Pure functions of definitions in sim units, so nothing here is saved.
## The kernel puts what they return into each sim's defs overlay.
##
## Expected input, in sim units as the loader gives it:
## - defs.theories: { id: { unlocks, optional qualify: [inputs] } }
## - defs.bench_test: { inputs, work, power_w }
## - a module's optional ideas: [{ id, points, complexity, deltas: { sim path: ppm } }]
## Every input entry has `grams`, plus `count` for a discrete item.

const PROTOTYPE_PREFIX := "prototype:"
const QUALIFY_PREFIX := "qualify:"
const VARIANT_SEPARATOR := "+"
const SCRAP_SINK := "fab_scrap"
const TEST_SINK := "test_consumed"
const LAB := "lab"
const MAX_IDEAS := 4
const PPM := 1_000_000
## A variant's cost scales by (COMPLEXITY_BASE + complexity) / COMPLEXITY_BASE.
const COMPLEXITY_BASE := 4
const REASON_MALFORMED := "malformed_command"
const REASON_STAT_OUT_OF_RANGE := "stat_out_of_range"


static func prototype_id(design: String) -> String:
	return PROTOTYPE_PREFIX + design


static func qualify_id(design: String) -> String:
	return QUALIFY_PREFIX + design


## A variant's ID: the base, then its sorted idea IDs, joined by "+".
static func variant_id(base: String, ideas: Array) -> String:
	var sorted := ideas.duplicate()
	sorted.sort()
	return VARIANT_SEPARATOR.join(PackedStringArray([base] + sorted))


## The prototype item and recipe and the bench test of every module a theory unlocks, as
## { items, recipes }, each keyed by ID.
static func derive_static(defs: Dictionary) -> Dictionary:
	var items := {}
	var recipes := {}
	var theories: Dictionary = defs.get("theories", {})
	var theory_ids: Array = theories.keys()
	theory_ids.sort()
	for theory_id: String in theory_ids:
		var theory: Dictionary = theories[theory_id]
		var unlocks: Array = theory["unlocks"].duplicate()
		unlocks.sort()
		for design: String in unlocks:
			var module: Dictionary = defs["modules"][design]
			var recipe: Dictionary = defs["recipes"][module["fabrication"]["recipe"]]
			_add_research_entries(defs, design, module, recipe, 0, theory.get("qualify", []), items, recipes)
	return { "items": items, "recipes": recipes }


## A variant of `base` with `ideas`, as { id, module, items, recipes }, or { reason }. Checks only
## what the definitions decide. Whether the base is qualified, an idea is unlocked or the variant
## exists is the command's business.
static func derive_variant(defs: Dictionary, base: String, ideas: Array) -> Dictionary:
	if not defs["modules"].has(base) or ideas.is_empty() or ideas.size() > MAX_IDEAS:
		return { "reason": REASON_MALFORMED }
	var base_module: Dictionary = defs["modules"][base]
	var fabrication: Variant = base_module.get("fabrication")
	if typeof(fabrication) != TYPE_DICTIONARY or not defs["recipes"].has(fabrication.get("recipe", "")):
		return { "reason": REASON_MALFORMED }
	var chosen := _chosen_ideas(base_module, ideas)
	if chosen.is_empty():
		return { "reason": REASON_MALFORMED }
	var id := variant_id(base, ideas)
	var module := _variant_module(base_module, chosen, id)
	if module.is_empty():
		return { "reason": REASON_STAT_OUT_OF_RANGE }
	var complexity := 0
	var points := 0
	for idea: Dictionary in chosen:
		complexity += idea["complexity"]
		points += idea["points"]
	complexity = maxi(0, complexity)
	var base_recipe: Dictionary = defs["recipes"][base_module["fabrication"]["recipe"]]
	var items := { id: _item(id, module["name"], module) }
	var recipes := { id: _variant_recipe(id, module, base_recipe, complexity) }
	var qualify: Array = []
	var theory := _theory_unlocking(defs, base)
	if not theory.is_empty():
		qualify = theory.get("qualify", [])
	_add_research_entries(defs, id, module, recipes[id], points, qualify, items, recipes)
	return { "id": id, "module": module, "items": items, "recipes": recipes, "complexity": complexity }


## The ideas of `base_module` named in `ideas`, in ID order, or [] if any is unknown or repeated.
static func _chosen_ideas(base_module: Dictionary, ideas: Array) -> Array[Dictionary]:
	var known := {}
	for idea: Dictionary in base_module.get("ideas", []):
		known[idea["id"]] = idea
	var sorted := ideas.duplicate()
	sorted.sort()
	var chosen: Array[Dictionary] = []
	for i in sorted.size():
		if typeof(sorted[i]) != TYPE_STRING or not known.has(sorted[i]) or (i > 0 and sorted[i] == sorted[i - 1]):
			return []
		chosen.append(known[sorted[i]])
	return chosen


## The base module with each delta applied once to its base value, or {} if a field ends at 0 or
## below. Connectors, collision, visual, min_ai_tier, volume and the capability keys are unchanged.
static func _variant_module(base_module: Dictionary, chosen: Array[Dictionary], id: String) -> Dictionary:
	var sums := {}
	for idea: Dictionary in chosen:
		var deltas: Dictionary = idea["deltas"]
		for path: String in deltas:
			sums[path] = sums.get(path, 0) + deltas[path]
	var module := base_module.duplicate(true)
	var paths: Array = sums.keys()
	paths.sort()
	for path: String in paths:
		var keys := path.split(".")
		var holder: Dictionary = module
		for i in keys.size() - 1:
			holder = holder[keys[i]]
		var value := IntMath.mul_div(holder[keys[-1]], PPM + sums[path], PPM)
		if value <= 0:
			return {}
		holder[keys[-1]] = value
	module["id"] = id
	module["variant_of"] = base_module["id"]
	module["ideas"] = []
	module["fabrication"] = { "recipe": id }
	var names := PackedStringArray()
	for idea: Dictionary in chosen:
		names.append(idea["name"])
	module["name"] = "%s (%s)" % [base_module["name"], ", ".join(names)]
	return module


## The variant's own recipe: the base's inputs scaled by its complexity, or further until they
## cover its mass, each rounded up; the time scaled by complexity; the same facility and power.
static func _variant_recipe(id: String, module: Dictionary, base_recipe: Dictionary, complexity: int) -> Dictionary:
	var base_g := _mass_of(base_recipe["inputs"])
	var scale_ppm := maxi((COMPLEXITY_BASE + complexity) * PPM / COMPLEXITY_BASE,
		IntMath.mul_div_ceil(module["mass_g"], PPM, base_g))
	var inputs: Array = []
	for input: Dictionary in base_recipe["inputs"]:
		if input.has("count"):
			var count := IntMath.mul_div_ceil(input["count"], scale_ppm, PPM)
			inputs.append({ "item": input["item"], "count": count, "grams": count * (input["grams"] / input["count"]) })
		else:
			inputs.append({ "item": input["item"], "grams": IntMath.mul_div_ceil(input["grams"], scale_ppm, PPM) })
	var recipe := {
		"id": id, "facility": base_recipe["facility"], "power_w": base_recipe["power_w"],
		"work": IntMath.mul_div_ceil(base_recipe["work"], COMPLEXITY_BASE + complexity, COMPLEXITY_BASE),
		"inputs": inputs, "abstract": base_recipe.get("abstract", true),
	}
	recipe["outputs"] = _part_and_scrap(id, module["mass_g"], inputs)
	return recipe


## Adds a design's prototype item, its prototype recipe (twice the normal recipe, plus `points`)
## and its bench test at a lab.
static func _add_research_entries(
	defs: Dictionary, design: String, module: Dictionary, recipe: Dictionary, points: int,
	qualify: Array, items: Dictionary, recipes: Dictionary
) -> void:
	var prototype := prototype_id(design)
	items[prototype] = _item(prototype, module["name"] + " Prototype", module)
	items[prototype]["prototype_of"] = design
	var inputs: Array = []
	for input: Dictionary in recipe["inputs"]:
		var doubled := input.duplicate()
		doubled["grams"] = input["grams"] * 2
		if input.has("count"):
			doubled["count"] = input["count"] * 2
		inputs.append(doubled)
	var built := {
		"id": prototype, "facility": recipe["facility"], "power_w": recipe["power_w"],
		"work": recipe["work"] * 2, "inputs": inputs, "abstract": recipe.get("abstract", true),
		"outputs": _part_and_scrap(prototype, module["mass_g"], inputs),
	}
	if points > 0:
		built["points"] = points
	recipes[prototype] = built
	var bench: Dictionary = defs["bench_test"]
	var test_inputs: Array = [{ "item": prototype, "count": 1, "grams": module["mass_g"] }]
	for input: Dictionary in (qualify if not qualify.is_empty() else bench["inputs"]):
		test_inputs.append(input.duplicate())
	var test_outputs: Array = []
	for input: Dictionary in test_inputs:
		var routed := input.duplicate()
		routed["sink"] = TEST_SINK
		test_outputs.append(routed)
	test_outputs.append({ "qualifies": design })
	recipes[qualify_id(design)] = {
		"id": qualify_id(design), "facility": LAB, "power_w": bench["power_w"], "work": bench["work"],
		"inputs": test_inputs, "outputs": test_outputs, "abstract": true,
	}


## One part of `mass_g`, then the rest of the inputs to the scrap sink. The part takes from the
## inputs in order, so each scrap entry is what is left of one input.
static func _part_and_scrap(id: String, mass_g: int, inputs: Array) -> Array:
	var outputs: Array = [{ "item": id, "count": 1, "grams": mass_g }]
	var left := mass_g
	for input: Dictionary in inputs:
		var used := mini(left, input["grams"])
		left -= used
		if input["grams"] > used:
			outputs.append({ "item": input["item"], "grams": input["grams"] - used, "sink": SCRAP_SINK })
	return outputs


## A discrete goods item for a part of `module`'s mass and volume.
static func _item(id: String, item_name: String, module: Dictionary) -> Dictionary:
	return {
		"id": id, "name": item_name, "stage": 5, "cargo_class": "goods",
		"density_g_l": module["mass_g"] / module["volume_l"], "unit_mass_g": module["mass_g"],
	}


static func _theory_unlocking(defs: Dictionary, design: String) -> Dictionary:
	var theories: Dictionary = defs.get("theories", {})
	var ids: Array = theories.keys()
	ids.sort()
	for theory_id: String in ids:
		if theories[theory_id]["unlocks"].has(design):
			return theories[theory_id]
	return {}


static func _mass_of(entries: Array) -> int:
	var total := 0
	for entry: Dictionary in entries:
		total += entry["grams"]
	return total
