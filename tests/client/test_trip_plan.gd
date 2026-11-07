extends GutTest
## D41: the trip panel. A rock takes one order to visit: fly there, scan and measure
## while it is unscanned; then fly there, measure what is unpaid and mine an amount.
## Sent as a one-shot cycle that the probe's Basic Core flies (C27), on the new start.

var main: Node
var bridge: SimBridge
var panel: OrderPanel
var probe := 0
var rock := 0


func before_each() -> void:
	main = add_child_autofree(load("res://client/main.tscn").instantiate())
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	panel = main.order_panel
	probe = main.local_view.commanded_unit
	for id: int in bridge.current_view["bodies"]:
		if bridge.current_view["bodies"][id]["name"] == "Red Rock":
			rock = id
	main.local_view.select("body", rock, 0)
	panel.refresh()


func _run_until_idle() -> void:
	bridge.fixed_ticks = true
	bridge.set_speed(1000)
	bridge.set_paused(false)
	for frame in 400:
		bridge.advance(0.5)
		var unit: Dictionary = bridge.current_view["units"][probe]
		if unit["op"]["type"] == "idle" and int(unit["task"]) == 0:
			break
		if bridge.speed != 1000:
			bridge.set_speed(1000)
	bridge.set_paused(true)
	panel.refresh()


func test_an_unscanned_rock_offers_fly_scan_and_measure() -> void:
	var trip := panel.button_for(TripPlan.KEY_SCAN)
	assert_not_null(trip)
	assert_eq(trip.text, "Fly there, scan and measure")
	assert_false(trip.disabled, "a Basic Core flies a one-shot plan: %s" % trip.tooltip_text)
	assert_eq(panel._button_box.get_child(0), trip, "the trip comes first")
	for order: Dictionary in panel._orders:
		if order["key"] == TripPlan.KEY_SCAN:
			var types: Array = order["command"]["args"]["steps"].map(func(step: Dictionary) -> String: return step["type"])
			assert_eq(types.slice(0, 2), ["move_to", "scan"])
			assert_has(types, "measure")
			assert_eq(order["command"]["args"]["laps"], 1)
	assert_true(TripPlan.orders(bridge.current_view, bridge.defs().get("science", {}), bridge.defs()["modules"],
		bridge.defs()["items"], probe, rock, 0).all(func(order: Dictionary) -> bool: return not order["key"].begins_with("Trip mine ")),
		"no mining before the scan finds the deposits")


func test_the_scan_trip_flies_scans_and_then_offers_mining() -> void:
	assert_true(panel.press(TripPlan.KEY_SCAN))
	_run_until_idle()
	var shown: Dictionary = bridge.current_view["bodies"][rock]
	assert_true(shown["scanned"], "scanned on arrival, with no other press")
	assert_true(bridge.current_view["science"]["paid"].has("survey:%d" % rock))
	panel.amount.value = 100
	panel.refresh()
	var mining := {}
	for order: Dictionary in panel._orders:
		if order["key"].begins_with("Trip mine "):
			mining = order
	assert_false(mining.is_empty(), "now a mining trip per deposit")
	assert_string_contains(mining["label"], "mine 100 kg of ")
	var steps: Array = mining["command"]["args"]["steps"]
	assert_eq(steps[steps.size() - 1]["type"], "start_mining")
	assert_eq(steps[steps.size() - 1]["args"]["grams"], 100_000)
	assert_true(bridge.check(mining["command"])["ok"])


## The plan's end is the order finishing: the warp stops then, not at its steps.
func test_a_one_shot_plans_end_stops_the_warp() -> void:
	var view := { "units": { 5: { "task": 9, "cycle_task": 0 } }, "tasks": { 9: { "kind": "cycle", "laps": 1 } } }
	var ended := [{ "type": "task_finished", "unit": 5, "data": { "task": 9 } }]
	assert_true(WarpLogic.needs_attention(ended, false, {}, view, 5))
	view["tasks"][9]["laps"] = 0
	assert_false(WarpLogic.needs_attention(ended, false, {}, view, 5), "a repeating cycle's own step stays quiet")
