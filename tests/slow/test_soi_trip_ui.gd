extends GutTest
## D18: an autopilot trip across a sphere of influence (A18) on the map, on the real
## Sim, in A's compact system: a heavy central body, a home frame at 20,000 km and a
## moon at 30,000 km with a ring frame round it. Slow: the trip takes hours of game time.

const GM_ROOT := 100_000_000_000_000
const GM_MOON := 10_000_000_000

var main: Node
var bridge: SimBridge
var sim: Sim
var keys := {}


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = "reference"
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	var defs := DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "root", "name": "Root", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 5_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_ROOT },
			{ "key": "moon", "name": "Moon", "kind": "planet", "radius_mm": 100_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_MOON, "orbit": { "parent": "root", "a_mm": 30_000_000_000, "mean_anomaly_mdeg": 40_000 } },
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
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	bridge.start(sim)
	main.local_view.rebuild()


func _ship() -> Dictionary:
	return bridge.current_view["units"][keys["Ship"]]


func _run_to(tick: int) -> void:
	sim.step(tick - sim.current_tick())
	bridge.start(sim)
	main.local_view.refresh(0.016)
	main.system_map.refresh(0.0)


func _gap(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return sqrt(pow(a[0] - b[0], 2) + pow(a[1] - b[1], 2) + pow(a[2] - b[2], 2))


## The joins between a chain's pieces: each piece's last point and the next one's first.
func _joins(arc: Array[PackedFloat64Array], segments: int) -> Array[float]:
	var gaps: Array[float] = []
	var per := segments + 1
	for piece in range(1, arc.size() / per):
		gaps.append(_gap(arc[piece * per - 1], arc[piece * per]))
	return gaps


func test_the_trip_across_a_sphere_is_drawn_planned_then_flown() -> void:
	main.local_view.select("body", keys["Moon Rock"], 0)
	main.order_panel.refresh()
	assert_true(main.order_panel.press("Move to"))
	_run_to(2)
	assert_eq(_ship()["op"]["type"], "waiting")
	var plan: Dictionary = _ship()["op"]["plan"]
	assert_eq(plan["legs"].size(), 3, "out: Hohmann, hyperbola round the moon, phasing")
	main.toggle_map()
	main.system_map.refresh(0.0)
	assert_gt((main.system_map.routes.mesh as ImmediateMesh).get_surface_count(), 0, "the planned arc while waiting")
	var planned := SystemMap.plan_arc(bridge.current_view, plan, 16)
	assert_eq(planned.size(), 3 * 17)
	for gap: float in _joins(planned, 16):
		assert_lt(gap, 2_000_000.0, "each leg starts where the last one ends (within 2 km)")
	_run_to(plan["depart_tick"] + 5)
	var transfer: Dictionary = _ship()["transfer"]
	assert_false(transfer.is_empty())
	assert_eq(transfer["legs"].size(), 2, "the legs still to come")
	var flown := SystemMap.transfer_arc(bridge.current_view, _ship(), 16)
	var ship_world := OrbitPath.shifted(WorldPosition.of(_ship()), [0, 0, 0])
	assert_lt(_gap(flown[0], ship_world), 1_000_000.0, "the arc starts at the ship")
	for gap: float in _joins(flown, 16):
		assert_lt(gap, 2_000_000.0, "and runs on through each leg")
	assert_string_starts_with(InspectText.status(_ship(), bridge.current_view), "Transfer ")
	var second: int = transfer["legs"][0]["from_tick"]
	_run_to(second + 5)
	assert_eq(_ship()["orbit"]["parent"], keys["Moon"], "riding the leg round the moon")
	assert_eq(SystemMap.transfer_arc(bridge.current_view, _ship(), 16).size(), 2 * 17, "two pieces left")
	_run_to(transfer["arrive_tick"] + 2)
	assert_true(_ship()["transfer"].is_empty())
	assert_eq(_ship()["frame"], keys["Ring"], "arrived in the moon's ring")
