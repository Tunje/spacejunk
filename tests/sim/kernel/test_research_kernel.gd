extends GutTest
## The kernel side of research (C12, contracts version 5): loading theories, science and idea
## deltas, the per-game definitions overlay, saved variants, a scenario's starting theories, unit 0
## commands and the science ledger.

const BASE := "battery_bank_mk1"
const IDEA := "dense_cells"
const VARIANT := "battery_bank_mk1+dense_cells"


func _game() -> Sim:
	var game := Sim.new_game("reference", 7)
	assert_not_null(game, Sim.last_error())
	game._strict = true
	return game


func test_the_loader_reads_theories_science_and_the_bench_test_in_sim_units() -> void:
	var defs := DataLoader.load_defs()
	assert_eq(DataLoader.error, "")
	assert_has(defs["theories"], "autonomous_navigation")
	assert_eq(defs["theories"]["autonomous_navigation"]["unlocks"], ["assisted_core"])
	assert_eq(defs["science"]["composition"]["ticks"], 1200, "120 s")
	assert_eq(defs["science"]["survey"]["points"], { "asteroid": 10 })
	assert_eq(defs["bench_test"]["power_w"], 100_000)
	assert_eq(defs["bench_test"]["work"], 300_000)
	assert_eq(defs["bench_test"]["inputs"][0]["count"], 10)
	assert_gt(defs["bench_test"]["inputs"][0]["grams"], 0, "a count gets its grams")


func test_idea_deltas_are_renamed_to_sim_fields_but_never_scaled() -> void:
	var ideas: Array = DataLoader.load_defs()["modules"][BASE]["ideas"]
	var dense: Dictionary = ideas.filter(func(idea: Dictionary) -> bool: return idea["id"] == IDEA)[0]
	assert_eq(dense["deltas"], { "capabilities.battery.capacity_j": 300_000, "mass_g": 150_000 },
		"ppm stay ppm whatever the field's unit")


func test_a_delta_must_name_a_whole_field_of_its_module() -> void:
	assert_eq(DataLoader.delta_problem(DataLoader.load_defs()["modules"]), "", "today's data passes")
	var module := { "id": "m", "mass_g": 1000, "capabilities": { "battery": { "capacity_j": 5 } }, "ideas": [
		{ "id": "good", "deltas": { "mass_g": 1000, "capabilities.battery.capacity_j": 10 } }] }
	assert_eq(DataLoader.delta_problem({ "m": module }), "")
	module["ideas"].append({ "id": "bad", "deltas": { "capabilities.battery.missing_w": 10 } })
	assert_string_contains(DataLoader.delta_problem({ "m": module }), "idea bad changes capabilities.battery.missing_w")


func test_a_game_sees_derived_entries_that_never_reach_the_cache() -> void:
	var game := _game()
	var defs := game.defs()
	assert_has(defs["items"], "prototype:assisted_core")
	assert_has(defs["recipes"], "prototype:assisted_core")
	assert_has(defs["recipes"], "qualify:assisted_core")
	var cached := DataLoader.load_defs()
	assert_does_not_have(cached["items"], "prototype:assisted_core")
	assert_does_not_have(cached["recipes"], "qualify:assisted_core")
	assert_eq(game._state["data_hash"], Sim._data_hash(cached), "the hash covers authored data only")


func test_a_designed_variant_is_saved_by_its_recipe_and_rebuilt_on_load() -> void:
	var game := _game()
	var made := Research.add_variant(game._ctx, BASE, [IDEA])
	assert_eq(made.get("id", made.get("reason")), VARIANT)
	assert_has(game._ctx.defs["modules"], VARIANT)
	assert_has(game._ctx.defs["recipes"], VARIANT)
	assert_has(game._ctx.defs["recipes"], "qualify:" + VARIANT)
	assert_eq(game._state["research"]["variants"][VARIANT], { "base": BASE, "ideas": [IDEA], "complexity": made["complexity"] })
	assert_eq(game._state["research"]["designs"][VARIANT], Research.PROTOTYPE)
	assert_does_not_have(DataLoader.load_defs()["modules"], VARIANT, "nothing leaks into the cache")
	assert_does_not_have(_game()._ctx.defs["modules"], VARIANT, "or into another game")
	var saved := game.to_save()
	assert_false(saved.contains("capacity_j\":" + str(made["module"]["capabilities"]["battery"]["capacity_j"])),
		"the variant's stats are derived, not saved")
	var loaded := Sim.from_save(saved)
	assert_not_null(loaded, Sim.last_error())
	assert_eq(loaded._ctx.defs["modules"][VARIANT], made["module"])
	assert_eq(loaded._ctx.defs["recipes"][VARIANT], made["recipes"][VARIANT])
	assert_eq(loaded.to_save(), saved)
	assert_eq(Research.add_variant(game._ctx, "no_such_module", [IDEA]).get("reason"), "malformed_command")


func test_a_scenario_may_start_with_theories_proven() -> void:
	var game := Sim.new()
	var defs := DataLoader.load_defs()
	game._setup(Sim._new_state("reference", 7, defs), defs)
	var scenario := { "bodies": [], "units": [], "research": { "theories": ["autonomous_navigation"] } }
	assert_eq(ScenarioBuilder.populate(game._ctx, scenario, {}), "")
	assert_eq(game._state["research"]["theories"], { "autonomous_navigation": 0 })
	assert_eq(game._state["research"]["designs"], { "assisted_core": Research.QUALIFIED })
	var other := Sim.new()
	other._setup(Sim._new_state("reference", 7, defs), defs)
	scenario["research"]["theories"] = ["no_such_theory"]
	assert_string_contains(ScenarioBuilder.populate(other._ctx, scenario, {}), "unknown theory no_such_theory")


class UnitlessSystem extends SimSystem:
	func commands() -> PackedStringArray:
		return PackedStringArray(["for_the_player", "for_a_unit"])

	func unitless_commands() -> PackedStringArray:
		return PackedStringArray(["for_the_player"])


func test_only_a_unitless_command_may_be_sent_with_unit_0() -> void:
	var game := _game()
	game._register_system(UnitlessSystem.new())
	assert_true(game.check({ "type": "for_the_player", "unit": 0, "args": {} })["ok"])
	assert_eq(game.check({ "type": "for_a_unit", "unit": 0, "args": {} })["reason"], Sim.REASON_UNKNOWN_UNIT)
	assert_eq(game.check({ "type": "for_the_player", "unit": 999_999, "args": {} })["reason"], Sim.REASON_UNKNOWN_UNIT,
		"unit 0 only, not any missing unit")


func test_the_science_ledger_holds_or_is_a_violation() -> void:
	var game := _game()
	var science: Dictionary = game._state["science"]
	science["earned"] = 100
	science["points"] = 60
	science["spent"] = 30
	game._state["jobs"][9_999_999] = { "points_held": 10 }
	assert_eq(Research.science_violations(game._state), PackedStringArray())
	assert_eq(Research.held_points(game._state), 10)
	game._state["jobs"].erase(9_999_999)
	assert_eq(game.ledger()["science"], { "points": 60, "earned": 100, "spent": 30, "held": 0 })
	game.step()
	assert_eq(game.ledger()["violations"].size(), 1, "10 points gone missing")
	assert_string_contains(game.ledger()["violations"][0], "science: earned 100")


func test_a_save_without_science_or_research_is_corrupt() -> void:
	for table: String in ["science", "research"]:
		var state: Dictionary = _game()._state.duplicate(true)
		state[table].erase(state[table].keys()[0])
		assert_null(Sim.from_save(Canon.encode(state)), table)
		assert_eq(Sim.last_error(), Sim.ERROR_CORRUPT, table)
