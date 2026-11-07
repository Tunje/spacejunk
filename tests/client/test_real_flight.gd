extends GutTest
## Flies the whole loop on the real Sim through the real order panel, the way
## the owner will: undock, fly, scan, mine, return, dock, unload, refuel.

const MAX_FRAMES := 4000

var main: Node
var bridge: SimBridge
var view: LocalView
var panel: OrderPanel
var ship: int
var station: int
var rock: int


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = "reference"
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.set_speed(8)
	view = main.get_node("LocalView")
	panel = main.order_panel
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


## Runs until the ship has been busy and is idle again, and returns the ticks taken.
func _run_order() -> int:
	var started: int = bridge.current_view["tick"]
	bridge.set_paused(false)
	var frames := 0
	bridge.advance(0.1)
	while _unit()["op"]["type"] != "idle" and frames < MAX_FRAMES:
		bridge.advance(0.1)
		frames += 1
	bridge.set_paused(true)
	view.refresh(0.016)
	panel.refresh()
	return bridge.current_view["tick"] - started


func _run_ticks(ticks: int) -> void:
	bridge.set_paused(false)
	for i in range(ceili(ticks / 8.0)):
		bridge.advance(0.1)
	bridge.set_paused(true)
	view.refresh(0.016)
	panel.refresh()


func _press_mine() -> bool:
	for key: String in panel._buttons:
		if key.begins_with("Mine ") and not panel._buttons[key].disabled:
			return panel.press(key)
	return false


func _press_first(prefix: String) -> bool:
	for key: String in panel._buttons:
		if key.begins_with(prefix) and not panel._buttons[key].disabled:
			return panel.press(key)
	return false


func _fly_to_rock() -> int:
	assert_true(panel.press("Undock"), "undock")
	_run_order()
	view.select("body", rock, 0)
	assert_true(panel.press("Move to"), "move to rock")
	return _run_order()


func test_the_default_game_is_the_real_sim() -> void:
	assert_true(bridge.sim is Sim)


func test_the_whole_loop_on_the_real_sim() -> void:
	var move_ticks := _fly_to_rock()
	assert_eq(_unit()["at_target"], rock)
	assert_true(panel.press("Scan"), "scan")
	var scan_ticks := _run_order()
	assert_true(bridge.current_view["bodies"][rock]["scanned"])
	view.select("body", rock, 0)
	assert_true(_press_mine(), "mine")
	_run_ticks(160)
	assert_eq(_unit()["op"]["type"], "mining")
	var ore := InspectText.inventory(_unit()["inventory"], bridge.defs()["items"])
	assert_string_contains(ore, "Ore")
	assert_true(panel.press("Stop"), "stop")
	_run_ticks(8)
	view.select("unit", station, 0)
	assert_true(panel.press("Move to"), "return")
	_run_order()
	assert_true(panel.press("Dock"), "dock")
	var dock_ticks := _run_order()
	assert_false(_unit()["dock"].is_empty())
	assert_true(_press_first("Unload "), "unload")
	var unload_ticks := _run_order()
	assert_eq(bridge.current_view["units"][ship]["cargo"]["ore"]["used_g"], 0)
	assert_true(_press_first("Load "), "refuel")
	_run_order()
	print("REAL_TIMINGS move=%d scan=%d dock=%d unload=%d" % [move_ticks, scan_ticks, dock_ticks, unload_ticks])


func test_feedback_runs_from_the_real_view() -> void:
	_fly_to_rock()
	assert_true(panel.press("Scan"), "scan")
	_run_ticks(16)
	assert_true(view.beams[ship].visible, "scan beam")
	_run_order()
	view.select("body", rock, 0)
	assert_true(_press_mine(), "mine")
	_run_ticks(16)
	assert_true(view.beams[ship].visible, "mining beam")


func test_plume_shows_on_a_real_trip() -> void:
	assert_true(panel.press("Undock"), "undock")
	_run_order()
	view.select("body", rock, 0)
	assert_true(panel.press("Move to"), "move")
	_run_ticks(16)
	assert_true(view.crafts[ship].is_thrust_shown())


func test_a_docking_part_pulses_through_op_port() -> void:
	assert_true(panel.press("Undock"), "undock")
	_run_ticks(4)
	assert_gt(Feedback.working_part(_unit()), 0)


func test_docking_takes_a_free_port_while_one_is_taken() -> void:
	var state: Dictionary = bridge.current_view
	var modules: Dictionary = bridge.defs()["modules"]
	var used := OrderList.ports_in_use(state)
	assert_true(used.has(state["units"][ship]["dock"]["target_port"]))
	var free := OrderList.free_port(state["units"][station]["parts"], modules, used)
	assert_gt(free, 0)
	assert_ne(free, state["units"][ship]["dock"]["target_port"])


func test_frame_probe_orders_work_on_the_real_sim() -> void:
	var order := FrameProbe.next_order(bridge.current_view, ship, 0, [rock])
	assert_eq(order["type"], "undock")
	assert_true(bridge.check(order)["ok"])


func test_too_hard_reads_cleanly() -> void:
	assert_eq(OrderText.reason("too_hard"), "Too hard for this laser")
