extends GutTest
## D25: the new start flown through the flight screen on the real Sim: a burn out of
## the cluster onto an orbit round Frost, then, from a low Frost orbit, a landing on
## the probe's legs and the start of a take-off. A's test_new_start_landing flies the
## whole route in the sim, and test_landing_ui flies a climb to orbit to the end; this
## proves the client's path on Frost. Slow: the landing is 16000 ticks.

const CELL := 7
## The low orbit the landing starts from, 35 km up (above A19's 30 km low-flight
## band), so the client test doesn't fly the 300 km half ellipse from the cluster.
const LOW_ORBIT_MM := 95_000_000

var main: Node
var bridge: SimBridge
var screen: FlightScreen
var sim: Sim
var frost := 0
var probe := 0


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	screen = main.flight_screen
	sim = bridge.sim
	for id: int in bridge.current_view["bodies"]:
		if bridge.current_view["bodies"][id]["name"] == "Frost":
			frost = id
	probe = main.local_view.commanded_unit


## Steps the sim, then hands the view and its events to the client as play would. The
## flight screen reads the bridge, so the 3D view isn't refreshed: its ground detail
## near Frost would only lengthen the teardown.
func _run_to(tick: int) -> void:
	sim.step(tick - sim.current_tick())
	var events := sim.take_events()
	bridge.start(sim)
	if not events.is_empty():
		bridge.events_received.emit(events)
	screen._land_ms = -FlightScreen.PATH_REFRESH_MS
	screen._settle_until = 0
	screen.refresh()


func _probe() -> Dictionary:
	return bridge.current_view["units"][probe]


## Moves the probe onto a circular orbit round Frost 35 km up, as a lower orbit
## would leave it, through the sim's own orbit maths.
func _low_frost_orbit() -> void:
	var gm: int = sim._state["bodies"][frost]["gm"]
	var tick := sim.current_tick()
	var unit: Dictionary = sim._state["units"][probe]
	unit["orbit"] = OrbitMath.from_state([LOW_ORBIT_MM, 0, 0], [0, 0, -OrbitMath.speed_um_s(gm, LOW_ORBIT_MM, LOW_ORBIT_MM)], gm, tick)
	unit["orbit"]["parent"] = frost
	unit["pos_mm"] = OrbitMath.position_at(unit["orbit"], tick)
	sim._ctx.index.clear()
	_run_to(tick + 1)


func test_leave_the_cluster_land_on_frost_and_lift_off() -> void:
	main.toggle_flight()
	assert_string_starts_with(screen._place.text, "In Cluster")
	# A small burn against the cluster's motion leaves it for an orbit round Frost.
	screen.burn_now()
	screen.set_components(-20.0)
	assert_true(screen.preview["ok"], str(screen.preview))
	screen.plan()
	_run_to(sim.current_tick() + 200)
	assert_eq(int(_probe()["frame"]), 0, "out of the cluster")
	assert_eq(int(_probe()["orbit"].get("parent", 0)), frost, "onto an orbit round Frost")
	assert_has(main.event_log.lines, "Probe drifted out of its frame onto an orbit")
	assert_string_starts_with(screen._place.text, "Orbiting Frost: ")

	_low_frost_orbit()
	assert_string_starts_with(screen._place.text, "Orbiting Frost: ")
	while PlanetMesh.busy():
		await wait_process_frames(1)
	assert_eq(screen.land_body(), frost, "Frost is offered for landing")
	screen.choose_cell(CELL)
	assert_true(screen.land_preview["ok"], str(screen.land_preview))
	var ticks: int = screen.land_preview["detail"]["ticks"]
	screen.land()
	_run_to(sim.current_tick() + 1)
	assert_eq(_probe()["op"]["type"], "landing")
	_run_to(sim.current_tick() + ticks + 2)
	assert_eq(_probe()["landed"], { "body": frost, "cell": CELL }, "down on its legs")
	assert_string_starts_with(main.event_log.lines[-1], "Probe landed on Frost")
	assert_true(screen._takeoff_row.visible)

	screen._altitude.value = 40.0
	_run_to(sim.current_tick())
	assert_true(screen.takeoff_preview["ok"], str(screen.takeoff_preview))
	ticks = screen.takeoff_preview["detail"]["ticks"]
	screen.take_off()
	_run_to(sim.current_tick() + 1)
	assert_eq(_probe()["op"]["type"], "taking_off", "the climb back to orbit has begun")
	assert_gt(ticks, 0)
	assert_string_starts_with(InspectText.status(_probe(), bridge.current_view), "Taking off ")
