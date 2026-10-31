extends GutTest

const COMMAND := FixtureSystem.COMMAND

var sim: Sim
var fixture: FixtureSystem


func before_each() -> void:
	sim = Sim.new_game(Sim.SCENARIO_EMPTY, 12345)
	sim._strict = true
	fixture = FixtureSystem.new()
	sim._register_system(fixture)
	FixtureSystem.add_unit(sim, 7, 100)
	FixtureSystem.add_unit(sim, 3, 100)


func _add(unit: int, grams: int) -> int:
	return sim.submit({ "type": COMMAND, "unit": unit, "args": { "grams": grams } })


func test_new_game_starts_at_tick_zero() -> void:
	assert_eq(sim.current_tick(), 0)
	assert_eq(Sim.last_error(), "")


func test_unknown_scenario_returns_null_with_a_reason() -> void:
	assert_null(Sim.new_game("no_such_scenario", 1))
	assert_eq(Sim.last_error(), "unknown_scenario")


func test_step_runs_the_requested_ticks() -> void:
	sim.step()
	assert_eq(sim.current_tick(), 1)
	sim.step(4)
	assert_eq(sim.current_tick(), 5)


func test_step_below_one_does_nothing() -> void:
	var before := sim.state_hash()
	sim.step(0)
	sim.step(-3)
	assert_eq(sim.state_hash(), before)


func test_phases_run_in_contract_order() -> void:
	_add(7, 5)
	sim.step()
	assert_eq(fixture.calls, [
		"apply", "update_tasks", "calculate_power", "allocate", "run",
		"apply_delta", "update_stores", "detect",
	])


func test_systems_run_in_registration_order_within_a_phase() -> void:
	var second := FixtureSystem.new()
	sim._register_system(second)
	var order: Array[String] = []
	fixture.calls = order
	second.calls = order
	sim.step()
	assert_eq(order.slice(0, 2), ["update_tasks", "update_tasks"])
	assert_eq(order.count("detect"), 2)


func test_submit_stamps_the_next_tick_and_counts_ids() -> void:
	sim.step(4)
	assert_eq(_add(7, 1), 1)
	assert_eq(_add(7, 1), 2)
	assert_eq(sim._state["commands"][1]["tick"], 5)


func test_submit_cannot_set_id_or_tick() -> void:
	sim.submit({ "id": 99, "tick": 99, "type": COMMAND, "unit": 7, "args": {} })
	assert_eq(sim._state["commands"][0]["id"], 1)
	assert_eq(sim._state["commands"][0]["tick"], 1)


func test_submit_deep_copies() -> void:
	var nested := [1]
	sim.submit({ "type": COMMAND, "unit": 7, "args": { "steps": nested } })
	nested.append(2)
	assert_eq(sim._state["commands"][0]["args"]["steps"], [1])


func test_command_applies_on_its_tick_and_leaves_the_queue() -> void:
	_add(7, 5)
	assert_eq(sim._state["units"][7]["inventory"]["hematite"], 100)
	sim.step()
	assert_eq(sim._state["units"][7]["inventory"]["hematite"], 105)
	assert_eq(sim._state["commands"], [])


func test_commands_apply_in_ascending_id() -> void:
	_add(7, 1)
	_add(3, 2)
	_add(7, 3)
	sim.step()
	var targets: Array = []
	for event in sim.take_events():
		targets.append(event["data"]["target"])
	# Events order by unit within the phase, but each unit keeps command order.
	assert_eq(targets, [2, 1, 3])


func test_deltas_apply_in_ascending_owner_id() -> void:
	_add(7, 1)
	_add(3, 2)
	_add(7, 3)
	sim.step()
	assert_eq(fixture.delta_owners, [3, 7, 7])


func test_unknown_command_is_rejected() -> void:
	var id := sim.submit({ "type": "warp", "unit": 7, "args": {} })
	sim.step()
	var events := sim.take_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "command_rejected")
	assert_eq(events[0]["unit"], 7)
	assert_eq(events[0]["tick"], 1)
	assert_eq(events[0]["data"]["command"], id)
	assert_eq(events[0]["data"]["reason"], "unknown_command")


func test_unknown_unit_is_rejected() -> void:
	_add(99, 1)
	sim.step()
	assert_eq(sim.take_events()[0]["data"]["reason"], "unknown_unit")


func test_system_rejection_carries_detail() -> void:
	_add(7, -2)
	sim.step()
	var event: Dictionary = sim.take_events()[0]
	assert_eq(event["data"]["reason"], "negative_grams")
	assert_eq(event["data"]["detail"], { "grams": -2 })


func test_a_fitting_failure_emits_only_attach_failed() -> void:
	sim.submit({ "type": COMMAND, "unit": 7, "args": { "fit_fail": true } })
	sim.step()
	var events := sim.take_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "attach_failed")
	assert_eq(events[0]["data"]["item"], "hull")
	assert_eq(events[0]["data"]["reason"], "over_mass_limit")


func test_a_float_in_a_command_is_rejected_in_phase_1_and_keeps_the_state_saveable() -> void:
	sim.submit({ "type": COMMAND, "unit": 7, "args": { "grams": 5.0 } })
	assert_ne(sim.to_save(), "")
	sim.step()
	assert_eq(sim.take_events()[0]["data"]["reason"], "float_in_command")
	assert_eq(sim._state["units"][7]["inventory"]["hematite"], 100)


func test_a_nested_float_is_rejected() -> void:
	sim.submit({ "type": COMMAND, "unit": 7, "args": { "steps": [{ "grams": 1.5 }] } })
	sim.step()
	assert_eq(sim.take_events()[0]["data"]["reason"], "float_in_command")


func test_malformed_commands_are_rejected() -> void:
	for bad: Dictionary in [
		{}, { "type": 5, "unit": 7 }, { "type": COMMAND }, { "type": COMMAND, "unit": 7.0 },
		{ "type": COMMAND, "unit": 7, "args": [] },
		{ "type": COMMAND, "unit": 7, "args": { "pos": Vector3i.ZERO } },
	]:
		sim.submit(bad)
		assert_ne(sim.to_save(), "", str(bad))
		sim.step()
		assert_eq(sim.take_events()[0]["data"]["reason"], "malformed_command", str(bad))


func test_check_reports_without_side_effects() -> void:
	var before := sim.state_hash()
	assert_eq(sim.check({ "type": COMMAND, "unit": 7, "args": { "grams": 1 } }),
		{ "ok": true, "reason": "", "detail": {} })
	assert_eq(sim.check({ "type": COMMAND, "unit": 7, "args": { "grams": -1 } }),
		{ "ok": false, "reason": "negative_grams", "detail": { "grams": -1 } })
	assert_eq(sim.check({ "type": "warp", "unit": 7 })["reason"], "unknown_command")
	assert_eq(sim.check({ "type": COMMAND, "unit": 7, "args": { "grams": 1.0 } })["reason"], "float_in_command")
	assert_eq(sim.state_hash(), before)


func test_events_order_by_phase_then_unit_then_emission() -> void:
	fixture.extra_events = [[9, "late_b"], [2, "late_a"], [9, "late_c"]]
	_add(7, 1)
	sim.step()
	var types: Array = []
	for event in sim.take_events():
		types.append(event["type"])
	assert_eq(types, ["arrived", "late_a", "late_b", "late_c"])


func test_take_events_drains() -> void:
	_add(7, 1)
	sim.step()
	assert_eq(sim.take_events().size(), 1)
	assert_eq(sim.take_events().size(), 0)


func test_take_events_keeps_oldest_first_across_ticks() -> void:
	_add(7, 1)
	sim.step()
	_add(7, 2)
	sim.step()
	var events := sim.take_events()
	assert_eq(events[0]["tick"], 1)
	assert_eq(events[1]["tick"], 2)


func test_event_queue_is_bounded_and_drops_oldest() -> void:
	var extra: Array = []
	for i in Sim.MAX_QUEUED_EVENTS + 10:
		extra.append([1, "e%d" % i])
	fixture.extra_events = extra
	sim.step()
	var events := sim.take_events()
	assert_eq(events.size(), Sim.MAX_QUEUED_EVENTS)
	assert_eq(events[0]["type"], "e10")


func test_events_do_not_affect_the_hash() -> void:
	var other := Sim.new_game(Sim.SCENARIO_EMPTY, 12345)
	other._register_system(FixtureSystem.new())
	FixtureSystem.add_unit(other, 7, 100)
	FixtureSystem.add_unit(other, 3, 100)
	for current: Sim in [sim, other]:
		current.submit({ "type": COMMAND, "unit": 7, "args": { "grams": 1 } })
		current.step()
	sim.take_events()
	assert_eq(sim.state_hash(), other.state_hash())


func test_same_seed_and_commands_give_the_same_hash() -> void:
	var a := Sim.new_game(Sim.SCENARIO_EMPTY, 9)
	var b := Sim.new_game(Sim.SCENARIO_EMPTY, 9)
	for current: Sim in [a, b]:
		current._ctx.rng.next_u32("scan")
		current.submit({ "type": "warp", "unit": 1 })
		current.step(30)
	assert_eq(a.state_hash(), b.state_hash())


func test_different_seeds_give_different_hashes() -> void:
	assert_ne(Sim.new_game(Sim.SCENARIO_EMPTY, 1).state_hash(), Sim.new_game(Sim.SCENARIO_EMPTY, 2).state_hash())


func test_state_hash_is_sha256_of_the_save() -> void:
	assert_eq(sim.state_hash(), sim.to_save().sha256_text())
	assert_eq(sim.state_hash().length(), 64)


func test_a_float_in_state_is_a_hard_error() -> void:
	sim._state["units"][7]["inventory"]["hematite"] = 1.5
	assert_eq(sim.to_save(), "")
	assert_push_error("not canonical")
	assert_eq(sim.state_hash(), "")
	assert_push_error("not canonical")


func test_entity_ids_count_up_from_one() -> void:
	assert_eq(sim._ctx.new_id(), 1)
	assert_eq(sim._ctx.new_id(), 2)
	assert_eq(sim._state["next_entity_id"], 3)


func test_view_has_the_frozen_top_level_shape() -> void:
	sim.step(2)
	var view := sim.view()
	assert_eq(view["tick"], 2)
	assert_eq(view["seed"], 12345)
	for key: String in ["units", "bodies", "deposits", "jobs", "tasks"]:
		assert_true(view[key] is Dictionary, key)


func test_view_and_defs_are_copies() -> void:
	sim.view()["units"].clear()
	assert_eq(sim.view()["units"].size(), 2)
	sim.view()["units"][7]["inventory"]["hematite"] = 1
	assert_eq(sim.view()["units"][7]["inventory"]["hematite"], 100)
	sim.defs()["modules"]["x"] = 1
	assert_eq(sim.defs()["modules"], {})


func test_defs_has_the_contract_sections() -> void:
	assert_eq(sim.defs().keys(), ["modules", "items", "recipes", "templates", "sinks"])


func test_ledger_rebuilds_matter_and_sums_all_places() -> void:
	sim._state["matter_start_g"] = 200
	sim.step(10)
	var matter: Dictionary = sim.ledger()["matter"]
	# Two units vent 3 g each over one second.
	assert_eq(matter["sinks_g"], 6)
	assert_eq(matter["inventories_g"], 194)
	assert_eq(matter["total_g"], matter["start_g"])


func test_an_injected_imbalance_fails_the_matter_check() -> void:
	sim._state["matter_start_g"] = 200
	sim.step(10)
	assert_eq(sim.ledger()["matter"]["total_g"], sim.ledger()["matter"]["start_g"])
	fixture.injected_g = 1
	assert_ne(sim.ledger()["matter"]["total_g"], sim.ledger()["matter"]["start_g"])


func test_strict_run_flags_values_outside_the_contract_ranges() -> void:
	sim._state["units"][7]["stored_j"] = -1
	sim._state["units"][7]["pos_mm"] = [0, 0, 4_000_000_000_000_000_001]
	sim._state["units"][7]["inventory"]["hematite"] = 2_000_000_000_000_000
	sim._state["units"][7]["other_remainder"] = 99
	sim.step()
	var joined := "\n".join(sim.ledger()["violations"])
	assert_string_contains(joined, "stored_j")
	assert_string_contains(joined, "pos_mm")
	assert_string_contains(joined, "hematite")
	assert_string_contains(joined, "other_remainder")


func test_strict_run_accepts_a_clean_state_and_large_world_totals() -> void:
	sim._state["matter_start_g"] = 9_000_000_000_000_000_000
	sim._state["sinks"]["slag_vent"] = { "slag": 2_000_000_000_000_000 }
	sim.step(20)
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_no_undeclared_state_changes_on_an_idle_tick() -> void:
	var idle := Sim.new_game(Sim.SCENARIO_EMPTY, 5)
	var before: Dictionary = idle._state.duplicate(true)
	idle.step()
	before["tick"] = 1
	assert_eq(idle._state, before)
