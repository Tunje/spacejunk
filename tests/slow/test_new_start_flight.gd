extends GutTest
## D25: the new start flown through the flight screen on the real Sim: a burn out of
## the cluster onto an orbit round Frost, a landing on Frost on the probe's legs, and
## a take-off back to orbit. Slow: the landing's half ellipse is about 70000 ticks,
## and Frost's terrain is built first.

const CELL := 7

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


## Steps the sim, then hands the view and its events to the client as play would.
func _run_to(tick: int) -> void:
	sim.step(tick - sim.current_tick())
	var events := sim.take_events()
	bridge.start(sim)
	if not events.is_empty():
		bridge.events_received.emit(events)
	main.local_view.refresh(0.016)
	screen._land_ms = -FlightScreen.PATH_REFRESH_MS
	screen._settle_until = 0
	screen.refresh()


func _probe() -> Dictionary:
	return bridge.current_view["units"][probe]


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

	screen._altitude.value = 30.0
	_run_to(sim.current_tick())
	assert_true(screen.takeoff_preview["ok"], str(screen.takeoff_preview))
	ticks = screen.takeoff_preview["detail"]["ticks"]
	screen.take_off()
	_run_to(sim.current_tick() + 1)
	assert_eq(_probe()["op"]["type"], "taking_off")
	_run_to(sim.current_tick() + ticks + 2)
	assert_true(_probe()["landed"].is_empty())
	assert_has(main.event_log.lines, "Probe took off from Frost")
	assert_string_starts_with(screen._place.text, "Orbiting Frost: ")
