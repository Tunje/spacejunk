extends GutTest
## D29: C15's fabricating in place from the jobs screen. A module recipe offers
## "Build into…": a free connector on this unit or a docked one, each checked by
## the Sim first, and the job's part is fitted there when it finishes. On the real
## reference start: the station's fabricator, the ship docked to it.

var main: Node
var bridge: SimBridge
var screen: IndustryScreen
var sim: Sim
var station := 0
var ship := 0


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = "reference"
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	sim = bridge.sim
	for id: int in bridge.current_view["units"]:
		if bridge.current_view["units"][id]["kind"] == "station":
			station = id
		else:
			ship = id
	screen = main.industry_screen


func _open_fabricator() -> Dictionary:
	main.local_view.select("unit", station, 0)
	main.toggle_industry()
	for entry: Dictionary in IndustryLogic.facilities(bridge.current_view["units"][station], bridge.defs()["modules"]):
		if entry["type"] == "fabricator":
			screen.choose_facility(entry)
	screen.refresh()
	return bridge.defs()["recipes"]["goods_container_mk1"]


func _run(ticks: int) -> void:
	sim.step(ticks)
	var events := sim.take_events()
	bridge.start(sim)
	bridge.events_received.emit(events)
	screen.refresh()


func test_only_a_recipe_that_makes_one_module_can_be_built_into() -> void:
	var defs := bridge.defs()
	assert_eq(IndustryLogic.module_output(defs["recipes"]["goods_container_mk1"], defs), "goods_container_mk1")
	var refine := IndustryLogic.recipes_for("refinery", defs["recipes"])[0]
	assert_eq(IndustryLogic.module_output(refine, defs), "", "ore into metal is not a part")


func test_the_targets_are_this_unit_and_docked_ones() -> void:
	assert_eq(IndustryLogic.install_units(bridge.current_view, station), [station, ship] as Array[int])
	assert_eq(IndustryLogic.install_units(bridge.current_view, ship), [ship, station] as Array[int], "docking works both ways")
	var slot := { "part": 9, "connector": "side_c_px" }
	assert_eq(IndustryLogic.install_to(ship, slot),
		{ "unit": ship, "parent_part": 9, "parent_connector": "side_c_px", "part_connector": "mount" })


func test_the_picker_lists_checked_slots_and_builds_onto_the_ship() -> void:
	var recipe := _open_fabricator()
	sim._state["units"][station]["inventory"]["structural_frame"] = 300_000
	screen.open_picker(recipe)
	assert_true(screen._picker.visible)
	# The part alone, as before D43's "Make its components too".
	screen.picker_with.button_pressed = false
	var enabled: Array = screen._slot_buttons.filter(func(row: Dictionary) -> bool: return not row["button"].disabled)
	var refused: Array = screen._slot_buttons.filter(func(row: Dictionary) -> bool: return row["button"].disabled)
	assert_gt(enabled.size(), 0, "some spots take it")
	assert_gt(refused.size(), 0, "a stack connector doesn't take a side part")
	assert_ne(refused[0]["button"].tooltip_text, "", "a refused spot says why")
	var onto_ship: Array = enabled.filter(func(row: Dictionary) -> bool: return row["unit"] == ship)
	assert_gt(onto_ship.size(), 0)
	var parts_before := InspectText.flatten(bridge.current_view["units"][ship]["parts"]).size()
	(onto_ship[0]["button"] as Button).pressed.emit()
	assert_false(screen._picker.visible, "the picker closes once sent")
	_run(1)
	var job := IndustryLogic.job_on(bridge.current_view, screen.facility["part"])
	assert_eq(job["install_to"]["unit"], ship)
	assert_string_starts_with(screen._job_label.text, "Goods Container into %s: " % bridge.current_view["units"][ship]["name"])
	_run(ceili(float(job["energy_left_j"]) * bridge.ticks_per_second() / job["rate_w"]) + 2)
	var parts := InspectText.flatten(bridge.current_view["units"][ship]["parts"])
	assert_eq(parts.size(), parts_before + 1, "fitted to the ship")
	assert_true(parts.any(func(part: Dictionary) -> bool: return part["def"] == "goods_container_mk1"))
	assert_true(IndustryLogic.job_on(bridge.current_view, screen.facility["part"]).is_empty(), "the job is done")


func test_a_blocked_install_reads_cleanly() -> void:
	var line := OrderText.event({ "type": "job_paused", "unit": 8, "data": { "job": 3, "reason": "install_blocked",
		"detail": "over_power_budget" } }, "Station", {})
	assert_eq(line, "Station: job held. Built, but it can't be fitted there yet: %s" % OrderText.reason("over_power_budget"))
