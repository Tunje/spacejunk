extends GutTest

const LIMIT := 4_000_000_000_000_000_000


func _assert_vector(actual: Vector3, expected: Vector3, label: String = "") -> void:
	assert_almost_eq(actual.distance_to(expected), 0.0, 0.0001, "%s: %s vs %s" % [label, actual, expected])


func test_positions_are_relative_to_focus() -> void:
	var result := FloatingOrigin.relative_m([3000, 0, -2000], [3000, 0, -2000], [1000, 0, 0], [1000, 0, 0], 0.0)
	_assert_vector(result, Vector3(2, 0, -2))


func test_precision_holds_at_the_edge_of_the_position_range() -> void:
	var focus := [LIMIT - 5000, LIMIT - 5000, -LIMIT]
	var entity := [LIMIT, LIMIT - 4000, -LIMIT + 250]
	var result := FloatingOrigin.relative_m(entity, entity, focus, focus, 0.5)
	_assert_vector(result, Vector3(5, 1, 0.25))


func test_full_range_difference_does_not_overflow() -> void:
	var result := FloatingOrigin.relative_m([LIMIT, 0, 0], [LIMIT, 0, 0], [-LIMIT, 0, 0], [-LIMIT, 0, 0], 0.0)
	assert_almost_eq(float(result.x), 8e15, 1e11)


func test_interpolation_runs_between_views() -> void:
	var result := FloatingOrigin.relative_m([0, 0, 0], [10000, 0, 0], [0, 0, 0], [0, 0, 0], 0.25)
	_assert_vector(result, Vector3(2.5, 0, 0))


func test_moving_focus_stays_on_the_render_origin() -> void:
	var result := FloatingOrigin.relative_m([0, 0, 0], [7000, 0, 0], [0, 0, 0], [7000, 0, 0], 0.4)
	_assert_vector(result, Vector3.ZERO)


func test_compression_leaves_near_objects_alone() -> void:
	assert_eq(FloatingOrigin.compression(100.0), 1.0)
	assert_eq(FloatingOrigin.compression(FloatingOrigin.NEAR_M), 1.0)


func test_compression_is_continuous_and_bounded() -> void:
	var near := FloatingOrigin.NEAR_M
	assert_almost_eq(FloatingOrigin.compression(near * 1.0001), 1.0, 0.01)
	var star_distance := 1.5e11
	assert_lt(FloatingOrigin.compression(star_distance) * star_distance, FloatingOrigin.FAR_M + 1.0)


func test_compressed_distance_keeps_increasing() -> void:
	var previous := 0.0
	for distance: float in [6e4, 1e5, 1e6, 1e9, 1e12]:
		var drawn := FloatingOrigin.compression(distance) * distance
		assert_gt(drawn, previous)
		previous = drawn


func _connector(facing: String, up: String, pos: Array = [0, 0, 0]) -> Dictionary:
	return { "id": "c", "facing": facing, "up": up, "pos_mm": pos }


func test_mate_joins_connector_points() -> void:
	var parent := _connector("+x", "+y", [1250, 2800, 0])
	var child := _connector("-x", "+y")
	var joint := CraftLayout.mate(parent, child)
	_assert_vector(joint * Vector3.ZERO, Vector3(1.25, 2.8, 0))


func test_mate_gives_opposite_facings_and_equal_ups() -> void:
	var cases: Array = [
		[_connector("+y", "+z"), _connector("-y", "+z", [100, 200, 0])],
		[_connector("+z", "+y", [0, 1000, 500]), _connector("-z", "+y")],
		[_connector("+x", "+y"), _connector("+y", "+z", [0, 700, 0])],
	]
	for pair: Array in cases:
		var parent_frame := CraftLayout.connector_transform(pair[0])
		var child_frame := CraftLayout.mate(pair[0], pair[1]) * CraftLayout.connector_transform(pair[1])
		_assert_vector(child_frame.basis.z, -parent_frame.basis.z, "facing")
		_assert_vector(child_frame.basis.y, parent_frame.basis.y, "up")
		_assert_vector(child_frame.origin, parent_frame.origin, "origin")


func test_child_of_a_child_stacks_its_transforms() -> void:
	var sim := StubSim.new_game("stub", 1)
	var view := sim.view()
	var modules: Dictionary = sim.defs()["modules"]
	var ship: Dictionary = {}
	for id: int in view["units"]:
		if view["units"][id]["kind"] == "ship":
			ship = view["units"][id]
	var transforms := CraftLayout.part_transforms(ship["parts"], modules)
	var tank: Dictionary = {}
	for child: Dictionary in ship["parts"]["children"]:
		if child["def"] == "stub_tank":
			tank = child
	var thruster: Dictionary = tank["children"][0]
	_assert_vector(transforms[tank["id"]].origin, Vector3.ZERO, "tank on hull base")
	_assert_vector(transforms[thruster["id"]].origin, Vector3(0, -2.6, 0), "thruster below tank")
	_assert_vector(transforms[ship["parts"]["id"]].origin, Vector3.ZERO, "root")


func test_docked_root_mates_the_two_ports_in_world_space() -> void:
	var target := _connector("+x", "+y", [2400, 0, 0])
	var own := _connector("+y", "+z", [0, 700, 0])
	var station_port := Transform3D(Basis.IDENTITY, Vector3(3.5, 0, 0))
	var own_port := Transform3D(Basis.IDENTITY, Vector3(0, 4, 0))
	var root := CraftLayout.docked_root(station_port, target, own, own_port)
	var own_world := root * own_port * CraftLayout.connector_transform(own)
	var target_world := station_port * CraftLayout.connector_transform(target)
	_assert_vector(own_world.origin, target_world.origin, "ports touch")
	_assert_vector(own_world.basis.z, -target_world.basis.z, "ports face each other")
	_assert_vector(own_world.basis.y, target_world.basis.y, "ups agree")


func test_heading_puts_the_nose_along_the_route() -> void:
	for direction: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, -5), Vector3(1, 2, 3), Vector3.UP, Vector3.DOWN]:
		var nose := CraftLayout.heading_towards(direction) * Vector3.UP
		_assert_vector(nose, direction.normalized(), str(direction))


func test_orbit_camera_keeps_its_distance_and_looks_at_the_pivot() -> void:
	var camera := OrbitCamera.new()
	add_child_autofree(camera)
	camera.pivot = Vector3(5, 0, 0)
	camera.update_view(0.0)
	assert_almost_eq(camera.global_position.distance_to(camera.pivot), camera.distance_m, 0.001)
	var forward := -camera.global_basis.z
	_assert_vector(forward, (camera.pivot - camera.global_position).normalized(), "look")


func test_orbit_camera_clamps_pitch_and_zoom() -> void:
	var camera := OrbitCamera.new()
	add_child_autofree(camera)
	camera.orbit(Vector2(0, -100000))
	assert_eq(camera.pitch, OrbitCamera.PITCH_LIMIT)
	camera.orbit(Vector2(0, 100000))
	assert_eq(camera.pitch, -OrbitCamera.PITCH_LIMIT)
	for i in range(200):
		camera.zoom(1.0)
	assert_eq(camera.target_distance_m, OrbitCamera.MAX_DISTANCE_M)
	for i in range(200):
		camera.zoom(-1.0)
	assert_eq(camera.target_distance_m, OrbitCamera.MIN_DISTANCE_M)
