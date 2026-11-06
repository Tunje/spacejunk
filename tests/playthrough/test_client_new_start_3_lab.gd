extends GutTest
## D31, stage 3 in the real client (NewStartPlayer): the tank topped up from ice, the lab built into the station, its core assigned through Auto. Starts from the bot's
## snapshot after stage 2 and plays this stage by the client's own controls.

var main: Node
var player: NewStartPlayer


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	player = NewStartPlayer.new(main, NewStartBot.STAGE_PREP)
	player.stage_lab()
	for line in player.friction:
		gut.p("friction: " + line)
	gut.p("warp drops: %s" % str(player.drops))


func after_all() -> void:
	main.free()


func test_the_stage_plays_through_the_client() -> void:
	assert_eq(player.problems, PackedStringArray())


func test_the_stage_ends_where_it_should() -> void:
	var defs: Array = InspectText.flatten(player.unit(player.station)["parts"]).map(func(part: Dictionary) -> String: return part["def"])
	assert_has(defs, "research_lab_mk1")
	assert_ne(int(player.unit(player.station)["core"]), 0, "core assigned")
