extends GutTest

const COMMAND := FixtureSystem.COMMAND
const STOP_TICK := 40
const SAVE_TICK := 17


func _game(seed_value: int = 12345) -> Sim:
	var sim := Sim.new_game(Sim.SCENARIO_EMPTY, seed_value)
	sim._register_system(FixtureSystem.new())
	FixtureSystem.add_unit(sim, 7, 1000)
	FixtureSystem.add_unit(sim, 3, 1000)
	sim._state["jobs"][5] = { "held": { "slag": 500 }, "work_left": 30, "facility": 0, "status": "fixture", "reason": "" }
	sim._state["matter_start_g"] = 2500
	return sim


func _load(text: String) -> Sim:
	var sim := Sim.from_save(text)
	if sim != null:
		sim._register_system(FixtureSystem.new())
	return sim


func _submit_for_tick(sim: Sim, tick: int) -> void:
	if tick % 5 == 0:
		sim.submit({ "type": COMMAND, "unit": 7 if tick % 10 == 0 else 3, "args": { "grams": tick } })


## Runs a fixed script of commands from the sim's tick up to the target tick.
func _run_to(sim: Sim, target: int) -> void:
	while sim.current_tick() < target:
		_submit_for_tick(sim, sim.current_tick() + 1)
		sim.step()


func _altered_save(sim: Sim, key: String, value: Variant) -> String:
	var state: Dictionary = sim._state.duplicate(true)
	state[key] = value
	return Canon.encode(state)


func test_new_game_round_trips() -> void:
	var text := Sim.new_game(Sim.SCENARIO_EMPTY, 5).to_save()
	assert_eq(Sim.from_save(text).to_save(), text)
	assert_eq(Sim.last_error(), "")


func test_mid_run_save_round_trips_byte_for_byte() -> void:
	var sim := _game()
	_run_to(sim, SAVE_TICK)
	var text := sim.to_save()
	assert_eq(_load(text).to_save(), text)


func test_a_loaded_game_keeps_its_exact_state() -> void:
	var sim := _game()
	_run_to(sim, SAVE_TICK)
	var loaded := _load(sim.to_save())
	assert_eq(loaded._state, sim._state)
	assert_eq(loaded.current_tick(), SAVE_TICK)
	assert_eq(loaded.state_hash(), sim.state_hash())


func test_a_save_midway_changes_nothing_about_the_run() -> void:
	var unbroken := _game()
	_run_to(unbroken, STOP_TICK)
	var first_half := _game()
	_run_to(first_half, SAVE_TICK)
	var resumed := _load(first_half.to_save())
	_run_to(resumed, STOP_TICK)
	assert_eq(resumed.state_hash(), unbroken.state_hash())


func test_saving_every_tick_changes_nothing_about_the_run() -> void:
	var unbroken := _game()
	_run_to(unbroken, STOP_TICK)
	var hopping := _game()
	while hopping.current_tick() < STOP_TICK:
		_run_to(hopping, hopping.current_tick() + 1)
		hopping = _load(hopping.to_save())
	assert_eq(hopping.state_hash(), unbroken.state_hash())


func test_midway_through_a_job_with_sinks_non_zero() -> void:
	# No test commands here: they add grams, which the ledger would rightly flag.
	var sim := _game()
	sim.step(SAVE_TICK)
	var before: Dictionary = sim.ledger()["matter"]
	assert_eq(before["jobs_g"], 500)
	assert_gt(before["sinks_g"], 0)
	var loaded := _load(sim.to_save())
	var after: Dictionary = loaded.ledger()["matter"]
	assert_eq(after, before)
	assert_eq(after["total_g"], after["start_g"])
	loaded.step(STOP_TICK - SAVE_TICK)
	var finished: Dictionary = loaded.ledger()["matter"]
	assert_eq(finished["jobs_g"], 0)
	assert_eq(finished["total_g"], finished["start_g"])


func test_pending_commands_survive_and_apply_after_load() -> void:
	var sim := _game()
	sim.step(3)
	var id := sim.submit({ "type": COMMAND, "unit": 7, "args": { "grams": 11 } })
	var loaded := _load(sim.to_save())
	loaded.step()
	sim.step()
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_eq(loaded.take_events()[0]["data"]["target"], 11)
	assert_eq(loaded.submit({ "type": COMMAND, "unit": 7 }), id + 1)


func test_entity_counter_survives_load() -> void:
	var sim := _game()
	sim._ctx.new_id()
	sim._ctx.new_id()
	assert_eq(_load(sim.to_save())._ctx.new_id(), 3)


func test_rng_streams_resume_including_negative_states() -> void:
	var sim := _game(-77)
	_run_to(sim, SAVE_TICK)
	assert_true(sim._state["rng"].has("fixture"))
	var loaded := _load(sim.to_save())
	for i in 200:
		assert_eq(loaded._ctx.rng.next_u32("fixture"), sim._ctx.rng.next_u32("fixture"))


func test_undrained_events_are_not_saved() -> void:
	var sim := _game()
	sim.submit({ "type": COMMAND, "unit": 7, "args": { "grams": 1 } })
	sim.step()
	assert_eq(_load(sim.to_save()).take_events().size(), 0)
	assert_eq(sim.take_events().size(), 1)


func test_values_of_every_kind_keep_their_type() -> void:
	var sim := Sim.new_game(Sim.SCENARIO_EMPTY, 5)
	var extremes := {
		7: "int key", "7": "string key", "max": 9223372036854775807, "min": -9223372036854775807 - 1,
		"above_float": 9007199254740993, "text": "120", "yes": true, "no": false, "empty": "",
		"quotes": "a\"b\\c", "lines": "a\nb\tc\u0001d", "unicode": "Ångström ∆",
		"list": [3, "3", [true], {}], "colon": "s:already",
	}
	sim._state["units"][1] = extremes
	var loaded := Sim.from_save(sim.to_save())
	assert_eq(loaded._state["units"][1], extremes)
	assert_eq(typeof(loaded._state["units"][1]["max"]), TYPE_INT)
	assert_eq(loaded.to_save(), sim.to_save())


func test_bad_text_is_corrupt() -> void:
	var good := _game().to_save()
	for bad: String in [
		"", "not json", "[]", "\"5\"", "true", "{}",
		good.substr(0, good.length() - 1),
		good + " ",
		good.replace(":", ": "),
	]:
		assert_null(Sim.from_save(bad), bad.substr(0, 20))
		assert_eq(Sim.last_error(), "corrupt", bad.substr(0, 20))


func test_integers_outside_64_bits_or_not_canonical_are_corrupt() -> void:
	var sim := _game()
	var marker := "\"s:seed\":\"12345\""
	assert_string_contains(sim.to_save(), marker)
	for bad: String in [
		"\"9223372036854775808\"", "\"-9223372036854775809\"", "\"007\"", "\"+7\"", "\"-0\"",
		"\"7.5\"", "\"\"", "7", "7.5", "null",
	]:
		var text := sim.to_save().replace(marker, "\"s:seed\":%s" % bad)
		assert_null(Sim.from_save(text), bad)
		assert_eq(Sim.last_error(), "corrupt", bad)


func test_missing_or_mistyped_fields_are_corrupt() -> void:
	var sim := _game()
	var state: Dictionary = sim._state.duplicate(true)
	state.erase("tick")
	assert_null(Sim.from_save(Canon.encode(state)))
	assert_eq(Sim.last_error(), "corrupt")
	assert_null(Sim.from_save(_altered_save(sim, "units", [])))
	assert_eq(Sim.last_error(), "corrupt")
	assert_null(Sim.from_save(_altered_save(sim, "tick", "5")))
	assert_eq(Sim.last_error(), "corrupt")


func test_contract_version_mismatch() -> void:
	assert_null(Sim.from_save(_altered_save(_game(), "contract_version", Sim.CONTRACT_VERSION + 1)))
	assert_eq(Sim.last_error(), "version_mismatch")


func test_a_version_3_save_with_tick_based_jobs_is_refused() -> void:
	var state: Dictionary = _game()._state.duplicate(true)
	state["contract_version"] = 3
	state["jobs"][5].erase("work_left")
	state["jobs"][5]["end_tick"] = 30
	assert_null(Sim.from_save(Canon.encode(state)))
	assert_eq(Sim.last_error(), "version_mismatch")


func test_a_version_4_save_without_research_is_refused() -> void:
	var state: Dictionary = _game()._state.duplicate(true)
	state["contract_version"] = 4
	state.erase("science")
	state.erase("research")
	assert_null(Sim.from_save(Canon.encode(state)))
	assert_eq(Sim.last_error(), "version_mismatch")


func test_tick_rate_mismatch() -> void:
	assert_null(Sim.from_save(_altered_save(_game(), "ticks_per_second", Sim.TICKS_PER_SECOND + 1)))
	assert_eq(Sim.last_error(), "version_mismatch")


func test_data_mismatch() -> void:
	assert_null(Sim.from_save(_altered_save(_game(), "data_hash", "changed")))
	assert_eq(Sim.last_error(), "data_mismatch")


func test_a_saved_game_does_not_need_its_scenario_file() -> void:
	var sim := Sim.new_game("reference", 1)
	var loaded := Sim.from_save(_altered_save(sim, "scenario", "removed_since"))
	assert_not_null(loaded)
	assert_eq(loaded.view()["units"].size(), 2)


func test_a_good_load_clears_the_last_error() -> void:
	assert_null(Sim.from_save("bad"))
	assert_not_null(Sim.from_save(_game().to_save()))
	assert_eq(Sim.last_error(), "")


func test_save_is_stable_across_runs() -> void:
	assert_eq(_game().to_save(), _game().to_save())
