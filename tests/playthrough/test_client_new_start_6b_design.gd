extends GutTest
## D42, stage 6 by design: the ore the Mining Drone's plan lacks mined, then one press
## of Build with components and one of Fit all in place of the jobs and fits one by
## one; the lap, Auto and three laps as in stage 6. From the bot's snapshot after stage 5.

var main: Node
var player: NewStartPlayer


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	player = NewStartPlayer.new(main, NewStartBot.STAGE_RESEARCH)
	player.stage_drone_by_design()
	for line in player.friction:
		gut.p("friction: " + line)
	gut.p("warp drops: %s" % str(player.drops))


func after_all() -> void:
	main.free()


func _count(unit: Dictionary, def: String) -> int:
	var found := 0
	for part: Dictionary in InspectText.flatten(unit.get("parts", {})):
		if part["def"] == def:
			found += 1
	return found


func test_the_stage_plays_through_the_client() -> void:
	assert_eq(player.problems, PackedStringArray())


func test_the_drone_is_fitted_and_ran_three_laps() -> void:
	var drone: Dictionary = player.unit(player.drone)
	for entry: Array in NewStartPlayer.DRONE_FIT:
		assert_eq(_count(drone, entry[0]), 1, entry[0])
	assert_eq(int(drone.get("core_tier", 0)), 2)
	assert_eq(player.laps, NewStartPlayer.DRONE_LAPS)
	assert_false(drone.get("dock", {}).is_empty(), "stopped at the station")
	assert_true(CyclePlan.running_cycle(drone, player.bridge.current_view).is_empty(), "the cycle stopped")


func test_the_drone_goals_are_done() -> void:
	var done: Dictionary = player.main.goal_panel.tracker.done
	assert_true(done.has("drone"), "a working drone")
	assert_true(done.has("handover"), "a lap run by its core")
