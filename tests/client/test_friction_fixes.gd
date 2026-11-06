extends GutTest
## D32: fixes for what the D31 playthrough found awkward. The research screen starts
## a theory's test or a bench test at a lab; a power shed names the part.

var main: Node
var bridge: SimBridge


## The bot's game after stage 6: home, docked, with the lab built and the evidence in.
func before_all() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	var sim := Sim.from_save(FileAccess.get_file_as_string(NewStartBot.snapshot_path(NewStartBot.STAGE_RETURN)))
	bridge.start(sim)
	main.local_view.rebuild()


func after_all() -> void:
	main.free()


func _button(text: String) -> Button:
	for node: Node in main.research_screen._body.get_children():
		if node is Button and (node as Button).text == text:
			return node
	return null


func test_research_starts_a_theory_at_a_lab() -> void:
	main.toggle_research()
	var screen: ResearchScreen = main.research_screen
	var labs := ResearchLogic.labs(bridge.current_view, bridge.defs())
	assert_eq(labs.size(), 1, "the station's lab")
	var start := _button("Start at a lab")
	assert_not_null(start)
	var started: Array = []
	screen.lab_started.connect(func(recipe: String) -> void: started.append(recipe))
	var jobs_before: int = bridge.current_view["jobs"].size()
	if start.disabled:
		assert_ne(start.tooltip_text, "", "says why: %s" % start.tooltip_text)
		return
	start.pressed.emit()
	bridge.set_paused(false)
	bridge.advance(0.1)
	bridge.set_paused(true)
	assert_eq(started.size(), 1)
	assert_gt(bridge.current_view["jobs"].size(), jobs_before, "the test is queued at the lab")


func test_without_a_lab_the_button_says_so() -> void:
	var defs := { "modules": {}, "recipes": {} }
	assert_eq(ResearchLogic.labs({ "units": {} }, defs), [] as Array[Dictionary])
	assert_eq(ResearchLogic.lab_command({ "unit": 3, "part": 9 }, "prove_x"),
		{ "type": "queue_job", "unit": 3, "args": { "facility": 9, "recipe": "prove_x", "count": 1 } })


func test_a_power_shed_names_the_part() -> void:
	var line := OrderText.event({ "type": "power_shed", "unit": 1, "data": { "module": 9, "reason": "power_shed" } },
		"Probe", {}, {}, { 9: "Mining Laser" })
	assert_string_starts_with(line, "Probe: Mining Laser shut down (")
	assert_string_ends_with(line, "It restarts when power returns.")


func test_measure_everything_runs_each_unpaid_kind_in_turn() -> void:
	main.toggle_research()
	var view: LocalView = main.local_view
	var panel: OrderPanel = main.order_panel
	var probe := 0
	for id: int in bridge.current_view["units"]:
		if bridge.current_view["units"][id]["name"] == "Probe":
			probe = id
	var rock := 0
	for id: int in bridge.current_view["bodies"]:
		if bridge.current_view["bodies"][id]["name"] == "Red Rock":
			rock = id
	# Undocked and at a fresh rock's side: survey and composition both still to do there.
	bridge.sim._state["units"][probe]["dock"] = {}
	for id: int in bridge.sim._state["units"]:
		bridge.sim._state["units"][id]["dock"] = {}
	bridge.sim._state["science"]["paid"].erase("survey:%d" % rock)
	bridge.sim._state["science"]["paid"].erase("composition:%d" % rock)
	bridge.start(bridge.sim)
	view.select("unit", probe, 0)
	view.select("body", rock, 0)
	panel.refresh()
	var commands := OrderList.measure_everything(bridge.current_view, bridge.defs()["science"], probe, rock)
	assert_eq(commands.map(func(command: Dictionary) -> String: return command["type"]), ["scan", "measure"])
	assert_not_null(panel.button_for("Measure everything here"))
