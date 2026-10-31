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
			_module("fabricator", 10, { "facility": { "type": "fabricator" } },
				[_connector("mount", "side", "medium")]),
			_hull(),
			_module("laser", 20, { "mine": { "rate_kg_per_s": 1, "hardness_max": 6 } },
				[_connector("mount", "side", "medium")]),
			_module("refinery", 10, { "facility": { "type": "refinery" } },
				[_connector("mount", "side", "medium")]),
		]),
		"recipes": _envelope([
			_fabrication("core", 1, "core"),
			_fabrication("fabricator", 1, "fabricator"),
			{ "id": "frame", "facility": "fabricator", "seconds": 5, "power_kw": 1,
				"inputs": [{ "item": "iron", "kg": 10 }],
				"outputs": [{ "item": "frame", "count": 1 }], "abstract": true },
			_fabrication("laser", 2, "laser"),
			{ "id": "refine", "facility": "refinery", "seconds": 5, "power_kw": 1,
				"inputs": [{ "item": "hematite", "kg": 100 }],
				"outputs": [{ "item": "iron", "kg": 60 },
					{ "item": "slag", "kg": 40, "sink": "slag_vent" }],
				"abstract": true },
			_fabrication("refinery", 1, "refinery"),
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
	}


func _fabrication(id: String, frames: int, output: String) -> Dictionary:
	return {
		"id": id, "facility": "fabricator", "seconds": 5, "power_kw": 1,
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
	}
	_assert_error("bad_number")


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


func test_recipe_not_abstract() -> void:
	_entry("recipes", "frame")["abstract"] = false
	_assert_error("recipe_not_abstract")


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
	_entry("modules", "laser")["connectors"][0]["size"] = "small"
	_assert_error("connector_size_mismatch")


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
	}
	_assert_error("propellant_storage_missing")


func test_item_without_source() -> void:
	data["deposits"]["entries"].clear()
	_assert_error("item_without_source")


func test_item_without_use() -> void:
	data["items"]["entries"].append({ "id": "zinc", "name": "Zinc", "stage": 3,
		"cargo_class": "goods", "density_kg_m3": 7000 })
	_assert_error("item_without_use")


func test_load_dir_reports_missing_files() -> void:
	var errors := DataValidator.validate(DataValidator.load_dir("res://tests/no_such_dir/"))
	assert_eq(errors.size(), DataValidator.FILES.size())
