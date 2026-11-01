extends GutTest
## The handover, on the real Sim through the real panels: fly a trip by hand,
## give the craft a tier 2 core, then repeat the route as a cycle.

const MAX_FRAMES := 8000

var main: Node
var bridge: SimBridge
var view: LocalView
var panel: OrderPanel
var screen: AutomationScreen
var ship: int
var station: int
var rock: int
var defs: Dictionary


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.set_speed(8)
	view = main.get_node("LocalView")
	panel = main.order_panel
	screen = main.automation_screen
	defs = bridge.defs()
	var state := bridge.current_view
	for id: int in state["units"]:
		if state["units"][id]["kind"] == "ship":
			ship = id
		else:
			station = id
	for id: int in state["bodies"]:
		if state["bodies"][id]["name"] == "Red Rock":
			rock = id


func _unit() -> Dictionary:
	return bridge.current_view["units"][ship]


func _run_ticks(ticks: int) -> void:
	bridge.set_paused(false)
	for i in range(ceili(ticks / 8.0)):
		bridge.advance(0.1)
	bridge.set_paused(true)
	view.refresh(0.016)
	panel.refresh()


func _run_order() -> void:
	bridge.set_paused(false)
	bridge.advance(0.1)
	var frames := 0
	while _unit()["op"]["type"] != "idle" and frames < MAX_FRAMES:
		bridge.advance(0.1)
		frames += 1
	bridge.set_paused(true)
	view.refresh(0.016)
	panel.refresh()


func _press_first(prefix: String) -> void:
	for key: String in panel._buttons:
		if key.begins_with(prefix) and not panel._buttons[key].disabled:
			panel.press(key)
			return
	fail_test("no enabled %s order" % prefix)


func _fly_trip_by_hand() -> void:
	panel.press("Undock")
	_run_order()
	view.select("body", rock, 0)
	panel.press("Move to")
	_run_order()
	panel.press("Scan")
	_run_order()
	view.select("body", rock, 0)
	_press_first("Mine ")
	_run_ticks(160)
	panel.press("Stop")
	_run_ticks(8)
	view.select("unit", station, 0)
	panel.press("Move to")
	_run_order()
	panel.press("Dock")
	_run_order()
	_press_first("Unload ")
	_run_order()


## Swaps the ship's basic core for an assisted one, through real commands.
func _fit_assisted_core() -> void:
	var sim: Sim = bridge.sim
	var mass: int = defs["modules"]["assisted_core"]["mass_g"]
	sim._state["units"][station]["inventory"]["assisted_core"] = mass
	var old_core: int = _unit()["core"]
	var hull: Dictionary = _unit()["parts"]
	sim.submit(FittingLogic.detach_command(ship, old_core, station))
	sim.submit(FittingLogic.attach_command(ship, { "item": "assisted_core", "from": station }, {
		"part": hull["id"], "connector": "core",
	}))
	_run_ticks(8)
	var cores := CyclePlan.cores(_unit(), defs["modules"])
	screen.assign(cores[0]["part"])
	_run_ticks(8)
	assert_eq(_unit()["core_tier"], 2)


func _command(type: String, args: Dictionary) -> Dictionary:
	return { "type": type, "unit": 1, "args": args }


func _trip_of(commands: Array) -> Array[Dictionary]:
	var trip: Array[Dictionary] = []
	for command: Dictionary in commands:
		CyclePlan.record(trip, command)
	return trip


func test_undocking_starts_a_new_trip() -> void:
	var trip := _trip_of([_command("move_to", { "target": 1 }), _command("undock", {})])
	assert_eq(trip.size(), 1)
	assert_eq(trip[0]["type"], "undock")


func test_a_changed_mind_replaces_the_move() -> void:
	var trip := _trip_of([_command("move_to", { "target": 1 }), _command("move_to", { "target": 2 })])
	assert_eq(trip.size(), 1)
	assert_eq(trip[0]["args"]["target"], 2)


func test_scans_and_stops_are_not_cycle_steps() -> void:
	assert_true(_trip_of([_command("scan", { "target": 1 }), _command("stop", {})]).is_empty())


func test_the_trip_keeps_only_what_a_cycle_can_hold() -> void:
	var commands: Array = []
	for i in range(30):
		commands.append(_command("load_cargo", { "from": 1, "item": "x" }))
	assert_eq(_trip_of(commands).size(), CyclePlan.MAX_STEPS)


func test_panel_orders_build_the_trip_with_readable_steps() -> void:
	_fly_trip_by_hand()
	var words: Array = screen.trip.map(func(step: Dictionary) -> String:
		return CyclePlan.step_text(step, bridge.current_view, defs))
	assert_eq(words[0], "Undock")
	assert_eq(words[1], "Fly to Red Rock")
	assert_eq(words[2], "Mine Hematite Ore")
	assert_eq(words[3], "Fly to Station")
	assert_eq(words[4], "Dock at Station")
	assert_eq(words[5], "Unload Hematite Ore")


func test_adapting_adds_the_propellant_load() -> void:
	_fly_trip_by_hand()
	var steps := screen.planned_steps()
	assert_eq(steps[0]["type"], "load_cargo", "first, so an empty drone can leave")
	assert_eq(steps[0]["args"]["item"], "propellant")


func test_a_trip_for_another_craft_uses_its_own_laser_and_port() -> void:
	_fly_trip_by_hand()
	var state: Dictionary = bridge.current_view.duplicate(true)
	var drone: Dictionary = state["units"][ship].duplicate(true)
	drone["dock"] = {}
	drone["parts"] = { "id": 900, "def": "small_hull", "parent_connector": "", "connector": "", "children": [
		{ "id": 901, "def": "small_docking_port_mk1", "parent_connector": "stack_top", "connector": "mount", "children": [] },
		{ "id": 902, "def": "small_mining_laser_mk1", "parent_connector": "side_a_nz", "connector": "mount", "children": [] },
	] }
	state["units"][910] = drone
	var steps := CyclePlan.adapt(screen.trip, 910, state, defs)
	for step: Dictionary in steps:
		if step["type"] == "start_mining":
			assert_eq(step["args"]["module"], 902)
		if step["type"] == "dock":
			assert_eq(step["args"]["port"], 901)


func test_a_tier_1_core_is_refused_with_the_reason() -> void:
	_fly_trip_by_hand()
	main.toggle_automation()
	screen.repeat_route()
	assert_eq(screen._message.text, "AI core tier is too low")
	assert_string_contains(screen._core_label.text, "tier 1")


func test_repeat_this_route_runs_a_real_cycle_unaided() -> void:
	_fly_trip_by_hand()
	_fit_assisted_core()
	main.toggle_automation()
	screen.repeat_route()
	assert_eq(screen._message.text, "", "the cycle is accepted")
	_run_ticks(8)
	screen.refresh()
	assert_string_contains(screen._cycle_title.text, "Cycle running")
	assert_gt(screen._cycle_box.get_child_count(), 5)
	var ore_at_start := int(bridge.current_view["units"][station]["cargo"]["ore"]["used_g"])
	var started: int = bridge.current_view["tick"]
	var frames := 0
	bridge.set_paused(false)
	while frames < MAX_FRAMES:
		bridge.advance(0.1)
		frames += 1
		var task := CyclePlan.running_cycle(_unit(), bridge.current_view)
		if task.get("cycle", 0) >= 1:
			break
	bridge.set_paused(true)
	var task := CyclePlan.running_cycle(_unit(), bridge.current_view)
	assert_gte(task.get("cycle", 0), 1, "a lap finished unaided")
	assert_gt(bridge.current_view["units"][station]["cargo"]["ore"]["used_g"], ore_at_start, "ore reached the station unaided")
	print("REAL_LAP ticks=%d" % (bridge.current_view["tick"] - started))
	screen.refresh()
	screen.stop_cycle()
	_run_ticks(16)
	screen.refresh()
	assert_eq(screen._cycle_title.text, "No cycle running")
	assert_false(screen._resume_button.disabled)
	_run_order()
	screen.resume_cycle()
	assert_eq(screen._message.text, "", "resume accepted, op %s" % _unit()["op"]["type"])
	_run_ticks(16)
	screen.refresh()
	assert_string_contains(screen._cycle_title.text, "Cycle running")


func test_a_bad_cycle_names_the_step() -> void:
	_fit_assisted_core()
	main.toggle_automation()
	screen.note_order({ "type": "undock", "unit": ship, "args": {} })
	screen.repeat_route()
	assert_string_contains(screen._message.text, "That cycle is not valid")


func test_a_blocked_step_shows_its_reason() -> void:
	var unit := { "parts": { "id": 1, "def": "starter_hull", "fault": "", "children": [] } }
	var task := { "state": "blocked", "reason": "port_busy" }
	assert_eq(CyclePlan.block_text(task, unit, defs["modules"]), "Docking port is busy")
	assert_eq(CyclePlan.block_text({ "state": "running" }, unit, defs["modules"]), "")


func test_core_offline_names_the_fault_behind_it() -> void:
	var unit := { "parts": { "id": 1, "def": "small_hull", "fault": "over_heat_limit", "children": [] } }
	var text := CyclePlan.block_text({ "state": "blocked", "reason": "core_offline" }, unit, defs["modules"])
	assert_string_contains(text, "AI core is offline")
	assert_string_contains(text, "Heat limit exceeded")


func test_the_inspection_panel_also_names_the_fault() -> void:
	var unit := {
		"op": { "type": "idle", "start_tick": 0, "end_tick": 0 }, "dock": {}, "task": 4,
		"parts": { "id": 1, "def": "x", "fault": "over_heat_limit", "children": [] },
	}
	var state := { "tick": 1, "tasks": { 4: { "state": "blocked", "reason": "core_offline" } } }
	assert_eq(InspectText.status(unit, state), "Idle. Blocked: AI core is offline (Heat limit exceeded)")


func test_only_one_side_screen_shows_at_a_time() -> void:
	main.toggle_automation()
	main.toggle_fitting()
	assert_false(screen.visible)
	main.toggle_industry()
	assert_false(main.fitting_screen.visible)
	main.toggle_automation()
	assert_false(main.industry_screen.visible)
	assert_true(panel.visible, "orders stay reachable")
	assert_true(panel.button_for("Undock") != null)
