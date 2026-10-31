extends GutTest

var bridge: SimBridge
var sim: StubSim


func before_each() -> void:
	bridge = SimBridge.new()
	bridge.set_process(false)
	add_child_autofree(bridge)
	sim = StubSim.new_game("stub", 7)
	bridge.start(sim)


func test_runs_ticks_at_the_tick_rate() -> void:
	for i in range(10):
		bridge.advance(0.1)
	assert_between(sim.current_tick(), 9, 11)


func test_speed_multiplies_steps_only() -> void:
	bridge.set_speed(4)
	for i in range(10):
		bridge.advance(0.1)
	assert_between(sim.current_tick(), 39, 41)


func test_unknown_speed_is_ignored() -> void:
	bridge.set_speed(3)
	assert_eq(bridge.speed, 1)


func test_pause_stops_steps_but_keeps_commands_queued() -> void:
	bridge.set_paused(true)
	bridge.advance(5.0)
	assert_eq(sim.current_tick(), 0)
	bridge.submit({ "type": "stop", "unit": 0, "args": {} })
	bridge.set_paused(false)
	bridge.advance(0.1)
	assert_eq(sim.current_tick(), 1)


func test_a_slow_frame_is_capped_and_does_not_snowball() -> void:
	bridge.advance(60.0)
	assert_eq(sim.current_tick(), SimBridge.MAX_STEPS_PER_FRAME)
	bridge.advance(0.0)
	assert_eq(sim.current_tick(), SimBridge.MAX_STEPS_PER_FRAME + 1)
	bridge.advance(0.0)
	assert_eq(sim.current_tick(), SimBridge.MAX_STEPS_PER_FRAME + 1)


func test_views_roll_forward_for_interpolation() -> void:
	bridge.advance(0.1)
	bridge.advance(0.1)
	assert_eq(bridge.current_view["tick"], bridge.previous_view["tick"] + 1)


func test_alpha_is_continuous_across_a_step() -> void:
	bridge.advance(0.05)
	var before := bridge.interpolation_alpha()
	assert_almost_eq(before, 0.5, 0.01)
	bridge.advance(0.04)
	assert_gt(bridge.interpolation_alpha(), before)
	bridge.advance(0.02)
	assert_lt(bridge.interpolation_alpha(), 0.2, "a new span restarts near its start")


func test_alpha_covers_a_multi_tick_span() -> void:
	bridge.set_speed(8)
	bridge.advance(0.03125)
	assert_eq(sim.current_tick(), 2)
	assert_almost_eq(bridge.interpolation_alpha(), 0.75, 0.01, "2.5 ticks owed, showing tick 1.5 of 2")


func test_events_reach_listeners() -> void:
	watch_signals(bridge)
	bridge.submit({ "type": "stop", "unit": 0, "args": {} })
	bridge.advance(0.1)
	assert_signal_emit_count(bridge, "events_received", 1)
	var events: Array = get_signal_parameters(bridge, "events_received")[0]
	assert_eq(events[0]["type"], "command_rejected")


func test_game_seconds_follow_ticks() -> void:
	bridge.advance(0.1)
	assert_almost_eq(bridge.game_seconds(), 0.1, 0.001)


func test_time_controls_reflect_and_drive_the_bridge() -> void:
	var controls := TimeControls.new()
	add_child_autofree(controls)
	controls.bind(bridge)
	var press := InputEventKey.new()
	press.pressed = true
	press.physical_keycode = KEY_3
	controls._unhandled_key_input(press)
	assert_eq(bridge.speed, 4)
	press.physical_keycode = KEY_SPACE
	controls._unhandled_key_input(press)
	assert_true(bridge.paused)


func test_screenshot_args_parse() -> void:
	var parsed := ScreenshotRunner.parse_args(["--shot=C:/a/b.png", "--frames=9", "ignored"])
	assert_eq(parsed, { "shot": "C:/a/b.png", "frames": "9" })
