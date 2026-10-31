extends GutTest
## What the order panel shows while a craft docks or undocks, on the real Sim.

var main: Node
var bridge: SimBridge
var view: LocalView
var panel: OrderPanel
var ship: int
var station: int


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.set_speed(1)
	view = main.get_node("LocalView")
	panel = main.order_panel
	ship = view.commanded_unit
	var state := bridge.current_view
	for id: int in state["units"]:
		if id != ship:
			station = id


func _op_type() -> String:
	return bridge.current_view["units"][ship]["op"]["type"]


func _run_ticks(ticks: int) -> void:
	bridge.set_paused(false)
	for i in range(ticks):
		bridge.advance(0.1)
	bridge.set_paused(true)
	panel.refresh()


func _run_until_idle() -> void:
	_run_ticks(1)
	while _op_type() != "idle":
		_run_ticks(10)


## Leaves the ship free beside the station, with the station selected.
func _undock_and_select_station() -> void:
	panel.press("Undock")
	_run_until_idle()
	view.select("unit", station, 0)


func test_undock_button_shows_progress_at_once_when_paused() -> void:
	var button := panel.button_for("Undock")
	assert_true(panel.press("Undock"))
	assert_eq(button.text, "Undocking 0%")
	assert_true(button.disabled, "a second click cannot queue it twice")


func test_undock_button_reads_as_progress_not_a_refusal() -> void:
	panel.press("Undock")
	_run_ticks(31)
	var button := panel.button_for("Undock")
	assert_eq(_op_type(), "undocking")
	assert_string_starts_with(button.text, "Undocking 3")
	assert_eq(button.tooltip_text, "")
	assert_eq(button.get_theme_color("font_disabled_color"), ClientTheme.ORANGE)
	assert_ne(button.get_theme_stylebox("disabled"), ClientTheme.build().get_stylebox("disabled", "Button"))


func test_other_orders_name_undocking_while_it_runs() -> void:
	view.select("unit", station, 0)
	panel.press("Undock")
	_run_ticks(5)
	assert_true(panel.button_for("Move to").disabled)
	assert_eq(panel.button_for("Move to").tooltip_text, "Wait for undocking to finish")
	assert_eq(panel._why_label.text, "Wait for undocking to finish")


func test_other_orders_name_docking_while_it_runs() -> void:
	_undock_and_select_station()
	panel.press("Dock")
	_run_ticks(5)
	assert_eq(panel.button_for("Move to").tooltip_text, "Wait for docking to finish")
	assert_eq(panel._why_label.text, "Wait for docking to finish")


func test_dock_button_shows_progress() -> void:
	_undock_and_select_station()
	assert_true(panel.press("Dock"))
	assert_eq(panel.button_for("Dock").text, "Docking 0%")
	_run_ticks(21)
	assert_string_starts_with(panel.button_for("Dock").text, "Docking 1")


func test_docking_stays_on_show_when_the_selection_moves() -> void:
	_undock_and_select_station()
	panel.press("Dock")
	_run_ticks(5)
	view.select("", 0, 0)
	assert_not_null(panel.button_for("Dock"))
	assert_string_starts_with(panel.button_for("Dock").text, "Docking")


func test_the_button_goes_back_to_normal_afterwards() -> void:
	_undock_and_select_station()
	panel.press("Dock")
	_run_until_idle()
	view.select("unit", ship, 0)
	var undock := panel.button_for("Undock")
	assert_eq(undock.text, "Undock")
	assert_false(undock.disabled)
	assert_false(undock.has_theme_stylebox_override("disabled"))


func test_a_kept_button_loses_the_running_look() -> void:
	var button := panel.button_for("Undock")
	panel.press("Undock")
	assert_true(button.has_theme_stylebox_override("disabled"))
	panel._clicked_tick = -1
	panel.refresh()
	assert_same(panel.button_for("Undock"), button)
	assert_eq(button.text, "Undock")
	assert_false(button.has_theme_stylebox_override("disabled"))
	assert_false(button.has_theme_color_override("font_disabled_color"))


func test_the_plain_reason_never_names_one_direction() -> void:
	assert_eq(OrderText.reason("busy_docking"), "Wait for the craft to finish at the port")


func test_stop_is_not_offered_during_a_plain_undock() -> void:
	panel.press("Undock")
	_run_ticks(5)
	assert_null(panel.button_for("Stop"))


func test_stop_is_not_offered_during_a_plain_dock() -> void:
	_undock_and_select_station()
	panel.press("Dock")
	_run_ticks(5)
	assert_null(panel.button_for("Stop"))


func test_a_stop_cannot_end_an_undock_on_the_real_sim() -> void:
	panel.press("Undock")
	_run_ticks(5)
	bridge.submit({ "type": "stop", "unit": ship, "args": {} })
	_run_ticks(2)
	assert_eq(_op_type(), "undocking", "it runs on alone")
	_run_until_idle()
	assert_true(bridge.current_view["units"][ship]["dock"].is_empty())


func test_stop_is_offered_as_stop_cycle_when_a_cycle_is_running() -> void:
	var state: Dictionary = bridge.current_view.duplicate(true)
	var unit: Dictionary = state["units"][ship]
	unit["op"]["type"] = "undocking"
	unit["cycle_task"] = 7
	state["tasks"][7] = { "kind": "cycle" }
	var orders := OrderList.build(state, bridge.defs()["modules"], bridge.defs()["items"], ship, "", 0)
	var stop: Array[Dictionary] = orders.filter(func(order: Dictionary) -> bool: return order["key"] == "Stop")
	assert_eq(stop.size(), 1)
	assert_eq(stop[0]["label"], "Stop cycle")


func test_stop_stays_plain_for_other_operations() -> void:
	var state: Dictionary = bridge.current_view.duplicate(true)
	state["units"][ship]["op"]["type"] = "mining"
	var orders := OrderList.build(state, bridge.defs()["modules"], bridge.defs()["items"], ship, "", 0)
	var labels: Array = orders.map(func(order: Dictionary) -> String: return order["label"])
	assert_true(labels.has("Stop"))
