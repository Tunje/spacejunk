extends GutTest
## A built unit takes its builder's place (C10): the frame, the orbit or the landed cell of the unit
## it docks to. So once it undocks it is where it was built, and can fly from there.

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const AU_MM := 149_597_870_700_000
const RADIUS_MM := 600_000_000
const ONE := OrbitMath.ONE
const RUN_TICKS := 3
const ORDER_LIMIT_TICKS := 6000

var sim: Sim
var state: Dictionary
var defs: Dictionary
var keys := {}


## A planet with a star on its -x side. The cluster frame Home is in low orbit on the sunward side,
## with a rock 20 km from the station in it, so solar panels work throughout.
func before_each() -> void:
	defs = DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": RADIUS_MM, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM },
				"planet": { "seed": 48213, "height_range_m": 8000 } },
			{ "key": "rock", "name": "Rock", "kind": "asteroid", "frame": "home", "pos_mm": [20_000_000, 0, 0],
				"radius_mm": 500_000, "visual_seed": 3, "deposits": [] },
		],
		"frames": [{ "key": "home", "name": "Home", "radius_mm": 1_000_000,
			"orbit": { "parent": "planet", "a_mm": 700_000_000, "mean_anomaly_mdeg": 180_000 } }],
		"units": [
			{ "key": "station", "template": "starter_station", "name": "Station", "pos_mm": [0, 0, 0],
				"frame": "home", "inventory": [], "dock": null },
		],
	}, {}), "")
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	defs = sim._ctx.defs
	defs["recipes"]["small_craft"]["ticks"] = RUN_TICKS
	state = sim._state
	keys = {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in state[table]:
			keys[state[table][id]["name"]] = id
	sim._strict = true


func _station() -> Dictionary:
	return state["units"][keys["Station"]]


func _fabricator() -> int:
	for part: int in Units.sorted_part_ids(state, keys["Station"]):
		if Units.module_of(state, defs, part)["capabilities"].get("facility", {}).get("type", "") == "fabricator":
			return part
	fail_test("the station has no fabricator")
	return 0


## Builds a small craft at the station and returns it.
func _build() -> int:
	for input: Dictionary in defs["recipes"]["small_craft"]["inputs"]:
		Units.add_stock(_station()["inventory"], input["item"], input["grams"])
	_count_matter()
	sim.submit({ "type": "start_job", "unit": keys["Station"],
		"args": { "facility": _fabricator(), "recipe": "small_craft", "count": 1 } })
	for i in RUN_TICKS + 1:
		sim.step()
		for event in sim.take_events():
			if event["type"] == "unit_created":
				return event["data"]["unit"]
	fail_test("no unit was built")
	return 0


## Fits enough for the craft to take orders and fly: power, heat, a tank, a thruster and a core.
func _make_flyable(id: int) -> void:
	var unit: Dictionary = state["units"][id]
	var hull: int = unit["root"]
	_fit(id, "small_solar_panel_mk1", hull, "side_a_px")
	_fit(id, "small_heat_radiator_mk1", hull, "side_a_nx")
	var tank := _fit(id, "small_propellant_tank_mk1", hull, "stack_bottom")
	_fit(id, "small_chemical_thruster_mk1", tank, "stack_bottom")
	unit["core"] = _fit(id, "assisted_core", hull, "core")
	var cap_g: int = sim.view()["units"][id]["cargo"]["propellant"]["cap_g"]
	Units.add_stock(unit["inventory"], "propellant", cap_g)
	_count_matter()


func _fit(unit: int, def: String, parent: int, connector: String) -> int:
	var part := Units.add_part(sim._ctx, unit, def, parent, connector, "mount")
	state["parts"][parent]["children"].append(part)
	return part


func _count_matter() -> void:
	sim._ctx.index.clear()
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]


func _order(id: int, type: String, args: Dictionary = {}) -> Dictionary:
	sim.submit({ "type": type, "unit": id, "args": args })
	for i in ORDER_LIMIT_TICKS:
		sim.step()
		for event in sim.take_events():
			if event["unit"] == id and event["type"] in ["task_finished", "task_cancelled", "command_rejected"]:
				return event
	fail_test("%s did not end" % type)
	return {}


func _gap_mm(a: int, b: int) -> int:
	return IntMath.dist(RailSystem.world_mm(state, "units", a), RailSystem.world_mm(state, "units", b))


func test_a_craft_built_in_a_frame_undocks_into_it_and_flies_to_a_rock() -> void:
	var craft := _build()
	assert_eq(state["units"][craft]["frame"], keys["Home"])
	assert_eq(state["units"][craft]["orbit"], {})
	_make_flyable(craft)
	assert_eq(_order(craft, "undock")["type"], "task_finished")
	assert_eq(RailSystem.unit_place(state, craft), keys["Home"])
	assert_lte(_gap_mm(craft, keys["Station"]), Travel.STANDOFF_MM, "undocked beside the station")
	var quoted := Travel.quote_trip(sim._ctx, craft, keys["Rock"], sim.current_tick() + 1)
	assert_eq(quoted.get("kind", quoted.get("reason")), "route", "a trip inside the frame")
	assert_eq(_order(craft, "move_to", { "target": keys["Rock"] })["type"], "task_finished")
	assert_eq(state["units"][craft]["at_target"], keys["Rock"])
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_a_craft_built_on_an_orbit_undocks_onto_it_with_no_jump() -> void:
	# A quarter turn from Home, so the station is clear of the frame, and out of the planet's shadow.
	var orbit := OrbitMath.make_orbit(GM_PLANET, 700_000_000, 0, [0, 0, ONE], [-ONE, 0, 0], 0, 0)
	orbit["parent"] = keys["Planet"]
	_station()["frame"] = 0
	_station()["orbit"] = orbit
	_station()["pos_mm"] = OrbitMath.position_at(orbit, 0)
	var craft := _build()
	assert_eq(state["units"][craft]["orbit"], _station()["orbit"])
	assert_eq(state["units"][craft]["frame"], 0)
	_make_flyable(craft)
	var docked_gap := _gap_mm(craft, keys["Station"])
	assert_eq(_order(craft, "undock")["type"], "task_finished")
	assert_eq(state["units"][craft]["orbit"], _station()["orbit"], "still on the station's orbit")
	assert_lte(_gap_mm(craft, keys["Station"]), docked_gap + Travel.STANDOFF_MM, "no jump on undocking")
	sim.step(100)
	assert_lte(_gap_mm(craft, keys["Station"]), docked_gap + Travel.STANDOFF_MM, "and it stays with the station")


func test_a_craft_built_while_landed_undocks_onto_the_same_cell() -> void:
	var cell := LandingSystem.cell_below(sim._ctx, keys["Planet"], [-RADIUS_MM * 2, 0, 0])
	_station()["frame"] = 0
	_station()["landed"] = { "body": keys["Planet"], "cell": cell }
	_station()["pos_mm"] = LandingSystem.cell_mm(sim._ctx, keys["Planet"], cell)
	var craft := _build()
	assert_eq(state["units"][craft]["landed"], { "body": keys["Planet"], "cell": cell })
	_make_flyable(craft)
	assert_eq(_order(craft, "undock")["type"], "task_finished")
	assert_eq(state["units"][craft]["landed"], { "body": keys["Planet"], "cell": cell }, "landed on the station's cell")
	assert_eq(sim.view()["units"][craft]["landed"], { "body": keys["Planet"], "cell": cell })
	assert_lte(_gap_mm(craft, keys["Station"]), Travel.STANDOFF_MM)
