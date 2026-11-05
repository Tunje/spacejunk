extends GutTest
## D17: close-up planet terrain on the real Sim after a landing. Slow: it waits for the
## planet's mesh and the close-up tiles to build.

const SEED := 48213
const RANGE_M := 6000
const RADIUS_MM := 250_000_000


func _has_level(keys: Array[String], level: int) -> bool:
	for key: String in keys:
		if key.begins_with("%d:" % level):
			return true
	return false


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
	assert_true(LandingLegs.fit(sim, ship))
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
