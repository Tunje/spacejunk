extends GutTest
## The order half of the task state machine (autonomy.md sections 3, 6 and 7), using `scan`.

const SHIP := 23
const CORE := 25
const LIDAR := 36
const ROCK := 2
const OTHER_ROCK := 4

var sim: Sim
var state: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	state["units"][SHIP]["dock"] = {}
	state["units"][SHIP]["at_target"] = ROCK


func _scan() -> Dictionary:
	return { "type": "scan", "unit": SHIP, "args": { "target": ROCK } }


func _stop() -> Dictionary:
	return { "type": "stop", "unit": SHIP, "args": {} }


func _run(command: Dictionary, ticks: int = 1) -> Array[Dictionary]:
	sim.submit(command)
	sim.step(ticks)
	return sim.take_events()


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


func _assert_idle() -> void:
	var unit: Dictionary = sim.view()["units"][SHIP]
	assert_eq(unit["task"], 0)
	assert_eq(unit["op"]["type"], "idle")
	assert_eq(sim.view()["tasks"].size(), 0)


func test_an_order_makes_a_one_step_task() -> void:
	var command_id := sim.submit(_scan())
	sim.step()
	var view := sim.view()
	var task_id: int = view["units"][SHIP]["task"]
	assert_eq(sim.take_events()[0]["data"], { "task": task_id, "command": command_id })
	assert_eq(view["tasks"][task_id], {
		"id": task_id, "owner": SHIP, "kind": "order", "state": "running", "reason": "", "hold": false,
		"steps": [{ "type": "scan", "args": { "target": ROCK } }],
		"step": 0, "cycle": 0, "since_tick": 1, "command": command_id,
	})


func test_the_operation_starts_on_the_tick_the_order_applies() -> void:
	sim.submit(_scan())
	sim.step()
	var op: Dictionary = sim.view()["units"][SHIP]["op"]
	assert_eq(op["start_tick"], 1)
	assert_eq(op["end_tick"], 300)


func test_the_view_is_a_copy() -> void:
	sim.submit(_scan())
	sim.step()
	var view := sim.view()
	var task_id: int = view["units"][SHIP]["task"]
	view["tasks"][task_id]["steps"][0]["args"]["target"] = 99
	assert_eq(sim.view()["tasks"][task_id]["steps"][0]["args"]["target"], ROCK)


func test_a_unit_with_no_core_refuses_orders() -> void:
	state["units"][SHIP]["core"] = 0
	var events := _run(_scan())
	assert_eq(events[0]["data"]["reason"], "no_core")


func test_an_offline_core_refuses_orders() -> void:
	state["parts"][CORE]["shed"] = true
	var events := _run(_scan())
	assert_eq(events[0]["data"]["reason"], "core_offline")


func test_an_atomic_operation_refuses_orders() -> void:
	state["units"][SHIP]["op"]["type"] = "docking"
	var events := _run(_scan())
	assert_eq(events[0]["data"]["reason"], "busy_docking")


func test_a_new_order_replaces_the_old_one() -> void:
	sim.submit(_scan())
	sim.step()
	var first: int = sim.view()["units"][SHIP]["task"]
	sim.take_events()
	var events := _run(_scan())
	assert_eq(_types(events), ["task_cancelled", "task_started"])
	assert_eq(events[0]["data"], { "task": first, "reason": "player_order" })
	var second: int = sim.view()["units"][SHIP]["task"]
	assert_ne(second, first)
	assert_eq(sim.view()["tasks"].size(), 1)
	assert_eq(sim.view()["units"][SHIP]["op"]["start_tick"], 2, "the new order runs in full")


func test_a_rejected_order_leaves_the_task_alone() -> void:
	sim.submit(_scan())
	sim.step()
	var task: int = sim.view()["units"][SHIP]["task"]
	sim.take_events()
	var bad := { "type": "scan", "unit": SHIP, "args": { "target": OTHER_ROCK } }
	assert_eq(_types(_run(bad)), ["command_rejected"])
	assert_eq(sim.view()["units"][SHIP]["task"], task)
	assert_eq(sim.view()["units"][SHIP]["op"]["start_tick"], 1)


func test_stop_cancels_the_task() -> void:
	sim.submit(_scan())
	sim.step()
	var task: int = sim.view()["units"][SHIP]["task"]
	sim.take_events()
	var events := _run(_stop())
	assert_eq(_types(events), ["task_cancelled"])
	assert_eq(events[0]["data"], { "task": task, "reason": "player_stop" })
	_assert_idle()


func test_stop_with_nothing_running_does_nothing() -> void:
	assert_eq(_run(_stop()), [] as Array[Dictionary])


func test_stop_needs_no_core() -> void:
	state["units"][SHIP]["core"] = 0
	assert_true(sim.check(_stop())["ok"])


func test_a_module_fault_ends_an_order() -> void:
	sim.submit(_scan())
	sim.step()
	sim.take_events()
	state["parts"][LIDAR]["fault"] = "test_fault"
	sim.step()
	assert_eq(sim.take_events()[0]["data"]["reason"], "module_fault")
	_assert_idle()


func test_lost_power_ends_an_order() -> void:
	sim.submit(_scan())
	sim.step()
	sim.take_events()
	state["parts"][LIDAR]["shed"] = true
	sim.step()
	assert_eq(sim.take_events()[0]["data"]["reason"], "no_power")
	_assert_idle()


func test_a_part_still_held_shed_ends_a_new_order() -> void:
	state["parts"][LIDAR]["shed"] = true
	state["parts"][LIDAR]["shed_until_tick"] = 1000
	var events := _run(_scan(), 2)
	assert_eq(_types(events), ["task_started", "task_cancelled"])
	assert_eq(events[1]["data"]["reason"], "no_power")


func test_an_offline_core_ends_an_order() -> void:
	sim.submit(_scan())
	sim.step()
	sim.take_events()
	state["parts"][CORE]["fault"] = "test_fault"
	sim.step()
	assert_eq(sim.take_events()[0]["data"]["reason"], "core_offline")
	_assert_idle()


## Detaching the assigned core sets `core` to 0.
func test_losing_the_core_ends_an_order() -> void:
	sim.submit(_scan())
	sim.step()
	sim.take_events()
	state["units"][SHIP]["core"] = 0
	sim.step()
	assert_eq(sim.take_events()[0]["data"]["reason"], "no_core")
	_assert_idle()


func test_a_finished_step_stands_when_a_fault_lands_on_its_last_tick() -> void:
	sim.submit(_scan())
	sim.step(300)
	state["parts"][LIDAR]["fault"] = "test_fault"
	sim.take_events()
	sim.step()
	assert_eq(_types(sim.take_events()), ["task_finished"])


func test_a_save_holds_a_running_task() -> void:
	sim.submit(_scan())
	sim.step(10)
	var loaded := Sim.from_save(sim.to_save())
	assert_eq(loaded.view()["tasks"], sim.view()["tasks"])
	assert_eq(loaded.to_save(), sim.to_save())
