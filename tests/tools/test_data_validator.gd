extends GutTest

var data: Dictionary


func _envelope(entries: Array) -> Dictionary:
	return { "schema_version": 1, "entries": entries }


func _connector(id: String, type: String, size: String, pos: Array = [0, 0, 0]) -> Dictionary:
	return {
		"id": id, "type": type, "size": size, "pos_mm": pos,
		"facing": "+x", "up": "+y", "load_limit_kg": 1000,
	}


func _module(id: String, mass: float, capabilities: Dictionary, connectors: Array) -> Dictionary:
	return {
		"id": id, "name": id, "mass_kg": mass, "volume_m3": 1, "power_kw": 1, "heat_kw": 1,
		"priority": 1, "durability": 100, "min_ai_tier": 1, "realism": "established",
		"capabilities": capabilities,
		"fabrication": { "recipe": id },
		"connectors": connectors,
		"collision": { "shape": "box", "center_mm": [0, 0, 0], "size_mm": [10, 10, 10] },
		"visual": { "model": null, "tint": "#8a8d91" },
	}


func _hull() -> Dictionary:
	var hull := _module("hull", 100, {
		"max_mass_kg": 1000,
		"generate": { "power_kw": 100 },
		"radiator": { "reject_kw": 100 },
		"heat_capacity": { "limit_kj": 100 },
		"storage": { "ore": { "mass_kg": 100, "volume_m3": 1 } },
	}, [
		_connector("core", "side", "core"),
		_connector("side_a", "side", "medium", [1, 0, 0]),
		_connector("side_b", "side", "medium", [-1, 0, 0]),
	])
	hull["fabrication"] = null
	return hull


## The smallest dataset that passes. Each test breaks one thing in it.
func before_each() -> void:
	data = {
		"items": _envelope([
			{ "id": "frame", "name": "Frame", "stage": 5, "cargo_class": "goods",
				"density_kg_m3": 2000, "unit_mass_kg": 10 },
			{ "id": "hematite", "name": "Hematite", "stage": 2, "cargo_class": "ore",
				"density_kg_m3": 5000 },
			{ "id": "iron", "name": "Iron", "stage": 3, "cargo_class": "goods",
				"density_kg_m3": 7000 },
			{ "id": "propellant", "name": "Propellant", "stage": 3,
				"cargo_class": "propellant", "density_kg_m3": 1000 },
			{ "id": "slag", "name": "Slag", "stage": 3, "cargo_class": "ore",
				"density_kg_m3": 2000 },
		]),
		"modules": _envelope([
			_module("core", 10, { "ai_core": { "tier": 1 } }, [_connector("mount", "side", "core")]),
			_module("fabricator", 10, { "facility": { "type": "fabricator", "throughput_kg_per_s": 1, "work_per_tick": 100 } },
				[_connector("mount", "side", "medium")]),
			_hull(),
			_module("laser", 20, { "mine": { "rate_kg_per_s": 1, "hardness_max": 6 } },
				[_connector("mount", "side", "medium")]),
			_module("refinery", 10, { "facility": { "type": "refinery", "throughput_kg_per_s": 1, "work_per_tick": 100 } },
				[_connector("mount", "side", "medium")]),
		]),
		"recipes": _envelope([
			_fabrication("core", 1, "core"),
			_fabrication("fabricator", 1, "fabricator"),
			{ "id": "frame", "facility": "fabricator", "energy_kj": 5000, "heat_kj": 5000, "work": 5000, "power_kw": 1,
				"inputs": [{ "item": "iron", "kg": 10 }],
				"outputs": [{ "item": "frame", "count": 1 }], "abstract": true },
			_fabrication("laser", 2, "laser"),
			{ "id": "refine", "facility": "refinery", "energy_kj": 5000, "heat_kj": 5000, "work": 5000, "power_kw": 1,
				"inputs": [{ "item": "hematite", "kg": 100 }],
				"outputs": [{ "item": "iron", "kg": 60 },
					{ "item": "slag", "kg": 40, "sink": "slag_vent" }],
				"abstract": true },
			_fabrication("refinery", 1, "refinery"),
			{ "id": "tanker", "facility": "fabricator", "energy_kj": 5000, "heat_kj": 5000, "work": 5000, "power_kw": 1,
				"inputs": [{ "item": "frame", "count": 10 }],
				"outputs": [{ "unit_template": "tanker" }], "abstract": true },
		]),
		"deposits": _envelope([
			{ "id": "hematite_small", "item": "hematite", "mass_kg": 1000, "hardness": 5 },
		]),
		"templates": _envelope([
			{ "id": "ship", "name": "Ship", "kind": "ship", "root": { "part": "hull", "children": [
				{ "part": "core", "parent_connector": "core", "connector": "mount", "children": [] },
				{ "part": "laser", "parent_connector": "side_a", "connector": "mount", "children": [] },
			] } },
		]),
		"sinks": _envelope([
			{ "id": "propellant_exhaust", "name": "Exhaust", "items": ["propellant"] },
			{ "id": "slag_vent", "name": "Slag Vent", "items": ["slag"] },
		]),
		"scenarios": [{
			"schema_version": 1, "id": "test", "name": "Test", "seed": 7,
			"bodies": [
				{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0],
					"radius_mm": 10, "visual_seed": 1, "deposits": [] },
				{ "key": "rock", "name": "Rock", "kind": "asteroid", "pos_mm": [9, 0, 0],
					"radius_mm": 10, "visual_seed": 2, "deposits": ["hematite_small"] },
			],
			"units": [
				{ "key": "ship", "template": "ship", "name": "Ship", "pos_mm": [0, 0, 0],
					"inventory": [{ "item": "hematite", "kg": 50 }], "dock": null },
				{ "key": "stock", "template": "tanker", "name": "Tanker", "pos_mm": [0, 0, 0],
					"inventory": [{ "item": "propellant", "kg": 500 }], "dock": null },
			],
		}],
	}
	var hull := _entry("modules", "hull")
	hull["capabilities"]["storage"]["propellant"] = { "mass_kg": 500, "volume_m3": 1 }
	hull["capabilities"]["port"] = {
		"transfer_kg_per_s": 1, "dock_seconds": 1, "undock_seconds": 1, "capture_range_mm": 100,
		"capture_speed_m_s": 0.1,
	}
	hull["connectors"].append(_connector("dock", "dock", "medium", [0, 9, 0]))
	data["templates"]["entries"].append({ "id": "tanker", "name": "Tanker", "kind": "ship",
		"root": { "part": "hull", "children": [] } })


func _fabrication(id: String, frames: int, output: String) -> Dictionary:
	return {
		"id": id, "facility": "fabricator", "energy_kj": 5000, "heat_kj": 5000, "work": 5000, "power_kw": 1,
		"inputs": [{ "item": "frame", "count": frames }],
		"outputs": [{ "item": output, "count": 1 }], "abstract": true,
	}


func _entry(file: String, id: String) -> Dictionary:
	for entry: Dictionary in data[file]["entries"]:
		if entry["id"] == id:
			return entry
	return {}


func _template_root() -> Dictionary:
	return _entry("templates", "ship")["root"]


func _assert_error(code: String) -> void:
	var errors := DataValidator.validate(data)
	var found := errors.any(func(error: String) -> bool: return error.begins_with(code + " "))
	assert_true(found, "expected %s, got %s" % [code, str(errors)])


func test_valid_data_passes() -> void:
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_json_floats_pass_like_ints() -> void:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	assert_eq(DataValidator.validate(parsed), [] as Array[String])


func test_missing_file() -> void:
	data["sinks"] = null
	_assert_error("bad_file")


func test_wrong_schema_version() -> void:
	data["items"]["schema_version"] = 2
	_assert_error("bad_schema_version")


func test_bad_id() -> void:
	_entry("items", "iron")["id"] = "Iron"
	_assert_error("bad_id")


func test_duplicate_id() -> void:
	data["items"]["entries"].append(_entry("items", "slag").duplicate())
	_assert_error("duplicate_id")


func test_unsorted_entries() -> void:
	data["items"]["entries"].reverse()
	_assert_error("entries_unsorted")


func test_unknown_field() -> void:
	_entry("items", "iron")["denisty"] = 1
	_assert_error("unknown_field")


func test_missing_field() -> void:
	_entry("items", "iron").erase("stage")
	_assert_error("missing_field")


func test_stage_out_of_range() -> void:
	_entry("items", "iron")["stage"] = 6
	_assert_error("out_of_range")


func test_fractional_density() -> void:
	_entry("items", "iron")["density_kg_m3"] = 7000.5
	_assert_error("not_whole")


func test_value_that_does_not_convert() -> void:
	_entry("modules", "laser")["mass_kg"] = 20.0001234
	_assert_error("inexact_value")


func test_unknown_capability() -> void:
	_entry("modules", "laser")["capabilities"]["move"] = {}
	_assert_error("unknown_capability")


func test_capability_field_missing() -> void:
	_entry("modules", "laser")["capabilities"]["thruster"] = {
		"speed_m_s": 1, "propellant_kg_per_s": 1,
	}
	_assert_error("missing_field")


func test_rated_mass_must_be_above_zero() -> void:
	_entry("modules", "laser")["capabilities"]["thruster"] = {
		"speed_m_s": 1, "propellant_kg_per_s": 1, "rated_mass_kg": 0,
		"exhaust_m_s": 3000, "thrust_kn": 3,
	}
	_assert_error("bad_number")


## A55's minimum throttle (B29): optional, whole, 1 to 1000000 parts per million of full thrust.
func _thruster(extra: Dictionary) -> void:
	var thruster := { "speed_m_s": 1, "propellant_kg_per_s": 1, "rated_mass_kg": 1, "exhaust_m_s": 3000,
		"thrust_kn": 3 }
	thruster.merge(extra)
	_entry("modules", "laser")["capabilities"]["thruster"] = thruster


func test_thruster_passes_without_a_minimum_throttle() -> void:
	_thruster({})
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_minimum_throttle_passes_from_deep_to_full_only() -> void:
	for ppm: int in [1, 200000, 1000000]:
		_thruster({ "min_throttle_ppm": ppm })
		assert_eq(DataValidator.validate(data), [] as Array[String])


func test_minimum_throttle_must_be_whole_and_in_range() -> void:
	_thruster({ "min_throttle_ppm": 0 })
	_assert_error("out_of_range")
	_thruster({ "min_throttle_ppm": 1000001 })
	_assert_error("out_of_range")
	_thruster({ "min_throttle_ppm": 0.5 })
	_assert_error("not_whole")


func test_slice_engines_throttle_as_their_types_do() -> void:
	var modules := {}
	for entry: Dictionary in DataValidator.load_dir()["modules"]["entries"]:
		modules[entry["id"]] = entry
	assert_eq(modules["chemical_thruster_mk1"]["capabilities"]["thruster"]["min_throttle_ppm"], 200000.0)
	assert_eq(modules["small_chemical_thruster_mk1"]["capabilities"]["thruster"]["min_throttle_ppm"], 1000000.0)


func test_efficiency_above_one_million() -> void:
	_entry("modules", "laser")["capabilities"]["battery"] = {
		"capacity_kj": 1, "max_charge_kw": 1, "max_discharge_kw": 1,
		"charge_efficiency_ppm": 1000001,
	}
	_assert_error("out_of_range")


func test_cylinder_z_must_equal_x() -> void:
	_entry("modules", "laser")["collision"] = {
		"shape": "cylinder", "center_mm": [0, 0, 0], "size_mm": [10, 20, 30],
	}
	_assert_error("bad_collision")


func test_up_parallel_to_facing() -> void:
	_entry("modules", "laser")["connectors"][0]["up"] = "-x"
	_assert_error("bad_connector_axes")


func test_duplicate_connector() -> void:
	var laser := _entry("modules", "laser")
	laser["connectors"].append(laser["connectors"][0].duplicate())
	_assert_error("duplicate_connector")


func test_module_density_must_be_whole() -> void:
	_entry("modules", "laser")["volume_m3"] = 3
	_assert_error("density_not_whole")


func test_module_item_cannot_be_authored() -> void:
	data["items"]["entries"].insert(3, { "id": "laser", "name": "Laser", "stage": 5,
		"cargo_class": "goods", "density_kg_m3": 20, "unit_mass_kg": 20 })
	_assert_error("module_item_authored")


func test_visual_cannot_hold_numbers() -> void:
	_entry("modules", "laser")["visual"]["scale"] = [1, 2]
	_assert_error("bad_visual")


func test_visual_needs_a_tint() -> void:
	_entry("modules", "laser")["visual"].erase("tint")
	_assert_error("bad_visual")


func test_tint_must_be_lowercase_hex() -> void:
	_entry("modules", "laser")["visual"]["tint"] = "#E8E4D8"
	_assert_error("bad_visual")


func test_visual_may_hold_extra_strings() -> void:
	_entry("modules", "laser")["visual"]["label"] = "Laser"
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_child_must_mate_through_mount() -> void:
	var laser := _entry("modules", "laser")
	laser["connectors"].append(_connector("top", "side", "medium", [0, 9, 0]))
	_template_root()["children"][1]["connector"] = "top"
	_assert_error("not_through_mount")


func test_root_cannot_be_fabricated() -> void:
	_entry("modules", "hull")["fabrication"] = { "recipe": "laser" }
	_assert_error("root_fabricated")


func test_non_root_needs_fabrication() -> void:
	_entry("modules", "laser")["fabrication"] = null
	_assert_error("fabrication_missing")


func test_fabrication_must_output_the_module() -> void:
	_entry("modules", "laser")["fabrication"] = { "recipe": "refinery" }
	_assert_error("fabrication_mismatch")


func test_mount_missing() -> void:
	_entry("modules", "laser")["connectors"][0]["id"] = "side"
	_assert_error("mount_missing")


func test_mount_not_at_origin() -> void:
	_entry("modules", "laser")["connectors"][0]["pos_mm"] = [0, 5, 0]
	_assert_error("mount_not_at_origin")


func test_non_root_may_have_more_connectors() -> void:
	_entry("modules", "laser")["connectors"].append(_connector("top", "stack", "medium", [0, 9, 0]))
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_root_needs_core_connector() -> void:
	_entry("modules", "hull")["connectors"].remove_at(0)
	_template_root()["children"].remove_at(0)
	_assert_error("root_without_core_connector")


func test_core_connector_only_on_cores_and_roots() -> void:
	_entry("modules", "laser")["connectors"].append(_connector("spare", "side", "core", [0, 9, 0]))
	_assert_error("core_connector_misplaced")


func test_core_has_only_its_mount() -> void:
	_entry("modules", "core")["connectors"].append(_connector("spare", "side", "small", [0, 9, 0]))
	_assert_error("bad_core_connector")


func test_dock_connector_needs_port() -> void:
	_entry("modules", "laser")["connectors"].append(_connector("dock", "dock", "medium", [0, 9, 0]))
	_assert_error("port_mismatch")


func test_slice_parts_declare_tier_one() -> void:
	_entry("modules", "laser")["min_ai_tier"] = 2
	_assert_error("slice_min_ai_tier")


func test_recipe_unbalanced() -> void:
	_entry("recipes", "refine")["outputs"][0]["kg"] = 59
	_assert_error("recipe_unbalanced")


func test_module_recipe_must_match_module_mass() -> void:
	_entry("recipes", "laser")["inputs"][0]["count"] = 3
	_assert_error("recipe_unbalanced")


func test_discrete_item_uses_count() -> void:
	_entry("recipes", "laser")["inputs"] = [{ "item": "frame", "kg": 20 }]
	_assert_error("wrong_amount_form")


func test_continuous_item_uses_kg() -> void:
	_entry("recipes", "frame")["inputs"] = [{ "item": "iron", "count": 1 }]
	_assert_error("wrong_amount_form")


func test_both_amount_forms() -> void:
	_entry("recipes", "frame")["inputs"] = [{ "item": "iron", "kg": 10, "count": 1 }]
	_assert_error("bad_amount")


func test_repeated_item() -> void:
	_entry("recipes", "frame")["inputs"] = [
		{ "item": "iron", "kg": 5 }, { "item": "iron", "kg": 5 },
	]
	_assert_error("repeated_item")


## Real chain recipes (B29): not abstract, balanced to the gram, slag kept rather than sunk.
func test_a_real_recipe_keeps_its_slag() -> void:
	var refine := _entry("recipes", "refine")
	refine["abstract"] = false
	refine["outputs"][1].erase("sink")
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_a_real_recipe_must_balance() -> void:
	var refine := _entry("recipes", "refine")
	refine["abstract"] = false
	refine["outputs"][1].erase("sink")
	refine["outputs"][1]["kg"] = 30
	_assert_error("recipe_unbalanced")


func test_a_real_recipe_is_held_to_chemistry_not_the_slice_ceilings() -> void:
	var refine := _entry("recipes", "refine")
	refine["abstract"] = false
	refine["outputs"] = [{ "item": "iron", "kg": 100 }]
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_the_new_cargo_classes_and_machines_are_known() -> void:
	_add_sorted("items", { "id": "water", "name": "Water", "stage": 3, "cargo_class": "water",
		"density_kg_m3": 1000 })
	_entry("modules", "refinery")["capabilities"]["facility"]["type"] = "electrolyser"
	_entry("recipes", "refine")["facility"] = "electrolyser"
	assert_eq(DataValidator.validate(data), [] as Array[String])


## A cryogenic tank (B29): boil-off per class a day, and its cooler's draw.
func _cryo(value: Variant) -> void:
	_entry("modules", "hull")["capabilities"]["cryo"] = value


func test_a_cryo_tank_passes() -> void:
	_cryo({ "boil_off_ppm_per_day": { "propellant": 10000 }, "cooler_kw": 1 })
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_a_cryo_tank_needs_its_cooler() -> void:
	_cryo({ "boil_off_ppm_per_day": { "propellant": 10000 } })
	_assert_error("missing_field")


func test_a_cryo_rate_is_a_known_class_and_at_most_all_of_it() -> void:
	_cryo({ "boil_off_ppm_per_day": { "plasma": 10 }, "cooler_kw": 1 })
	_assert_error("bad_enum")
	_cryo({ "boil_off_ppm_per_day": { "propellant": 1000001 }, "cooler_kw": 1 })
	_assert_error("out_of_range")


func test_a_cryo_tank_is_an_object() -> void:
	_cryo(5)
	_assert_error("bad_capability")


func test_unknown_item() -> void:
	_entry("recipes", "frame")["inputs"] = [{ "item": "gold", "kg": 10 }]
	_assert_error("unknown_item")


func test_unknown_sink() -> void:
	_entry("recipes", "refine")["outputs"][1]["sink"] = "void"
	_assert_error("unknown_sink")


func test_sink_refuses_item() -> void:
	_entry("recipes", "refine")["outputs"] = [
		{ "item": "iron", "kg": 100, "sink": "slag_vent" },
	]
	_assert_error("sink_refuses_item")


func test_slag_must_route_to_a_sink() -> void:
	_entry("recipes", "refine")["outputs"][1].erase("sink")
	_assert_error("sink_route_missing")


func test_refining_needs_slag() -> void:
	_entry("recipes", "refine")["outputs"] = [{ "item": "iron", "kg": 100 }]
	_assert_error("slag_missing")


func test_yield_over_ceiling() -> void:
	var outputs: Array = _entry("recipes", "refine")["outputs"]
	outputs[0]["kg"] = 70
	outputs[1]["kg"] = 30
	_assert_error("yield_over_ceiling")


func test_yield_at_ceiling_passes() -> void:
	var outputs: Array = _entry("recipes", "refine")["outputs"]
	outputs[0]["kg"] = 69.9
	outputs[1]["kg"] = 30.1
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_recipe_over_facility_rating() -> void:
	_entry("recipes", "refine")["power_kw"] = 2
	_assert_error("recipe_over_power")


func test_unit_output_mass_counts_toward_balance() -> void:
	var recipe := _fabrication("build_ship", 13, "x")
	recipe["outputs"] = [{ "unit_template": "ship" }]
	data["recipes"]["entries"].append(recipe)
	data["recipes"]["entries"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["id"] < b["id"])
	assert_eq(DataValidator.validate(data), [] as Array[String])
	recipe["inputs"][0]["count"] = 12
	_assert_error("recipe_unbalanced")


func test_a_built_unit_needs_a_port_to_appear_at() -> void:
	var hull := _entry("modules", "hull")
	hull["capabilities"].erase("port")
	hull["connectors"] = hull["connectors"].filter(func(connector: Dictionary) -> bool:
		return connector["type"] != "dock")
	var recipe := _fabrication("build_ship", 13, "x")
	recipe["outputs"] = [{ "unit_template": "ship" }]
	data["recipes"]["entries"].append(recipe)
	data["recipes"]["entries"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["id"] < b["id"])
	_assert_error("built_unit_without_port")


func test_unit_output_must_be_alone() -> void:
	_entry("recipes", "refine")["outputs"].append({ "unit_template": "ship" })
	_assert_error("unit_output_not_alone")


func test_unknown_template() -> void:
	_entry("recipes", "laser")["outputs"] = [{ "unit_template": "nothing" }]
	_assert_error("unknown_template")


func test_deposit_too_hard() -> void:
	_entry("deposits", "hematite_small")["hardness"] = 7
	_assert_error("deposit_too_hard")


func test_deposit_needs_ore() -> void:
	_entry("deposits", "hematite_small")["item"] = "iron"
	_assert_error("bad_deposit")


func test_template_root_must_be_root_part() -> void:
	_template_root()["part"] = "laser"
	_assert_error("root_not_a_root_part")


func test_root_part_as_child() -> void:
	_template_root()["children"][1]["part"] = "hull"
	_assert_error("root_part_as_child")


func test_unknown_connector() -> void:
	_template_root()["children"][1]["parent_connector"] = "nowhere"
	_assert_error("unknown_connector")


func test_connector_type_mismatch() -> void:
	_entry("modules", "laser")["connectors"][0]["type"] = "stack"
	_assert_error("connector_type_mismatch")


func test_connector_size_mismatch() -> void:
	_template_root()["children"][1]["parent_connector"] = "core"
	_assert_error("connector_size_mismatch")


func test_sizes_other_than_core_join_freely() -> void:
	_entry("modules", "laser")["connectors"][0]["size"] = "small"
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_connector_occupied() -> void:
	_template_root()["children"].append({
		"part": "refinery", "parent_connector": "side_a", "connector": "mount", "children": [],
	})
	_assert_error("connector_occupied")


func test_over_load_limit() -> void:
	_entry("modules", "hull")["connectors"][1]["load_limit_kg"] = 1
	_assert_error("over_load_limit")


func test_over_mass_limit() -> void:
	_entry("modules", "hull")["capabilities"]["max_mass_kg"] = 50
	_assert_error("over_mass_limit")


func test_over_power_budget() -> void:
	_entry("modules", "hull")["capabilities"]["generate"]["power_kw"] = 1
	_assert_error("over_power_budget")


func test_battery_discharge_counts_toward_power_budget() -> void:
	var capabilities: Dictionary = _entry("modules", "hull")["capabilities"]
	capabilities["generate"]["power_kw"] = 1
	capabilities["battery"] = {
		"capacity_kj": 10, "max_charge_kw": 1, "max_discharge_kw": 2,
		"charge_efficiency_ppm": 1000000,
	}
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_over_heat_budget() -> void:
	_entry("modules", "hull")["capabilities"]["radiator"]["reject_kw"] = 1
	_assert_error("over_heat_budget")


func test_too_many_cores() -> void:
	var extra := _connector("core_b", "side", "core", [0, 9, 0])
	_entry("modules", "hull")["connectors"].append(extra)
	_template_root()["children"].append({
		"part": "core", "parent_connector": "core_b", "connector": "mount", "children": [],
	})
	_assert_error("too_many_cores")


func test_heat_needs_heat_capacity() -> void:
	_entry("modules", "hull")["capabilities"].erase("heat_capacity")
	_assert_error("heat_capacity_missing")


func test_thruster_needs_propellant_storage() -> void:
	_entry("modules", "laser")["capabilities"]["thruster"] = {
		"speed_m_s": 1, "propellant_kg_per_s": 1, "rated_mass_kg": 100,
		"exhaust_m_s": 3000, "thrust_kn": 3,
	}
	_entry("modules", "hull")["capabilities"]["storage"].erase("propellant")
	_assert_error("propellant_storage_missing")


func test_item_without_source() -> void:
	_scenario()["bodies"][1]["deposits"] = []
	_scenario()["units"][0]["inventory"].clear()
	data["deposits"]["entries"].clear()
	_assert_error("item_without_source")


func test_item_without_use() -> void:
	data["items"]["entries"].append({ "id": "zinc", "name": "Zinc", "stage": 3,
		"cargo_class": "goods", "density_kg_m3": 7000 })
	_assert_error("item_without_use")


func _scenario() -> Dictionary:
	return data["scenarios"][0]


func test_no_scenario() -> void:
	data["scenarios"] = []
	_assert_error("scenario_missing")


func test_unparsable_scenario() -> void:
	data["scenarios"].append(null)
	_assert_error("bad_scenario")


func test_scenario_unknown_field() -> void:
	_scenario()["sede"] = 1
	_assert_error("unknown_field")


func test_scenario_duplicate_key() -> void:
	_scenario()["units"][1]["key"] = "rock"
	_assert_error("duplicate_id")


func test_scenario_position_must_fit_json() -> void:
	_scenario()["bodies"][1]["pos_mm"] = [1e17, 0, 0]
	_assert_error("out_of_range")


func test_star_cannot_hold_deposits() -> void:
	_scenario()["bodies"][0]["deposits"] = ["hematite_small"]
	_assert_error("star_with_deposits")


func test_scenario_unknown_deposit() -> void:
	_scenario()["bodies"][1]["deposits"] = ["gold"]
	_assert_error("unknown_deposit")


func test_scenario_unknown_template() -> void:
	_scenario()["units"][0]["template"] = "nothing"
	_assert_error("unknown_template")


func test_scenario_stock_uses_recipe_amount_forms() -> void:
	_scenario()["units"][0]["inventory"] = [{ "item": "frame", "kg": 10 }]
	_assert_error("wrong_amount_form")


func test_scenario_stock_must_fit_by_mass() -> void:
	_scenario()["units"][1]["inventory"][0]["kg"] = 501
	_assert_error("start_stock_too_large")


func test_scenario_stock_must_fit_by_volume() -> void:
	_entry("modules", "hull")["capabilities"]["storage"]["propellant"]["volume_m3"] = 0.1
	_assert_error("start_stock_too_large")


func test_start_stock_is_a_source() -> void:
	_scenario()["units"][1]["inventory"].clear()
	_assert_error("item_without_source")


func test_start_dock_passes() -> void:
	_scenario()["units"][1]["dock"] = { "host": "ship", "port": 0, "host_port": 0 }
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_start_dock_unknown_host() -> void:
	_scenario()["units"][1]["dock"] = { "host": "nobody", "port": 0, "host_port": 0 }
	_assert_error("bad_start_dock")


func test_start_dock_port_out_of_range() -> void:
	_scenario()["units"][1]["dock"] = { "host": "ship", "port": 0, "host_port": 1 }
	_assert_error("bad_start_dock")


func test_start_dock_needs_the_host_position() -> void:
	_scenario()["units"][1]["pos_mm"] = [5, 0, 0]
	_scenario()["units"][1]["dock"] = { "host": "ship", "port": 0, "host_port": 0 }
	_assert_error("bad_start_dock")


## The star gets gravity and the rock and ship sit in a cluster frame on a 1 AU orbit.
func _add_cluster() -> void:
	var star: Dictionary = _scenario()["bodies"][0]
	star["gm_km3_s2"] = 132712440018
	_scenario()["frames"] = [{
		"key": "cluster", "name": "Cluster", "radius_mm": 1000000000,
		"orbit": { "parent": "star", "a_mm": 149597870700000 },
	}]
	_scenario()["bodies"][1]["frame"] = "cluster"
	_scenario()["units"][0]["frame"] = "cluster"


func test_frames_and_orbits_pass() -> void:
	_add_cluster()
	_scenario()["frames"][0]["orbit"].merge({
		"e_ppm": 16700, "inclination_mdeg": 0, "node_mdeg": 1000, "periapsis_mdeg": 359999,
		"mean_anomaly_mdeg": 90000,
	})
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_body_on_an_orbit_needs_no_position() -> void:
	_add_cluster()
	var rock: Dictionary = _scenario()["bodies"][1]
	rock.erase("frame")
	rock.erase("pos_mm")
	rock["orbit"] = { "parent": "star", "a_mm": 200000000000000 }
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_body_on_an_orbit_with_a_position() -> void:
	_add_cluster()
	_scenario()["bodies"][1].erase("frame")
	_scenario()["bodies"][1]["orbit"] = { "parent": "star", "a_mm": 200000000000000 }
	_assert_error("bad_place")


func test_body_needs_a_position_without_an_orbit() -> void:
	_scenario()["bodies"][1].erase("pos_mm")
	_assert_error("missing_field")


func test_orbit_parent_needs_gravity() -> void:
	_add_cluster()
	_scenario()["bodies"][0].erase("gm_km3_s2")
	_assert_error("orbit_without_gravity")


func test_orbit_parent_must_exist() -> void:
	_add_cluster()
	_scenario()["frames"][0]["orbit"]["parent"] = "nothing"
	_assert_error("orbit_without_gravity")


func test_orbit_takes_whole_numbers_only() -> void:
	_add_cluster()
	_scenario()["frames"][0]["orbit"]["e_ppm"] = 0.5
	_assert_error("not_whole")


func test_orbit_must_be_elliptic() -> void:
	_add_cluster()
	_scenario()["frames"][0]["orbit"]["e_ppm"] = 1000000
	_assert_error("out_of_range")


func test_orbit_angle_within_one_turn() -> void:
	_add_cluster()
	_scenario()["frames"][0]["orbit"]["node_mdeg"] = 360000
	_assert_error("out_of_range")


func test_orbit_unknown_field() -> void:
	_add_cluster()
	_scenario()["frames"][0]["orbit"]["a_m"] = 1
	_assert_error("unknown_field")


func test_frame_needs_radius_mm() -> void:
	_add_cluster()
	_scenario()["frames"][0].erase("radius_mm")
	_assert_error("missing_field")


func test_unknown_frame() -> void:
	_add_cluster()
	_scenario()["units"][0]["frame"] = "elsewhere"
	_assert_error("unknown_frame")


func test_docked_unit_has_no_frame() -> void:
	_add_cluster()
	_scenario()["units"][1]["frame"] = "cluster"
	_scenario()["units"][1]["dock"] = { "host": "ship", "port": 0, "host_port": 0 }
	_assert_error("bad_place")


func test_frame_key_is_unique_across_bodies() -> void:
	_add_cluster()
	_scenario()["frames"][0]["key"] = "rock"
	_assert_error("duplicate_id")


func test_gm_must_fit_the_contract_range() -> void:
	_scenario()["bodies"][0]["gm_km3_s2"] = 9100000000000
	_assert_error("out_of_range")


func test_gm_far_beyond_the_range_reports_the_range() -> void:
	_scenario()["bodies"][0]["gm_km3_s2"] = 1e13
	_assert_error("out_of_range")


func test_thruster_needs_burn_figures() -> void:
	_entry("modules", "laser")["capabilities"]["thruster"] = {
		"speed_m_s": 1, "propellant_kg_per_s": 1, "rated_mass_kg": 100,
	}
	_assert_error("missing_field")


## The rock becomes a planet with terrain settings.
func _make_planet() -> Dictionary:
	var rock: Dictionary = _scenario()["bodies"][1]
	rock["kind"] = "planet"
	rock["planet"] = { "seed": 48213, "height_range_m": 8000 }
	return rock["planet"]


func test_planet_passes() -> void:
	_make_planet().merge({ "sea_level_m": -200, "weights": [4, 2, 1] })
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_planet_kind_without_terrain_is_a_smooth_sphere() -> void:
	_scenario()["bodies"][1]["kind"] = "planet"
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_planet_object_only_on_a_planet() -> void:
	_make_planet()
	_scenario()["bodies"][1]["kind"] = "asteroid"
	_assert_error("bad_planet")


func test_planet_needs_a_seed() -> void:
	_make_planet().erase("seed")
	_assert_error("missing_field")


func test_planet_height_range_within_the_proven_limit() -> void:
	_make_planet()["height_range_m"] = 8001
	_assert_error("out_of_range")


func test_planet_sea_level_within_range() -> void:
	_make_planet()["sea_level_m"] = -8001
	_assert_error("out_of_range")


func test_planet_unknown_field() -> void:
	_make_planet()["roughness"] = 500
	_assert_error("unknown_field")


func test_planet_weights_are_whole() -> void:
	_make_planet()["weights"] = [4, 2.5, 1]
	_assert_error("not_whole")


func test_planet_weights_need_one_above_zero() -> void:
	_make_planet()["weights"] = [0, 0]
	_assert_error("bad_planet")


func test_planet_weights_at_most_twelve_octaves() -> void:
	_make_planet()["weights"] = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
	_assert_error("bad_planet")


func test_planet_weight_within_range() -> void:
	_make_planet()["weights"] = [1001]
	_assert_error("out_of_range")


func test_load_dir_reads_scenarios() -> void:
	var loaded := DataValidator.load_dir()
	assert_gt(loaded["scenarios"].size(), 0)


func test_load_dir_reports_missing_files() -> void:
	var errors := DataValidator.validate(DataValidator.load_dir("res://tests/no_such_dir/"))
	assert_eq(errors.size(), DataValidator.FILES.size())


func _gear(value: Variant) -> void:
	_entry("modules", "laser")["capabilities"]["landing_gear"] = { "max_touchdown_m_s": value }


func test_landing_gear_passes() -> void:
	_gear(6)
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_landing_gear_accepts_fractions_of_a_metre() -> void:
	_gear(2.5)
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_landing_gear_must_be_above_zero() -> void:
	_gear(0)
	_assert_error("bad_number")


func test_landing_gear_must_convert_to_whole_mm_s() -> void:
	_gear(1.0004)
	_assert_error("inexact_value")


func test_landing_gear_needs_its_limit() -> void:
	_entry("modules", "laser")["capabilities"]["landing_gear"] = {}
	_assert_error("missing_field")


## Docking capture limits (B29, for A54): how close and how slowly a port must be met to latch.
func test_port_needs_its_capture_limits() -> void:
	_entry("modules", "hull")["capabilities"]["port"].erase("capture_range_mm")
	_assert_error("missing_field")


func test_port_capture_range_is_whole_mm() -> void:
	_entry("modules", "hull")["capabilities"]["port"]["capture_range_mm"] = 100.5
	_assert_error("not_whole")


func test_port_capture_speed_must_be_above_zero() -> void:
	_entry("modules", "hull")["capabilities"]["port"]["capture_speed_m_s"] = 0
	_assert_error("bad_number")


func test_port_capture_speed_converts_to_whole_mm_s() -> void:
	_entry("modules", "hull")["capabilities"]["port"]["capture_speed_m_s"] = 0.0505
	_assert_error("inexact_value")


func test_slice_port_capture_limits() -> void:
	var modules := {}
	for entry: Dictionary in DataValidator.load_dir()["modules"]["entries"]:
		modules[entry["id"]] = entry
	var medium: Dictionary = modules["docking_port_mk1"]["capabilities"]["port"]
	var small: Dictionary = modules["small_docking_port_mk1"]["capabilities"]["port"]
	assert_eq([medium["capture_range_mm"], medium["capture_speed_m_s"]], [100.0, 0.1])
	assert_eq([small["capture_range_mm"], small["capture_speed_m_s"]], [50.0, 0.05])


func test_landing_gear_is_an_object() -> void:
	_entry("modules", "laser")["capabilities"]["landing_gear"] = 6
	_assert_error("bad_capability")


## Work points (C11, task B11b): `work` on recipes, `work_per_tick` on facilities, no `seconds`.
func test_recipe_seconds_is_rejected() -> void:
	_entry("recipes", "refine")["seconds"] = 5
	_assert_error("unknown_field")


## Factory rates (C30, B29): energy and heat per run, throughput per machine. Work points are optional
## until C30 is on main.
func test_recipe_needs_energy() -> void:
	_entry("recipes", "refine").erase("energy_kj")
	_assert_error("missing_field")


func test_recipe_needs_heat() -> void:
	_entry("recipes", "refine").erase("heat_kj")
	_assert_error("missing_field")


func test_recipe_passes_without_work_points() -> void:
	for id: String in ["frame", "refine", "tanker"]:
		_entry("recipes", id).erase("work")
		_entry("recipes", id).erase("power_kw")
	for id: String in ["fabricator", "refinery"]:
		_entry("modules", id)["capabilities"]["facility"].erase("work_per_tick")
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_energy_must_be_whole_and_positive() -> void:
	_entry("recipes", "refine")["energy_kj"] = 0
	_assert_error("out_of_range")
	_entry("recipes", "refine")["energy_kj"] = 5000.5
	_assert_error("not_whole")


func test_heat_may_be_zero_or_above_energy() -> void:
	_entry("recipes", "refine")["heat_kj"] = 0
	assert_eq(DataValidator.validate(data), [] as Array[String])
	_entry("recipes", "refine")["heat_kj"] = 50000
	assert_eq(DataValidator.validate(data), [] as Array[String])
	_entry("recipes", "refine")["heat_kj"] = -1
	_assert_error("out_of_range")


func test_facility_needs_throughput() -> void:
	_entry("modules", "refinery")["capabilities"]["facility"].erase("throughput_kg_per_s")
	_assert_error("missing_field")


func test_throughput_must_be_above_zero_and_exact() -> void:
	var facility: Dictionary = _entry("modules", "refinery")["capabilities"]["facility"]
	facility["throughput_kg_per_s"] = 0
	_assert_error("bad_number")
	facility["throughput_kg_per_s"] = 0.0005
	_assert_error("inexact_value")


func test_recipe_may_set_a_slower_throughput() -> void:
	_entry("recipes", "refine")["throughput_kg_per_s"] = 0.5
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_slower_facility_draws_power_in_proportion() -> void:
	var refinery: Dictionary = _entry("modules", "refinery")
	_entry("recipes", "refine")["power_kw"] = 2
	_assert_error("recipe_over_power")
	refinery["capabilities"]["facility"]["work_per_tick"] = 50
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_work_must_be_above_zero() -> void:
	_entry("recipes", "refine")["work"] = 0
	_assert_error("out_of_range")


func test_work_must_be_whole() -> void:
	_entry("recipes", "refine")["work"] = 5000.5
	_assert_error("not_whole")


func test_work_per_tick_must_be_whole_and_positive() -> void:
	var facility: Dictionary = _entry("modules", "refinery")["capabilities"]["facility"]
	facility["work_per_tick"] = 0
	_assert_error("out_of_range")
	facility["work_per_tick"] = 50.5
	_assert_error("not_whole")


func test_facility_rejects_other_fields() -> void:
	_entry("modules", "refinery")["capabilities"]["facility"]["speed"] = 2
	_assert_error("unknown_field")


## Everything is buildable (task B11).
func test_root_built_only_by_a_template_passes() -> void:
	assert_eq(DataValidator.validate(data), [] as Array[String])
	assert_null(_entry("modules", "hull")["fabrication"])


func test_module_nothing_builds() -> void:
	data["recipes"]["entries"] = data["recipes"]["entries"].filter(
		func(recipe: Dictionary) -> bool: return recipe["id"] != "tanker")
	_assert_error("not_buildable")


func test_part_inside_a_built_template_counts() -> void:
	var tanker: Dictionary = _entry("templates", "tanker")
	tanker["root"]["children"].append(
		{ "part": "laser", "parent_connector": "side_a", "connector": "mount", "children": [] })
	_entry("recipes", "tanker")["inputs"][0]["count"] = 12
	data["recipes"]["entries"] = data["recipes"]["entries"].filter(
		func(recipe: Dictionary) -> bool: return recipe["id"] != "laser")
	_entry("modules", "laser")["fabrication"] = null
	var errors := DataValidator.validate(data)
	assert_false(errors.any(func(error: String) -> bool: return error.begins_with("not_buildable ")),
		str(errors))


## Propellant is a product of ice (task B11), so a recipe may keep it rather than vent it.
func test_propellant_output_may_stay_in_the_hold() -> void:
	var recipe: Dictionary = _entry("recipes", "refine")
	recipe["outputs"] = [{ "item": "propellant", "kg": 60 }, { "item": "slag", "kg": 40, "sink": "slag_vent" }]
	var errors := DataValidator.validate(data)
	assert_false(errors.any(func(error: String) -> bool: return error.begins_with("sink_route_missing ")),
		str(errors))


func test_slag_must_still_be_vented() -> void:
	_entry("recipes", "refine")["outputs"][1].erase("sink")
	_assert_error("sink_route_missing")


## Research data (task B19): theories, science kinds, the lab and ideas.
func _research() -> void:
	data["modules"]["entries"].append(_module("lab", 10, { "facility": { "type": "lab", "throughput_kg_per_s": 1, "work_per_tick": 100 } },
		[_connector("mount", "side", "medium")]))
	data["recipes"]["entries"].append(_fabrication("lab", 1, "lab"))
	data["recipes"]["entries"].append({ "id": "prove_x", "facility": "lab", "energy_kj": 5000, "heat_kj": 5000, "work": 5000,
		"power_kw": 1, "points": 5, "inputs": [{ "item": "frame", "count": 1 }],
		"outputs": [{ "item": "frame", "count": 1, "sink": "test_consumed" }, { "theory": "x" }],
		"abstract": true })
	for file: String in ["modules", "recipes"]:
		data[file]["entries"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	data["sinks"]["entries"].append({ "id": "test_consumed", "name": "Test", "items": ["frame"] })
	data["theories"] = _envelope([{ "id": "x", "name": "X", "era": 2, "requires": [],
		"evidence": [{ "kind": "survey", "count": 1 }], "test": "prove_x", "unlocks": ["laser"] }])
	data["theories"]["bench_test"] = { "inputs": [{ "item": "frame", "count": 1 }], "energy_kj": 3000, "heat_kj": 3000, "work": 3000, "power_kw": 1 }
	data["science"] = _envelope([{ "id": "survey", "name": "Survey", "place": "asteroid",
		"capability": "scan", "points": { "asteroid": 10 } }])
	_entry("modules", "laser")["ideas"] = [
		{ "id": "fast", "name": "Fast", "theory": "x", "points": 5, "complexity": 2,
			"deltas": { "capabilities.mine.rate_kg_per_s": 250000, "power_kw": 200000 } },
		{ "id": "simple", "name": "Simple", "points": 0, "complexity": -1,
			"simplifies": true, "deltas": { "capabilities.mine.rate_kg_per_s": -100000, "mass_kg": -50000 } },
	]


func _theory() -> Dictionary:
	return data["theories"]["entries"][0]


func _idea(index: int) -> Dictionary:
	return _entry("modules", "laser")["ideas"][index]


func test_research_data_passes() -> void:
	_research()
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_theory_needs_known_evidence() -> void:
	_research()
	_theory()["evidence"][0]["kind"] = "smell"
	_assert_error("unknown_science")


func test_theory_test_must_be_its_lab_recipe() -> void:
	_research()
	_theory()["test"] = "laser"
	_assert_error("theory_test_mismatch")


func test_theory_era_is_two_or_later() -> void:
	_research()
	_theory()["era"] = 1
	_assert_error("out_of_range")


func test_theory_cannot_require_itself() -> void:
	_research()
	_theory()["requires"] = ["x"]
	_assert_error("theory_cycle")


func test_lab_recipe_must_prove_a_theory() -> void:
	_research()
	_entry("recipes", "prove_x")["outputs"] = [{ "item": "frame", "count": 1, "sink": "test_consumed" }]
	_assert_error("lab_without_theory")


func test_theory_proven_only_at_a_lab() -> void:
	_research()
	_entry("recipes", "prove_x")["facility"] = "fabricator"
	_assert_error("theory_not_at_lab")


func test_theory_output_stands_alone() -> void:
	_research()
	_entry("recipes", "prove_x")["outputs"][0].erase("sink")
	_assert_error("theory_output_not_alone")


func test_a_module_is_unlocked_once() -> void:
	_research()
	data["theories"]["entries"].append({ "id": "y", "name": "Y", "era": 2, "requires": [],
		"evidence": [], "test": "prove_x", "unlocks": ["laser"] })
	_assert_error("unlocked_twice")


func test_idea_needs_a_trade_off() -> void:
	_research()
	_idea(0)["deltas"] = { "capabilities.mine.rate_kg_per_s": 250000 }
	_assert_error("idea_without_trade_off")


func test_idea_field_must_be_allowed() -> void:
	_research()
	_idea(0)["deltas"]["connectors"] = 100
	_assert_error("bad_idea_field")


func test_idea_field_must_be_on_the_module() -> void:
	_research()
	_idea(0)["deltas"] = { "capabilities.battery.capacity_kj": 100000, "mass_kg": 100000 }
	_assert_error("bad_idea_field")


func test_idea_delta_cannot_reach_zero() -> void:
	_research()
	_idea(0)["deltas"]["power_kw"] = -1000000
	_assert_error("bad_idea_delta")


func test_negative_complexity_means_simplifies() -> void:
	_research()
	_idea(1).erase("simplifies")
	_assert_error("bad_idea")


func test_hidden_idea_needs_a_discovery_chance() -> void:
	_research()
	_idea(1)["hidden"] = true
	_assert_error("missing_field")
	_idea(1)["discover_ppm"] = 200000
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_idea_theory_must_exist() -> void:
	_research()
	_idea(0)["theory"] = "z"
	_assert_error("unknown_theory")


func test_science_place_is_known() -> void:
	_research()
	data["science"]["entries"][0]["place"] = "anywhere"
	_assert_error("bad_enum")


func test_science_points_name_body_classes() -> void:
	_research()
	data["science"]["entries"][0]["points"] = { "comet": 10 }
	_assert_error("bad_enum")


func test_goods_a_recipe_uses_may_go_to_a_sink_or_stay() -> void:
	_research()
	var errors := DataValidator.validate(data)
	assert_false(errors.any(func(error: String) -> bool: return error.begins_with("sink_route_missing ")),
		str(errors))


## C12: wildcard sinks, the bench test default, scenario research, and derived-ID safety.
func test_wildcard_sink_accepts_any_item() -> void:
	_research()
	data["sinks"]["entries"][2]["items"] = ["*"]
	_entry("recipes", "prove_x")["outputs"][0] = { "item": "frame", "count": 1, "sink": "test_consumed" }
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_wildcard_stands_alone() -> void:
	_research()
	data["sinks"]["entries"][2]["items"] = ["*", "frame"]
	_assert_error("bad_sink")


func test_wildcard_sink_does_not_make_goods_waste() -> void:
	data["sinks"]["entries"].append({ "id": "z_scrap", "name": "Scrap", "items": ["*"] })
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_theories_need_a_bench_test() -> void:
	_research()
	data["theories"].erase("bench_test")
	_assert_error("missing_field")


func test_bench_test_power_within_the_lab() -> void:
	_research()
	data["theories"]["bench_test"]["power_kw"] = 5
	_assert_error("recipe_over_power")


func test_theory_qualify_inputs_must_resolve() -> void:
	_research()
	_theory()["qualify"] = [{ "item": "nothing", "count": 1 }]
	_assert_error("unknown_item")


func test_scenario_research_names_known_theories() -> void:
	_research()
	_scenario()["research"] = { "theories": ["x"] }
	assert_eq(DataValidator.validate(data), [] as Array[String])
	_scenario()["research"] = { "theories": ["nope"] }
	_assert_error("unknown_theory")


## Derived IDs use ':' (prototype:<design>) and variants '+', so authored IDs never may.
func test_ids_cannot_hold_colon_or_plus() -> void:
	_entry("items", "iron")["id"] = "prototype:iron"
	_assert_error("bad_id")
	_entry("items", "prototype:iron")["id"] = "iron+fast"
	_assert_error("bad_id")


## A design (B25): the tanker hull plus a core and a laser, to fit in that order.
func _add_design() -> Dictionary:
	var design := { "id": "miner", "name": "Miner", "kind": "ship", "base": "tanker",
		"summary": "Mines on its own", "root": { "part": "hull", "children": [
			{ "part": "core", "parent_connector": "core", "connector": "mount", "children": [] },
			{ "part": "laser", "parent_connector": "side_a", "connector": "mount", "children": [] },
		] } }
	_add_sorted("templates", design)
	return design


func test_a_design_passes() -> void:
	_add_design()
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_a_design_needs_a_known_base() -> void:
	_add_design()["base"] = "barge"
	_assert_error("unknown_template")


func test_a_design_summary_is_a_string() -> void:
	_add_design()["summary"] = 3
	_assert_error("bad_type")


func test_a_design_base_must_be_built_by_a_recipe() -> void:
	_add_design()["base"] = "ship"
	_assert_error("design_base_not_built")


func test_a_design_is_never_built_in_one_go() -> void:
	_add_design()
	_add_sorted("recipes", { "id": "miner", "facility": "fabricator", "energy_kj": 5000, "heat_kj": 5000, "work": 5000,
		"power_kw": 1, "inputs": [{ "item": "frame", "count": 13 }],
		"outputs": [{ "unit_template": "miner" }], "abstract": true })
	_assert_error("design_built_whole")


func test_a_design_keeps_its_base_parts() -> void:
	var tanker := _entry("templates", "tanker")
	tanker["root"]["children"].append(
		{ "part": "laser", "parent_connector": "side_b", "connector": "mount", "children": [] })
	_entry("recipes", "tanker")["inputs"][0]["count"] = 12
	_add_design()
	_assert_error("design_drops_base_part")


func test_a_design_kind_matches_its_base() -> void:
	_add_design()["kind"] = "drone"
	_assert_error("design_kind_mismatch")


func test_a_design_over_its_budgets_is_allowed() -> void:
	# Fitting warns and allows (owner, 2026-11-07): the lamp may go on before the panel that powers it.
	_add_sorted("modules", _module("lamp", 10, {}, [_connector("mount", "side", "medium")]))
	_entry("modules", "lamp")["power_kw"] = 150
	_add_sorted("modules", _module("panel", 10, { "generate": { "power_kw": 200 } },
		[_connector("mount", "side", "medium")]))
	_add_sorted("recipes", _fabrication("lamp", 1, "lamp"))
	_add_sorted("recipes", _fabrication("panel", 1, "panel"))
	var design := _add_design()
	design["root"]["children"] = [
		{ "part": "panel", "parent_connector": "side_a", "connector": "mount", "children": [] },
		{ "part": "lamp", "parent_connector": "side_b", "connector": "mount", "children": [] },
	]
	assert_eq(DataValidator.validate(data), [] as Array[String], "panel first fits")
	design["root"]["children"].reverse()
	assert_eq(DataValidator.validate(data), [] as Array[String], "lamp first is allowed too")


func test_the_mining_drone_design_holds_the_drone_the_bot_flies() -> void:
	var defs := DataLoader.load_defs()
	var design: Dictionary = defs["templates"]["mining_drone"]
	assert_eq(design["base"], "small_craft")
	var fits: Array[String] = []
	for child: Dictionary in design["root"]["children"]:
		fits.append(child["part"])
	assert_eq(fits, ["small_docking_port_mk1", "small_solar_panel_mk1", "small_heat_radiator_mk1",
		"small_propellant_tank_mk1", "small_ore_container_mk1", "small_mining_laser_mk1",
		"small_battery_bank_mk1", "assisted_core"] as Array[String])


## Adds an entry in ID order, as the files keep them.
func _add_sorted(file: String, entry: Dictionary) -> void:
	var entries: Array = data[file]["entries"]
	entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
