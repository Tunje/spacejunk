extends GutTest
## The autopilot's transfers (task A13, orbital_flight.md section 11): quote_trip, next_window and
## quote_leg, and a move_to between places that waits for its window, flies on rails and arrives.
##
## To keep the suite quick (A20) the planet has 100 times Kerbin's GM, so every period and flight is
## 10 times shorter, and Far starts where its window opens a few seconds in. One trip at the real
## scale, with its real wait, is in tests/slow/test_transfer_real_scale.gd.

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 353_160_000_000
## The same GM in m^3/s^2, for the float formulas the tests check against.
const MU_M3 := 3.5316e14
const PROPELLANT_G := 100_000_000
const AU_MM := 149_597_870_700_000
const ONE := OrbitMath.ONE

var sim: Sim
var keys := {}


func before_each() -> void:
	sim = _build()


## A planet with three small frames around it: Home at 700 km, Far at 900 km holding a rock, and
## Ahead in Home's ring, 20 degrees on. A ship sits in Home.
func _build(extra: Dictionary = {}) -> Sim:
	var defs := DataLoader.load_defs()
	var built := Sim.new()
	built._setup(Sim._new_state("reference", 7, defs), defs)
	var frame := func(key: String, a_mm: int, mean_mdeg: int) -> Dictionary:
		return { "key": key, "name": key.capitalize(), "radius_mm": 1_000_000,
			"orbit": { "parent": "planet", "a_mm": a_mm, "mean_anomaly_mdeg": mean_mdeg } }
	var scenario := {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM } },
			{ "key": "rock", "name": "Rock", "kind": "asteroid", "frame": "far", "pos_mm": [20_000_000, 0, 0],
				"radius_mm": 500_000, "visual_seed": 3, "deposits": [] },
			{ "key": "pebble", "name": "Pebble", "kind": "asteroid", "frame": "ahead", "pos_mm": [0, 0, 0],
				"radius_mm": 100_000, "visual_seed": 4, "deposits": [] },
		],
		"frames": [frame.call("home", 700_000_000, 0), frame.call("far", 900_000_000, 31_100),
			frame.call("ahead", 700_000_000, 20_000)],
		"units": [
			{ "key": "ship", "template": "starter_ship", "name": "Ship", "pos_mm": [150_000, 0, 0],
				"frame": "home", "inventory": [{ "item": "propellant", "grams": PROPELLANT_G }], "dock": null },
		],
	}
	scenario.merge(extra, true)
	assert_eq(ScenarioBuilder.populate(built._ctx, scenario, {}), "")
	built._strict = true
	keys = {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in built._state[table]:
			keys[built._state[table][id]["name"]] = id
	return built


func _ship() -> Dictionary:
	return sim._state["units"][keys["Ship"]]


func _move(target: String) -> Dictionary:
	return { "type": "move_to", "unit": keys["Ship"], "args": { "target": keys[target] } }


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> String: return e["type"])


func test_a_hohmann_quote_leaves_on_the_window() -> void:
	var quoted := Travel.quote_trip(sim._ctx, keys["Ship"], keys["Rock"], 0)
	assert_eq(quoted["kind"], Transfer.KIND, str(quoted))
	var expected := TAU * sqrt(pow(800_000.0, 3) / MU_M3) / 2.0 * Sim.TICKS_PER_SECOND
	assert_almost_eq(float(quoted["ticks"]), expected, 2.0, "half the transfer orbit's period")
	assert_eq(quoted["arrive_tick"], quoted["depart_tick"] + quoted["ticks"] - 1)
	# At departure the target leads by half a turn less its motion during the flight.
	var home: Dictionary = sim._state["frames"][keys["Home"]]["orbit"]
	var far: Dictionary = sim._state["frames"][keys["Far"]]["orbit"]
	var lead := (Transfer.angle_at(far, home, quoted["depart_tick"]) - Transfer.angle_at(home, home, quoted["depart_tick"])) \
		& OrbitMath.ANGLE_MASK
	var needed := (OrbitMath.HALF_TURN - Transfer.turn_in(far, quoted["ticks"])) & OrbitMath.ANGLE_MASK
	var off := absi(lead - needed)
	off = mini(off, OrbitMath.TURN - off)
	var per_tick := absi(Transfer.turn_in(home, 1) - Transfer.turn_in(far, 1))
	assert_lte(off, per_tick * 2, "within two ticks of relative motion of the exact window")
	var dv := 2_641_900_000.0  # 700 to 900 km at 100 times Kerbin's GM, both burns
	assert_almost_eq(float(quoted["dv_um_s"]), dv, dv * 0.01)


func test_next_window_respects_the_cap() -> void:
	var quoted := Travel.quote_trip(sim._ctx, keys["Ship"], keys["Rock"], 0)
	assert_eq(sim.next_window(keys["Ship"], keys["Rock"], 0, quoted["cost_g"] - 1), { "reason": "no_window" })
	assert_eq(sim.next_window(keys["Ship"], keys["Rock"], 0, quoted["cost_g"]), quoted)
	assert_eq(sim.quote(keys["Ship"], keys["Rock"], 0), quoted)
	var later := sim.quote(keys["Ship"], keys["Rock"], quoted["depart_tick"] + 1)
	assert_gt(later["depart_tick"], quoted["depart_tick"], "a missed window waits for the next")
	assert_eq(later["cost_g"], quoted["cost_g"], "every Hohmann window costs the same")


func test_a_move_between_places_waits_flies_and_arrives() -> void:
	var quoted := sim.quote(keys["Ship"], keys["Rock"], 1)
	sim.submit(_move("Rock"))
	sim.step(2)
	assert_eq(_ship()["op"]["type"], MoveStep.OP_WAITING)
	assert_eq(_ship()["op"]["depart_tick"], quoted["depart_tick"])
	assert_eq(sim._state["sinks"].get(Travel.SINK, {}), {}, "nothing paid while waiting")
	sim.take_events()
	sim.step(quoted["depart_tick"] - sim.current_tick())
	var departed: Array = sim.take_events().filter(func(e: Dictionary) -> bool: return e["type"] == "departed")
	assert_eq(departed.size(), 1, "departed fires once, on the window's tick (A34)")
	assert_eq(departed[0]["tick"], quoted["depart_tick"])
	assert_eq(departed[0]["unit"], keys["Ship"])
	assert_eq(departed[0]["data"], { "target": keys["Rock"], "arrive_tick": quoted["arrive_tick"] })
	assert_eq(_ship()["op"]["type"], MoveStep.OP_MOVING)
	assert_eq(_ship()["transfer"]["arrive_tick"], quoted["arrive_tick"])
	assert_eq(_ship()["frame"], 0, "off the frame and on rails")
	sim.step()
	assert_eq(sim._state["sinks"][Travel.SINK][Travel.PROPELLANT], quoted["cost_g"])
	sim.step(quoted["arrive_tick"] - 1 - sim.current_tick())
	# Just before arrival, how far is the transfer orbit from where the target's frame will be?
	var far: Dictionary = sim._state["frames"][keys["Far"]]
	var miss := IntMath.dist(OrbitMath.position_at(_ship()["orbit"], quoted["arrive_tick"]),
		OrbitMath.position_at(far["orbit"], quoted["arrive_tick"]))
	print("TRANSFER Hohmann 700 to 900 km: %d ticks, %d g, arrives %d km from the target frame" % [
		quoted["ticks"], quoted["cost_g"], miss / 1_000_000])
	assert_lt(miss, 100_000_000, "within 100 km before parking")
	sim.take_events()
	sim.step()
	assert_true(_types(sim.take_events()).has("arrived"))
	assert_eq(_ship()["frame"], keys["Far"])
	assert_eq(_ship()["at_target"], keys["Rock"])
	var gap := IntMath.dist(_ship()["pos_mm"], sim._state["bodies"][keys["Rock"]]["pos_mm"])
	assert_almost_eq(gap, 500_000 + Travel.STANDOFF_MM, 3, "parked at the standoff")
	sim.step(2)
	assert_eq(_ship()["task"], 0, "the step ends after arrival")
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
	assert_eq(ledger["violations"], PackedStringArray())


func test_stopping_while_waiting_costs_nothing() -> void:
	sim.submit(_move("Rock"))
	sim.step(5)
	assert_eq(_ship()["op"]["type"], MoveStep.OP_WAITING)
	sim.submit({ "type": "stop", "unit": keys["Ship"], "args": {} })
	sim.step(3)
	assert_eq(_ship()["task"], 0)
	assert_eq(_ship()["op"]["type"], "idle")
	assert_eq(_ship()["frame"], keys["Home"])
	assert_eq(sim._state["sinks"].get(Travel.SINK, {}), {})


func test_a_paid_transfer_is_atomic() -> void:
	var quoted := sim.quote(keys["Ship"], keys["Rock"], 1)
	sim.submit(_move("Rock"))
	sim.step(quoted["depart_tick"] + 10)
	sim.submit({ "type": "stop", "unit": keys["Ship"], "args": {} })
	sim.step(quoted["arrive_tick"] - sim.current_tick() + 3)
	assert_eq(_ship()["frame"], keys["Far"], "it still arrived")
	assert_eq(_ship()["transfer"], {})


func test_the_same_ring_uses_a_phasing_orbit_with_no_wait() -> void:
	var quoted := sim.quote(keys["Ship"], keys["Pebble"], 50)
	assert_eq(quoted["kind"], Transfer.KIND)
	assert_eq(quoted["depart_tick"], 50, "no window to wait for")
	var period := TAU * sqrt(pow(700_000.0, 3) / MU_M3) * Sim.TICKS_PER_SECOND
	print("TRANSFER phasing 20 degrees ahead in one ring: %d ticks (%.2f orbits), %d mm/s" % [
		quoted["ticks"], quoted["ticks"] / period, quoted["dv_um_s"] / 1000])
	assert_lt(quoted["ticks"], int(period * 2.0))
	sim.submit(_move("Pebble"))
	sim.step(quoted["arrive_tick"] + 3)
	assert_eq(_ship()["frame"], keys["Ahead"])
	assert_eq(_ship()["at_target"], keys["Pebble"])


func test_a_move_inside_one_frame_is_still_a_route() -> void:
	var defs := DataLoader.load_defs()
	sim = _build({ "bodies": _scenario_bodies_with_home_rock() })
	var quoted := sim.quote(keys["Ship"], keys["Home Rock"], 0)
	assert_eq(quoted["kind"], Travel.KIND_ROUTE)
	assert_eq(quoted["ticks"], 984, "today's trip, as in reference_scenario.md")
	assert_eq(quoted["depart_tick"], 0)


func _scenario_bodies_with_home_rock() -> Array:
	var bodies: Array = sim._state["bodies"].keys().map(func(_id: int) -> int: return 0)
	return [
		{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
			"visual_seed": 1, "deposits": [], "gm": GM_STAR },
		{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
			"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM } },
		{ "key": "rock", "name": "Home Rock", "kind": "asteroid", "frame": "home", "pos_mm": [50_000_000, 0, 0],
			"radius_mm": 500_000, "visual_seed": 3, "deposits": [] },
		{ "key": "pebble", "name": "Pebble", "kind": "asteroid", "frame": "ahead", "pos_mm": [0, 0, 0],
			"radius_mm": 100_000, "visual_seed": 4, "deposits": [] },
	]


func test_unsupported_trips_are_refused() -> void:
	assert_eq(sim.quote(keys["Ship"], keys["Planet"], 0), { "reason": "unsupported_orbit" }, "a body to orbit or land on")
	var far: Dictionary = sim._state["frames"][keys["Far"]]
	var dirs := OrbitMath.directions(OrbitMath.TURN / 36, 0, 0)  # 10 degrees inclined
	far["orbit"] = OrbitMath.make_orbit(GM_PLANET, 900_000_000, 0, dirs[0], dirs[1], 0, 0)
	far["orbit"]["parent"] = keys["Planet"]
	assert_eq(sim.quote(keys["Ship"], keys["Rock"], 0), { "reason": "unsupported_orbit" }, "another plane")


func test_quote_leg_prices_a_leg_from_elsewhere_at_any_mass() -> void:
	var back_light := Travel.quote_leg(sim._ctx, keys["Ship"], keys["Rock"], keys["Pebble"], 6_000_000, 0)
	var back_heavy := Travel.quote_leg(sim._ctx, keys["Ship"], keys["Rock"], keys["Pebble"], 8_000_000, 0)
	assert_eq(back_light["kind"], Transfer.KIND)
	assert_gt(back_heavy["cost_g"], back_light["cost_g"], "a full hold costs more to fly")
	assert_eq(back_heavy["depart_tick"], back_light["depart_tick"], "the window doesn't depend on mass")
	var here := Travel.quote_leg(sim._ctx, keys["Ship"], keys["Pebble"], keys["Pebble"], 6_000_000, 0)
	assert_eq(here["kind"], Travel.KIND_ROUTE)
	assert_eq(here["cost_g"], 0, "already there")


## A player's order without the propellant at its window ends there, as a route does, with nothing
## paid and the ship still at home. A cycle's step is held instead, and MoveStep.retry takes the next
## window; C's cycle tests cover that.
func test_missing_propellant_at_departure_ends_a_players_order() -> void:
	var first := sim.quote(keys["Ship"], keys["Rock"], 1)
	sim.submit(_move("Rock"))
	sim.step(first["depart_tick"] - 2)
	_ship()["inventory"]["propellant"] = 10
	sim._state["matter_start_g"] -= PROPELLANT_G - 10
	sim.take_events()
	sim.step(3)
	var reasons := sim.take_events().map(func(e: Dictionary) -> String: return e["data"].get("reason", ""))
	assert_true(reasons.has(MoveStep.REASON_NO_PROPELLANT), str(reasons))
	assert_eq(_ship()["transfer"], {})
	assert_eq(_ship()["frame"], keys["Home"])
	assert_eq(sim._state["sinks"].get(Travel.SINK, {}), {})


## A wait whose task is held at the window doesn't leave late: when it runs again it takes the next.
func test_a_missed_window_takes_the_next_one() -> void:
	var first := sim.quote(keys["Ship"], keys["Rock"], 1)
	sim.submit(_move("Rock"))
	sim.step(5)
	var task: Dictionary = sim._state["tasks"][_ship()["task"]]
	var depart: int = _ship()["op"]["depart_tick"]
	# Hold the task across its window, as an offline core would, then let it run again.
	task["state"] = "blocked"
	sim.step(depart + 3 - sim.current_tick())
	assert_eq(_ship()["transfer"], {}, "nothing left while held")
	task["state"] = "running"
	sim.step()
	assert_eq(_ship()["op"]["type"], MoveStep.OP_WAITING)
	assert_gt(_ship()["op"]["depart_tick"], first["depart_tick"], "the next window")


func test_save_and_load_while_waiting_and_in_flight_is_byte_exact() -> void:
	var quoted := sim.quote(keys["Ship"], keys["Rock"], 1)
	sim.submit(_move("Rock"))
	for at: int in [maxi(3, quoted["depart_tick"] - 10), quoted["depart_tick"] + 200]:
		sim.step(at - sim.current_tick())
		var saved := sim.to_save()
		var loaded := Sim.from_save(saved)
		assert_eq(loaded.to_save(), saved)
		var copy := Sim.from_save(saved)
		copy.step(quoted["arrive_tick"] - at + 3)
		var original := Sim.from_save(saved)
		original.step(quoted["arrive_tick"] - at + 3)
		assert_eq(copy.state_hash(), original.state_hash())
		assert_eq(copy._state["units"][keys["Ship"]]["frame"], keys["Far"])
