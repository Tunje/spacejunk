extends GutTest
## D31, stage 4 in the real client (NewStartPlayer): the station undocked, the probe flown out of the cluster, landed on Frost, a surface sample taken. Starts from the bot's
## snapshot after stage 3 and plays this stage by the client's own controls.

var main: Node
var player: NewStartPlayer


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	player = NewStartPlayer.new(main, NewStartBot.STAGE_LAB)
	player.stage_frost_down()
	for line in player.friction:
		gut.p("friction: " + line)
	gut.p("warp drops: %s" % str(player.drops))


func after_all() -> void:
	main.free()


func test_the_stage_plays_through_the_client() -> void:
	assert_eq(player.problems, PackedStringArray())


func test_the_stage_ends_where_it_should() -> void:
	assert_eq(int(player.unit(player.probe)["landed"].get("body", 0)), player.frost)
	assert_gte(int(player.bridge.current_view["science"]["evidence"].get("surface", 0)), 1)
