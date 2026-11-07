extends GutTest
## D43, on the bot's stage 5 snapshot (slow: it loads a whole game).


## Build into with "Make its components too": the components first, then the part built
## in place on the spot picked.
func test_build_into_can_make_the_components_too() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	# Stage 5's end: the station docked with the probe has room for its depot tank.
	bridge.start(Sim.from_save(FileAccess.get_file_as_string(NewStartBot.snapshot_path(NewStartBot.STAGE_RESEARCH))))
	main.local_view.rebuild()
	var probe := 0
	var station := 0
	for id: int in bridge.current_view["units"]:
		match bridge.current_view["units"][id]["kind"]:
			"station":
				station = id
			"ship":
				probe = id
	main.local_view.select("unit", probe, 0)
	main.toggle_industry()
	var screen: IndustryScreen = main.industry_screen
	for entry: Dictionary in IndustryLogic.facilities(bridge.current_view["units"][probe], bridge.defs()["modules"]):
		if entry["type"] == "fabricator":
			screen.choose_facility(entry)
	screen.open_picker(bridge.defs()["recipes"]["propellant_tank_mk1"])
	var spot := {}
	for slot: Dictionary in screen._slot_buttons:
		if spot.is_empty() and slot["unit"] == station and not (slot["button"] as Button).disabled:
			spot = slot
	assert_false(spot.is_empty(), "a free spot on the station")
	assert_true(screen.picker_with.button_pressed, "on by default when inputs are missing")
	(spot["button"] as Button).pressed.emit()
	assert_string_starts_with(screen._message.text, "Queued ")
	bridge.set_paused(false)
	bridge.advance(0.2)
	var installs := 0
	for id: int in bridge.current_view["jobs"]:
		if not (bridge.current_view["jobs"][id]["install_to"] as Dictionary).is_empty():
			installs += 1
	assert_gt(bridge.current_view["jobs"].size(), 1, "components queued")
	assert_eq(installs, 1, "the panel itself built in place")
