extends "res://tests/sim/networks/landing_fixture.gd"
## Landing tests that fly half an orbit of the planet, which can't be shortened there: about
## 8,800 ticks (A24). The rest are in tests/sim/networks/test_landing.gd.


func test_take_off_reaches_a_circular_orbit() -> void:
	_strong_thruster()
	LandingSystem._set_down(sim._ctx, keys["Ship"], keys["Planet"], 777)
	var command := { "type": "take_off", "unit": keys["Ship"], "args": { "altitude_mm": 100_000_000 } }
	var checked := sim.check(command)
	assert_true(checked["ok"], str(checked))
	sim.submit(command)
	sim.step(checked["detail"]["ticks"] - 5)
	assert_eq(_ship()["op"]["type"], LandingSystem.OP_TAKING_OFF, "still climbing")
	var took := _until("took_off", 10)
	assert_false(took.is_empty())
	var orbit: Dictionary = _ship()["orbit"]
	assert_eq(orbit["parent"], keys["Planet"])
	assert_almost_eq(orbit["a_mm"], 700_000_000, 10_000, "a circle at 100 km altitude")
	assert_lt(orbit["e_q30"], ONE / 100_000)
	assert_eq(_ship()["landed"], {})
