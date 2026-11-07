extends GutTest
## D30: the time warp on the client (orbital_flight.md 11.22): the ladder up to
## 10,000×, coasting through A33's Sim.coast, batches capped by step cost, a drop
## to 1× on events that need the player, one view per frame, and the readouts.


## A stand-in Sim: counts its calls, and can be made slow, capped or coast-less.
class FakeSim extends RefCounted:
	const TICKS_PER_SECOND := 10
	var tick := 0
	var views := 0
	var step_usec := 0
	var cap := ""
	var events: Array[Dictionary] = []
	var event_at := -1
	var event_type := "arrived"

	func view() -> Dictionary:
		views += 1
		return { "tick": tick, "units": {}, "bodies": {} }

	func step(count: int = 1) -> void:
		for i in count:
			tick += 1
			if step_usec > 0:
				OS.delay_usec(step_usec)
			if tick == event_at:
				events.append({ "type": event_type, "unit": 1, "data": {}, "tick": tick })

	func take_events() -> Array[Dictionary]:
		var taken := events
		events = []
		return taken


class CoastingSim extends FakeSim:
	var coasts := 0

	func coast(max_ticks: int) -> Dictionary:
		coasts += 1
		if cap != "":
			step(1)
			return { "ticks": 1, "capped_by": cap }
		var ticks := max_ticks if event_at <= tick or event_at > tick + max_ticks else event_at - tick
		tick += ticks - 1
		step(1)
		return { "ticks": ticks, "capped_by": "" }


var bridge: SimBridge


func before_each() -> void:
	bridge = SimBridge.new()
	add_child_autofree(bridge)
	bridge.set_process(false)


func test_the_ladder_and_its_modes() -> void:
	assert_eq(SimBridge.SPEEDS, [1, 2, 4, 8, 50, 1000, 10000] as Array[int])
	assert_eq(WarpLogic.mode(8), "step")
	assert_eq(WarpLogic.mode(50), "batch")
	assert_eq(WarpLogic.mode(10000), "coast")
	assert_eq(SimBridge.SPEEDS.map(WarpLogic.speed_label), ["1x", "2x", "4x", "8x", "50x", "1kx", "10kx"])


func test_the_clock_turns_to_days() -> void:
	assert_eq(WarpLogic.clock_text(3725), "T+01:02:05")
	assert_eq(WarpLogic.clock_text(3 * 86400 + 4 * 3600 + 12 * 60 + 9), "T+3 d 04:12")
	assert_eq(WarpLogic.achieved_text(3204.6), "≈3,205×")


func test_attention_events_and_the_jobs_option() -> void:
	var finished: Array = [{ "type": "job_finished", "data": { "job": 7 } }]
	assert_true(WarpLogic.needs_attention([{ "type": "landed" }]))
	assert_false(WarpLogic.needs_attention([{ "type": "deposit_found" }]))
	assert_true(WarpLogic.needs_attention(finished), "its last run: the job is gone")
	assert_false(WarpLogic.needs_attention(finished, false, { 7: {} }), "a run of a job with runs left")
	assert_false(WarpLogic.needs_attention(finished, true), "warp past jobs")
	assert_eq(WarpLogic.cap_text("docking_or_cargo"), "docking or moving cargo")
	assert_true(WarpLogic.needs_attention([{ "type": "departed" }]), "A34: a window opening")
	assert_false(WarpLogic.needs_attention([{ "type": "job_paused", "data": { "reason": "missing_inputs" } }]),
		"waiting on another job's output is the plan")
	assert_true(WarpLogic.needs_attention([{ "type": "job_paused", "data": { "reason": "output_full" } }]))
	assert_false(WarpLogic.needs_attention([{ "type": "transfer_done" }]), "cargo moved isn't a stop")
	var line := OrderText.event({ "type": "departed", "unit": 1, "tick": 100, "data": { "target": 4, "arrive_tick": 1300 } },
		"Probe", {}, { 4: { "name": "White Rock" } })
	assert_eq(line, "Probe departed for White Rock, arriving in 2 min 0 s")


## D39b: a drone on its cycle comes and goes every lap without stopping the warp;
## a block still stops it, and so does a craft flown by hand.
func test_a_cycle_lap_keeps_the_warp() -> void:
	var view := {
		"units": { 5: { "task": 9, "cycle_task": 0 }, 6: { "task": 10, "cycle_task": 0 }, 7: { "task": 11, "cycle_task": 9 } },
		"tasks": { 9: { "kind": "cycle" }, 10: { "kind": "order" }, 11: { "kind": "order" } },
	}
	for type: String in WarpLogic.CYCLE_ROUTINE:
		assert_false(WarpLogic.needs_attention([{ "type": type, "unit": 5 }], false, {}, view), type)
		assert_false(WarpLogic.needs_attention([{ "type": type, "unit": 7 }], false, {}, view), "%s, an order over a cycle" % type)
		assert_true(WarpLogic.needs_attention([{ "type": type, "unit": 6 }], false, {}, view), "%s by hand" % type)
	assert_true(WarpLogic.needs_attention([{ "type": "task_blocked", "unit": 5 }], false, {}, view))
	assert_false(WarpLogic.in_cycle(99, view), "an unknown unit")


func test_a_coast_jumps_a_frame_with_one_view() -> void:
	var sim := CoastingSim.new()
	bridge.start(sim)
	bridge.set_speed(1000)
	var views := sim.views
	bridge.advance(0.1)
	assert_eq(sim.tick, 1000, "0.1 s at 1000× is 1000 ticks")
	assert_eq(sim.coasts, 1, "one jump, nothing in the way")
	assert_eq(sim.views - views, 1, "one view per frame")
	assert_eq(bridge.capped_by, "")


func test_an_attention_event_stops_the_warp_on_its_tick() -> void:
	var sim := CoastingSim.new()
	sim.event_at = 420
	bridge.start(sim)
	bridge.set_speed(10000)
	var got: Array = []
	bridge.events_received.connect(func(events: Array[Dictionary]) -> void: got.append_array(events))
	bridge.advance(0.1)
	assert_eq(sim.tick, 420, "stopped on the event's tick")
	assert_eq(bridge.speed, 1, "dropped to 1×")
	assert_eq(got.size(), 1)


func test_a_capped_coast_runs_the_rest_of_the_frame_as_batches() -> void:
	var sim := CoastingSim.new()
	sim.cap = "burning"
	bridge.start(sim)
	bridge.set_speed(1000)
	bridge.advance(0.01)
	assert_eq(sim.coasts, 1, "tried once, then batches")
	assert_eq(sim.tick, 100, "every owed tick still ran")
	assert_eq(bridge.capped_by, "burning")
	assert_eq(bridge.shown_cap(), "burning", "a lasting cap shows at once")


func test_a_momentary_cap_shows_only_if_it_lasts() -> void:
	var sim := CoastingSim.new()
	sim.cap = "power"
	bridge.start(sim)
	bridge.set_speed(1000)
	bridge.achieved_speed = 900.0
	bridge.advance(0.01)
	bridge.achieved_speed = 900.0
	assert_eq(bridge.shown_cap(), "", "a passing power edge isn't worth showing")
	bridge.achieved_speed = 300.0
	assert_eq(bridge.shown_cap(), "power", "unless it has pulled the speed well down")
	for i in 40:
		bridge.advance(0.016)
	assert_eq(bridge.shown_cap(), "power")


func test_without_coast_the_top_rungs_run_as_batches() -> void:
	var sim := FakeSim.new()
	bridge.start(sim)
	bridge.set_speed(1000)
	bridge.advance(0.01)
	assert_eq(sim.tick, 100)
	assert_eq(bridge.capped_by, "no_coast")


func test_slow_steps_cap_the_batch_to_the_frame_budget() -> void:
	var sim := FakeSim.new()
	sim.step_usec = 2000
	bridge.start(sim)
	bridge.set_speed(50)
	var started := Time.get_ticks_msec()
	bridge.advance(1.0)
	assert_lt(sim.tick, 500, "a busy world can't do 50× in one frame")
	assert_lt(Time.get_ticks_msec() - started, 40, "the frame stays near its budget")
	assert_eq(bridge.capped_by, "busy_world")
	assert_lt(bridge.achieved_speed, 50.0)


func test_the_stub_coasts_to_its_next_event() -> void:
	var stub := StubSim.new_game(StubSim.SCENARIO_ID, 1)
	var result: Dictionary = stub.coast(50)
	assert_eq(result["capped_by"], "")
	assert_between(int(result["ticks"]), 1, 50)


func test_the_screens_follow_the_warp() -> void:
	var main: Node = add_child_autofree(StubScene.build())
	var real: SimBridge = main.get_node("Bridge")
	real.set_paused(false)
	real.set_speed(1000)
	main.toggle_flight()
	main.flight_screen.refresh()
	assert_true(main.flight_screen._now_button.disabled, "no hand-flying above 8×")
	assert_true(main.time_controls.warp_label.visible)
	assert_string_starts_with(main.time_controls.warp_label.text, "Warp ≈")
	real.set_speed(8)
	main.flight_screen.refresh()
	assert_false(main.flight_screen._now_button.disabled)
	assert_false(main.time_controls.warp_label.visible)
