extends GutTest
## Refining and fabrication (checks 4 and 5), at the reference scenario's station. Recipes run in a
## few ticks here to keep the suite fast. One test runs a recipe at full length, with a save.

const STATION := 8
const REFINERY := 13
const FABRICATOR := 14
const SHIP := 23
const RUN_TICKS := 3
## A full-size facility's work_per_tick, so a recipe of RUN_TICKS * FULL_RATE work takes RUN_TICKS.
const FULL_RATE := 100
const HEMATITE_RUN_G := 100000
const IRON_RUN_G := 69000
const SLAG_RUN_G := 31000
const COPPER_RUN_G := 10000
const WIRING_G := 10000

var sim: Sim
var state: Dictionary
var defs: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	defs = sim._ctx.defs
	defs["recipes"]["refine_hematite"]["work"] = RUN_TICKS * FULL_RATE
	defs["recipes"]["wiring"]["work"] = RUN_TICKS * FULL_RATE


## Puts stock at the station, counted as starting matter.
func _give(item: String, grams: int) -> void:
	Units.add_stock(state["units"][STATION]["inventory"], item, grams)
	state["matter_start_g"] += grams


func _start(recipe: String = "wiring", count: int = 1, facility: int = FABRICATOR) -> Dictionary:
	return { "type": "start_job", "unit": STATION, "args": { "facility": facility, "recipe": recipe, "count": count } }


func _cancel(job: int) -> Dictionary:
	return { "type": "cancel_job", "unit": STATION, "args": { "job": job } }


## Starts a job on tick 1 and returns its ID.
func _started(recipe: String = "wiring", count: int = 1, facility: int = FABRICATOR) -> int:
	sim.submit(_start(recipe, count, facility))
	sim.step()
	return sim.view()["jobs"].keys()[0]


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


func _first(events: Array[Dictionary], type: String) -> Dictionary:
	for event in events:
		if event["type"] == type:
			return event
	fail_test("no %s event" % type)
	return {}


func _stock(item: String) -> int:
	return state["units"][STATION]["inventory"].get(item, 0)


func _step_balanced(ticks: int) -> void:
	for i in ticks:
		sim.step()
		var matter: Dictionary = sim.ledger()["matter"]
		assert_eq(matter["total_g"], matter["start_g"], "tick %d" % sim.current_tick())
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func _assert_refused(command: Dictionary, reason: String) -> void:
	assert_eq(sim.check(command)["reason"], reason)
	sim.submit(command)
	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["command_rejected"], reason)
	assert_eq(events[0]["data"]["reason"], reason)


func test_a_run_turns_inputs_into_outputs_in_its_ticks() -> void:
	_give("copper", COPPER_RUN_G)
	var command_id := sim.submit(_start())
	_step_balanced(1)
	var job: int = sim.view()["jobs"].keys()[0]
	assert_eq(sim.take_events()[0]["data"], { "job": job, "command": command_id })
	assert_eq(_stock("copper"), 0, "inputs move at the start")
	assert_eq(sim.ledger()["matter"]["jobs_g"], COPPER_RUN_G)
	assert_eq(sim.view()["jobs"][job], {
		"unit": STATION, "facility": FABRICATOR, "recipe": "wiring", "count_left": 1,
		"status": "running", "reason": "", "start_tick": 1, "queue_pos": 0,
		"work_left": (RUN_TICKS - 1) * FULL_RATE, "work": RUN_TICKS * FULL_RATE, "work_per_tick": FULL_RATE,
	})
	_step_balanced(RUN_TICKS - 2)
	assert_eq(_stock("wiring"), 0)
	_step_balanced(1)
	assert_eq(_stock("wiring"), WIRING_G, "delivered on S + N - 1")
	assert_eq(sim.ledger()["matter"]["jobs_g"], 0)
	var finished := sim.take_events()
	assert_eq(_types(finished), ["job_finished"])
	assert_eq(finished[0]["data"], { "job": job, "recipe": "wiring", "facility": FABRICATOR })
	assert_eq(sim.view()["jobs"].size(), 0)


func test_refining_vents_slag_to_its_sink() -> void:
	_give("hematite", HEMATITE_RUN_G)
	sim.submit(_start("refine_hematite", 1, REFINERY))
	_step_balanced(RUN_TICKS)
	assert_eq(_stock("iron"), IRON_RUN_G)
	assert_eq(_stock("slag"), 0, "slag takes no storage")
	assert_eq(sim.ledger()["matter"]["sinks"]["slag_vent"], SLAG_RUN_G)


func test_a_job_needs_no_core() -> void:
	_give("copper", COPPER_RUN_G)
	state["units"][STATION]["core"] = 0
	sim.submit(_start())
	_step_balanced(RUN_TICKS)
	assert_eq(_stock("wiring"), WIRING_G)


func test_each_run_takes_its_own_inputs_and_runs_end_to_end() -> void:
	_give("copper", COPPER_RUN_G * 2)
	var job := _started("wiring", 2)
	assert_eq(_stock("copper"), COPPER_RUN_G, "only one run's inputs are held")
	assert_eq(sim.view()["jobs"][job]["count_left"], 2)
	sim.step(RUN_TICKS - 1)
	assert_eq(_stock("wiring"), WIRING_G)
	assert_eq(sim.view()["jobs"][job]["count_left"], 1)
	sim.step()
	assert_eq(sim.view()["jobs"][job]["start_tick"], RUN_TICKS + 1, "the next run starts at once")
	sim.step(RUN_TICKS - 1)
	assert_eq(_stock("wiring"), WIRING_G * 2)
	var types := _types(sim.take_events())
	assert_eq(types.count("job_started"), 1)
	assert_eq(types.count("job_finished"), 2)
	assert_eq(sim.view()["jobs"].size(), 0)


func test_a_job_waits_for_inputs_and_starts_when_they_arrive() -> void:
	var job := _started()
	assert_eq(sim.view()["jobs"][job]["status"], "waiting")
	assert_eq(sim.view()["jobs"][job]["reason"], "missing_inputs")
	var events := sim.take_events()
	assert_eq(_types(events), ["job_paused"])
	sim.step(5)
	assert_eq(sim.take_events().size(), 0, "reported once")
	_give("copper", COPPER_RUN_G)
	sim.step()
	assert_eq(_types(sim.take_events()), ["job_resumed", "job_started"])
	assert_eq(sim.view()["jobs"][job]["status"], "running")


func test_a_later_run_waits_for_inputs_without_restarting() -> void:
	_give("copper", COPPER_RUN_G)
	var job := _started("wiring", 2)
	sim.step(RUN_TICKS)
	assert_eq(sim.view()["jobs"][job]["reason"], "missing_inputs")
	assert_eq(sim.view()["jobs"][job]["work_left"], 0, "no run in progress")


func test_a_job_waits_for_output_space() -> void:
	_give("copper", COPPER_RUN_G)
	defs["modules"]["goods_storage_mk1"]["capabilities"]["storage"]["goods"]["mass_g"] = COPPER_RUN_G
	var outputs: Array = defs["recipes"]["wiring"]["outputs"]
	outputs[0]["grams"] = WIRING_G * 2
	var job := _started()
	assert_eq(sim.view()["jobs"][job]["reason"], "output_full")
	assert_eq(_stock("copper"), COPPER_RUN_G, "no inputs taken")


func test_outputs_may_use_the_space_their_inputs_leave() -> void:
	_give("copper", COPPER_RUN_G)
	defs["modules"]["goods_storage_mk1"]["capabilities"]["storage"]["goods"]["mass_g"] = COPPER_RUN_G
	var job := _started()
	assert_eq(sim.view()["jobs"][job]["status"], "running")


func test_output_space_is_reserved_for_the_whole_run() -> void:
	_give("copper", COPPER_RUN_G)
	var job := _started()
	assert_eq(sim.view()["units"][STATION]["cargo"]["goods"]["reserved_g"], WIRING_G)
	assert_eq(sim.view()["units"][STATION]["cargo"]["goods"]["reserved_l"], 4)
	sim.submit(_cancel(job))
	sim.step()
	assert_eq(sim.view()["units"][STATION]["cargo"]["goods"]["reserved_g"], 0)


func test_a_reservation_clears_on_delivery() -> void:
	_give("copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step(RUN_TICKS)
	assert_eq(state["units"][STATION]["reserved"], {})


func test_a_faulted_facility_pauses_the_run_with_inputs_held() -> void:
	_give("copper", COPPER_RUN_G)
	var job := _started()
	sim.take_events()
	state["parts"][FABRICATOR]["fault"] = "test_fault"
	_step_balanced(5)
	var shown: Dictionary = sim.view()["jobs"][job]
	assert_eq(shown["status"], "paused")
	assert_eq(shown["reason"], "module_fault")
	assert_eq(shown["work_left"], (RUN_TICKS - 1) * FULL_RATE, "a paused run keeps its progress")
	assert_eq(sim.ledger()["matter"]["jobs_g"], COPPER_RUN_G)
	assert_eq(_types(sim.take_events()), ["job_paused"])

	state["parts"][FABRICATOR]["fault"] = ""
	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["job_resumed"])
	assert_eq(events[0]["data"]["reason"], "module_fault")
	assert_eq(sim.view()["jobs"][job]["work_left"], FULL_RATE, "2 of 3 ticks of work were done")
	sim.step()
	assert_eq(_stock("wiring"), WIRING_G)


func test_a_waiting_job_does_not_start_on_a_faulted_facility() -> void:
	var job := _started()
	state["parts"][FABRICATOR]["fault"] = "test_fault"
	_give("copper", COPPER_RUN_G)
	sim.step()
	assert_eq(sim.view()["jobs"][job]["reason"], "module_fault")
	assert_eq(_stock("copper"), COPPER_RUN_G)


func test_lost_power_pauses_a_run_and_it_resumes_after_the_hold() -> void:
	_give("copper", COPPER_RUN_G)
	state["parts"][18]["stored_j"] = 0
	var recipe: Dictionary = defs["recipes"]["wiring"]
	recipe["power_w"] = 1000000
	var job := _started()
	assert_eq(sim.view()["jobs"][job]["status"], "paused")
	assert_eq(sim.view()["jobs"][job]["reason"], "no_power")
	var events := sim.take_events()
	assert_true(_types(events).has("power_shed"))
	assert_true(_types(events).has("job_paused"))
	assert_eq(sim.ledger()["matter"]["jobs_g"], COPPER_RUN_G)

	recipe["power_w"] = 50000
	sim.step(PowerSystem.SHED_HOLD_SECONDS * Sim.TICKS_PER_SECOND)
	assert_eq(sim.view()["jobs"][job]["status"], "running")
	sim.step(RUN_TICKS - 1)
	assert_eq(_stock("wiring"), WIRING_G)


func test_a_facility_stops_drawing_when_its_job_ends() -> void:
	_give("copper", COPPER_RUN_G)
	var job := _started()
	assert_gt(state["units"][STATION]["demand_w"], 7000)
	sim.submit(_cancel(job))
	sim.step()
	assert_eq(state["units"][STATION]["demand_w"], 7000, "the hub and core")


func test_cancelling_a_running_job_returns_its_inputs() -> void:
	_give("copper", COPPER_RUN_G)
	var job := _started()
	sim.take_events()
	sim.submit(_cancel(job))
	_step_balanced(1)
	assert_eq(_stock("copper"), COPPER_RUN_G)
	assert_eq(sim.view()["jobs"].size(), 0)
	var events := sim.take_events()
	assert_eq(_types(events), ["job_cancelled"])
	assert_eq(events[0]["data"], { "job": job, "recipe": "wiring", "facility": FABRICATOR })


func test_cancelling_a_paused_job_returns_its_inputs() -> void:
	_give("copper", COPPER_RUN_G)
	var job := _started()
	state["parts"][FABRICATOR]["fault"] = "test_fault"
	sim.step()
	sim.submit(_cancel(job))
	_step_balanced(1)
	assert_eq(_stock("copper"), COPPER_RUN_G)


func test_cancelling_a_waiting_job_moves_nothing() -> void:
	var job := _started()
	sim.submit(_cancel(job))
	_step_balanced(1)
	assert_eq(sim.view()["jobs"].size(), 0)


func test_cancelling_between_runs_keeps_the_runs_already_done() -> void:
	_give("copper", COPPER_RUN_G)
	var job := _started("wiring", 3)
	sim.step(RUN_TICKS)
	assert_eq(sim.view()["jobs"][job]["status"], "waiting")
	sim.submit(_cancel(job))
	_step_balanced(1)
	assert_eq(_stock("wiring"), WIRING_G)
	assert_eq(_stock("copper"), 0)


func test_cancelling_during_a_later_run_returns_only_that_run() -> void:
	_give("copper", COPPER_RUN_G * 3)
	var job := _started("wiring", 3)
	sim.step(RUN_TICKS)
	sim.submit(_cancel(job))
	_step_balanced(1)
	assert_eq(_stock("wiring"), WIRING_G)
	assert_eq(_stock("copper"), COPPER_RUN_G * 2)


## Inputs that no longer fit stay on the job, and are never destroyed (accounting.md section 2).
func test_a_cancel_with_no_room_waits_on_the_job() -> void:
	_give("copper", COPPER_RUN_G)
	defs["modules"]["goods_storage_mk1"]["capabilities"]["storage"]["goods"]["mass_g"] = COPPER_RUN_G
	var job := _started()
	sim.take_events()
	_give("iron", COPPER_RUN_G)
	sim.submit(_cancel(job))
	_step_balanced(3)
	var shown: Dictionary = sim.view()["jobs"][job]
	assert_eq(shown["status"], "cancelling")
	assert_eq(shown["reason"], "cargo_full")
	assert_eq(shown["work_left"], 0, "the cancelled run's progress is gone")
	assert_eq(sim.ledger()["matter"]["jobs_g"], COPPER_RUN_G)
	assert_eq(sim.view()["units"][STATION]["cargo"]["goods"]["reserved_g"], 0, "the reservation is gone")
	assert_eq(state["units"][STATION]["demand_w"], 7000, "a cancelling job draws nothing")
	var events := sim.take_events()
	assert_eq(_types(events), ["job_paused"])
	assert_eq(events[0]["data"]["reason"], "cargo_full")

	assert_eq(sim.check(_start())["reason"], "facility_busy")
	sim.submit(_cancel(job))
	sim.step()
	assert_eq(sim.take_events().size(), 0, "a repeat cancel does nothing")

	Units.remove_stock(state["units"][STATION]["inventory"], "iron", COPPER_RUN_G)
	state["matter_start_g"] -= COPPER_RUN_G
	_step_balanced(1)
	assert_eq(_stock("copper"), COPPER_RUN_G)
	assert_eq(_types(sim.take_events()), ["job_cancelled"])
	assert_eq(sim.view()["jobs"].size(), 0)


func test_a_busy_facility_refuses_a_second_job() -> void:
	_give("copper", COPPER_RUN_G)
	_started()
	sim.take_events()
	_assert_refused(_start(), "facility_busy")


func test_a_facility_is_free_on_the_tick_after_its_job_ends() -> void:
	_give("copper", COPPER_RUN_G * 2)
	sim.submit(_start())
	sim.step(RUN_TICKS)
	sim.take_events()
	sim.submit(_start())
	sim.step()
	assert_eq(_types(sim.take_events()), ["job_started"])


func test_start_job_needs_a_part_on_this_unit() -> void:
	_assert_refused(_start("wiring", 1, 27), "unknown_part")
	_assert_refused(_start("wiring", 1, 9999), "unknown_part")


func test_start_job_needs_a_known_recipe() -> void:
	_assert_refused(_start("no_such_recipe"), "unknown_recipe")


func test_start_job_needs_the_right_facility() -> void:
	_assert_refused(_start("wiring", 1, REFINERY), "wrong_facility")
	_assert_refused(_start("wiring", 1, 15), "wrong_facility")


func test_start_job_needs_a_healthy_facility() -> void:
	state["parts"][FABRICATOR]["fault"] = "test_fault"
	_assert_refused(_start(), "module_fault")


func test_start_job_needs_a_positive_count() -> void:
	_assert_refused(_start("wiring", 0), "malformed_command")


func test_cancel_job_needs_a_job_on_this_unit() -> void:
	var job := _started()
	sim.take_events()
	_assert_refused({ "type": "cancel_job", "unit": SHIP, "args": { "job": job } }, "unknown_job")
	_assert_refused(_cancel(9999), "unknown_job")
	_assert_refused({ "type": "cancel_job", "unit": STATION, "args": {} }, "malformed_command")


func test_a_facility_cannot_be_detached_from_its_job() -> void:
	_give("copper", COPPER_RUN_G)
	_started()
	assert_eq(sim.check({
		"type": "detach_part", "unit": STATION, "args": { "part": FABRICATOR, "to": STATION },
	})["reason"], "part_busy")


## Real definitions, so this one runs a whole recipe and the save can load.
func test_a_save_mid_run_finishes_identically() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	_give("copper", COPPER_RUN_G * 2)
	sim.submit(_start("wiring", 2))
	sim.step(50)
	var saved := Sim.from_save(sim.to_save())
	assert_not_null(saved)
	assert_eq(saved.to_save(), sim.to_save(), "round trip")
	sim.step(360)
	saved.step(360)
	assert_eq(saved.state_hash(), sim.state_hash())
	assert_eq(saved.view()["units"][STATION]["inventory"]["wiring"], WIRING_G * 2)
	var matter: Dictionary = saved.ledger()["matter"]
	assert_eq(matter["total_g"], matter["start_g"])


## Saves now, loads it with this test's definitions, applies `change` to both games, and requires
## both to run on identically. The state keeps the real data hash, so the load is accepted.
func _assert_load_resumes(change: Callable, ticks: int = 8) -> void:
	sim.take_events()
	var loaded := Sim.from_save(sim.to_save())
	assert_not_null(loaded)
	loaded._ctx.defs = defs
	assert_eq(loaded.to_save(), sim.to_save(), "round trip")
	change.call(sim)
	change.call(loaded)
	sim.step(ticks)
	loaded.step(ticks)
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_eq(loaded.take_events(), sim.take_events(), "the same events")


func test_a_load_finishes_a_cancel_waiting_for_room() -> void:
	_give("copper", COPPER_RUN_G)
	defs["modules"]["goods_storage_mk1"]["capabilities"]["storage"]["goods"]["mass_g"] = COPPER_RUN_G
	var job := _started()
	_give("iron", COPPER_RUN_G)
	sim.submit(_cancel(job))
	sim.step()
	assert_eq(sim.view()["jobs"][job]["status"], "cancelling")
	_assert_load_resumes(func(game: Sim) -> void:
		Units.remove_stock(game._state["units"][STATION]["inventory"], "iron", COPPER_RUN_G)
		game._state["matter_start_g"] -= COPPER_RUN_G)
	assert_eq(sim.view()["jobs"].size(), 0)
