extends GutTest
## The job queue (C9): queue_job, move_job and cancel_job on a facility's ordered queue, at the
## reference scenario's fabricator. Recipes run in a few ticks here to keep the suite fast.

const STATION := 8
const FABRICATOR := 14
const RUN_TICKS := 3
const COPPER_RUN_G := 10000
const IRON_RUN_G := 50000
const WIRING_G := 10000
const FRAME_G := 50000
const QUEUE_LIMIT := 16
## Long enough that the running job outlasts a test that only reorders.
const LONG_TICKS := 50

var sim: Sim
var state: Dictionary
var defs: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	defs = sim._ctx.defs
	defs["recipes"]["wiring"]["ticks"] = RUN_TICKS
	defs["recipes"]["structural_frame"]["ticks"] = RUN_TICKS


## Puts stock at the station, counted as starting matter.
func _give(item: String, grams: int) -> void:
	Units.add_stock(state["units"][STATION]["inventory"], item, grams)
	state["matter_start_g"] += grams


func _queue(recipe: String = "wiring", count: int = 1) -> Dictionary:
	return { "type": "queue_job", "unit": STATION, "args": { "facility": FABRICATOR, "recipe": recipe, "count": count } }


func _move(job: int, position: int) -> Dictionary:
	return { "type": "move_job", "unit": STATION, "args": { "job": job, "position": position } }


func _cancel(job: int) -> Dictionary:
	return { "type": "cancel_job", "unit": STATION, "args": { "job": job } }


## Queues the recipes on one tick and returns their job IDs in queue order.
func _queued(recipes: Array[String]) -> Array[int]:
	for recipe in recipes:
		sim.submit(_queue(recipe))
	_step_balanced(1)
	return _order()


## The fabricator's job IDs in queue order, from the view.
func _order() -> Array[int]:
	var jobs: Dictionary = sim.view()["jobs"]
	var ids: Array[int] = []
	ids.assign(jobs.keys())
	ids.sort_custom(func(a: int, b: int) -> bool: return jobs[a]["queue_pos"] < jobs[b]["queue_pos"])
	return ids


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


func _of_type(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


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


func test_queue_job_on_an_idle_facility_starts_like_start_job() -> void:
	_give("copper", COPPER_RUN_G)
	var job: int = _queued(["wiring"])[0]
	var events := sim.take_events()
	assert_eq(_types(events), ["job_queued", "job_started"])
	assert_eq(events[0]["data"], { "job": job, "command": 1, "position": 0 })
	var shown: Dictionary = sim.view()["jobs"][job]
	assert_eq(shown["status"], "running")
	assert_eq(shown["queue_pos"], 0)


func test_queued_jobs_wait_their_turn_holding_nothing() -> void:
	_give("copper", COPPER_RUN_G * 3)
	var order := _queued(["wiring", "wiring", "wiring"])
	var jobs: Dictionary = sim.view()["jobs"]
	assert_eq(order.map(func(id: int) -> int: return jobs[id]["queue_pos"]), [0, 1, 2])
	assert_eq(order.map(func(id: int) -> String: return jobs[id]["status"]), ["running", "queued", "queued"])
	assert_eq(jobs[order[1]]["reason"], "")
	assert_eq(sim.ledger()["matter"]["jobs_g"], COPPER_RUN_G, "only the active run holds matter")
	var queued := _of_type(sim.take_events(), "job_queued")
	assert_eq(queued.map(func(event: Dictionary) -> int: return event["data"]["position"]), [0, 1, 2])


## The next job starts the tick after the last one finishes, the same gap as between two runs.
func test_the_next_job_starts_with_the_same_gap_as_a_second_run() -> void:
	_give("copper", COPPER_RUN_G * 2)
	sim.submit({ "type": "start_job", "unit": STATION, "args": { "facility": FABRICATOR, "recipe": "wiring", "count": 2 } })
	_step_balanced(RUN_TICKS + 1)
	var second_run: int = sim.view()["jobs"].values()[0]["start_tick"]

	before_each()
	_give("copper", COPPER_RUN_G * 2)
	var order := _queued(["wiring", "wiring"])
	_step_balanced(RUN_TICKS)
	var next: Dictionary = sim.view()["jobs"][order[1]]
	assert_eq(next["status"], "running")
	assert_eq(next["queue_pos"], 0)
	assert_eq(next["start_tick"], second_run)
	assert_eq(second_run, RUN_TICKS + 1)
	_step_balanced(RUN_TICKS - 1)
	assert_eq(_stock("wiring"), WIRING_G * 2)
	assert_true(sim.view()["jobs"].is_empty())


func test_start_job_still_refuses_a_facility_with_a_queue() -> void:
	_queued(["wiring"])
	sim.take_events()
	_assert_refused({ "type": "start_job", "unit": STATION,
		"args": { "facility": FABRICATOR, "recipe": "wiring", "count": 1 } }, "facility_busy")


func test_a_facility_holds_at_most_sixteen_jobs() -> void:
	var recipes: Array[String] = []
	for i in QUEUE_LIMIT:
		recipes.append("wiring")
	assert_eq(_queued(recipes).size(), QUEUE_LIMIT)
	sim.take_events()
	assert_eq(sim.check(_queue())["detail"], { "need": QUEUE_LIMIT + 1, "have": QUEUE_LIMIT })
	_assert_refused(_queue(), "queue_full")


func test_queue_job_checks_what_start_job_checks() -> void:
	_assert_refused({ "type": "queue_job", "unit": STATION,
		"args": { "facility": FABRICATOR, "recipe": "refine_hematite", "count": 1 } }, "wrong_facility")
	_assert_refused(_queue("wiring", 0), "malformed_command")
	state["parts"][FABRICATOR]["fault"] = "test_fault"
	_assert_refused(_queue(), "module_fault")


func test_move_job_reorders_the_queue_behind_the_run() -> void:
	defs["recipes"]["wiring"]["ticks"] = LONG_TICKS
	_give("copper", COPPER_RUN_G)
	var order := _queued(["wiring", "wiring", "wiring", "wiring"])
	sim.take_events()
	sim.submit(_move(order[3], 1))
	_step_balanced(1)
	assert_eq(_order(), [order[0], order[3], order[1], order[2]])
	assert_eq(sim.take_events()[0], {
		"tick": sim.current_tick(), "type": "job_moved", "unit": STATION, "data": { "job": order[3], "position": 1 },
	})

	sim.submit(_move(order[2], 0))
	_step_balanced(1)
	assert_eq(_order(), [order[0], order[2], order[3], order[1]], "a run in progress is never overtaken")
	sim.submit(_move(order[2], 99))
	_step_balanced(1)
	assert_eq(_order(), [order[0], order[3], order[1], order[2]], "a position past the end means last")
	sim.take_events()
	sim.submit(_move(order[2], 3))
	sim.step()
	assert_eq(sim.take_events(), [] as Array[Dictionary], "a move to where it is does nothing")


func test_a_job_stuck_on_missing_inputs_can_be_moved_out_of_the_way() -> void:
	_give("iron", IRON_RUN_G)
	var order := _queued(["wiring", "structural_frame"])
	var stuck: Dictionary = sim.view()["jobs"][order[0]]
	assert_eq([stuck["status"], stuck["reason"]], ["waiting", "missing_inputs"])
	sim.take_events()

	sim.submit(_move(order[0], 1))
	_step_balanced(1)
	assert_eq(_order(), [order[1], order[0]])
	var events := sim.take_events()
	assert_eq(_types(events), ["job_resumed", "job_moved", "job_started"])
	assert_eq(events[0]["data"], { "job": order[0], "reason": "missing_inputs" })
	var jobs: Dictionary = sim.view()["jobs"]
	assert_eq([jobs[order[0]]["status"], jobs[order[0]]["reason"]], ["queued", ""])
	assert_eq(jobs[order[1]]["status"], "running")
	assert_eq(jobs[order[1]]["start_tick"], sim.current_tick(), "it starts on the tick it moves up")
	_step_balanced(RUN_TICKS)
	assert_eq(_stock("structural_frame"), FRAME_G)
	assert_eq(sim.view()["jobs"][order[0]]["reason"], "missing_inputs", "back in front, still waiting")


func test_move_job_refuses_a_job_with_a_run_in_progress() -> void:
	defs["recipes"]["wiring"]["ticks"] = LONG_TICKS
	_give("copper", COPPER_RUN_G)
	var order := _queued(["wiring", "wiring"])
	sim.take_events()
	_assert_refused(_move(order[0], 1), "job_busy")
	_assert_refused(_move(999, 1), "unknown_job")
	_assert_refused({ "type": "move_job", "unit": STATION, "args": { "job": order[1] } }, "malformed_command")


func test_cancelling_a_queued_job_ends_it_and_closes_the_gap() -> void:
	_give("copper", COPPER_RUN_G)
	var order := _queued(["wiring", "wiring", "wiring"])
	sim.take_events()
	sim.submit(_cancel(order[1]))
	_step_balanced(1)
	assert_eq(_types(sim.take_events()), ["job_cancelled"])
	assert_eq(_order(), [order[0], order[2]])
	assert_eq(sim.view()["jobs"][order[2]]["queue_pos"], 1)
	assert_eq(sim.ledger()["matter"]["jobs_g"], COPPER_RUN_G, "the running job is untouched")


func test_cancelling_the_running_job_starts_the_next_on_the_same_tick() -> void:
	_give("copper", COPPER_RUN_G * 2)
	var order := _queued(["wiring", "wiring"])
	sim.take_events()
	sim.submit(_cancel(order[0]))
	_step_balanced(1)
	assert_eq(_types(sim.take_events()), ["job_cancelled", "job_started"])
	var next: Dictionary = sim.view()["jobs"][order[1]]
	assert_eq([next["status"], next["queue_pos"], next["start_tick"]], ["running", 0, sim.current_tick()])
	assert_eq(_stock("copper"), COPPER_RUN_G, "one run returned, the next run took its own")


func test_a_facility_with_a_queue_cannot_be_detached() -> void:
	_give("copper", COPPER_RUN_G)
	var order := _queued(["wiring", "wiring"])
	sim.take_events()
	sim.submit(_cancel(order[0]))
	var detach := { "type": "detach_part", "unit": STATION, "args": { "part": FABRICATOR, "to": STATION } }
	sim.submit(detach)
	_step_balanced(1)
	var events := sim.take_events()
	assert_eq(_types(events), ["job_cancelled", "command_rejected", "job_started"])
	assert_eq(events[1]["data"]["reason"], "part_busy", "the queued job moved up and still holds the facility")


func test_a_faulted_facility_keeps_its_queue_and_can_reorder_it() -> void:
	_give("copper", COPPER_RUN_G)
	var order := _queued(["wiring", "wiring", "wiring"])
	state["parts"][FABRICATOR]["fault"] = "test_fault"
	_step_balanced(RUN_TICKS + 2)
	var jobs: Dictionary = sim.view()["jobs"]
	assert_eq([jobs[order[0]]["status"], jobs[order[1]]["status"]], ["paused", "queued"])
	sim.submit(_move(order[2], 1))
	_step_balanced(1)
	assert_eq(_order(), [order[0], order[2], order[1]])
	state["parts"][FABRICATOR]["fault"] = ""
	_step_balanced(RUN_TICKS - 1)
	assert_eq(_stock("wiring"), WIRING_G)
	assert_eq(sim.view()["jobs"][order[2]]["queue_pos"], 0)


func test_a_queue_saves_and_loads_unchanged_and_runs_on_identically() -> void:
	_give("copper", COPPER_RUN_G * 2)
	_give("iron", IRON_RUN_G)
	var order := _queued(["wiring", "structural_frame", "wiring"])
	sim.submit(_move(order[2], 1))
	_step_balanced(1)
	var text := sim.to_save()
	var loaded := Sim.from_save(text)
	assert_not_null(loaded)
	assert_eq(loaded.to_save(), text)
	assert_eq(loaded.view()["jobs"], sim.view()["jobs"])
	sim.step(RUN_TICKS * 3 + 3)
	loaded._ctx.defs = defs
	loaded.step(RUN_TICKS * 3 + 3)
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_true(sim.view()["jobs"].is_empty())

