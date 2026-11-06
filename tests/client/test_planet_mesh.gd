extends GutTest
## D13: the planet's base mesh from PlanetGrid (planets.md section 6, option B),
## built off the main thread and cached. Small grids here; the full n = 100 build
## is timed in tests/slow/test_planet_build.gd.

const N := 4
## A radius that gives n = 4 at about 6 km per n.
const RADIUS_MM := 24_000_000


func _settings(sea: Variant = -300) -> Dictionary:
	var settings := PlanetMesh.settings_of({ "radius_mm": RADIUS_MM, "seed": 48213, "height_range_m": 3000, "sea_level_m": sea })
	assert_eq(settings["n"], N)
	return settings


func _wait_for_builds() -> void:
	var frames := 0
	while PlanetMesh.busy() and frames < 600:
		await wait_process_frames(1)
		frames += 1
	assert_false(PlanetMesh.busy(), "the build finished")


func test_one_vertex_per_cell_and_the_dual_triangles() -> void:
	var built := PlanetMesh.build(_settings())
	assert_eq(built["cells"], 10 * N * N + 2)
	assert_eq(built["triangles"], 20 * N * N)
	assert_eq(built["surface"][Mesh.ARRAY_VERTEX].size(), built["cells"])
	assert_eq(built["outline"][Mesh.ARRAY_VERTEX].size(), 2 * 30 * N * N, "each of the 30 n^2 edges once")


func test_the_surface_is_closed() -> void:
	var triangles: PackedInt32Array = PlanetMesh.build(_settings())["surface"][Mesh.ARRAY_INDEX]
	var edges: Dictionary = {}
	for face in triangles.size() / 3:
		for corner in 3:
			var a := triangles[face * 3 + corner]
			var b := triangles[face * 3 + (corner + 1) % 3]
			var key := "%d-%d" % [mini(a, b), maxi(a, b)]
			edges[key] = edges.get(key, 0) + 1
	for key: String in edges:
		assert_eq(edges[key], 2, "edge %s is shared by two triangles" % key)
	var cells := 10 * N * N + 2
	assert_eq(cells - edges.size() + triangles.size() / 3, 2, "Euler: V - E + F = 2")


func test_every_triangle_faces_outwards() -> void:
	var built := PlanetMesh.build(_settings())
	var vertices: PackedVector3Array = built["surface"][Mesh.ARRAY_VERTEX]
	var triangles: PackedInt32Array = built["surface"][Mesh.ARRAY_INDEX]
	for face in triangles.size() / 3:
		var a := vertices[triangles[face * 3]]
		var b := vertices[triangles[face * 3 + 1]]
		var c := vertices[triangles[face * 3 + 2]]
		assert_lt((b - a).cross(c - a).dot(a + b + c), 0.0, "clockwise from outside, Godot's front face")


func test_vertices_are_the_sims_cell_centres() -> void:
	var settings := _settings()
	var built := PlanetMesh.build(settings)
	var vertices: PackedVector3Array = built["surface"][Mesh.ARRAY_VERTEX]
	for cell: int in [PlanetGrid.NORTH, PlanetGrid.SOUTH, 2, 77, 161]:
		var dir := PlanetGrid.direction(cell, N)
		var height := PlanetGrid.height_m(48213, dir, PlanetMesh.DEFAULT_WEIGHTS, 3000)
		assert_eq(built["heights"][cell], height)
		var centre := PlanetGrid.centre_mm(cell, N, RADIUS_MM, height)
		var expected := Vector3(centre[0], centre[1], centre[2]) / float(RADIUS_MM)
		assert_almost_eq(vertices[cell].distance_to(expected), 0.0, 1e-5, "cell %d" % cell)


func test_a_parallel_build_is_identical() -> void:
	var settings := _settings()
	var serial := PlanetMesh.build(settings, false)
	var holder := [{}]
	var thread := Thread.new()
	thread.start(func() -> void: holder[0] = PlanetMesh.build(settings, true))
	thread.wait_to_finish()
	assert_eq(holder[0]["surface"], serial["surface"])
	assert_eq(holder[0]["outline"], serial["outline"])


func test_colours_stand_in_for_surface_types() -> void:
	var settings := _settings()
	var sea := PlanetMesh.colour(-2000, 500, 0.0, settings)
	var dry := PlanetMesh.colour(100, 50, 0.0, settings)
	var wet := PlanetMesh.colour(100, 950, 0.0, settings)
	var pole := PlanetMesh.colour(100, 500, 0.99, settings)
	var peak := PlanetMesh.colour(2900, 500, 0.0, settings)
	assert_gt(sea.b, sea.r, "sea is blue")
	assert_gt(dry.r, wet.r, "dust is warmer than wetland")
	assert_gt(pole.v, 0.85, "poles are white")
	assert_gt(peak.v, 0.85, "peaks are white")
	assert_eq(PlanetMesh.colour(-2000, 500, 0.0, _settings(null)).b, PlanetMesh.colour(-2000, 500, 0.0, _settings(null)).b)
	assert_lt(PlanetMesh.colour(-2000, 500, 0.0, _settings(null)).b, sea.b, "a dry world has no sea")


func test_settings_fall_back_until_planets_are_data() -> void:
	var settings := PlanetMesh.settings_of({ "radius_mm": 600_000_000, "visual_seed": 7 })
	assert_eq(settings["seed"], 7)
	assert_eq(settings["range_m"], PlanetMesh.DEFAULT_RANGE_M)
	assert_eq(settings["sea_level_m"], null)
	assert_eq(settings["n"], 100)


func test_a_request_builds_in_the_background_then_caches() -> void:
	var settings := PlanetMesh.settings_of({ "radius_mm": RADIUS_MM, "seed": 991, "height_range_m": 1000 })
	var receiver := PlanetReceiver.new()
	assert_eq(PlanetMesh.request(settings, receiver), {}, "not built yet")
	assert_true(PlanetMesh.busy())
	await _wait_for_builds()
	assert_eq(receiver.received, 1)
	assert_false(PlanetMesh.request(settings, receiver).is_empty(), "now cached")


## D26: a game or test that ends mid-build joins the thread, rather than leaving it
## running at exit, where Godot hung or crashed.
func test_finish_all_ends_a_running_build_and_keeps_its_result() -> void:
	var settings := PlanetMesh.settings_of({ "radius_mm": RADIUS_MM, "seed": 993, "height_range_m": 1000 })
	var receiver := PlanetReceiver.new()
	PlanetMesh.request(settings, receiver)
	assert_true(PlanetMesh.busy())
	PlanetMesh.finish_all()
	assert_false(PlanetMesh.busy(), "no thread left running")
	assert_false(PlanetMesh.cached(settings).is_empty(), "the built planet is kept")
	await wait_process_frames(2)
	assert_eq(receiver.received, 0, "its late delivery finds nothing to do")


func test_two_requests_share_one_build() -> void:
	var settings := PlanetMesh.settings_of({ "radius_mm": RADIUS_MM, "seed": 992 })
	var first := PlanetReceiver.new()
	var second := PlanetReceiver.new()
	PlanetMesh.request(settings, first)
	PlanetMesh.request(settings, second)
	assert_eq(PlanetMesh._pending.size(), 1)
	await _wait_for_builds()
	assert_eq([first.received, second.received], [1, 1])


func test_a_freed_requester_is_skipped() -> void:
	var settings := PlanetMesh.settings_of({ "radius_mm": RADIUS_MM, "seed": 993 })
	var gone := PlanetReceiver.new()
	PlanetMesh.request(settings, gone)
	gone = null
	await _wait_for_builds()
	assert_false(PlanetMesh.cached(settings).is_empty(), "the build still lands in the cache")


func test_a_planet_body_swaps_its_sphere_for_terrain_and_toggles_outlines() -> void:
	var node := BodyNode.new()
	add_child_autofree(node)
	node.build(5, { "kind": "planet", "radius_mm": RADIUS_MM, "visual_seed": 4, "seed": 994 })
	assert_true(node.surface.mesh is SphereMesh, "a sphere until the terrain is ready")
	await _wait_for_builds()
	assert_true(node.surface.mesh is ArrayMesh)
	assert_eq(node.planet_cells, 10 * N * N + 2)
	assert_false(node.outline.visible)
	node.set_outlines(true)
	assert_true(node.outline.visible)


func test_o_toggles_outlines_on_every_planet() -> void:
	var main: Node = load("res://client/main.tscn").instantiate()
	main.scenario = StubSim.SCENARIO_ORBIT
	add_child_autofree(main)
	main.get_node("Bridge").set_paused(true)
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_O
	main._unhandled_key_input(key)
	assert_true(BodyNode.show_outlines)
	var planets := 0
	for id: int in main.local_view.bodies:
		var body: BodyNode = main.local_view.bodies[id]
		if body.kind == "planet":
			planets += 1
			assert_true(body.outline.visible)
	assert_eq(planets, 1)
	main._unhandled_key_input(key)
	assert_false(BodyNode.show_outlines)
	await _wait_for_builds()
