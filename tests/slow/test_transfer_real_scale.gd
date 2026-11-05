extends GutTest
## One autopilot transfer at the real scale (task A13): a Kerbin-gravity planet, 700 km to 900 km.
## Far starts where its window opens within a minute, but the flight is the real one. To keep the
## suite quick (A20), tests/sim/networks/test_transfers.gd runs everything else on a denser planet;
## this is the check that the quick version hides no scale bug.

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
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
				"frame": "home", "inventory": [{ "item": "propellant", "grams": 1_000_000 }], "dock": null },
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


func test_a_move_between_places_waits_flies_and_arrives() -> void:
	var quoted := sim.quote(keys["Ship"], keys["Rock"], 1)
	sim.submit(_move("Rock"))
	sim.step(2)
	assert_eq(_ship()["op"]["type"], MoveStep.OP_WAITING)
	assert_eq(_ship()["op"]["depart_tick"], quoted["depart_tick"])
	assert_eq(sim._state["sinks"].get(Travel.SINK, {}), {}, "nothing paid while waiting")
	sim.step(quoted["depart_tick"] - sim.current_tick())
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
