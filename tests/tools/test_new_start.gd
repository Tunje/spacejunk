extends GutTest

## Checks the new start (task B11, owner rulings of 2026-11-06) in data/: the probe-only scenario
## round the icy moon, the probe's legs, its lift-off thrust and the ice-to-propellant chain.

const MOON_KEY := "moon"
## Lead rule after D19: lift-off thrust at least twice local gravity, fully fuelled.
const LIFT_OFF_MARGIN := 2.0
## km³/s² to m³/s², for the moon's surface gravity from its GM.
const KM3_TO_M3 := 1.0e9

var data: Dictionary
var scenario: Dictionary
var modules: Dictionary = {}


func before_all() -> void:
	data = DataValidator.load_dir()
	for entry: Dictionary in data["scenarios"]:
		if entry["id"] == "new_start":
			scenario = entry
	for entry: Dictionary in data["modules"]["entries"]:
		modules[entry["id"]] = entry


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


func _mass_kg(node: Dictionary) -> float:
	var total: float = modules[node["part"]]["mass_kg"]
	for child: Dictionary in node["children"]:
		total += _mass_kg(child)
	return total


func _find(node: Dictionary, part: String, out: Array) -> void:
	if node["part"] == part:
		out.append(node)
	for child: Dictionary in node["children"]:
		_find(child, part, out)


func _connector(module: String, id: String) -> Dictionary:
	for connector: Dictionary in modules[module]["connectors"]:
		if connector["id"] == id:
			return connector
	return {}


## The lowest point of a module's collision box, relative to its own origin.
func _bottom_mm(module: String) -> float:
	var collision: Dictionary = modules[module]["collision"]
	return collision["center_mm"][1] - collision["size_mm"][1] / 2.0


func test_new_start_exists_with_only_the_probe() -> void:
	assert_false(scenario.is_empty(), "data/scenarios/new_start.json")
	assert_eq(scenario["units"].size(), 1)
	assert_eq(scenario["units"][0]["template"], "probe")
	assert_eq(scenario["units"][0]["inventory"], [{ "item": "propellant", "kg": 2000.0 }])


func test_cluster_has_the_four_rocks_including_ice() -> void:
	var items: Array = []
	for body: Dictionary in scenario["bodies"]:
		if body["kind"] == "asteroid":
			assert_eq(body.get("frame"), "cluster", body["key"])
			items.append(body["deposits"][0])
	items.sort()
	assert_eq(items, ["chalcopyrite_deposit", "hematite_deposit", "olivine_deposit", "water_ice_deposit"])


func test_cluster_orbits_the_moon_at_300_km_inside_its_sphere() -> void:
	var moon := _body(MOON_KEY)
	var planet := _body("planet")
	var orbit: Dictionary = scenario["frames"][0]["orbit"]
	assert_eq(orbit["parent"], MOON_KEY)
	assert_eq(orbit["a_mm"], 300_000_000.0)
	var soi_mm: float = moon["orbit"]["a_mm"] * pow(moon["gm_km3_s2"] / planet["gm_km3_s2"], 0.4)
	assert_lt(orbit["a_mm"], soi_mm, "the cluster stays inside the moon's sphere of influence")
	assert_gt(orbit["a_mm"] - scenario["frames"][0]["radius_mm"], moon["radius_mm"],
		"every point of the frame clears the moon's surface")


func test_moon_is_half_kerbin_density() -> void:
	var moon := _body(MOON_KEY)
	var planet := _body("planet")
	var ratio: float = (moon["gm_km3_s2"] / pow(moon["radius_mm"], 3)) \
		/ (planet["gm_km3_s2"] / pow(planet["radius_mm"], 3))
	assert_almost_eq(ratio, 0.5, 0.001)


func test_probe_has_four_legs_on_the_tank() -> void:
	var tanks: Array = []
	_find(_template("probe")["root"], "propellant_tank_mk1", tanks)
	assert_eq(tanks.size(), 1)
	var legs: Array = tanks[0]["children"].filter(
		func(node: Dictionary) -> bool: return node["part"] == "landing_legs_mk1")
	assert_eq(legs.size(), 4)


func test_legs_reach_below_the_nozzle() -> void:
	var leg_mount: Dictionary = _connector("propellant_tank_mk1", "side_px")
	var thruster_mount: Dictionary = _connector("propellant_tank_mk1", "stack_bottom")
	var foot_mm: float = leg_mount["pos_mm"][1] + _bottom_mm("landing_legs_mk1")
	var nozzle_mm: float = thruster_mount["pos_mm"][1] + _bottom_mm("chemical_thruster_mk1")
	assert_lt(foot_mm, nozzle_mm, "the probe stands on its feet, not its nozzle")
	assert_almost_eq(nozzle_mm - foot_mm, 400.0, 1.0)


func test_lift_off_thrust_is_twice_the_moons_gravity_fully_fuelled() -> void:
	var moon := _body(MOON_KEY)
	var radius_m: float = moon["radius_mm"] / 1000.0
	var gravity: float = moon["gm_km3_s2"] * KM3_TO_M3 / (radius_m * radius_m)
	var wet_kg: float = _mass_kg(_template("probe")["root"]) + 2000.0
	var thrust_n: float = modules["chemical_thruster_mk1"]["capabilities"]["thruster"]["thrust_kn"] * 1000.0
	assert_gt(thrust_n / wet_kg, LIFT_OFF_MARGIN * gravity)


func test_ice_refines_into_propellant() -> void:
	var recipe: Dictionary = {}
	for entry: Dictionary in data["recipes"]["entries"]:
		if entry["id"] == "refine_water_ice":
			recipe = entry
	assert_eq(recipe["facility"], "refinery")
	assert_eq(recipe["inputs"], [{ "item": "water_ice", "kg": 100.0 }])
	assert_eq(recipe["outputs"][0], { "item": "propellant", "kg": 90.0 })
	assert_eq(recipe["outputs"][1]["sink"], "slag_vent")


func test_every_hull_and_hub_is_built_by_a_template_recipe() -> void:
	var built := {}
	for entry: Dictionary in data["recipes"]["entries"]:
		for output: Dictionary in entry["outputs"]:
			if output.has("unit_template"):
				built[_template(output["unit_template"])["root"]["part"]] = true
	for root: String in ["small_hull", "starter_hull", "small_hub", "command_hub"]:
		assert_true(built.has(root), root)
