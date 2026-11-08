extends GutTest
## D31, stage 1 in the real client (NewStartPlayer): from a new game, the probe
## prospects, refines and builds the station, fits it through a refused fit, and
## hauls ore into it, by the client's own controls.

var main: Node
var player: NewStartPlayer


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	player = NewStartPlayer.new(main, 0)
	player.stage_chain()
	for line in player.friction:
		gut.p("friction: " + line)
	gut.p("warp drops: %s" % str(player.drops))


func after_all() -> void:
	main.free()


func test_the_stage_plays_through_the_client() -> void:
	assert_eq(player.problems, PackedStringArray())


func test_the_station_is_built_fitted_and_holds_ore() -> void:
	var station: Dictionary = player.unit(player.station)
	assert_false(station.is_empty(), "built")
	var defs: Array = InspectText.flatten(station.get("parts", {})).map(func(part: Dictionary) -> String: return part["def"])
	for def in ["lidar_mk1", "solar_panel_mk1", "heat_radiator_mk1", "ore_container_mk1"]:
		assert_has(defs, def)
	assert_gt(player.held(player.station, "hematite"), 0, "ore hauled in")
	assert_true(player.main.goal_panel.tracker.done.has("fix"), "a fit over the limits, then brought back (C30)")
