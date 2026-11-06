extends GutTest
## D31, stage 5 in the real client (NewStartPlayer): the climb to a low orbit and a lap mapping Frost's gravity field. Starts from the bot's
## snapshot after stage 4 and plays this stage by the client's own controls.

var main: Node
var player: NewStartPlayer


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	player = NewStartPlayer.new(main, NewStartBot.STAGE_FROST_DOWN)
	player.stage_frost_lap()
	for line in player.friction:
		gut.p("friction: " + line)
	gut.p("warp drops: %s" % str(player.drops))


func after_all() -> void:
	main.free()


func test_the_stage_plays_through_the_client() -> void:
	assert_eq(player.problems, PackedStringArray())


func test_the_stage_ends_where_it_should() -> void:
	assert_true(player.unit(player.probe)["landed"].is_empty())
	assert_gte(int(player.bridge.current_view["science"]["evidence"].get("gravity_field", 0)), 1)
