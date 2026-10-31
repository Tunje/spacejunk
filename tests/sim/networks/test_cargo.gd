extends GutTest
## Travel, docking and transfer (networks.md sections 5 and 6), run through real orders, with the
## figures of reference_scenario.md. Durations run from a step's start to the next step's start.

const STATION := 8
const SHIP := 23
const RED_ROCK := 2
const BRASS_ROCK := 4
const SHIP_PORT := 28
const STATION_PORT := 12
const SPARE_PORT := 11
const UNDOCK_POINT := [150_000, 0, 0]
const RED_STOP := [49_350_000, 0, 0]
const TRIP_TICKS := 984
const TRIP_1_OUT_G := 54_908
const TRIP_1_BACK_G := 74_047
const DRONE_OUT_G := 6692

var sim: Sim
var state: Dictionary


## Adds mass after phase 1 validation and before phase 4 pricing.
class LateCargo extends SimSystem:
	const GRAMS := 1_000_000
	var done := false

	func update_tasks(ctx: SimContext) -> void:
		if not done:
			done = true
			Units.add_stock(ctx.state["units"][23]["inventory"], "hematite", GRAMS)


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state


func _order(type: String, args: Dictionary = {}, unit: int = SHIP) -> Dictionary:
	return { "type": type, "unit": unit, "args": args }


## Steps until the unit's task ends, and returns how many ticks that took from the order's tick.
func _run_order(command: Dictionary, limit: int = 3000) -> int:
	sim.submit(command)
	var unit: int = command["unit"]
	sim.step()
	var taken := 0
	while state["units"][unit]["task"] != 0 and taken < limit:
		sim.step()
		taken += 1
		_assert_clean()
	return taken


## Runs every tick, so it reports only on a failure. GUT's asserts are slow at this volume.
func _assert_clean() -> void:
	var ledger := sim.ledger()
	if ledger["matter"]["total_g"] != ledger["matter"]["start_g"] or not ledger["violations"].is_empty():
		fail_test("ledger at tick %d: %s" % [sim.current_tick(), ledger])


func _unit() -> Dictionary:
	return state["units"][SHIP]


func _propellant(unit: int = SHIP) -> int:
	return state["units"][unit]["inventory"].get("propellant", 0)


func _undock() -> void:
	_run_order(_order("undock"))


func _types(events: Array) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


## Sets a stack by hand, keeping the ledger right.
func _set_stock(unit: int, item: String, grams: int) -> void:
	var inventory: Dictionary = state["units"][unit]["inventory"]
	state["matter_start_g"] += grams - inventory.get(item, 0)
	inventory[item] = grams


func test_mul_div_ceil() -> void:
	assert_eq(IntMath.mul_div_ceil(7, 1, 2), 4)
	assert_eq(IntMath.mul_div_ceil(6, 1, 2), 3)
	assert_eq(IntMath.mul_div_ceil(0, 5, 3), 0)
	var big := 9223372036854775807
	assert_eq(IntMath.mul_div_ceil(big, big, big), big)
	assert_eq(IntMath.mul_div_ceil(big, big - 1, big), big - 1)
	assert_eq(IntMath.mul_div_ceil(4_000_000_000_000_000_000, 7, 8), 3_500_000_000_000_000_000)
	assert_eq(IntMath.mul_div_ceil(4_000_000_000_000_000_001, 7, 8), 3_500_000_000_000_000_001)


func test_undock_takes_100_ticks_and_leaves_the_unit_at_its_host() -> void:
	assert_eq(_run_order(_order("undock")), 100)
	assert_eq(_unit()["pos_mm"], UNDOCK_POINT)
	assert_eq(_unit()["at_target"], STATION)
	assert_eq(_unit()["dock"], {})
	assert_false(Units.port_in_use(state, STATION_PORT))


func test_undocked_fires_on_the_last_operation_tick() -> void:
	sim.submit(_order("undock"))
	sim.step(100)
	assert_true(_types(sim.take_events()).has("undocked"))
	sim.step()
	assert_eq(_types(sim.take_events()), ["task_finished"])


func test_trip_1_out_matches_the_document() -> void:
	_undock()
	var quote := sim.check(_order("move_to", { "target": RED_ROCK }))
	assert_true(quote["ok"])
	assert_eq(quote["detail"], { "ticks": TRIP_TICKS, "propellant_g": TRIP_1_OUT_G })
	assert_eq(_run_order(_order("move_to", { "target": RED_ROCK })), TRIP_TICKS)
	assert_eq(_unit()["pos_mm"], RED_STOP)
	assert_eq(_unit()["at_target"], RED_ROCK)
	assert_eq(_propellant(), 1_000_000 - TRIP_1_OUT_G)
	assert_eq(sim.ledger()["matter"]["sinks"], { "propellant_exhaust": TRIP_1_OUT_G })


func test_payment_is_whole_on_the_departure_tick_and_movement_starts_then() -> void:
	_undock()
	sim.submit(_order("move_to", { "target": RED_ROCK }))
	sim.step()
	assert_eq(_propellant(), 1_000_000 - TRIP_1_OUT_G)
	assert_eq(_unit()["pos_mm"], [200_000, 0, 0])
	assert_eq(_unit()["at_target"], 0)
	assert_eq(sim.view()["units"][SHIP]["route"]["eta_tick"], sim.current_tick() + TRIP_TICKS - 1)


func test_arrived_fires_on_eta_tick() -> void:
	_undock()
	sim.submit(_order("move_to", { "target": RED_ROCK }))
	sim.step()
	var eta: int = sim.view()["units"][SHIP]["route"]["eta_tick"]
	sim.step(eta - sim.current_tick() - 1)
	assert_eq(_unit()["at_target"], 0)
	sim.step()
	assert_eq(sim.current_tick(), eta)
	assert_eq(_unit()["at_target"], RED_ROCK)
	assert_true(_types(sim.take_events()).has("arrived"))


func test_mass_raises_the_price() -> void:
	_undock()
	_set_stock(SHIP, "hematite", 2_000_000)
	var loaded := sim.check(_order("move_to", { "target": RED_ROCK }))
	assert_gt(loaded["detail"]["propellant_g"], TRIP_1_OUT_G)


func test_trip_1_back_matches_the_document() -> void:
	_undock()
	_run_order(_order("move_to", { "target": RED_ROCK }))
	_set_stock(SHIP, "hematite", 2_000_000)
	assert_eq(_run_order(_order("move_to", { "target": STATION })), TRIP_TICKS)
	assert_eq(_unit()["pos_mm"], UNDOCK_POINT)
	assert_eq(_unit()["at_target"], STATION)
	assert_eq(_propellant(), 1_000_000 - TRIP_1_OUT_G - TRIP_1_BACK_G)


func test_the_stop_point_is_off_the_axis_and_floored() -> void:
	_undock()
	_set_stock(SHIP, "propellant", 744_615)
	_run_order(_order("move_to", { "target": BRASS_ROCK }))
	assert_eq(_unit()["pos_mm"], [29_671_058, 0, 39_559_207])
	assert_eq(_propellant(), 692_007)


func test_a_whole_tank_trip_pays_exactly_and_one_gram_short_does_not_start() -> void:
	_undock()
	# The tank's own mass is in the price, so settle on the amount that exactly pays for itself.
	var cost := 53_000
	for i in 5:
		_set_stock(SHIP, "propellant", cost)
		cost = sim.check(_order("move_to", { "target": RED_ROCK }))["detail"]["propellant_g"]
	_set_stock(SHIP, "propellant", cost)
	var exact := sim.check(_order("move_to", { "target": RED_ROCK }))
	assert_eq(exact["detail"]["propellant_g"], cost, "the price holds at this mass")
	assert_true(exact["ok"])
	_set_stock(SHIP, "propellant", cost - 1)
	var short := sim.check(_order("move_to", { "target": RED_ROCK }))
	assert_false(short["ok"])
	assert_eq(short["reason"], "no_propellant")
	assert_eq(short["detail"]["have_g"], cost - 1)
	var before: Array = _unit()["pos_mm"].duplicate()
	sim.take_events()
	sim.submit(_order("move_to", { "target": RED_ROCK }))
	sim.step()
	assert_eq(sim.take_events()[0]["data"]["reason"], "no_propellant")
	assert_eq(_unit()["pos_mm"], before)
	assert_eq(_propellant(), cost - 1)
	_set_stock(SHIP, "propellant", cost)
	_run_order(_order("move_to", { "target": RED_ROCK }))
	assert_eq(_propellant(), 0)
	assert_false(_unit()["inventory"].has("propellant"))
	assert_eq(_unit()["at_target"], RED_ROCK)


func test_a_trip_priced_higher_in_phase_4_ends_with_no_propellant() -> void:
	_undock()
	var cost: int = sim.check(_order("move_to", { "target": RED_ROCK }))["detail"]["propellant_g"]
	_set_stock(SHIP, "propellant", cost)
	sim._register_system(LateCargo.new())
	state["matter_start_g"] += LateCargo.GRAMS
	sim.submit(_order("move_to", { "target": RED_ROCK }))
	sim.step(2)
	assert_eq(_unit()["task"], 0)
	var last: Dictionary = sim.take_events()[-1]
	assert_eq(last["type"], "task_cancelled")
	assert_eq(last["data"]["reason"], "no_propellant")
	assert_eq(_propellant(), cost)


func test_a_stop_holds_position_with_no_refund() -> void:
	_undock()
	sim.submit(_order("move_to", { "target": RED_ROCK }))
	sim.step(10)
	var held: Array = _unit()["pos_mm"].duplicate()
	sim.submit(_order("stop"))
	sim.step(5)
	assert_eq(_unit()["pos_mm"], held)
	assert_eq(_unit()["route"], {})
	assert_eq(_unit()["at_target"], 0)
	assert_eq(_propellant(), 1_000_000 - TRIP_1_OUT_G)


func test_a_new_order_while_moving_starts_a_new_route_from_there() -> void:
	_undock()
	sim.submit(_order("move_to", { "target": RED_ROCK }))
	sim.step(10)
	sim.submit(_order("move_to", { "target": BRASS_ROCK }))
	sim.step()
	var route: Dictionary = sim.view()["units"][SHIP]["route"]
	assert_eq(route["target"], BRASS_ROCK)
	assert_eq(route["from_mm"][0], 650_000)
	_assert_clean()


func test_a_trip_ignores_faults_and_shed_power() -> void:
	_undock()
	sim.submit(_order("move_to", { "target": RED_ROCK }))
	sim.step(5)
	state["parts"][27]["fault"] = "test_fault"
	sim.step(TRIP_TICKS)
	assert_eq(_unit()["at_target"], RED_ROCK)


func test_a_trip_needs_a_healthy_thruster() -> void:
	_undock()
	state["parts"][27]["fault"] = "test_fault"
	assert_eq(sim.check(_order("move_to", { "target": RED_ROCK }))["reason"], "module_fault")


func test_move_refusals() -> void:
	assert_eq(sim.check(_order("move_to", { "target": RED_ROCK }))["reason"], "docked")
	_undock()
	assert_eq(sim.check(_order("move_to", { "target": 999 }))["reason"], "invalid_target")
	assert_eq(sim.check(_order("move_to", { "target": SHIP }))["reason"], "invalid_target")
	assert_eq(sim.check(_order("move_to", { "target": 3 }))["reason"], "invalid_target")
	assert_eq(sim.check(_order("move_to", {}))["reason"], "malformed_command")


func test_repeating_an_order_to_the_current_target_costs_nothing() -> void:
	_undock()
	_run_order(_order("move_to", { "target": BRASS_ROCK }))
	var quote := sim.check(_order("move_to", { "target": BRASS_ROCK }))
	assert_eq(quote["detail"], { "ticks": 1, "propellant_g": 0 })
	var held: Array = _unit()["pos_mm"].duplicate()
	var before := _propellant()
	assert_eq(_run_order(_order("move_to", { "target": BRASS_ROCK })), 1)
	assert_eq(_unit()["pos_mm"], held)
	assert_eq(_propellant(), before)
	assert_eq(_unit()["at_target"], BRASS_ROCK)


func test_a_unit_already_inside_the_standoff_arrives_for_nothing() -> void:
	_undock()
	_unit()["at_target"] = 0
	_unit()["pos_mm"] = [50_000, 0, 0]
	assert_eq(sim.check(_order("move_to", { "target": STATION }))["detail"], { "ticks": 1, "propellant_g": 0 })
	_run_order(_order("move_to", { "target": STATION }))
	assert_eq(_unit()["at_target"], STATION)
	assert_eq(_unit()["pos_mm"], [50_000, 0, 0])


func test_leaving_clears_at_target_on_units_at_the_mover() -> void:
	_undock()
	state["units"][STATION]["at_target"] = SHIP
	sim.submit(_order("move_to", { "target": RED_ROCK }))
	sim.step()
	assert_eq(state["units"][STATION]["at_target"], 0)


func test_docking_needs_to_be_at_the_host() -> void:
	_undock()
	var dock := _order("dock", { "port": SHIP_PORT, "target_port": STATION_PORT })
	assert_true(sim.check(dock)["ok"])
	_run_order(_order("move_to", { "target": RED_ROCK }))
	assert_eq(sim.check(dock)["reason"], "out_of_range")


func test_dock_takes_200_ticks_and_joins_the_host() -> void:
	_undock()
	var taken := _run_order(_order("dock", { "port": SHIP_PORT, "target_port": SPARE_PORT }))
	assert_eq(taken, 200)
	assert_eq(_unit()["dock"], { "port": SHIP_PORT, "target_unit": STATION, "target_port": SPARE_PORT })
	assert_eq(_unit()["pos_mm"], [0, 0, 0])
	assert_eq(_unit()["at_target"], STATION)
	assert_false(state["parts"][SPARE_PORT].has("claimed_by"))


func test_dock_refusals() -> void:
	var dock := _order("dock", { "port": SHIP_PORT, "target_port": SPARE_PORT })
	assert_eq(sim.check(dock)["reason"], "docked")
	_undock()
	assert_eq(sim.check(_order("dock", { "port": 35, "target_port": 12 }))["reason"], "unknown_part")
	assert_eq(sim.check(_order("dock", { "port": SHIP_PORT, "target_port": 13 }))["reason"], "unknown_part")
	assert_eq(sim.check(_order("dock", {}))["reason"], "malformed_command")
	state["parts"][SPARE_PORT]["fault"] = "test_fault"
	assert_eq(sim.check(dock)["reason"], "module_fault")


func test_a_taken_port_is_refused() -> void:
	_undock()
	state["parts"][SPARE_PORT]["claimed_by"] = 99
	var dock := _order("dock", { "port": SHIP_PORT, "target_port": SPARE_PORT })
	assert_eq(sim.check(dock)["reason"], "port_busy")


func test_losing_the_phase_4_grant_cancels_the_order() -> void:
	_undock()
	var rival := Units.create(sim._ctx, "starter_ship", "Rival", UNDOCK_POINT)
	state["units"][rival]["at_target"] = STATION
	state["matter_start_g"] += Units.unit_mass(state, sim._ctx.defs, rival)
	var rival_port: int = Units.ports(state, sim._ctx.defs, rival)[0]
	sim.submit(_order("dock", { "port": SHIP_PORT, "target_port": SPARE_PORT }))
	sim.submit(_order("dock", { "port": rival_port, "target_port": SPARE_PORT }, rival))
	sim.step(2)
	assert_eq(state["units"][rival]["task"], 0)
	var cancelled := sim.take_events().filter(func(event: Dictionary) -> bool:
		return event["type"] == "task_cancelled")
	assert_eq(cancelled.size(), 1)
	assert_eq(cancelled[0]["unit"], rival)
	assert_eq(cancelled[0]["data"]["reason"], "port_busy")
	assert_eq(_unit()["op"]["type"], "docking")


func test_a_space_claim_reduces_what_fits_this_tick() -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["ore_container_mk1"]["capabilities"]["storage"]["ore"]["mass_g"] = 3000
	Reservations.claim_space(sim._ctx, SHIP, "hematite", 2000)
	assert_eq(Reservations.free_space(sim._ctx, SHIP, "hematite"), 1000)


func test_a_cancelled_dock_gives_its_ports_back() -> void:
	_undock()
	sim.submit(_order("dock", { "port": SHIP_PORT, "target_port": SPARE_PORT }))
	sim.step(5)
	assert_true(Units.port_in_use(state, SPARE_PORT))
	sim.submit(_order("stop"))
	sim.step()
	assert_false(Units.port_in_use(state, SPARE_PORT))


func test_new_orders_during_undocking_are_rejected() -> void:
	sim.submit(_order("undock"))
	sim.step(5)
	assert_eq(sim.check(_order("undock"))["reason"], "busy_docking")


func test_undock_refused_when_not_docked() -> void:
	_undock()
	assert_eq(sim.check(_order("undock"))["reason"], "not_docked")


func test_unload_takes_400_ticks_for_a_full_hold() -> void:
	_set_stock(SHIP, "hematite", 2_000_000)
	assert_eq(_run_order(_order("unload_cargo", { "to": STATION, "item": "hematite" })), 400)
	assert_eq(state["units"][STATION]["inventory"]["hematite"], 2_000_000)
	assert_false(_unit()["inventory"].has("hematite"))


func test_transfer_done_reports_the_real_amount_on_the_last_moving_tick() -> void:
	_set_stock(SHIP, "hematite", 7000)
	sim.submit(_order("unload_cargo", { "to": STATION, "item": "hematite" }))
	sim.step(2)
	var events := sim.take_events()
	assert_eq(events[-1]["type"], "transfer_done")
	assert_eq(events[-1]["data"], { "from": SHIP, "to": STATION, "item": "hematite", "grams": 7000 })
	sim.step()
	assert_eq(_types(sim.take_events()), ["task_finished"])


func test_a_top_up_of_18238_g_takes_4_ticks() -> void:
	_set_stock(SHIP, "propellant", 2_000_000 - 18_238)
	assert_eq(_run_order(_order("load_cargo", { "from": STATION, "item": "propellant" })), 4)
	assert_eq(_propellant(), 2_000_000)


func test_an_explicit_amount_stops_exactly() -> void:
	_run_order(_order("load_cargo", { "from": STATION, "item": "propellant", "grams": 12_345 }))
	assert_eq(_propellant(), 1_000_000 + 12_345)


func test_loading_ends_when_the_source_runs_out() -> void:
	_set_stock(STATION, "hematite", 3000)
	var taken := _run_order(_order("load_cargo", { "from": STATION, "item": "hematite" }))
	assert_eq(taken, 1)
	assert_eq(_unit()["inventory"]["hematite"], 3000)


func test_loading_a_full_class_ends_at_once_without_blocking() -> void:
	_set_stock(SHIP, "propellant", 2_000_000)
	assert_eq(_run_order(_order("load_cargo", { "from": STATION, "item": "propellant" })), 1)
	assert_eq(_unit()["task"], 0)


func test_loading_is_limited_by_volume() -> void:
	_set_stock(STATION, "olivine", 4_000_000)
	_run_order(_order("load_cargo", { "from": STATION, "item": "olivine" }))
	assert_eq(_unit()["inventory"]["olivine"], 2_000_000, "607 L fits inside 750 L")
	_set_stock(SHIP, "olivine", 0)
	_unit()["inventory"].erase("olivine")
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["ore_container_mk1"]["capabilities"]["storage"]["ore"]["volume_l"] = 100
	_run_order(_order("load_cargo", { "from": STATION, "item": "olivine" }))
	assert_eq(_unit()["inventory"]["olivine"], 330_000)


func test_unloading_into_a_full_destination_cancels_the_order_with_cargo_full() -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["ore_storage_mk1"]["capabilities"]["storage"]["ore"]["mass_g"] = 10_000
	_set_stock(SHIP, "hematite", 20_000)
	sim.submit(_order("unload_cargo", { "to": STATION, "item": "hematite" }))
	sim.step(4)
	var events := sim.take_events()
	var last: Dictionary = events[-1]
	assert_eq(last["type"], "task_cancelled")
	assert_eq(last["data"]["reason"], "cargo_full")
	assert_eq(state["units"][STATION]["inventory"]["hematite"], 10_000)
	var done := events.filter(func(event: Dictionary) -> bool: return event["type"] == "transfer_done")
	assert_eq(done.size(), 1)
	assert_eq(done[0]["data"]["grams"], 10_000)


func test_an_interrupted_transfer_still_reports_what_moved() -> void:
	_set_stock(SHIP, "hematite", 100_000)
	sim.submit(_order("unload_cargo", { "to": STATION, "item": "hematite" }))
	sim.step(3)
	sim.submit(_order("stop"))
	sim.step()
	var done := sim.take_events().filter(func(event: Dictionary) -> bool:
		return event["type"] == "transfer_done")
	assert_eq(done.size(), 1)
	assert_eq(done[0]["data"]["grams"], 15_000)


func test_a_station_can_refuel_a_docked_unit() -> void:
	_run_order(_order("unload_cargo", { "to": SHIP, "item": "propellant", "grams": 5000 }, STATION))
	assert_eq(_propellant(), 1_005_000)


func test_transfer_refusals() -> void:
	var load_args := { "from": STATION, "item": "propellant" }
	assert_eq(sim.check(_order("load_cargo", { "from": 999, "item": "propellant" }))["reason"], "unknown_unit")
	assert_eq(sim.check(_order("load_cargo", { "from": STATION, "item": "nothing" }))["reason"], "invalid_target")
	assert_eq(sim.check(_order("load_cargo", { "from": STATION }))["reason"], "malformed_command")
	assert_eq(sim.check(_order("load_cargo", { "from": STATION, "item": "propellant", "grams": 0 }))["reason"], "malformed_command")
	assert_eq(sim.check(_order("load_cargo", { "from": SHIP, "item": "propellant" }))["reason"], "not_docked")
	assert_true(sim.check(_order("load_cargo", load_args))["ok"])
	_undock()
	assert_eq(sim.check(_order("load_cargo", load_args))["reason"], "not_docked")


func test_an_inexact_discrete_amount_is_refused() -> void:
	var command := _order("unload_cargo", { "to": STATION, "item": "wiring", "grams": 15_000 })
	assert_eq(sim.check(command)["reason"], "not_whole_unit")


func test_discrete_stacks_stay_whole_through_a_rate_limited_transfer() -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["ore_container_mk1"]["capabilities"]["storage"]["goods"] = {
		"mass_g": 200_000, "volume_l": 1000,
	}
	sim._ctx.defs["modules"]["docking_port_mk1"]["capabilities"]["port"]["transfer_g_per_s"] = 7000
	_set_stock(STATION, "wiring", 50_000)
	sim.submit(_order("load_cargo", { "from": STATION, "item": "wiring" }))
	for i in 120:
		sim.step()
		var held: int = _unit()["inventory"].get("wiring", 0)
		assert_eq(held % 10_000, 0, "tick %d" % i)
		_assert_clean()
	assert_eq(_unit()["inventory"]["wiring"], 50_000)
	assert_eq(_unit()["task"], 0)


func test_a_save_midway_through_a_trip_matches_an_unbroken_run() -> void:
	_undock()
	sim.submit(_order("move_to", { "target": BRASS_ROCK }))
	var other := Sim.from_save(sim.to_save())
	sim.step(400)
	other.step(200)
	other = Sim.from_save(other.to_save())
	other.step(200)
	assert_eq(other.state_hash(), sim.state_hash())
	sim.step(800)
	other.step(800)
	assert_eq(other.state_hash(), sim.state_hash())
	assert_eq(other._state["units"][SHIP]["at_target"], BRASS_ROCK)


func test_a_save_midway_through_a_transfer_matches_an_unbroken_run() -> void:
	_set_stock(SHIP, "hematite", 2_000_000)
	sim.submit(_order("unload_cargo", { "to": STATION, "item": "hematite" }))
	var other := Sim.from_save(sim.to_save())
	sim.step(200)
	other.step(100)
	other = Sim.from_save(other.to_save())
	other.step(100)
	assert_eq(other.state_hash(), sim.state_hash())


func test_part_a_round_trip_runs_clean_to_the_document_total() -> void:
	assert_eq(_run_order(_order("undock")), 100)
	assert_eq(_run_order(_order("move_to", { "target": RED_ROCK })), TRIP_TICKS)
	_set_stock(SHIP, "hematite", 2_000_000)
	assert_eq(_run_order(_order("move_to", { "target": STATION })), TRIP_TICKS)
	assert_eq(_run_order(_order("dock", { "port": SHIP_PORT, "target_port": STATION_PORT })), 200)
	assert_eq(_run_order(_order("unload_cargo", { "to": STATION, "item": "hematite" })), 400)
	assert_eq(_propellant(), 1_000_000 - TRIP_1_OUT_G - TRIP_1_BACK_G)
	assert_eq(state["units"][STATION]["inventory"]["hematite"], 2_000_000)
