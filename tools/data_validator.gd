class_name DataValidator
extends RefCounted

## Checks `data/` against docs/design/schemas.md and section 3 of
## docs/design/accounting.md. Works on raw parsed JSON, so it runs without the sim.
## Each error is "<code> <where>: <detail>". Codes are stable; tests match on them.

const SCHEMA_VERSION := 1
const DATA_DIR := "res://data/"
const FILES := {
	"items": "items.json",
	"modules": "modules.json",
	"recipes": "recipes.json",
	"deposits": "deposits.json",
	"templates": "templates.json",
	"sinks": "sinks.json",
}

const ID_PATTERN := "^[a-z][a-z0-9_]*$"
const TINT_PATTERN := "^#[0-9a-f]{6}$"
const CARGO_CLASSES := ["ore", "goods", "propellant"]
const REALISM := ["established", "extrapolation", "speculative", "fictional"]
const CONNECTOR_TYPES := ["stack", "side", "dock"]
const CONNECTOR_SIZES := ["core", "small", "medium", "large"]
const AXES := ["+x", "-x", "+y", "-y", "+z", "-z"]
const SHAPES := ["box", "cylinder"]
const FACILITIES := ["refinery", "fabricator"]
const UNIT_KINDS := ["ship", "station", "drone"]

const ITEM_FIELDS := ["id", "name", "stage", "cargo_class", "density_kg_m3"]
const MODULE_FIELDS := [
	"id", "name", "mass_kg", "volume_m3", "power_kw", "heat_kw", "priority", "durability",
	"min_ai_tier", "realism", "capabilities", "fabrication", "connectors", "collision", "visual",
]
const CONNECTOR_FIELDS := ["id", "type", "size", "pos_mm", "facing", "up", "load_limit_kg"]
const COLLISION_FIELDS := ["shape", "center_mm", "size_mm"]
const RECIPE_FIELDS := ["id", "facility", "seconds", "power_kw", "inputs", "outputs", "abstract"]
const DEPOSIT_FIELDS := ["id", "item", "mass_kg", "hardness"]
const TEMPLATE_FIELDS := ["id", "name", "kind", "root"]
const SINK_FIELDS := ["id", "name", "items"]
const SCENARIO_DIR := "scenarios/"
const SCENARIO_FIELDS := ["schema_version", "id", "name", "seed", "bodies", "units"]
const BODY_FIELDS := ["key", "name", "kind", "pos_mm", "radius_mm", "visual_seed", "deposits"]
const UNIT_FIELDS := ["key", "template", "name", "pos_mm", "inventory", "dock"]
const DOCK_FIELDS := ["host", "port", "host_port"]
const BODY_KINDS := ["star", "asteroid"]

## Capability fields as field -> [factor, whole number only].
const CAPABILITIES := {
	"scan": { "seconds": [1, true] },
	"mine": { "rate_kg_per_s": [1000, false], "hardness_max": [1, true] },
	"ai_core": { "tier": [1, true] },
	"generate": { "power_kw": [1000, false] },
	"battery": {
		"capacity_kj": [1000, false], "max_charge_kw": [1000, false],
		"max_discharge_kw": [1000, false], "charge_efficiency_ppm": [1, true],
	},
	"radiator": { "reject_kw": [1000, false] },
	"heat_capacity": { "limit_kj": [1000, false] },
	"port": {
		"transfer_kg_per_s": [1000, false], "dock_seconds": [1, true],
		"undock_seconds": [1, true],
	},
	"thruster": {
		"speed_m_s": [1000, false], "propellant_kg_per_s": [1000, false],
		"rated_mass_kg": [1000, false],
	},
}
const OTHER_CAPABILITIES := ["storage", "max_mass_kg", "facility", "always_on"]

const MAX_STACK_G := 1_000_000_000_000_000
const MAX_STORE_J := 1_000_000_000_000_000
const MAX_STORE_L := 1_000_000_000_000
const MAX_RATE := 1_000_000_000_000
const PPM := 1_000_000
## The largest whole number JSON keeps exactly, since Godot parses numbers as floats.
const MAX_JSON_WHOLE := 9_007_199_254_740_992

## Refining yields may not pass the element's real mass share (spec section 7.1).
const YIELD_CEILINGS_PPM := {
	"hematite": { "iron": 699_000 },
	"chalcopyrite": { "copper": 346_000 },
	"olivine": { "silicon": 190_000 },
}

var _errors: Array[String] = []
var _items: Dictionary = {}
var _modules: Dictionary = {}
var _recipes: Dictionary = {}
var _deposits: Dictionary = {}
var _templates: Dictionary = {}
var _sinks: Dictionary = {}
var _scenarios: Array = []
var _id_regex := RegEx.create_from_string(ID_PATTERN)
var _tint_regex := RegEx.create_from_string(TINT_PATTERN)


## Reads every data file. A missing or unparsable file becomes a null entry,
## which validate() reports.
static func load_dir(dir: String = DATA_DIR) -> Dictionary:
	var data := {}
	for key: String in FILES:
		var path: String = dir + FILES[key]
		data[key] = null
		if FileAccess.file_exists(path):
			data[key] = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["scenarios"] = []
	if not DirAccess.dir_exists_absolute(dir + SCENARIO_DIR):
		return data
	var files := DirAccess.get_files_at(dir + SCENARIO_DIR)
	files.sort()
	for file_name: String in files:
		if file_name.ends_with(".json"):
			var text := FileAccess.get_file_as_string(dir + SCENARIO_DIR + file_name)
			data["scenarios"].append(JSON.parse_string(text))
	return data


## Returns all errors in `data`, a map of FILES key to parsed file, plus `scenarios`,
## an array of parsed scenarios. Empty means valid.
static func validate(data: Dictionary) -> Array[String]:
	return DataValidator.new()._run(data)


func _run(data: Dictionary) -> Array[String]:
	_items = _index(data, "items")
	_modules = _index(data, "modules")
	_recipes = _index(data, "recipes")
	_deposits = _index(data, "deposits")
	_templates = _index(data, "templates")
	_sinks = _index(data, "sinks")
	if not _errors.is_empty():
		return _errors

	for id: String in _sorted(_items):
		_shape_item(_items[id])
	for id: String in _sorted(_modules):
		_shape_module(_modules[id])
	for id: String in _sorted(_recipes):
		_shape_recipe(_recipes[id])
	for id: String in _sorted(_deposits):
		_shape_deposit(_deposits[id])
	for id: String in _sorted(_templates):
		_shape_template(_templates[id])
	for id: String in _sorted(_sinks):
		_shape_sink(_sinks[id])
	_scenarios = data.get("scenarios", [])
	if _scenarios.is_empty():
		_err("scenario_missing", "data/scenarios", "at least one scenario is needed")
	for scenario: Variant in _scenarios:
		_shape_scenario(scenario)
	# Cross-checks assume every entry has the right shape.
	if not _errors.is_empty():
		return _errors

	_derive_module_items()
	for id: String in _sorted(_sinks):
		_cross_sink(_sinks[id])
	for id: String in _sorted(_modules):
		_cross_module(_modules[id])
	for id: String in _sorted(_recipes):
		_cross_recipe(_recipes[id])
	for id: String in _sorted(_deposits):
		_cross_deposit(_deposits[id])
	for id: String in _sorted(_templates):
		_cross_template(_templates[id])
	for scenario: Dictionary in _scenarios:
		_cross_scenario(scenario)
	_check_coverage()
	return _errors


func _err(code: String, where: String, detail: String = "") -> void:
	_errors.append("%s %s: %s" % [code, where, detail])


func _sorted(table: Dictionary) -> Array:
	var keys := table.keys()
	keys.sort()
	return keys


## Checks a file's envelope and entry order, and keys its entries by ID.
func _index(data: Dictionary, key: String) -> Dictionary:
	var file: String = FILES[key]
	var parsed: Variant = data.get(key)
	var table := {}
	if not parsed is Dictionary:
		_err("bad_file", file, "missing, unparsable or not an object")
		return table
	if not _has_fields(file, parsed, ["schema_version", "entries"]):
		return table
	if parsed["schema_version"] != SCHEMA_VERSION:
		_err("bad_schema_version", file, str(parsed["schema_version"]))
	if not parsed["entries"] is Array:
		_err("bad_file", file, "entries is not an array")
		return table
	var previous := ""
	for entry: Variant in parsed["entries"]:
		if not entry is Dictionary or not entry.get("id") is String:
			_err("bad_entry", file, "entry has no string id")
			continue
		var id: String = entry["id"]
		if _id_regex.search(id) == null:
			_err("bad_id", file, id)
		if table.has(id):
			_err("duplicate_id", file, id)
		if id < previous:
			_err("entries_unsorted", file, id)
		previous = id
		table[id] = entry
	return table


func _has_fields(where: String, entry: Dictionary, required: Array, optional: Array = []) -> bool:
	var ok := true
	for field: String in required:
		if not entry.has(field):
			_err("missing_field", where, field)
			ok = false
	for field: String in entry:
		if not field in required and not field in optional:
			_err("unknown_field", where, field)
			ok = false
	return ok


func _is_number(value: Variant) -> bool:
	return value is float or value is int


func _is_whole(value: Variant) -> bool:
	return _is_number(value) and float(value) == floor(float(value))


## Sim-unit value, using the loader's conversion (contracts section 1).
func _to_sim(value: Variant, factor: int) -> int:
	return roundi(float(value) * factor)


func _converts_exactly(value: Variant, factor: int) -> bool:
	var scaled := float(value) * factor
	var difference := absf(scaled - roundi(scaled))
	return difference <= 1e-9 * maxf(absf(scaled), 1.0)


## A non-negative number that converts exactly and stays in range.
func _check_number(where: String, field: String, value: Variant, factor: int, limit: int) -> void:
	if not _is_number(value) or float(value) < 0.0:
		_err("bad_number", where, "%s is not a non-negative number" % field)
	elif not _converts_exactly(value, factor):
		_err("inexact_value", where, "%s does not convert exactly" % field)
	elif _to_sim(value, factor) > limit:
		_err("out_of_range", where, field)


func _check_positive(where: String, field: String, value: Variant, factor: int, limit: int) -> void:
	_check_number(where, field, value, factor, limit)
	if _is_number(value) and float(value) == 0.0:
		_err("bad_number", where, "%s must be above 0" % field)


func _check_whole(where: String, field: String, value: Variant, low: int, high: int) -> void:
	if not _is_whole(value):
		_err("not_whole", where, field)
	elif float(value) < low or float(value) > high:
		_err("out_of_range", where, field)


func _check_enum(where: String, field: String, value: Variant, allowed: Array) -> void:
	if not value in allowed:
		_err("bad_enum", where, "%s is %s" % [field, str(value)])


func _check_vector(where: String, field: String, value: Variant, minimum: float) -> void:
	if not value is Array or value.size() != 3:
		_err("bad_vector", where, field)
		return
	for number: Variant in value:
		if not _is_whole(number) or float(number) < minimum:
			_err("bad_vector", where, field)
			return


func _check_name(where: String, entry: Dictionary) -> void:
	if not entry["name"] is String or entry["name"] == "":
		_err("bad_name", where, "name is empty or not a string")


func _shape_item(item: Dictionary) -> void:
	var where := "items.json:%s" % item["id"]
	if not _has_fields(where, item, ITEM_FIELDS, ["unit_mass_kg"]):
		return
	_check_name(where, item)
	_check_whole(where, "stage", item["stage"], 2, 5)
	_check_enum(where, "cargo_class", item["cargo_class"], CARGO_CLASSES)
	_check_whole(where, "density_kg_m3", item["density_kg_m3"], 1, MAX_STORE_L)
	if item.has("unit_mass_kg"):
		_check_positive(where, "unit_mass_kg", item["unit_mass_kg"], 1000, MAX_STACK_G)


func _shape_module(module: Dictionary) -> void:
	var where := "modules.json:%s" % module["id"]
	if not _has_fields(where, module, MODULE_FIELDS):
		return
	_check_name(where, module)
	_check_positive(where, "mass_kg", module["mass_kg"], 1000, MAX_STACK_G)
	_check_positive(where, "volume_m3", module["volume_m3"], 1000, MAX_STORE_L)
	_check_number(where, "power_kw", module["power_kw"], 1000, MAX_RATE)
	_check_number(where, "heat_kw", module["heat_kw"], 1000, MAX_RATE)
	_check_whole(where, "priority", module["priority"], 0, MAX_RATE)
	_check_whole(where, "durability", module["durability"], 1, MAX_RATE)
	_check_whole(where, "min_ai_tier", module["min_ai_tier"], 1, 6)
	_check_enum(where, "realism", module["realism"], REALISM)
	_shape_capabilities(where, module["capabilities"])
	_shape_fabrication(where, module["fabrication"])
	_shape_collision(where, module["collision"])
	if not module["visual"] is Dictionary or not module["visual"].has("model"):
		_err("bad_visual", where, "visual needs a model field")
	elif not (module["visual"]["model"] is String or module["visual"]["model"] == null):
		_err("bad_visual", where, "model is not a string or null")
	elif _holds_number(module["visual"]):
		_err("bad_visual", where, "numbers parse as floats, which the data hash rejects")
	elif not module["visual"].get("tint") is String \
			or _tint_regex.search(module["visual"]["tint"]) == null:
		_err("bad_visual", where, "tint is not a #rrggbb string")
	if not module["connectors"] is Array:
		_err("bad_connectors", where, "connectors is not an array")
		return
	var seen := {}
	for connector: Variant in module["connectors"]:
		if not connector is Dictionary:
			_err("bad_connectors", where, "connector is not an object")
			continue
		_shape_connector(where, connector)
		if seen.has(connector.get("id")):
			_err("duplicate_connector", where, str(connector.get("id")))
		seen[connector.get("id")] = true


func _holds_number(value: Variant) -> bool:
	if value is Dictionary:
		return value.values().any(_holds_number)
	if value is Array:
		return value.any(_holds_number)
	return _is_number(value)


func _shape_capabilities(where: String, capabilities: Variant) -> void:
	if not capabilities is Dictionary:
		_err("bad_capability", where, "capabilities is not an object")
		return
	for key: String in capabilities:
		var value: Variant = capabilities[key]
		var at := "%s.%s" % [where, key]
		if CAPABILITIES.has(key):
			_shape_capability_fields(at, value, CAPABILITIES[key])
		elif key == "storage":
			_shape_storage(at, value)
		elif key == "max_mass_kg":
			_check_positive(at, key, value, 1000, MAX_STACK_G)
		elif key == "facility":
			if value is Dictionary and _has_fields(at, value, ["type"]):
				_check_enum(at, "type", value["type"], FACILITIES)
			elif not value is Dictionary:
				_err("bad_capability", at, "not an object")
		elif key == "always_on":
			if value != true:
				_err("bad_capability", at, "must be true")
		else:
			_err("unknown_capability", where, key)


func _shape_capability_fields(where: String, value: Variant, fields: Dictionary) -> void:
	if not value is Dictionary:
		_err("bad_capability", where, "not an object")
		return
	if not _has_fields(where, value, fields.keys()):
		return
	for field: String in fields:
		var factor: int = fields[field][0]
		if fields[field][1]:
			_check_whole(where, field, value[field], 1, MAX_RATE)
		else:
			_check_positive(where, field, value[field], factor, MAX_RATE)
	if value.has("capacity_kj"):
		_check_number(where, "capacity_kj", value["capacity_kj"], 1000, MAX_STORE_J)
	if value.has("charge_efficiency_ppm") and _is_number(value["charge_efficiency_ppm"]):
		if float(value["charge_efficiency_ppm"]) > PPM:
			_err("out_of_range", where, "charge_efficiency_ppm")
	if value.has("tier"):
		_check_whole(where, "tier", value["tier"], 1, 6)
	if value.has("limit_kj"):
		_check_number(where, "limit_kj", value["limit_kj"], 1000, MAX_STORE_J)


func _shape_storage(where: String, storage: Variant) -> void:
	if not storage is Dictionary or storage.is_empty():
		_err("bad_capability", where, "storage needs at least one cargo class")
		return
	for cargo_class: String in storage:
		_check_enum(where, "cargo class", cargo_class, CARGO_CLASSES)
		var capacity: Variant = storage[cargo_class]
		if not capacity is Dictionary:
			_err("bad_capability", where, "%s is not an object" % cargo_class)
		elif _has_fields(where, capacity, ["mass_kg", "volume_m3"]):
			_check_positive(where, "mass_kg", capacity["mass_kg"], 1000, MAX_STACK_G)
			_check_positive(where, "volume_m3", capacity["volume_m3"], 1000, MAX_STORE_L)


func _shape_fabrication(where: String, fabrication: Variant) -> void:
	if fabrication == null:
		return
	if not fabrication is Dictionary:
		_err("bad_fabrication", where, "fabrication is not an object or null")
	elif _has_fields(where, fabrication, ["recipe"]) and not fabrication["recipe"] is String:
		_err("bad_fabrication", where, "recipe is not a string")


func _shape_collision(where: String, collision: Variant) -> void:
	if not collision is Dictionary:
		_err("bad_collision", where, "collision is not an object")
		return
	if not _has_fields(where, collision, COLLISION_FIELDS):
		return
	_check_enum(where, "shape", collision["shape"], SHAPES)
	_check_vector(where, "center_mm", collision["center_mm"], -INF)
	_check_vector(where, "size_mm", collision["size_mm"], 1.0)
	if collision["shape"] == "cylinder" and collision["size_mm"] is Array:
		if collision["size_mm"].size() == 3 and collision["size_mm"][0] != collision["size_mm"][2]:
			_err("bad_collision", where, "cylinder z must equal x")


func _shape_connector(where: String, connector: Dictionary) -> void:
	var at := "%s.%s" % [where, str(connector.get("id"))]
	if not _has_fields(at, connector, CONNECTOR_FIELDS):
		return
	if not connector["id"] is String or _id_regex.search(connector["id"]) == null:
		_err("bad_id", at, "connector id")
	_check_enum(at, "type", connector["type"], CONNECTOR_TYPES)
	_check_enum(at, "size", connector["size"], CONNECTOR_SIZES)
	_check_vector(at, "pos_mm", connector["pos_mm"], -INF)
	_check_enum(at, "facing", connector["facing"], AXES)
	_check_enum(at, "up", connector["up"], AXES)
	_check_positive(at, "load_limit_kg", connector["load_limit_kg"], 1000, MAX_STACK_G)
	if str(connector["facing"]).right(1) == str(connector["up"]).right(1):
		_err("bad_connector_axes", at, "up is not at right angles to facing")
	if connector["size"] == "core" and connector["type"] != "side":
		_err("bad_core_connector", at, "core connectors are type side")


func _shape_recipe(recipe: Dictionary) -> void:
	var where := "recipes.json:%s" % recipe["id"]
	if not _has_fields(where, recipe, RECIPE_FIELDS):
		return
	_check_enum(where, "facility", recipe["facility"], FACILITIES)
	_check_whole(where, "seconds", recipe["seconds"], 1, MAX_RATE)
	_check_number(where, "power_kw", recipe["power_kw"], 1000, MAX_RATE)
	if not recipe["abstract"] is bool:
		_err("bad_recipe", where, "abstract is not a boolean")
	if not recipe["inputs"] is Array or recipe["inputs"].is_empty():
		_err("bad_recipe", where, "inputs needs at least one entry")
	else:
		for entry: Variant in recipe["inputs"]:
			_shape_amount(where, entry, [])
	if not recipe["outputs"] is Array or recipe["outputs"].is_empty():
		_err("bad_recipe", where, "outputs needs at least one entry")
	else:
		for entry: Variant in recipe["outputs"]:
			if entry is Dictionary and entry.has("unit_template"):
				_has_fields(where, entry, ["unit_template"])
			else:
				_shape_amount(where, entry, ["sink"])


## An item entry with exactly one of `kg` and `count`.
func _shape_amount(where: String, entry: Variant, optional: Array) -> void:
	if not entry is Dictionary or not entry.get("item") is String:
		_err("bad_recipe", where, "entry needs an item")
		return
	if entry.has("kg") == entry.has("count"):
		_err("bad_amount", where, "%s needs exactly one of kg and count" % entry["item"])
		return
	var amount_field := "kg" if entry.has("kg") else "count"
	if not _has_fields(where, entry, ["item", amount_field], optional):
		return
	if entry.has("kg"):
		_check_positive(where, "kg", entry["kg"], 1000, MAX_STACK_G)
	else:
		_check_whole(where, "count", entry["count"], 1, MAX_RATE)
	if entry.has("sink") and not entry["sink"] is String:
		_err("bad_recipe", where, "sink is not a string")


func _shape_deposit(deposit: Dictionary) -> void:
	var where := "deposits.json:%s" % deposit["id"]
	if not _has_fields(where, deposit, DEPOSIT_FIELDS):
		return
	if not deposit["item"] is String:
		_err("bad_deposit", where, "item is not a string")
	_check_positive(where, "mass_kg", deposit["mass_kg"], 1000, MAX_STACK_G)
	_check_whole(where, "hardness", deposit["hardness"], 1, 10)


func _shape_template(template: Dictionary) -> void:
	var where := "templates.json:%s" % template["id"]
	if not _has_fields(where, template, TEMPLATE_FIELDS):
		return
	_check_name(where, template)
	_check_enum(where, "kind", template["kind"], UNIT_KINDS)
	if not template["root"] is Dictionary:
		_err("bad_node", where, "root is not an object")
	else:
		_shape_node(where, template["root"], true)


func _shape_node(where: String, node: Dictionary, is_root: bool) -> void:
	var fields := ["part", "children"]
	if not is_root:
		fields.append_array(["parent_connector", "connector"])
	if not _has_fields(where, node, fields):
		return
	if not node["part"] is String or not node["children"] is Array:
		_err("bad_node", where, "part or children has the wrong type")
		return
	for child: Variant in node["children"]:
		if child is Dictionary:
			_shape_node(where, child, false)
		else:
			_err("bad_node", where, "child is not an object")


func _shape_sink(sink: Dictionary) -> void:
	var where := "sinks.json:%s" % sink["id"]
	if not _has_fields(where, sink, SINK_FIELDS):
		return
	_check_name(where, sink)
	if not sink["items"] is Array or sink["items"].is_empty():
		_err("bad_sink", where, "items needs at least one entry")


## Adds the item each module has while uninstalled (schemas section 3).
func _derive_module_items() -> void:
	for id: String in _sorted(_modules):
		var where := "modules.json:%s" % id
		if _items.has(id):
			_err("module_item_authored", where, "items.json has an entry with this ID")
			continue
		var module: Dictionary = _modules[id]
		var mass_g := _to_sim(module["mass_kg"], 1000)
		var volume_l := _to_sim(module["volume_m3"], 1000)
		if mass_g % volume_l != 0:
			_err("density_not_whole", where, "mass_kg / volume_m3 is not a whole number")
		_items[id] = {
			"id": id, "stage": 5, "cargo_class": "goods",
			"density_kg_m3": mass_g / volume_l, "unit_mass_kg": module["mass_kg"],
		}


func _cross_sink(sink: Dictionary) -> void:
	for item: Variant in sink["items"]:
		if not _items.has(item):
			_err("unknown_item", "sinks.json:%s" % sink["id"], str(item))


func _cross_module(module: Dictionary) -> void:
	var where := "modules.json:%s" % module["id"]
	var capabilities: Dictionary = module["capabilities"]
	var is_root: bool = capabilities.has("max_mass_kg")
	if module["min_ai_tier"] != 1:
		_err("slice_min_ai_tier", where, "slice parts declare 1")
	if is_root and module["fabrication"] != null:
		_err("root_fabricated", where, "root parts have null fabrication")
	if not is_root and module["fabrication"] == null:
		_err("fabrication_missing", where, "only root parts have null fabrication")
	if module["fabrication"] != null:
		_cross_fabrication(where, module)
	_cross_connectors(where, module, is_root)


func _cross_fabrication(where: String, module: Dictionary) -> void:
	var recipe_id: String = module["fabrication"]["recipe"]
	if not _recipes.has(recipe_id):
		_err("unknown_recipe", where, recipe_id)
		return
	for output: Dictionary in _recipes[recipe_id]["outputs"]:
		if output.get("item") == module["id"]:
			return
	_err("fabrication_mismatch", where, "%s does not output this module" % recipe_id)


func _cross_connectors(where: String, module: Dictionary, is_root: bool) -> void:
	var is_core: bool = module["capabilities"].has("ai_core")
	var core_connectors := 0
	var dock_connectors := 0
	var has_mount := false
	for connector: Dictionary in module["connectors"]:
		if connector["size"] == "core":
			core_connectors += 1
		if connector["type"] == "dock":
			dock_connectors += 1
		if connector["id"] == "mount":
			has_mount = true
			if connector["pos_mm"].any(func(value: Variant) -> bool: return value != 0):
				_err("mount_not_at_origin", where, "mount must sit at [0, 0, 0]")
	if not is_root and not has_mount:
		_err("mount_missing", where, "non-root modules need a mount connector")
	if is_root and core_connectors == 0:
		_err("root_without_core_connector", where)
	if is_root and core_connectors > 1:
		_err("core_connector_misplaced", where, "a root has one core connector")
	if not is_root and not is_core and core_connectors > 0:
		_err("core_connector_misplaced", where, "only cores and root parts have one")
	if is_core and (module["connectors"].size() != 1 or core_connectors != 1):
		_err("bad_core_connector", where, "a core has one side connector of size core")
	if dock_connectors > 1:
		_err("too_many_dock_connectors", where)
	if (dock_connectors == 1) != module["capabilities"].has("port"):
		_err("port_mismatch", where, "dock connector and port capability go together")


func _cross_recipe(recipe: Dictionary) -> void:
	var where := "recipes.json:%s" % recipe["id"]
	if recipe["abstract"] != true:
		_err("recipe_not_abstract", where, "every slice recipe is abstract")
	_check_recipe_facility(where, recipe)

	var input_g := 0
	var seen := {}
	for entry: Dictionary in recipe["inputs"]:
		input_g += _entry_grams(where, entry)
		if seen.has(entry["item"]):
			_err("repeated_item", where, entry["item"])
		seen[entry["item"]] = true

	var output_g := 0
	seen = {}
	var has_sink_output := false
	for entry: Dictionary in recipe["outputs"]:
		if entry.has("unit_template"):
			output_g += _cross_unit_output(where, recipe, entry)
			continue
		output_g += _entry_grams(where, entry)
		if seen.has(entry["item"]):
			_err("repeated_item", where, entry["item"])
		seen[entry["item"]] = true
		has_sink_output = has_sink_output or entry.has("sink")
		_check_sink_route(where, entry)

	if input_g != output_g:
		_err("recipe_unbalanced", where, "%d g in, %d g out" % [input_g, output_g])
	if recipe["facility"] == "refinery" and not has_sink_output:
		_err("slag_missing", where, "a refining recipe routes slag to a sink")
	_check_yields(where, recipe)


func _check_recipe_facility(where: String, recipe: Dictionary) -> void:
	var found := false
	for id: String in _sorted(_modules):
		var capabilities: Dictionary = _modules[id]["capabilities"]
		if capabilities.get("facility", {}).get("type") != recipe["facility"]:
			continue
		found = true
		if float(recipe["power_kw"]) > float(_modules[id]["power_kw"]):
			_err("recipe_over_power", where, "above the rating of %s" % id)
	if not found:
		_err("unknown_facility", where, "no module has type %s" % recipe["facility"])


## Grams of a recipe entry. Discrete items use `count`, continuous items use `kg`.
func _entry_grams(where: String, entry: Dictionary) -> int:
	var id: String = entry["item"]
	if not _items.has(id):
		_err("unknown_item", where, id)
		return 0
	var item: Dictionary = _items[id]
	var is_discrete: bool = item.has("unit_mass_kg")
	if is_discrete != entry.has("count"):
		_err("wrong_amount_form", where, "%s uses %s" % [id, "count" if is_discrete else "kg"])
		return 0
	if is_discrete:
		return _to_sim(item["unit_mass_kg"], 1000) * int(entry["count"])
	return _to_sim(entry["kg"], 1000)


func _cross_unit_output(where: String, recipe: Dictionary, entry: Dictionary) -> int:
	if recipe["outputs"].size() != 1:
		_err("unit_output_not_alone", where, "a unit output is the only output")
	var id: Variant = entry["unit_template"]
	if not _templates.has(id):
		_err("unknown_template", where, str(id))
		return 0
	return _node_mass(_templates[id]["root"])


func _node_mass(node: Dictionary) -> int:
	var total := 0
	if _modules.has(node["part"]):
		total = _to_sim(_modules[node["part"]]["mass_kg"], 1000)
	for child: Dictionary in node["children"]:
		total += _node_mass(child)
	return total


func _check_sink_route(where: String, entry: Dictionary) -> void:
	var id: String = entry["item"]
	if entry.has("sink"):
		if not _sinks.has(entry["sink"]):
			_err("unknown_sink", where, entry["sink"])
		elif not id in _sinks[entry["sink"]]["items"]:
			_err("sink_refuses_item", where, "%s does not accept %s" % [entry["sink"], id])
		return
	for sink_id: String in _sorted(_sinks):
		if id in _sinks[sink_id]["items"]:
			_err("sink_route_missing", where, "%s must route to a sink" % id)


func _check_yields(where: String, recipe: Dictionary) -> void:
	for input: Dictionary in recipe["inputs"]:
		if not YIELD_CEILINGS_PPM.has(input["item"]) or not input.has("kg"):
			continue
		var ceilings: Dictionary = YIELD_CEILINGS_PPM[input["item"]]
		var input_g := _to_sim(input["kg"], 1000)
		for output: Dictionary in recipe["outputs"]:
			if not ceilings.has(output.get("item")) or not output.has("kg"):
				continue
			var ceiling_g := IntMath.mul_div(input_g, ceilings[output["item"]], PPM)
			if _to_sim(output["kg"], 1000) > ceiling_g:
				_err("yield_over_ceiling", where, output["item"])


func _cross_deposit(deposit: Dictionary) -> void:
	var where := "deposits.json:%s" % deposit["id"]
	if not _items.has(deposit["item"]):
		_err("unknown_item", where, str(deposit["item"]))
		return
	if _items[deposit["item"]]["cargo_class"] != "ore":
		_err("bad_deposit", where, "a deposit yields an ore item")
	for id: String in _sorted(_modules):
		var mine: Variant = _modules[id]["capabilities"].get("mine")
		if mine != null and float(deposit["hardness"]) <= float(mine["hardness_max"]):
			return
	_err("deposit_too_hard", where, "no laser reaches hardness %s" % str(deposit["hardness"]))


func _cross_template(template: Dictionary) -> void:
	var where := "templates.json:%s" % template["id"]
	var root_id: String = template["root"]["part"]
	if not _modules.has(root_id):
		_err("unknown_module", where, root_id)
		return
	if not _modules[root_id]["capabilities"].has("max_mass_kg"):
		_err("root_not_a_root_part", where, root_id)
		return
	var parts: Array[Dictionary] = []
	var mass_g := _walk_node(where, template["root"], parts)
	if parts.is_empty():
		return
	_check_fit(where, template, parts, mass_g)


## Checks a node's joins, collects its modules and returns the subtree's mass.
func _walk_node(where: String, node: Dictionary, parts: Array[Dictionary]) -> int:
	if not _modules.has(node["part"]):
		_err("unknown_module", where, node["part"])
		return 0
	var module: Dictionary = _modules[node["part"]]
	parts.append(module)
	var mass_g := _to_sim(module["mass_kg"], 1000)
	var occupied := {}
	for child: Dictionary in node["children"]:
		var below_g := _walk_node(where, child, parts)
		mass_g += below_g
		if not _modules.has(child["part"]):
			continue
		if _modules[child["part"]]["capabilities"].has("max_mass_kg"):
			_err("root_part_as_child", where, child["part"])
		if child["connector"] != "mount":
			_err("not_through_mount", where, child["part"])
		var parent_end := _connector(module, child["parent_connector"])
		var child_end := _connector(_modules[child["part"]], child["connector"])
		if parent_end.is_empty() or child_end.is_empty():
			_err("unknown_connector", where, "%s to %s" % [
				child["parent_connector"], child["connector"]])
			continue
		_check_join(where, parent_end, child_end, below_g)
		if occupied.has(parent_end["id"]):
			_err("connector_occupied", where, parent_end["id"])
		occupied[parent_end["id"]] = true
	return mass_g


func _connector(module: Dictionary, id: Variant) -> Dictionary:
	for connector: Dictionary in module["connectors"]:
		if connector["id"] == id:
			return connector
	return {}


func _check_join(where: String, parent: Dictionary, child: Dictionary, below_g: int) -> void:
	if parent["type"] != child["type"]:
		_err("connector_type_mismatch", where, parent["id"])
	if parent["size"] != child["size"]:
		_err("connector_size_mismatch", where, parent["id"])
	if parent["type"] == "dock":
		_err("dock_connector_in_tree", where, parent["id"])
	if below_g > _to_sim(parent["load_limit_kg"], 1000):
		_err("over_load_limit", where, parent["id"])


## The fitting rules of contracts section 5, applied to a whole template.
func _check_fit(where: String, template: Dictionary, parts: Array[Dictionary], mass_g: int) -> void:
	var power_w := 0
	var heat_w := 0
	var budget_w := 0
	var reject_w := 0
	var cores := 0
	for module: Dictionary in parts:
		var capabilities: Dictionary = module["capabilities"]
		power_w += _to_sim(module["power_kw"], 1000)
		heat_w += _to_sim(module["heat_kw"], 1000)
		if capabilities.has("generate"):
			budget_w += _to_sim(capabilities["generate"]["power_kw"], 1000)
		if capabilities.has("battery"):
			budget_w += _to_sim(capabilities["battery"]["max_discharge_kw"], 1000)
		if capabilities.has("radiator"):
			reject_w += _to_sim(capabilities["radiator"]["reject_kw"], 1000)
		if capabilities.has("ai_core"):
			cores += 1
	var root_capabilities: Dictionary = parts[0]["capabilities"]
	if mass_g > _to_sim(root_capabilities["max_mass_kg"], 1000):
		_err("over_mass_limit", where, "%d g" % mass_g)
	if power_w > budget_w:
		_err("over_power_budget", where, "need %d W, have %d W" % [power_w, budget_w])
	if heat_w > reject_w:
		_err("over_heat_budget", where, "need %d W, have %d W" % [heat_w, reject_w])
	if cores > 1:
		_err("too_many_cores", where, "a template holds at most one")
	if heat_w > 0 and not _any_part_has(parts, "heat_capacity"):
		_err("heat_capacity_missing", where, "units that make heat need a limit")
	if _any_part_has(parts, "thruster") and not _stores_propellant(parts):
		_err("propellant_storage_missing", where, template["id"])


func _any_part_has(parts: Array[Dictionary], capability: String) -> bool:
	return parts.any(func(module: Dictionary) -> bool:
		return module["capabilities"].has(capability))


func _stores_propellant(parts: Array[Dictionary]) -> bool:
	return parts.any(func(module: Dictionary) -> bool:
		return module["capabilities"].get("storage", {}).has("propellant"))


func _check_position(where: String, value: Variant) -> void:
	_check_vector(where, "pos_mm", value, -INF)
	if value is Array and value.any(func(axis: Variant) -> bool:
			return _is_number(axis) and absf(float(axis)) > MAX_JSON_WHOLE):
		_err("out_of_range", where, "pos_mm is too large for JSON to keep exactly")


func _shape_scenario(scenario: Variant) -> void:
	if not scenario is Dictionary or not scenario.get("id") is String:
		_err("bad_scenario", "data/scenarios", "missing, unparsable or has no id")
		return
	var where := "scenarios/%s" % scenario["id"]
	if not _has_fields(where, scenario, SCENARIO_FIELDS):
		return
	if scenario["schema_version"] != SCHEMA_VERSION:
		_err("bad_schema_version", where, str(scenario["schema_version"]))
	_check_name(where, scenario)
	_check_whole(where, "seed", scenario["seed"], 0, MAX_JSON_WHOLE)
	if not scenario["bodies"] is Array or not scenario["units"] is Array:
		_err("bad_scenario", where, "bodies and units are arrays")
		return
	var keys := {}
	for body: Variant in scenario["bodies"]:
		_shape_body(where, body, keys)
	for unit: Variant in scenario["units"]:
		_shape_scenario_unit(where, unit, keys)


func _claim_key(where: String, entry: Dictionary, keys: Dictionary) -> void:
	if not entry.get("key") is String or _id_regex.search(entry["key"]) == null:
		_err("bad_id", where, "key %s" % str(entry.get("key")))
	elif keys.has(entry["key"]):
		_err("duplicate_id", where, entry["key"])
	else:
		keys[entry["key"]] = true


func _shape_body(where: String, body: Variant, keys: Dictionary) -> void:
	if not body is Dictionary:
		_err("bad_scenario", where, "body is not an object")
		return
	if not _has_fields(where, body, BODY_FIELDS):
		return
	_claim_key(where, body, keys)
	_check_name(where, body)
	_check_enum(where, "kind", body["kind"], BODY_KINDS)
	_check_position(where, body["pos_mm"])
	_check_whole(where, "radius_mm", body["radius_mm"], 1, MAX_JSON_WHOLE)
	_check_whole(where, "visual_seed", body["visual_seed"], 0, MAX_JSON_WHOLE)
	if not body["deposits"] is Array:
		_err("bad_scenario", where, "deposits is not an array")


func _shape_scenario_unit(where: String, unit: Variant, keys: Dictionary) -> void:
	if not unit is Dictionary:
		_err("bad_scenario", where, "unit is not an object")
		return
	if not _has_fields(where, unit, UNIT_FIELDS):
		return
	_claim_key(where, unit, keys)
	_check_name(where, unit)
	_check_position(where, unit["pos_mm"])
	if not unit["inventory"] is Array:
		_err("bad_scenario", where, "inventory is not an array")
	else:
		for entry: Variant in unit["inventory"]:
			_shape_amount(where, entry, [])
	if unit["dock"] != null:
		if not unit["dock"] is Dictionary:
			_err("bad_scenario", where, "dock is not an object or null")
		elif _has_fields(where, unit["dock"], DOCK_FIELDS):
			_check_whole(where, "port", unit["dock"]["port"], 0, MAX_RATE)
			_check_whole(where, "host_port", unit["dock"]["host_port"], 0, MAX_RATE)


func _cross_scenario(scenario: Dictionary) -> void:
	var where := "scenarios/%s" % scenario["id"]
	for body: Dictionary in scenario["bodies"]:
		if body["kind"] == "star" and not body["deposits"].is_empty():
			_err("star_with_deposits", where, body["key"])
		for id: Variant in body["deposits"]:
			if not _deposits.has(id):
				_err("unknown_deposit", where, str(id))
	var units := {}
	for unit: Dictionary in scenario["units"]:
		units[unit["key"]] = unit
	var used_ports := {}
	for unit: Dictionary in scenario["units"]:
		var at := "%s.%s" % [where, unit["key"]]
		if not _templates.has(unit["template"]):
			_err("unknown_template", at, str(unit["template"]))
			continue
		var parts: Array[Dictionary] = []
		_walk_node(at, _templates[unit["template"]]["root"], parts)
		_check_inventory(at, unit, parts)
		if unit["dock"] != null:
			_check_start_dock(at, unit, parts, units, used_ports)


## Starting stock must fit the unit's own storage, by mass and volume per cargo class.
func _check_inventory(where: String, unit: Dictionary, parts: Array[Dictionary]) -> void:
	var used_g := {}
	var used_l := {}
	var seen := {}
	for entry: Dictionary in unit["inventory"]:
		if seen.has(entry["item"]):
			_err("repeated_item", where, entry["item"])
		seen[entry["item"]] = true
		var grams := _entry_grams(where, entry)
		if not _items.has(entry["item"]):
			continue
		var item: Dictionary = _items[entry["item"]]
		var cargo_class: String = item["cargo_class"]
		var density: int = _to_sim(item["density_kg_m3"], 1)
		used_g[cargo_class] = used_g.get(cargo_class, 0) + grams
		used_l[cargo_class] = used_l.get(cargo_class, 0) + ceili(float(grams) / density)
	for cargo_class: String in _sorted(used_g):
		var cap_g := 0
		var cap_l := 0
		for module: Dictionary in parts:
			var capacity: Variant = module["capabilities"].get("storage", {}).get(cargo_class)
			if capacity != null:
				cap_g += _to_sim(capacity["mass_kg"], 1000)
				cap_l += _to_sim(capacity["volume_m3"], 1000)
		if used_g[cargo_class] > cap_g or used_l[cargo_class] > cap_l:
			_err("start_stock_too_large", where, cargo_class)


func _port_count(parts: Array[Dictionary]) -> int:
	return parts.filter(func(module: Dictionary) -> bool:
		return module["capabilities"].has("port")).size()


func _check_start_dock(
		where: String, unit: Dictionary, parts: Array[Dictionary], units: Dictionary,
		used_ports: Dictionary) -> void:
	var dock: Dictionary = unit["dock"]
	if not units.has(dock["host"]) or not _templates.has(units[dock["host"]]["template"]):
		_err("bad_start_dock", where, "unknown host %s" % str(dock["host"]))
		return
	var host: Dictionary = units[dock["host"]]
	var host_parts: Array[Dictionary] = []
	_walk_node(where, _templates[host["template"]]["root"], host_parts)
	if dock["port"] >= _port_count(parts) or dock["host_port"] >= _port_count(host_parts):
		_err("bad_start_dock", where, "port index is out of range")
	if unit["pos_mm"] != host["pos_mm"]:
		_err("bad_start_dock", where, "a docked unit takes its host's position")
	var port_key := "%s:%d" % [dock["host"], int(dock["host_port"])]
	if used_ports.has(port_key):
		_err("bad_start_dock", where, "host port is already taken")
	used_ports[port_key] = true


## Every item has a source and a use (schemas section 12).
func _check_coverage() -> void:
	var sources := {}
	var uses := {}
	for scenario: Dictionary in _scenarios:
		for unit: Dictionary in scenario["units"]:
			for entry: Dictionary in unit["inventory"]:
				sources[entry["item"]] = true
	for id: String in _sorted(_deposits):
		sources[_deposits[id]["item"]] = true
	for id: String in _sorted(_sinks):
		for item: Variant in _sinks[id]["items"]:
			uses[item] = true
	for id: String in _sorted(_recipes):
		for entry: Dictionary in _recipes[id]["inputs"]:
			uses[entry["item"]] = true
		for entry: Dictionary in _recipes[id]["outputs"]:
			if entry.has("item"):
				sources[entry["item"]] = true
	for id: String in _sorted(_templates):
		_mark_template_parts(_templates[id]["root"], sources, uses)
	for id: String in _sorted(_items):
		var where := "items.json:%s" % id
		var fits := _modules.has(id) and _fits_somewhere(_modules[id])
		if not sources.has(id):
			_err("item_without_source", where)
		if not uses.has(id) and not fits:
			_err("item_without_use", where)


func _mark_template_parts(node: Dictionary, sources: Dictionary, uses: Dictionary) -> void:
	sources[node["part"]] = true
	uses[node["part"]] = true
	for child: Dictionary in node["children"]:
		_mark_template_parts(child, sources, uses)


## A module is usable if another module has a free connector its mount can join.
func _fits_somewhere(module: Dictionary) -> bool:
	var mount := _connector(module, "mount")
	if mount.is_empty():
		return false
	for id: String in _sorted(_modules):
		if id == module["id"]:
			continue
		for connector: Dictionary in _modules[id]["connectors"]:
			if connector["id"] == "mount":
				continue
			if connector["type"] == mount["type"] and connector["size"] == mount["size"]:
				return true
	return false
