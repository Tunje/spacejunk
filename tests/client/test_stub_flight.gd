extends GutTest
## The stub's A11 burns, built from the kernel's API shape, so the flight screen has
## something to fly before A11 lands. Orbit maths is the kernel's own OrbitMath.

var sim: StubSim
var ship := 0


func _ship_of(stub: StubSim) -> int:
	for id: int in stub._state["units"]:
		if stub._state["units"][id]["kind"] == "ship":
			return id
	return 0


func _orbit_sim() -> void:
	sim = StubSim.new_game(StubSim.SCENARIO_ORBIT, 1)
	ship = _ship_of(sim)


func _frame_sim() -> void:
	sim = StubSim.new_game(StubSim.SCENARIO_ID, 1)
	ship = _ship_of(sim)
	assert_true(sim.view()["units"][ship]["dock"].is_empty(), "the stub probe starts free, beside the station")


func _burn(tick: int, prograde: int, normal := 0, radial := 0) -> Dictionary:
	return { "type": "plan_burn", "unit": ship, "args": {
		"tick": tick, "prograde_um_s": prograde, "normal_um_s": normal, "radial_um_s": radial } }


func _apoapsis_mm(orbit: Dictionary) -> float:
	return float(orbit["a_mm"]) * (1.0 + float(orbit["e_q30"]) / OrbitMath.ONE)


func _events(type: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in sim.take_events():
		if entry["type"] == type:
			found.append(entry)
	return found


func test_the_view_has_places_and_flight_fields() -> void:
	_frame_sim()
	var view := sim.view()
	assert_eq(view["frames"].size(), 1)
	var unit: Dictionary = view["units"][ship]
	for field: String in ["frame", "orbit", "world_mm", "vel_um_s", "burns", "burn"]:
		assert_true(unit.has(field), field)
	assert_ne(unit["frame"], 0)
	for id: int in view["bodies"]:
		for field: String in ["frame", "orbit", "gm", "world_mm"]:
			assert_true(view["bodies"][id].has(field), field)


func test_the_orbit_scenario_puts_the_probe_on_rails() -> void:
	_orbit_sim()
	var unit: Dictionary = sim.view()["units"][ship]
	assert_false(unit["orbit"].is_empty())
	var start: Array = unit["pos_mm"].duplicate()
	sim.step(100)
	assert_ne(sim.view()["units"][ship]["pos_mm"], start)
	assert_almost_eq(float(IntMath.dist(sim.view()["units"][ship]["pos_mm"], [0, 0, 0])), float(StubSim.PROBE_ORBIT_MM), 1000.0)


func test_a_burn_in_the_past_or_while_docked_is_refused() -> void:
	sim = StubSim.new_game(StubSim.SCENARIO_ID, 1)
	ship = _ship_of(sim)
	sim._state["units"][ship]["dock"] = { "port": 1, "target_unit": 2, "target_port": 3 }
	assert_eq(sim.check(_burn(5, 1000))["reason"], "not_flying")
	_orbit_sim()
	assert_eq(sim.check(_burn(0, 1000))["reason"], "burn_in_past")
	assert_eq(sim.check(_burn(1, 1000))["reason"], "")
	assert_eq(sim.check({ "type": "plan_burn", "unit": ship, "args": { "tick": 1 } })["reason"], "malformed_command")


func test_check_previews_a_prograde_burn_on_an_orbit() -> void:
	_orbit_sim()
	var result := sim.check(_burn(10, 20_000_000))
	assert_true(result["ok"])
	var detail: Dictionary = result["detail"]
	assert_eq(detail["dv_um_s"], 20_000_000)
	assert_gt(detail["propellant_g"], 0)
	assert_gt(detail["burn_ticks"], 0)
	assert_gt(_apoapsis_mm(detail["orbit"]), StubSim.PROBE_ORBIT_MM * 1.05, "a prograde burn raises the far side")
	assert_eq(detail["orbit"]["parent"], sim.view()["units"][ship]["orbit"]["parent"])


func test_a_planned_burn_runs_and_raises_the_orbit() -> void:
	_orbit_sim()
	var preview: Dictionary = sim.check(_burn(5, 20_000_000))["detail"]
	var fuel_before: int = sim.view()["units"][ship]["inventory"]["propellant"]
	var matter: int = sim.ledger()["matter_g"]
	sim.submit(_burn(5, 20_000_000))
	sim.step(2)
	assert_eq(sim.view()["units"][ship]["burns"].size(), 1)
	sim.step(4)
	assert_eq(sim.view()["units"][ship]["op"]["type"], "burning")
	assert_false(sim.view()["units"][ship]["burn"].is_empty())
	sim.step(preview["burn_ticks"] + 5)
	var unit: Dictionary = sim.view()["units"][ship]
	assert_true(unit["burn"].is_empty())
	assert_eq(unit["op"]["type"], "idle")
	assert_almost_eq(_apoapsis_mm(unit["orbit"]), _apoapsis_mm(preview["orbit"]), _apoapsis_mm(preview["orbit"]) * 0.01,
		"a finite burn lands near the one-impulse preview")
	assert_almost_eq(fuel_before - int(unit["inventory"]["propellant"]), preview["propellant_g"], preview["propellant_g"] / 20)
	assert_eq(sim.ledger()["matter_g"], matter, "propellant goes to exhaust, not nowhere")
	var events := sim.take_events().map(func(e: Dictionary) -> String: return e["type"])
	assert_has(events, "burn_started")
	assert_has(events, "burn_done")


func test_a_burn_in_a_frame_starts_a_straight_drift() -> void:
	_frame_sim()
	var tick := sim.current_tick()
	var preview: Dictionary = sim.check(_burn(tick + 1, 3_000_000))["detail"]
	assert_eq(preview["vel_um_s"], [0, 0, -3_000_000])
	assert_true(preview["leaves_frame"])
	assert_true(preview["orbit"].is_empty())
	sim.submit(_burn(tick + 1, 3_000_000))
	sim.step(40)
	var unit: Dictionary = sim.view()["units"][ship]
	assert_eq(unit["vel_um_s"], [0, 0, -3_000_000])
	var z: int = unit["pos_mm"][2]
	sim.step(10)
	assert_eq(sim.view()["units"][ship]["pos_mm"][2], z - 3000, "3 m/s for one second")


func test_an_opposite_burn_stops_the_drift() -> void:
	_frame_sim()
	sim.submit(_burn(sim.current_tick() + 1, 2_000_000))
	sim.step(30)
	sim.submit(_burn(sim.current_tick() + 1, -2_000_000))
	sim.step(30)
	assert_eq(sim.view()["units"][ship]["vel_um_s"], [0, 0, 0])


func test_cancel_removes_a_planned_burn_and_stops_a_running_one() -> void:
	_orbit_sim()
	sim.submit(_burn(50, 10_000_000))
	sim.step(1)
	var burn: int = sim.view()["units"][ship]["burns"][0]["id"]
	sim.submit({ "type": "cancel_burn", "unit": ship, "args": { "burn": burn } })
	sim.step(1)
	assert_true(sim.view()["units"][ship]["burns"].is_empty())
	sim.submit(_burn(sim.current_tick() + 1, 50_000_000))
	sim.step(3)
	var running: int = sim.view()["units"][ship]["burn"]["id"]
	sim.submit({ "type": "cancel_burn", "unit": ship, "args": { "burn": running } })
	sim.step(1)
	assert_true(sim.view()["units"][ship]["burn"].is_empty())
	assert_eq(sim.view()["units"][ship]["op"]["type"], "idle")


func test_predict_follows_the_orbit_and_the_drift() -> void:
	_orbit_sim()
	var path := sim.predict(ship, sim.current_tick(), 600, 10)
	assert_eq(path["place"], { "orbit_parent": sim.view()["units"][ship]["orbit"]["parent"] })
	assert_eq(path["points"].size(), 61)
	assert_eq(path["points"][0], sim.view()["units"][ship]["pos_mm"])
	assert_eq(sim.predict(ship, 0, 1_000_000, 1)["points"].size(), StubSim.PREDICT_LIMIT)
	_frame_sim()
	path = sim.predict(ship, sim.current_tick(), 100, 50)
	assert_eq(path["place"], { "frame": sim.view()["units"][ship]["frame"] })


func test_a_short_burn_reports_no_propellant() -> void:
	_orbit_sim()
	sim._state["units"][ship]["inventory"]["propellant"] = 1000
	sim.submit(_burn(2, 100_000_000))
	sim.step(20)
	var shorts := _events("burn_short")
	assert_eq(shorts.size(), 1)
	assert_eq(shorts[0]["data"]["reason"], "no_propellant")


func test_a_mid_burn_save_resumes_identically() -> void:
	_orbit_sim()
	sim.submit(_burn(3, 30_000_000))
	sim.step(8)
	var copy := StubSim.from_save(sim.to_save())
	sim.step(40)
	copy.step(40)
	assert_eq(copy.state_hash(), sim.state_hash())
