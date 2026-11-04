extends GutTest
## D15: the client on A13's autopilot transfers, on the real Sim: a ship in one
## frame round a planet told to Move to a rock in another frame waits for its
## window, then rides a transfer orbit on rails and arrives.

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const AU_MM := 149_597_870_700_000

var main: Node
var bridge: SimBridge
var sim: Sim
var keys := {}


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	var defs := DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	var frame := func(key: String, a_mm: int, mean_mdeg: int) -> Dictionary:
		return { "key": key, "name": key.capitalize(), "radius_mm": 1_000_000,
			"orbit": { "parent": "planet", "a_mm": a_mm, "mean_anomaly_mdeg": mean_mdeg } }
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM } },
			{ "key": "rock", "name": "Rock", "kind": "asteroid", "frame": "far", "pos_mm": [20_000_000, 0, 0],
				"radius_mm": 500_000, "visual_seed": 3, "deposits": [] },
		],
		"frames": [frame.call("home", 700_000_000, 0), frame.call("far", 900_000_000, 123_000)],
		"units": [
			{ "key": "ship", "template": "starter_ship", "name": "Ship", "pos_mm": [150_000, 0, 0],
				"frame": "home", "inventory": [{ "item": "propellant", "grams": 1_000_000 }], "dock": null },
		],
	}, {}), "")
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	bridge.start(sim)
	main.local_view.rebuild()


func _ship() -> Dictionary:
	return bridge.current_view["units"][keys["Ship"]]


## Runs the sim straight to a tick, then lets the client see it.
func _run_to(tick: int) -> void:
	sim.step(tick - sim.current_tick())
	bridge.start(sim)
	main.local_view.refresh(0.016)


func test_the_map_quotes_the_window_and_the_trip() -> void:
	main.local_view.select("body", keys["Rock"], 0)
	main.toggle_map()
	var quote := sim.quote(keys["Ship"], keys["Rock"], sim.current_tick())
	assert_eq(quote["kind"], "transfer")
	assert_eq(main.system_map.eta_text, SystemMap.trip_text(quote, sim.current_tick(), 10))
	assert_string_starts_with(main.system_map.eta_text, "Departs in ")


func test_waiting_then_transfer_then_arrival_through_the_panels() -> void:
	main.local_view.select("body", keys["Rock"], 0)
	main.order_panel.refresh()
	assert_true(main.order_panel.press("Move to"))
	_run_to(2)
	assert_eq(_ship()["op"]["type"], "waiting")
	var depart: int = _ship()["op"]["depart_tick"]
	assert_string_starts_with(InspectText.status(_ship(), bridge.current_view), "Waiting for window, departs in ")
	main.inspection_panel.refresh()
	_run_to(depart + 5)
	var transfer: Dictionary = _ship()["transfer"]
	assert_false(transfer.is_empty(), "riding the transfer")
	assert_eq(_ship()["op"]["type"], "moving")
	assert_string_starts_with(InspectText.status(_ship(), bridge.current_view), "Transfer 0%, arrives in ")
	main.toggle_map()
	main.system_map.refresh(0.0)
	assert_gt((main.system_map.routes.mesh as ImmediateMesh).get_surface_count(), 0, "the arc is drawn")
	var arc := SystemMap.transfer_arc(bridge.current_view, _ship(), 8)
	assert_eq(arc.size(), 9)
	_run_to((transfer["depart_tick"] + transfer["arrive_tick"]) / 2)
	var halfway := InspectText.status(_ship(), bridge.current_view)
	assert_true(halfway.begins_with("Transfer 49%") or halfway.begins_with("Transfer 50%"), halfway)
	_run_to(transfer["arrive_tick"] + 2)
	assert_true(_ship()["transfer"].is_empty())
	assert_eq(_ship()["frame"], keys["Far"], "arrived in the rock's frame")


func test_flight_says_a_burn_now_would_be_dropped_while_waiting() -> void:
	main.local_view.select("body", keys["Rock"], 0)
	main.order_panel.refresh()
	assert_true(main.order_panel.press("Move to"))
	_run_to(2)
	main.toggle_flight()
	main.flight_screen.set_components(1.0)
	assert_string_contains(main.flight_screen._after.text, "Waiting for window now")
