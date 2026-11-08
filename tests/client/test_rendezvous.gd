extends GutTest
## D46: the rendezvous readouts and markers, from the Sim's relative state to a target,
## Sim.relative (A54, real_orbits.md 3.5). The wording on a sample state, and the
## flight screen's Target section on the real new start, its query faked until A54.

const TPS := 10

var state := {
	"tick": 0, "parent": 2, "rel_pos_mm": [1_234_000, 0, 0], "rel_vel_um_s": [0, 3_000_000, 0],
	"range_mm": 1_234_000, "speed_um_s": 3_225_000, "closing_um_s": 3_200_000, "lateral_um_s": 400_000,
	"closest": { "tick": 25_800, "range_mm": 1_200_000, "speed_um_s": 3_100_000 },
	"closest_planned": { "tick": 24_600, "range_mm": 120_000, "speed_um_s": 800_000 },
	"plane": { "inclination_mdeg": 2_300, "ascending_tick": 7_200, "descending_tick": 34_800 },
	"phase_mdeg": 345_800,
	"window": { "depart_tick": 111_000, "ticks": 78_000 },
	"stop": { "burn_ticks": 700, "lead_ticks": 350, "propellant_g": 12_000 },
	"dock": { "range_mm": 1_600, "speed_um_s": 150_000, "capture_range_mm": 2_000, "capture_speed_um_s": 200_000, "reason": "" },
}


## Sim.relative until A54 merges: the same state for any target but 99, which it refuses.
class FakeSim extends RefCounted:
	var answer: Dictionary = {}

	func relative(_unit: int, target: int, _from_tick: int, _horizon_ticks: int = 0) -> Dictionary:
		return { "reason": "invalid_target" } if target == 99 else answer


func test_distances_and_speeds_read_down_to_docking_scale() -> void:
	assert_eq(RendezvousLogic.distance(350), "35 cm")
	assert_eq(RendezvousLogic.distance(4_200), "4.2 m")
	assert_eq(RendezvousLogic.distance(860_000), "860 m")
	assert_eq(RendezvousLogic.distance(12_400_000), "12.4 km")
	assert_eq(RendezvousLogic.speed(4_000), "4 mm/s")
	assert_eq(RendezvousLogic.speed(150_000), "15 cm/s")
	assert_eq(RendezvousLogic.speed(3_200_000), "3.2 m/s")
	assert_eq(RendezvousLogic.speed(-3_200_000), "3.2 m/s", "a size, the sign is in the words")


func test_each_readout_line() -> void:
	assert_eq(RendezvousLogic.range_text(state), "Range 1.2 km")
	assert_eq(RendezvousLogic.motion_text(state), "Closing at 3.2 m/s, 40 cm/s across")
	assert_eq(RendezvousLogic.closest_text(state, false, 0, TPS), "Closest approach 1.2 km in 43 min 0 s, at 3.1 m/s")
	assert_eq(RendezvousLogic.closest_text(state, true, 0, TPS), "With the planned burns: 120 m in 41 min 0 s, at 80 cm/s")
	assert_eq(RendezvousLogic.planes_text(state, 0, TPS), "Planes 2.3° apart: ascending node in 12 min 0 s, descending in 58 min 0 s")
	assert_eq(RendezvousLogic.phase_text(state, 0, TPS), "Target 14.2° behind; next window in 3 h 5 min, a 2 h 10 min trip")
	assert_eq(RendezvousLogic.stop_text(state, TPS), "To stop: a 1 min 10 s burn, start it 35 s early, 12.0 kg")
	assert_eq(RendezvousLogic.dock_text(state), "Dock: ready (1.6 m of 2.0 m, 15 cm/s of 20 cm/s)")


func test_opening_same_plane_no_shared_parent_and_a_refused_dock() -> void:
	var other := state.duplicate(true)
	other["closing_um_s"] = -500_000
	other["plane"]["inclination_mdeg"] = 3
	other["phase_mdeg"] = -1
	other["window"] = {}
	other["dock"]["reason"] = "too_fast"
	assert_string_starts_with(RendezvousLogic.motion_text(other), "Opening at 50 cm/s")
	assert_eq(RendezvousLogic.planes_text(other, 0, TPS), "Same plane")
	assert_eq(RendezvousLogic.phase_text(other, 0, TPS), "", "no shared parent, no window")
	assert_string_starts_with(RendezvousLogic.dock_text(other), "Dock: %s (" % OrderText.reason("too_fast", {}))
	other["phase_mdeg"] = 20_000
	assert_eq(RendezvousLogic.phase_text(other, 0, TPS), "Target 20.0° ahead")


func test_missing_figures_are_left_out() -> void:
	var bare := { "range_mm": 5_000, "closing_um_s": 0, "lateral_um_s": 0, "closest_planned": {}, "phase_mdeg": -1 }
	var lines := RendezvousLogic.lines(bare, 0, TPS)
	assert_eq(lines[0], "Range 5.0 m")
	assert_false(Array(lines).any(func(line: String) -> bool:
		return line.begins_with("Closest") or line.begins_with("With") or line.begins_with("Dock") or line.begins_with("To stop")))
	assert_eq(RendezvousLogic.lines({}, 0, TPS).size(), 0)


func test_fetch_asks_the_query_and_drops_a_refusal() -> void:
	var sim := FakeSim.new()
	sim.answer = state
	assert_eq(RendezvousLogic.fetch(sim, 13, 4, 0), state)
	assert_eq(RendezvousLogic.fetch(sim, 13, 99, 0), {}, "invalid_target")
	assert_eq(RendezvousLogic.fetch(sim, 13, 0, 0), {}, "no target")
	assert_eq(RendezvousLogic.fetch(null, 13, 4, 0), {}, "no Sim")


func test_the_flight_screen_targets_the_selection() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	var rock := 0
	for id: int in bridge.current_view["bodies"]:
		if bridge.current_view["bodies"][id]["name"] == "Red Rock":
			rock = id
	main.toggle_flight()
	var flight: FlightScreen = main.flight_screen
	flight.refresh()
	assert_string_starts_with(flight._target_title.text, "No target")
	assert_true(flight._target_button.disabled, "nothing selected to target")
	main.local_view.select("body", rock, 0)
	flight.refresh()
	assert_false(flight._target_button.disabled)
	flight._target_button.pressed.emit()
	assert_string_starts_with(flight._target_title.text, "Target: Red Rock")
	main.rendezvous_panel.refresh()
	assert_true(main.rendezvous_panel.visible, "the readouts' panel, while flying with a target")
	assert_gt(main.rendezvous_panel.shown_lines().size(), 0, "a line, if only that the Sim gives nothing yet")
	assert_true(flight._target_button.disabled, "already the target")
	flight._untarget_button.pressed.emit()
	assert_eq(flight.target_id, 0)
	assert_eq(main.rendezvous_markers.spots(), {}, "no target, no markers")
	main.rendezvous_panel.refresh()
	assert_false(main.rendezvous_panel.visible)


## The burn preview says how early to start, from check(plan_burn)'s lead_ticks (A54).
func test_the_burn_preview_gives_the_lead() -> void:
	var view := { "units": { 1: { "inventory": { "propellant": 1_000_000 }, "orbit": {}, "low_flight": 0, "landed": {},
		"pos_mm": [0, 0, 0], "frame": 0 } }, "frames": {} }
	var detail := { "dv_um_s": 20_000_000, "propellant_g": 5_000, "burn_ticks": 1300, "lead_ticks": 650, "vel_um_s": [0, 0, 0] }
	assert_string_contains(FlightLogic.preview_lines(detail, view, 1, TPS)[0], "Start it 1 min 5 s before the moment it's aimed at")
	detail["lead_ticks"] = 4
	assert_false(FlightLogic.preview_lines(detail, view, 1, TPS)[0].contains("Start it"), "under a second: not worth saying")
