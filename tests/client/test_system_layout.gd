extends GutTest
## D37: the System view lays out the star's planets, their moons, frames and craft
## round what each orbits, with every orbit drawn, from the view alone.

var main: Node
var bridge: SimBridge


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)


func after_all() -> void:
	main.free()


func _id(table: String, name: String) -> int:
	for id: int in bridge.current_view[table]:
		if bridge.current_view[table][id]["name"] == name:
			return id
	return 0


func test_each_thing_hangs_off_what_it_orbits() -> void:
	var view := bridge.current_view
	var star := _id("bodies", "Star")
	var planet := _id("bodies", "Planet")
	var frost := _id("bodies", "Frost")
	var cluster := _id("frames", "Cluster")
	assert_eq(SystemLayout.parent_of(view, "body", star), "")
	assert_eq(SystemLayout.parent_of(view, "body", planet), "body:%d" % star)
	assert_eq(SystemLayout.parent_of(view, "body", frost), "body:%d" % planet)
	assert_eq(SystemLayout.parent_of(view, "frame", cluster), "body:%d" % frost)
	assert_eq(SystemLayout.parent_of(view, "body", _id("bodies", "Red Rock")), "frame:%d" % cluster)
	assert_eq(SystemLayout.parent_of(view, "unit", _id("units", "Probe")), "frame:%d" % cluster)


func test_the_star_is_central_and_moons_sit_near_their_planet() -> void:
	var view := bridge.current_view
	var placed := SystemLayout.positions(view)
	var star: Vector3 = placed["body:%d" % _id("bodies", "Star")]["pos"]
	var planet: Vector3 = placed["body:%d" % _id("bodies", "Planet")]["pos"]
	var frost: Vector3 = placed["body:%d" % _id("bodies", "Frost")]["pos"]
	assert_eq(star, Vector3.ZERO)
	assert_gt(planet.length(), 10.0, "the planet well out from the star")
	assert_lt((frost - planet).length(), planet.length() * 0.5, "Frost close by its planet, not across the system")
	var rings := SystemLayout.orbit_rings(view, placed)
	assert_eq(rings.size(), 3, "the planet's, Frost's and the cluster's orbits")
	assert_almost_eq(rings[0]["radius"], planet.length(), 0.5, "the planet sits on its ring")


func test_the_map_toggles_to_the_system_view() -> void:
	main.toggle_map()
	var map: SystemMap = main.system_map
	map.toggle_system()
	assert_true(map.system_view)
	var star_entry: Array = map.entries.filter(func(entry: Dictionary) -> bool: return entry["label"] == "Star")
	assert_eq(star_entry[0]["map_pos"], Vector3.ZERO, "the star at the centre")
	assert_eq(map.frame_labels.size(), 1)
	map.toggle_system()
	assert_false(map.system_view, "back round the craft")
	main.toggle_map()
