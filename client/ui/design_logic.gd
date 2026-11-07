class_name DesignLogic extends RefCounted
## Designs (B25): a template with `base` is a buildable template (the hull a recipe
## makes) plus parts to fit in its listed order. "Build with components" (D42) turns a
## design into every job it needs on one builder, components and refining included,
## producers first; "Fit all" fits the parts the built hull still lacks, in order.
## What is allowed stays the Sim's to say: every command is checked before it is sent.

const PATH_JOIN := "/"


## Every design's template ID, by name.
static func designs(defs: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var templates: Dictionary = defs.get("templates", {})
	var ids: Array = templates.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return templates[a]["name"] < templates[b]["name"])
	for id: String in ids:
		if templates[id].has("base"):
			found.append(id)
	return found


## The design's nodes, depth first in listed order, each { path, part, parent_path,
## parent_connector, connector }. The root's path is "".
static func nodes(tree: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	DesignLogic._walk(tree, "", found)
	return found


static func _walk(node: Dictionary, path: String, found: Array[Dictionary]) -> void:
	for child: Dictionary in node.get("children", []):
		var child_path: String = child["parent_connector"] if path.is_empty() else path + PATH_JOIN + child["parent_connector"]
		found.append({ "path": child_path, "part": child["part"], "parent_path": path,
			"parent_connector": child["parent_connector"], "connector": child.get("connector", "mount") })
		DesignLogic._walk(child, child_path, found)


## The nodes a design adds to its base: those not on the base's tree at the same path.
static func extra_nodes(design: String, defs: Dictionary) -> Array[Dictionary]:
	var templates: Dictionary = defs["templates"]
	var base_paths: Dictionary = {}
	for node: Dictionary in DesignLogic.nodes(templates[templates[design]["base"]]["root"]):
		base_paths[node["path"]] = node["part"]
	var extra: Array[Dictionary] = []
	for node: Dictionary in DesignLogic.nodes(templates[design]["root"]):
		if base_paths.get(node["path"], "") != node["part"]:
			extra.append(node)
	return extra


## The recipe whose output is a unit of this template, or "".
static func template_recipe(template: String, defs: Dictionary) -> String:
	var ids: Array = defs["recipes"].keys()
	ids.sort()
	for id: String in ids:
		for output: Dictionary in defs["recipes"][id].get("outputs", []):
			if output.get("unit_template", "") == template:
				return id
	return ""


## The plain recipe that makes an item, lowest ID first, on a facility type the
## builder has; "" if none. Prototypes, tests and variants are never picked.
static func producer(item: String, defs: Dictionary, facility_types: Array) -> String:
	var ids: Array = defs["recipes"].keys()
	ids.sort()
	for id: String in ids:
		if id.contains(":") or id.contains("+"):
			continue
		var recipe: Dictionary = defs["recipes"][id]
		if not facility_types.has(recipe.get("facility", "")):
			continue
		for output: Dictionary in recipe.get("outputs", []):
			if output.get("item", "") == item and not output.has("sink"):
				return id
	return ""


static func output_grams(recipe: Dictionary, item: String, defs: Dictionary) -> int:
	for output: Dictionary in recipe.get("outputs", []):
		if output.get("item", "") == item:
			if output.has("grams"):
				return int(output["grams"])
			return int(output.get("count", 1)) * int(defs["items"].get(item, {}).get("unit_mass_g", 1))
	return 0


## Every job a design needs on a builder holding `stock` (grams by item), producers
## first: { jobs: [{ recipe, runs }], short: { item: grams } }. `short` is what no
## facility here can make, such as ore still to mine. Stock is used before making more.
static func build_plan(design: String, stock: Dictionary, defs: Dictionary, facility_types: Array) -> Dictionary:
	var demand: Dictionary = {}
	var recipe_runs: Dictionary = {}
	var base_recipe := DesignLogic.template_recipe(defs["templates"][design]["base"], defs)
	if base_recipe != "":
		recipe_runs[base_recipe] = 1
	for node: Dictionary in DesignLogic.extra_nodes(design, defs):
		demand[node["part"]] = int(demand.get(node["part"], 0)) + DesignLogic._unit_grams(node["part"], defs)
	if base_recipe != "":
		DesignLogic._add_inputs(defs["recipes"][base_recipe], 1, demand)
	var levels: Dictionary = {}
	var short: Dictionary = {}
	# Consumers before producers: an item's level is above everything it is made from,
	# so once the highest open item is settled, nothing can add to its demand again.
	var done: Dictionary = {}
	while true:
		var item := ""
		var best := -1
		var open: Array = demand.keys()
		open.sort()
		for candidate: String in open:
			var level := DesignLogic._level(candidate, defs, facility_types, levels)
			if not done.has(candidate) and level > best:
				best = level
				item = candidate
		if item.is_empty():
			break
		done[item] = true
		var net := int(demand[item]) - int(stock.get(item, 0))
		if net <= 0:
			continue
		var recipe := DesignLogic.producer(item, defs, facility_types)
		if recipe == "":
			short[item] = net
			continue
		var per_run := DesignLogic.output_grams(defs["recipes"][recipe], item, defs)
		var runs := (net + per_run - 1) / per_run
		recipe_runs[recipe] = int(recipe_runs.get(recipe, 0)) + runs
		DesignLogic._add_inputs(defs["recipes"][recipe], runs, demand)
	var order: Array = recipe_runs.keys()
	order.sort_custom(func(a: String, b: String) -> bool:
		var la := DesignLogic._recipe_level(a, defs, facility_types, levels)
		var lb := DesignLogic._recipe_level(b, defs, facility_types, levels)
		return la < lb if la != lb else a < b)
	var jobs: Array[Dictionary] = []
	for recipe: String in order:
		jobs.append({ "recipe": recipe, "runs": recipe_runs[recipe] })
	return { "jobs": jobs, "short": short }


static func _add_inputs(recipe: Dictionary, runs: int, demand: Dictionary) -> void:
	for input: Dictionary in recipe.get("inputs", []):
		demand[input["item"]] = int(demand.get(input["item"], 0)) + int(input["grams"]) * runs


static func _unit_grams(item: String, defs: Dictionary) -> int:
	return int(defs["items"].get(item, {}).get("unit_mass_g", 1))


## 0 for what no facility here makes, otherwise one above the highest of its inputs.
static func _level(item: String, defs: Dictionary, facility_types: Array, levels: Dictionary, depth := 0) -> int:
	if levels.has(item):
		return levels[item]
	var recipe := DesignLogic.producer(item, defs, facility_types)
	var level := 0
	if recipe != "" and depth < 16:
		level = DesignLogic._recipe_level(recipe, defs, facility_types, levels, depth + 1)
	levels[item] = level
	return level


static func _recipe_level(recipe: String, defs: Dictionary, facility_types: Array, levels: Dictionary, depth := 0) -> int:
	var level := 1
	for input: Dictionary in defs["recipes"][recipe].get("inputs", []):
		level = maxi(level, DesignLogic._level(input["item"], defs, facility_types, levels, depth + 1) + 1)
	return level


## queue_job commands for a plan on one builder: each recipe on the first facility of
## its type. `facilities` as IndustryLogic.facilities gives them.
static func queue_commands(plan: Dictionary, unit_id: int, facilities: Array, defs: Dictionary) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	for job: Dictionary in plan["jobs"]:
		var recipe: Dictionary = defs["recipes"][job["recipe"]]
		for facility: Dictionary in facilities:
			if facility["type"] == recipe.get("facility", ""):
				commands.append(IndustryLogic.start_command(unit_id, facility["part"], recipe, job["runs"], false))
				break
	return commands


## "9 Refine Hematite, 11 Structural Frame, …", for the button's preview.
static func plan_text(plan: Dictionary, defs: Dictionary) -> String:
	var lines: PackedStringArray = []
	for job: Dictionary in plan["jobs"]:
		lines.append("%d %s" % [job["runs"], IndustryLogic.name_of(job["recipe"], defs)])
	return ", ".join(lines)


## "Needs 120 kg more Hematite Ore, mined first", or "".
static func short_text(plan: Dictionary, defs: Dictionary) -> String:
	var lines: PackedStringArray = []
	var items: Array = plan["short"].keys()
	items.sort()
	for item: String in items:
		lines.append("%s %s" % [OrderText.tonnes(plan["short"][item]), IndustryLogic.name_of(item, defs)])
	return "" if lines.is_empty() else "Needs %s more first" % " and ".join(lines)


# --- Fit all ---

## The unit's part at a design path ("" is the root), or {}.
static func part_at(unit: Dictionary, path: String) -> Dictionary:
	var at: Dictionary = unit.get("parts", {})
	if path.is_empty():
		return at
	for step: String in path.split(PATH_JOIN):
		var next := {}
		for child: Dictionary in at.get("children", []):
			if child["parent_connector"] == step:
				next = child
		if next.is_empty():
			return {}
		at = next
	return at


## Designs a unit can be finished as: its root is the design's root part.
static func designs_for_unit(unit: Dictionary, defs: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for design: String in DesignLogic.designs(defs):
		if defs["templates"][design]["root"]["part"] == unit.get("parts", {}).get("def", ""):
			found.append(design)
	return found


## The next part Fit all would fit: the first extra node with nothing at its path,
## as the node, or {} when every part is on.
static func next_fit(design: String, unit: Dictionary, defs: Dictionary) -> Dictionary:
	for node: Dictionary in DesignLogic.extra_nodes(design, defs):
		if DesignLogic.part_at(unit, node["path"]).is_empty():
			return node
	return {}


## attach_part for a node onto a unit, from the first unit of `group` holding the item,
## or {} if no one holds it or its parent isn't on yet.
static func fit_command(node: Dictionary, unit_id: int, view: Dictionary, group: Array) -> Dictionary:
	var parent := DesignLogic.part_at(view["units"][unit_id], node["parent_path"])
	if parent.is_empty():
		return {}
	for holder: int in group:
		if int(view["units"].get(holder, {}).get("inventory", {}).get(node["part"], 0)) > 0:
			return { "type": "attach_part", "unit": unit_id, "args": { "item": node["part"], "from": holder,
				"parent_part": parent["id"], "parent_connector": node["parent_connector"],
				"part_connector": node["connector"] } }
	return {}


## The design's AI core part on the unit, when it isn't the assigned core yet; 0 otherwise.
static func core_to_assign(design: String, unit: Dictionary, defs: Dictionary) -> int:
	for node: Dictionary in DesignLogic.extra_nodes(design, defs):
		if defs["modules"].get(node["part"], {}).get("capabilities", {}).has("ai_core"):
			var part := DesignLogic.part_at(unit, node["path"])
			if not part.is_empty() and int(unit.get("core", 0)) != int(part["id"]):
				return part["id"]
	return 0
