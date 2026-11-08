extends "res://tests/sim/kernel/coast_fixture.gd"
## The view's power.sun_tick (task A48): 0 while a unit is lit; while it is in shadow, the first tick
## it is lit again; -1 if that can't be foreseen. The probe of coast_fixture.gd laps a moon low
## enough that each lap passes through its shadow.


func _power(sim: Sim) -> Dictionary:
	return sim.view()["units"][keys["Probe"]]["power"]


## Exactly `ticks` on, by coasting, which leaves what stepping would (A33) but quicker.
func _on(sim: Sim, ticks: int) -> void:
	var target := sim.current_tick() + ticks
	while sim.current_tick() < target:
		sim.coast(target - sim.current_tick())


func test_sun_tick_is_the_tick_the_probe_comes_out_of_the_shadow() -> void:
	var sim := _game()
	# Out into the light, then into the shadow again, so the answer below is for a whole pass through
	# it. A shadow's edge isn't an event, so one long coast passes it; this looks every 200 ticks.
	for n in 400:
		if not _power(sim)["in_shadow"]:
			break
		_on(sim, 200)
	assert_false(_power(sim)["in_shadow"])
	assert_eq(_power(sim)["sun_tick"], 0, "0 while lit")
	var entered := false
	for n in 400:
		_on(sim, 200)
		if _power(sim)["in_shadow"]:
			entered = true
			break
	assert_true(entered, "the lap reached the shadow")
	assert_gt(_power(sim)["sun_tick"] - sim.current_tick(), 1000, "a pass through the shadow takes a while")
	var sun: int = _power(sim)["sun_tick"]
	print("SUN in shadow at tick %d, lit again at %d" % [sim.current_tick(), sun])
	assert_gt(sun, sim.current_tick(), "a coming tick")
	# Exactly then: still dark the tick before, and lit on it.
	_on(sim, sun - 1 - sim.current_tick())
	assert_true(_power(sim)["in_shadow"], "still in shadow the tick before")
	assert_eq(_power(sim)["sun_tick"], sun, "the same answer from later in the shadow")
	sim.step()
	assert_false(_power(sim)["in_shadow"], "lit on sun_tick")
	assert_eq(_power(sim)["sun_tick"], 0)


func test_sun_tick_is_minus_one_when_the_place_ahead_cannot_be_foreseen() -> void:
	var sim := _game()
	assert_true(_power(sim)["in_shadow"], "the probe starts in the moon's shadow")
	# In low flight a unit flies by forces, not rails, so its place ahead is unknown.
	var probe: Dictionary = sim._state["units"][keys["Probe"]]
	probe["stepped"] = keys["Moon"]
	assert_eq(PowerSystem.sun_tick(sim._state, keys["Probe"]), -1)
