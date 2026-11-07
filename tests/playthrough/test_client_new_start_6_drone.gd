extends GutTest
## D39b, stage 6 in the real client (NewStartPlayer): the drone built at the station,
## fitted from the probe through the docked group, its core assigned, one lap flown by
## hand and repeated with Auto for three laps; then Part F's second ore store. Starts
## from the bot's snapshot after stage 5 and plays by the client's own controls.

var main: Node
var player: NewStartPlayer


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	player = NewStartPlayer.new(main, NewStartBot.STAGE_RESEARCH)
	player.stage_drone()
	if player.problems.is_empty():
		player.stage_part_f()
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


func test_the_station_grew() -> void:
	var station: Dictionary = player.unit(player.station)
	assert_eq(_count(station, "ore_container_mk1"), 2)
	assert_eq(_count(station, "propellant_tank_mk1"), 1)


func test_the_drone_goals_are_done() -> void:
	var done: Dictionary = player.main.goal_panel.tracker.done
	assert_true(done.has("drone"), "a working drone")
	assert_true(done.has("handover"), "a lap run by its core")
