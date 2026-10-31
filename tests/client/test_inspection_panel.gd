extends GutTest

var main: Node
var bridge: SimBridge
var view: LocalView
var panel: InspectionPanel
var ship: int
var station: int


func before_each() -> void:
	main = add_child_autofree(StubScene.build())
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	view = main.get_node("LocalView")
	panel = main.inspection_panel
	var state := bridge.current_view
	for id: int in state["units"]:
		if state["units"][id]["kind"] == "ship":
			ship = id
		else:
			station = id


func _cargo(used_g: int, cap_g: int, used_l: int, cap_l: int, reserved_g: int = 0, reserved_l: int = 0) -> Dictionary:
	return {
		"used_g": used_g, "cap_g": cap_g, "used_l": used_l, "cap_l": cap_l,
		"reserved_g": reserved_g, "reserved_l": reserved_l,
	}


func _part(state: String, fault: String = "", draw_w: int = 0) -> Dictionary:
	return { "id": 1, "state": state, "fault": fault, "draw_w": draw_w, "children": [] }


func test_units_read_cleanly() -> void:
	assert_eq(InspectText.watts(750), "750 W")
	assert_eq(InspectText.watts(150000), "150 kW")
	assert_eq(InspectText.watts(2400000), "2.4 MW")
	assert_eq(InspectText.joules(40000000), "40.0 MJ")


func test_ratio_handles_empty_and_overfull() -> void:
	assert_eq(InspectText.ratio(5, 0), 0.0)
	assert_eq(InspectText.ratio(15, 10), 1.0)


func test_cargo_fill_uses_the_tighter_limit() -> void:
	assert_almost_eq(InspectText.cargo_ratio(_cargo(100, 1000, 90, 100)), 0.9, 0.001)
	assert_almost_eq(InspectText.cargo_ratio(_cargo(900, 1000, 10, 100)), 0.9, 0.001)


func test_reserved_space_counts_as_taken() -> void:
	assert_almost_eq(InspectText.cargo_ratio(_cargo(100, 1000, 0, 100, 400, 0)), 0.5, 0.001)
	assert_string_contains(InspectText.cargo_line(_cargo(2000000, 8000000, 0, 100, 1000000, 0)), "reserved")


func test_inventory_lists_names_in_order_and_skips_empty_stacks() -> void:
	var items := { "iron": { "name": "Iron" }, "copper": { "name": "Copper" } }
	assert_eq(InspectText.inventory({ "iron": 5000, "copper": 2000000, "air": 0 }, items), "2.0 t Copper, 5.0 kg Iron")


func test_blocked_task_shows_its_reason() -> void:
	var unit := {
		"op": { "type": "idle", "start_tick": 0, "end_tick": 0 }, "dock": {}, "task": 4,
	}
	var state := { "tick": 1, "tasks": { 4: { "state": "blocked", "reason": "no_propellant" } } }
	assert_eq(InspectText.status(unit, state), "Idle. Blocked: Out of propellant")


func test_status_shows_progress() -> void:
	var unit := { "op": { "type": "moving", "start_tick": 10, "end_tick": 20 }, "dock": {}, "task": 0 }
	assert_eq(InspectText.status(unit, { "tick": 15, "tasks": {} }), "Moving 50%")


func test_core_line() -> void:
	assert_eq(InspectText.core({ "core_tier": 0 }), "No AI core")
	assert_eq(InspectText.core({ "core_tier": 2 }), "AI core: tier 2")


func test_part_lines_show_state() -> void:
	var module := { "name": "Laser" }
	assert_eq(InspectText.part_line(_part("on", "", 150000), module), "Laser: 150 kW")
	assert_eq(InspectText.part_line(_part("on"), module), "Laser")
	assert_eq(InspectText.part_line(_part("shed"), module), "Laser: shed")
	assert_eq(InspectText.part_line(_part("fault", "over_heat_limit"), module), "Laser: fault, Heat limit exceeded")


func test_part_colours_flag_trouble() -> void:
	assert_eq(InspectText.part_colour(_part("fault")), ClientTheme.ORANGE)
	assert_eq(InspectText.part_colour(_part("shed")), ClientTheme.GOLD)
	assert_eq(InspectText.part_colour(_part("on")), Color.WHITE)


func test_panel_shows_the_selected_craft() -> void:
	view.select("unit", station, 0)
	assert_eq(panel._title.text, "Foothold")
	view.select("unit", ship, 0)
	assert_eq(panel._title.text, "First Probe")


func test_panel_falls_back_to_the_commanded_craft() -> void:
	var bodies: Array = bridge.current_view["bodies"].keys()
	view.select("body", bodies[1], 0)
	assert_eq(panel.shown_unit(), ship)
	view.clear_selection()
	assert_eq(panel.shown_unit(), ship)


func test_panel_lists_every_part_and_each_cargo_class() -> void:
	var unit: Dictionary = bridge.current_view["units"][ship]
	assert_eq(panel.part_line_count(), InspectText.flatten(unit["parts"]).size())
	assert_eq(panel._cargo_rows.size(), unit["cargo"].size())


func test_panel_figures_change_with_the_sim() -> void:
	var hull_before: String = panel._power_label.text
	var bodies: Array = bridge.current_view["bodies"].keys()
	bodies.sort()
	var rock: int = bodies[1]
	view.select("body", rock, 0)
	assert_true(main.order_panel.press("Move to"))
	bridge.set_paused(false)
	bridge.set_speed(8)
	for i in range(30):
		bridge.advance(0.1)
	bridge.set_paused(true)
	view.refresh(0.016)
	assert_string_contains(panel._status.text, "Idle")
	assert_true(main.order_panel.press("Scan"))
	bridge.set_paused(false)
	bridge.advance(0.1)
	bridge.set_paused(true)
	assert_string_contains(panel._status.text, "Scanning")
	assert_eq(panel._power_label.text, hull_before, "scanning has no extra stub draw")


func test_rows_are_kept_across_ticks() -> void:
	var first: Node = panel._parts_box.get_child(0)
	panel.refresh()
	panel.refresh()
	assert_same(panel._parts_box.get_child(0), first)


func test_hidden_battery_rows_when_there_is_no_battery() -> void:
	assert_false(panel._battery_bar.visible)


func test_battery_rows_appear_when_a_craft_has_storage() -> void:
	var unit: Dictionary = bridge.current_view["units"][ship].duplicate(true)
	unit["power"]["capacity_j"] = 4000
	unit["power"]["stored_j"] = 1000
	panel._refresh_power(unit)
	assert_true(panel._battery_bar.visible)
	assert_almost_eq(panel._battery_bar.value, 0.25, 0.001)
	assert_string_contains(panel._battery_label.text, "1 kJ of 4 kJ")


func test_empty_bars_keep_a_visible_track() -> void:
	var track := panel._heat_bar.get_theme_stylebox("background") as StyleBoxFlat
	assert_not_null(track)
	assert_gt(track.bg_color.a, 0.9)
	assert_gt(track.bg_color.get_luminance(), 0.1)


func test_nearly_full_bars_are_flagged() -> void:
	var unit: Dictionary = bridge.current_view["units"][ship].duplicate(true)
	unit["heat"]["limit_j"] = 100
	unit["heat"]["stored_j"] = 95
	panel._refresh_heat(unit)
	assert_eq(panel._heat_bar.modulate, ClientTheme.ORANGE)
