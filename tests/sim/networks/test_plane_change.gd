extends GutTest
## Plane changes on autopilot trips (task A41a, orbital_flight.md 11.28). A trip between
## near-circular orbits round one parent, in planes more than a degree apart, rides to the line of
## nodes, burns onto the circle in the target's plane there, then makes the coplanar trip. The
## planet is test_transfers.gd's, at 100 times Kerbin's GM, so orbits are quick and fast: 22 km/s
## at 700 km, so only small angles are flown.

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 353_160_000_000
const MU_M3 := 3.5316e14
const PROPELLANT_G := 100_000_000
const AU_MM := 149_597_870_700_000

var sim: Sim
var keys := {}


## Home at 700 km in the planet's equator, holding a stone. Far at 900 km holding a rock and Ring
## at 700 km holding a pebble, both tilted by `tilt_mdeg` about a node line `node_mdeg` round. The
## ship starts in `ship_frame`.
func _build(tilt_mdeg: int, node_mdeg: int = 40_000, ship_frame: String = "home") -> Sim:
	var defs := DataLoader.load_defs()
	var built := Sim.new()
	built._setup(Sim._new_state("reference", 7, defs), defs)
	var tilted := func(key: String, a_mm: int, mean_mdeg: int) -> Dictionary:
		return { "key": key, "name": key.capitalize(), "radius_mm": 1_000_000, "orbit": { "parent": "planet",
			"a_mm": a_mm, "mean_anomaly_mdeg": mean_mdeg, "inclination_mdeg": tilt_mdeg, "node_mdeg": node_mdeg } }
	assert_eq(ScenarioBuilder.populate(built._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM } },
			{ "key": "rock", "name": "Rock", "kind": "asteroid", "frame": "far", "pos_mm": [20_000_000, 0, 0],
				"radius_mm": 500_000, "visual_seed": 3, "deposits": [] },
			{ "key": "pebble", "name": "Pebble", "kind": "asteroid", "frame": "ring", "pos_mm": [0, 0, 0],
				"radius_mm": 100_000, "visual_seed": 4, "deposits": [] },
			{ "key": "stone", "name": "Stone", "kind": "asteroid", "frame": "home", "pos_mm": [-20_000_000, 0, 0],
				"radius_mm": 100_000, "visual_seed": 5, "deposits": [] },
		],
		"frames": [
			{ "key": "home", "name": "Home", "radius_mm": 1_000_000,
				"orbit": { "parent": "planet", "a_mm": 700_000_000, "mean_anomaly_mdeg": 0 } },
			tilted.call("far", 900_000_000, 31_100), tilted.call("ring", 700_000_000, 200_000),
		],
		"units": [
			{ "key": "ship", "template": "starter_ship", "name": "Ship", "pos_mm": [150_000, 0, 0],
				"frame": ship_frame, "inventory": [{ "item": "propellant", "grams": PROPELLANT_G }], "dock": null },
		],
	}, {}), "")
	keys = {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in built._state[table]:
			keys[built._state[table][id]["name"]] = id
	return built


func _ship() -> Dictionary:
	return sim._state["units"][keys["Ship"]]


## 2 v sin(θ/2), in um/s, for a pure plane change of θ on a circle of radius r.
func _expected_change(r_mm: int, tilt_mdeg: int) -> float:
	var v := sqrt(MU_M3 / (r_mm / 1000.0)) * 1_000_000.0
	return 2.0 * v * sin(deg_to_rad(tilt_mdeg / 1000.0) / 2.0)


## A41a's plan on its own: the plane change at the start, on the unit's circle. Since A41b the
## quote may take the combined plan instead, which test_the_quote_takes_the_cheaper_plane_change
## covers, so this checks A41a's plan directly.
func test_a_trip_to_another_plane_is_quoted_with_its_plane_change() -> void:
	for tilt_mdeg: int in [3_000, 10_000, 30_000, 60_000, 170_000]:
		sim = _build(tilt_mdeg)
		var quoted: Dictionary = _both("Rock")[0]
		assert_eq(quoted.get("kind", ""), Transfer.KIND, "%d mdeg: %s" % [tilt_mdeg, str(quoted)])
		if quoted.get("kind", "") != Transfer.KIND:
			continue
		var change: int = quoted["plane_change_dv_um_s"]
		assert_almost_eq(float(change), _expected_change(700_000_000, tilt_mdeg),
			_expected_change(700_000_000, tilt_mdeg) * 0.01 + 50_000.0, "2 v sin(θ/2) at %d mdeg" % tilt_mdeg)
		assert_gt(quoted["dv_um_s"], change, "plus the Hohmann burns")
		var legs: Array = quoted["legs"]
		assert_eq(legs.size(), 2)
		assert_eq(legs[0]["from_tick"], quoted["depart_tick"], "it leaves on the node")
		assert_lt(legs[0]["from_tick"], legs[1]["from_tick"])
		# The circle is in the target's plane, and the burn point is on the line of nodes.
		var far: Dictionary = sim._state["frames"][keys["Far"]]["orbit"]
		var normal := OrbitMath.unit(OrbitMath.cross(far["p_q30"], far["q_q30"]))
		var circle: Dictionary = legs[0]["orbit"]
		assert_gte(OrbitMath.dot(OrbitMath.unit(OrbitMath.cross(circle["p_q30"], circle["q_q30"])), normal),
			Transfer.MIN_COPLANAR_Q30, "the circle is in the target's plane")
		var home: Dictionary = sim._state["frames"][keys["Home"]]["orbit"]
		var jump := IntMath.dist(OrbitMath.position_at(home, quoted["depart_tick"]),
			OrbitMath.position_at(circle, quoted["depart_tick"]))
		assert_lt(jump, 3_000_000, "a jump of at most one tick's motion: %d mm" % jump)


func test_coplanar_trips_still_quote_no_plane_change() -> void:
	sim = _build(0)
	var quoted := Travel.quote_trip(sim._ctx, keys["Ship"], keys["Rock"], 0)
	assert_eq(quoted["plane_change_dv_um_s"], 0)
	assert_false(quoted.has("legs"), "one leg, as before")
	sim = _build(500)
	assert_eq(Travel.quote_trip(sim._ctx, keys["Ship"], keys["Rock"], 0)["plane_change_dv_um_s"], 0,
		"half a degree counts as one plane")


func test_a_tilted_trip_flies_and_arrives_for_its_quoted_price() -> void:
	sim = _build(3_000)
	sim._strict = true
	var quoted := Travel.quote_trip(sim._ctx, keys["Ship"], keys["Rock"], 0)
	assert_lt(quoted["cost_g"], PROPELLANT_G, str(quoted))
	sim.submit({ "type": "move_to", "unit": keys["Ship"], "args": { "target": keys["Rock"] } })
	sim.step(quoted["arrive_tick"] + 5)
	var types := sim.take_events().map(func(e: Dictionary) -> String: return e["type"])
	assert_has(types, "departed")
	assert_has(types, "arrived")
	assert_eq(_ship()["frame"], keys["Far"], "in the tilted frame")
	assert_eq(PROPELLANT_G - int(_ship()["inventory"]["propellant"]), quoted["cost_g"], "paid what was quoted")
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
	assert_eq(ledger["violations"], PackedStringArray())


func test_a_tilted_trip_coasts_and_saves_exactly() -> void:
	sim = _build(10_000)
	var quoted := Travel.quote_trip(sim._ctx, keys["Ship"], keys["Pebble"], 0)
	assert_gt(quoted["plane_change_dv_um_s"], 0, str(quoted))
	sim.submit({ "type": "move_to", "unit": keys["Ship"], "args": { "target": keys["Pebble"] } })
	var coasted := Sim.from_save(sim.to_save())
	var ticks: int = quoted["arrive_tick"] + 5
	# A save halfway between the node and the arrival loads and plays the same.
	var mid: int = (quoted["depart_tick"] + quoted["arrive_tick"]) / 2
	sim.step(mid)
	var loaded := Sim.from_save(sim.to_save())
	assert_eq(loaded.to_save(), sim.to_save(), "byte-exact mid-trip")
	assert_false(sim._state["units"][keys["Ship"]]["transfer"].is_empty(), "under way at the save")
	sim.step(ticks - mid)
	loaded.step(ticks - mid)
	assert_eq(loaded.to_save(), sim.to_save(), "the same play after the load")
	var calls := 0
	var caps := {}
	while coasted.current_tick() < ticks:
		var done: Dictionary = coasted.coast(ticks - coasted.current_tick())
		caps[done["capped_by"]] = caps.get(done["capped_by"], 0) + 1
		calls += 1
	gut.p("coast calls %d, capped by %s" % [calls, str(caps)])
	assert_eq(coasted.to_save(), sim.to_save(), "coasted the same, byte for byte")
	assert_eq(sim._state["units"][keys["Ship"]]["frame"], keys["Ring"], "arrived in the tilted ring")
	# The legs and the node coast. The rest are the shadow edges of this fast, low orbit, which a
	# coplanar lap meets the same way.
	assert_lt(calls - int(caps.get("power", 0)), 20, "the legs coast")


## Both plans for the ship's trip to `target` from tick 0, as [A41a's, A41b's].
func _both(target: String) -> Array:
	var ship: int = keys["Ship"]
	var mine := Transfer.unit_orbit(sim._ctx, ship)
	var theirs := Transfer.target_orbit(sim._ctx, keys[target])
	var gm: int = sim._state["bodies"][keys["Planet"]]["gm"]
	var found := BurnSystem.thruster(sim._ctx, ship)
	var mass := Units.unit_mass(sim._state, sim._ctx.defs, ship)
	return [Transfer._plane_change_plan(mine, theirs, keys[target], gm, mass, 0, found),
		Transfer._combined_plan(mine, theirs, keys[target], gm, mass, 0, found)]


## A41b: the quote takes the cheaper of the two ways to change plane, ties to A41a's, up and down,
## from small angles to large and between rings and on one.
func test_the_quote_takes_the_cheaper_plane_change() -> void:
	var picked := {}
	for case: Array in [["home", "Rock"], ["home", "Pebble"], ["far", "Stone"]]:
		for tilt_mdeg: int in [3_000, 10_000, 30_000, 60_000]:
			sim = _build(tilt_mdeg, 40_000, case[0])
			var plans := _both(case[1])
			var quoted := Travel.quote_trip(sim._ctx, keys["Ship"], keys[case[1]], 0)
			var low: Dictionary = plans[0]
			var high: Dictionary = plans[1]
			var label := "%s to %s at %d mdeg" % [case[0], case[1], tilt_mdeg]
			assert_eq(quoted["cost_g"], mini(low["cost_g"], high["cost_g"]), label)
			var expected: String = "start" if low["cost_g"] <= high["cost_g"] else high["plane_change_at"]
			assert_eq(quoted["plane_change_at"], expected, label)
			picked[quoted["plane_change_at"]] = true
			gut.p("%s: A41a %d kg in %d ticks, A41b %d kg in %d ticks" % [label, low["cost_g"] / 1000, low["ticks"],
				high["cost_g"] / 1000, high["ticks"]])
	assert_has(picked, "start", "small angles and one ring stay with A41a")
	assert_has(picked, "arrival", "going up, the plane change joins the far burn")
	assert_has(picked, "departure", "going down, it joins the departure burn")


## A41b's combined burn going up is the vector difference at the far node: the law of cosines
## between the ellipse's speed there and the ring's, at the angle between the planes.
func test_the_combined_burn_is_the_law_of_cosines() -> void:
	var tilt_mdeg := 30_000
	sim = _build(tilt_mdeg)
	var high: Dictionary = _both("Rock")[1]
	var r1 := 700_000.0
	var r2 := 900_000.0
	var a_t := (r1 + r2) / 2.0
	var v_apo := sqrt(MU_M3 * (2.0 / r2 - 1.0 / a_t))
	var v_ring := sqrt(MU_M3 / r2)
	var angle := deg_to_rad(tilt_mdeg / 1000.0)
	var combined := sqrt(v_apo * v_apo + v_ring * v_ring - 2.0 * v_apo * v_ring * cos(angle)) * 1_000_000.0
	var coplanar := (v_ring - v_apo) * 1_000_000.0
	assert_almost_eq(float(high["plane_change_dv_um_s"]), combined - coplanar, (combined - coplanar) * 0.01,
		"the burn beyond the coplanar circularisation")
	assert_eq(high["legs"].size(), 3, "the ellipse, the ring and the phasing orbit")


## A41b flown: the trip the quote picks at 10 degrees up to Far arrives in the tilted frame and pays
## exactly its quote, and a save mid-trip loads and plays the same, and coasting it is exact.
func test_a_combined_trip_flies_saves_and_coasts_exactly() -> void:
	sim = _build(10_000)
	var quoted := Travel.quote_trip(sim._ctx, keys["Ship"], keys["Rock"], 0)
	assert_eq(quoted["plane_change_at"], "arrival", str(quoted))
	assert_lt(quoted["cost_g"], PROPELLANT_G, "affordable")
	sim.submit({ "type": "move_to", "unit": keys["Ship"], "args": { "target": keys["Rock"] } })
	var coasted := Sim.from_save(sim.to_save())
	var ticks: int = quoted["arrive_tick"] + 5
	var mid: int = (quoted["depart_tick"] + quoted["arrive_tick"]) / 2
	sim._strict = true
	sim.step(mid)
	var loaded := Sim.from_save(sim.to_save())
	assert_eq(loaded.to_save(), sim.to_save(), "byte-exact mid-trip")
	sim.step(ticks - mid)
	loaded.step(ticks - mid)
	assert_eq(loaded.to_save(), sim.to_save(), "the same play after the load")
	while coasted.current_tick() < ticks:
		coasted.coast(ticks - coasted.current_tick())
	assert_eq(coasted.to_save(), sim.to_save(), "coasted the same, byte for byte")
	assert_eq(_ship()["frame"], keys["Far"], "arrived in the tilted frame")
	assert_eq(PROPELLANT_G - int(_ship()["inventory"]["propellant"]), quoted["cost_g"], "paid what was quoted")
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
	assert_eq(ledger["violations"], PackedStringArray())

