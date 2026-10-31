extends GutTest

var rules: Array[Dictionary]
var grants: Array[Dictionary]


func before_each() -> void:
	rules = StandingOrdersMock.new_rules()
	grants = StandingOrdersMock.new_grants()


func _rule(id: String) -> Dictionary:
	for rule: Dictionary in rules:
		if rule["id"] == id:
			return rule
	return {}


func _grant(id: String) -> Dictionary:
	for grant: Dictionary in grants:
		if grant["id"] == id:
			return grant
	return {}


func _states() -> Array:
	return StandingOrdersMock.project(rules, grants).map(func(line: Dictionary) -> String: return line["state"])


func _text() -> String:
	var lines: Array = StandingOrdersMock.project(rules, grants).map(func(line: Dictionary) -> String: return line["text"])
	return "\n".join(lines)


func test_defaults_give_a_clean_plan() -> void:
	assert_does_not_have(_states(), "blocked")


func test_each_copy_of_the_rules_is_independent() -> void:
	_rule("keep_ore")["value"] = 1
	assert_ne(StandingOrdersMock.new_rules()[0]["value"], 1)
	assert_eq(StandingOrdersMock.RULES[0]["value"], 200)


func test_withdrawing_a_permission_blocks_the_rule_that_needs_it() -> void:
	_grant("spend_propellant")["on"] = false
	assert_has(_states(), "blocked")
	assert_string_contains(_text(), "depot propellant")


func test_a_target_beyond_the_fleet_needs_building_permissions() -> void:
	_rule("replace_drones")["value"] = 10
	assert_has(_states(), "blocked")
	_grant("build_drones")["on"] = true
	_grant("fabricate")["on"] = true
	assert_does_not_have(_states(), "blocked")
	assert_string_contains(_text(), "building 4 more")


func test_a_tight_trip_limit_is_flagged_not_blocked() -> void:
	_rule("trip_limit")["on"] = true
	assert_has(_states(), "limited")
	assert_does_not_have(_states(), "blocked")


func test_no_rules_means_the_core_waits() -> void:
	for rule: Dictionary in rules:
		rule["on"] = false
	assert_string_contains(_text(), "waits for you")


func test_ore_target_caps_at_the_fleet() -> void:
	_rule("keep_ore")["value"] = 2000
	assert_string_contains(_text(), "6 of 6")


func test_scene_toggles_with_the_key_and_closes_with_escape() -> void:
	var main: Node = add_child_autofree(StubScene.build())
	main.get_node("Bridge").set_paused(true)
	var screen: StandingOrdersScreen = main.standing_orders
	assert_false(screen.visible)
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_P
	main._unhandled_key_input(key)
	assert_true(screen.visible)
	key.physical_keycode = KEY_ESCAPE
	main._unhandled_key_input(key)
	assert_false(screen.visible)


func test_escape_closes_the_screen_before_the_map() -> void:
	var main: Node = add_child_autofree(StubScene.build())
	main.get_node("Bridge").set_paused(true)
	main.toggle_map()
	main.standing_orders.toggle()
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_ESCAPE
	main._unhandled_key_input(key)
	assert_false(main.standing_orders.visible)
	assert_true(main.system_map.is_open())


func test_screen_never_touches_the_simulation() -> void:
	var main: Node = add_child_autofree(StubScene.build())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	var before: String = bridge.sim.state_hash()
	var screen: StandingOrdersScreen = main.standing_orders
	screen.toggle()
	screen._on_rule_toggled(false, screen.rules[0])
	screen._on_grant_toggled(false, screen.grants[0])
	screen._on_value_changed(55.0, screen.rules[1])
	screen.move_rule(1, -1)
	assert_eq(bridge.sim.state_hash(), before)


func test_unchecked_boxes_have_a_visible_outline() -> void:
	var icon := ClientTheme.build().get_icon("unchecked", "CheckBox")
	assert_eq(icon.get_width(), ClientTheme.CHECK_ICON_PX)
	assert_gt(icon.get_image().get_pixel(2, 8).a, 0.9)
	assert_eq(icon.get_image().get_pixel(8, 8).a, 0.0)


func test_changes_update_the_projection_and_reordering_keeps_rules() -> void:
	var screen := StandingOrdersScreen.new()
	add_child_autofree(screen)
	var first_id: String = screen.rules[0]["id"]
	screen.move_rule(0, 1)
	assert_eq(screen.rules[1]["id"], first_id)
	screen.move_rule(0, -1)
	assert_eq(screen.rules[1]["id"], first_id, "moving past the top does nothing")
	var count := screen._projection_box.get_child_count()
	assert_gt(count, 0)
	screen._on_rule_toggled(false, screen.rules[1])
	await wait_process_frames(1)
	assert_lt(screen._projection_box.get_child_count(), count)
