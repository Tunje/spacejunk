extends GutTest
## D31, stage 2 in the real client (NewStartPlayer): composition measured at three rocks; the station's core, goods container and second solar panel built in place. Starts from the bot's
## snapshot after stage 1 and plays this stage by the client's own controls.

var main: Node
var player: NewStartPlayer


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	player = NewStartPlayer.new(main, NewStartBot.STAGE_CHAIN)
	player.stage_prep()
	for line in player.friction:
		gut.p("friction: " + line)
	gut.p("warp drops: %s" % str(player.drops))


func after_all() -> void:
	main.free()


func test_the_stage_plays_through_the_client() -> void:
	assert_eq(player.problems, PackedStringArray())


func test_the_stage_ends_where_it_should() -> void:
	var defs: Array = InspectText.flatten(player.unit(player.station)["parts"]).map(func(part: Dictionary) -> String: return part["def"])
	for def in ["basic_core", "goods_container_mk1"]:
		assert_has(defs, def, "built in place")
	assert_eq(defs.count("solar_panel_mk1"), 2)
	assert_gte(int(player.bridge.current_view["science"]["evidence"].get("composition", 0)), 3)
