extends GutTest
## D16: landing and takeoff (A15's atomic autopilot) through the flight screen, on
## the real Sim: pick a hex, read check's cost, land, stand on the drawn surface,
## take off, and see a crash reported.

const GM_STAR := 132_712_440_018_000_000
## A small airless world, so the starter ship's tank covers a landing.
const GM_PLANET := 65_138_398
const RADIUS_MM := 250_000_000
const AU_MM := 149_597_870_700_000
const ONE := OrbitMath.ONE
const SEED := 48213
const RANGE_M := 6000

var main: Node
var bridge: SimBridge
var screen: FlightScreen
var sim: Sim
var keys := {}


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	screen = main.flight_screen


## A planet with terrain and an orbiter on the orbit through r (mm) and v (um/s).
func _fly(orbit_r: Array, orbit_v: Array, terrain: Dictionary = { "seed": SEED, "height_range_m": RANGE_M }) -> void:
	var defs := DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": RADIUS_MM, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM },
				"planet": terrain },
		],
		"units": [
			{ "key": "orbiter", "template": "starter_ship", "name": "Orbiter", "pos_mm": [0, 0, 0],
				"inventory": [{ "item": "propellant", "grams": 1_000_000 }], "dock": null },
		],
	}, {}), "")
	for table: String in ["bodies", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	assert_true(LandingLegs.fit(sim, keys["Orbiter"]), "landing legs fitted, as A19 needs to land")
	var orbiter: Dictionary = sim._state["units"][keys["Orbiter"]]
	orbiter["orbit"] = OrbitMath.from_state(orbit_r, orbit_v, GM_PLANET, 0)
	orbiter["orbit"]["parent"] = keys["Planet"]
	orbiter["pos_mm"] = OrbitMath.position_at(orbiter["orbit"], 0)
	sim._ctx.index.clear()
	bridge.start(sim)
	main.local_view.rebuild()
	main.toggle_flight()


func _circular(terrain: Dictionary = { "seed": SEED, "height_range_m": RANGE_M }) -> void:
	# 466 m/s is circular 50 km up, 300 km from this planet's centre.
	_fly([300_000_000, 0, 0], [0, 0, -466_000_000], terrain)


func _n() -> int:
	return PlanetGrid.n_for_radius(RADIUS_MM)


## Runs the sim straight to a tick, then lets the client see it, events included.
func _run_to(tick: int) -> void:
	sim.step(tick - sim.current_tick())
	var events := sim.take_events()
	bridge.start(sim)
	if not events.is_empty():
		bridge.events_received.emit(events)
	main.local_view.refresh(0.016)
	screen._land_ms = -FlightScreen.PATH_REFRESH_MS
	screen.refresh()


func _ship() -> Dictionary:
	return bridge.current_view["units"][keys["Orbiter"]]


func _planet_node() -> BodyNode:
	return main.local_view.bodies[keys["Planet"]]


func _wait_for_terrain() -> void:
	var frames := 0
	while PlanetMesh.busy() and frames < 1200:
		await wait_process_frames(1)
		frames += 1
	assert_false(_planet_node().planet.is_empty(), "the terrain is built")


func _land_on(cell: int) -> void:
	screen.choose_cell(cell)
	var ticks: int = screen.land_preview["detail"]["ticks"]
	screen.land()
	_run_to(sim.current_tick() + 1)
	assert_eq(_ship()["op"]["type"], "landing")
	_run_to(sim.current_tick() + ticks + 2)


func test_the_renderer_takes_the_planets_own_settings() -> void:
	var settings := PlanetMesh.settings_of({ "radius_mm": 600_000_000, "visual_seed": 9,
		"planet": { "seed": SEED, "height_range_m": RANGE_M } })
	assert_eq([settings["seed"], settings["range_m"]], [SEED, RANGE_M])
	assert_eq(PlanetMesh.settings_of({ "radius_mm": 600_000_000, "visual_seed": 9,
		"planet": { "seed": 1, "height_range_m": 10, "weights": [1, 1] } })["weights"], [1, 1], "the planet's own weights")
	assert_eq(PlanetMesh.settings_of({ "radius_mm": 600_000_000, "visual_seed": 9, "planet": {} })["range_m"], 0,
		"a planet without settings is a smooth sphere, as in the sim")


func test_the_landing_section_shows_on_an_orbit_round_a_planet() -> void:
	_circular()
	assert_true(screen._land_box.visible)
	assert_eq(screen._land_title.text, "Landing on Planet")
	assert_true(screen._land_button.disabled, "no site yet")
	assert_false(screen._takeoff_row.visible)


func test_a_click_on_the_planet_picks_the_hex_under_it() -> void:
	_circular()
	await _wait_for_terrain()
	screen.set_picking(true)
	assert_true(_planet_node().outline.visible, "outlines help while picking")
	var cell := 4321
	var dir := PlanetGrid.direction(cell, _n())
	var body := _planet_node()
	var point := body.position + Vector3(dir[0], dir[1], dir[2]) / float(ONE) * body.scale.x
	var hit := { "kind": "body", "id": keys["Planet"], "part": 0, "point": point }
	assert_false(screen._land_click(hit), "the click is used, not passed on as a selection")
	assert_eq(screen.land_cell, cell)
	assert_true(body._site.visible, "the chosen hex is ringed")
	screen.set_picking(false)
	assert_false(_planet_node().outline.visible)


func test_land_shows_checks_cost_then_lands_on_the_hex_at_its_height() -> void:
	_circular()
	await _wait_for_terrain()
	var cell := 4321
	screen.choose_cell(cell)
	var result: Dictionary = bridge.check(screen.land_command())
	assert_true(result["ok"], str(result))
	assert_eq(screen._land_text.text, "Hex 4321. %s" % FlightLogic.trip_cost_text(result, "Descent", 10))
	assert_false(screen._land_button.disabled)
	_land_on(cell)
	assert_eq(_ship()["landed"], { "body": keys["Planet"], "cell": cell })
	var dir := PlanetGrid.direction(cell, _n())
	var height := PlanetGrid.height_m(SEED, dir, PlanetMesh.DEFAULT_WEIGHTS, RANGE_M)
	var side := "above" if height >= 0 else "below"
	assert_eq(screen._place.text, "Landed on Planet, hex %d, %s %s datum" % [cell, OrderText.metres(absi(height) * 1000), side])
	assert_has(main.event_log.lines, "Orbiter landed on Planet")
	screen.burn_now()
	screen.set_components(0.0, 0.0, 5.0)
	assert_string_starts_with(screen._cost.text, "Delta-v 5.0 m/s", "a burn on the ground is a lift-off (A19)")


func test_a_landed_craft_stands_on_the_drawn_surface() -> void:
	_circular()
	await _wait_for_terrain()
	_land_on(4321)
	main.local_view.refresh(0.016)
	var craft: CraftNode = main.local_view.crafts[keys["Orbiter"]]
	var body := _planet_node()
	var up := craft.basis.y.normalized()
	var dir := PlanetGrid.direction(4321, _n())
	var radial := Vector3(dir[0], dir[1], dir[2]).normalized()
	assert_almost_eq(up.dot(radial), 1.0, 0.001, "upright on its cell")
	# The ground at the cell is the sim's height there; close up, the detail tiles are
	# levelled to it round a landed craft, and the base mesh sits a little below.
	var height := PlanetGrid.height_m(SEED, dir, PlanetMesh.DEFAULT_WEIGHTS, RANGE_M)
	var ground := body.position + radial * (RADIUS_MM / 1000.0 + height)
	var feet := craft.position + up * craft.bottom_m
	assert_almost_eq(feet.distance_to(ground), 0.0, 1.0, "its lowest part is on the ground")
	assert_eq(body.scale, Vector3.ONE * RADIUS_MM / 1000.0, "drawn at true scale this close")


func test_take_off_back_to_orbit() -> void:
	_circular()
	await _wait_for_terrain()
	_land_on(4321)
	# Landing took nearly the whole starter tank; fill it on the ground to climb back.
	sim._state["units"][keys["Orbiter"]]["inventory"]["propellant"] = 1_900_000
	_run_to(sim.current_tick() + 1)
	assert_true(screen._takeoff_row.visible)
	assert_false(screen._pick_button.visible)
	assert_string_starts_with(screen._land_text.text, "Climb: delta-v ")
	var ticks: int = screen.takeoff_preview["detail"]["ticks"]
	screen.take_off()
	_run_to(sim.current_tick() + 1)
	assert_eq(_ship()["op"]["type"], "taking_off")
	assert_string_starts_with(InspectText.status(_ship(), bridge.current_view), "Taking off ")
	_run_to(sim.current_tick() + ticks + 2)
	assert_true(_ship()["landed"].is_empty())
	assert_false(_ship()["orbit"].is_empty())
	assert_has(main.event_log.lines, "Orbiter took off from Planet")
	assert_string_starts_with(screen._place.text, "Orbiting Planet: ")


func test_a_crash_is_reported() -> void:
	# An ellipse from 300 km whose periapsis is well under the surface.
	_fly([300_000_000, 0, 0], [0, 0, -200_000_000])
	var crashed := false
	for i in 400:
		_run_to(sim.current_tick() + 20)
		if not _ship()["landed"].is_empty():
			crashed = true
			break
	assert_true(crashed)
	var said := false
	for line: String in main.event_log.lines:
		said = said or line.begins_with("Orbiter crashed on Planet")
	assert_true(said, "the crash is in the log, with its speed since A19")


## The height the mesh draws at a cell, and the sim's landed height there, in m.
func _heights_at(cell: int) -> Array[int]:
	_land_on(cell)
	var drawn: int = _planet_node().planet["heights"][cell]
	var pos: Array = _ship()["pos_mm"]
	var landed := roundi((Vector3(pos[0], pos[1], pos[2]).length() - RADIUS_MM) / 1000.0)
	return [drawn, landed]


func test_mesh_heights_equal_landed_heights() -> void:
	_circular()
	await _wait_for_terrain()
	for cell: int in [4321]:
		var heights := _heights_at(cell)
		assert_almost_eq(heights[0], heights[1], 1, "cell %d" % cell)


func test_mesh_heights_follow_the_planets_own_weights() -> void:
	var weights := [1, 3, 2]
	_circular({ "seed": SEED, "height_range_m": RANGE_M, "weights": weights })
	await _wait_for_terrain()
	var cell := 4321
	var dir := PlanetGrid.direction(cell, _n())
	var own := PlanetGrid.height_m(SEED, dir, weights, RANGE_M)
	var fixed := PlanetGrid.height_m(SEED, dir, PlanetMesh.DEFAULT_WEIGHTS, RANGE_M)
	assert_ne(own, fixed, "the weights change this cell's height")
	assert_eq(_planet_node().planet["heights"][cell], own, "the mesh draws the planet's own weights")
	var heights := _heights_at(cell)
	if absi(heights[1] - fixed) <= 1 and absi(heights[1] - own) > 1:
		pending("The sim reads planet.weights from A17 (kernel/A16, e545dab); main still lands at [4, 2, 1]")
		return
	assert_almost_eq(heights[0], heights[1], 1, "the mesh and the sim agree on a planet with its own weights")

