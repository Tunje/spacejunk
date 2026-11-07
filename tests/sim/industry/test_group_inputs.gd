extends "res://tests/sim/industry/coast_fixture.gd"
## Jobs draw their inputs from the docked group (C26): the job's own unit first, then the rest of
## the group by unit ID. Outputs and anything handed back stay with the job's own unit.

const HEMATITE_RUN_G := 100_000

var sim: Sim


func before_each() -> void:
	sim = _reference()
	sim._strict = true


func _stock(unit: int, item: String = "hematite") -> int:
	return sim._state["units"][unit]["inventory"].get(item, 0)


## A bare craft, with a hand-set dock record to `target` if given, enough for the group walk.
func _bare(target: int = 0) -> int:
	var id := Units.create(sim._ctx, "small_craft", "Bare", [0, 0, 0])
	if target != 0:
		sim._state["units"][id]["dock"] = { "port": 0, "target_unit": target, "target_port": 0 }
	sim._ctx.index.clear()
	sim._state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	return id


func _refine(count: int = 1) -> void:
	sim.submit(_job(REFINERY, "refine_hematite", count))


func _job_reason() -> String:
	var jobs: Dictionary = sim._state["jobs"]
	return jobs.values()[0]["reason"] if not jobs.is_empty() else ""


func _step_balanced(ticks: int) -> void:
	for i in ticks:
		sim.step()
		sim.take_events()
		var ledger := sim.ledger()
		assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"], "tick %d" % sim.current_tick())
		assert_eq(ledger["violations"], PackedStringArray())


func test_a_run_takes_its_input_from_a_docked_unit() -> void:
	_give(sim, SHIP, "hematite", HEMATITE_RUN_G)
	_refine()
	_step_balanced(1)
	assert_eq(sim._state["jobs"].values()[0]["status"], "running")
	assert_eq(_stock(SHIP), 0, "taken from the ship docked to the station")
	_step_balanced(1_300)
	assert_gt(_stock(STATION, "iron"), 0, "the iron is the station's")
	assert_eq(_stock(SHIP, "iron"), 0)


func test_the_jobs_own_unit_gives_first() -> void:
	_give(sim, STATION, "hematite", 60_000)
	_give(sim, SHIP, "hematite", 70_000)
	_refine()
	_step_balanced(1)
	assert_eq(_stock(STATION), 0, "all 60 kg of its own")
	assert_eq(_stock(SHIP), 30_000, "then 40 kg from the ship")


func test_a_unit_further_along_the_group_gives_too() -> void:
	var far := _bare(SHIP)
	_give(sim, far, "hematite", HEMATITE_RUN_G)
	_refine()
	_step_balanced(1)
	assert_eq(_stock(far), 0, "through the ship it is docked to")


func test_a_unit_outside_the_group_does_not_count() -> void:
	var loose := _bare()
	_give(sim, loose, "hematite", HEMATITE_RUN_G)
	_refine()
	_step_balanced(1)
	assert_eq(_job_reason(), "missing_inputs")
	assert_eq(_stock(loose), HEMATITE_RUN_G)


func test_a_cancelled_run_hands_its_inputs_to_the_jobs_own_unit() -> void:
	_give(sim, SHIP, "hematite", HEMATITE_RUN_G)
	_refine()
	_step_balanced(10)
	var job: int = sim._state["jobs"].keys()[0]
	sim.submit({ "type": "cancel_job", "unit": STATION, "args": { "job": job } })
	_step_balanced(2)
	assert_eq(_stock(STATION), HEMATITE_RUN_G, "back to the station, not the ship")
	assert_eq(_stock(SHIP), 0)


func test_runs_drawn_from_the_group_coast_exactly() -> void:
	_give(sim, STATION, "hematite", 50_000)
	_give(sim, SHIP, "hematite", 250_000)
	_refine(3)
	sim.step()
	sim.take_events()
	var coasted := _copy(sim)
	assert_lt(_same_both_ways(sim, coasted, 4_000), 30)
	assert_eq(_stock(STATION) + _stock(SHIP), 0, "all three runs drew their ore")
