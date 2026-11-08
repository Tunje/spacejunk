extends GutTest
## Science points and the measure order (C12): payments that halve per key, a scan paying survey
## points, composition at a rock, a surface sample while landed, and a gravity field over one lap
## that a change of orbit ends unpaid.

const GM_STAR := 132_712_440_018_000_000
## A dense little planet, so a lap at 100 km takes about 63 s.
const GM_PLANET := 10_000_000_000
const GM_MOON := 100_000_000
const AU_MM := 149_597_870_700_000
const RADIUS_MM := 50_000_000
const ORBIT_MM := 100_000_000
const ONE := OrbitMath.ONE
const ORDER_LIMIT_TICKS := 6000

var sim: Sim
var state: Dictionary
var keys := {}


func _reference() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state


## A star, a planet round it, a moon round the planet and a rock, with a ship on a low orbit of
## the planet.
func _small_world() -> int:
	var defs := DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": RADIUS_MM, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM },
				"planet": { "seed": 48213, "height_range_m": 1000 } },
			{ "key": "moon", "name": "Moon", "kind": "planet", "radius_mm": 20_000_000, "visual_seed": 3,
				"deposits": [], "gm": GM_MOON, "orbit": { "parent": "planet", "a_mm": 5_000_000_000 },
				"planet": { "seed": 7, "height_range_m": 500 } },
		],
		"frames": [{ "key": "ring", "name": "Ring", "radius_mm": 1_000_000,
			"orbit": { "parent": "planet", "a_mm": ORBIT_MM } }],
		"units": [],
	}, {}), "")
	sim._strict = true
	state = sim._state
	keys = {}
	for table: String in ["bodies", "frames"]:
		for id: int in state[table]:
			keys[state[table][id]["name"]] = id
	var ship := Units.create(sim._ctx, "starter_ship", "Ship", [0, 0, 0])
	var orbit := OrbitMath.make_orbit(GM_PLANET, ORBIT_MM, 0, [0, 0, ONE], [ONE, 0, 0], 0, 0)
	orbit["parent"] = keys["Planet"]
	var unit: Dictionary = state["units"][ship]
	unit["frame"] = 0
	unit["orbit"] = orbit
	unit["pos_mm"] = OrbitMath.position_at(orbit, 0)
	for part: int in Units.sorted_part_ids(state, ship):
		var capabilities: Dictionary = Units.module_of(state, sim._ctx.defs, part)["capabilities"]
		if capabilities.has("ai_core"):
			unit["core"] = part
		if capabilities.has("battery"):
			# Charged, as a scenario's units start, so the core runs through the planet's shadow.
			state["parts"][part]["stored_j"] = capabilities["battery"]["capacity_j"]
	sim._ctx.index.clear()
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	return ship


## Gives an order and steps until its task ends; returns the ending event.
func _order(unit: int, type: String, args: Dictionary, limit: int = ORDER_LIMIT_TICKS) -> Dictionary:
	sim.submit({ "type": type, "unit": unit, "args": args })
	for i in limit:
		sim.step()
		for event in sim.take_events():
			if event["unit"] == unit and event["type"] in ["task_finished", "task_cancelled", "command_rejected"]:
				return event
	fail_test("%s did not end" % type)
	return {}


## Pays `kind` at a body `times` times, and returns the points each payment gave.
func _pay(kind: String, body: int, times: int) -> Array:
	var gained := []
	for i in times:
		var before: int = state["science"]["points"]
		Science.pay(sim._ctx, 23, kind, body)
		gained.append(state["science"]["points"] - before)
	return gained


func test_a_key_pays_half_as_much_each_time_down_to_nothing() -> void:
	_reference()
	assert_eq(_pay("composition", 2, 6), [20, 10, 5, 2, 1, 0])
	assert_eq(state["science"]["paid"], { "composition:2": 6 })
	assert_eq(state["science"]["points"], 38)
	assert_eq(state["science"]["earned"], 38)
	assert_eq(_pay("composition", 4, 1), [20], "a new rock pays in full")
	assert_eq(Science.evidence(state), { "composition": 2 })


func test_a_finished_scan_pays_survey_points() -> void:
	_reference()
	_order(23, "undock", {})
	_order(23, "move_to", { "target": 2 })
	assert_eq(_order(23, "scan", { "target": 2 })["type"], "task_finished")
	assert_eq(state["science"]["paid"], { "survey:2": 1 })
	assert_eq(state["science"]["points"], 10)
	assert_eq(sim.view()["science"]["evidence"], { "survey": 1 })
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_composition_is_measured_at_a_rock_with_the_lidar() -> void:
	_reference()
	_order(23, "undock", {})
	assert_eq(sim.check({ "type": "measure", "unit": 23, "args": { "target": 2, "kind": "composition" } })["reason"],
		"out_of_range")
	_order(23, "move_to", { "target": 2 })
	var start := sim.current_tick()
	assert_eq(_order(23, "measure", { "target": 2, "kind": "composition" })["type"], "task_finished")
	assert_eq(sim.current_tick() - start, sim.defs()["science"]["composition"]["ticks"] + 1,
		"its time, then the task ends on the next tick")
	assert_eq(state["science"]["paid"], { "composition:2": 1 })
	assert_eq(state["science"]["points"], 20)


func test_measure_refuses_what_does_not_apply() -> void:
	_reference()
	# Docked at the station, the ship measures from the station's place, out of range of the rock
	# rather than refused for being docked (C34).
	var docked := sim.check({ "type": "measure", "unit": 23, "args": { "target": 2, "kind": "composition" } })
	assert_eq(docked["reason"], "out_of_range")
	assert_eq(sim.check({ "type": "measure", "unit": 23, "args": { "target": 2, "kind": "luck" } })["reason"],
		"malformed_command")
	assert_eq(sim.check({ "type": "measure", "unit": 23, "args": { "target": 2, "kind": "gravity_field" } })["reason"],
		"invalid_target", "an asteroid has no gravity-field points")
	assert_eq(sim.check({ "type": "measure", "unit": 23, "args": { "target": 2, "kind": "surface" } })["reason"],
		"invalid_target")


func test_bodies_are_classed_as_asteroid_moon_or_planet() -> void:
	_small_world()
	assert_eq(Science.body_class(state, keys["Planet"]), "planet")
	assert_eq(Science.body_class(state, keys["Moon"]), "moon")
	assert_eq(Science.body_class(state, keys["Star"]), "star")


func test_a_gravity_field_takes_one_lap_and_pays_once_for_the_planet() -> void:
	var ship := _small_world()
	var period: int = (state["units"][ship]["orbit"]["period_subticks"] + OrbitMath.SUB_TICKS - 1) / OrbitMath.SUB_TICKS
	var start := sim.current_tick()
	assert_eq(_order(ship, "measure", { "target": keys["Planet"], "kind": "gravity_field" })["type"], "task_finished")
	assert_eq(sim.current_tick() - start, period + 1, "one lap, then the task ends on the next tick")
	assert_eq(state["science"]["paid"], { "gravity_field:%d" % keys["Planet"]: 1 })
	assert_eq(state["science"]["points"], 60)
	assert_eq(sim.check({ "type": "measure", "unit": ship, "args": { "target": keys["Moon"], "kind": "gravity_field" } })["reason"],
		"out_of_range", "not on an orbit round the moon")
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_a_change_of_orbit_ends_a_gravity_field_unpaid() -> void:
	var ship := _small_world()
	sim.submit({ "type": "measure", "unit": ship, "args": { "target": keys["Planet"], "kind": "gravity_field" } })
	sim.step(50)
	var orbit: Dictionary = state["units"][ship]["orbit"]
	orbit["epoch_tick"] = orbit["epoch_tick"] + 1
	var ended := {}
	for i in 5:
		sim.step()
		for event in sim.take_events():
			if event["type"] == "task_cancelled":
				ended = event
	assert_eq(ended.get("data", {}).get("reason"), "orbit_changed")
	assert_eq(state["science"]["paid"], {})
	assert_eq(state["science"]["points"], 0)


## C18: a unit in a frame whose orbit is round the body measures over one of the frame's laps.
func _into_the_ring(ship: int) -> void:
	var unit: Dictionary = state["units"][ship]
	unit["orbit"] = {}
	unit["frame"] = keys["Ring"]
	unit["pos_mm"] = [100_000, 0, 0]
	sim._ctx.index.clear()


func test_a_gravity_field_is_taken_from_a_frame_round_the_body() -> void:
	var ship := _small_world()
	_into_the_ring(ship)
	var ring: Dictionary = state["frames"][keys["Ring"]]["orbit"]
	var period: int = (ring["period_subticks"] + OrbitMath.SUB_TICKS - 1) / OrbitMath.SUB_TICKS
	assert_eq(sim.check({ "type": "measure", "unit": ship, "args": { "target": keys["Moon"], "kind": "gravity_field" } })["reason"],
		"out_of_range", "the ring orbits the planet, not the moon")
	var start := sim.current_tick()
	assert_eq(_order(ship, "measure", { "target": keys["Planet"], "kind": "gravity_field" })["type"], "task_finished")
	assert_eq(sim.current_tick() - start, period + 1, "one lap of the frame, then the task ends on the next tick")
	assert_eq(state["science"]["paid"], { "gravity_field:%d" % keys["Planet"]: 1 })
	assert_eq(state["science"]["points"], 60)


func test_leaving_the_frame_ends_a_gravity_field_unpaid() -> void:
	var ship := _small_world()
	_into_the_ring(ship)
	sim.submit({ "type": "measure", "unit": ship, "args": { "target": keys["Planet"], "kind": "gravity_field" } })
	sim.step(50)
	var unit: Dictionary = state["units"][ship]
	unit["frame"] = 0
	unit["orbit"] = OrbitMath.make_orbit(GM_PLANET, ORBIT_MM, 0, [0, 0, ONE], [ONE, 0, 0], 0, 0)
	unit["orbit"]["parent"] = keys["Planet"]
	unit["pos_mm"] = OrbitMath.position_at(unit["orbit"], sim.current_tick())
	sim._ctx.index.clear()
	var ended := {}
	for i in 5:
		sim.step()
		for event in sim.take_events():
			if event["type"] == "task_cancelled":
				ended = event
	assert_eq(ended.get("data", {}).get("reason"), "orbit_changed")
	assert_eq(state["science"]["paid"], {})


func test_a_surface_sample_is_taken_landed() -> void:
	var ship := _small_world()
	var unit: Dictionary = state["units"][ship]
	# The sunward side, so solar keeps the core and LIDAR running for the whole sample.
	var cell := LandingSystem.cell_below(sim._ctx, keys["Planet"], [-RADIUS_MM * 2, 0, 0])
	unit["orbit"] = {}
	unit["landed"] = { "body": keys["Planet"], "cell": cell }
	unit["pos_mm"] = LandingSystem.cell_mm(sim._ctx, keys["Planet"], cell)
	var ended := _order(ship, "measure", { "target": keys["Planet"], "kind": "surface" })
	assert_eq([ended["type"], ended["data"].get("reason", "")], ["task_finished", ""])
	assert_eq(state["science"]["paid"], { "surface:%d:default" % keys["Planet"]: 1 })
	assert_eq(state["science"]["points"], 50)


## C34: docked, a ship measures on its host's orbit. Here the host is a bare craft on the ship's own
## low orbit of the planet, and the ship rides it.
func _docked_to_a_host(ship: int) -> int:
	var host := Units.create(sim._ctx, "small_craft", "Host", [0, 0, 0])
	var unit: Dictionary = state["units"][ship]
	state["units"][host]["frame"] = 0
	state["units"][host]["orbit"] = unit["orbit"].duplicate(true)
	state["units"][host]["pos_mm"] = unit["pos_mm"].duplicate()
	unit["orbit"] = {}
	unit["dock"] = { "port": 0, "target_unit": host, "target_port": 0 }
	sim._ctx.index.clear()
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	return host


func test_a_docked_ship_measures_a_gravity_field_on_its_hosts_orbit() -> void:
	var ship := _small_world()
	var host := _docked_to_a_host(ship)
	var period: int = (state["units"][host]["orbit"]["period_subticks"] + OrbitMath.SUB_TICKS - 1) / OrbitMath.SUB_TICKS
	var start := sim.current_tick()
	assert_eq(_order(ship, "measure", { "target": keys["Planet"], "kind": "gravity_field" })["type"], "task_finished")
	assert_eq(sim.current_tick() - start, period + 1, "one lap of the host's orbit")
	assert_eq(state["science"]["paid"], { "gravity_field:%d" % keys["Planet"]: 1 })


func test_undocking_ends_a_gravity_field_taken_on_the_hosts_orbit() -> void:
	var ship := _small_world()
	var host := _docked_to_a_host(ship)
	sim.submit({ "type": "measure", "unit": ship, "args": { "target": keys["Planet"], "kind": "gravity_field" } })
	sim.step(50)
	var unit: Dictionary = state["units"][ship]
	unit["dock"] = {}
	unit["orbit"] = state["units"][host]["orbit"].duplicate(true)
	sim._ctx.index.clear()
	var ended := {}
	for i in 5:
		sim.step()
		for event in sim.take_events():
			if event["type"] == "task_cancelled":
				ended = event
	assert_eq(ended.get("data", {}).get("reason"), "orbit_changed", "the same orbit, but its own now")
	assert_eq(state["science"]["paid"], {})
