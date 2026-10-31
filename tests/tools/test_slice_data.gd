extends GutTest

## Checks the authored slice in data/ against spec section 7.

const ITEMS := [
	"chalcopyrite", "copper", "hematite", "iron", "olivine", "processor", "propellant",
	"silicon", "slag", "structural_frame", "wiring",
]
const MODULES := [
	"assisted_core", "basic_core", "battery_bank_mk1", "chemical_thruster_mk1", "command_hub",
	"docking_port_mk1", "fabricator_mk1", "goods_storage_mk1", "heat_radiator_mk1", "lidar_mk1",
	"mining_drone_body", "mining_laser_mk1", "ore_container_mk1", "ore_refinery_mk1",
	"ore_storage_mk1", "propellant_tank_mk1", "solar_farm_mk1", "solar_panel_mk1", "starter_hull",
]
const DEPOSIT_ITEMS := ["chalcopyrite", "hematite", "olivine"]
const TEMPLATES := ["mining_drone", "starter_ship", "starter_station"]
const PALETTE := ["#e8e4d8", "#8a8d91", "#e8641b", "#c9a227"]

var data: Dictionary


func before_all() -> void:
	data = DataValidator.load_dir()


func _ids(file: String) -> Array:
	return data[file]["entries"].map(func(entry: Dictionary) -> String: return entry["id"])


func _module(id: String) -> Dictionary:
	for entry: Dictionary in data["modules"]["entries"]:
		if entry["id"] == id:
			return entry
	return {}


func _template(id: String) -> Dictionary:
	for entry: Dictionary in data["templates"]["entries"]:
		if entry["id"] == id:
			return entry
	return {}


func _template_parts(node: Dictionary) -> Array:
	var parts: Array = [_module(node["part"])]
	for child: Dictionary in node["children"]:
		parts.append_array(_template_parts(child))
	return parts


func _sum(parts: Array, value: Callable) -> int:
	var total := 0.0
	for part: Dictionary in parts:
		total += float(value.call(part))
	return roundi(total)


func _power_budget(part: Dictionary) -> float:
	var capabilities: Dictionary = part["capabilities"]
	var total := 0.0
	if capabilities.has("generate"):
		total += capabilities["generate"]["power_kw"]
	if capabilities.has("battery"):
		total += capabilities["battery"]["max_discharge_kw"]
	return total


func _heat_budget(part: Dictionary) -> float:
	return part["capabilities"].get("radiator", {}).get("reject_kw", 0.0)


func test_data_passes_the_validator() -> void:
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_every_spec_id_exists_and_nothing_else() -> void:
	var items := _ids("items")
	var modules := _ids("modules")
	var templates := _ids("templates")
	items.sort()
	modules.sort()
	templates.sort()
	assert_eq(items, ITEMS)
	assert_eq(modules, MODULES)
	assert_eq(templates, TEMPLATES)


func test_deposits_are_the_three_slice_ores() -> void:
	var yielded: Array = data["deposits"]["entries"].map(
		func(entry: Dictionary) -> String: return entry["item"])
	yielded.sort()
	assert_eq(yielded, DEPOSIT_ITEMS)


func test_every_laser_reaches_every_deposit() -> void:
	for entry: Dictionary in data["deposits"]["entries"]:
		for id: String in ["mining_laser_mk1", "mining_drone_body"]:
			assert_lte(entry["hardness"], _module(id)["capabilities"]["mine"]["hardness_max"])


func test_starting_ship_and_station_have_a_basic_core_and_the_drone_has_none() -> void:
	var has_core := func(parts: Array) -> bool:
		return parts.any(func(part: Dictionary) -> bool: return part["id"] == "basic_core")
	assert_true(has_core.call(_template_parts(_template("starter_ship")["root"])))
	assert_true(has_core.call(_template_parts(_template("starter_station")["root"])))
	assert_false(has_core.call(_template_parts(_template("mining_drone")["root"])))


func test_either_core_fits_the_drone_without_failing_a_budget() -> void:
	var body := _module("mining_drone_body")
	for id: String in ["basic_core", "assisted_core"]:
		var parts := [body, _module(id)]
		assert_lte(_sum(parts, func(p: Dictionary) -> float: return p["power_kw"]),
			_sum(parts, _power_budget))
		assert_lte(_sum(parts, func(p: Dictionary) -> float: return p["heat_kw"]),
			_sum(parts, _heat_budget))


## Check 10: a second laser passes on power and mass, fails on heat, and one more
## radiator fixes it (spec section 7.5).
func test_first_upgrade_fails_on_heat_and_one_radiator_fixes_it() -> void:
	var parts := _template_parts(_template("starter_ship")["root"])
	parts.append(_module("mining_laser_mk1"))
	var power := _sum(parts, func(p: Dictionary) -> float: return p["power_kw"])
	var heat := _sum(parts, func(p: Dictionary) -> float: return p["heat_kw"])
	assert_lte(power, _sum(parts, _power_budget))
	assert_gt(heat, _sum(parts, _heat_budget))
	parts.append(_module("heat_radiator_mk1"))
	assert_lte(heat, _sum(parts, _heat_budget))
	var mass := _sum(parts, func(p: Dictionary) -> float: return p["mass_kg"])
	assert_lte(mass, _module("starter_hull")["capabilities"]["max_mass_kg"])


func test_ship_has_free_side_connectors_for_the_upgrade_and_radiator() -> void:
	var used: Array = _template("starter_ship")["root"]["children"].map(
		func(child: Dictionary) -> String: return child["parent_connector"])
	var free: Array = _module("starter_hull")["connectors"].filter(
		func(connector: Dictionary) -> bool:
			return connector["type"] == "side" and connector["size"] == "medium" \
				and not connector["id"] in used)
	assert_gte(free.size(), 2)


func test_every_tint_is_from_the_slice_palette() -> void:
	for entry: Dictionary in data["modules"]["entries"]:
		assert_has(PALETTE, entry["visual"]["tint"], entry["id"])


func test_refining_fills_no_storage() -> void:
	for entry: Dictionary in data["recipes"]["entries"]:
		for output: Dictionary in entry["outputs"]:
			if output.get("item") == "slag":
				assert_eq(output.get("sink"), "slag_vent")
