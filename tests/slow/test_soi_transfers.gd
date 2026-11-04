extends GutTest
## Autopilot trips across spheres of influence (task A18): out from an orbit around the central
## body to a ring around its moon, and back. A compact system keeps the trips to hours of game time:
## a heavy central body, a home frame at 20,000 km and a moon at 30,000 km. In tests/slow because
## the trips step about 250,000 ticks between them.

const GM_ROOT := 100_000_000_000_000  # 1e17 m^3/s^2 in units of 1000 m^3/s^2
const GM_MOON := 10_000_000_000       # 1e13 m^3/s^2
const ONE := OrbitMath.ONE

var sim: Sim
var keys := {}


func before_each() -> void:
	var defs := DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "root", "name": "Root", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 5_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_ROOT },
			{ "key": "moon", "name": "Moon", "kind": "planet", "radius_mm": 100_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_MOON, "orbit": { "parent": "root", "a_mm": 30_000_000_000, "mean_anomaly_mdeg": 40_000 } },
			{ "key": "home_rock", "name": "Home Rock", "kind": "asteroid", "frame": "home", "pos_mm": [20_000_000, 0, 0],
				"radius_mm": 300_000, "visual_seed": 3, "deposits": [] },
			{ "key": "moon_rock", "name": "Moon Rock", "kind": "asteroid", "frame": "ring", "pos_mm": [20_000_000, 0, 0],
				"radius_mm": 300_000, "visual_seed": 4, "deposits": [] },
		],
		"frames": [
			{ "key": "home", "name": "Home", "radius_mm": 1_000_000, "orbit": { "parent": "root", "a_mm": 20_000_000_000 } },
			{ "key": "ring", "name": "Ring", "radius_mm": 1_000_000,
				"orbit": { "parent": "moon", "a_mm": 300_000_000, "mean_anomaly_mdeg": 200_000 } },
		],
		"units": [
			{ "key": "ship", "template": "starter_ship", "name": "Ship", "pos_mm": [150_000, 0, 0], "frame": "home",
				"inventory": [{ "item": "propellant", "grams": 4_000_000_000 }], "dock": null },
		],
	}, {}), "")
	sim._strict = true
	keys = {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id


func _ship() -> Dictionary:
	return sim._state["units"][keys["Ship"]]


## Flies a move_to and returns the largest step in world position between ticks, as
## { arrived, largest_mm, largest_tick, typical_mm, snap_mm }, where snap is the arrival tick's step.
func _fly(target: String) -> Dictionary:
	var quoted := sim.quote(keys["Ship"], keys[target], sim.current_tick() + 1)
	assert_eq(quoted.get("kind", ""), Transfer.KIND, str(quoted))
	sim.submit({ "type": "move_to", "unit": keys["Ship"], "args": { "target": keys[target] } })
	sim.step(quoted["depart_tick"] - sim.current_tick())
	var last := RailSystem.world_mm(sim._state, "units", keys["Ship"])
	var largest := 0
	var largest_tick := 0
	var total := 0
	var count := 0
	var snap := 0
	var arrived := false
	while sim.current_tick() < quoted["arrive_tick"] + 2:
		sim.step()
		var here := RailSystem.world_mm(sim._state, "units", keys["Ship"])
		var moved := IntMath.dist(here, last)
		last = here
		var events := sim.take_events()
		if events.any(func(e: Dictionary) -> bool: return e["type"] == "arrived"):
			arrived = true
			snap = moved
			continue
		total += moved
		count += 1
		if moved > largest:
			largest = moved
			largest_tick = sim.current_tick()
	return { "arrived": arrived, "largest_mm": largest, "largest_tick": largest_tick,
		"typical_mm": total / maxi(1, count), "snap_mm": snap, "quote": quoted }


func test_a_trip_out_to_a_moon_ring() -> void:
	var flown := _fly("Moon Rock")
	var quoted: Dictionary = flown["quote"]
	print("SOI out: depart %d, %d ticks, %d m/s, %d kg; largest tick step %d km (typical %d km), arrival snap %d km" % [
		quoted["depart_tick"], quoted["ticks"], quoted["dv_um_s"] / 1_000_000, quoted["cost_g"] / 1000,
		flown["largest_mm"] / 1_000_000, flown["typical_mm"] / 1_000_000, flown["snap_mm"] / 1_000_000])
	assert_true(flown["arrived"])
	assert_eq(_ship()["frame"], keys["Ring"])
	assert_eq(_ship()["at_target"], keys["Moon Rock"])
	assert_lt(flown["largest_mm"], flown["typical_mm"] * 4, "no jump between legs")
	assert_lt(flown["snap_mm"], 200_000_000, "parks within 200 km of where the path ends")
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
	assert_eq(ledger["violations"], PackedStringArray())


func test_a_trip_back_from_the_moon_ring() -> void:
	_fly("Moon Rock")
	sim.step(3)
	# Refill: the compact system's speeds make the way out cost most of the tank.
	var inventory: Dictionary = _ship()["inventory"]
	sim._state["matter_start_g"] += 4_000_000_000 - inventory["propellant"]
	inventory["propellant"] = 4_000_000_000
	var flown := _fly("Home Rock")
	var quoted: Dictionary = flown["quote"]
	print("SOI back: depart %d, %d ticks, %d m/s, %d kg; largest tick step %d km (typical %d km), arrival snap %d km" % [
		quoted["depart_tick"], quoted["ticks"], quoted["dv_um_s"] / 1_000_000, quoted["cost_g"] / 1000,
		flown["largest_mm"] / 1_000_000, flown["typical_mm"] / 1_000_000, flown["snap_mm"] / 1_000_000])
	assert_true(flown["arrived"])
	assert_eq(_ship()["frame"], keys["Home"])
	assert_lt(flown["largest_mm"], flown["typical_mm"] * 4, "no jump between legs")
	assert_lt(flown["snap_mm"], 200_000_000, "parks within 200 km of where the path ends")


func test_quotes_across_spheres_are_stable_and_saved_mid_flight() -> void:
	var quoted := sim.quote(keys["Ship"], keys["Moon Rock"], 1)
	assert_eq(sim.quote(keys["Ship"], keys["Moon Rock"], 1), quoted, "the same quote twice")
	sim.submit({ "type": "move_to", "unit": keys["Ship"], "args": { "target": keys["Moon Rock"] } })
	sim.step(quoted["depart_tick"] + (quoted["ticks"] * 3) / 4 - sim.current_tick())
	var saved := sim.to_save()
	var loaded := Sim.from_save(saved)
	assert_eq(loaded.to_save(), saved)
	sim.step(quoted["ticks"] / 2)
	loaded.step(quoted["ticks"] / 2)
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_eq(sim._state["units"][keys["Ship"]]["frame"], keys["Ring"])


func test_a_target_two_levels_away_is_refused() -> void:
	var ring: Dictionary = sim._state["frames"][keys["Ring"]]
	var moon_orbit: Dictionary = sim._state["bodies"][keys["Moon"]]["orbit"]
	# A ring around the root's parent's grandchild doesn't exist here; fake one by parenting the
	# target ring to a body with no orbit of its own above the root.
	ring["orbit"]["parent"] = keys["Home Rock"]
	assert_eq(sim.quote(keys["Ship"], keys["Moon Rock"], 0), { "reason": "unsupported_orbit" })
	ring["orbit"]["parent"] = keys["Moon"]
	assert_eq(moon_orbit["parent"], keys["Root"])
