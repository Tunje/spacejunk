extends GutTest
## The frame measurement itself needs a GPU and runs from tools/frametime.ps1.
## These cover its statistics, its load and its order logic.


func _frames(values: Array) -> PackedFloat64Array:
	return PackedFloat64Array(values)


func _ramp(count: int) -> PackedFloat64Array:
	var frames: PackedFloat64Array = []
	for index in range(count):
		frames.append(float(index + 1))
	return frames


func test_percentiles_on_a_known_ramp() -> void:
	var sorted := _ramp(100)
	assert_eq(FrameProbe.percentile(sorted, 0.5), 50.0)
	assert_eq(FrameProbe.percentile(sorted, 0.95), 95.0)
	assert_eq(FrameProbe.percentile(sorted, 0.99), 99.0)
	assert_eq(FrameProbe.percentile(sorted, 1.0), 100.0)


func test_percentile_of_one_frame() -> void:
	assert_eq(FrameProbe.percentile(_frames([7.0]), 0.95), 7.0)


func test_stats_do_not_depend_on_frame_order() -> void:
	var result := FrameProbe.stats(_frames([30.0, 10.0, 20.0]))
	assert_eq(result["worst_ms"], 30.0)
	assert_almost_eq(result["average_ms"], 20.0, 0.001)
	assert_almost_eq(result["average_fps"], 50.0, 0.001)


func test_stats_leave_the_samples_unsorted() -> void:
	var frames := _frames([30.0, 10.0])
	FrameProbe.stats(frames)
	assert_eq(frames[0], 30.0)


func test_a_steady_60_fps_passes() -> void:
	var frames: PackedFloat64Array = []
	frames.resize(200)
	frames.fill(16.0)
	assert_true(FrameProbe.stats(frames)["passed"])


func test_a_rare_hitch_is_reported_without_failing() -> void:
	var frames: PackedFloat64Array = []
	frames.resize(200)
	frames.fill(10.0)
	frames[50] = 90.0
	var result := FrameProbe.stats(frames)
	assert_true(result["passed"])
	assert_eq(result["worst_ms"], 90.0)


func test_a_slow_run_fails() -> void:
	var frames: PackedFloat64Array = []
	frames.resize(200)
	frames.fill(25.0)
	assert_false(FrameProbe.stats(frames)["passed"])


func test_op_counts_cover_ships_only() -> void:
	var view := { "units": {
		1: { "kind": "ship", "op": { "type": "mining" } },
		2: { "kind": "ship", "op": { "type": "moving" } },
		3: { "kind": "station", "op": { "type": "idle" } },
	} }
	var totals: Dictionary = {}
	FrameProbe.count_ops(view, totals)
	FrameProbe.count_ops(view, totals)
	assert_eq(totals, { "mining": 2, "moving": 2 })


func test_load_scenario_adds_ships_only() -> void:
	var base := StubSim.new_game("stub", 1).view()
	var load_view := StubSim.new_game("stub_load", 1).view()
	assert_eq(load_view["units"].size(), base["units"].size() + StubSim.LOAD_EXTRA_SHIPS)
	assert_eq(load_view["bodies"].size(), base["bodies"].size())


func test_load_ships_do_not_share_a_position() -> void:
	var view := StubSim.new_game("stub_load", 1).view()
	var seen: Dictionary = {}
	for id: int in view["units"]:
		seen[str(view["units"][id]["pos_mm"])] = true
	assert_eq(seen.size(), view["units"].size())


func test_load_scenario_keeps_the_view_shape_and_saves() -> void:
	var sim := StubSim.new_game("stub_load", 1)
	sim.step(3)
	var text := sim.to_save()
	assert_eq(StubSim.from_save(text).to_save(), text)


func test_spread_offsets_differ_and_stay_close() -> void:
	var seen: Dictionary = {}
	for id in range(1, 40):
		var offset := LocalView.spread_offset(id)
		assert_lt(offset.length(), 60.0)
		assert_gt(offset.length(), 10.0)
		seen[offset] = true
	assert_eq(seen.size(), 39)


func test_craft_sharing_a_stop_spread_on_screen_but_not_in_the_sim() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	var sim := StubSim.new_game("stub_load", 1)
	var ids: Array = []
	for id: int in sim.view()["units"]:
		if sim.view()["units"][id]["kind"] == "ship":
			ids.append(id)
	var rock: int = 2
	for id: int in ids:
		sim.submit({ "type": "move_to", "unit": id, "args": { "target": rock } })
	sim.step(200)
	var view := sim.view()
	assert_lt(IntMath.dist(view["units"][ids[0]]["pos_mm"], view["units"][ids[1]]["pos_mm"]), LocalView.CROWD_MM)
	bridge.start(sim)
	var local: LocalView = main.get_node("LocalView")
	for i in range(200):
		local.refresh(0.016)
	var first: CraftNode = local.crafts[ids[0]]
	var second: CraftNode = local.crafts[ids[1]]
	assert_gt(first.position.distance_to(second.position), 10.0)
	assert_eq(sim.view()["units"][ids[0]]["pos_mm"], view["units"][ids[0]]["pos_mm"])


func test_a_docked_ship_does_not_push_its_station_aside() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	var local: LocalView = main.get_node("LocalView")
	var station: int = 0
	var view: Dictionary = bridge.current_view
	for id: int in view["units"]:
		if view["units"][id]["kind"] == "station":
			station = id
	var docked_ship: Dictionary = view["units"][local.commanded_unit].duplicate(true)
	docked_ship["pos_mm"] = view["units"][station]["pos_mm"].duplicate()
	docked_ship["dock"] = { "port": 1, "target_unit": station, "target_port": 2 }
	var state := { "units": { station: view["units"][station], local.commanded_unit: docked_ship } }
	assert_false(local._is_crowded(view["units"][station], station, state))
	assert_false(local._is_crowded(docked_ship, local.commanded_unit, state))


func test_a_lone_craft_sits_exactly_on_its_sim_position() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	main.get_node("Bridge").set_paused(true)
	var local: LocalView = main.get_node("LocalView")
	local.refresh(0.016)
	assert_eq(local.crafts[local.focus_id].display_offset, Vector3.ZERO)


func _order_view() -> Dictionary:
	return {
		"units": { 1: { "op": { "type": "idle" }, "at_target": 0 } },
		"bodies": { 5: { "scanned": false }, 6: { "scanned": false } },
		"deposits": {},
	}


func test_idle_ship_in_open_space_flies() -> void:
	assert_eq(FrameProbe.next_order(_order_view(), 1, 9, [5, 6])["type"], "move_to")


func test_busy_ship_is_left_alone() -> void:
	var view := _order_view()
	view["units"][1]["op"]["type"] = "moving"
	assert_true(FrameProbe.next_order(view, 1, 9, [5, 6]).is_empty())


func test_ship_at_an_unscanned_rock_scans() -> void:
	var view := _order_view()
	view["units"][1]["at_target"] = 5
	assert_eq(FrameProbe.next_order(view, 1, 9, [5, 6])["type"], "scan")


func test_ship_at_a_deposit_mines() -> void:
	var view := _order_view()
	view["units"][1]["at_target"] = 5
	view["bodies"][5]["scanned"] = true
	view["deposits"][20] = { "body": 5 }
	var order := FrameProbe.next_order(view, 1, 9, [5, 6])
	assert_eq(order["type"], "start_mining")
	assert_eq(order["args"], { "deposit": 20, "module": 9 })


func test_ship_at_an_empty_scanned_rock_moves_on() -> void:
	var view := _order_view()
	view["units"][1]["at_target"] = 5
	view["bodies"][5]["scanned"] = true
	assert_eq(FrameProbe.next_order(view, 1, 9, [5, 6])["type"], "move_to")


func test_load_runs_in_the_scene_with_every_ship_busy() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.start(StubSim.new_game("stub_load", 1))
	var probe := FrameProbe.new()
	probe.main = main
	probe._give_orders()
	bridge.set_paused(false)
	bridge.advance(0.2)
	bridge.set_paused(true)
	main.get_node("LocalView").refresh(0.016)
	var busy := 0
	var view: Dictionary = bridge.current_view
	for id: int in view["units"]:
		if view["units"][id]["kind"] == "ship" and view["units"][id]["op"]["type"] == "moving":
			busy += 1
	assert_eq(busy, StubSim.LOAD_EXTRA_SHIPS + 1)
	assert_eq(main.get_node("LocalView").crafts.size(), view["units"].size())
	probe.free()
