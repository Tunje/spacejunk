extends GutTest
## Mining (check 2), on the reference scenario's ship at Red Rock, with real power and heat.

const SHIP := 23
const LASER := 35
const LIDAR := 36
const ROCK := 2
const DEPOSIT := 3
const OTHER_DEPOSIT := 5
const OLIVINE_DEPOSIT := 7
const DEPOSIT_G := 200000000
const FULL_HOLD_G := 2000000
const FULL_TICKS := 1000
const TICK_YIELD_G := 2000

var sim: Sim
var state: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	_place(SHIP)
	state["deposits"][DEPOSIT]["found"] = true


## Puts a unit at the rock. Travel arrives with A6.
func _place(unit: int) -> void:
	state["units"][unit]["dock"] = {}
	state["units"][unit]["at_target"] = ROCK


func _mine(unit: int = SHIP, deposit: int = DEPOSIT, module: int = LASER) -> Dictionary:
	return { "type": "start_mining", "unit": unit, "args": { "deposit": deposit, "module": module } }


func _stop() -> Dictionary:
	return { "type": "stop", "unit": SHIP, "args": {} }


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


func _first(events: Array[Dictionary], type: String) -> Dictionary:
	for event in events:
		if event["type"] == type:
			return event
	fail_test("no %s event" % type)
	return {}


func _held(unit: int = SHIP, item: String = "hematite") -> int:
	return sim.view()["units"][unit]["inventory"].get(item, 0)


## Changes the deposit's size, and the starting total with it.
func _set_deposit(grams: int) -> void:
	state["matter_start_g"] += grams - state["deposits"][DEPOSIT]["remaining_g"]
	state["deposits"][DEPOSIT]["remaining_g"] = grams


## Fills part of the hold with hematite, counted as starting matter.
func _fill_hold(grams: int) -> void:
	Units.add_stock(state["units"][SHIP]["inventory"], "hematite", grams)
	state["matter_start_g"] += grams


func _own_defs() -> Dictionary:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	return sim._ctx.defs


func _step_balanced(ticks: int) -> void:
	for i in ticks:
		sim.step()
		var ledger := sim.ledger()
		assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"], "tick %d" % sim.current_tick())
		if ledger["matter"]["total_g"] != ledger["matter"]["start_g"]:
			return
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func _assert_refused(command: Dictionary, reason: String) -> void:
	assert_eq(sim.check(command)["reason"], reason)
	sim.submit(command)
	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["command_rejected"], reason)
	assert_eq(events[0]["data"]["reason"], reason)
	assert_eq(sim.view()["tasks"].size(), 0, "no task made")


func test_mining_fills_the_hold_in_the_reference_time() -> void:
	sim.submit(_mine())
	_step_balanced(FULL_TICKS - 1)
	assert_eq(_held(), FULL_HOLD_G - TICK_YIELD_G)
	assert_eq(sim.view()["units"][SHIP]["op"]["type"], "mining")
	_step_balanced(1)
	assert_eq(_held(), FULL_HOLD_G)
	assert_eq(sim.view()["deposits"][DEPOSIT]["remaining_g"], DEPOSIT_G - FULL_HOLD_G)
	assert_eq(_types(sim.take_events()), ["task_started"], "no event until phase 2")


func test_a_full_hold_finishes_the_order_on_the_next_tick() -> void:
	sim.submit(_mine())
	sim.step(FULL_TICKS)
	sim.take_events()
	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["mining_stopped", "task_finished"])
	assert_eq(events[0]["data"], { "deposit": DEPOSIT, "grams": FULL_HOLD_G, "reason": "cargo_full" })
	assert_eq(sim.view()["units"][SHIP]["op"]["type"], "idle")


## C19: an order for an amount.
func _mine_grams(grams: Variant) -> Dictionary:
	var command := _mine()
	command["args"]["grams"] = grams
	return command


func test_an_amount_stops_exactly_on_it() -> void:
	sim.submit(_mine_grams(5_500))
	_step_balanced(3)
	assert_eq(_held(), 5_500, "two full ticks, then a third cut to the amount")
	sim.take_events()
	sim.step(5)
	var events := sim.take_events()
	assert_eq(_types(events), ["mining_stopped", "task_finished"])
	assert_eq(events[0]["data"], { "deposit": DEPOSIT, "grams": 5_500, "reason": "amount_mined" })
	assert_eq(_held(), 5_500, "nothing after the amount")
	assert_eq(state["deposits"][DEPOSIT]["remaining_g"], DEPOSIT_G - 5_500)


func test_an_amount_on_a_tick_boundary_stops_there() -> void:
	sim.submit(_mine_grams(3 * TICK_YIELD_G))
	sim.step(4)
	assert_eq(_held(), 3 * TICK_YIELD_G)
	assert_eq(_first(sim.take_events(), "mining_stopped")["data"]["reason"], "amount_mined")


func test_a_hold_that_fills_first_ends_as_it_does_without_an_amount() -> void:
	_fill_hold(FULL_HOLD_G - 3_000)
	sim.submit(_mine_grams(10_000))
	sim.step(4)
	var stopped := _first(sim.take_events(), "mining_stopped")
	assert_eq(stopped["data"], { "deposit": DEPOSIT, "grams": 3_000, "reason": "cargo_full" })


func test_an_amount_must_be_a_whole_number_above_zero() -> void:
	for grams: Variant in [0, -5, "5000"]:
		_assert_refused(_mine_grams(grams), "malformed_command")


func test_nothing_more_is_mined_after_the_hold_fills() -> void:
	sim.submit(_mine())
	sim.step(FULL_TICKS + 5)
	assert_eq(_held(), FULL_HOLD_G)


func test_an_exhausted_deposit_finishes_the_order() -> void:
	_set_deposit(5000)
	sim.submit(_mine())
	_step_balanced(4)
	assert_eq(_held(), 5000)
	assert_eq(state["deposits"][DEPOSIT]["remaining_g"], 0)
	var events := sim.take_events()
	var stopped := _first(events, "mining_stopped")
	assert_eq(stopped["data"]["reason"], "deposit_exhausted")
	assert_eq(stopped["data"]["grams"], 5000)
	assert_true(_types(events).has("task_finished"))


func test_a_tick_is_clamped_by_the_deposit() -> void:
	_set_deposit(500)
	sim.submit(_mine())
	_step_balanced(1)
	assert_eq(_held(), 500)


func test_a_tick_is_clamped_by_the_hold() -> void:
	_fill_hold(FULL_HOLD_G - 700)
	sim.submit(_mine())
	_step_balanced(1)
	assert_eq(_held(), FULL_HOLD_G)


func test_a_tick_clamped_by_both_takes_the_smaller() -> void:
	_fill_hold(FULL_HOLD_G - 700)
	_set_deposit(300)
	sim.submit(_mine())
	_step_balanced(1)
	assert_eq(_held(), FULL_HOLD_G - 400)


func test_both_ending_on_one_tick_reports_the_deposit() -> void:
	_fill_hold(FULL_HOLD_G - 700)
	_set_deposit(700)
	sim.submit(_mine())
	sim.step(2)
	assert_eq(_first(sim.take_events(), "mining_stopped")["data"]["reason"], "deposit_exhausted")


func test_mining_with_a_full_hold_ends_with_nothing_taken() -> void:
	_fill_hold(FULL_HOLD_G)
	sim.submit(_mine())
	sim.step(2)
	var stopped := _first(sim.take_events(), "mining_stopped")
	assert_eq(stopped["data"], { "deposit": DEPOSIT, "grams": 0, "reason": "cargo_full" })


func test_a_hold_limited_by_volume_stops_on_it() -> void:
	var defs := _own_defs()
	defs["modules"]["ore_container_mk1"]["capabilities"]["storage"]["ore"]["volume_l"] = 2
	sim.submit(_mine())
	sim.step(10)
	assert_eq(_held(), 10000, "2 litres of 5 kg per litre")


func test_the_lower_unit_id_takes_a_shared_deposit_first() -> void:
	var other := Units.create(sim._ctx, "starter_ship", "Second", [0, 0, 0])
	_place(other)
	var other_laser := -1
	for part_id in Units.part_ids(state, other):
		if state["parts"][part_id]["def"] == "mining_laser_mk1":
			other_laser = part_id
		if state["parts"][part_id].has("stored_j"):
			state["parts"][part_id]["stored_j"] = 1000000000  # A built unit's batteries start empty.
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	_set_deposit(3000)
	sim.submit(_mine())
	sim.submit(_mine(other, DEPOSIT, other_laser))
	_step_balanced(1)
	assert_eq(_held(SHIP), 2000)
	assert_eq(_held(other), 1000)
	assert_eq(state["deposits"][DEPOSIT]["remaining_g"], 0)


func test_a_fractional_rate_carries_its_remainder() -> void:
	_own_defs()["modules"]["mining_laser_mk1"]["capabilities"]["mine"]["rate_g_per_s"] = 25
	sim.submit(_mine())
	sim.step(10)
	assert_eq(_held(), 25, "one second of mining gives exactly the rate")
	assert_eq(sim.view()["units"][SHIP]["op"]["mine_remainder"], 0)


func test_a_clamped_tick_leaves_the_remainder_unchanged() -> void:
	_own_defs()["modules"]["mining_laser_mk1"]["capabilities"]["mine"]["rate_g_per_s"] = 25
	_set_deposit(1)
	sim.submit(_mine())
	sim.step()
	assert_eq(_held(), 1, "2 wanted, 1 left")
	assert_eq(state["units"][SHIP]["op"]["mine_remainder"], 0)


func test_mining_draws_power_and_makes_heat() -> void:
	sim.submit(_mine())
	sim.step(1)
	var unit: Dictionary = sim.view()["units"][SHIP]
	var stored_before: int = unit["power"]["stored_j"]
	assert_eq(unit["power"]["demand_w"], 152000, "laser and core")
	assert_eq(unit["heat"]["input_w"], 122000, "laser and core")
	sim.step(FULL_TICKS - 1)
	unit = sim.view()["units"][SHIP]
	assert_lt(unit["power"]["stored_j"], stored_before, "the batteries cover the difference")
	assert_lte(unit["heat"]["stored_j"], unit["heat"]["limit_j"])
	assert_false(_types(sim.take_events()).has("power_shed"))


func test_the_laser_stops_drawing_when_mining_ends() -> void:
	sim.submit(_mine())
	sim.step(FULL_TICKS + 1)
	assert_eq(sim.view()["units"][SHIP]["power"]["demand_w"], 2000, "the core alone")


func test_no_power_ends_the_order_with_nothing_mined() -> void:
	for part_id in [31, 32]:
		state["parts"][part_id]["stored_j"] = 0
	sim.submit(_mine())
	sim.step(2)
	assert_eq(_held(), 0)
	var events := sim.take_events()
	assert_true(_types(events).has("power_shed"))
	assert_eq(_first(events, "mining_stopped")["data"], { "deposit": DEPOSIT, "grams": 0, "reason": "no_power" })
	assert_eq(_first(events, "task_cancelled")["data"]["reason"], "no_power")


func test_overheating_ends_the_order_and_keeps_what_was_mined() -> void:
	var defs := _own_defs()
	defs["modules"]["starter_hull"]["capabilities"]["heat_capacity"]["limit_j"] = 100
	defs["modules"]["heat_radiator_mk1"]["capabilities"]["radiator"]["reject_w"] = 100000
	sim.submit(_mine())
	_step_balanced(3)
	var events := sim.take_events()
	assert_true(_types(events).has("fault"))
	var stopped := _first(events, "mining_stopped")
	assert_eq(stopped["data"]["reason"], "module_fault")
	assert_eq(stopped["data"]["grams"], _held())
	assert_gt(_held(), 0)


func test_stop_ends_mining_and_keeps_what_was_mined() -> void:
	sim.submit(_mine())
	sim.step(10)
	sim.take_events()
	sim.submit(_stop())
	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["mining_stopped", "task_cancelled"])
	assert_eq(events[0]["data"], { "deposit": DEPOSIT, "grams": 20000, "reason": "player_stop" })
	assert_eq(_held(), 20000)


func test_a_new_order_ends_mining() -> void:
	sim.submit(_mine())
	sim.step(10)
	sim.take_events()
	sim.submit({ "type": "scan", "unit": SHIP, "args": { "target": ROCK } })
	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["mining_stopped", "task_cancelled", "task_started"])
	assert_eq(events[0]["data"]["reason"], "player_order")


func test_mining_again_counts_from_zero() -> void:
	sim.submit(_mine())
	sim.step(10)
	sim.submit(_stop())
	sim.step()
	sim.take_events()
	sim.submit(_mine())
	sim.step(10)
	sim.submit(_stop())
	sim.step()
	assert_eq(_first(sim.take_events(), "mining_stopped")["data"]["grams"], 20000)


func test_mining_needs_a_found_deposit() -> void:
	_assert_refused(_mine(SHIP, OTHER_DEPOSIT), "unknown_deposit")
	_assert_refused(_mine(SHIP, 9999), "unknown_deposit")


func test_a_refusal_reveals_nothing_about_a_hidden_deposit() -> void:
	var hidden := sim.check(_mine(SHIP, OTHER_DEPOSIT))
	var absent := sim.check(_mine(SHIP, 9999))
	assert_eq(hidden, absent)


func test_mining_needs_a_laser_on_this_unit() -> void:
	_assert_refused(_mine(SHIP, DEPOSIT, LIDAR), "module_missing")
	_assert_refused(_mine(SHIP, DEPOSIT, 9), "module_missing")
	_assert_refused(_mine(SHIP, DEPOSIT, 9999), "module_missing")


func test_mining_needs_a_healthy_laser() -> void:
	state["parts"][LASER]["fault"] = "test_fault"
	_assert_refused(_mine(), "module_fault")


func test_mining_is_refused_while_docked() -> void:
	state["units"][SHIP]["dock"] = { "port": 28, "target_unit": 8, "target_port": 12 }
	_assert_refused(_mine(), "docked")


func test_mining_is_refused_away_from_the_body() -> void:
	state["units"][SHIP]["at_target"] = 4
	_assert_refused(_mine(), "out_of_range")


func test_mining_an_empty_deposit_is_refused() -> void:
	_set_deposit(0)
	_assert_refused(_mine(), "deposit_exhausted")


func test_a_deposit_can_be_too_hard_for_the_laser() -> void:
	_own_defs()["modules"]["mining_laser_mk1"]["capabilities"]["mine"]["hardness_max"] = 5
	_assert_refused(_mine(), "too_hard")


func test_mining_needs_the_module_tier() -> void:
	_own_defs()["modules"]["mining_laser_mk1"]["min_ai_tier"] = 2
	_assert_refused(_mine(), "tier_too_low")


func test_mining_needs_arguments_of_the_right_type() -> void:
	_assert_refused({ "type": "start_mining", "unit": SHIP, "args": { "deposit": DEPOSIT } }, "malformed_command")


func test_a_mining_laser_cannot_be_detached_while_it_runs() -> void:
	sim.submit(_mine())
	sim.step()
	assert_eq(sim.check({
		"type": "detach_part", "unit": SHIP, "args": { "part": LASER, "to": SHIP },
	})["reason"], "part_busy")


func test_a_save_midway_finishes_identically() -> void:
	sim.submit(_mine())
	sim.step(103)
	var loaded := Sim.from_save(sim.to_save())
	assert_not_null(loaded)
	sim.step(FULL_TICKS)
	loaded.step(FULL_TICKS)
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_eq(loaded.view()["units"][SHIP]["inventory"]["hematite"], FULL_HOLD_G)
