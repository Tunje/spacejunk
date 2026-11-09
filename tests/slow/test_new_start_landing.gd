extends GutTest
## new_start's probe leaves the cluster round Frost and lands (task A26, D's case from D25). It flies
## the whole descent, about 50 minutes of game time, so it lives here; the frame margin rules are
## tested in tests/sim/networks/test_frame_margins.gd.

const ONE := OrbitMath.ONE

## D's case on new_start (D25): parked at a rock in the cluster, a 20 m/s retrograde burn takes the
## probe out of the frame at once, onto an orbit round Frost, from which it can land.
func test_new_start_probe_burns_out_of_the_cluster_into_a_frost_orbit_and_lands() -> void:
	var game := Sim.new_game("new_start", 1)
	var ids := {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in game._state[table]:
			ids[game._state[table][id]["name"]] = id
	var probe: Dictionary = game._state["units"][ids["Probe"]]
	game.submit({ "type": "move_to", "unit": ids["Probe"], "args": { "target": ids["Red Rock"] } })
	assert_false(_wait(game, "arrived", 20_000).is_empty(), "parked at the rock")
	game.submit({ "type": "plan_burn", "unit": ids["Probe"], "args": { "tick": game.current_tick() + 1,
		"prograde_um_s": -20_000_000, "normal_um_s": 0, "radial_um_s": 0 } })
	var left := _wait(game, "frame_left", 200)
	assert_false(left.is_empty(), "left the cluster within the burn")
	assert_eq(probe["frame"], 0)
	# The rest of the burn is stepped round Frost (A55), and it ends on an orbit round Frost.
	assert_eq(probe["stepped"], ids["Frost"])
	var left_at: Array = probe["pos_mm"].duplicate()
	_wait(game, "burn_done", 200)
	assert_eq(probe["orbit"]["parent"], ids["Frost"])
	var orbit: Dictionary = probe["orbit"]
	var periapsis: int = orbit["a_mm"] - OrbitMath.smul_div(orbit["a_mm"], orbit["e_q30"], ONE)
	var apoapsis := BurnSystem.apoapsis_mm(orbit)
	# Parked at the rock, 50 km from the cluster's centre, it starts off the cluster's circle, so the
	# periapsis is wherever that point and the burn give: lower than it was, and above the ground.
	assert_between(periapsis, 60_000_000, IntMath.dist(left_at, [0, 0, 0]), "down towards Frost, not into it")
	assert_lt(apoapsis, game._state["bodies"][ids["Frost"]]["soi_mm"])
	var cell := LandingSystem.cell_below(game._ctx, ids["Frost"], probe["pos_mm"])
	var land := { "type": "land", "unit": ids["Probe"], "args": { "body": ids["Frost"], "cell": cell } }
	var checked := game.check(land)
	assert_true(checked["ok"], str(checked))
	game.submit(land)
	game.step(checked["detail"]["ticks"] - 5)
	assert_false(_wait(game, "landed", 20).is_empty(), "landed on Frost")
	assert_eq(probe["landed"]["body"], ids["Frost"])


func _wait(game: Sim, event_type: String, limit: int) -> Dictionary:
	for i in limit:
		game.step()
		for event in game.take_events():
			if event["type"] == event_type:
				return event
	return {}
