extends GutTest
## The power network of networks.md sections 2 and 3, on the reference ship and station.
## The ship makes 120 kW and has a 2 kW core. Its two batteries hold 720 MJ and give up to 300 kW.

const STATION := 8
const SHIP := 23
const CORE := 25
const THRUSTER := 27
const PANEL_A := 29
const PANEL_B := 30
const BATTERY_A := 31
const BATTERY_B := 32
const LASER := 35
const LIDAR := 36
const REFINERY := 13
const HOLD_TICKS := PowerSystem.SHED_HOLD_SECONDS * Sim.TICKS_PER_SECOND

var sim: Sim
var state: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state


func _run_op(part: int, op_type: String = "mining") -> void:
	state["units"][SHIP]["op"] = { "type": op_type, "target": 3, "part": part, "start_tick": 0, "end_tick": 0 }


func _set_stored(a_j: int, b_j: int = 0) -> void:
	state["parts"][BATTERY_A]["stored_j"] = a_j
	state["parts"][BATTERY_B]["stored_j"] = b_j


func _flow(unit: int = SHIP) -> Dictionary:
	return sim.ledger()["energy"][unit]


func _assert_balanced(flow: Dictionary) -> void:
	assert_eq(flow["generated_w"] + flow["discharged_w"],
		flow["consumed_w"] + flow["charged_w"] + flow["curtailed_w"], "power balances")
	for part_id: int in flow["batteries"]:
		var battery: Dictionary = flow["batteries"][part_id]
		assert_eq(battery["charged_w"], battery["stored_w"] + battery["conversion_loss_w"])


func _event_types() -> Array:
	return sim.take_events().map(func(event: Dictionary) -> String: return event["type"])


func _part_state(part: int) -> String:
	var result := [""]
	var walk := func(node: Dictionary, again: Callable) -> void:
		if node["id"] == part:
			result[0] = node["state"]
		for child: Dictionary in node["children"]:
			again.call(child, again)
	walk.call(sim.view()["units"][SHIP]["parts"], walk)
	return result[0]


func test_an_idle_unit_runs_only_its_core_and_curtails_the_rest() -> void:
	sim.step()
	var flow := _flow()
	assert_eq(flow["generated_w"], 120_000)
	assert_eq(flow["consumed_w"], 2000)
	assert_eq(flow["charged_w"], 0)
	assert_eq(flow["curtailed_w"], 118_000)
	assert_eq(flow["ran"], [CORE])
	_assert_balanced(flow)


func test_idle_modules_demand_nothing() -> void:
	sim.step()
	assert_eq(state["parts"][LASER]["draw_w"], 0)
	assert_eq(state["parts"][LIDAR]["draw_w"], 0)
	assert_eq(sim.view()["units"][SHIP]["power"]["demand_w"], 2000)


func test_always_on_modules_and_the_core_draw_on_a_station() -> void:
	sim.step()
	var flow := _flow(STATION)
	assert_eq(flow["consumed_w"], 7000)
	assert_eq(flow["ran"], [9, 10])


func test_a_fitted_but_unassigned_core_demands_nothing() -> void:
	state["units"][SHIP]["core"] = 0
	sim.step()
	assert_eq(_flow()["consumed_w"], 0)


func test_an_operation_draws_the_module_power() -> void:
	_run_op(LASER)
	sim.step()
	assert_eq(_flow()["consumed_w"], 152_000)
	assert_eq(state["parts"][LASER]["draw_w"], 150_000)


func test_a_thruster_is_never_a_load() -> void:
	_run_op(THRUSTER, "moving")
	sim.step()
	assert_eq(_flow()["consumed_w"], 2000)


func test_a_held_operation_keeps_its_demand() -> void:
	_run_op(LASER)
	_set_stored(0)
	sim.step(2)
	assert_eq(sim.view()["units"][SHIP]["power"]["demand_w"], 152_000)
	assert_eq(_part_state(LASER), "shed")


func test_a_running_job_draws_the_recipe_power() -> void:
	state["jobs"][40] = JobFixture.record(state, 14, "wiring", "running")
	sim.step()
	assert_eq(_flow(STATION)["consumed_w"], 57_000)
	assert_eq(state["parts"][14]["draw_w"], 50_000)


func test_a_waiting_job_draws_nothing() -> void:
	state["jobs"][40] = JobFixture.record(state, 14, "wiring", "waiting", "missing_inputs")
	sim.step()
	assert_eq(_flow(STATION)["consumed_w"], 7000)


func test_a_job_paused_by_a_fault_draws_nothing() -> void:
	state["jobs"][40] = JobFixture.record(state, 13, "refine_hematite", "paused", "module_fault")
	state["parts"][REFINERY]["fault"] = "test_fault"
	sim.step()
	assert_eq(_flow(STATION)["consumed_w"], 7000)


func test_a_job_paused_by_shedding_stays_a_load() -> void:
	state["jobs"][40] = JobFixture.record(state, 13, "refine_hematite", "paused", "no_power")
	sim.step()
	assert_eq(_flow(STATION)["consumed_w"], 207_000)


func test_a_shortfall_draws_on_batteries_in_part_order() -> void:
	_run_op(LASER)
	sim.step()
	var flow := _flow()
	assert_eq(flow["discharged_w"], 32_000)
	assert_eq(flow["batteries"][BATTERY_A]["discharged_w"], 32_000)
	assert_eq(flow["batteries"][BATTERY_B]["discharged_w"], 0)
	assert_eq(state["parts"][BATTERY_A]["stored_j"], 360_000_000 - 3200)
	_assert_balanced(flow)


func test_a_large_shortfall_spreads_to_the_next_battery() -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["solar_panel_mk1"]["capabilities"]["generate"]["power_w"] = 0
	sim._ctx.defs["modules"]["mining_laser_mk1"]["power_w"] = 180_000
	_run_op(LASER)
	sim.step()
	var flow := _flow()
	assert_eq(flow["batteries"][BATTERY_A]["discharged_w"], 150_000)
	assert_eq(flow["batteries"][BATTERY_B]["discharged_w"], 32_000)
	_assert_balanced(flow)


func test_max_discharge_limits_stored_energy() -> void:
	_run_op(LASER)
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["mining_laser_mk1"]["power_w"] = 500_000
	sim.step()
	assert_eq(_part_state(LASER), "shed", "120 kW + 300 kW cannot carry 502 kW")
	assert_eq(_flow()["discharged_w"], 0)


func test_discharge_cap_is_limited_by_stored_energy() -> void:
	_set_stored(100)
	sim.step()
	assert_eq(_flow()["batteries"][BATTERY_A]["discharge_cap_w"], 1000)


func test_surplus_charges_batteries_with_losses() -> void:
	_set_stored(0)
	sim.step()
	var flow := _flow()
	assert_eq(flow["batteries"][BATTERY_A]["charged_w"], 60_000)
	assert_eq(flow["batteries"][BATTERY_A]["stored_w"], 54_000)
	assert_eq(flow["batteries"][BATTERY_A]["conversion_loss_w"], 6000)
	assert_eq(flow["batteries"][BATTERY_B]["charged_w"], 58_000)
	assert_eq(flow["curtailed_w"], 0)
	assert_eq(state["parts"][BATTERY_A]["stored_j"], 5400)
	assert_eq(state["parts"][BATTERY_B]["stored_j"], 5220)
	_assert_balanced(flow)


func test_charging_stops_exactly_at_capacity() -> void:
	_set_stored(360_000_000 - 7, 360_000_000)
	for i in 20:
		sim.step()
		assert_lte(state["parts"][BATTERY_A]["stored_j"], 360_000_000)
		_assert_balanced(_flow())
	assert_gte(state["parts"][BATTERY_A]["stored_j"], 360_000_000 - 1)


func test_stored_energy_tracks_the_exact_rate_over_time() -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["solar_panel_mk1"]["capabilities"]["generate"]["power_w"] = 1003
	sim._ctx.defs["modules"]["basic_core"]["power_w"] = 0
	_set_stored(0, 360_000_000)
	var stored_w_ticks := 0
	for i in 1000:
		sim.step()
		stored_w_ticks += _flow()["batteries"][BATTERY_A]["stored_w"]
	var remainder: int = state["parts"][BATTERY_A]["charge_remainder"]
	assert_eq(state["parts"][BATTERY_A]["stored_j"] * Sim.TICKS_PER_SECOND + remainder, stored_w_ticks)


func test_a_shed_battery_never_goes_below_zero() -> void:
	_set_stored(50)
	_run_op(LASER)
	for i in 30:
		sim.step()
		assert_gte(state["parts"][BATTERY_A]["stored_j"], 0)
		_assert_balanced(_flow())


func test_a_new_battery_starts_empty() -> void:
	Units.add_stock(state["units"][STATION]["inventory"], "battery_bank_mk1", 300_000)
	state["matter_start_g"] += 300_000
	sim.submit({ "type": "attach_part", "unit": SHIP, "args": {
		"item": "battery_bank_mk1", "from": STATION, "parent_part": 24,
		"parent_connector": "side_c_pz", "part_connector": "mount" } })
	sim.step()
	var id: int = sim.take_events()[0]["data"]["part"]
	assert_eq(state["parts"][id]["stored_j"], 5400, "one tick of charging, from empty")


func test_lowest_priority_sheds_first() -> void:
	_set_stored(0)
	_run_op(LASER)
	sim.step()
	assert_eq(_part_state(LASER), "shed")
	assert_eq(_part_state(CORE), "on")
	assert_eq(_flow()["ran"], [CORE])
	assert_eq(_flow()["charged_w"], 118_000)


func test_shedding_fires_once_and_restoring_fires_once() -> void:
	_set_stored(0)
	_run_op(LASER)
	sim.step()
	var first := sim.take_events()
	assert_eq(first.size(), 1)
	assert_eq(first[0]["type"], "power_shed")
	assert_eq(first[0]["data"], { "module": LASER, "reason": "no_power" })
	sim.step(5)
	assert_eq(_event_types(), [])


func test_a_shed_load_holds_for_five_seconds_then_restores() -> void:
	_set_stored(0)
	_run_op(LASER)
	sim.step()
	_set_stored(360_000_000, 360_000_000)
	sim.take_events()
	sim.step(HOLD_TICKS - 1)
	assert_eq(_part_state(LASER), "shed", "still held on the last tick of the hold")
	assert_eq(_event_types(), [])
	sim.step()
	assert_eq(_part_state(LASER), "on")
	assert_eq(_event_types(), ["power_restored"])


func test_higher_id_sheds_first_within_a_class() -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	var modules: Dictionary = sim._ctx.defs["modules"]
	modules["lidar_mk1"]["power_w"] = 100_000
	modules["mining_laser_mk1"]["power_w"] = 100_000
	_set_stored(0)
	state["units"][SHIP]["op"] = { "type": "mining", "target": 3, "part": LASER, "start_tick": 0, "end_tick": 0 }
	state["jobs"][40] = JobFixture.record(state, LIDAR, "wiring", "running")
	modules["lidar_mk1"]["capabilities"]["facility"] = { "type": "fabricator", "work_per_tick": 100 }
	sim._ctx.defs["recipes"]["wiring"] = { "power_w": 100_000, "work": 100 }
	sim.step()
	assert_eq(_part_state(LASER), "on")
	assert_eq(_part_state(LIDAR), "shed")


func test_a_small_load_is_readmitted_after_a_big_one_is_shed() -> void:
	_set_stored(0)
	_run_op(LASER)
	state["jobs"][40] = JobFixture.record(state, LIDAR, "wiring", "running")
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["lidar_mk1"]["capabilities"]["facility"] = { "type": "fabricator", "work_per_tick": 100 }
	sim._ctx.defs["recipes"]["wiring"] = { "power_w": 10_000, "work": 100 }
	sim.step()
	assert_eq(_part_state(LASER), "shed")
	assert_eq(_part_state(LIDAR), "on", "the small load fits once the laser is off")
	var events := sim.take_events()
	assert_eq(events.size(), 1, "the small load never flickers")


func test_an_order_during_a_hold_is_shed_at_once() -> void:
	_set_stored(0)
	_run_op(LASER)
	sim.step()
	state["units"][SHIP]["op"] = { "type": "idle", "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 }
	sim.step()
	assert_eq(_part_state(LASER), "on", "not a load, so back to on")
	var hold_end: int = state["parts"][LASER]["shed_until_tick"]
	_set_stored(360_000_000, 360_000_000)
	_run_op(LASER)
	sim.step()
	assert_eq(_part_state(LASER), "shed")
	assert_eq(state["parts"][LASER]["shed_until_tick"], hold_end, "the hold is not extended")


func test_a_faulted_part_gets_no_power_and_is_not_shed() -> void:
	_run_op(LASER)
	state["parts"][LASER]["fault"] = "test_fault"
	sim.step()
	assert_eq(_flow()["consumed_w"], 2000)
	assert_eq(_part_state(LASER), "fault")
	assert_eq(_event_types(), [])


func test_faulted_generators_and_batteries_give_nothing() -> void:
	state["parts"][PANEL_A]["fault"] = "test_fault"
	state["parts"][BATTERY_A]["fault"] = "test_fault"
	sim.step()
	var flow := _flow()
	assert_eq(flow["generated_w"], 60_000)
	assert_false(flow["batteries"].has(BATTERY_A))
	assert_eq(sim.view()["units"][SHIP]["power"]["supply_w"], 60_000)


func test_set_priority_changes_who_sheds() -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["mining_laser_mk1"]["power_w"] = 119_000
	_set_stored(0)
	_run_op(LASER)
	sim.submit({ "type": "set_priority", "unit": SHIP, "args": { "module": LASER, "priority": 20 } })
	sim.step()
	assert_eq(state["parts"][LASER]["priority"], 20)
	assert_eq(_part_state(LASER), "on")
	assert_eq(_part_state(CORE), "shed", "121 kW wanted of 120 kW, and the core now ranks lower")


func test_set_priority_is_allowed_on_a_faulted_part() -> void:
	state["parts"][LASER]["fault"] = "test_fault"
	sim.submit({ "type": "set_priority", "unit": SHIP, "args": { "module": LASER, "priority": 1 } })
	sim.step()
	assert_eq(state["parts"][LASER]["priority"], 1)
	assert_eq(_event_types(), [])


func test_set_priority_refusals() -> void:
	for args: Dictionary in [{ "module": 9999, "priority": 1 }, { "module": 13, "priority": 1 }]:
		assert_eq(sim.check({ "type": "set_priority", "unit": SHIP, "args": args })["reason"], "unknown_part")
	for args: Dictionary in [{}, { "module": LASER }, { "module": LASER, "priority": -1 }]:
		assert_eq(sim.check({ "type": "set_priority", "unit": SHIP, "args": args })["reason"], "malformed_command")


func test_the_view_shows_shed_draw_and_supply() -> void:
	_run_op(LASER)
	sim.step()
	var power: Dictionary = sim.view()["units"][SHIP]["power"]
	assert_eq(power["supply_w"], 120_000)
	assert_eq(power["demand_w"], 152_000)
	assert_eq(power["stored_j"], 720_000_000 - 3200)


func test_energy_balances_every_tick_through_competing_loads() -> void:
	_set_stored(4000)
	_run_op(LASER)
	state["jobs"][40] = JobFixture.record(state, 13, "refine_hematite", "running")
	for i in 300:
		if i == 100:
			state["parts"][PANEL_B]["fault"] = "test_fault"
		if i == 200:
			state["parts"][PANEL_B]["fault"] = ""
		sim.step()
		var ledger := sim.ledger()
		for unit: int in ledger["energy"]:
			_assert_balanced(ledger["energy"][unit])
		assert_eq(ledger["violations"], PackedStringArray())
		assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])


func test_a_save_during_a_hold_matches_an_unbroken_run() -> void:
	_set_stored(0)
	_run_op(LASER)
	var other := Sim.from_save(sim.to_save())
	sim.step(10)
	other.step(5)
	other = Sim.from_save(other.to_save())
	other.step(5)
	assert_eq(other.state_hash(), sim.state_hash())
	sim.step(HOLD_TICKS)
	other.step(HOLD_TICKS)
	assert_eq(other.state_hash(), sim.state_hash())
