extends GutTest

## Rechecks the hand calculations in docs/design/reference_scenario.md from data/,
## with the kernel's integer maths. C6 runs the chain itself against the same numbers.

const STANDOFF_MM := 150_000
const UNDOCK_POINT := [STANDOFF_MM, 0, 0]
const STATION_POS := [0, 0, 0]
const SHIP_START_PROPELLANT_G := 1_000_000
const HOLD_G := 2_000_000
const DRONE_TANK_G := 100_000
const DRONE_HOLD_G := 500_000

## Rock key, then the ticks and cost of each leg, as in the document.
const SHIP_TRIPS := [
	["rock_hematite", 984, 54908, 984, 74047],
	["rock_hematite", 984, 53639, 984, 72791],
	["rock_chalcopyrite", 988, 52608, 986, 71702],
	["rock_olivine", 634, 32970, 629, 45083],
]
const SHIP_PROPELLANT_LEFT_G := 542_252
const DRONE_OUT := [1968, 6692]
const DRONE_BACK := [1968, 11546]
const START_MATTER_G := 374_510_000

var data: Dictionary
var scenario: Dictionary
var modules: Dictionary = {}


func before_all() -> void:
	data = DataValidator.load_dir()
	scenario = data["scenarios"][0]
	for entry: Dictionary in data["modules"]["entries"]:
		modules[entry["id"]] = entry


func _ceil_div(a: int, b: int) -> int:
	return (a + b - 1) / b


func _template(id: String) -> Dictionary:
	for entry: Dictionary in data["templates"]["entries"]:
		if entry["id"] == id:
			return entry
	return {}


func _body(key: String) -> Dictionary:
	for body: Dictionary in scenario["bodies"]:
		if body["key"] == key:
			return body
	return {}


func _vector(values: Array) -> Array:
	return values.map(func(value: Variant) -> int: return int(value))


## The stop point of networks section 6, with its floored per-axis maths.
func _stop_point(from: Array, target: Array, stop_mm: int) -> Array:
	var total := IntMath.dist(from, target)
	var point := []
	for axis: int in 3:
		var span: int = absi(target[axis] - from[axis])
		var sign_value := 1 if target[axis] >= from[axis] else -1
		point.append(from[axis] + sign_value * IntMath.mul_div(span, total - stop_mm, total))
	return point


func _price(from: Array, to: Array, mass_g: int, thruster: Dictionary) -> Array:
	var speed_mm_s := roundi(thruster["speed_m_s"] * 1000.0)
	var burn_g_s := roundi(thruster["propellant_kg_per_s"] * 1000.0)
	var rated_g := roundi(thruster["rated_mass_kg"] * 1000.0)
	var ticks := _ceil_div(IntMath.dist(from, to) * Sim.TICKS_PER_SECOND, speed_mm_s)
	var base_g := _ceil_div(ticks * burn_g_s, Sim.TICKS_PER_SECOND)
	return [ticks, _ceil_div(base_g * mass_g, rated_g)]


func _tree_mass(node: Dictionary) -> int:
	var total := roundi(modules[node["part"]]["mass_kg"] * 1000.0)
	for child: Dictionary in node["children"]:
		total += _tree_mass(child)
	return total


func _parts_in_id_order(node: Dictionary) -> Array:
	var parts: Array = [node["part"]]
	for child: Dictionary in node["children"]:
		parts.append_array(_parts_in_id_order(child))
	return parts


func test_scenario_passes_the_validator() -> void:
	assert_eq(DataValidator.validate(data), [] as Array[String])


func test_entity_ids_match_the_document() -> void:
	var next_id := 1
	var ids := {}
	for body: Dictionary in scenario["bodies"]:
		ids[body["key"]] = next_id
		next_id += 1 + body["deposits"].size()
	for unit: Dictionary in scenario["units"]:
		ids[unit["key"]] = next_id
		var parts := _parts_in_id_order(_template(unit["template"])["root"])
		for index: int in parts.size():
			ids["%s.%d.%s" % [unit["key"], index, parts[index]]] = next_id + 1 + index
		next_id += 1 + parts.size()
	assert_eq(ids["rock_hematite"], 2)
	assert_eq(ids["rock_chalcopyrite"], 4)
	assert_eq(ids["rock_olivine"], 6)
	assert_eq(ids["station"], 8)
	assert_eq(ids["ship"], 23)
	assert_eq(ids["station.2.docking_port_mk1"], 11)
	assert_eq(ids["station.3.docking_port_mk1"], 12)
	assert_eq(ids["station.4.ore_refinery_mk1"], 13)
	assert_eq(ids["station.5.fabricator_mk1"], 14)
	assert_eq(ids["ship.0.starter_hull"], 24)
	assert_eq(ids["ship.4.docking_port_mk1"], 28)
	assert_eq(ids["ship.11.mining_laser_mk1"], 35)
	assert_eq(ids["ship.12.lidar_mk1"], 36)


func test_ship_trips_match_the_document() -> void:
	var thruster: Dictionary = modules["chemical_thruster_mk1"]["capabilities"]["thruster"]
	var dry_g := _tree_mass(_template("starter_ship")["root"])
	var propellant_g := SHIP_START_PROPELLANT_G
	for trip: Array in SHIP_TRIPS:
		var body := _body(trip[0])
		var rock := _vector(body["pos_mm"])
		var stop_mm := int(body["radius_mm"]) + STANDOFF_MM
		var there := _stop_point(UNDOCK_POINT, rock, stop_mm)
		assert_eq(_price(UNDOCK_POINT, there, dry_g + propellant_g, thruster), [trip[1], trip[2]])
		propellant_g -= trip[2]
		var home := _stop_point(there, STATION_POS, STANDOFF_MM)
		var loaded_g := dry_g + propellant_g + HOLD_G
		assert_eq(_price(there, home, loaded_g, thruster), [trip[3], trip[4]])
		propellant_g -= trip[4]
	assert_eq(propellant_g, SHIP_PROPELLANT_LEFT_G)


func test_drone_lap_matches_the_document() -> void:
	var thruster: Dictionary = modules["mining_drone_body"]["capabilities"]["thruster"]
	var dry_g := roundi((modules["mining_drone_body"]["mass_kg"]
		+ modules["assisted_core"]["mass_kg"]) * 1000.0)
	var body := _body("rock_hematite")
	var stop_mm := int(body["radius_mm"]) + STANDOFF_MM
	var there := _stop_point(UNDOCK_POINT, _vector(body["pos_mm"]), stop_mm)
	assert_eq(_price(UNDOCK_POINT, there, dry_g + DRONE_TANK_G, thruster), DRONE_OUT)
	var left_g: int = DRONE_TANK_G - DRONE_OUT[1]
	var home := _stop_point(there, STATION_POS, STANDOFF_MM)
	assert_eq(_price(there, home, dry_g + left_g + DRONE_HOLD_G, thruster), DRONE_BACK)


func test_starting_matter_matches_the_document() -> void:
	var total := 0
	var deposits := {}
	for entry: Dictionary in data["deposits"]["entries"]:
		deposits[entry["id"]] = roundi(entry["mass_kg"] * 1000.0)
	for body: Dictionary in scenario["bodies"]:
		for id: String in body["deposits"]:
			total += deposits[id]
	for unit: Dictionary in scenario["units"]:
		total += _tree_mass(_template(unit["template"])["root"])
		for entry: Dictionary in unit["inventory"]:
			total += roundi(entry["kg"] * 1000.0)
	assert_eq(total, START_MATTER_G)


func test_ship_starts_docked_at_the_second_station_port() -> void:
	var ship: Dictionary = scenario["units"][1]
	assert_eq(ship["dock"], { "host": "station", "port": 0.0, "host_port": 1.0 })


func test_upgrade_connectors_are_free_on_the_ship() -> void:
	var used: Array = _template("starter_ship")["root"]["children"].map(
		func(child: Dictionary) -> String: return child["parent_connector"])
	assert_does_not_have(used, "side_b_nz")
	assert_does_not_have(used, "side_c_nx")


func test_expansion_connector_is_free_on_the_station() -> void:
	var used: Array = _template("starter_station")["root"]["children"].map(
		func(child: Dictionary) -> String: return child["parent_connector"])
	assert_does_not_have(used, "side_c_px")
