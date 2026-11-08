extends GutTest
## D50: A55's burn options. The throttle down to the engines' floor (B29), and the
## steering choices, those at a target only with one; both go in plan_burn only when
## they aren't the defaults, and planned burns say them.


func test_a_plain_burn_is_the_same_command_as_before() -> void:
	var command := FlightLogic.burn_command(13, 100, [5_000_000, 0, 0])
	assert_eq(command["args"], { "tick": 100, "prograde_um_s": 5_000_000, "normal_um_s": 0, "radial_um_s": 0 })


func test_throttle_steer_and_target_go_in_when_set() -> void:
	var command := FlightLogic.burn_command(13, 100, [5_000_000, 0, 0], 400_000, "target_retrograde", 4)
	assert_eq(command["args"]["throttle_ppm"], 400_000)
	assert_eq(command["args"]["steer"], "target_retrograde")
	assert_eq(command["args"]["target"], 4)


func test_the_throttle_floor_is_the_highest_engine_minimum() -> void:
	var modules := {
		"hull": { "capabilities": {} },
		"soft": { "capabilities": { "thruster": { "min_throttle_ppm": 200_000 } } },
		"stiff": { "capabilities": { "thruster": { "min_throttle_ppm": 600_000 } } },
		"old": { "capabilities": { "thruster": {} } },
	}
	var unit := { "parts": { "id": 1, "def": "hull", "children": [{ "id": 2, "def": "soft", "children": [] }] } }
	assert_eq(FlightLogic.min_throttle_ppm(unit, modules), 200_000)
	unit["parts"]["children"].append({ "id": 3, "def": "stiff", "children": [] })
	assert_eq(FlightLogic.min_throttle_ppm(unit, modules), 600_000, "all fire together")
	unit["parts"]["children"].append({ "id": 4, "def": "old", "children": [] })
	assert_eq(FlightLogic.min_throttle_ppm(unit, modules), 1_000_000, "an engine with no floor runs only at full")
	assert_eq(FlightLogic.min_throttle_ppm({ "parts": { "id": 1, "def": "hull", "children": [] } }, modules), 1_000_000)


func test_a_planned_burn_says_its_options() -> void:
	var burn := { "tick": 110, "prograde_um_s": 5_000_000, "normal_um_s": 0, "radial_um_s": 0, "throttle_ppm": 400_000, "steer": "orbit" }
	assert_string_ends_with(FlightLogic.planned_text(burn, 100, 10), ", at 40%, follow the orbit")
	burn["throttle_ppm"] = 1_000_000
	burn["steer"] = "fixed"
	assert_false(FlightLogic.planned_text(burn, 100, 10).contains(", at"))


func test_the_flight_screen_offers_the_options() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	main.get_node("Bridge").set_paused(true)
	main.toggle_flight()
	var flight: FlightScreen = main.flight_screen
	flight.refresh()
	assert_eq(flight.throttle_steer.item_count, FlightLogic.STEERS.size())
	assert_true(flight.throttle_steer.is_item_disabled(2), "toward a target: no target yet")
	assert_lte(flight.throttle.min_value, 100.0)
	flight.set_components(5.0)
	flight.throttle.value = 100.0
	assert_false(flight.pending_command()["args"].has("throttle_ppm"), "full is the default")


## A55: a burn in orbit is stepped flight, so stepped isn't news, and the descent side
## of flying follows the path meeting the ground instead.
func test_stepped_flight_is_quiet_and_the_ground_decides_descent() -> void:
	var event := { "type": "stepped_entered", "unit": 1, "tick": 5, "data": { "body": 3 } }
	assert_eq(OrderText.event(event, "Probe", {}, {}), "", "not logged")
	assert_false(WarpLogic.needs_attention([event]), "doesn't stop the warp")
	assert_eq(WarpLogic.cap_text("stepped"), "flying a burn")
	assert_false(FlightLogic.near_surface({ "stepped": 3, "surface_contact_tick": -1 }), "a burn in orbit")
	assert_true(FlightLogic.near_surface({ "stepped": 3, "surface_contact_tick": 900 }), "a path that meets the ground")
