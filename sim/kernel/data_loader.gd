class_name DataLoader
extends RefCounted
## Reads data/ and converts it to sim units by field name (schemas.md section 2). Definitions are
## cached, since they never change in a run. Callers must not change what these functions return.

const DATA_DIR := "res://data/"
const SCENARIO_DIR := "res://data/scenarios/"
const SCHEMA_VERSION := 1
const EXACT_TOLERANCE := 1e-9
const GRAMS_PER_KG := 1000
const UNITS_PER_KILO := 1000
## GM is stated in km^3/s^2 and held in units of 1000 m^3/s^2 (orbital_flight.md section 11.4).
const GM_FACTOR := 1_000_000
## Whole numbers below this convert by integer multiplication, so a large one stays exact.
const WHOLE_LIMIT := 9007199254740992.0
## Fields the simulation never reads after load. They stay in defs() for the client, but do not
## count toward the data hash, so changing them does not invalidate a save.
const UNREAD_FIELDS: Array[String] = ["visual", "collision", "fabrication", "name", "realism"]
## Suffix rules, longest first, as [data suffix, sim suffix, factor].
const SUFFIX_RULES := [
	["_kg_per_s", "_g_per_s", UNITS_PER_KILO],
	["_kn", "_n", UNITS_PER_KILO],
	["_m_s", "_mm_s", UNITS_PER_KILO],
	["_seconds", "_ticks", Sim.TICKS_PER_SECOND],
	["_kg", "_g", UNITS_PER_KILO],
	["_kw", "_w", UNITS_PER_KILO],
	["_kj", "_j", UNITS_PER_KILO],
	["_m3", "_l", UNITS_PER_KILO],
]

## Why the last call failed. Empty after a success.
static var error := ""

static var _defs_cache := {}
static var _deposits_cache := {}


## All definitions in sim units as { modules, items, recipes, templates, sinks, theories, science,
## bench_test }, or {} with error. These are the authored definitions only: what research derives
## from them is added per game by Research.overlay (C12).
static func load_defs() -> Dictionary:
	error = ""
	if not _defs_cache.is_empty():
		return _defs_cache
	var modules := _load_table("modules")
	var items := _load_table("items")
	var recipes := _load_table("recipes")
	var templates := _load_table("templates")
	var sinks := _load_table("sinks")
	var theories := _load_table("theories")
	var science := _load_table("science")
	var bench_test := _load_section("theories", "bench_test")
	if error != "":
		return {}
	var problem := work_problem(recipes, modules)
	if problem == "":
		problem = delta_problem(modules)
	if problem != "":
		_fail(problem)
		return {}
	_derive_module_items(modules, items)
	_add_recipe_grams(recipes, items)
	_add_amount_grams(bench_test.get("inputs", []), items, "bench_test")
	var theory_ids := theories.keys()
	theory_ids.sort()
	for id: String in theory_ids:
		_add_amount_grams(theories[id].get("qualify", []), items, id)
	if error != "":
		return {}
	_defs_cache = {
		"modules": modules, "items": items, "recipes": recipes,
		"templates": templates, "sinks": sinks, "theories": theories, "science": science,
		"bench_test": bench_test,
	}
	return _defs_cache


## Deposit definitions, which clients must learn through scanning, so they are not in defs().
static func load_deposits() -> Dictionary:
	error = ""
	if _deposits_cache.is_empty():
		_deposits_cache = _load_table("deposits")
	return _deposits_cache


static func has_scenario(scenario_id: String) -> bool:
	return scenario_id.is_valid_ascii_identifier() \
		and FileAccess.file_exists("%s%s.json" % [SCENARIO_DIR, scenario_id])


## One scenario in sim units, or {} with error.
static func load_scenario(scenario_id: String, items: Dictionary) -> Dictionary:
	error = ""
	var parsed: Variant = _read_json("%s%s.json" % [SCENARIO_DIR, scenario_id])
	if error != "":
		return {}
	var scenario: Dictionary = _convert(parsed, "", 1, scenario_id)
	for unit: Dictionary in scenario.get("units", []):
		_add_amount_grams(unit["inventory"], items, unit["key"])
	return {} if error != "" else scenario


## A copy of the definitions holding only what the simulation reads after load.
static func read_after_load(defs: Dictionary) -> Dictionary:
	var result: Dictionary = defs.duplicate(true)
	for section: String in result:
		var entries: Dictionary = result[section]
		for id: String in entries:
			if typeof(entries[id]) != TYPE_DICTIONARY:
				continue  # a single section such as bench_test, not a table of entries
			var entry: Dictionary = entries[id]
			for field: String in UNREAD_FIELDS:
				entry.erase(field)
	return result


## Clears the caches, so a test can load changed files.
static func reset_cache() -> void:
	_defs_cache = {}
	_deposits_cache = {}


static func _load_table(table: String) -> Dictionary:
	var parsed: Variant = _read_json("%s%s.json" % [DATA_DIR, table])
	if error != "":
		return {}
	var result := {}
	for entry: Variant in parsed["entries"]:
		var converted: Dictionary = _convert(entry, "", 1, table)
		result[converted["id"]] = converted
	return result


## A top-level section of a data file other than its entries, converted, or {} if it has none.
static func _load_section(table: String, section: String) -> Dictionary:
	var parsed: Variant = _read_json("%s%s.json" % [DATA_DIR, table])
	if error != "":
		return {}
	if typeof(parsed.get(section)) != TYPE_DICTIONARY:
		return {}
	return _convert_map(parsed[section], "%s.%s" % [table, section])


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_fail("missing %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or roundi(parsed.get("schema_version", 0)) != SCHEMA_VERSION:
		_fail("%s is not a version %d data file" % [path, SCHEMA_VERSION])
		return null
	return parsed


## Copies a parsed value, converting numbers by the field they sit under and renaming fields.
static func _convert(value: Variant, key: String, factor: int, path: String) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			return _exact(value, factor, "%s.%s" % [path, key])
		TYPE_ARRAY:
			var result: Array = []
			var values: Array = value
			for item: Variant in values:
				result.append(_convert(item, key, factor, path))
			return result
		TYPE_DICTIONARY:
			return _convert_map(value, path)
	return value


static func _convert_map(map: Dictionary, path: String) -> Dictionary:
	var result := {}
	for key: String in map:
		if key == "visual":
			result[key] = map[key].duplicate(true)
			continue
		if key == "deltas":
			result[key] = _convert_deltas(map[key], "%s.%s" % [path, key])
			continue
		var rule := _rule(key)
		result[rule[0]] = _convert(map[key], key, rule[1], "%s.%s" % [path, key])
	return result


## An idea's deltas (research.md section 4): each path is renamed to its sim field by the last
## part's suffix rule, as "capabilities.battery.capacity_kj" becomes "capabilities.battery.capacity_j".
## The values are parts per million of the field, so they are never scaled, only checked whole.
static func _convert_deltas(deltas: Dictionary, path: String) -> Dictionary:
	var result := {}
	for data_path: String in deltas:
		var parts := data_path.split(".")
		parts[parts.size() - 1] = _rule(parts[parts.size() - 1])[0]
		result[".".join(parts)] = _exact(deltas[data_path], 1, "%s.%s" % [path, data_path])
	return result


## "" if every idea's delta path names a whole number in its module, in sim units. Otherwise what
## is wrong, for the first in ID order, so a delta can never scale a missing or fractional field.
static func delta_problem(modules: Dictionary) -> String:
	var ids := modules.keys()
	ids.sort()
	for id: String in ids:
		for idea: Dictionary in modules[id].get("ideas", []):
			var paths: Array = idea.get("deltas", {}).keys()
			paths.sort()
			for path: String in paths:
				var value: Variant = modules[id]
				for part in path.split("."):
					value = value.get(part) if typeof(value) == TYPE_DICTIONARY else null
				if typeof(value) != TYPE_INT:
					return "module %s idea %s changes %s, which is not a whole number in the module" % [
						id, idea.get("id", "?"), path]
	return ""


## The sim field name and factor for a data field, as [name, factor].
static func _rule(key: String) -> Array:
	match key:
		"density_kg_m3":
			return ["density_g_l", 1]
		"kg":
			return ["grams", GRAMS_PER_KG]
		"seconds":
			return ["ticks", Sim.TICKS_PER_SECOND]
		"gm_km3_s2":
			return ["gm", GM_FACTOR]
	for rule: Array in SUFFIX_RULES:
		if key.ends_with(rule[0]):
			return [key.trim_suffix(rule[0]) + rule[1], rule[2]]
	return [key, 1]


static func _exact(value: float, factor: int, where: String) -> int:
	if value == floorf(value) and absf(value) < WHOLE_LIMIT:
		return IntMath.mul_div(absi(int(value)), factor, 1) * (1 if value >= 0.0 else -1)
	var scaled := value * factor
	var rounded := roundi(scaled)
	if absf(scaled - rounded) > EXACT_TOLERANCE * maxf(1.0, absf(scaled)):
		_fail("%s = %s does not convert exactly" % [where, value])
	return rounded


## "" if every recipe needs a whole `work` of at least 1 and has no duration left over, and every
## facility does a whole `work_per_tick` of at least 1 (C11, contracts section 5). Otherwise what is
## wrong, naming the first entry in ID order. A job on a facility of rate 0 would never end, and one
## without a rate would fail its first lookup.
static func work_problem(recipes: Dictionary, modules: Dictionary) -> String:
	var recipe_ids := recipes.keys()
	recipe_ids.sort()
	for id: String in recipe_ids:
		var recipe: Dictionary = recipes[id]
		if recipe.has("ticks"):
			return "recipe %s has seconds; recipes take work points instead" % id
		if typeof(recipe.get("work")) != TYPE_INT or recipe["work"] < 1:
			return "recipe %s needs a whole work of at least 1" % id
	var module_ids := modules.keys()
	module_ids.sort()
	for id: String in module_ids:
		var facility: Variant = modules[id].get("capabilities", {}).get("facility")
		if facility == null:
			continue
		if typeof(facility.get("work_per_tick")) != TYPE_INT or facility["work_per_tick"] < 1:
			return "module %s's facility needs a whole work_per_tick of at least 1" % id
	return ""


## One item per module, with the same ID, as schemas.md section 3 sets out.
static func _derive_module_items(modules: Dictionary, items: Dictionary) -> void:
	for id: String in modules:
		var module: Dictionary = modules[id]
		items[id] = {
			"id": id, "name": module["name"], "stage": 5, "cargo_class": "goods",
			"density_g_l": module["mass_g"] / module["volume_l"], "unit_mass_g": module["mass_g"],
		}


static func _add_recipe_grams(recipes: Dictionary, items: Dictionary) -> void:
	for id: String in recipes:
		_add_amount_grams(recipes[id]["inputs"], items, id)
		_add_amount_grams(recipes[id]["outputs"], items, id)


## Gives every entry authored with `count` its `grams`, so all amounts read the same way.
static func _add_amount_grams(entries: Array, items: Dictionary, where: String) -> void:
	for entry: Dictionary in entries:
		if not entry.has("count"):
			continue
		var item: Dictionary = items.get(entry["item"], {})
		if not item.has("unit_mass_g"):
			_fail("%s counts %s, which is not discrete" % [where, entry["item"]])
			return
		entry["grams"] = IntMath.mul_div(entry["count"], item["unit_mass_g"], 1)


static func _fail(message: String) -> void:
	if error == "":
		error = message
