extends GutTest

var defs: Dictionary


func before_all() -> void:
	defs = DataLoader.load_defs()


func _assert_no_floats(value: Variant, label: String) -> void:
	assert_false(value is float, "%s holds a float" % label)
	if value is Array:
		for entry: Variant in value:
			_assert_no_floats(entry, label)
	elif value is Dictionary:
		for key: Variant in value:
			if key != "visual":
				_assert_no_floats(value[key], "%s.%s" % [label, key])


func test_data_loads_with_every_section() -> void:
	assert_eq(DataLoader.error, "")
	assert_eq(defs.keys(), ["modules", "items", "recipes", "templates", "sinks"])


func test_nothing_the_simulation_reads_is_a_float() -> void:
	_assert_no_floats(defs, "defs")


func test_module_units_convert() -> void:
	var laser: Dictionary = defs["modules"]["mining_laser_mk1"]
	assert_eq(laser["mass_g"], 400_000)
	assert_eq(laser["volume_l"], 2000)
	assert_eq(laser["power_w"], 150_000)
	assert_eq(laser["heat_w"], 120_000)
	assert_eq(laser["capabilities"]["mine"]["rate_g_per_s"], 20_000)
	assert_eq(laser["connectors"][0]["load_limit_g"], 1_000_000)
	assert_false(laser.has("mass_kg"))


func test_capability_units_convert() -> void:
	var battery: Dictionary = defs["modules"]["battery_bank_mk1"]["capabilities"]["battery"]
	assert_eq(battery["capacity_j"], 360_000_000)
	assert_eq(battery["max_discharge_w"], 150_000)
	assert_eq(battery["charge_efficiency_ppm"], 900_000)
	var port: Dictionary = defs["modules"]["docking_port_mk1"]["capabilities"]["port"]
	assert_eq(port["transfer_g_per_s"], 50_000)
	assert_eq(port["dock_ticks"], 20 * Sim.TICKS_PER_SECOND)
	assert_eq(port["undock_ticks"], 10 * Sim.TICKS_PER_SECOND)
	var thruster: Dictionary = defs["modules"]["small_chemical_thruster_mk1"]["capabilities"]["thruster"]
	assert_eq(thruster["speed_mm_s"], 250_000)
	assert_eq(thruster["propellant_g_per_s"], 50)
	assert_eq(thruster["rated_mass_g"], 1_000_000)
	var ore: Dictionary = defs["modules"]["small_ore_container_mk1"]["capabilities"]["storage"]["ore"]
	assert_eq(ore["mass_g"], 500_000)
	assert_eq(ore["volume_l"], 200)
	assert_eq(defs["modules"]["small_hull"]["capabilities"]["max_mass_g"], 1_500_000)
	assert_eq(defs["modules"]["lidar_mk1"]["capabilities"]["scan"]["ticks"], 30 * Sim.TICKS_PER_SECOND)


func test_items_convert_and_modules_become_items() -> void:
	assert_eq(defs["items"]["hematite"]["density_g_l"], 5000)
	assert_eq(defs["items"]["wiring"]["unit_mass_g"], 10_000)
	var laser: Dictionary = defs["items"]["mining_laser_mk1"]
	assert_eq(laser["cargo_class"], "goods")
	assert_eq(laser["unit_mass_g"], 400_000)
	assert_eq(laser["density_g_l"], 200)


func test_recipes_give_every_amount_in_grams() -> void:
	var refine: Dictionary = defs["recipes"]["refine_hematite"]
	assert_eq(refine["ticks"], 60 * Sim.TICKS_PER_SECOND)
	assert_eq(refine["power_w"], 200_000)
	assert_eq(refine["inputs"][0]["grams"], 100_000)
	assert_eq(refine["outputs"][1]["sink"], "slag_vent")
	var frame: Dictionary = defs["recipes"]["ore_storage_mk1"]
	assert_eq(frame["inputs"][0]["grams"], 20 * 50_000)


func test_deposit_definitions_stay_out_of_defs() -> void:
	assert_false(defs.has("deposits"))
	assert_eq(DataLoader.load_deposits()["hematite_deposit"]["mass_g"], 200_000_000)


func test_exact_conversion_accepts_float_noise() -> void:
	assert_eq(1.001 * 1000.0 == 1001.0, false)
	DataLoader.error = ""
	assert_eq(DataLoader._exact(1.001, 1000, "test"), 1001)
	assert_eq(DataLoader.error, "")


func test_exact_conversion_rejects_a_real_fraction() -> void:
	DataLoader.error = ""
	DataLoader._exact(0.0005, 1000, "test")
	assert_string_contains(DataLoader.error, "test")
	DataLoader.error = ""


func test_field_rules() -> void:
	assert_eq(DataLoader._rule("propellant_kg_per_s"), ["propellant_g_per_s", 1000])
	assert_eq(DataLoader._rule("density_kg_m3"), ["density_g_l", 1])
	assert_eq(DataLoader._rule("speed_m_s"), ["speed_mm_s", 1000])
	assert_eq(DataLoader._rule("kg"), ["grams", 1000])
	assert_eq(DataLoader._rule("seconds"), ["ticks", Sim.TICKS_PER_SECOND])
	assert_eq(DataLoader._rule("pos_mm"), ["pos_mm", 1])
	assert_eq(DataLoader._rule("charge_efficiency_ppm"), ["charge_efficiency_ppm", 1])


func test_the_hash_ignores_what_the_simulation_never_reads() -> void:
	var changed: Dictionary = defs.duplicate(true)
	var laser: Dictionary = changed["modules"]["mining_laser_mk1"]
	laser["visual"]["tint"] = "#000000"
	laser["visual"]["scale"] = 1.5
	laser["name"] = "Renamed"
	laser["collision"]["size_mm"] = [1, 1, 1]
	assert_eq(Sim._data_hash(changed), Sim._data_hash(defs))


func test_the_hash_covers_what_the_simulation_reads() -> void:
	var changed: Dictionary = defs.duplicate(true)
	changed["modules"]["mining_laser_mk1"]["heat_w"] += 1
	assert_ne(Sim._data_hash(changed), Sim._data_hash(defs))


func test_a_hash_that_cannot_be_encoded_is_empty_and_loud() -> void:
	var changed: Dictionary = defs.duplicate(true)
	changed["modules"]["mining_laser_mk1"]["heat_w"] = 1.5
	assert_eq(Sim._data_hash(changed), "")
	assert_push_error("not canonical")
