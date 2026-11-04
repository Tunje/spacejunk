extends GutTest
## D12: the manual flight screen, on the stub's orbit and frame scenarios, and the
## 64-bit drawing maths it rests on.

const ORBIT_REFERENCE := "res://tests/sim/kernel/test_orbit_math.gd"

var main: Node
var bridge: SimBridge
var screen: FlightScreen
var ship := 0


func _start(scenario: String) -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = scenario
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.set_speed(1)
	screen = main.flight_screen
	ship = main.local_view.commanded_unit


func _ticks(count: int) -> void:
	bridge.set_paused(false)
	for i in range(count):
		bridge.advance(1.0 / bridge.ticks_per_second())
	bridge.set_paused(true)
	screen.refresh()


func _open() -> void:
	main.toggle_flight()
	assert_true(screen.visible)


func _unit() -> Dictionary:
	return bridge.current_view["units"][ship]


# --- Drawing maths ---

func _sample_orbits() -> Array[Dictionary]:
	var gm := StubSim.MOON_GM
	var orbits: Array[Dictionary] = [
		OrbitMath.make_orbit(gm, 400_000_000, 0, [OrbitMath.ONE, 0, 0], [0, 0, -OrbitMath.ONE], 0, 0),
	]
	var dirs := OrbitMath.directions(OrbitMath.TURN / 12, OrbitMath.TURN / 5, OrbitMath.TURN / 7)
	orbits.append(OrbitMath.make_orbit(gm, 900_000_000, OrbitMath.ONE / 4, dirs[0], dirs[1], 12345, 77))
	return orbits


func test_orbit_points_match_the_sim_within_a_metre() -> void:
	for orbit: Dictionary in _sample_orbits():
		for tick: int in [0, 1234, 98765, 4_000_000]:
			var drawn := OrbitPath.position(orbit, tick)
			var exact := OrbitMath.position_at(orbit, tick)
			var gap := sqrt(pow(drawn[0] - exact[0], 2) + pow(drawn[1] - exact[1], 2) + pow(drawn[2] - exact[2], 2))
			assert_lt(gap, 1000.0, "within 1 m at tick %d" % tick)


func test_orbit_points_match_the_kernels_float_reference() -> void:
	var reference: GDScript = load(ORBIT_REFERENCE)
	for orbit: Dictionary in _sample_orbits():
		for tick: int in [0, 5555, 3_000_001]:
			var ours := OrbitPath.position(orbit, tick)
			var theirs: Array = reference.position_float(orbit, tick)
			for axis in 3:
				assert_almost_eq(ours[axis], theirs[axis], 1.0)


func test_a_loop_closes_and_lands_in_the_world() -> void:
	var orbit := _sample_orbits()[1]
	var parent := [5_000_000_000_000, 0, -7]
	var points := OrbitPath.loop(orbit, parent, 100, 64)
	assert_eq(points.size(), 65)
	for axis in 3:
		assert_almost_eq(points[0][axis], points[64][axis], 1.0)
	var first := OrbitMath.position_at(orbit, 100)
	assert_almost_eq(points[0][0], float(first[0] + parent[0]), 1000.0)


func test_relative_positions_keep_millimetres_far_from_the_origin() -> void:
	var far := 149_597_870_700_000
	var point := OrbitPath.shifted([1234, 0, 0], [far, 0, 0])
	assert_eq(OrbitPath.relative_m(point, [far, 0, 0]), Vector3(1.234, 0, 0))


func test_apsis_timing() -> void:
	var orbit := _sample_orbits()[1]
	var period := OrbitPath.period_ticks(orbit)
	var to_peri := OrbitPath.ticks_until(orbit, 500, 0.0)
	var to_apo := OrbitPath.ticks_until(orbit, 500, PI)
	assert_almost_eq(OrbitPath.mean_anomaly(orbit, 500 + to_peri), 0.0 if OrbitPath.mean_anomaly(orbit, 500 + to_peri) < PI else TAU, 0.01)
	assert_almost_eq(OrbitPath.mean_anomaly(orbit, 500 + to_apo), PI, 0.01)
	assert_lt(to_peri, ceili(period) + 1)
	var apsides := OrbitPath.apsides_mm(orbit)
	assert_almost_eq(apsides[0], 900_000_000 * 0.75, 1.0)
	assert_almost_eq(apsides[1], 900_000_000 * 1.25, 1.0)


func test_time_to_the_frame_edge() -> void:
	assert_almost_eq(OrbitPath.seconds_to_edge([0, 0, 0], [0, 0, -2_000_000], 1_000_000), 500.0, 0.001)
	assert_eq(OrbitPath.seconds_to_edge([0, 0, 0], [0, 0, 0], 1_000_000), -1.0)


func test_world_positions_from_the_view() -> void:
	assert_eq(WorldPosition.of({ "pos_mm": [1, 2, 3] }), [1, 2, 3], "a view from before version 3")
	var entry := { "pos_mm": [1, 2, 3], "world_mm": [11, 22, 33] }
	assert_eq(WorldPosition.of(entry), [11, 22, 33])
	assert_eq(WorldPosition.local_to_world(entry, [5, 5, 5]), [15, 25, 35])


func test_burn_text() -> void:
	assert_eq(FlightLogic.components_text({ "prograde_um_s": 20_000_000, "normal_um_s": 0, "radial_um_s": -5_000_000 }),
		"20.0 m/s prograde, 5.0 m/s radial in")
	assert_eq(FlightLogic.speed(2_500_000_000), "2.50 km/s")
	assert_eq(FlightLogic.to_um_s(0.5), 500_000)


# --- The screen on an orbit ---

func test_b_and_the_fly_button_open_it() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_B
	main._unhandled_key_input(key)
	assert_true(screen.visible)
	main.time_controls.fly_pressed.emit()
	assert_false(screen.visible)


func test_it_says_where_the_craft_is() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	assert_eq(screen._title.text, "Flight: First Probe")
	assert_eq(screen._place.text, "Orbiting Pebble: 150.0 km x 150.0 km")
	assert_true(screen._diagram.visible)
	assert_gt(screen.current_path.size(), 50, "the current orbit from predict")


func test_a_prograde_burn_previews_the_higher_orbit() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	assert_true(screen._plan_button.disabled, "nothing to plan yet")
	screen.set_components(60.0)
	assert_string_starts_with(screen._cost.text, "Delta-v 60.0 m/s")
	assert_string_starts_with(screen._after.text, "Then 150.0 km x ")
	assert_string_ends_with(screen._after.text, "above Pebble")
	assert_false(screen._plan_button.disabled)
	assert_gt(screen.planned_path.size(), 100)
	assert_false(screen.marker.is_empty())
	assert_gt(screen._diagram.planned.size(), 100)


func test_the_preview_is_checks_answer() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	screen.set_components(25.0, 0.0, -3.0)
	var detail: Dictionary = bridge.check(screen.pending_command())["detail"]
	assert_eq(screen.preview["detail"], detail)
	assert_eq(screen.pending_command()["args"]["radial_um_s"], -3_000_000)


func test_planning_sends_the_burn_and_lists_it() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	screen._when.value = 30.0
	screen.set_components(20.0)
	var tick: int = screen.burn_tick
	screen.plan()
	_ticks(1)
	var burns: Array = _unit()["burns"]
	assert_eq(burns.size(), 1)
	assert_eq(burns[0]["tick"], tick)
	assert_eq(burns[0]["prograde_um_s"], 20_000_000)
	assert_eq(screen.components(), [0, 0, 0] as Array[int], "the editor clears for the next one")
	var row: HBoxContainer = screen._burns_box.get_child(0)
	assert_string_ends_with((row.get_child(0) as Label).text, ": 20.0 m/s prograde")


func test_a_planned_burn_can_be_cancelled() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	screen._when.value = 30.0
	screen.set_components(20.0)
	screen.plan()
	_ticks(1)
	(screen._burns_box.get_child(0).get_child(1) as Button).pressed.emit()
	_ticks(1)
	assert_true(_unit()["burns"].is_empty())
	assert_eq(screen._burns_box.get_child_count(), 0)


func test_a_running_burn_shows_progress_and_can_be_stopped() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	screen.burn_now()
	screen.set_components(40.0)
	screen.plan()
	_ticks(5)
	var label := screen._burns_box.get_child(0).get_child(0) as Label
	assert_string_starts_with(label.text, "Burning: ")
	assert_string_ends_with(label.text, " of 40.0 m/s")
	(screen._burns_box.get_child(0).get_child(1) as Button).pressed.emit()
	_ticks(1)
	assert_true(_unit()["burn"].is_empty())


func test_a_burn_raises_the_orbit_the_screen_reports() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	screen.burn_now()
	screen.set_components(60.0)
	var promised := screen._after.text
	var burn_ticks: int = screen.preview["detail"]["burn_ticks"]
	screen.plan()
	_ticks(burn_ticks + 10)
	assert_true(_unit()["burn"].is_empty())
	var high := OrbitPath.apsides_mm(_unit()["orbit"])[1]
	assert_gt(high, StubSim.PROBE_ORBIT_MM * 1.2)
	assert_ne(screen._place.text, "Orbiting Pebble: 150.0 km x 150.0 km")
	assert_ne(promised, "")


func test_burn_at_apoapsis_lands_on_the_far_side() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	screen.burn_now()
	screen.set_components(60.0)
	var burn_ticks: int = screen.preview["detail"]["burn_ticks"]
	screen.plan()
	_ticks(burn_ticks + 10)
	screen.burn_at_apsis(PI)
	var orbit: Dictionary = _unit()["orbit"]
	assert_almost_eq(OrbitPath.mean_anomaly(orbit, screen.burn_tick), PI, 0.01)
	assert_almost_eq(screen._when.value, float(screen.burn_tick - bridge.current_view["tick"] - 1) / 10.0, 0.11)


func test_the_burn_never_falls_into_the_past() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	screen.burn_now()
	var planned_for: int = screen.burn_tick
	_ticks(5)
	assert_gt(screen.burn_tick, bridge.current_view["tick"])
	assert_gt(screen.burn_tick, planned_for)


func test_closing_hides_the_paths() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	main.toggle_flight()
	assert_false(screen._local_mesh.visible)
	assert_false(screen._map_mesh.visible)


# --- The screen in a frame ---

func test_in_a_frame_a_burn_previews_a_drift() -> void:
	_start(StubSim.SCENARIO_ID)
	_open()
	assert_eq(screen._place.text, "In Rock Cluster, holding still")
	assert_false(screen._diagram.visible)
	assert_true(screen._apo_button.disabled, "no apsis to aim for")
	screen.set_components(3.0)
	assert_string_starts_with(screen._after.text, "Then drifting 3.0 m/s, leaving Rock Cluster in ")
	assert_gt(screen.planned_path.size(), 2)
	screen.plan()
	_ticks(20)
	assert_eq(screen._place.text, "In Rock Cluster, drifting 3.0 m/s")
	assert_gt(screen.current_path.size(), 2)
	await wait_process_frames(1)
	assert_gt(screen._local_mesh.mesh.get_surface_count(), 0, "the drift is drawn in the local view")


func test_docked_it_asks_to_undock() -> void:
	_start(StubSim.SCENARIO_ID)
	var station := 0
	for id: int in bridge.current_view["units"]:
		if bridge.current_view["units"][id]["kind"] == "station":
			station = id
	bridge.sim._state["units"][ship]["dock"] = { "port": 1, "target_unit": station, "target_port": 2 }
	bridge.start(bridge.sim)
	_open()
	assert_eq(screen._place.text, "Docked at Foothold: undock to fly")
	screen.set_components(5.0)
	assert_eq(screen._cost.text, "Undock to plan a burn.")
	assert_true(screen._plan_button.disabled)


# --- The real Sim, before A11 ---

func test_on_the_real_sim_it_opens_and_explains() -> void:
	_start("reference")
	_open()
	assert_eq(screen._place.text, "Docked at Station: undock to fly")
	screen.set_components(5.0)
	assert_eq(screen._cost.text, "Undock to plan a burn.")
	assert_true(screen._plan_button.disabled)
	assert_true(screen.current_path.is_empty())


func test_on_the_real_sim_undocked_it_shows_checks_answer() -> void:
	_start("reference")
	assert_true(main.order_panel.press("Undock"))
	var waited := 0
	while not _unit()["dock"].is_empty() and waited < 600:
		_ticks(10)
		waited += 10
	assert_true(_unit()["dock"].is_empty(), "undocked")
	_open()
	screen.set_components(5.0)
	var result: Dictionary = bridge.check(screen.pending_command())
	if result["ok"]:
		assert_string_starts_with(screen._cost.text, "Delta-v 5.0 m/s")
	else:
		assert_eq(screen._cost.text, OrderText.reason(result["reason"], result["detail"]))
		assert_true(screen._plan_button.disabled)


func test_burn_events_reach_the_log() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	screen.burn_now()
	screen.set_components(40.0)
	screen.plan()
	_ticks(5)
	assert_eq(main.event_log.lines[-1], "First Probe: burn started")
	(screen._burns_box.get_child(0).get_child(1) as Button).pressed.emit()
	_ticks(1)
	assert_string_starts_with(main.event_log.lines[-1], "First Probe: burn stopped at ")
	assert_string_ends_with(main.event_log.lines[-1], " m/s. Cancelled")


func test_a_finished_burn_is_logged_with_its_delta_v() -> void:
	_start(StubSim.SCENARIO_ORBIT)
	_open()
	screen.burn_now()
	screen.set_components(10.0)
	var burn_ticks: int = screen.preview["detail"]["burn_ticks"]
	screen.plan()
	_ticks(burn_ticks + 5)
	assert_eq(main.event_log.lines[-1], "First Probe: burn done, 10.0 m/s")
