extends "res://tests/sim/industry/coast_fixture.gd"
## Coast closed forms for docking, undocking and cargo transfers (C20): each byte-equal to stepping.


func test_an_undock_and_a_dock_coast_to_their_end_ticks() -> void:
	var stepped := _docked()
	var dock: Dictionary = stepped._state["units"][SHIP]["dock"].duplicate()
	stepped.submit({ "type": "undock", "unit": SHIP, "args": {} })
	assert_lte(_then_same(stepped, 200), 6, "the undock coasts")
	assert_true(stepped._state["units"][SHIP]["dock"].is_empty())
	stepped.submit({ "type": "dock", "unit": SHIP,
		"args": { "port": dock["port"], "target_port": dock["target_port"] } })
	assert_lte(_then_same(stepped, 400), 6, "the dock coasts once its ports are granted")
	assert_false(stepped._state["units"][SHIP]["dock"].is_empty())


func test_a_load_and_an_unload_coast_exactly() -> void:
	var stepped := _docked()
	stepped.submit({ "type": "load_cargo", "unit": SHIP, "args": { "from": STATION, "item": "hematite" } })
	assert_lte(_then_same(stepped, 600), 6, "the load is summed, not stepped")
	assert_eq(caps.get("docking_or_cargo", 0), 0)
	assert_eq(_held(stepped, SHIP, "hematite"), 900_000, "all of it came")
	stepped.submit({ "type": "unload_cargo", "unit": SHIP, "args": { "to": STATION, "item": "chalcopyrite" } })
	assert_lte(_then_same(stepped, 600), 6, "the unload is summed, not stepped")
	assert_eq(_held(stepped, STATION, "chalcopyrite"), 400_000, "all of it went")


func test_a_transfer_amount_stops_exactly_under_coast() -> void:
	var stepped := _docked()
	stepped.submit({ "type": "unload_cargo", "unit": SHIP,
		"args": { "to": STATION, "item": "chalcopyrite", "grams": 123_456 } })
	_then_same(stepped, 400)
	assert_eq(_held(stepped, SHIP, "chalcopyrite"), 400_000 - 123_456)


func test_a_load_into_a_hold_that_fills_coasts_exactly() -> void:
	var stepped := _docked()
	var room := Units.grams_that_fit(stepped._state, stepped._ctx.defs, SHIP, "hematite")
	_give(stepped, STATION, "hematite", room)
	stepped.submit({ "type": "load_cargo", "unit": SHIP, "args": { "from": STATION, "item": "hematite" } })
	_then_same(stepped, 2_000)
	assert_eq(_held(stepped, SHIP, "hematite"), room, "the hold filled")
	assert_eq(Units.grams_that_fit(stepped._state, stepped._ctx.defs, SHIP, "hematite"), 0)


func test_whole_units_still_step_and_match() -> void:
	var stepped := _docked()
	var unit_g: int = stepped._ctx.defs["items"]["processor"]["unit_mass_g"]
	_give(stepped, SHIP, "processor", 40 * unit_g)
	stepped.submit({ "type": "unload_cargo", "unit": SHIP, "args": { "to": STATION, "item": "processor" } })
	_then_same(stepped, 300)
	assert_eq(_held(stepped, STATION, "processor"), 40 * unit_g, "all forty went")
	assert_gt(caps.get("tasks", 0), 30, "a whole-unit transfer steps, from the task side first")


## A job held for inputs at the station starts on the tick the arriving ore lets it, coasted or not.
## The ore comes from outside the station's group: the cycle's drone mines it at the rock and
## brings it back, and the job may draw it from the drone once it docks (C26) or from the station
## once it is unloaded, whichever comes first.
func test_a_job_waiting_on_arriving_ore_starts_on_the_same_tick() -> void:
	var stepped := _mining_cycle({})
	stepped.submit(_job(REFINERY, "refine_hematite", 2))
	stepped.step()
	stepped.take_events()
	assert_eq(stepped._state["jobs"].values()[0]["reason"], "missing_inputs")
	_same_both_ways(stepped, _copy(stepped), 6_000)
	assert_gt(stepped._state["units"][STATION]["inventory"].get("iron", 0), 0, "the job ran on the drone's ore")
	assert_gt(caps.get("jobs", 0), 0, "the held job stepped while its inputs came")
