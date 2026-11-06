extends GutTest
## D31, stage 4 in the real client (NewStartPlayer): Frost's gravity field mapped from the cluster, docked at the station, over one warped lap (C18b). Starts from the bot's
## snapshot after stage 3 and plays this stage by the client's own controls.

var main: Node
var player: NewStartPlayer


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	player = NewStartPlayer.new(main, NewStartBot.STAGE_LAB)
	player.stage_lap()
	for line in player.friction:
		gut.p("friction: " + line)
	gut.p("warp drops: %s" % str(player.drops))


func after_all() -> void:
	main.free()


func test_the_stage_plays_through_the_client() -> void:
	assert_eq(player.problems, PackedStringArray())


func test_the_stage_ends_where_it_should() -> void:
	var science: Dictionary = player.bridge.current_view["science"]
	assert_gte(int(science["evidence"].get("gravity_field", 0)), 1, "the lap is mapped")
	assert_eq(int(science["points"]), 140, "4 surveys, 3 compositions and the lap")
	assert_eq(FittingLogic.docked_with(player.bridge.current_view, player.probe), [player.station] as Array[int],
		"still docked at the station (its dock record, as it was built at the probe's port)")
