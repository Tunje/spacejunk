extends GutTest
## All ten goals on the real Sim through the real panels, from one shared run.

var main: Node
var player: PanelPlayer


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	add_child(main)
	player = PanelPlayer.new(main)
	var started := Time.get_ticks_msec()
	player.run()
	print("PLAYTHROUGH ticks=%d real_ms=%d goals=%s" % [
		player.bridge.current_view["tick"], Time.get_ticks_msec() - started, str(player.goal_order),
	])


func after_all() -> void:
	main.free()


func test_the_run_had_no_problems() -> void:
	assert_eq(player.problems, PackedStringArray())


func test_every_goal_ticked() -> void:
	for goal: Dictionary in GoalTracker.GOALS:
		assert_true(player.goals.done.has(goal["id"]), goal["id"])
	assert_true(player.goals.current().is_empty())


func test_the_panel_says_all_goals_are_done() -> void:
	assert_eq(main.goal_panel._title.text, "All ten goals done")


func test_the_second_laser_is_refused_with_the_page_figures() -> void:
	assert_eq(player.refusal, "Over the heat budget: needs 280 kW, has 200 kW")


func test_the_radiator_fix_shows_on_the_ship() -> void:
	var ship: Dictionary = player.unit(player.ship)
	assert_eq(ship["fit"]["heat_rated_w"], 280000)
	assert_eq(ship["fit"]["heat_budget_w"], 400000)


func test_the_station_is_expanded() -> void:
	assert_eq(player.unit(player.station)["cargo"]["ore"]["cap_g"], 100000000)


func test_the_real_drone_ran_a_lap_unaided() -> void:
	assert_ne(player.drone, 0)
	assert_gte(player.laps, 1)
	assert_eq(player.unit(player.drone)["core_tier"], 2)


func test_the_drone_cycle_starts_with_propellant() -> void:
	var cycle: Array = player.unit(player.drone)["last_cycle"]
	assert_eq(cycle[0]["type"], "load_cargo")
	assert_eq(cycle[0]["args"]["item"], "propellant")


func test_the_real_parts_are_on_the_craft_in_the_scene() -> void:
	var ship_parts: int = InspectText.flatten(player.unit(player.ship)["parts"]).size()
	assert_eq(player.view.crafts[player.ship].part_transforms.size(), ship_parts)
	assert_true(player.view.crafts.has(player.drone))
