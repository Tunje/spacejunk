extends GutTest
## All ten goals on the real Sim through the real panels, from one shared run.

const SAVE_PATH := "user://test_playthrough.save"
const LAP_LIMIT := 2000

var main: Node
var player: PanelPlayer
var hash_saved := ""
var hash_loaded := ""
var laps_before_load := 0


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	add_child(main)
	player = PanelPlayer.new(main)
	var started := Time.get_ticks_msec()
	player.run()
	print("PLAYTHROUGH ticks=%d real_ms=%d goals=%s" % [
		player.bridge.current_view["tick"], Time.get_ticks_msec() - started, str(player.goal_order),
	])
	_save_and_load_mid_cycle()


## The hardest save there is: every goal done and a real drone mid-cycle.
func _save_and_load_mid_cycle() -> void:
	SaveStore.path = SAVE_PATH
	var bridge := player.bridge
	hash_saved = bridge.sim.state_hash()
	main.save_game()
	bridge.set_paused(false)
	for i in range(100):
		bridge.advance(0.1)
	bridge.set_paused(true)
	main.load_game()
	hash_loaded = bridge.sim.state_hash()
	laps_before_load = player.laps
	bridge.set_paused(false)
	var count := 0
	while player.laps == laps_before_load and count < LAP_LIMIT:
		bridge.advance(0.1)
		count += 1
	bridge.set_paused(true)
	player.view.refresh(0.016)
	DirAccess.remove_absolute(SAVE_PATH)
	SaveStore.path = SaveStore.DEFAULT_PATH


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


func test_a_save_mid_cycle_restores_exactly() -> void:
	assert_eq(hash_loaded, hash_saved)


func test_the_drone_carries_on_after_a_load() -> void:
	assert_gt(player.laps, laps_before_load, "another lap finished after the load")


func test_all_goals_survive_that_load() -> void:
	for goal: Dictionary in GoalTracker.GOALS:
		assert_true(player.goals.done.has(goal["id"]), goal["id"])


func test_the_real_parts_are_on_the_craft_in_the_scene() -> void:
	var ship_parts: int = InspectText.flatten(player.unit(player.ship)["parts"]).size()
	assert_eq(player.view.crafts[player.ship].part_transforms.size(), ship_parts)
	assert_true(player.view.crafts.has(player.drone))
