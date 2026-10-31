extends GutTest

var main: Node
var bridge: SimBridge
var view: LocalView
var panel: OrderPanel
var ship: int
var station: int
var rock: int


func before_each() -> void:
	main = add_child_autofree(StubScene.build())
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	view = main.get_node("LocalView")
	panel = main.order_panel
	var state := bridge.current_view
	for id: int in state["units"]:
		if state["units"][id]["kind"] == "ship":
			ship = id
		else:
			station = id
	var bodies: Array = state["bodies"].keys()
	bodies.sort()
	rock = bodies[1]


func _run_ticks(ticks: int) -> void:
	bridge.set_paused(false)
	bridge.set_speed(8)
	for i in range(ceili(ticks / 8.0)):
		bridge.advance(0.1)
	bridge.set_paused(true)
	view.refresh(0.016)


func _fly_to_rock() -> void:
	view.select("body", rock, 0)
	assert_true(panel.press("Move to"))
	var ticks: int = bridge.check({ "type": "move_to", "unit": ship, "args": { "target": rock } })["detail"]["ticks"]
	_run_ticks(ticks + 8)


func _start_mining() -> void:
	_fly_to_rock()
	assert_true(panel.press("Scan"))
	_run_ticks(38)
	view.select("body", rock, 0)
	var deposit: int = bridge.current_view["deposits"].keys()[0]
	assert_true(panel.press("Mine %d" % deposit))
	_run_ticks(8)


func _unit(op_type: String, target: int = 0, part: int = 0) -> Dictionary:
	return {
		"op": { "type": op_type, "target": target, "part": part, "start_tick": 0, "end_tick": 0 },
		"heat": { "stored_j": 0, "limit_j": 0, "reject_w": 0, "input_w": 0 },
	}


func test_thrust_follows_the_moving_op() -> void:
	assert_true(Feedback.is_thrusting(_unit("moving")))
	assert_false(Feedback.is_thrusting(_unit("idle")))
	assert_false(Feedback.is_thrusting(_unit("mining")))


func test_mining_beam_finds_the_body_through_the_deposit() -> void:
	var state := { "deposits": { 12: { "body": 3 } } }
	assert_eq(Feedback.beam_of(_unit("mining", 12, 9), state), { "part": 9, "body": 3, "kind": Feedback.BEAM_MINE })


func test_scan_beam_targets_the_body_directly() -> void:
	assert_eq(Feedback.beam_of(_unit("scanning", 3, 9), { "deposits": {} }), { "part": 9, "body": 3, "kind": Feedback.BEAM_SCAN })


func test_no_beam_when_idle_or_the_deposit_is_gone() -> void:
	assert_true(Feedback.beam_of(_unit("idle"), { "deposits": {} }).is_empty())
	assert_true(Feedback.beam_of(_unit("mining", 12, 9), { "deposits": {} }).is_empty())


func test_working_part_only_for_operations_with_a_part() -> void:
	assert_eq(Feedback.working_part(_unit("docking", 1, 5)), 5)
	assert_eq(Feedback.working_part(_unit("moving", 1, 0)), 0)


func test_heat_level_is_a_clamped_ratio() -> void:
	var unit := _unit("idle")
	assert_eq(Feedback.heat_level(unit), 0.0, "no limit means no glow, not a division by zero")
	unit["heat"]["limit_j"] = 1000
	unit["heat"]["stored_j"] = 250
	assert_almost_eq(Feedback.heat_level(unit), 0.25, 0.001)
	unit["heat"]["stored_j"] = 5000
	assert_eq(Feedback.heat_level(unit), 1.0)


func test_plume_shows_only_in_flight() -> void:
	assert_false(view.crafts[ship].is_thrust_shown())
	view.select("body", rock, 0)
	assert_true(panel.press("Move to"))
	_run_ticks(8)
	assert_true(view.crafts[ship].is_thrust_shown())
	assert_true(panel.press("Stop"))
	_run_ticks(8)
	assert_false(view.crafts[ship].is_thrust_shown())


func test_station_has_no_plume_or_beam() -> void:
	assert_false(view.crafts[station].is_thrust_shown())
	assert_false(view.beams.has(station))


func test_plume_points_away_from_the_thruster_mount() -> void:
	var tips: Array = []
	var hull: Dictionary = bridge.current_view["units"][ship]["parts"]
	for child: Dictionary in hull["children"]:
		if child["def"] == "stub_tank":
			tips.append(view.crafts[ship].tip_of(child["children"][0]["id"]))
	assert_almost_eq(tips[0]["direction"].distance_to(Vector3.DOWN), 0.0, 0.001)


func test_beam_runs_from_the_laser_to_the_rock_while_mining() -> void:
	_start_mining()
	assert_true(view.beams[ship].visible)
	var body: BodyNode = view.bodies[rock]
	var reach: float = body.position.distance_to(view.crafts[ship].position) - body.scale.x
	assert_gt(view.beams[ship].length_m, reach * 0.9)
	assert_true(panel.press("Stop"))
	_run_ticks(8)
	assert_false(view.beams[ship].visible)


func test_beam_endpoints_land_exactly_where_aimed() -> void:
	var beam := BeamNode.new()
	add_child_autofree(beam)
	var from := Vector3(3, -2, 5)
	for to: Vector3 in [Vector3(40, 10, -30), Vector3(3, -2, -50), Vector3(-9, 60, 5), Vector3(3, -80, 5)]:
		beam.aim(from, to, Feedback.BEAM_MINE, 0.0)
		assert_almost_eq((beam.transform * Vector3(0, -0.5, 0)).distance_to(from), 0.0, 0.001, str(to))
		assert_almost_eq((beam.transform * Vector3(0, 0.5, 0)).distance_to(to), 0.0, 0.001, str(to))


func test_beam_stays_thin_at_any_angle() -> void:
	var beam := BeamNode.new()
	add_child_autofree(beam)
	beam.aim(Vector3.ZERO, Vector3(100, 40, -70), Feedback.BEAM_MINE, 0.0)
	var side_a: Vector3 = beam.transform.basis * Vector3.RIGHT
	var side_b: Vector3 = beam.transform.basis * Vector3.BACK
	assert_almost_eq(side_a.length(), BeamNode.WIDTHS_M[Feedback.BEAM_MINE], 0.001)
	assert_almost_eq(side_b.length(), BeamNode.WIDTHS_M[Feedback.BEAM_MINE], 0.001)


func test_beam_shows_while_scanning() -> void:
	_fly_to_rock()
	assert_true(panel.press("Scan"))
	_run_ticks(8)
	assert_true(view.beams[ship].visible)


func test_mining_turns_the_laser_towards_the_rock() -> void:
	_start_mining()
	for i in range(400):
		view.refresh(0.016)
	var laser: int = bridge.current_view["units"][ship]["op"]["part"]
	var tip: Dictionary = view.crafts[ship].tip_of(laser)
	var outward: Vector3 = view.crafts[ship].basis * (tip["direction"] as Vector3)
	var to_rock: Vector3 = (view.bodies[rock].position - view.crafts[ship].position).normalized()
	assert_gt(outward.dot(to_rock), 0.99)


func test_stub_heat_rises_while_mining_and_falls_when_idle() -> void:
	_start_mining()
	_run_ticks(400)
	var hot: int = bridge.current_view["units"][ship]["heat"]["stored_j"]
	assert_gt(hot, 0)
	assert_true(panel.press("Stop"))
	_run_ticks(80)
	assert_lt(bridge.current_view["units"][ship]["heat"]["stored_j"], hot)


func test_radiator_glows_with_heat_and_goes_dark_when_cool() -> void:
	var craft: CraftNode = view.crafts[ship]
	var radiator: int = craft._radiators[0]
	var unit: Dictionary = bridge.current_view["units"][ship].duplicate(true)
	unit["heat"]["limit_j"] = 100
	unit["heat"]["stored_j"] = 80
	craft.apply_feedback(unit, 0.016)
	var material: StandardMaterial3D = craft._materials[radiator]
	assert_true(material.emission_enabled)
	assert_almost_eq(material.emission_energy_multiplier, CraftNode.HEAT_ENERGY * 0.8, 0.01)
	unit["heat"]["stored_j"] = 0
	craft.apply_feedback(unit, 0.016)
	assert_false(material.emission_enabled)


func test_selection_beats_heat_glow() -> void:
	var craft: CraftNode = view.crafts[ship]
	var radiator: int = craft._radiators[0]
	var unit: Dictionary = bridge.current_view["units"][ship].duplicate(true)
	unit["heat"]["limit_j"] = 100
	unit["heat"]["stored_j"] = 80
	view.select("unit", ship, radiator)
	craft.apply_feedback(unit, 0.016)
	assert_almost_eq(craft._materials[radiator].emission_energy_multiplier, CraftNode.SELECT_ENERGY, 0.001)


func test_working_part_pulses_while_docking() -> void:
	view.select("unit", station, 0)
	assert_true(panel.press("Dock"))
	_run_ticks(8)
	var craft: CraftNode = view.crafts[ship]
	var port: int = bridge.current_view["units"][ship]["op"]["part"]
	var seen := 0.0
	for i in range(40):
		craft.apply_feedback(bridge.current_view["units"][ship], 0.02)
		seen = maxf(seen, craft._materials[port].emission_energy_multiplier)
	assert_gt(seen, CraftNode.PULSE_ENERGY * 0.5)


func _grown_tree(unit: Dictionary) -> Dictionary:
	var root: Dictionary = unit["parts"].duplicate(true)
	root["children"].append({
		"id": 9000, "def": "stub_lidar", "parent_connector": "side_pz", "connector": "mount",
		"state": "on", "fault": "", "draw_w": 0, "priority": 0, "children": [],
	})
	return root


func test_a_new_part_grows_in_and_settles() -> void:
	var craft: CraftNode = view.crafts[ship]
	var unit: Dictionary = bridge.current_view["units"][ship]
	craft.build(ship, _grown_tree(unit), bridge.defs()["modules"])
	assert_true(craft.is_growing())
	assert_eq(craft._growing.keys(), [9000], "only the new part")
	craft.apply_feedback(unit, 0.1)
	assert_lt(craft._meshes[9000].scale.x, 1.0)
	assert_true(craft._materials[9000].emission_enabled)
	for i in range(30):
		craft.apply_feedback(unit, 0.1)
	assert_false(craft.is_growing())
	assert_almost_eq(craft._meshes[9000].scale.x, 1.0, 0.001)
	assert_false(craft._materials[9000].emission_enabled)


func test_first_build_does_not_grow_every_part() -> void:
	assert_false(view.crafts[ship].is_growing())


func test_effects_survive_a_rebuild() -> void:
	var craft: CraftNode = view.crafts[ship]
	var unit: Dictionary = bridge.current_view["units"][ship]
	craft.build(ship, _grown_tree(unit), bridge.defs()["modules"])
	assert_eq(craft._plumes.size(), 1)
	assert_eq(craft._radiators.size(), 1)
