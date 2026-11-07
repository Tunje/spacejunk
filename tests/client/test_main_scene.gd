extends GutTest
## Runs the real scene for a few frames, which load() alone does not do.


func test_scene_starts_and_ticks() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var bridge: SimBridge = main.get_node("Bridge")
	assert_not_null(bridge.sim, "backend started")
	bridge.advance(0.5)
	assert_gt(bridge.current_view["tick"], 0)
	await wait_process_frames(2)
	assert_ne(main.get_node("Overlay/TimeControls")._clock.text, "")


## D38: a launch with no choice plays the new start, its goals showing at once.
func test_a_plain_launch_plays_the_new_start() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	assert_eq(main.scenario, Main.NEW_START)
	assert_eq(main.goal_panel.tracker.goals, GoalTracker.NEW_START_GOALS)
	assert_eq(main.goal_panel._title.text, "Goal 1 of 13: Scan a rock")
	assert_false(main.goal_panel._hint.text.is_empty(), "the first hint shows from the start")


## D38: New, then Station sandbox, starts the reference game with its own goals.
func test_new_game_switches_to_the_station_sandbox() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	main.time_controls.new_game_pressed.emit(Main.REFERENCE)
	assert_eq(main.scenario, Main.REFERENCE)
	var kinds: Array = bridge.current_view["units"].values().map(func(unit: Dictionary) -> String: return unit["kind"])
	assert_has(kinds, "station", "the sandbox's ready-built station")
	assert_eq(main.goal_panel.tracker.goals, GoalTracker.GOALS)
	assert_has(main.event_log.lines, "Started: Station sandbox")
	main.time_controls.new_game_pressed.emit(Main.NEW_START)
	assert_eq(main.goal_panel.tracker.goals, GoalTracker.NEW_START_GOALS, "and back")


## A load sets the goal list from the save's own start.
func test_a_load_takes_the_saves_start() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	main.get_node("Bridge").set_paused(true)
	var sandbox: Sim = Sim.new_game(Main.REFERENCE, 1)
	main._apply_load(sandbox, {})
	assert_eq(main.scenario, Main.REFERENCE)
	assert_eq(main.goal_panel.tracker.goals, GoalTracker.GOALS)
