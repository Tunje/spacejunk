extends GutTest
## D31, stage 5 in the real client (NewStartPlayer): the theory proven at the lab, the Assisted Core prototyped and bench-tested. Starts from the bot's
## snapshot after stage 4 and plays this stage by the client's own controls.

var main: Node
var player: NewStartPlayer


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	player = NewStartPlayer.new(main, NewStartBot.STAGE_LAP)
	player.stage_research()
	for line in player.friction:
		gut.p("friction: " + line)
	gut.p("warp drops: %s" % str(player.drops))


func after_all() -> void:
	main.free()


func test_the_stage_plays_through_the_client() -> void:
	assert_eq(player.problems, PackedStringArray())


func test_the_stage_ends_where_it_should() -> void:
	var research: Dictionary = player.bridge.current_view["research"]
	assert_true(research["theories"].has("autonomous_navigation"))
	assert_eq(research["designs"].get("assisted_core", ""), "qualified")
	assert_true(player.main.goal_panel.tracker.done.has("research"), "the research goal is done")
