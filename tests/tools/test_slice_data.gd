extends GutTest

## Checks the authored slice in data/ against spec section 7.

const ITEMS := [
	"chalcopyrite", "copper", "hematite", "iron", "olivine", "processor", "propellant",
	"silicon", "slag", "structural_frame", "water_ice", "wiring",
]
const MODULES := [
	"assisted_core", "basic_core", "battery_bank_mk1", "chemical_thruster_mk1", "command_hub",
	"docking_port_mk1", "fabricator_mk1", "goods_container_mk1", "goods_storage_mk1",
	"heat_radiator_mk1", "landing_legs_mk1", "lidar_mk1", "mining_laser_mk1", "ore_container_mk1",
	"ore_refinery_mk1", "ore_storage_mk1", "propellant_tank_mk1", "research_lab_mk1", "small_battery_bank_mk1",
	"small_chemical_thruster_mk1", "small_docking_port_mk1", "small_heat_radiator_mk1", "small_hub",
	"small_hull", "small_landing_legs_mk1", "small_mining_laser_mk1", "small_ore_container_mk1",
	"small_propellant_tank_mk1", "small_solar_panel_mk1", "solar_farm_mk1", "solar_panel_mk1",
	"starter_hull",
]
const DEPOSIT_ITEMS := ["chalcopyrite", "hematite", "olivine", "water_ice"]
const TEMPLATES := [
	"large_station", "medium_craft", "probe", "small_craft", "small_station", "starter_ship",
	"starter_station",
]
## Everything a working drone adds to a small craft.
const DRONE_MODULES := [
	"small_chemical_thruster_mk1", "small_heat_radiator_mk1", "small_mining_laser_mk1",
	"small_ore_container_mk1", "small_propellant_tank_mk1", "small_solar_panel_mk1",
]
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
		for id: String in ["mining_laser_mk1", "small_mining_laser_mk1"]:
			assert_lte(entry["hardness"], _module(id)["capabilities"]["mine"]["hardness_max"])


func test_starting_ship_and_station_have_a_basic_core_and_a_small_craft_has_none() -> void:
	var has_core := func(parts: Array) -> bool:
		return parts.any(func(part: Dictionary) -> bool: return part["id"] == "basic_core")
	assert_true(has_core.call(_template_parts(_template("starter_ship")["root"])))
	assert_true(has_core.call(_template_parts(_template("starter_station")["root"])))
	assert_false(has_core.call(_template_parts(_template("small_craft")["root"])))


func test_either_core_fits_the_drone_without_failing_a_budget() -> void:
	for id: String in ["basic_core", "assisted_core"]:
		var parts := _drone_parts()
		parts.append(_module(id))
		assert_lte(_sum(parts, func(p: Dictionary) -> float: return p["power_kw"]),
			_sum(parts, _power_budget))
		assert_lte(_sum(parts, func(p: Dictionary) -> float: return p["heat_kw"]),
			_sum(parts, _heat_budget))


## The drone's figures stay the sum of its parts, which keeps the lap figures in
## docs/design/reference_scenario.md.
func test_a_drone_keeps_its_mass_and_build_cost_across_its_parts() -> void:
	var parts := _drone_parts()
	assert_eq(_sum(parts, func(p: Dictionary) -> float: return p["mass_kg"]), 520)
	var used := {}
	var seconds := 0
	var recipes := ["small_craft"]
	recipes.append_array(DRONE_MODULES)
	for id: String in recipes:
		var recipe: Dictionary = _entry_of("recipes", id)
		seconds += int(recipe["seconds"])
		for input: Dictionary in recipe["inputs"]:
			used[input["item"]] = used.get(input["item"], 0) + int(input["count"])
	assert_eq(used, { "structural_frame": 8, "wiring": 10, "processor": 4 })
	assert_eq(seconds, 300)


func test_small_parts_never_beat_medium_on_capacity_per_kg() -> void:
	var pairs := {
		"small_solar_panel_mk1": ["solar_panel_mk1", _generated],
		"small_heat_radiator_mk1": ["heat_radiator_mk1", _rejected],
		"small_ore_container_mk1": ["ore_container_mk1", _stored.bind("ore")],
		"small_propellant_tank_mk1": ["propellant_tank_mk1", _stored.bind("propellant")],
	}
	for small: String in pairs:
		var medium: String = pairs[small][0]
		var figure: Callable = pairs[small][1]
		assert_lte(figure.call(_module(small)) / float(_module(small)["mass_kg"]),
			figure.call(_module(medium)) / float(_module(medium)["mass_kg"]), small)


func _drone_parts() -> Array:
	var parts := _template_parts(_template("small_craft")["root"])
	for id: String in DRONE_MODULES:
		parts.append(_module(id))
	return parts


func _entry_of(file: String, id: String) -> Dictionary:
	for entry: Dictionary in data[file]["entries"]:
		if entry["id"] == id:
			return entry
	return {}


func _generated(module: Dictionary) -> float:
	return module["capabilities"]["generate"]["power_kw"]


func _rejected(module: Dictionary) -> float:
	return module["capabilities"]["radiator"]["reject_kw"]


func _stored(module: Dictionary, cargo_class: String) -> float:
	return module["capabilities"]["storage"][cargo_class]["mass_kg"]


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
