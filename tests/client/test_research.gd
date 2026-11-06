extends GutTest
## D27: C12's research on the client: the research panel's reading of theories,
## evidence and designs, the variant preview and designer, Measure orders, event
## text, and defs read again once a variant is designed. On the real new start, one
## game for the file: each new start waits on Frost's planet build at teardown. The
## tests that change it (a variant designed, screens toggled) come last.

var main: Node
var bridge: SimBridge
var defs: Dictionary


func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	defs = bridge.defs()


func after_all() -> void:
	main.free()


func _id_of(table: String, name: String) -> int:
	for id: int in bridge.current_view[table]:
		if bridge.current_view[table][id]["name"] == name:
			return id
	return 0


func _with(science: Dictionary, research: Dictionary = {}) -> Dictionary:
	var view: Dictionary = bridge.current_view.duplicate()
	view["science"] = science
	view["research"] = { "theories": {}, "designs": {}, "variants": {}, "discovered": {} }
	view["research"].merge(research, true)
	return view


func _step() -> void:
	bridge.set_paused(false)
	bridge.advance(1.0 / bridge.ticks_per_second())
	bridge.set_paused(true)


func test_design_states_follow_the_theories() -> void:
	var view: Dictionary = bridge.current_view
	assert_eq(ResearchLogic.unlocked_by("assisted_core", defs), "autonomous_navigation")
	assert_eq(ResearchLogic.design_state("assisted_core", view, defs), "locked", "until its theory is proven")
	assert_eq(ResearchLogic.design_state("battery_bank_mk1", view, defs), "qualified", "no theory unlocks it")
	var later := _with({}, { "designs": { "assisted_core": "prototype" } })
	assert_eq(ResearchLogic.design_state("assisted_core", later, defs), "prototype")
	assert_eq(ResearchLogic.next_step("assisted_core", view, defs), "Locked: prove Autonomous Navigation")


func test_a_theory_reads_its_evidence_and_cost() -> void:
	var theory: Dictionary = defs["theories"]["autonomous_navigation"]
	assert_eq(ResearchLogic.theory_status(theory, bridge.current_view, defs), "Gathering evidence")
	var partway := _with({ "points": 0, "evidence": { "survey": 2 } })
	assert_eq(ResearchLogic.evidence_text(theory, partway), "Gravity Field 0 of 1, Survey 2 of 3")
	var ready := _with({ "points": 90, "evidence": { "survey": 3, "gravity_field": 1 } })
	assert_eq(ResearchLogic.theory_status(theory, ready, defs), "Ready to prove")
	var proven := _with({}, { "theories": { "autonomous_navigation": 500 } })
	assert_eq(ResearchLogic.theory_status(theory, proven, defs), "Proven")
	assert_string_starts_with(ResearchLogic.test_cost(theory, defs), "Lab test: 80 points, 10 Processor")


func test_the_variant_preview_matches_the_rules() -> void:
	var shown := ResearchLogic.preview("battery_bank_mk1", ["dense_cells"], defs)
	assert_eq(shown["id"], "battery_bank_mk1+dense_cells")
	assert_eq(shown["complexity"], 2)
	assert_eq(shown["cost_scale"], 1.5)
	assert_eq(shown["points"], 30)
	var capacity: Dictionary = shown["changes"].filter(func(change: Dictionary) -> bool: return change["path"].ends_with("capacity_j"))[0]
	assert_eq(capacity["after"], IntMath.mul_div(capacity["before"], 1_300_000, 1_000_000))
	assert_eq(ResearchLogic.change_text(capacity), "Capacity: +30%")
	# A simplifying idea can't take complexity below zero.
	assert_eq(ResearchLogic.preview("battery_bank_mk1", ["simple_casing"], defs)["complexity"], 0)
	assert_eq(ResearchLogic.variant_id("battery_bank_mk1", ["simple_casing", "dense_cells"]),
		"battery_bank_mk1+dense_cells+simple_casing", "ideas sorted, as the Sim names it")


func test_hidden_ideas_show_once_discovered_and_locked_ones_say_why() -> void:
	var fake := { "modules": { "box": { "ideas": [
		{ "id": "open", "name": "Open" },
		{ "id": "secret", "name": "Secret", "hidden": true },
		{ "id": "gated", "name": "Gated", "theory": "big_idea" },
	] } } }
	var ids := func(view: Dictionary) -> Array:
		return ResearchLogic.visible_ideas("box", view, fake).map(func(idea: Dictionary) -> String: return idea["id"])
	assert_eq(ids.call(_with({})), ["open", "gated"])
	assert_eq(ids.call(_with({}, { "discovered": { "box:secret": 9 } })), ["open", "secret", "gated"])
	assert_true(ResearchLogic.visible_ideas("box", _with({}), fake)[1]["locked"])


func test_measure_orders_suit_the_body() -> void:
	var probe: int = main.local_view.commanded_unit
	var keys := func(kind: String, body: int) -> Array:
		return OrderList.build(bridge.current_view, defs["modules"], defs["items"], probe, kind, body, defs["science"]) \
			.map(func(order: Dictionary) -> String: return order["key"])
	var rock: Array = keys.call("body", _id_of("bodies", "Red Rock"))
	assert_has(rock, "Scan")
	assert_has(rock, "Measure composition")
	assert_does_not_have(rock, "Measure survey", "survey is Scan")
	var frost: Array = keys.call("body", _id_of("bodies", "Frost"))
	assert_has(frost, "Measure gravity_field")
	assert_has(frost, "Measure surface")
	assert_does_not_have(keys.call("body", _id_of("bodies", "Star")), "Measure gravity_field")


func test_research_text_reads_cleanly() -> void:
	var items: Dictionary = defs["items"]
	var event := func(type: String, data: Dictionary) -> String:
		return OrderText.event({ "type": type, "unit": 1, "data": data }, "Probe", items)
	assert_eq(event.call("science_gained", { "kind": "survey", "target": 4, "key": "survey:4", "points": 10 }), "Probe: +10 science (Survey)")
	assert_eq(event.call("science_gained", { "kind": "survey", "target": 4, "key": "survey:4", "points": 0 }),
		"Probe: Survey measured again, no new science")
	assert_eq(event.call("theory_proven", { "theory": "autonomous_navigation" }), "Theory proven: Autonomous Navigation")
	assert_eq(event.call("design_qualified", { "design": "assisted_core" }), "Design qualified: Assisted Core")
	assert_eq(IndustryLogic.name_of("qualify:assisted_core", defs), "Bench Test: Assisted Core")
	assert_string_starts_with(IndustryLogic.name_of("battery_bank_mk1+dense_cells", defs), "Battery Bank")
	assert_eq(OrderText.reason("missing_points"), "Not enough science points")
	var test_recipe: Dictionary = defs["recipes"]["prove_autonomous_navigation"]
	assert_string_starts_with(IndustryLogic.inputs_line(test_recipe, {}, defs, 25), "Science 25 of 80 points")
	assert_false(IndustryLogic.outputs_line(test_recipe, defs).contains("Processor"), "spent test inputs aren't products")


func test_the_panel_opens_and_designs_a_variant() -> void:
	main.toggle_research()
	var screen: ResearchScreen = main.research_screen
	assert_true(screen.visible)
	assert_eq(screen._points.text, "Science: 0 points (earned 0, spent 0)")
	assert_has(ResearchLogic.variant_bases(bridge.current_view, defs), "battery_bank_mk1")
	screen.choose_base("battery_bank_mk1")
	screen.toggle_idea("dense_cells", true)
	assert_false(screen._design_button.disabled, "check takes it: " + screen._message.text)
	var changed := [false]
	bridge.defs_changed.connect(func() -> void: changed[0] = true)
	screen.design()
	_step()
	assert_true(changed[0], "the defs are read again")
	assert_true(bridge.current_view["research"]["variants"].has("battery_bank_mk1+dense_cells"))
	assert_true(main.industry_screen._defs["recipes"].has("prototype:battery_bank_mk1+dense_cells"),
		"the jobs screen has the new prototype recipe")
	assert_has(main.event_log.lines, "New design: Battery Bank (Dense Cells)")
	screen.refresh()
	assert_eq(ResearchLogic.design_state("battery_bank_mk1+dense_cells", bridge.current_view, defs), "prototype")


func test_the_r_key_opens_research_and_shuts_the_jobs_screen() -> void:
	main.toggle_industry()
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_R
	main._unhandled_key_input(key)
	assert_true(main.research_screen.visible)
	assert_false(main.industry_screen.visible, "one side screen at a time")
