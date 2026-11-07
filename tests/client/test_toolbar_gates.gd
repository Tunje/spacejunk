extends GutTest
## D39: toolbar buttons greyed until useful, and "Warp past jobs" only once a job exists.

const LAB_MODULES: Dictionary = {
	"lab": { "name": "Lab", "capabilities": { "facility": { "type": "lab" } } },
	"hull": { "name": "Hull", "capabilities": {} },
}


func _new_start_main() -> Node:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	main.get_node("Bridge").set_paused(true)
	return main


func _done_until(tracker: GoalTracker, goal: String) -> void:
	for entry: Dictionary in tracker.goals:
		if entry["id"] == goal:
			return
		tracker.complete(entry["id"])


func _view(parts: Dictionary, core_tier: int) -> Dictionary:
	return { "units": { 3: { "parts": parts, "core_tier": core_tier } } }


func test_first_screen_greys_research_auto_and_policy() -> void:
	var main := _new_start_main()
	for gate: String in ToolbarGates.GATES:
		var button: Button = main.time_controls.gate_buttons[gate]
		assert_true(button.disabled, gate)
		assert_eq(button.tooltip_text, ToolbarGates.GATES[gate]["tip"], gate)


func test_a_gate_opens_when_its_goal_comes_up() -> void:
	var tracker := GoalTracker.new(Main.NEW_START)
	_done_until(tracker, "research")
	assert_true(ToolbarGates.goal_reached("research", tracker))
	assert_false(ToolbarGates.goal_reached("auto", tracker))
	assert_false(ToolbarGates.goal_reached("policy", tracker))
	_done_until(tracker, "expand")
	assert_true(ToolbarGates.goal_reached("auto", tracker))
	assert_true(ToolbarGates.goal_reached("policy", tracker), "the last goal")


## Goals can finish out of order: a done goal opens its gate even if an earlier one is open.
func test_a_done_goal_opens_its_gate() -> void:
	var tracker := GoalTracker.new(Main.NEW_START)
	tracker.complete("handover")
	assert_true(ToolbarGates.goal_reached("auto", tracker))


func test_having_what_it_needs_opens_a_gate_early() -> void:
	var bare := _view({ "id": 1, "def": "hull", "children": [] }, 1)
	assert_false(ToolbarGates.has_what_it_needs("research", bare, LAB_MODULES))
	assert_false(ToolbarGates.has_what_it_needs("auto", bare, LAB_MODULES))
	var lab := _view({ "id": 1, "def": "hull", "children": [{ "id": 2, "def": "lab", "children": [] }] }, 2)
	assert_true(ToolbarGates.has_what_it_needs("research", lab, LAB_MODULES))
	assert_true(ToolbarGates.has_what_it_needs("auto", lab, LAB_MODULES), "an Assisted Core")
	assert_false(ToolbarGates.has_what_it_needs("policy", lab, LAB_MODULES))


func test_the_station_sandbox_has_research_open() -> void:
	var main := _new_start_main()
	main.time_controls.new_game_pressed.emit(Main.REFERENCE)
	assert_false(main.time_controls.gate_buttons["research"].disabled, "the sandbox has no research goal")
	main.time_controls.new_game_pressed.emit(Main.NEW_START)
	assert_true(main.time_controls.gate_buttons["research"].disabled, "and greyed again on a new game")


func test_set_gate_opens_and_greys() -> void:
	var main := _new_start_main()
	main.time_controls.set_gate("auto", true)
	assert_false(main.time_controls.gate_buttons["auto"].disabled)
	assert_eq(main.time_controls.gate_buttons["auto"].tooltip_text, "")


func test_warp_past_jobs_shows_once_a_job_exists() -> void:
	var main := _new_start_main()
	var bridge: SimBridge = main.get_node("Bridge")
	var controls: TimeControls = main.time_controls
	assert_false(controls._through_jobs.visible, "no jobs on the first screen")
	bridge.current_view["jobs"] = { 1: {} }
	controls._refresh()
	assert_true(controls._through_jobs.visible)
	bridge.current_view["jobs"] = {}
	controls._refresh()
	assert_true(controls._through_jobs.visible, "stays once seen, so the bar doesn't jump")
	bridge.current_view["tick"] = -1
	controls._refresh()
	assert_false(controls._through_jobs.visible, "a clock gone back is a new game")
