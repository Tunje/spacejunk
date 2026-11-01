extends GutTest
## Tier 2 cycles and the core commands (autonomy.md sections 2 and 5 to 8). The fixture shrinks the
## world so a lap takes about 120 ticks: the rock is close, the hold small and docking quick. The
## full-length lap is in the reference chain.

const STATION := 8
const FREE_PORT := 11
const SHIP := 23
const SHIP_CORE := 25
const ROCK := 2
const DEPOSIT := 3
const OTHER_ROCK := 4
const HOLD_G := 5000
const MINE_TICKS := 10

var sim: Sim
var state: Dictionary
var defs: Dictionary
var drone: int
var hull: int
var dock_port: int
var laser: int
var core: int


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	defs = sim._ctx.defs
	_shrink_world()
	state["deposits"][DEPOSIT]["found"] = true
	_make_first_drone()
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]


func _shrink_world() -> void:
	state["bodies"][ROCK]["pos_mm"] = [2000000, 0, 0]
	var modules: Dictionary = defs["modules"]
	modules["small_ore_container_mk1"]["capabilities"]["storage"]["ore"]["mass_g"] = HOLD_G
	modules["small_docking_port_mk1"]["capabilities"]["port"]["dock_ticks"] = 2
	modules["small_docking_port_mk1"]["capabilities"]["port"]["undock_ticks"] = 2
	defs["templates"] = defs["templates"].duplicate(true)


func _make_first_drone() -> void:
	drone = _make_drone(FREE_PORT)
	hull = state["units"][drone]["root"]
	dock_port = Units.ports(state, defs, drone)[0]
	laser = _part_of(drone, "small_mining_laser_mk1")
	core = state["units"][drone]["core"]


## A fully fitted drone with an Assisted Core assigned, docked at a station port.
func _make_drone(target_port: int) -> int:
	var id := Units.create(sim._ctx, "small_craft", "Drone", state["units"][STATION]["pos_mm"])
	var unit: Dictionary = state["units"][id]
	var root: int = unit["root"]
	_fit(id, "small_solar_panel_mk1", root, "side_a_px")
	_fit(id, "small_heat_radiator_mk1", root, "side_a_nx")
	var tank := _fit(id, "small_propellant_tank_mk1", root, "stack_bottom")
	_fit(id, "small_chemical_thruster_mk1", tank, "stack_bottom")
	_fit(id, "small_ore_container_mk1", root, "side_a_pz")
	_fit(id, "small_mining_laser_mk1", root, "side_a_nz")
	unit["core"] = _fit(id, "assisted_core", root, "core")
	unit["dock"] = { "port": Units.ports(state, defs, id)[0], "target_unit": STATION, "target_port": target_port }
	unit["at_target"] = STATION
	return id


func _fit(unit: int, def: String, parent: int, connector: String) -> int:
	var part := Units.add_part(sim._ctx, unit, def, parent, connector, "mount")
	state["parts"][parent]["children"].append(part)
	return part


func _part_of(unit: int, def: String) -> int:
	for part: int in Units.part_ids(state, unit):
		if state["parts"][part]["def"] == def:
			return part
	return 0


func _steps(unit: int = drone, target_port: int = FREE_PORT) -> Array:
	var port: int = Units.ports(state, defs, unit)[0]
	return [
		{ "type": "load_cargo", "args": { "from": STATION, "item": "propellant" } },
		{ "type": "undock", "args": {} },
		{ "type": "move_to", "args": { "target": ROCK } },
		{ "type": "start_mining", "args": { "deposit": DEPOSIT, "module": _part_of(unit, "small_mining_laser_mk1") } },
		{ "type": "move_to", "args": { "target": STATION } },
		{ "type": "dock", "args": { "port": port, "target_port": target_port } },
		{ "type": "unload_cargo", "args": { "to": STATION, "item": "hematite" } },
	]


func _set_cycle(steps: Array = _steps(), unit: int = drone) -> Dictionary:
	return { "type": "set_cycle", "unit": unit, "args": { "steps": steps } }


func _order(type: String, args: Dictionary = {}, unit: int = drone) -> Dictionary:
	return { "type": type, "unit": unit, "args": args }


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


func _find(events: Array[Dictionary], type: String) -> Dictionary:
	for event in events:
		if event["type"] == type:
			return event
	return {}


func _task() -> Dictionary:
	var view := sim.view()
	var id: int = view["units"][drone]["task"]
	return view["tasks"].get(id, {})


func _cycle_step() -> String:
	return _task()["steps"][_task()["step"]]["type"]


## Steps until a task's current step is `type`, or fails the test.
func _run_to_step(type: String, limit: int = 400) -> void:
	for i in limit:
		if not _task().is_empty() and _task()["kind"] == "cycle" and _cycle_step() == type \
				and state["units"][drone]["op"]["type"] != "idle":
			return
		sim.step()
	fail_test("never reached %s" % type)


func _run_to_blocked(limit: int = 400) -> void:
	for i in limit:
		if _task().get("state", "") == "blocked":
			return
		sim.step()
	fail_test("never blocked")


func _give_fuel(grams: int = 50000) -> void:
	Units.add_stock(state["units"][drone]["inventory"], "propellant", grams)
	state["matter_start_g"] += grams


func _assert_refused(command: Dictionary, reason: String) -> void:
	assert_eq(sim.check(command)["reason"], reason)
	sim.take_events()
	sim.submit(command)
	sim.step()
	var event := _find(sim.take_events(), "command_rejected")
	assert_eq(event.get("data", {}).get("reason", ""), reason)


func _assert_balanced() -> void:
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
	assert_eq(ledger["violations"], PackedStringArray())


func test_a_cycle_runs_laps_with_no_further_commands() -> void:
	sim.submit(_set_cycle())
	var laps := 0
	for i in 1000:
		sim.step()
		var event := _find(sim.take_events(), "task_cycle_done")
		if not event.is_empty():
			laps = event["data"]["cycle"]
			if laps == 3:
				break
	assert_eq(laps, 3)
	assert_eq(state["units"][STATION]["inventory"]["hematite"], HOLD_G * 3)
	assert_eq(state["units"][drone]["inventory"].get("hematite", 0), 0)
	assert_eq(_task()["cycle"], 3)
	assert_eq(sim.view()["units"][drone]["last_cycle"], _steps())
	_assert_balanced()


func test_the_next_lap_starts_on_the_tick_the_last_ends() -> void:
	sim.submit(_set_cycle())
	for i in 1000:
		sim.step()
		if not _find(sim.take_events(), "task_cycle_done").is_empty():
			break
	assert_eq(sim.view()["units"][drone]["op"]["type"], "loading")
	assert_eq(_task()["step"], 0)


func test_a_cycle_needs_an_assisted_core() -> void:
	var ship_steps := [
		{ "type": "move_to", "args": { "target": ROCK } },
		{ "type": "move_to", "args": { "target": OTHER_ROCK } },
	]
	_assert_refused(_set_cycle(ship_steps, SHIP), "tier_too_low")


func test_a_cycle_needs_a_core() -> void:
	state["units"][drone]["core"] = 0
	_assert_refused(_set_cycle(), "no_core")


func test_bad_cycles_are_refused_with_the_failing_step() -> void:
	var one := [_steps()[2]]
	assert_eq(sim.check(_set_cycle(one))["detail"], { "step": 0 })
	var no_move := [_steps()[0], _steps()[6]]
	assert_eq(sim.check(_set_cycle(no_move))["reason"], "bad_cycle")
	var scanning := _steps()
	scanning[3] = { "type": "scan", "args": { "target": ROCK } }
	assert_eq(sim.check(_set_cycle(scanning))["detail"], { "step": 3 })
	var hidden := _steps()
	hidden[3]["args"]["deposit"] = 5
	assert_eq(sim.check(_set_cycle(hidden))["detail"], { "step": 3 })
	var too_long: Array = []
	too_long.resize(17)
	too_long.fill(_steps()[2])
	assert_eq(sim.check(_set_cycle(too_long))["reason"], "bad_cycle")


func test_a_cycle_that_does_not_close_is_refused() -> void:
	var open := _steps()
	open.remove_at(5)
	var result := sim.check(_set_cycle(open))
	assert_eq(result["reason"], "bad_cycle")
	assert_eq(result["detail"], { "step": 5 }, "unloading with no dock")
	var wrong_rock := _steps()
	wrong_rock[2]["args"]["target"] = OTHER_ROCK
	assert_eq(sim.check(_set_cycle(wrong_rock))["detail"], { "step": 3 })


func test_a_cycle_can_be_given_from_anywhere() -> void:
	state["units"][drone]["dock"] = {}
	state["units"][drone]["at_target"] = OTHER_ROCK
	_give_fuel()
	sim.submit(_set_cycle())
	sim.step()
	assert_eq(_task()["step"], 4, "walks back past step 0 to the move home")
	assert_eq(_cycle_step(), "move_to")


func test_assign_core_sets_the_tier() -> void:
	sim.submit(_order("assign_core", { "core": SHIP_CORE }, SHIP))
	sim.step()
	assert_eq(sim.view()["units"][SHIP]["core_tier"], 1)


func test_assign_core_needs_a_core_on_this_unit() -> void:
	_assert_refused(_order("assign_core", { "core": SHIP_CORE }), "unknown_part")
	_assert_refused(_order("assign_core", { "core": hull }), "unknown_part")
	_assert_refused(_order("assign_core", { "core": "x" }), "malformed_command")


func test_clearing_the_core_cancels_every_task() -> void:
	sim.submit(_set_cycle())
	sim.step()
	sim.take_events()
	sim.submit(_order("assign_core", { "core": 0 }))
	sim.step()
	var event := _find(sim.take_events(), "task_cancelled")
	assert_eq(event["data"]["reason"], "no_core")
	assert_eq(sim.view()["units"][drone]["core_tier"], 0)
	assert_eq(sim.view()["tasks"].size(), 0)


func test_a_detached_core_cancels_a_cycle_at_the_next_phase_two() -> void:
	sim.submit(_set_cycle())
	sim.step()
	state["units"][drone]["core"] = 0
	sim.step()
	assert_eq(sim.view()["tasks"].size(), 0)


func test_a_lower_tier_core_cancels_a_cycle_but_not_an_order() -> void:
	var second := _fit(drone, "basic_core", hull, "side_b_nx")
	sim.submit(_set_cycle())
	sim.step()
	sim.take_events()
	sim.submit(_order("assign_core", { "core": second }))
	sim.step()
	assert_eq(_find(sim.take_events(), "task_cancelled")["data"]["reason"], "tier_too_low")
	sim.submit(_order("undock"))
	sim.step()
	sim.submit(_order("assign_core", { "core": core }))
	sim.step()
	assert_eq(_task()["kind"], "order", "an order survives a core change")


func test_a_module_fault_holds_the_step_and_resumes_it() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	sim.step(3)
	var mined: int = state["units"][drone]["inventory"].get("hematite", 0)
	assert_gt(mined, 0)
	sim.take_events()
	state["parts"][laser]["fault"] = "test_fault"
	sim.step(4)
	assert_eq(_task()["state"], "blocked")
	assert_eq(_task()["reason"], "module_fault")
	assert_true(_task()["hold"], "the operation stays in place")
	assert_eq(state["units"][drone]["op"]["type"], "mining")
	assert_eq(state["units"][drone]["inventory"]["hematite"], mined, "no work while held")
	assert_eq(_types(sim.take_events()).count("task_blocked"), 1, "reported once")

	state["parts"][laser]["fault"] = ""
	sim.step()
	var resumed := _find(sim.take_events(), "task_resumed")
	assert_eq(resumed["data"]["reason"], "module_fault")
	assert_eq(_task()["state"], "running")
	assert_eq(_cycle_step(), "start_mining", "the same step")
	assert_gt(state["units"][drone]["inventory"]["hematite"], mined)


func test_lost_power_holds_the_step() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	state["parts"][laser]["shed"] = true
	state["parts"][laser]["shed_until_tick"] = sim.current_tick() + 3
	sim.step()
	assert_eq(_task()["reason"], "no_power")
	assert_eq(state["units"][drone]["op"]["type"], "mining")
	sim.step(4)
	assert_eq(_task()["state"], "running")


func test_an_offline_core_holds_the_step() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	state["parts"][core]["fault"] = "test_fault"
	sim.step()
	assert_eq(_task()["reason"], "core_offline")
	state["parts"][core]["fault"] = ""
	sim.step()
	assert_eq(_task()["state"], "running")


func test_a_paid_trip_ignores_an_offline_core() -> void:
	sim.submit(_set_cycle())
	_run_to_step("move_to")
	sim.step(2)
	state["parts"][core]["fault"] = "test_fault"
	sim.step(2)
	assert_eq(_task()["state"], "running", "only the player interrupts a paid trip")
	assert_false(state["units"][drone]["route"].is_empty())


func test_an_order_ignores_an_offline_core_while_moving() -> void:
	state["units"][SHIP]["dock"] = {}
	sim.submit(_order("move_to", { "target": ROCK }, SHIP))
	sim.step(2)
	state["parts"][SHIP_CORE]["fault"] = "test_fault"
	sim.step(2)
	assert_ne(sim.view()["units"][SHIP]["task"], 0)
	assert_eq(sim.view()["units"][SHIP]["op"]["type"], "moving")


func test_removing_the_core_still_stops_a_paid_trip() -> void:
	sim.submit(_set_cycle())
	_run_to_step("move_to")
	sim.step(2)
	state["units"][drone]["core"] = 0
	sim.step()
	assert_eq(sim.view()["tasks"].size(), 0)
	assert_true(state["units"][drone]["route"].is_empty(), "the unit halts")


func test_a_full_destination_blocks_the_unload_until_room_appears() -> void:
	sim.submit(_set_cycle())
	_run_to_step("unload_cargo")
	defs["modules"]["ore_storage_mk1"]["capabilities"]["storage"]["ore"]["mass_g"] = 1000
	sim._ctx.index.clear()
	_run_to_blocked()
	assert_eq(_task()["reason"], "cargo_full")
	var held: int = state["units"][drone]["inventory"]["hematite"]
	assert_gt(held, 0)
	defs["modules"]["ore_storage_mk1"]["capabilities"]["storage"]["ore"]["mass_g"] = 50000000
	sim._ctx.index.clear()
	sim.step(2)
	assert_eq(_task()["state"], "running")
	sim.step(5)
	assert_lt(state["units"][drone]["inventory"].get("hematite", 0), held)


func test_mining_an_emptied_deposit_ends_the_step_and_hauls_the_load() -> void:
	state["matter_start_g"] -= state["deposits"][DEPOSIT]["remaining_g"] - 2000
	state["deposits"][DEPOSIT]["remaining_g"] = 2000
	sim.submit(_set_cycle())
	_run_to_blocked()
	assert_eq(_task()["reason"], "deposit_exhausted")
	assert_eq(_task()["step"], 0, "blocked by the lap gate, at home")
	assert_eq(state["units"][STATION]["inventory"]["hematite"], 2000)
	assert_false(state["units"][drone]["dock"].is_empty())
	var fuel: int = state["units"][drone]["inventory"]["propellant"]
	sim.step(50)
	assert_eq(state["units"][drone]["inventory"]["propellant"], fuel, "no trip wasted")


func test_a_cycle_with_an_empty_deposit_blocks_at_once() -> void:
	state["matter_start_g"] -= state["deposits"][DEPOSIT]["remaining_g"]
	state["deposits"][DEPOSIT]["remaining_g"] = 0
	sim.submit(_set_cycle())
	sim.step()
	assert_eq(_task()["reason"], "deposit_exhausted")


func test_no_propellant_blocks_until_there_is_enough() -> void:
	var steps := _steps()
	steps.remove_at(0)
	sim.submit(_set_cycle(steps))
	sim.step(3)
	assert_eq(_task()["state"], "blocked")
	assert_eq(_task()["reason"], "no_propellant")
	assert_eq(_task()["hold"], false)
	assert_eq(_cycle_step(), "move_to")
	sim.take_events()
	Units.add_stock(state["units"][drone]["inventory"], "propellant", 50000)
	state["matter_start_g"] += 50000
	sim.step()
	assert_eq(_find(sim.take_events(), "task_resumed")["data"]["reason"], "no_propellant")
	assert_false(state["units"][drone]["route"].is_empty())


func test_a_core_is_not_a_laser() -> void:
	var steps := _steps()
	steps[3]["args"]["module"] = core
	assert_eq(sim.check(_set_cycle(steps))["reason"], "bad_cycle")


func test_a_detached_part_blocks_for_good() -> void:
	sim.submit(_set_cycle())
	sim.step()
	sim.submit(_order("detach_part", { "part": laser, "to": STATION }))
	_run_to_blocked()
	assert_eq(_task()["reason"], "module_missing")
	sim.step(5)
	assert_eq(_task()["reason"], "module_missing", "only a new cycle clears it")


func test_stop_ends_a_cycle_and_keeps_last_cycle() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	sim.take_events()
	sim.submit(_order("stop"))
	sim.step()
	var events := sim.take_events()
	assert_eq(_find(events, "task_cancelled")["data"]["reason"], "player_stop")
	assert_eq(sim.view()["units"][drone]["last_cycle"], _steps())
	assert_eq(sim.view()["tasks"].size(), 0)
	assert_eq(sim.view()["units"][drone]["op"]["type"], "idle")


func test_an_order_suspends_a_cycle_and_it_resumes_afterwards() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	var cycle_id: int = _task()["id"]
	sim.take_events()
	sim.submit(_order("move_to", { "target": ROCK }))
	sim.step()
	var events := sim.take_events()
	assert_eq(_find(events, "task_blocked")["data"], { "task": cycle_id, "reason": "player_order" })
	var view := sim.view()
	assert_eq(view["units"][drone]["cycle_task"], cycle_id)
	assert_ne(view["units"][drone]["task"], cycle_id)
	assert_eq(view["tasks"].size(), 2)
	assert_eq(view["tasks"][cycle_id]["state"], "blocked")
	assert_false(view["tasks"][cycle_id]["hold"], "the cycle gave up its operation")

	sim.step(2)
	events = sim.take_events()
	assert_eq(_find(events, "task_resumed")["data"], { "task": cycle_id, "reason": "player_order" })
	assert_eq(_task()["id"], cycle_id)
	assert_eq(sim.view()["units"][drone]["cycle_task"], 0)
	assert_eq(sim.view()["tasks"].size(), 1)
	assert_eq(_cycle_step(), "start_mining")


func test_a_failed_order_brings_the_cycle_back_to_meet_the_same_problem() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	var cycle_id: int = _task()["id"]
	sim.submit(_order("start_mining", { "deposit": DEPOSIT, "module": laser }))
	sim.step()
	assert_eq(_task()["kind"], "order")
	state["parts"][laser]["fault"] = "test_fault"
	sim.take_events()
	sim.step()
	var events := sim.take_events()
	assert_eq(_find(events, "task_cancelled")["data"]["reason"], "module_fault")
	assert_eq(_task()["id"], cycle_id)
	assert_eq(_task()["state"], "blocked")
	assert_eq(_task()["reason"], "module_fault")


func test_stop_ends_an_override_and_its_cycle() -> void:
	sim.submit(_set_cycle())
	_run_to_step("move_to")
	sim.step()
	var cycle_id: int = _task()["id"]
	sim.take_events()
	sim.submit(_order("move_to", { "target": OTHER_ROCK }))
	sim.step(2)
	assert_eq(sim.view()["units"][drone]["cycle_task"], cycle_id, "overridden")
	assert_eq(state["units"][drone]["route"]["target"], OTHER_ROCK)
	sim.take_events()
	sim.submit(_order("stop"))
	sim.step()
	assert_eq(sim.view()["tasks"].size(), 0, "stop ends both")
	var cancelled := sim.take_events().filter(func(event: Dictionary) -> bool:
		return event["type"] == "task_cancelled")
	assert_eq(cancelled.size(), 2)
	assert_eq(cancelled[0]["data"]["task"], cycle_id, "in ascending task ID")


func test_a_rejected_order_leaves_the_cycle_alone() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	var task := _task()
	sim.submit(_order("undock"))
	sim.step()
	assert_eq(_task()["id"], task["id"])
	assert_eq(sim.view()["units"][drone]["cycle_task"], 0)
	assert_eq(state["units"][drone]["op"]["type"], "mining")


func _override_with_move_then_finish(target: int) -> void:
	sim.submit(_order("move_to", { "target": target }))
	for i in 400:
		sim.step()
		if sim.view()["units"][drone]["cycle_task"] == 0 and sim.current_tick() > 1 \
				and _task().get("kind", "") == "cycle":
			return
	fail_test("the override never ended")


func test_re_entry_stays_at_the_same_body() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	_override_with_move_then_finish(ROCK)
	assert_eq(_cycle_step(), "start_mining")


func test_re_entry_from_open_space_goes_back_to_the_move() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	sim.submit(_order("move_to", { "target": STATION }))
	sim.step(3)
	sim.submit(_order("stop"))
	sim.step()
	sim.submit(_set_cycle())
	sim.step()
	assert_eq(_cycle_step(), "move_to", "the last step it is placed for")
	assert_eq(_task()["step"], 4, "walks back past step 0 to the move home")


func test_re_entry_near_the_station_docks() -> void:
	sim.submit(_set_cycle())
	_run_to_step("unload_cargo")
	sim.submit(_order("undock"))
	sim.step(4)
	assert_eq(_cycle_step(), "dock")


func test_re_entry_when_docked_goes_to_undock() -> void:
	sim.submit(_set_cycle())
	sim.step()
	var task: Dictionary = state["tasks"][state["units"][drone]["task"]]
	task["step"] = 2
	task["enter"] = true
	state["units"][drone]["op"] = { "type": "idle", "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 }
	state["units"][drone].erase(TransferStep.OPEN_KEY)
	sim.step()
	assert_eq(_cycle_step(), "undock")


func test_no_safe_step_blocks_until_placement_allows() -> void:
	var moves := [
		{ "type": "move_to", "args": { "target": ROCK } },
		{ "type": "start_mining", "args": { "deposit": DEPOSIT, "module": laser } },
	]
	sim.submit(_set_cycle(moves))
	sim.step()
	assert_eq(_task()["reason"], "no_safe_step", "docked, and no step undocks")
	state["units"][drone]["dock"] = {}
	Units.add_stock(state["units"][drone]["inventory"], "propellant", 50000)
	state["matter_start_g"] += 50000
	sim.step()
	assert_eq(_task()["state"], "running")


func test_three_drones_on_one_port_are_served_in_arrival_order() -> void:
	var second := _make_drone(FREE_PORT)
	var third := _make_drone(FREE_PORT)
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	for id: int in [drone, second, third]:
		var unit: Dictionary = state["units"][id]
		unit["dock"] = {}
		unit["at_target"] = STATION
	var waiters := [third, second]
	state["units"][drone]["dock"] = { "port": dock_port, "target_unit": STATION, "target_port": FREE_PORT }
	for id: int in waiters:
		var steps := _steps(id)
		sim.submit(_set_cycle(steps, id))
		sim.step()
	var second_task: int = state["units"][second]["task"]
	var third_task: int = state["units"][third]["task"]
	assert_eq(state["tasks"][third_task]["reason"], "port_busy")
	assert_eq(state["tasks"][second_task]["reason"], "port_busy")
	assert_lt(state["tasks"][third_task]["since_tick"], state["tasks"][second_task]["since_tick"])
	state["units"][drone]["dock"] = {}
	sim.step(1)
	assert_eq(state["tasks"][third_task]["state"], "running", "first to wait, though its ID is higher")
	assert_eq(state["tasks"][second_task]["reason"], "port_busy")


func test_a_build_yields_a_port_to_an_earlier_waiter() -> void:
	assert_true(PortQueue.is_free_for_job(sim._ctx, FREE_PORT, 5, 99), "no waiters")
	var second := _make_drone(FREE_PORT)
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	state["units"][second]["dock"] = {}
	sim.submit(_set_cycle(_steps(second), second))
	sim.step()
	var tick: int = state["tasks"][state["units"][second]["task"]]["since_tick"]
	assert_false(PortQueue.is_free_for_job(sim._ctx, FREE_PORT, tick + 1, 99), "the task was first")
	assert_true(PortQueue.is_free_for_job(sim._ctx, FREE_PORT, tick - 1, 99), "the job was first")


func test_a_save_while_blocked_resumes_identically() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	defs = sim._ctx.defs
	state["deposits"][DEPOSIT]["found"] = true
	_make_first_drone()
	state["deposits"][DEPOSIT]["remaining_g"] = 0
	sim.submit(_set_cycle())
	sim.step(5)
	assert_eq(_task()["reason"], "deposit_exhausted")
	var loaded := Sim.from_save(sim.to_save())
	assert_not_null(loaded)
	assert_eq(loaded.to_save(), sim.to_save(), "round trip")
	assert_eq(loaded.view()["tasks"], sim.view()["tasks"])
	sim.step(5)
	loaded.step(5)
	assert_eq(loaded.state_hash(), sim.state_hash())


## Saves now, loads it with the same small-world definitions, applies `change` to both games, and
## requires both to run on identically. The state keeps the real data hash, so the load is accepted.
func _assert_load_resumes(change: Callable = func(_game: Sim) -> void: pass, ticks: int = 40) -> void:
	sim.take_events()
	var loaded := Sim.from_save(sim.to_save())
	assert_not_null(loaded)
	loaded._ctx.defs = defs
	assert_eq(loaded.to_save(), sim.to_save(), "round trip")
	change.call(sim)
	change.call(loaded)
	sim.step(ticks)
	loaded.step(ticks)
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_eq(loaded.take_events(), sim.take_events(), "the same events")


func _set_fault(game: Sim, part: int, fault: String) -> void:
	game._state["parts"][part]["fault"] = fault


## The unit docked at the free port.
func _occupant(game: Sim) -> int:
	var units: Dictionary = game._state["units"]
	for id: int in units:
		if units[id]["dock"].get("target_port", 0) == FREE_PORT:
			return id
	return 0


func test_a_load_resumes_a_step_held_by_a_module_fault() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	sim.step(2)
	_set_fault(sim, laser, "test_fault")
	sim.step(2)
	assert_true(_task()["hold"])
	_assert_load_resumes(func(game: Sim) -> void: _set_fault(game, laser, ""))


func test_a_load_resumes_a_step_held_by_lost_power() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	state["parts"][laser]["shed"] = true
	state["parts"][laser]["shed_until_tick"] = sim.current_tick() + 5
	sim.step()
	assert_eq(_task()["reason"], "no_power")
	_assert_load_resumes()


func test_a_load_resumes_a_step_held_by_an_offline_core() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	_set_fault(sim, core, "test_fault")
	sim.step()
	assert_eq(_task()["reason"], "core_offline")
	_assert_load_resumes(func(game: Sim) -> void: _set_fault(game, core, ""))


func test_a_load_resumes_an_unload_blocked_by_a_full_destination() -> void:
	sim.submit(_set_cycle())
	_run_to_step("unload_cargo")
	var storage: Dictionary = defs["modules"]["ore_storage_mk1"]["capabilities"]["storage"]["ore"]
	storage["mass_g"] = 1000
	sim._ctx.index.clear()
	_run_to_blocked()
	assert_eq(_task()["reason"], "cargo_full")
	storage["mass_g"] = 50000000
	_assert_load_resumes(func(game: Sim) -> void: game._ctx.index.clear())


func test_a_load_resumes_a_cycle_waiting_for_a_port() -> void:
	var second := _make_drone(FREE_PORT)
	state["units"][second]["dock"] = {}
	Units.add_stock(state["units"][second]["inventory"], "propellant", 50000)
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	drone = second
	sim.submit(_set_cycle(_steps(second), second))
	sim.step()
	assert_eq(_task()["reason"], "port_busy")
	_assert_load_resumes(func(game: Sim) -> void: game._state["units"][_occupant(game)]["dock"] = {})


func test_a_load_resumes_a_cycle_out_of_propellant() -> void:
	var steps := _steps()
	steps.remove_at(0)
	sim.submit(_set_cycle(steps))
	sim.step(3)
	assert_eq(_task()["reason"], "no_propellant")
	_assert_load_resumes(func(game: Sim) -> void:
		Units.add_stock(game._state["units"][drone]["inventory"], "propellant", 50000)
		game._state["matter_start_g"] += 50000)


func test_a_load_keeps_a_cycle_with_a_missing_part_blocked() -> void:
	sim.submit(_set_cycle())
	sim.step()
	sim.submit(_order("detach_part", { "part": laser, "to": STATION }))
	_run_to_blocked()
	assert_eq(_task()["reason"], "module_missing")
	_assert_load_resumes()


func test_a_load_resumes_a_cycle_with_no_safe_step() -> void:
	var steps := [
		{ "type": "move_to", "args": { "target": ROCK } },
		{ "type": "start_mining", "args": { "deposit": DEPOSIT, "module": laser } },
	]
	sim.submit(_set_cycle(steps))
	sim.step()
	assert_eq(_task()["reason"], "no_safe_step")
	_assert_load_resumes(func(game: Sim) -> void:
		game._state["units"][drone]["dock"] = {}
		Units.add_stock(game._state["units"][drone]["inventory"], "propellant", 50000)
		game._state["matter_start_g"] += 50000)


func test_a_load_resumes_a_cycle_suspended_by_an_order() -> void:
	sim.submit(_set_cycle())
	_run_to_step("start_mining")
	sim.submit(_order("move_to", { "target": STATION }))
	sim.step(3)
	assert_ne(sim.view()["units"][drone]["cycle_task"], 0)
	_assert_load_resumes(func(_game: Sim) -> void: pass, 120)


func test_a_load_finishes_an_atomic_operation_left_by_stop() -> void:
	sim.submit(_set_cycle())
	_run_to_step("undock")
	sim.submit(_order("stop"))
	sim.step()
	assert_eq(sim.view()["units"][drone]["op"]["type"], "undocking")
	_assert_load_resumes()
	assert_eq(sim.view()["units"][drone]["op"]["type"], "idle")
