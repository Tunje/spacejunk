extends GutTest

var tracker: GoalTracker
var defs: Dictionary
var items: Dictionary


func before_each() -> void:
	tracker = GoalTracker.new()
	defs = {
		"recipes": { "refine_iron": { "facility": "refinery" }, "frame": { "facility": "fabricator" } },
	}
	items = { "hematite": { "cargo_class": "ore" }, "iron": { "cargo_class": "goods" } }


func _view(units: Dictionary = {}, deposits: Dictionary = {}) -> Dictionary:
	return { "units": units, "deposits": deposits }


func _unit(kind: String, inventory: Dictionary = {}, parts: Dictionary = {}) -> Dictionary:
	var tree := parts if not parts.is_empty() else { "id": 1, "def": "hull", "children": [] }
	return { "kind": kind, "inventory": inventory, "parts": tree }


func _event(type: String, unit: int, data: Dictionary) -> Dictionary:
	return { "type": type, "unit": unit, "data": data, "tick": 1 }


func test_there_are_ten_goals_in_check_order() -> void:
	var ids: Array = GoalTracker.GOALS.map(func(goal: Dictionary) -> String: return goal["id"])
	assert_eq(ids, ["scan", "mine", "haul", "refine", "fabricate", "install", "drone", "handover", "expand", "fix"])


func test_every_goal_has_a_title_and_a_hint() -> void:
	for goal: Dictionary in GoalTracker.GOALS:
		assert_ne(goal["title"], "")
		assert_ne(goal["hint"], "")


func test_the_current_goal_is_the_first_open_one() -> void:
	assert_eq(tracker.current()["id"], "scan")
	tracker.complete("scan")
	tracker.complete("haul")
	assert_eq(tracker.current()["id"], "mine")
	for goal: Dictionary in GoalTracker.GOALS:
		tracker.complete(goal["id"])
	assert_true(tracker.current().is_empty())


func test_a_goal_finishes_only_once() -> void:
	assert_true(tracker.complete("scan"))
	assert_false(tracker.complete("scan"))


func test_a_found_deposit_finishes_scan() -> void:
	assert_eq(tracker.observe_view(_view({}, { 5: {} }), items), ["scan"] as Array[String])


func test_ore_aboard_finishes_mine_and_ore_at_a_station_finishes_haul() -> void:
	assert_eq(tracker.observe_view(_view({ 1: _unit("ship", { "hematite": 10 }) }), items), ["mine"] as Array[String])
	assert_eq(tracker.observe_view(_view({ 2: _unit("station", { "hematite": 10 }) }), items), ["haul"] as Array[String])


func test_goods_do_not_count_as_ore() -> void:
	assert_true(tracker.observe_view(_view({ 1: _unit("ship", { "iron": 10 }) }), items).is_empty())


func test_finished_jobs_split_by_facility() -> void:
	assert_eq(tracker.observe_event(_event("job_finished", 1, { "recipe": "refine_iron" }), _view(), defs), ["refine"] as Array[String])
	assert_eq(tracker.observe_event(_event("job_finished", 1, { "recipe": "frame" }), _view(), defs), ["fabricate"] as Array[String])


func test_a_lap_finishes_the_handover() -> void:
	assert_eq(tracker.observe_event(_event("task_cycle_done", 1, { "task": 4, "cycle": 1 }), _view(), defs), ["handover"] as Array[String])


func test_a_drone_finishes_from_either_the_event_or_the_view() -> void:
	assert_eq(tracker.observe_event(_event("unit_created", 2, { "unit": 3 }), _view(), defs), ["drone"] as Array[String])
	var other := GoalTracker.new()
	assert_eq(other.observe_view(_view({ 3: _unit("drone") }), items), ["drone"] as Array[String])


func test_attaching_to_a_ship_installs_and_to_a_station_expands() -> void:
	var state := _view({ 1: _unit("ship"), 2: _unit("station") })
	assert_eq(tracker.observe_event(_event("part_attached", 1, { "part": 1 }), state, defs), ["install"] as Array[String])
	assert_eq(tracker.observe_event(_event("part_attached", 2, { "part": 1 }), state, defs), ["expand"] as Array[String])


func test_fix_needs_a_limit_failure_then_that_part_fitted() -> void:
	var state := _view({ 1: _unit("ship", {}, { "id": 7, "def": "laser", "children": [] }) })
	tracker.complete("install")
	tracker.note_fit_blocked("laser", "connector_occupied")
	assert_true(tracker.observe_event(_event("part_attached", 1, { "part": 7 }), state, defs).is_empty(), "not a limit")
	tracker.note_fit_blocked("laser", "over_heat_budget")
	assert_eq(tracker.observe_event(_event("part_attached", 1, { "part": 7 }), state, defs), ["fix"] as Array[String])


func test_fix_ignores_a_different_part() -> void:
	var state := _view({ 1: _unit("ship", {}, { "id": 7, "def": "tank", "children": [] }) })
	tracker.complete("install")
	tracker.note_fit_blocked("laser", "over_power_budget")
	assert_true(tracker.observe_event(_event("part_attached", 1, { "part": 7 }), state, defs).is_empty())


func test_the_real_game_starts_on_goal_one_with_a_hint() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	main.get_node("Bridge").set_paused(true)
	var panel: GoalPanel = main.goal_panel
	assert_eq(panel._title.text, "Goal 1 of 10: Scan an asteroid")
	assert_string_contains(panel._hint.text, "Scan")


func test_the_list_opens_and_marks_done_goals() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	main.get_node("Bridge").set_paused(true)
	var panel: GoalPanel = main.goal_panel
	panel.toggle_list()
	panel.tracker.complete("scan")
	panel.refresh()
	assert_true(panel._list.visible)
	assert_string_contains(panel._list.get_child(0).text, "[x]")
	assert_string_contains(panel._list.get_child(1).text, "[  ]")
	assert_eq(panel._title.text, "Goal 2 of 10: Mine ore")


func test_finishing_everything_says_so() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	main.get_node("Bridge").set_paused(true)
	var panel: GoalPanel = main.goal_panel
	for goal: Dictionary in GoalTracker.GOALS:
		panel.tracker.complete(goal["id"])
	panel.refresh()
	assert_eq(panel._title.text, "All ten goals done")


func test_h_hides_the_goals() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	main.get_node("Bridge").set_paused(true)
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_H
	main._unhandled_key_input(key)
	assert_false(main.goal_panel.visible)


func test_goals_finish_and_announce_on_the_real_sim() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.set_speed(8)
	var view: LocalView = main.get_node("LocalView")
	var panel: OrderPanel = main.order_panel
	assert_true(panel.press("Undock"))
	for i in range(40):
		bridge.set_paused(false)
		bridge.advance(0.1)
	var state: Dictionary = bridge.current_view
	var rock := 0
	for id: int in state["bodies"]:
		if state["bodies"][id]["name"] == "Red Rock":
			rock = id
	view.select("body", rock, 0)
	assert_true(panel.press("Move to"))
	for i in range(160):
		bridge.advance(0.1)
	view.select("body", rock, 0)
	assert_true(panel.press("Scan"))
	for i in range(60):
		bridge.advance(0.1)
	assert_true(main.goal_panel.tracker.done.has("scan"))
	assert_string_contains("\n".join(main.event_log.lines), "Goal done: Scan an asteroid")
	assert_eq(main.goal_panel._title.text, "Goal 2 of 10: Mine ore")


func test_fitting_works_on_a_selected_station_for_check_9() -> void:
	var main: Node = add_child_autofree(StubScene.build())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	var view: LocalView = main.get_node("LocalView")
	var station := 0
	for id: int in bridge.current_view["units"]:
		if bridge.current_view["units"][id]["kind"] == "station":
			station = id
	view.select("unit", station, 0)
	main.toggle_fitting()
	assert_eq(main.fitting_screen.fit_unit(), station)
	assert_eq(main.fitting_screen._title.text, "Fitting: Foothold")
	assert_gt(main.fitting_screen._stock.size(), 0, "a station fits from its own stock")


func test_a_blocked_fit_reaches_the_tracker() -> void:
	var main: Node = add_child_autofree(StubScene.build())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	var view: LocalView = main.get_node("LocalView")
	var ship: int = view.commanded_unit
	var screen: FittingScreen = main.fitting_screen
	var station := 0
	for id: int in bridge.current_view["units"]:
		if id != ship:
			station = id
	view.select("unit", station, 0)
	assert_true(main.order_panel.press("Dock"))
	bridge.set_paused(false)
	bridge.set_speed(8)
	for i in range(6):
		bridge.advance(0.1)
	bridge.set_paused(true)
	view.select("unit", ship, 0)
	main.toggle_fitting()
	for entry: Dictionary in screen._stock:
		if entry["item"] == "stub_laser":
			screen.choose(entry)
	for slot: Dictionary in FittingLogic.free_slots(screen.unit(), screen._modules):
		if slot["connector"] == "ext_a":
			screen.choose_slot(slot)
	assert_true(main.goal_panel.tracker._blocked_items.has("stub_laser"))
