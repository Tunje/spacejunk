extends "res://tests/sim/industry/coast_fixture.gd"
## A cycle's optional `laps` (C25): after that many laps it finishes, task_cycle_done then
## task_finished, and the unit idles. 1 is a one-shot trip; without it the cycle repeats.


## The coast fixture's drone and cycle, set again with `laps`, after a tick.
func _with_laps(laps: Variant) -> Sim:
	var sim := _mining_cycle({})
	var drone: int = sim._state["units"].keys().max()
	var command := { "type": "set_cycle", "unit": drone,
		"args": { "steps": sim._state["units"][drone]["last_cycle"].duplicate(true) } }
	if laps != null:
		command["args"]["laps"] = laps
	sim.submit(command)
	sim.step()
	sim.take_events()
	return sim


func _drone(sim: Sim) -> int:
	return sim._state["units"].keys().max()


## Warps `ticks`, which test_a_counted_cycle_coasts_exactly shows is the same as stepping, and
## returns the drone's task events.
func _run(sim: Sim, ticks: int) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	var left := ticks
	while left > 0:
		left -= sim.coast(left)["ticks"]
		seen.append_array(sim.take_events().filter(func(event: Dictionary) -> bool:
			return event["unit"] == _drone(sim) and event["type"].begins_with("task_")))
	return seen


func test_two_laps_then_the_cycle_finishes() -> void:
	var sim := _with_laps(2)
	var task: int = sim._state["units"][_drone(sim)]["task"]
	assert_eq(sim.view()["tasks"][task]["laps"], 2, "the view shows it")
	var seen := _run(sim, 12_000)
	var types: Array = seen.map(func(event: Dictionary) -> String: return event["type"])
	assert_eq(types, ["task_cycle_done", "task_cycle_done", "task_finished"])
	assert_eq(seen[1]["data"], { "task": task, "cycle": 2 })
	assert_eq(seen[2]["tick"], seen[1]["tick"], "it finishes on the tick its last lap is done")
	assert_eq(sim._state["units"][_drone(sim)]["task"], 0, "the unit idles")
	assert_false(sim._state["tasks"].has(task))
	assert_gt(sim._state["units"][STATION]["inventory"].get("hematite", 0), 0)
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_one_lap_is_a_one_shot_trip() -> void:
	var sim := _with_laps(1)
	var types: Array = _run(sim, 8_000).map(func(event: Dictionary) -> String: return event["type"])
	assert_eq(types, ["task_cycle_done", "task_finished"])


func test_without_laps_the_cycle_repeats() -> void:
	var sim := _with_laps(null)
	var types: Array = _run(sim, 12_000).map(func(event: Dictionary) -> String: return event["type"])
	assert_does_not_have(types, "task_finished")
	assert_gt(types.count("task_cycle_done"), 2)
	assert_eq(sim.view()["tasks"][sim._state["units"][_drone(sim)]["task"]]["laps"], 0)


func test_laps_must_be_a_whole_number_above_zero() -> void:
	var sim := _mining_cycle({})
	var drone := _drone(sim)
	for laps: Variant in [0, -1, "2"]:
		var checked := sim.check({ "type": "set_cycle", "unit": drone,
			"args": { "steps": sim._state["units"][drone]["last_cycle"], "laps": laps } })
		assert_eq(checked["reason"], "malformed_command", str(laps))


func test_a_counted_cycle_coasts_exactly() -> void:
	var stepped := _with_laps(2)
	var coasted := _copy(stepped)
	assert_lt(_same_both_ways(stepped, coasted, 12_000), 40)
	assert_eq(stepped._state["units"][_drone(stepped)]["task"], 0)


## A v8 save from before C25 holds tasks with no laps: they load, show 0 and repeat.
func test_a_task_saved_without_laps_repeats() -> void:
	var sim := _with_laps(null)
	var task: int = sim._state["units"][_drone(sim)]["task"]
	sim._state["tasks"][task].erase("laps")
	var loaded := Sim.from_save(sim.to_save())
	assert_not_null(loaded, Sim.last_error())
	assert_eq(loaded.view()["tasks"][task]["laps"], 0)
	var types: Array = _run(loaded, 12_000).map(func(event: Dictionary) -> String: return event["type"])
	assert_does_not_have(types, "task_finished")


## C27: a one-shot plan is a list of orders, so a tier 1 core runs it; repeating stays tier 2.
func test_a_tier_one_core_flies_a_one_shot_plan() -> void:
	var sim := _mining_cycle({}, true, "basic_core", { "laps": 1 })
	var drone := _drone(sim)
	assert_eq(sim.view()["units"][drone]["core_tier"], 1)
	var types: Array = _run(sim, 8_000).map(func(event: Dictionary) -> String: return event["type"])
	assert_eq(types, ["task_cycle_done", "task_finished"])
	assert_gt(sim._state["units"][STATION]["inventory"].get("hematite", 0), 0, "the trip unloaded ore")
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_a_tier_one_core_may_not_repeat() -> void:
	var sim := _mining_cycle({}, false, "basic_core", { "laps": 2 })
	var drone := _drone(sim)
	var steps: Array = sim._state["units"][drone]["last_cycle"]
	for args: Dictionary in [{ "steps": steps, "laps": 2 }, { "steps": steps }]:
		assert_eq(sim.check({ "type": "set_cycle", "unit": drone, "args": args })["reason"], "tier_too_low",
			str(args.get("laps", "none")))


func test_a_tier_one_core_keeps_its_one_shot_but_not_a_repeat() -> void:
	var sim := _mining_cycle({}, true, "assisted_core", { "laps": 1 })
	var drone := _drone(sim)
	var basic := Units.add_part(sim._ctx, drone, "basic_core", sim._state["units"][drone]["root"], "side_b_nx", "mount")
	sim._state["parts"][sim._state["units"][drone]["root"]]["children"].append(basic)
	sim._ctx.index.clear()
	sim._state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	sim.submit({ "type": "assign_core", "unit": drone, "args": { "core": basic } })
	sim.step()
	assert_ne(sim._state["units"][drone]["task"], 0, "the one-shot plan goes on")
