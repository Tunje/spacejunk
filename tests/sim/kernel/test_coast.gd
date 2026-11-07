extends "res://tests/sim/kernel/coast_fixture.gd"
## The coast time warp (task A33, orbital_flight.md 11.22): Sim.coast must leave exactly what
## stepping leaves. Each case runs one game stepped in strict mode and a copy coasted, then compares
## the saves byte for byte and the events one for one. The lap and the landing, which step tens of
## thousands of ticks, are in tests/slow/test_coast_lap.gd (A35).


func test_a_warm_loop_cools_the_same_when_coasted() -> void:
	var stepped := _game()
	stepped._state["units"][keys["Probe"]]["heat_stored_j"] = 40_000_000
	var coasted := _copy(stepped)
	_same_both_ways(stepped, coasted, 6_000)
	assert_lt(stepped._state["units"][keys["Probe"]]["heat_stored_j"], 40_000_000, "it cooled")


func test_a_planned_burn_stops_the_coast_on_its_tick_and_caps_it() -> void:
	var stepped := _game()
	stepped.submit({ "type": "plan_burn", "unit": keys["Probe"], "args": {
		"tick": 3_000, "prograde_um_s": 2_000_000, "normal_um_s": 0, "radial_um_s": 0 } })
	var coasted := _copy(stepped)
	var first: Dictionary = coasted.coast(10_000)
	assert_eq(coasted.current_tick(), 3_000, "back on the burn's tick, which was stepped")
	assert_eq(first["capped_by"], "")
	assert_has(coasted.take_events().map(func(e: Dictionary) -> String: return e["type"]), "burn_started")
	assert_eq(coasted.coast(10_000), { "ticks": 1, "capped_by": "burning" })
	stepped.step(3_001)
	assert_eq(coasted.to_save(), stepped.to_save())


## An undock under way coasts to its end tick since C20; the tick it ends on, with its events, is
## stepped, and the result still matches.
func test_a_task_coasts_to_its_end_and_it_still_matches() -> void:
	var stepped := Sim.new_game("reference", 12345)
	var coasted := _copy(stepped)
	stepped.submit({ "type": "undock", "unit": 23, "args": {} })
	coasted.submit({ "type": "undock", "unit": 23, "args": {} })
	var caps: Array = []
	for i in 5:
		caps.append(coasted.coast(50)["capped_by"])
	assert_does_not_have(caps, "tasks", "an undock under way no longer steps the world: %s" % str(caps))
	assert_true(coasted._state["units"][23]["dock"].is_empty(), "it undocked")
	stepped.step(coasted.current_tick())
	assert_eq(coasted.to_save(), stepped.to_save())


func test_strict_coast_steps_every_tick() -> void:
	var stepped := _game()
	var coasted := _copy(stepped)
	coasted._strict = true
	assert_eq(coasted.coast(500), { "ticks": 500, "capped_by": "" })
	stepped.step(500)
	assert_eq(coasted.to_save(), stepped.to_save())
