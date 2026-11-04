extends GutTest
## D17: close-up planet terrain (planets.md section 7) and the camera near a planet.

const SEED := 48213
const RANGE_M := 6000
const RADIUS_MM := 250_000_000


func _settings() -> Dictionary:
	return PlanetMesh.settings_of({ "radius_mm": RADIUS_MM, "visual_seed": 2, "planet": { "seed": SEED, "height_range_m": RANGE_M } })


func _dir(cell: int) -> Vector3:
	var q := PlanetGrid.direction(cell, PlanetGrid.n_for_radius(RADIUS_MM))
	return Vector3(q[0], q[1], q[2]).normalized()


func _has_level(keys: Array[String], level: int) -> bool:
	for key: String in keys:
		if key.begins_with("%d:" % level):
			return true
	return false


func test_tiles_split_towards_a_camera_near_the_ground() -> void:
	var low := PlanetDetail.wanted_tiles(Vector2.ZERO, 10.0)
	assert_true(_has_level(low, PlanetDetail.MAX_LEVEL), "finest tiles under the camera")
	assert_lt(low.size(), 120, "only near the camera")
	var high := PlanetDetail.wanted_tiles(Vector2.ZERO, 30000.0)
	assert_false(_has_level(high, PlanetDetail.MAX_LEVEL), "coarse from high up")
	assert_lt(high.size(), low.size())


func test_leaves_cover_the_root_exactly() -> void:
	var area := 0.0
	for key: String in PlanetDetail.wanted_tiles(Vector2(1234.0, -5678.0), 50.0):
		var size := PlanetDetail.ROOT_M / (1 << int(key.split(":")[0]))
		area += size * size
	assert_almost_eq(area, PlanetDetail.ROOT_M * PlanetDetail.ROOT_M, 1.0, "no gaps, no overlaps")


func test_without_detail_a_cell_centre_is_the_sims_height() -> void:
	var empty: Array[FastNoiseLite] = []
	var none: Array[Dictionary] = []
	for cell: int in [2, 777, 4321]:
		var expected := PlanetGrid.height_m(SEED, PlanetGrid.direction(cell, PlanetGrid.n_for_radius(RADIUS_MM)),
			PlanetMesh.DEFAULT_WEIGHTS, RANGE_M)
		assert_almost_eq(PlanetDetail.height_at(_dir(cell), _settings(), empty, none), float(expected), 1.0, "cell %d" % cell)


func test_detail_adds_bounded_relief() -> void:
	var noise := PlanetDetail.detail_noise(2)
	var empty: Array[FastNoiseLite] = []
	var none: Array[Dictionary] = []
	var dir := _dir(4321)
	var biggest := 0.0
	for step in 50:
		var off := (dir + Vector3(0.0003 * step, 0.0, 0.0)).normalized()
		biggest = maxf(biggest, absf(PlanetDetail.height_at(off, _settings(), noise, none)
			- PlanetDetail.height_at(off, _settings(), empty, none)))
	assert_gt(biggest, 1.0, "some relief")
	assert_lt(biggest, PlanetDetail.DETAIL_M + PlanetDetail.FINE_M + 0.01)


func test_the_ground_is_level_round_a_landed_craft() -> void:
	var noise := PlanetDetail.detail_noise(2)
	var site_dir := _dir(4321)
	var sites: Array[Dictionary] = [{ "dir": site_dir, "height_m": 123 }]
	var none: Array[Dictionary] = []
	var radius := RADIUS_MM / 1000.0
	var tangent := site_dir.cross(Vector3.UP).normalized()
	for metres: float in [0.0, 20.0, PlanetDetail.FLAT_INNER_M - 1.0]:
		var dir := (site_dir * radius + tangent * metres).normalized()
		assert_almost_eq(PlanetDetail.height_at(dir, _settings(), noise, sites), 123.0, 0.001, "%d m away" % metres)
	var outside := (site_dir * radius + tangent * (PlanetDetail.FLAT_OUTER_M + 10.0)).normalized()
	assert_eq(PlanetDetail.height_at(outside, _settings(), noise, sites), PlanetDetail.height_at(outside, _settings(), noise, none))


func test_a_tile_has_its_grid_and_skirts() -> void:
	var dir := _dir(4321)
	var east := dir.cross(Vector3.UP).normalized()
	var none: Array[Dictionary] = []
	var built := PlanetDetail.build_tile({ "key": "%d:512:512" % PlanetDetail.MAX_LEVEL, "settings": _settings(), "seed": 2,
		"sites": none, "centre": dir, "east": east, "north": east.cross(dir).normalized(), "anchor": "a" })
	var count := PlanetDetail.SEGMENTS + 1
	var vertices: PackedVector3Array = built["arrays"][Mesh.ARRAY_VERTEX]
	assert_eq(vertices.size(), count * count + 4 * count)
	assert_eq(built["arrays"][Mesh.ARRAY_INDEX].size(),
		PlanetDetail.SEGMENTS * PlanetDetail.SEGMENTS * 6 + 4 * PlanetDetail.SEGMENTS * 12)
	var span := vertices[count - 1].distance_to(vertices[0])
	assert_almost_eq(span, PlanetDetail.ROOT_M / (1 << PlanetDetail.MAX_LEVEL), 5.0, "64 m across at the finest level")
	for vertex: Vector3 in vertices:
		assert_lt(vertex.length(), 150.0, "kept small, relative to the tile's own origin")


## The real Sim: land on a small planet and look at what the client draws.
func test_close_up_tiles_appear_under_a_landed_craft() -> void:
	var main: Node = load("res://client/main.tscn").instantiate()
	add_child_autofree(main)
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	var defs := DataLoader.load_defs()
	var sim := Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": 132_712_440_018_000_000 },
			{ "key": "planet", "name": "Grit", "kind": "planet", "radius_mm": RADIUS_MM, "visual_seed": 2,
				"deposits": [], "gm": 65_138_398, "orbit": { "parent": "star", "a_mm": 149_597_870_700_000 },
				"planet": { "seed": SEED, "height_range_m": RANGE_M } },
		],
		"units": [{ "key": "ship", "template": "starter_ship", "name": "Probe", "pos_mm": [0, 0, 0],
			"inventory": [{ "item": "propellant", "grams": 1_000_000 }], "dock": null }],
	}, {}), "")
	var ship := 0
	var planet := 0
	for id: int in sim._state["units"]:
		ship = id
	for id: int in sim._state["bodies"]:
		if sim._state["bodies"][id]["kind"] == "planet":
			planet = id
	var orbit := OrbitMath.from_state([300_000_000, 0, 0], [0, 0, -466_000_000], 65_138_398, 0)
	orbit["parent"] = planet
	sim._state["units"][ship]["orbit"] = orbit
	sim._state["units"][ship]["pos_mm"] = OrbitMath.position_at(orbit, 0)
	sim._ctx.index.clear()
	var land := { "type": "land", "unit": ship, "args": { "body": planet, "cell": 4321 } }
	var ticks: int = sim.check(land)["detail"]["ticks"]
	sim.submit(land)
	sim.step(ticks + 3)
	assert_false(sim.view()["units"][ship]["landed"].is_empty())
	bridge.start(sim)
	main.local_view.rebuild()
	var view: LocalView = main.local_view
	var frames := 0
	while (view.detail.shown.is_empty() or PlanetMesh.busy()) and frames < 1500:
		await wait_process_frames(1)
		frames += 1
	assert_true(view.detail.is_active(), "close-up detail runs on the ground")
	assert_false(view.detail.shown.is_empty(), "tiles are built and shown")
	var body_now: BodyNode = view.bodies[planet]
	var altitude := (view.camera.global_position - body_now.position).length() - body_now.radius_m
	assert_true(_has_level(view.detail.shown, PlanetDetail.MAX_LEVEL),
		"the finest tiles are under the camera (camera %.0f m up, shown %s, wanted %s)" % [altitude, str(view.detail.shown), str(view.detail.wanted)])
	var body: BodyNode = view.bodies[planet]
	for i in 60:
		await wait_process_frames(1)
	var radial := (view.camera.pivot - body.position).normalized()
	assert_almost_eq(view.camera.up_dir.dot(radial), 1.0, 0.01, "the camera's up is the local vertical")
	assert_gt(view.camera.far, body.radius_m, "the far plane reaches past the horizon")
	assert_eq(view.detail.sites.size(), 1, "the landed craft levels the ground under it")


func test_far_from_any_planet_the_camera_keeps_world_up() -> void:
	var main: Node = StubScene.build()
	add_child_autofree(main)
	main.get_node("Bridge").set_paused(true)
	for i in 30:
		await wait_process_frames(1)
	assert_almost_eq(main.local_view.camera.up_dir.dot(Vector3.UP), 1.0, 0.0001)
	assert_false(main.local_view.detail.is_active())
