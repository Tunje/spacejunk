extends GutTest
## Save and load through the real client, on the real Sim unless stated.

const TEST_PATH := "user://test_slot.save"
const AUTO_PATH := "user://test_autosave.save"

var main: Node
var bridge: SimBridge
var view: LocalView
var panel: OrderPanel


func before_each() -> void:
	SaveStore.path = TEST_PATH
	SaveStore.autosave_path = AUTO_PATH
	_remove_slot()
	main = load("res://client/main.tscn").instantiate()
	add_child_autofree(main)
	_wire()


func after_each() -> void:
	_remove_slot()
	SaveStore.path = SaveStore.DEFAULT_PATH
	SaveStore.autosave_path = SaveStore.DEFAULT_AUTOSAVE_PATH


func _wire() -> void:
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.set_speed(8)
	view = main.get_node("LocalView")
	panel = main.order_panel


func _remove_slot() -> void:
	for at: String in [TEST_PATH, AUTO_PATH]:
		if FileAccess.file_exists(at):
			DirAccess.remove_absolute(at)


func _write_slot(text: String, at := TEST_PATH) -> void:
	var file := FileAccess.open(at, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _run_ticks(ticks: int) -> void:
	bridge.set_paused(false)
	for i in range(ceili(ticks / 8.0)):
		bridge.advance(0.1)
	bridge.set_paused(true)
	view.refresh(0.016)


func _last_log() -> String:
	return main.event_log.lines[-1]


func _ship() -> int:
	return view.commanded_unit


func _rock() -> int:
	var state: Dictionary = bridge.current_view
	for id: int in state["bodies"]:
		if state["bodies"][id]["name"] == "Red Rock":
			return id
	return 0


func test_saving_writes_the_slot_and_says_so() -> void:
	main.save_game()
	assert_true(SaveStore.exists())
	assert_eq(_last_log(), "Game saved")


func test_no_side_file_is_left_behind() -> void:
	main.save_game()
	assert_false(FileAccess.file_exists(TEST_PATH + ".tmp"))


func test_the_default_slot_is_on_user_storage() -> void:
	assert_string_starts_with(SaveStore.DEFAULT_PATH, "user://")


func test_loading_with_no_save_explains_and_changes_nothing() -> void:
	var hash_before: String = bridge.sim.state_hash()
	main.load_game()
	assert_eq(_last_log(), "Load failed: No saved game yet")
	assert_eq(bridge.sim.state_hash(), hash_before)


func test_a_damaged_outer_file_is_reported() -> void:
	_write_slot("not a save at all")
	main.load_game()
	assert_eq(_last_log(), "Load failed: The save file is damaged")


func test_damaged_sim_text_shows_last_error_and_keeps_the_game() -> void:
	main.save_game()
	var hash_before: String = bridge.sim.state_hash()
	assert_true(SaveStore.write("garbage", {}))
	main.load_game()
	assert_eq(Sim.last_error(), "corrupt")
	assert_eq(_last_log(), "Load failed: The save file is damaged")
	assert_eq(bridge.sim.state_hash(), hash_before)
	assert_eq(view.crafts.size(), bridge.current_view["units"].size())


func test_a_newer_slot_format_is_a_version_mismatch() -> void:
	_write_slot(JSON.stringify({ "format": 999, "sim": "x", "client": "{}" }))
	main.load_game()
	assert_eq(_last_log(), "Load failed: The save is from a different version")


func test_a_version_mismatch_from_the_backend_is_shown() -> void:
	var stub: Node = StubScene.build()
	add_child_autofree(stub)
	stub.get_node("Bridge").set_paused(true)
	assert_true(SaveStore.write("stub-save:999\n{}", {}))
	stub.load_game()
	assert_eq(stub.event_log.lines[-1], "Load failed: The save is from a different version")


func test_a_load_restores_the_exact_state() -> void:
	panel.press("Undock")
	_run_ticks(160)
	var saved_hash: String = bridge.sim.state_hash()
	main.save_game()
	_run_ticks(160)
	assert_ne(bridge.sim.state_hash(), saved_hash)
	main.load_game()
	assert_eq(bridge.sim.state_hash(), saved_hash)
	assert_eq(_last_log(), "Game loaded")


func test_play_after_a_load_matches_play_without_one() -> void:
	panel.press("Undock")
	_run_ticks(160)
	view.select("body", _rock(), 0)
	panel.press("Move to")
	_run_ticks(80)
	main.save_game()
	var tick_saved: int = bridge.sim.current_tick()
	bridge.sim.step(600)
	var straight: String = bridge.sim.state_hash()
	main.load_game()
	assert_eq(bridge.sim.current_tick(), tick_saved)
	bridge.sim.step(600)
	assert_eq(bridge.sim.state_hash(), straight)


func test_a_load_rebuilds_the_scene_for_the_saved_state() -> void:
	var state: Dictionary = bridge.current_view
	main.save_game()
	main.load_game()
	await wait_process_frames(2)
	assert_eq(view.crafts.size(), state["units"].size())
	assert_eq(view.bodies.size(), state["bodies"].size())
	var nodes := 0
	for child: Node in view.get_children():
		if child is CraftNode and not child.is_queued_for_deletion():
			nodes += 1
	assert_eq(nodes, state["units"].size(), "no craft left over from before")


func test_loading_an_earlier_save_drops_a_part_added_since() -> void:
	var stub: Node = StubScene.build()
	add_child_autofree(stub)
	var stub_bridge: SimBridge = stub.get_node("Bridge")
	stub_bridge.set_paused(true)
	var local: LocalView = stub.get_node("LocalView")
	var ship: int = local.commanded_unit
	var parts: int = local.crafts[ship].part_transforms.size()
	var state: Dictionary = stub_bridge.current_view
	var station := 0
	for id: int in state["units"]:
		if id != ship:
			station = id
	local.select("unit", station, 0)
	stub.order_panel.press("Dock")
	stub_bridge.set_paused(false)
	stub_bridge.set_speed(8)
	for i in range(6):
		stub_bridge.advance(0.1)
	stub_bridge.set_paused(true)
	stub.save_game()
	var slot := { "part": stub_bridge.current_view["units"][ship]["parts"]["id"], "connector": "ext_a" }
	stub_bridge.submit(FittingLogic.attach_command(ship, { "item": "stub_radiator", "from": station }, slot))
	stub_bridge.set_paused(false)
	stub_bridge.advance(0.1)
	stub_bridge.set_paused(true)
	local.refresh(0.016)
	assert_eq(local.crafts[ship].part_transforms.size(), parts + 1)
	stub.load_game()
	assert_eq(local.crafts[ship].part_transforms.size(), parts)
	assert_false(local.crafts[ship].is_growing(), "nothing grows in on a load")


func test_event_based_goals_survive_a_load() -> void:
	var tracker: GoalTracker = main.goal_panel.tracker
	tracker.complete("refine")
	tracker.complete("handover")
	tracker.note_fit_blocked("mining_laser_mk1", "over_heat_budget")
	main.save_game()
	tracker.done.clear()
	tracker._blocked_items.clear()
	main.load_game()
	assert_true(tracker.done.has("refine"))
	assert_true(tracker.done.has("handover"))
	assert_true(tracker._blocked_items.has("mining_laser_mk1"), "a fix after the load still counts")


func test_goals_survive_a_fresh_start_of_the_client() -> void:
	main.goal_panel.tracker.complete("refine")
	main.goal_panel.tracker.complete("scan")
	main.save_game()
	var second: Node = load("res://client/main.tscn").instantiate()
	add_child_autofree(second)
	second.get_node("Bridge").set_paused(true)
	assert_false(second.goal_panel.tracker.done.has("refine"))
	second.load_game()
	assert_true(second.goal_panel.tracker.done.has("refine"))
	assert_eq(second.goal_panel._title.text, "Goal 2 of 10: Mine ore")


func test_the_flown_trip_survives_with_integer_ids() -> void:
	panel.press("Undock")
	_run_ticks(160)
	view.select("body", _rock(), 0)
	panel.press("Move to")
	main.save_game()
	main.automation_screen.trip.clear()
	main.load_game()
	var trip: Array[Dictionary] = main.automation_screen.trip
	assert_eq(trip.size(), 2)
	assert_eq(trip[1]["args"]["target"], _rock())
	assert_true(trip[1]["args"]["target"] is int, "floats would be refused by the sim")


func test_a_load_closes_open_screens() -> void:
	main.save_game()
	main.toggle_map()
	main.toggle_automation()
	main.load_game()
	assert_false(main.system_map.is_open())
	assert_false(main.automation_screen.visible)


func test_a_focus_on_a_craft_missing_from_the_save_recovers() -> void:
	main.save_game()
	view.focus_id = 99999
	view.selected_kind = "unit"
	view.selected_id = 99999
	view.commanded_unit = 99999
	main.load_game()
	view.refresh(0.016)
	assert_true(view.crafts.has(view.focus_id))
	assert_true(bridge.current_view["units"].has(view.commanded_unit))


func test_keys_and_buttons_save_and_load() -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_F5
	main._unhandled_key_input(key)
	assert_eq(_last_log(), "Game saved")
	key.physical_keycode = KEY_F9
	main._unhandled_key_input(key)
	assert_eq(_last_log(), "Game loaded")
	main.time_controls.save_pressed.emit()
	assert_eq(_last_log(), "Game saved")
	main.time_controls.load_pressed.emit()
	assert_eq(_last_log(), "Game loaded")


func _slot_text(at: String) -> String:
	return FileAccess.get_file_as_string(at)


func test_the_autosave_has_its_own_file_on_user_storage() -> void:
	assert_string_starts_with(SaveStore.DEFAULT_AUTOSAVE_PATH, "user://")
	assert_ne(SaveStore.DEFAULT_AUTOSAVE_PATH, SaveStore.DEFAULT_PATH)


func test_autosave_fires_when_the_timer_runs_out() -> void:
	main._process(main.AUTOSAVE_SECONDS - 1.0)
	assert_false(SaveStore.exists(AUTO_PATH), "not before five minutes")
	main._process(1.0)
	assert_true(SaveStore.exists(AUTO_PATH))
	assert_false(SaveStore.exists(), "the manual slot is left alone")
	assert_eq(_last_log(), "Game autosaved")
	assert_false(FileAccess.file_exists(AUTO_PATH + ".tmp"))


func test_the_timer_restarts_after_an_autosave() -> void:
	main._process(main.AUTOSAVE_SECONDS)
	DirAccess.remove_absolute(AUTO_PATH)
	main._process(main.AUTOSAVE_SECONDS - 1.0)
	assert_false(SaveStore.exists(AUTO_PATH))
	main._process(1.0)
	assert_true(SaveStore.exists(AUTO_PATH))


func test_closing_the_window_autosaves() -> void:
	panel.press("Undock")
	_run_ticks(160)
	var closing_hash: String = bridge.sim.state_hash()
	main._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_true(SaveStore.exists(AUTO_PATH))
	var second: Node = load("res://client/main.tscn").instantiate()
	add_child_autofree(second)
	second.get_node("Bridge").set_paused(true)
	second.load_game()
	assert_eq(second.event_log.lines[-1], "Autosave loaded")
	assert_eq(second.get_node("Bridge").sim.state_hash(), closing_hash)


func test_a_game_that_never_started_does_not_autosave() -> void:
	var unstarted: Node = load("res://client/main.tscn").instantiate()
	unstarted._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	unstarted._process(main.AUTOSAVE_SECONDS * 2.0)
	unstarted.free()
	assert_false(SaveStore.exists(AUTO_PATH))


func test_load_picks_a_newer_autosave() -> void:
	main.save_game()
	panel.press("Undock")
	_run_ticks(160)
	var auto_hash: String = bridge.sim.state_hash()
	main.autosave()
	_run_ticks(80)
	main.load_game()
	assert_eq(bridge.sim.state_hash(), auto_hash)
	assert_eq(_last_log(), "Autosave loaded")


func test_load_picks_a_newer_manual_save() -> void:
	main.autosave()
	panel.press("Undock")
	_run_ticks(160)
	var manual_hash: String = bridge.sim.state_hash()
	main.save_game()
	_run_ticks(80)
	main.load_game()
	assert_eq(bridge.sim.state_hash(), manual_hash)
	assert_eq(_last_log(), "Game loaded")


func test_f9_and_the_load_button_pick_the_newer_slot() -> void:
	main.save_game()
	main.autosave()
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_F9
	main._unhandled_key_input(key)
	assert_eq(_last_log(), "Autosave loaded")
	main.save_game()
	main.time_controls.load_pressed.emit()
	assert_eq(_last_log(), "Game loaded")


func test_an_autosave_never_overwrites_the_manual_save() -> void:
	main.save_game()
	var manual := _slot_text(TEST_PATH)
	panel.press("Undock")
	_run_ticks(160)
	main._process(main.AUTOSAVE_SECONDS)
	main._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	main.autosave()
	assert_eq(_slot_text(TEST_PATH), manual)
	assert_ne(_slot_text(AUTO_PATH), manual)


func test_a_failed_autosave_is_reported_and_play_goes_on() -> void:
	SaveStore.autosave_path = "user://no_such_folder/autosave.save"
	main.autosave()
	assert_eq(_last_log(), "Autosave failed: could not write the file")
	var tick: int = bridge.sim.current_tick()
	_run_ticks(80)
	assert_gt(bridge.sim.current_tick(), tick)


func test_a_damaged_autosave_falls_back_to_the_manual_save() -> void:
	panel.press("Undock")
	_run_ticks(160)
	var manual_hash: String = bridge.sim.state_hash()
	main.save_game()
	_run_ticks(80)
	_write_slot("not a save at all", AUTO_PATH)
	main.load_game()
	assert_eq(bridge.sim.state_hash(), manual_hash)
	assert_eq(main.event_log.lines[-2], "Autosave failed to load: The save file is damaged")
	assert_eq(_last_log(), "Game loaded")


func test_a_newer_autosave_the_sim_rejects_falls_back_to_the_manual_save() -> void:
	main.save_game()
	var manual_hash: String = bridge.sim.state_hash()
	assert_true(SaveStore.write("garbage", {}, AUTO_PATH))
	panel.press("Undock")
	_run_ticks(80)
	main.load_game()
	assert_eq(bridge.sim.state_hash(), manual_hash)
	assert_eq(main.event_log.lines[-2], "Autosave failed to load: The save file is damaged")
	assert_eq(_last_log(), "Game loaded")


func test_a_damaged_autosave_with_no_manual_save_changes_nothing() -> void:
	_write_slot("not a save at all", AUTO_PATH)
	var hash_before: String = bridge.sim.state_hash()
	main.load_game()
	assert_eq(_last_log(), "Autosave failed to load: The save file is damaged")
	assert_eq(bridge.sim.state_hash(), hash_before)


func test_a_manual_save_without_a_stamp_still_loads_and_counts_as_oldest() -> void:
	main.save_game()
	var data: Dictionary = JSON.parse_string(_slot_text(TEST_PATH))
	data.erase("saved_us")
	main.autosave()
	_write_slot(JSON.stringify(data))
	main.load_game()
	assert_eq(_last_log(), "Autosave loaded")
	DirAccess.remove_absolute(AUTO_PATH)
	main.load_game()
	assert_eq(_last_log(), "Game loaded")


## CONTRACT_VERSION went to 2 with C9. A save from version 1 is otherwise the
## same shape, so a real save with its version set back stands in for one.
func _write_version_1(at: String) -> void:
	var text: String = bridge.sim.to_save()
	var field := "\"s:contract_version\":\"%d\""
	assert_string_contains(text, field % Sim.CONTRACT_VERSION)
	var old := text.replace(field % Sim.CONTRACT_VERSION, field % 1)
	assert_true(SaveStore.write(old, {}, at))


func test_version_1_saves_on_disk_explain_and_change_nothing() -> void:
	_write_version_1(TEST_PATH)
	_write_version_1(AUTO_PATH)
	var hash_before: String = bridge.sim.state_hash()
	main.load_game()
	assert_eq(Sim.last_error(), "version_mismatch")
	assert_eq(Array(main.event_log.lines.slice(-2)), [
		"Autosave failed to load: The save is from a different version",
		"Load failed: The save is from a different version",
	])
	assert_eq(bridge.sim.state_hash(), hash_before)


func test_a_version_1_autosave_falls_back_to_a_current_manual_save() -> void:
	main.save_game()
	_write_version_1(AUTO_PATH)
	main.load_game()
	assert_eq(_last_log(), "Game loaded")


func test_startup_with_version_1_saves_on_disk_is_quiet() -> void:
	_write_version_1(TEST_PATH)
	_write_version_1(AUTO_PATH)
	var second: Node = load("res://client/main.tscn").instantiate()
	add_child_autofree(second)
	assert_true(second._started, "the game starts; saves are only read on a load")
	for line: String in second.event_log.lines:
		assert_false(line.to_lower().contains("load"), "nothing is loaded at startup: %s" % line)
