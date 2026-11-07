extends GutTest
## D42: designs (B25) expand into every job they need, producers first, and a built
## hull is fitted from the design in its order. On the real new start's data.

const DESIGN := "mining_drone"
const BUILDER := ["refinery", "fabricator"]

var defs: Dictionary


func before_all() -> void:
	defs = Sim.new_game("new_start", 12345).defs()


func test_the_drone_design_is_found() -> void:
	assert_has(DesignLogic.designs(defs), DESIGN)
	assert_eq(DesignLogic.template_recipe(defs["templates"][DESIGN]["base"], defs), "small_craft")


func test_extra_nodes_are_the_parts_beyond_the_hull_in_order() -> void:
	var parts: Array = DesignLogic.extra_nodes(DESIGN, defs).map(func(node: Dictionary) -> String: return node["part"])
	assert_eq(parts, ["small_solar_panel_mk1", "small_heat_radiator_mk1", "small_propellant_tank_mk1",
		"small_chemical_thruster_mk1", "small_ore_container_mk1", "small_mining_laser_mk1",
		"small_battery_bank_mk1", "assisted_core"])
	var thruster: Dictionary = DesignLogic.extra_nodes(DESIGN, defs)[3]
	assert_eq(thruster["path"], "stack_bottom/stack_bottom")
	assert_eq(thruster["parent_path"], "stack_bottom", "on the tank")


## Every job's inputs are made by jobs before it, and nothing is made twice over.
func test_a_plan_puts_producers_first() -> void:
	var plan := DesignLogic.build_plan(DESIGN, {}, defs, BUILDER)
	var made: Dictionary = {}
	for job: Dictionary in plan["jobs"]:
		var recipe: Dictionary = defs["recipes"][job["recipe"]]
		for input: Dictionary in recipe["inputs"]:
			var producer := DesignLogic.producer(input["item"], defs, BUILDER)
			if producer != "":
				assert_true(made.has(producer), "%s comes before %s" % [producer, job["recipe"]])
		made[job["recipe"]] = true
	assert_eq(plan["jobs"][plan["jobs"].size() - 1]["recipe"] in ["small_craft", "assisted_core"], true,
		"an assembly comes last")
	assert_true(made.has("small_craft"), "the hull")
	assert_true(made.has("refine_hematite"), "iron refined from ore")
	assert_true(plan["short"].has("hematite"), "with no ore aboard, ore is short")


func test_stock_on_hand_is_used_first() -> void:
	var stock := {}
	for node: Dictionary in DesignLogic.extra_nodes(DESIGN, defs):
		stock[node["part"]] = defs["items"][node["part"]]["unit_mass_g"]
	stock["structural_frame"] = 100 * defs["items"]["structural_frame"]["unit_mass_g"]
	stock["wiring"] = 100 * defs["items"]["wiring"]["unit_mass_g"]
	var plan := DesignLogic.build_plan(DESIGN, stock, defs, BUILDER)
	assert_eq(plan["jobs"], [{ "recipe": "small_craft", "runs": 1 }], "every part aboard: only the hull")
	assert_true(plan["short"].is_empty())


func test_ore_aboard_is_refined_not_short() -> void:
	var plan := DesignLogic.build_plan(DESIGN, { "hematite": 10_000_000, "chalcopyrite": 10_000_000,
		"olivine": 10_000_000 }, defs, BUILDER)
	assert_true(plan["short"].is_empty(), str(plan["short"]))


func test_without_a_refinery_ore_is_not_refined() -> void:
	var plan := DesignLogic.build_plan(DESIGN, {}, defs, ["fabricator"])
	assert_true(plan["short"].has("iron"), "iron must come from elsewhere")
	assert_false(plan["jobs"].any(func(job: Dictionary) -> bool: return job["recipe"].begins_with("refine_")))


func test_the_plan_reads_as_words() -> void:
	var plan := { "jobs": [{ "recipe": "structural_frame", "runs": 11 }], "short": { "hematite": 120_000 } }
	assert_eq(DesignLogic.plan_text(plan, defs), "11 %s" % IndustryLogic.name_of("structural_frame", defs))
	assert_eq(DesignLogic.short_text(plan, defs), "Needs 120.0 kg %s more first" % IndustryLogic.name_of("hematite", defs))


func test_queue_commands_use_each_recipes_facility() -> void:
	var plan := { "jobs": [{ "recipe": "refine_hematite", "runs": 3 }, { "recipe": "structural_frame", "runs": 2 }] }
	var facilities := [{ "part": 5, "type": "refinery" }, { "part": 6, "type": "fabricator" }]
	var commands := DesignLogic.queue_commands(plan, 13, facilities, defs)
	assert_eq(commands[0], { "type": "queue_job", "unit": 13, "args": { "facility": 5, "recipe": "refine_hematite", "count": 3 } })
	assert_eq(commands[1]["args"]["facility"], 6)


# --- Fit all ---

func _hull(children: Array) -> Dictionary:
	return { "parts": { "id": 1, "def": "small_hull", "children": children }, "core": 0, "inventory": {} }


func test_fit_all_takes_the_first_missing_part_and_finds_its_parent() -> void:
	var tank := { "id": 4, "def": "small_propellant_tank_mk1", "parent_connector": "stack_bottom", "children": [] }
	var unit := _hull([tank])
	assert_eq(DesignLogic.part_at(unit, "stack_bottom")["id"], 4)
	assert_eq(DesignLogic.part_at(unit, ""), unit["parts"])
	assert_true(DesignLogic.part_at(unit, "side_a_px").is_empty())
	assert_eq(DesignLogic.next_fit(DESIGN, unit, defs)["part"], "small_solar_panel_mk1")
	var thruster: Dictionary = DesignLogic.extra_nodes(DESIGN, defs)[3]
	var view := { "units": { 20: unit, 13: { "inventory": { "small_chemical_thruster_mk1": 1 } } } }
	assert_eq(DesignLogic.fit_command(thruster, 20, view, [20, 13]), { "type": "attach_part", "unit": 20, "args": {
		"item": "small_chemical_thruster_mk1", "from": 13, "parent_part": 4, "parent_connector": "stack_bottom",
		"part_connector": "mount" } })
	view["units"][13]["inventory"] = {}
	assert_true(DesignLogic.fit_command(thruster, 20, view, [20, 13]).is_empty(), "no one holds it")


func test_the_core_is_assigned_after_the_last_fit() -> void:
	var unit := _hull([{ "id": 9, "def": "assisted_core", "parent_connector": "core", "children": [] }])
	assert_eq(DesignLogic.core_to_assign(DESIGN, unit, defs), 9)
	unit["core"] = 9
	assert_eq(DesignLogic.core_to_assign(DESIGN, unit, defs), 0)


func test_a_design_matches_a_unit_by_its_root() -> void:
	assert_has(DesignLogic.designs_for_unit(_hull([]), defs), DESIGN)
	assert_eq(DesignLogic.designs_for_unit({ "parts": { "def": "probe_hull" } }, defs), [])


## The Jobs screen on the new start's probe offers the design on its fabricator, and a
## design still locked by research is refused whole, with the Sim's reason.
func test_jobs_offers_the_design_and_refuses_it_whole_while_locked() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	main.toggle_industry()
	var screen: IndustryScreen = main.industry_screen
	for entry: Dictionary in IndustryLogic.facilities(bridge.current_view["units"][screen.unit_id], bridge.defs()["modules"]):
		if entry["type"] == "fabricator":
			screen.choose_facility(entry)
	assert_eq(screen.design_rows.size(), 1)
	assert_string_starts_with((screen.design_rows[0]["preview"] as Label).text, "Queues ")
	var jobs_before: int = bridge.current_view["jobs"].size()
	screen.build_design(DESIGN)
	assert_ne(screen._message.text, "", "refused, with why")
	bridge.set_paused(false)
	bridge.advance(0.2)
	assert_eq(bridge.current_view["jobs"].size(), jobs_before, "nothing queued")


# --- Start with components on any recipe (D43) ---

func test_a_recipe_plan_makes_its_inputs_first() -> void:
	var plan := DesignLogic.recipe_plan("small_solar_panel_mk1", 2, {}, defs, BUILDER)
	var recipes: Array = plan["jobs"].map(func(job: Dictionary) -> String: return job["recipe"])
	assert_eq(recipes[recipes.size() - 1], "small_solar_panel_mk1", "the part itself last")
	assert_eq(plan["jobs"][recipes.size() - 1]["runs"], 2)
	assert_lt(recipes.find("refine_hematite"), recipes.find("structural_frame"), "iron before frames")
	assert_true(recipes.has("wiring"))
	var stocked := DesignLogic.recipe_plan("small_solar_panel_mk1", 1,
		{ "structural_frame": 1_000_000, "wiring": 1_000_000 }, defs, BUILDER)
	assert_eq(stocked["jobs"], [{ "recipe": "small_solar_panel_mk1", "runs": 1 }], "inputs aboard: just the part")


func test_jobs_rows_offer_start_with_components_where_inputs_are_missing() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	main.toggle_industry()
	var screen: IndustryScreen = main.industry_screen
	for entry: Dictionary in IndustryLogic.facilities(bridge.current_view["units"][screen.unit_id], bridge.defs()["modules"]):
		if entry["type"] == "fabricator":
			screen.choose_facility(entry)
	var row := {}
	for candidate: Dictionary in screen._rows:
		if candidate["recipe"]["id"] == "small_solar_panel_mk1":
			row = candidate
	assert_true((row["with"] as Button).visible, "frames and wiring still to make")
	assert_string_contains((row["with"] as Button).tooltip_text, IndustryLogic.name_of("structural_frame", bridge.defs()))
	var jobs_before: int = bridge.current_view["jobs"].size()
	(row["with"] as Button).pressed.emit()
	assert_string_starts_with(screen._message.text, "Queued ")
	bridge.set_paused(false)
	bridge.advance(0.2)
	assert_gt(bridge.current_view["jobs"].size(), jobs_before + 1, "the part and its components")


## A plan made while jobs are queued counts what they will still take and make.
func test_available_stock_counts_queued_jobs() -> void:
	var jobs := {
		1: { "unit": 13, "recipe": "refine_hematite", "count_left": 3, "status": "running", "install_to": {} },
		2: { "unit": 13, "recipe": "structural_frame", "count_left": 2, "status": "queued", "install_to": {} },
		3: { "unit": 99, "recipe": "structural_frame", "count_left": 9, "status": "queued", "install_to": {} },
	}
	var stock := DesignLogic.available_stock(13, { "hematite": 250_000, "iron": 10_000 }, jobs, defs)
	assert_eq(stock["hematite"], 50_000, "the running refine has its current 100 kg; two runs still to take")
	assert_eq(stock["iron"], 10_000 + 3 * 69_000 - 2 * 50_000, "three runs of iron in, two frames' worth out")
	assert_eq(stock["structural_frame"], 2 * defs["items"]["structural_frame"]["unit_mass_g"], "another unit's jobs don't count")
	jobs[2]["install_to"] = { "unit": 5 }
	assert_false(DesignLogic.available_stock(13, {}, jobs, defs).get("structural_frame", 0) > 0, "built in place, never in the hold")

