extends GutTest
## D31, stage 6 in the real client (NewStartPlayer): home to the station and docked. Starts from the bot's
## snapshot after stage 5 and plays this stage by the client's own controls.

var main: Node
var player: NewStartPlayer


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	player = NewStartPlayer.new(main, NewStartBot.STAGE_FROST_LAP)
	player.stage_return()
	for line in player.friction:
		gut.p("friction: " + line)
	gut.p("warp drops: %s" % str(player.drops))


func after_all() -> void:
	main.free()


func test_the_stage_plays_through_the_client() -> void:
	assert_eq(player.problems, PackedStringArray())


func test_the_stage_ends_where_it_should() -> void:
	var probe: Dictionary = player.unit(player.probe)
	assert_eq(int(probe["dock"].get("target_unit", 0)), player.station, "docked at the station")
