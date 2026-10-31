extends GutTest
## Save and load through the real client, on the real Sim unless stated.

const TEST_PATH := "user://test_slot.save"

var main: Node
var bridge: SimBridge
var view: LocalView
var panel: OrderPanel


func before_each() -> void:
	SaveStore.path = TEST_PATH
	_remove_slot()
	main = load("res://client/main.tscn").instantiate()
	add_child_autofree(main)
	_wire()


func after_each() -> void:
	_remove_slot()
	SaveStore.path = SaveStore.DEFAULT_PATH


func _wire() -> void:
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.set_speed(8)
	view = main.get_node("LocalView")
	panel = main.order_panel


func _remove_slot() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _write_slot(text: String) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
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
