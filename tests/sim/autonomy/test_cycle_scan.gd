extends "res://tests/sim/industry/coast_fixture.gd"
## A cycle may scan (C28). The first scan of a rock reveals it and pays survey points; a cycle's
## scan of a rock already scanned passes as done in one tick, with nothing paid. A cycle's
## start_mining still names a deposit already found: hidden stays hidden.


## The coast fixture's drone with a LIDAR, set a cycle that scans the rock before it mines there.
func _scanning_cycle(laps: int) -> Sim:
	var sim := _mining_cycle({})
	var drone: int = sim._state["units"].keys().max()
	var root: int = sim._state["units"][drone]["root"]
	_fit(sim, drone, "lidar_mk1", root, "side_b_pz")
	sim._ctx.index.clear()
	sim._state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	var steps: Array = sim._state["units"][drone]["last_cycle"].duplicate(true)
	steps.insert(3, { "type": "scan", "args": { "target": ROCK } })
	var args := { "steps": steps }
	if laps > 0:
		args["laps"] = laps
	sim.submit({ "type": "set_cycle", "unit": drone, "args": args })
	sim.step()
	assert_false(sim.take_events().any(func(event: Dictionary) -> bool: return event["type"] == "command_rejected"))
	return sim


func _drone(sim: Sim) -> int:
	return sim._state["units"].keys().max()


func _run(sim: Sim, ticks: int) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	var left := ticks
	while left > 0:
		left -= sim.coast(left)["ticks"]
		seen.append_array(sim.take_events().filter(func(event: Dictionary) -> bool:
			return event["unit"] == _drone(sim)))
	return seen


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


func test_a_one_shot_trip_scans_its_rock_then_mines() -> void:
	var sim := _scanning_cycle(1)
	assert_false(sim._state["bodies"][ROCK].get("scanned", false), "the rock starts unscanned")
	var types := _types(_run(sim, 8_000))
	assert_lt(types.find("scan_finished"), types.find("mining_stopped"), "scanned, then mined")
	assert_eq(types[-1], "task_finished")
	assert_true(sim._state["bodies"][ROCK]["scanned"])
	assert_eq(sim._state["science"]["paid"].get("survey:%d" % ROCK, 0), 1, "survey points paid once")
	assert_gt(sim._state["units"][STATION]["inventory"].get("hematite", 0), 0)
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_a_later_laps_scan_passes_straight_through() -> void:
	var sim := _scanning_cycle(3)
	var events := _run(sim, 20_000)
	var types := _types(events)
	assert_eq(types.count("task_cycle_done"), 3)
	assert_eq(types.count("scan_finished"), 1, "only the first lap scans")
	assert_eq(sim._state["science"]["paid"].get("survey:%d" % ROCK, 0), 1, "nothing paid again")


func test_a_scanning_cycle_coasts_exactly() -> void:
	var stepped := _scanning_cycle(2)
	var coasted := _copy(stepped)
	_same_both_ways(stepped, coasted, 14_000)
	assert_eq(stepped._state["units"][_drone(stepped)]["task"], 0, "both laps done")


func test_a_scan_order_on_a_scanned_rock_still_scans_and_pays() -> void:
	var sim := _reference()
	var ship: Dictionary = sim._state["units"][23]
	ship["dock"] = {}
	ship["at_target"] = ROCK
	sim._state["bodies"][ROCK]["scanned"] = true
	sim._ctx.index.clear()
	sim.submit({ "type": "scan", "unit": 23, "args": { "target": ROCK } })
	var paid := 0
	for i in 2_000:
		sim.step()
		for event in sim.take_events():
			if event["type"] == "science_gained":
				paid += 1
		if sim._state["units"][23]["task"] == 0 and i > 2:
			break
	assert_eq(paid, 1, "an order is not a cycle: it scans again")


func test_a_cycle_cannot_mine_a_deposit_not_yet_found() -> void:
	var sim := _scanning_cycle(1)
	var drone := _drone(sim)
	sim._state["deposits"][DEPOSIT]["found"] = false
	sim._ctx.index.clear()
	var checked := sim.check({ "type": "set_cycle", "unit": drone,
		"args": { "steps": sim._state["units"][drone]["last_cycle"], "laps": 1 } })
	assert_eq(checked["reason"], "bad_cycle", "hidden stays hidden")
