extends "res://tests/sim/industry/coast_fixture.gd"
## Coast closed forms for jobs, scans, measurements and mining (C17, C19): each byte-equal to
## stepping.


func test_jobs_with_several_runs_and_a_queue_coast_exactly() -> void:
	var stepped := _reference()
	_give(stepped, STATION, "hematite", 300_000)
	_give(stepped, STATION, "iron", 200_000)
	stepped.submit(_job(REFINERY, "refine_hematite", 3))
	stepped.submit(_job(FABRICATOR, "structural_frame", 2))
	stepped.submit(_job(FABRICATOR, "structural_frame", 2, "queue_job"))
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	var calls := _same_both_ways(stepped, coasted, 3_000)
	assert_true(stepped._state["jobs"].is_empty(), "every run finished")
	assert_lt(calls, 60, "the runs were skipped, not stepped: %d calls" % calls)


func test_a_lab_job_coasts_exactly() -> void:
	var stepped := _reference()
	var hub := 9
	var lab := Units.add_part(stepped._ctx, STATION, "research_lab_mk1", hub, "side_d_px", "mount")
	stepped._state["parts"][hub]["children"].append(lab)
	stepped._state["research"] = Research.empty_research()
	stepped._state["science"]["points"] = 100
	stepped._state["science"]["earned"] = 100
	for key in ["survey:2", "survey:4", "survey:6", "gravity_field:20"]:
		stepped._state["science"]["paid"][key] = 1
	stepped._ctx.index.clear()
	for input: Dictionary in stepped._ctx.defs["recipes"]["prove_autonomous_navigation"]["inputs"]:
		_give(stepped, STATION, input["item"], input["grams"])
	stepped.submit({ "type": "start_job", "unit": STATION,
		"args": { "facility": lab, "recipe": "prove_autonomous_navigation", "count": 1 } })
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	assert_lt(_same_both_ways(stepped, coasted, 3_100), 20)
	assert_true(stepped._state["research"]["theories"].has("autonomous_navigation"))


func test_a_scan_coasts_to_its_end() -> void:
	var stepped := _ship_at_rock()
	stepped.submit({ "type": "scan", "unit": SHIP, "args": { "target": ROCK } })
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	assert_lt(_same_both_ways(stepped, coasted, 400), 10)


func test_mining_coasts_in_closed_form_to_a_full_hold() -> void:
	var stepped := _ship_at_rock()
	var laser := 0
	for part: int in Units.sorted_part_ids(stepped._state, SHIP):
		if Units.module_of(stepped._state, stepped._ctx.defs, part)["capabilities"].has("mine"):
			laser = part
	stepped.submit({ "type": "start_mining", "unit": SHIP, "args": { "deposit": DEPOSIT, "module": laser } })
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	assert_lt(_same_both_ways(stepped, coasted, 2_500), 20, "with A35's power horizon")
	assert_eq(stepped._state["units"][SHIP]["task"], 0, "the hold filled and the order ended")
	assert_gt(stepped._state["units"][SHIP]["inventory"].get("hematite", 0), 0)
	# Mining itself never caps: only its start and end.
	assert_lte(caps.get("tasks", 0), 2, "mining coasts in closed form: %s" % str(caps))


## C19: an amount stops the closed form on the tick that reaches it.
func test_mining_an_amount_coasts_to_exactly_that_amount() -> void:
	var stepped := _ship_at_rock()
	var laser := _laser(stepped, SHIP)
	stepped.submit({ "type": "start_mining", "unit": SHIP,
		"args": { "deposit": DEPOSIT, "module": laser, "grams": 777_777 } })
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	_same_both_ways(stepped, coasted, 2_500)
	assert_eq(stepped._state["units"][SHIP]["task"], 0, "the order ended")
	assert_eq(stepped._state["units"][SHIP]["inventory"].get("hematite", 0), 777_777)
	assert_lte(caps.get("tasks", 0), 2, "the amount is a horizon edge, not a step per tick: %s" % str(caps))


func test_a_gravity_field_lap_coasts_exactly() -> void:
	var stepped := _orbiting()
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	assert_lt(_same_both_ways(stepped, coasted, 800), 30, "with A35's power horizon")
	assert_eq(stepped._state["science"]["paid"].size(), 1, "the lap paid")
	assert_lte(caps.get("tasks", 0), 2, "a running measurement never caps: %s" % str(caps))
