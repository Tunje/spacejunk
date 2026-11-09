extends GutTest
## D19: hand-flown descent (A19) through the flight screen, on the real Sim: lift off
## from the ground, read the predicted touchdown and the legs' verdict, and see it
## land or crash as predicted. On a 250 km airless world light enough (0.16 m/s^2)
## for the starter ship's thrust to lift off: on Grit, at 1.04 m/s^2, it can't.
## Slow: it waits for planet builds and flies hops of a minute or more.

const GM := 10_000_000
const RADIUS_MM := 250_000_000
const SEED := 48213
const RANGE_M := 6000
const CELL := 4321

var main: Node
var bridge: SimBridge
var screen: FlightScreen
var sim: Sim
var keys := {}
var events: Array[Dictionary] = []


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = "reference"
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	screen = main.flight_screen
	events.clear()


## A ship landed on a hex, with or without legs, by the atomic autopilot (which
## needs legs; without them it is set down directly).
func _on_the_ground(legs: bool) -> void:
	var defs := DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": 132_712_440_018_000_000 },
			{ "key": "planet", "name": "Grit", "kind": "planet", "radius_mm": RADIUS_MM, "visual_seed": 2,
				"deposits": [], "gm": GM, "orbit": { "parent": "star", "a_mm": 149_597_870_700_000 },
				"planet": { "seed": SEED, "height_range_m": RANGE_M } },
		],
		"units": [{ "key": "ship", "template": "starter_ship", "name": "Probe", "pos_mm": [0, 0, 0],
			"inventory": [{ "item": "propellant", "grams": 1_000_000 }], "dock": null }],
	}, {}), "")
	for table: String in ["bodies", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	if legs:
		assert_true(LandingLegs.fit(sim, keys["Probe"]))
	# Set straight down on the hex, as a landing ends: the autopilot's half-ellipse
	# descent on this light world is tens of thousands of ticks the test doesn't need.
	var ship: Dictionary = sim._state["units"][keys["Probe"]]
	var n := PlanetGrid.n_for_radius(RADIUS_MM)
	var height := PlanetGrid.height_m(SEED, PlanetGrid.direction(CELL, n), PlanetMesh.DEFAULT_WEIGHTS, RANGE_M)
	ship["orbit"] = {}
	ship["landed"] = { "body": keys["Grit"], "cell": CELL }
	ship["pos_mm"] = PlanetGrid.centre_mm(CELL, n, RADIUS_MM, height)
	ship["inventory"]["propellant"] = 1_900_000
	sim._ctx.index.clear()
	sim.take_events()
	bridge.events_received.connect(func(batch: Array[Dictionary]) -> void: events.append_array(batch))
	bridge.start(sim)
	main.local_view.rebuild()
	main.toggle_flight()
	assert_false(_ship()["landed"].is_empty(), "on the ground")


func _ship() -> Dictionary:
	return bridge.current_view["units"][keys["Probe"]]


## Steps the sim a tick at a time through the bridge, so events reach the log.
func _ticks(count: int) -> void:
	bridge.set_paused(false)
	for i in count:
		bridge.advance(1.0 / bridge.ticks_per_second())
	bridge.set_paused(true)
	screen.force_paths()
	screen.refresh()


## Runs on until an event, without forcing the screen to work its paths out again.
func _until(event_type: String, limit: int) -> Dictionary:
	bridge.set_paused(false)
	for i in range(0, limit, 20):
		for step in 20:
			bridge.advance(1.0 / bridge.ticks_per_second())
		for entry: Dictionary in events:
			if entry["type"] == event_type:
				bridge.set_paused(true)
				return entry
	bridge.set_paused(true)
	return {}


func _hop(radial_m_s: float) -> void:
	screen.lift_off()
	screen.set_components(0.0, 0.0, radial_m_s)
	assert_true(screen.preview["ok"], str(screen.preview))
	var burn_ticks: int = screen.preview["detail"]["burn_ticks"]
	screen.plan()
	_ticks(burn_ticks + 10)


func test_on_the_ground_the_screen_offers_lift_off() -> void:
	_on_the_ground(true)
	assert_true(screen._descent_box.visible)
	assert_true(screen._lift_button.visible)
	assert_eq(screen._verdict.text, "Legs take up to 6.0 m/s.")
	screen.lift_off()
	assert_eq(screen.components(), [0, 0, 30_000_000] as Array[int], "straight up, now")
	assert_true(screen.preview["ok"], "a burn on the ground is a lift-off")
	# A55 flies the lift-off exactly: 30 m/s up on Grit comes back down.
	assert_string_starts_with(screen._after.text, "Then back on the ground in ")


func test_a_hard_hop_predicts_the_crash_it_gets() -> void:
	_on_the_ground(true)
	_hop(10.0)
	assert_ne(int(_ship()["stepped"]), 0, "lifted off into stepped flight")
	assert_string_starts_with(screen._place.text, "Low over Grit: ")
	assert_false(Array(main.event_log.lines).any(func(line: String) -> bool: return line.contains("flying low")),
		"stepped flight isn't news (A55)")
	assert_false(screen.contact.is_empty(), "predict finds the ground")
	assert_string_starts_with(screen._descent_text.text, "Touchdown in ")
	assert_string_starts_with(screen._verdict.text, "CRASH at this speed")
	assert_false(screen.touchdown.is_empty(), "the touchdown point is marked")
	var predicted: Dictionary = screen.contact.duplicate()
	var crashed := _until("crashed", 3000)
	assert_false(crashed.is_empty(), "it crashed, as warned")
	assert_eq(crashed["data"]["speed_um_s"], predicted["speed_um_s"], "at the predicted speed")
	assert_eq(crashed["data"]["cell"], predicted["cell"], "on the predicted hex")
	await wait_process_frames(2)
	assert_string_starts_with(main.event_log.lines[-1], "Probe crashed on Grit at ")


func test_a_gentle_hop_lands_safely() -> void:
	_on_the_ground(true)
	_hop(2.0)
	assert_string_starts_with(screen._verdict.text, "Lands safely")
	assert_eq(screen._verdict.modulate, FlightScreen.SAFE_COLOUR)
	var landed := _until("landed", 3000)
	assert_false(landed.is_empty())
	assert_lt(landed["data"]["speed_um_s"], 6_000_000)
	assert_string_starts_with(main.event_log.lines[-1], "Probe landed on Grit at ")


func test_without_legs_any_touchdown_is_a_crash() -> void:
	_on_the_ground(false)
	assert_eq(_ship()["touchdown_mm_s"], 0)
	assert_eq(screen._verdict.text, "No landing legs: any touchdown is a crash.")
	_hop(2.0)
	assert_string_starts_with(screen._verdict.text, "CRASH: no landing legs")
