extends GutTest
## Jobs on the real Sim, through the real screen.

const MAX_FRAMES := 6000

var main: Node
var bridge: SimBridge
var view: LocalView
var panel: OrderPanel
var screen: IndustryScreen
var ship: int
var station: int
var rock: int
var defs: Dictionary


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	bridge.set_speed(8)
	view = main.get_node("LocalView")
	panel = main.order_panel
	screen = main.industry_screen
	defs = bridge.defs()
	var state := bridge.current_view
	for id: int in state["units"]:
		if state["units"][id]["kind"] == "ship":
			ship = id
		else:
			station = id
	for id: int in state["bodies"]:
		if state["bodies"][id]["name"] == "Red Rock":
			rock = id


func _run_ticks(ticks: int) -> void:
	bridge.set_paused(false)
	for i in range(ceili(ticks / 8.0)):
		bridge.advance(0.1)
	bridge.set_paused(true)
	view.refresh(0.016)


func _run_order() -> void:
	bridge.set_paused(false)
	bridge.advance(0.1)
	var frames := 0
	while bridge.current_view["units"][ship]["op"]["type"] != "idle" and frames < MAX_FRAMES:
		bridge.advance(0.1)
		frames += 1
	bridge.set_paused(true)
	view.refresh(0.016)
	panel.refresh()


func _press_first(prefix: String) -> void:
	for key: String in panel._buttons:
		if key.begins_with(prefix) and not panel._buttons[key].disabled:
			panel.press(key)
			return
	fail_test("no enabled %s order" % prefix)


func _bring_ore_home() -> void:
	panel.press("Undock")
	_run_order()
	view.select("body", rock, 0)
	panel.press("Move to")
	_run_order()
	panel.press("Scan")
	_run_order()
	view.select("body", rock, 0)
	_press_first("Mine ")
	_run_ticks(1200)
	panel.press("Stop")
	_run_ticks(8)
	view.select("unit", station, 0)
	panel.press("Move to")
	_run_order()
	panel.press("Dock")
	_run_order()
	_press_first("Unload ")
	_run_order()


func _open_on(facility_type: String) -> void:
	main.toggle_industry()
	for entry: Dictionary in IndustryLogic.facilities(bridge.current_view["units"][station], defs["modules"]):
		if entry["type"] == facility_type:
			screen.choose_facility(entry)


func _recipe(id: String) -> Dictionary:
	return defs["recipes"][id]


func _refinery_recipe() -> Dictionary:
	return IndustryLogic.recipes_for("refinery", defs["recipes"])[0]


func test_the_station_is_the_working_unit_with_two_facilities() -> void:
	main.toggle_industry()
	assert_eq(screen.unit_id, station)
	var types: Array = IndustryLogic.facilities(bridge.current_view["units"][station], defs["modules"]).map(
		func(entry: Dictionary) -> String: return entry["type"])
	assert_has(types, "refinery")
	assert_has(types, "fabricator")


func test_each_tab_lists_only_its_recipes() -> void:
	_open_on("refinery")
	var refinery_rows: int = screen._rows.size()
	assert_gt(refinery_rows, 0)
	for row: Dictionary in screen._rows:
		assert_eq(row["recipe"]["facility"], "refinery")
	for entry: Dictionary in IndustryLogic.facilities(bridge.current_view["units"][station], defs["modules"]):
		if entry["type"] == "fabricator":
			screen.choose_facility(entry)
	assert_eq(screen._rows[0]["recipe"]["facility"], "fabricator")


func test_a_job_without_stock_waits_and_says_why() -> void:
	_open_on("refinery")
	screen.start(_refinery_recipe())
	_run_ticks(8)
	screen.refresh()
	assert_string_contains(screen._job_label.text, "Waiting")
	assert_string_contains(screen._job_label.text, "Missing inputs")
	assert_false(screen._cancel_button.disabled)


## C9: on a busy facility, Start queues the job instead of refusing it.
func test_a_busy_facility_queues_a_second_job() -> void:
	_open_on("refinery")
	screen.start(_refinery_recipe())
	_run_ticks(8)
	var queue_check: Dictionary = bridge.check(IndustryLogic.start_command(screen.unit_id, screen.facility["part"], _refinery_recipe(), 1, false))
	if queue_check["reason"] == "unknown_command":
		pending("The real Sim has no queue_job until C9 lands")
		return
	screen.start(_refinery_recipe())
	_run_ticks(8)
	assert_eq(screen._message.text, "")
	assert_eq(IndustryLogic.queue_on(bridge.current_view, screen.facility["part"]).size(), 2)


func test_cancelling_clears_the_job() -> void:
	_open_on("refinery")
	screen.start(_refinery_recipe())
	_run_ticks(8)
	screen.refresh()
	screen.cancel()
	_run_ticks(16)
	screen.refresh()
	assert_eq(screen._job_label.text, "Idle")
	assert_true(screen._cancel_button.disabled)


func test_real_ore_refines_through_the_screen() -> void:
	_bring_ore_home()
	var stock: Dictionary = bridge.current_view["units"][station]["inventory"]
	var ore_item: String = ""
	for item: String in stock:
		if defs["items"][item]["cargo_class"] == "ore":
			ore_item = item
	assert_ne(ore_item, "", "ore reached the station")
	var chosen: Dictionary = {}
	for recipe: Dictionary in IndustryLogic.recipes_for("refinery", defs["recipes"]):
		if IndustryLogic.has_inputs(recipe, stock):
			chosen = recipe
	assert_false(chosen.is_empty(), "a recipe can run on that ore: %s" % str(stock))
	if chosen.is_empty():
		return
	_open_on("refinery")
	var row_found := false
	for row: Dictionary in screen._rows:
		if row["recipe"]["id"] == chosen["id"]:
			row_found = true
			assert_eq((row["inputs"] as Label).modulate, Color.WHITE, "inputs shown as present")
	assert_true(row_found)
	screen.start(chosen)
	_run_ticks(16)
	screen.refresh()
	assert_string_contains(screen._job_label.text, "Running")
	assert_gt(screen._job_bar.value, 0.0)
	var rate: int = defs["modules"]["ore_refinery_mk1"]["capabilities"]["facility"]["work_per_tick"]
	_run_ticks(IndustryLogic.run_ticks(chosen["work"], rate) + 16)
	screen.refresh()
	var after: Dictionary = bridge.current_view["units"][station]["inventory"]
	for output: Dictionary in chosen["outputs"]:
		if output.has("item") and not output.has("sink"):
			assert_gt(after.get(output["item"], 0), 0, output["item"])
	print("REAL_JOB %s work=%d" % [chosen["id"], chosen["work"]])


func test_screen_swaps_with_fitting_and_restores_orders() -> void:
	main.toggle_industry()
	assert_true(panel.visible, "orders stay reachable")
	main.toggle_fitting()
	assert_false(screen.visible)
	assert_true(main.fitting_screen.visible)
	assert_true(panel.visible)
	main.toggle_industry()
	assert_false(main.fitting_screen.visible)
	assert_true(screen.visible)


func test_the_key_and_escape_work() -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_J
	main._unhandled_key_input(key)
	assert_true(screen.visible)
	key.physical_keycode = KEY_ESCAPE
	main._unhandled_key_input(key)
	assert_false(screen.visible)


func test_text_helpers() -> void:
	var job := { "recipe": "iron", "status": "paused", "reason": "no_power", "count_left": 3, "start_tick": 0,
		"queue_pos": 0, "work_left": 0, "work": 3000, "work_per_tick": 100 }
	assert_eq(IndustryLogic.job_line(job, defs, 10.0), "Iron: Paused, Not enough power (3 left)")
	assert_eq(IndustryLogic.job_progress(job), 0.0, "no run under way")
	assert_eq(IndustryLogic.name_of("no_such_thing", defs), "No Such Thing")


## D23: progress and time come from work points, not ticks.
func test_progress_and_time_left_come_from_work() -> void:
	var job := { "recipe": "iron", "status": "running", "reason": "", "count_left": 1, "start_tick": 0,
		"queue_pos": 0, "work_left": 750, "work": 3000, "work_per_tick": 100 }
	assert_almost_eq(IndustryLogic.job_progress(job), 0.75, 0.001)
	assert_eq(IndustryLogic.seconds_left(job, 10.0), 0.8, "ceil(750 / 100) = 8 ticks")
	assert_eq(IndustryLogic.job_line(job, defs, 10.0), "Iron: Running, about 1 s")
	job["work_left"] = 2000
	assert_eq(IndustryLogic.job_line(job, defs, 10.0), "Iron: Running, about 2 s")
	# A paused run keeps its place and gives no time, since it isn't moving.
	job["status"] = "paused"
	job["reason"] = "no_power"
	assert_almost_eq(IndustryLogic.job_progress(job), 1.0 / 3.0, 0.001)
	assert_eq(IndustryLogic.seconds_left(job, 10.0), 0.0)
	# A half-rate facility takes twice as long; spare work on the last tick is lost.
	job["status"] = "running"
	job["work_per_tick"] = 50
	assert_eq(IndustryLogic.seconds_left(job, 10.0), 4.0)
	assert_eq(IndustryLogic.run_ticks(3000, 70), 43)
	assert_eq(IndustryLogic.run_ticks(3000, 0), 0)


func test_a_queued_job_shows_all_its_runs() -> void:
	var job := { "recipe": "iron", "status": "queued", "reason": "", "count_left": 4, "start_tick": 0,
		"queue_pos": 2, "work_left": 0, "work": 3000, "work_per_tick": 100 }
	assert_eq(IndustryLogic.seconds_left(job, 10.0), 12.0, "4 runs of 30 ticks")
	assert_eq(IndustryLogic.job_line(job, defs, 10.0), "Iron: Queued (4 left), about 12 s")
	assert_eq(IndustryLogic.queue_line(job, defs, 10.0), "Iron (4 left), about 12 s", "the queue says queued")


func test_no_facilities_gives_no_working_unit() -> void:
	var state := { "units": { 1: { "dock": {}, "parts": { "id": 2, "def": "starter_hull", "children": [] } } } }
	assert_eq(IndustryLogic.working_unit(state, defs["modules"], "", 0, 1), 0)
