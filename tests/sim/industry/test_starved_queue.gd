extends "res://tests/sim/industry/coast_fixture.gd"
## A starved queue skips (C24): while a facility's active job waits on missing_inputs or
## output_full with no run in progress, the first queued job that can run goes ahead for one run,
## and the active job takes the facility back once that run ends and it can start.

var sim: Sim
var events: Array[Dictionary] = []


func before_each() -> void:
	sim = _reference()
	sim._strict = true
	events = []
	# The station starts with its propellant tank full; empty it, so ice has room unless a test
	# fills it again.
	var inventory: Dictionary = sim._state["units"][STATION]["inventory"]
	Units.remove_stock(inventory, "propellant", inventory.get("propellant", 0))
	sim._state["matter_start_g"] = sim.ledger()["matter"]["total_g"]


func _queue(recipe: String, count: int) -> int:
	sim.submit(_job(REFINERY, recipe, count, "queue_job"))
	sim.step()
	for event in _take():
		if event["type"] == "job_queued":
			return event["data"]["job"]
	return 0


func _take() -> Array[Dictionary]:
	var taken := sim.take_events()
	events.append_array(taken)
	assert_eq(sim.ledger()["violations"], PackedStringArray(), "tick %d" % sim.current_tick())
	return taken


func _of(type: String) -> Array[Dictionary]:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


func _job_of(id: int) -> Dictionary:
	return sim._state["jobs"].get(id, {})


## Fills the station's propellant tank, so refine_water_ice has no room for its output.
func _fill_propellant() -> void:
	_give(sim, STATION, "propellant", Units.grams_that_fit(sim._state, sim._ctx.defs, STATION, "propellant"))


func test_a_queued_job_goes_ahead_of_a_head_missing_inputs() -> void:
	_give(sim, STATION, "hematite", 300_000)
	var ice := _queue("refine_water_ice", 5)
	var hematite := _queue("refine_hematite", 3)
	sim.step()
	_take()
	assert_eq(_job_of(ice)["reason"], "missing_inputs")
	var ahead := _of("job_went_ahead")
	assert_eq(ahead.size(), 1)
	assert_eq(ahead[0]["data"], { "job": hematite, "ahead_of": ice, "reason": "missing_inputs" })
	assert_eq([_job_of(hematite)["status"], _job_of(hematite)["queue_pos"]], ["running", 1], "keeps its place")


func test_the_head_takes_the_facility_back_after_the_current_run() -> void:
	_give(sim, STATION, "hematite", 300_000)
	var ice := _queue("refine_water_ice", 5)
	var hematite := _queue("refine_hematite", 3)
	sim.step(10)
	_take()
	_give(sim, STATION, "water_ice", 100_000)
	var finished_at := 0
	for i in 3_000:
		sim.step()
		for event in _take():
			if event["type"] == "job_finished" and event["data"]["job"] == hematite:
				finished_at = event["tick"]
		if finished_at != 0:
			break
	assert_ne(finished_at, 0, "the hematite run went on to its end")
	assert_eq(_job_of(hematite)["status"], "queued", "back in its place")
	assert_eq(_job_of(hematite)["count_left"], 2, "one run only")
	sim.step()
	_take()
	assert_eq(_job_of(ice)["status"], "running", "the head starts on the tick after")
	assert_eq(_job_of(ice)["start_tick"], finished_at + 1)
	assert_eq(_of("job_went_ahead").size(), 1, "nothing went ahead of a head that could run")


func test_a_queued_job_goes_ahead_of_a_head_with_no_room_for_its_output() -> void:
	_fill_propellant()
	_give(sim, STATION, "water_ice", 300_000)
	_give(sim, STATION, "hematite", 100_000)
	var ice := _queue("refine_water_ice", 3)
	var hematite := _queue("refine_hematite", 1)
	sim.step()
	_take()
	assert_eq(_job_of(ice)["reason"], "output_full")
	assert_eq(_of("job_went_ahead")[0]["data"], { "job": hematite, "ahead_of": ice, "reason": "output_full" })


func test_nothing_goes_ahead_of_a_run_in_progress() -> void:
	_give(sim, STATION, "water_ice", 100_000)
	_give(sim, STATION, "hematite", 300_000)
	var ice := _queue("refine_water_ice", 3)
	var hematite := _queue("refine_hematite", 3)
	var ice_done := 0
	var went := 0
	for i in 3_000:
		sim.step()
		for event in _take():
			if event["type"] == "job_finished" and event["data"]["job"] == ice and ice_done == 0:
				ice_done = event["tick"]
			if event["type"] == "job_went_ahead":
				went = event["tick"]
		if went != 0:
			break
	assert_ne(ice_done, 0)
	assert_eq(went, ice_done + 1, "only once the ice run ended and the head starved")
	assert_eq(_job_of(hematite)["queue_pos"], 1)


func test_the_lowest_queue_pos_that_can_run_goes_ahead() -> void:
	_give(sim, STATION, "hematite", 300_000)
	var ice := _queue("refine_water_ice", 2)
	var olivine := _queue("refine_olivine", 2)
	var hematite := _queue("refine_hematite", 2)
	sim.step()
	_take()
	assert_eq(_of("job_went_ahead")[0]["data"]["job"], hematite, "olivine has no ore, so it is passed")
	assert_eq(_job_of(olivine)["status"], "queued")
	assert_eq(_job_of(ice)["status"], "waiting")


func test_a_starved_queue_runs_the_same_with_the_same_seed() -> void:
	var saves := []
	for run in 2:
		before_each()
		_give(sim, STATION, "hematite", 300_000)
		_queue("refine_water_ice", 5)
		_queue("refine_hematite", 3)
		sim.step(2_000)
		_take()
		_give(sim, STATION, "water_ice", 100_000)
		sim.step(2_000)
		_take()
		saves.append(sim.to_save())
	assert_eq(saves[0], saves[1])


func test_a_starved_queue_coasts_exactly() -> void:
	_give(sim, STATION, "hematite", 300_000)
	_queue("refine_water_ice", 5)
	_queue("refine_hematite", 3)
	sim.step()
	sim.take_events()
	var coasted := _copy(sim)
	assert_lt(_same_both_ways(sim, coasted, 6_000), 30, "runs that went ahead still coast")
	assert_eq(sim._state["units"][STATION]["inventory"].get("hematite", 0), 0, "all three ran")
