extends GutTest
## D11: the job queue (C9) on the stub, through the real Jobs screen.

const LASER := "stub_laser"
const SOLAR := "stub_solar"
const RADIATOR := "stub_radiator"

var main: Node
var bridge: SimBridge
var screen: IndustryScreen
var sim: StubSim
var station := 0
var refinery := 0
var events: Array[Dictionary] = []


func before_each() -> void:
	main = add_child_autofree(StubScene.build())
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.set_speed(1)
	events.clear()
	bridge.events_received.connect(func(batch: Array[Dictionary]) -> void: events.append_array(batch))
	sim = bridge.sim
	screen = main.industry_screen
	var view := bridge.current_view
	for id: int in view["units"]:
		if view["units"][id]["kind"] == "station":
			station = id
	refinery = IndustryLogic.facilities(view["units"][station], bridge.defs()["modules"])[0]["part"]
	main.toggle_industry()


func _recipe(id: String) -> Dictionary:
	return bridge.defs()["recipes"][id]


## Applies queued orders and runs ticks straight on the sim, then refreshes.
func _ticks(count: int) -> void:
	bridge.set_paused(false)
	for i in range(count):
		bridge.advance(1.0 / bridge.ticks_per_second())
	bridge.set_paused(true)
	screen.refresh()


func _queue(recipe: String, count := 1) -> void:
	screen._count.value = count
	screen.start(_recipe(recipe))
	_ticks(1)


func _jobs() -> Array[Dictionary]:
	return IndustryLogic.queue_on(bridge.current_view, refinery)


func _recipes_in_order() -> Array:
	return _jobs().map(func(job: Dictionary) -> String: return job["recipe"])


func _queue_three() -> void:
	_queue(LASER)
	_queue(SOLAR)
	_queue(RADIATOR)


func _events_of(type: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in events:
		if entry["type"] == type:
			found.append(entry)
	return found


func test_the_stub_station_has_a_refinery_with_recipes() -> void:
	assert_eq(screen.unit_id, station)
	assert_eq(screen._rows.size(), 3)
	assert_eq(screen._queue_heading.text, "Queue empty")


func test_start_on_an_idle_facility_runs_at_once_at_position_0() -> void:
	_queue(LASER)
	var jobs := _jobs()
	assert_eq(jobs.size(), 1)
	assert_eq(jobs[0]["queue_pos"], 0)
	assert_eq(jobs[0]["status"], "running")
	assert_string_contains(screen._job_label.text, "Running")


func test_start_becomes_queue_while_the_facility_is_busy() -> void:
	assert_eq(screen._rows[0]["start"].text, "Start")
	_queue(LASER)
	assert_eq(screen._rows[0]["start"].text, "Queue")


func test_a_second_job_queues_behind_the_first() -> void:
	_queue(LASER)
	_queue(SOLAR, 2)
	var jobs := _jobs()
	assert_eq(jobs.size(), 2)
	assert_eq(jobs[1]["queue_pos"], 1)
	assert_eq(jobs[1]["status"], "queued")
	assert_eq(screen._queue_heading.text, "Queue: 2 of 16")
	assert_eq(screen._queue_rows.size(), 1)
	assert_eq(screen._queue_rows[0]["label"].text, "1. Solar Slab: Queued (2 left)")
	assert_eq(_events_of("job_queued").back()["data"]["position"], 1)


func test_the_next_job_starts_the_tick_after_the_previous_finishes() -> void:
	_queue(SOLAR)
	_queue(RADIATOR)
	var first := _jobs()[0]
	var second_id: int = _jobs()[1]["id"]
	while bridge.current_view["jobs"].has(first["id"]):
		_ticks(1)
	var finished_tick: int = bridge.current_view["tick"]
	assert_eq(bridge.current_view["jobs"][second_id]["queue_pos"], 0)
	assert_ne(bridge.current_view["jobs"][second_id]["status"], "running", "not on the same tick")
	_ticks(1)
	assert_eq(bridge.current_view["jobs"][second_id]["status"], "running")
	assert_eq(bridge.current_view["jobs"][second_id]["start_tick"], finished_tick + 1)


func test_up_and_down_reorder_the_queue() -> void:
	_queue_three()
	assert_eq(_recipes_in_order(), [LASER, SOLAR, RADIATOR])
	assert_true(screen._queue_rows[0]["up"].disabled, "the first queued job cannot pass the active one")
	assert_true(screen._queue_rows[1]["down"].disabled)
	screen._queue_rows[1]["up"].pressed.emit()
	_ticks(1)
	assert_eq(_recipes_in_order(), [LASER, RADIATOR, SOLAR])
	screen._queue_rows[0]["down"].pressed.emit()
	_ticks(1)
	assert_eq(_recipes_in_order(), [LASER, SOLAR, RADIATOR])
	assert_eq(_events_of("job_moved").size(), 2)


func test_out_of_range_positions_are_clamped() -> void:
	_queue_three()
	var solar: int = _jobs()[1]["id"]
	screen.move(solar, 99)
	_ticks(1)
	assert_eq(_recipes_in_order(), [LASER, RADIATOR, SOLAR])
	screen.move(solar, -5)
	_ticks(1)
	assert_eq(_recipes_in_order(), [LASER, SOLAR, RADIATOR])


func test_a_running_job_cannot_be_moved() -> void:
	_queue(LASER)
	_queue(SOLAR)
	assert_true(screen._back_button.disabled)
	screen.move(_jobs()[0]["id"], 2)
	assert_eq(screen._message.text, "That job has already started")


func test_a_waiting_job_short_of_ore_can_move_back() -> void:
	sim._state["units"][station]["inventory"]["hematite"] = 300000
	_queue(LASER)
	_queue(SOLAR)
	assert_string_contains(screen._job_label.text, "Missing inputs")
	assert_false(screen._back_button.disabled)
	screen._back_button.pressed.emit()
	_ticks(1)
	assert_eq(_recipes_in_order(), [SOLAR, LASER])
	assert_eq(_jobs()[0]["status"], "running")
	assert_eq(_jobs()[1]["status"], "queued")


func test_remove_ends_a_queued_job_at_once() -> void:
	_queue_three()
	var stock_before: Dictionary = bridge.current_view["units"][station]["inventory"].duplicate()
	screen._queue_rows[0]["remove"].pressed.emit()
	_ticks(1)
	assert_eq(_recipes_in_order(), [LASER, RADIATOR])
	assert_eq(_jobs()[1]["queue_pos"], 1)
	assert_eq(bridge.current_view["units"][station]["inventory"], stock_before, "a queued job held nothing")


func test_cancelling_the_active_job_hands_over_to_the_next() -> void:
	_queue(LASER)
	_queue(SOLAR)
	screen.cancel()
	_ticks(1)
	assert_eq(_recipes_in_order(), [SOLAR])
	assert_eq(_jobs()[0]["queue_pos"], 0)


func test_the_queue_is_full_at_sixteen() -> void:
	for i in range(IndustryLogic.QUEUE_LIMIT):
		_queue(SOLAR)
	assert_eq(_jobs().size(), 16)
	screen.start(_recipe(SOLAR))
	assert_eq(screen._message.text, "The queue is full")


func test_a_faulted_facility_takes_no_new_job_but_can_still_reorder() -> void:
	_queue_three()
	sim._find_part(sim._state["units"][station], refinery)["state"] = "fault"
	screen.start(_recipe(SOLAR))
	assert_eq(screen._message.text, "A required module has a fault")
	screen.move(_jobs()[2]["id"], 1)
	assert_eq(screen._message.text, "")


func test_every_job_in_the_view_has_a_queue_position() -> void:
	_queue_three()
	for id: int in bridge.current_view["jobs"]:
		assert_true(bridge.current_view["jobs"][id]["queue_pos"] is int)


func test_matter_is_conserved_through_a_queue() -> void:
	var before: int = sim.ledger()["matter_g"]
	_queue(LASER, 2)
	_queue(SOLAR)
	for i in range(100):
		_ticks(1)
		assert_eq(sim.ledger()["matter_g"], before)
	assert_true(_jobs().is_empty())
	assert_eq(bridge.current_view["units"][station]["inventory"][LASER], 400000 + 2 * 400000)


func test_a_queue_survives_save_and_load() -> void:
	_queue_three()
	var restored := StubSim.from_save(sim.to_save())
	assert_eq(restored.view()["jobs"], sim.view()["jobs"])
	assert_eq(restored.state_hash(), sim.state_hash())


func test_an_old_stub_save_is_a_version_mismatch() -> void:
	assert_null(StubSim.from_save("stub-save:1\n{}"))
	assert_eq(StubSim.last_error(), "version_mismatch")
