extends GutTest
## D47: apsis ticks and heights come from the Sim's orbit fields (A57) where the view
## has them, so the client works none of it out; until then, from the elements.


func test_apsis_ticks_come_from_the_orbit_fields() -> void:
	var orbit := { "parent": 3, "next_periapsis_tick": 1200, "next_apoapsis_tick": 4800 }
	assert_eq(FlightLogic.apsis_tick(orbit, false, 100), 1200)
	assert_eq(FlightLogic.apsis_tick(orbit, true, 100), 4800)
	orbit["next_apoapsis_tick"] = -1
	assert_eq(FlightLogic.apsis_tick(orbit, true, 100), -1, "an escape path: no apoapsis")
	assert_eq(FlightLogic.apsis_tick({}, false, 100), -1, "no orbit")


func test_apsis_heights_come_from_the_orbit_fields() -> void:
	var orbit := { "parent": 3, "periapsis_mm": 260_000_000, "apoapsis_mm": 330_000_000 }
	assert_eq(FlightLogic.apsides_mm(orbit), PackedFloat64Array([260_000_000.0, 330_000_000.0]))
	var view := { "bodies": { 3: { "radius_mm": 250_000_000 } } }
	assert_eq(FlightLogic.orbit_text(view, orbit), "%s x %s" % [OrderText.metres(10_000_000), OrderText.metres(80_000_000)])


## A closed orbit's turn is read off the Sim's apsis ticks: they are half a turn apart.
func test_a_turn_is_twice_the_gap_between_the_apsis_ticks() -> void:
	assert_eq(FlightLogic.turn_ticks({ "next_periapsis_tick": 1200, "next_apoapsis_tick": 4800 }), 7200)
	assert_eq(FlightLogic.turn_ticks({ "next_periapsis_tick": 9000, "next_apoapsis_tick": 5400 }), 7200, "either first")
	assert_eq(FlightLogic.turn_ticks({ "next_periapsis_tick": 1200, "next_apoapsis_tick": -1 }), -1, "an open path")
	assert_eq(FlightLogic.turn_ticks({}), -1, "before A57")
