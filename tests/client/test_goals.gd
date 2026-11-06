extends GutTest

var tracker: GoalTracker
var defs: Dictionary
var items: Dictionary
var modules: Dictionary


func before_each() -> void:
	tracker = GoalTracker.new()
	defs = {
		"recipes": { "refine_iron": { "facility": "refinery" }, "frame": { "facility": "fabricator" } },
	}
	items = { "hematite": { "cargo_class": "ore" }, "iron": { "cargo_class": "goods" } }
	modules = {
		"hull": { "capabilities": {} },
		"laser": { "capabilities": { "mine": {} } },
		"thruster": { "capabilities": { "thruster": {} } },
		"ore_box": { "capabilities": { "storage": { "ore": {} } } },
		"tank": { "capabilities": { "storage": { "propellant": {} } } },
		"both_stores": { "capabilities": { "storage": { "ore": {}, "propellant": {} } } },
	}


func _view(units: Dictionary = {}, deposits: Dictionary = {}) -> Dictionary:
	return { "units": units, "deposits": deposits }


func _unit(kind: String, inventory: Dictionary = {}, parts: Dictionary = {}) -> Dictionary:
	var tree := parts if not parts.is_empty() else { "id": 1, "def": "hull", "children": [] }
	return { "kind": kind, "inventory": inventory, "parts": tree }


## A hull carrying one part of each named definition.
func _tree(fitted: Array[String], root: String = "hull") -> Dictionary:
	var hull := { "id": 1, "def": root, "children": [] }
	for index in range(fitted.size()):
		hull["children"].append({ "id": index + 2, "def": fitted[index], "children": [] })
	return hull


func _real_modules() -> Dictionary:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	main.get_node("Bridge").set_paused(true)
	return main.get_node("Bridge").defs()["modules"]


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
	assert_eq(tracker.observe_view(_view({}, { 5: {} }), items, modules), ["scan"] as Array[String])


func test_ore_aboard_finishes_mine_and_ore_at_a_station_finishes_haul() -> void:
	assert_eq(tracker.observe_view(_view({ 1: _unit("ship", { "hematite": 10 }) }), items, modules), ["mine"] as Array[String])
	assert_eq(tracker.observe_view(_view({ 2: _unit("station", { "hematite": 10 }) }), items, modules), ["haul"] as Array[String])


func test_goods_do_not_count_as_ore() -> void:
	assert_true(tracker.observe_view(_view({ 1: _unit("ship", { "iron": 10 }) }), items, modules).is_empty())


func test_finished_jobs_split_by_facility() -> void:
	assert_eq(tracker.observe_event(_event("job_finished", 1, { "recipe": "refine_iron" }), _view(), defs), ["refine"] as Array[String])
	assert_eq(tracker.observe_event(_event("job_finished", 1, { "recipe": "frame" }), _view(), defs), ["fabricate"] as Array[String])


func test_a_lap_finishes_the_handover() -> void:
	assert_eq(tracker.observe_event(_event("task_cycle_done", 1, { "task": 4, "cycle": 1 }), _view(), defs), ["handover"] as Array[String])


func test_a_new_craft_is_not_yet_a_drone() -> void:
	assert_true(tracker.observe_event(_event("unit_created", 2, { "unit": 3 }), _view(), defs).is_empty())
	assert_true(tracker.observe_view(_view({ 3: _unit("drone") }), items, modules).is_empty())


func test_a_drone_finishes_once_every_capability_is_fitted() -> void:
	var parts: Array[String] = ["laser", "thruster", "ore_box"]
	assert_true(tracker.observe_view(_view({ 3: _unit("drone", {}, _tree(parts)) }), items, modules).is_empty())
	parts.append("tank")
	assert_eq(tracker.observe_view(_view({ 3: _unit("drone", {}, _tree(parts)) }), items, modules), ["drone"] as Array[String])


func test_a_drone_counts_by_capability_not_part_id() -> void:
	var parts: Array[String] = ["laser", "thruster", "both_stores"]
	assert_eq(tracker.observe_view(_view({ 3: _unit("drone", {}, _tree(parts)) }), items, modules), ["drone"] as Array[String])


func test_a_ship_with_all_of_those_is_not_a_drone() -> void:
	var parts: Array[String] = ["laser", "thruster", "ore_box", "tank"]
	assert_true(tracker.observe_view(_view({ 3: _unit("ship", {}, _tree(parts)) }), items, modules).is_empty())


func test_medium_parts_on_the_real_small_hull_count() -> void:
	var parts: Array[String] = ["mining_laser_mk1", "chemical_thruster_mk1", "ore_container_mk1", "propellant_tank_mk1"]
	var state := _view({ 3: _unit("drone", {}, _tree(parts, "small_hull")) })
	assert_eq(tracker.observe_view(state, items, _real_modules()), ["drone"] as Array[String])


func test_attaching_to_a_ship_installs_and_to_a_station_expands() -> void:
	var state := _view({ 1: _unit("ship"), 2: _unit("station") })
	assert_eq(tracker.observe_event(_event("part_attached", 1, { "part": 1 }), state, defs), ["install"] as Array[String])
	assert_eq(tracker.observe_event(_event("part_attached", 2, { "part": 1 }), state, defs), ["expand"] as Array[String])


func test_attaching_to_a_drone_is_not_the_install_goal() -> void:
	var state := _view({ 3: _unit("drone") })
	assert_true(tracker.observe_event(_event("part_attached", 3, { "part": 1 }), state, defs).is_empty())


func test_the_drone_hint_names_the_parts_in_the_order_they_fit() -> void:
	var real := _real_modules()
	var hint: String = GoalTracker.GOALS[6]["hint"]
	var last := hint.find("Small Craft")
	assert_gte(last, 0)
	for fit: Dictionary in PanelPlayer.DRONE_FITS:
		var at := hint.find(real[fit["item"]]["name"])
		assert_gt(at, last, fit["item"])
		last = at


func test_the_core_hint_holds_on_the_real_sim() -> void:
	assert_string_contains(GoalTracker.GOALS[7]["hint"], "solar panel and radiator")
	for fitted: int in [0, 2]:
		var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
		var bridge: SimBridge = main.get_node("Bridge")
		bridge.set_paused(true)
		var drone := ScreenshotDriver.build_drone(bridge, fitted)
		ScreenshotDriver.stock_part(bridge, "assisted_core")
		var unit: Dictionary = bridge.current_view["units"][drone]
		var core_slot := { "part": unit["parts"]["id"], "connector": "core" }
		var from := { "item": "assisted_core", "from": unit["dock"]["target_unit"] }
		var result: Dictionary = bridge.check(FittingLogic.attach_command(drone, from, core_slot))
		if fitted == 0:
			assert_eq(result["reason"], "over_power_budget")
		else:
			assert_true(result["ok"], "fits with the solar panel and radiator on")


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


# --- D26: the new start's list (C13), picked by scenario ---

func _new_start() -> GoalTracker:
	return GoalTracker.new("new_start")


func test_the_start_picks_its_list() -> void:
	assert_eq(GoalTracker.new().goals, GoalTracker.GOALS, "reference by default")
	assert_eq(GoalTracker.new("reference").goals, GoalTracker.GOALS)
	var ids: Array = _new_start().goals.map(func(goal: Dictionary) -> String: return goal["id"])
	assert_eq(ids, ["scan", "science", "mine", "refine", "fabricate", "station", "install", "fix", "haul",
		"research", "drone", "handover", "expand"])
	for goal: Dictionary in GoalTracker.NEW_START_GOALS:
		assert_ne(goal["title"], "")
		assert_ne(goal["hint"], "")
		assert_false(goal["hint"].contains("Undock"), "nothing to undock from in the new start")


func test_science_needs_points() -> void:
	var goals := _new_start()
	var data := { "kind": "survey", "target": 4, "key": "survey:4", "points": 0 }
	assert_eq(goals.observe_event(_event("science_gained", 1, data), _view(), defs), [] as Array[String], "0 points")
	data["points"] = 12
	assert_eq(goals.observe_event(_event("science_gained", 1, data), _view(), defs), ["science"] as Array[String])


func test_a_built_station_finishes_station() -> void:
	var goals := _new_start()
	var with_templates := defs.duplicate()
	with_templates["templates"] = { "small_station": { "kind": "station" }, "small_craft": { "kind": "drone" } }
	var craft := { "unit": 30, "def": "small_craft", "job": 9 }
	assert_eq(goals.observe_event(_event("unit_created", 1, craft), _view(), with_templates), [] as Array[String])
	var station := { "unit": 31, "def": "small_station", "job": 10 }
	assert_eq(goals.observe_event(_event("unit_created", 1, station), _view(), with_templates), ["station"] as Array[String])


func test_research_is_the_assisted_core_qualified() -> void:
	var goals := _new_start()
	assert_eq(goals.observe_event(_event("design_qualified", 5, { "design": "other_core" }), _view(), defs), [] as Array[String])
	assert_eq(goals.observe_event(_event("design_qualified", 5, { "design": "assisted_core" }), _view(), defs),
		["research"] as Array[String])


func test_new_start_install_counts_only_on_something_built() -> void:
	var goals := _new_start()
	var view := _view({ 1: _unit("ship", {}, _tree(["laser"])), 31: _unit("station", {}, _tree(["laser"])) })
	assert_eq(goals.observe_event(_event("part_attached", 1, { "part": 2 }), view, defs), [] as Array[String],
		"the probe was never built")
	goals.observe_event(_event("unit_created", 1, { "unit": 31, "def": "small_station", "job": 10 }), view, defs)
	assert_eq(goals.observe_event(_event("part_attached", 31, { "part": 2 }), view, defs), ["install"] as Array[String])


func test_reference_install_still_needs_a_ship_and_ignores_built_drones() -> void:
	var view := _view({ 1: _unit("ship", {}, _tree(["laser"])), 30: _unit("drone", {}, _tree(["laser"])) })
	tracker.observe_event(_event("unit_created", 2, { "unit": 30, "def": "small_craft", "job": 9 }), view, defs)
	assert_eq(tracker.observe_event(_event("part_attached", 30, { "part": 2 }), view, defs), [] as Array[String])
	assert_eq(tracker.observe_event(_event("part_attached", 1, { "part": 2 }), view, defs), ["install"] as Array[String])


func test_new_start_expand_waits_for_handover() -> void:
	var goals := _new_start()
	var view := _view({ 31: _unit("station", {}, _tree(["laser"])) })
	assert_eq(goals.observe_event(_event("part_attached", 31, { "part": 2 }), view, defs), [] as Array[String],
		"a station fit before handover is not yet expanding")
	goals.observe_event(_event("task_cycle_done", 30, {}), view, defs)
	assert_eq(goals.observe_event(_event("part_attached", 31, { "part": 2 }), view, defs), ["expand"] as Array[String])


func test_built_units_survive_a_save() -> void:
	var goals := _new_start()
	goals.observe_event(_event("unit_created", 1, { "unit": 31, "def": "small_station", "job": 10 }), _view(), defs)
	var again := _new_start()
	again.restore_state(JSON.parse_string(JSON.stringify(goals.save_state())))
	var view := _view({ 31: _unit("station", {}, _tree(["laser"])) })
	assert_eq(again.observe_event(_event("part_attached", 31, { "part": 2 }), view, defs), ["install"] as Array[String])


func test_view_shows_science_station_and_research_for_a_loaded_game() -> void:
	var goals := _new_start()
	var view := _view({ 31: _unit("station") })
	view["science"] = { "earned": 40 }
	view["research"] = { "designs": { "assisted_core": "qualified" } }
	var finished := goals.observe_view(view, items, modules)
	for id in ["science", "station", "research"]:
		assert_has(finished, id)


func test_the_new_start_panel_shows_thirteen_goals() -> void:
	var main: Node = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child_autofree(main)
	main.get_node("Bridge").set_paused(true)
	var panel: GoalPanel = main.goal_panel
	assert_eq(panel.tracker.goals, GoalTracker.NEW_START_GOALS)
	assert_eq(panel._title.text, "Goal 1 of 13: Scan a rock")
	assert_eq(panel._list.get_child_count(), 13)
	for goal: Dictionary in panel.tracker.goals:
		panel.tracker.complete(goal["id"])
	panel.refresh()
	assert_eq(panel._title.text, "All 13 goals done")
