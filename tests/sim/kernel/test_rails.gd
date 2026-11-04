extends GutTest
## Bodies, frames and units on rails (task A10, orbital_flight.md section 11): orbits in the
## state, the co-moving frame, world positions, travel inside a frame, and saves.

const AU_MM := 149_597_870_700_000
const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const GM_MOON := 65_138_398

var sim: Sim
var keys := {}


func before_each() -> void:
	sim = _build(_scenario())


## A world in sim units: a star, a planet with a moon, and a rock cluster in solar orbit holding
## a station with a docked ship, and a scout.
func _scenario() -> Dictionary:
	return {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET,
				"orbit": { "parent": "star", "a_mm": AU_MM, "e_ppm": 16_700, "inclination_mdeg": 1000,
					"mean_anomaly_mdeg": 90_000 } },
			{ "key": "moon", "name": "Moon", "kind": "planet", "radius_mm": 200_000_000, "visual_seed": 3,
				"deposits": [], "gm": GM_MOON, "orbit": { "parent": "planet", "a_mm": 12_000_000_000 } },
			{ "key": "rock", "name": "Red Rock", "kind": "asteroid", "frame": "cluster",
				"pos_mm": [50_000_000, 0, 0], "radius_mm": 500_000, "visual_seed": 4, "deposits": ["hematite_deposit"] },
		],
		"frames": [
			{ "key": "cluster", "name": "Cluster", "radius_mm": 1_000_000_000,
				"orbit": { "parent": "star", "a_mm": AU_MM, "mean_anomaly_mdeg": 10_000 } },
		],
		"units": [
			{ "key": "station", "template": "starter_station", "name": "Station", "pos_mm": [0, 0, 0],
				"frame": "cluster", "inventory": [], "dock": null },
			{ "key": "ship", "template": "starter_ship", "name": "Probe", "pos_mm": [0, 0, 0],
				"inventory": [], "dock": { "host": "station", "port": 0, "host_port": 1 } },
			{ "key": "scout", "template": "starter_ship", "name": "Scout", "pos_mm": [150_000, 0, 0],
				"frame": "cluster", "inventory": [{ "item": "propellant", "grams": 1_000_000 }], "dock": null },
		],
	}


func _build(scenario: Dictionary) -> Sim:
	var defs := DataLoader.load_defs()
	var built := Sim.new()
	built._setup(Sim._new_state("reference", 7, defs), defs)
	var problem := ScenarioBuilder.populate(built._ctx, scenario, DataLoader.load_deposits())
	assert_eq(problem, "", "the scenario builds")
	built._strict = true
	keys = {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in built._state[table]:
			keys[built._state[table][id]["name"]] = id
	return built


func _orbit_of(name: String) -> Dictionary:
	var id: int = keys[name]
	return sim._state["frames"][id]["orbit"] if sim._state["frames"].has(id) else sim._state["bodies"][id]["orbit"]


func test_ids_follow_bodies_then_frames_then_units() -> void:
	assert_eq(keys["Star"], 1)
	assert_eq(keys["Red Rock"], 4)
	assert_eq(keys["Cluster"], 6, "after the rock's deposit")
	assert_eq(keys["Station"], 7)


func test_orbiting_bodies_and_frames_move_on_rails() -> void:
	for ticks in [1, 9, 990]:
		sim.step(ticks)
		var tick := sim.current_tick()
		for name: String in ["Planet", "Moon", "Cluster"]:
			var table := "frames" if name == "Cluster" else "bodies"
			assert_eq(sim._state[table][keys[name]]["pos_mm"], OrbitMath.position_at(_orbit_of(name), tick), name)
	assert_eq(sim._state["bodies"][keys["Star"]]["pos_mm"], [0, 0, 0], "the root stays put")
	assert_eq(sim._state["bodies"][keys["Red Rock"]]["pos_mm"], [50_000_000, 0, 0], "frame members keep their local place")


func test_world_positions_add_up_the_chain() -> void:
	sim.step(37)
	var state := sim._state
	var planet: Array = state["bodies"][keys["Planet"]]["pos_mm"]
	var moon: Array = state["bodies"][keys["Moon"]]["pos_mm"]
	var cluster: Array = state["frames"][keys["Cluster"]]["pos_mm"]
	assert_eq(RailSystem.world_mm(state, "bodies", keys["Moon"]),
		[planet[0] + moon[0], planet[1] + moon[1], planet[2] + moon[2]])
	assert_eq(RailSystem.world_mm(state, "units", keys["Scout"]),
		[cluster[0] + 150_000, cluster[1], cluster[2]])
	assert_eq(RailSystem.world_mm(state, "units", keys["Probe"]), RailSystem.world_mm(state, "units", keys["Station"]),
		"a docked unit is where its host is")


func test_a_docked_unit_is_in_its_hosts_frame() -> void:
	assert_eq(sim._state["units"][keys["Probe"]]["frame"], 0, "nothing stored on the docked unit")
	assert_eq(RailSystem.unit_place(sim._state, keys["Probe"]), keys["Cluster"])
	assert_eq(sim.view()["units"][keys["Probe"]]["frame"], keys["Cluster"])


func test_move_to_inside_the_frame_is_todays_trip() -> void:
	var command := { "type": "move_to", "unit": keys["Scout"], "args": { "target": keys["Red Rock"] } }
	var checked := sim.check(command)
	assert_true(checked["ok"], str(checked))
	var quoted := Travel.quote(sim._ctx, keys["Scout"], keys["Red Rock"])
	assert_eq(quoted["to_mm"], [49_350_000, 0, 0], "stop point as in reference_scenario.md")
	assert_eq(quoted["ticks"], 984)
	sim.submit(command)
	sim.step(quoted["ticks"] + 1)
	var scout: Dictionary = sim._state["units"][keys["Scout"]]
	assert_eq(scout["pos_mm"], [49_350_000, 0, 0])
	assert_eq(scout["at_target"], keys["Red Rock"])
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_move_to_outside_the_frame_waits_for_the_planner() -> void:
	for target: String in ["Planet", "Moon", "Star"]:
		var checked := sim.check({ "type": "move_to", "unit": keys["Scout"], "args": { "target": keys[target] } })
		assert_false(checked["ok"], target)
		assert_eq(checked["reason"], Travel.REASON_OTHER_PLACE, target)


func test_save_and_load_midway_through_a_trip_is_byte_exact() -> void:
	sim.submit({ "type": "move_to", "unit": keys["Scout"], "args": { "target": keys["Red Rock"] } })
	sim.step(400)
	var saved := sim.to_save()
	var loaded := Sim.from_save(saved)
	assert_not_null(loaded, Sim.last_error())
	assert_eq(loaded.to_save(), saved, "save, load, save is identical")
	sim.step(800)
	loaded.step(800)
	assert_eq(loaded.state_hash(), sim.state_hash(), "a loaded game runs on identically")
	assert_eq(loaded._state["frames"][keys["Cluster"]]["pos_mm"], OrbitMath.position_at(_orbit_of("Cluster"), 1200))


func test_state_stays_inside_its_ranges() -> void:
	sim.step(50)
	assert_eq(sim.ledger()["violations"], PackedStringArray())
	var orbit: Dictionary = _orbit_of("Planet")
	assert_lt(orbit["e_q30"], OrbitMath.ONE)
	assert_between(orbit["m0_angle"], 0, OrbitMath.ANGLE_MASK)


func test_the_view_shows_frames_orbits_and_world_positions() -> void:
	sim.step(3)
	var view := sim.view()
	var frame: Dictionary = view["frames"][keys["Cluster"]]
	assert_eq(frame["world_mm"], frame["pos_mm"], "the cluster orbits the star at the origin")
	assert_eq(frame["radius_mm"], 1_000_000_000)
	assert_eq(view["bodies"][keys["Planet"]]["orbit"]["parent"], keys["Star"])
	assert_eq(view["bodies"][keys["Red Rock"]]["frame"], keys["Cluster"])
	assert_eq(view["bodies"][keys["Planet"]]["gm"], GM_PLANET)
	assert_eq(view["units"][keys["Scout"]]["world_mm"], RailSystem.world_mm(sim._state, "units", keys["Scout"]))
	assert_ne(Canon.encode(view), "", "the view is plain data")


func test_a_bad_scenario_is_refused() -> void:
	var defs := DataLoader.load_defs()
	var cases := {
		"orbits a body with no gravity": func(s: Dictionary) -> void: s["bodies"][2]["orbit"]["parent"] = "rock",
		"unknown frame": func(s: Dictionary) -> void: s["units"][2]["frame"] = "nowhere",
		"frame with no parent gravity": func(s: Dictionary) -> void: s["frames"][0]["orbit"]["parent"] = "nobody",
	}
	for label: String in cases:
		var scenario := _scenario()
		cases[label].call(scenario)
		var built := Sim.new()
		built._setup(Sim._new_state("reference", 7, defs), defs)
		assert_ne(ScenarioBuilder.populate(built._ctx, scenario, DataLoader.load_deposits()), "", label)


func test_an_old_save_is_a_version_mismatch() -> void:
	var state: Dictionary = Canon.decode(sim.to_save())
	state["contract_version"] = 2
	state.erase("frames")
	assert_null(Sim.from_save(Canon.encode(state)))
	assert_eq(Sim.last_error(), Sim.ERROR_VERSION_MISMATCH)


func test_the_reference_scenario_is_unchanged_in_the_old_world() -> void:
	var reference := Sim.new_game("reference", 12345)
	assert_eq(reference._state["frames"], {})
	for id: int in reference._state["units"]:
		assert_eq(RailSystem.unit_place(reference._state, id), 0)


func test_the_loader_converts_gm_and_thrust_exactly() -> void:
	var converted := DataLoader._convert_map({ "gm_km3_s2": 132712440018.0, "thrust_kn": 0.15,
		"exhaust_m_s": 3000.0 }, "test")
	assert_eq(converted["gm"], GM_STAR, "the star's GM, exact beyond 2^53")
	assert_eq(converted["thrust_n"], 150)
	assert_eq(converted["exhaust_mm_s"], 3_000_000)
	assert_eq(DataLoader._convert_map({ "gm_km3_s2": 3531.6 }, "test")["gm"], GM_PLANET)
