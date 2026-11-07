extends GutTest
## D14: the flight screen on A12's escape paths and spheres of influence, on the real
## Sim, with a star, a 600 km planet and a ship orbiting it, built as A's tests build it.

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const AU_MM := 149_597_870_700_000
const ONE := OrbitMath.ONE

var main: Node
var bridge: SimBridge
var screen: FlightScreen
var sim: Sim
var keys := {}


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = "reference"
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.set_speed(1)
	screen = main.flight_screen


## The planet and an orbiter on the orbit through r (mm) and v (um/s), loaded into
## the client the way a load is.
func _fly(orbit_r: Array, orbit_v: Array) -> void:
	var orbit := OrbitMath.from_state(orbit_r, orbit_v, GM_PLANET, 0)
	assert_false(orbit.is_empty(), "a valid starting orbit")
	var defs: Dictionary = DataLoader.load_defs().duplicate(true)
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	var problem := ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM * 2 } },
		],
		"units": [
			{ "key": "orbiter", "template": "starter_ship", "name": "Orbiter", "pos_mm": [0, 0, 0],
				"inventory": [{ "item": "propellant", "grams": 1_000_000 }], "dock": null },
		],
	}, {})
	assert_eq(problem, "")
	for table: String in ["bodies", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	var orbiter: Dictionary = sim._state["units"][keys["Orbiter"]]
	orbiter["orbit"] = orbit
	orbiter["orbit"]["parent"] = keys["Planet"]
	orbiter["pos_mm"] = OrbitMath.position_at(orbiter["orbit"], 0)
	sim._ctx.index.clear()
	bridge.start(sim)
	main.local_view.rebuild()
	main.toggle_flight()


func _ticks(count: int) -> void:
	bridge.set_paused(false)
	for i in range(count):
		bridge.advance(1.0 / bridge.ticks_per_second())
	bridge.set_paused(true)
	screen.refresh()


func _unit() -> Dictionary:
	return bridge.current_view["units"][keys["Orbiter"]]


func test_a_real_burn_past_escape_speed_through_the_screen() -> void:
	# A fast ellipse at 700 km, a little under escape speed (3.18 km/s there).
	_fly([700_000_000, 0, 0], [0, 0, -3_100_000_000])
	assert_string_starts_with(screen._place.text, "Orbiting Planet: ")
	assert_false(screen._apo_button.disabled)
	screen.burn_now()
	# 120 m/s is enough from 3.1 km/s against 3.18 km/s escape, and a shorter burn
	# keeps the flown preview and the run short.
	screen.set_components(120.0)
	assert_true(screen.preview["ok"], str(screen.preview))
	assert_true(OrbitPath.is_open(screen.preview["detail"]["orbit"]), "check previews a hyperbola")
	assert_string_starts_with(screen._after.text, "Then escaping Planet, periapsis ")
	assert_gt(screen.planned_path.size(), 2, "the open branch is drawn")
	var burn_ticks: int = screen.preview["detail"]["burn_ticks"]
	screen.plan()
	_ticks(burn_ticks + 10)
	assert_true(_unit()["burn"].is_empty())
	assert_true(OrbitPath.is_open(_unit()["orbit"]))
	assert_string_starts_with(screen._place.text, "Escaping Planet: periapsis ")
	assert_string_ends_with(screen._place.text, ", escaping")
	assert_true(screen._apo_button.disabled, "no apoapsis on an escape path")
	assert_gt(screen.current_path.size(), 2, "predict draws the branch ahead")
	assert_true(screen._diagram.visible)
	await wait_process_frames(2)
	assert_eq(main.event_log.lines[-1], "Orbiter: burn done, 120.0 m/s")


func test_crossing_out_of_the_planets_sphere_reparents_the_screen() -> void:
	# Start on a hyperbola 1000 km inside the sphere, heading out, as A's test does.
	var soi := OrbitMath.soi_mm(AU_MM * 2, GM_PLANET, GM_STAR)
	_fly([soi - 1_000_000_000, 0, 0], [5_000_000_000, 0, -300_000_000])
	assert_eq(bridge.current_view["bodies"][keys["Planet"]]["soi_mm"], soi)
	assert_string_starts_with(screen._place.text, "Escaping Planet: ")
	assert_true(screen._peri_button.disabled, "periapsis is behind")
	assert_gt(screen.current_path.size(), 2)
	var crossed := false
	var started := Time.get_ticks_msec()
	for i in 400:
		_ticks(10)
		if _unit()["orbit"]["parent"] == keys["Star"]:
			crossed = true
			break
	assert_true(crossed, "left the planet's sphere")
	assert_lt(Time.get_ticks_msec() - started, 30_000, "the screen keeps up with the ticks")
	screen.force_paths()
	screen.refresh()
	assert_has(main.event_log.lines, "Orbiter: now orbiting Star")
	assert_true(screen._place.text.contains("Star"), screen._place.text)
	assert_gt(screen.current_path.size(), 2, "the path follows the new parent")
	await wait_process_frames(2)


func test_escape_path_drawing_matches_the_kernels_reference() -> void:
	var reference: GDScript = load("res://tests/sim/kernel/test_orbit_math.gd")
	var escape := OrbitMath.from_state([700_000_000, 0, 0], [0, 0, -4_000_000_000], GM_PLANET, 0)
	assert_true(escape["hyperbolic"])
	for tick: int in [0, 300, 5000, 40_000]:
		var ours := OrbitPath.position(escape, tick)
		var theirs: Array = reference.position_float(escape, tick)
		var exact := OrbitMath.position_at(escape, tick)
		for axis in 3:
			assert_almost_eq(ours[axis], theirs[axis], 1.0)
			assert_almost_eq(ours[axis], float(exact[axis]), 1000.0)
	var apsides := OrbitPath.apsides_mm(escape)
	assert_almost_eq(apsides[0], 700_000_000.0, 1000.0)
	assert_eq(apsides[1], INF)
	var branch := OrbitPath.ahead(escape, [0, 0, 0], 0, 32, 5_000_000_000.0)
	assert_eq(branch.size(), 33)
	var last := branch[32]
	assert_almost_eq(sqrt(last[0] * last[0] + last[1] * last[1] + last[2] * last[2]), 5_000_000_000.0, 1000.0, "drawn out to the reach")
	assert_eq(OrbitPath.ticks_until(escape, 0, PI), -1, "no apoapsis")
