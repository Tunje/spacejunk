class_name PanelPlayer extends RefCounted
## Plays the reference scenario through the real panels, pressing only what a
## player can press: no stock is poked and no command is built by hand. Records
## what happened, so tests assert on one shared run, as ReferenceBot does.

const MAX_ADVANCES := 4000
const FRAME_SECONDS := 0.1

var main: Node
var bridge: SimBridge
var view: LocalView
var orders: OrderPanel
var fitting: FittingScreen
var industry: IndustryScreen
var automation: AutomationScreen
var goals: GoalTracker
var ship := 0
var station := 0
var drone := 0
var rocks: Dictionary = {}
var problems := PackedStringArray()
## Goal IDs in the order they finished.
var goal_order: Array[String] = []
var refusal := ""
var laps := 0


func _init(new_main: Node) -> void:
	main = new_main
	bridge = main.get_node("Bridge")
	view = main.get_node("LocalView")
	orders = main.order_panel
	fitting = main.fitting_screen
	industry = main.industry_screen
	automation = main.automation_screen
	goals = main.goal_panel.tracker
	bridge.set_paused(true)
	bridge.set_speed(SimBridge.SPEEDS[-1])
	bridge.events_received.connect(_on_events)
	var state := bridge.current_view
	for id: int in state["units"]:
		if state["units"][id]["kind"] == "ship":
			ship = id
		else:
			station = id
	for id: int in state["bodies"]:
		rocks[state["bodies"][id]["name"]] = id


func run() -> void:
	_trip("Brass Rock", "Chalcopyrite Ore")
	_trip("Green Rock", "Olivine Ore")
	_trip("Red Rock", "Hematite Ore")
	_trip("Red Rock", "Hematite Ore")
	_job("refinery", "refine_hematite", 26)
	_job("refinery", "refine_chalcopyrite", 10)
	_job("refinery", "refine_olivine", 6)
	_job("fabricator", "structural_frame", 35)
	_job("fabricator", "wiring", 21)
	_job("fabricator", "processor", 24)
	_job("fabricator", "heat_radiator_mk1", 1)
	_job("fabricator", "mining_laser_mk1", 1)
	_fail_then_fix_the_fit()
	_job("fabricator", "ore_storage_mk1", 1)
	_expand_the_station()
	_job("fabricator", "mining_drone", 1)
	_find_the_drone()
	_job("fabricator", "basic_core", 1)
	_job("fabricator", "assisted_core", 1)
	_hand_over_to_the_drone()


func unit(id: int) -> Dictionary:
	return bridge.current_view["units"].get(id, {})


func _problem(text: String) -> void:
	problems.append("tick %d: %s" % [bridge.current_view["tick"], text])


func _on_events(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		match event["type"]:
			"task_cycle_done":
				laps += 1
			"command_rejected", "attach_failed":
				_problem("%s: %s" % [event["type"], event["data"]["reason"]])
			"task_blocked":
				_problem("task blocked: %s" % event["data"]["reason"])
	for id: String in goals.done:
		if not goal_order.has(id):
			goal_order.append(id)


func _advance_until(done: Callable, label: String) -> bool:
	bridge.set_paused(false)
	var count := 0
	while not done.call() and count < MAX_ADVANCES:
		bridge.advance(FRAME_SECONDS)
		count += 1
	bridge.set_paused(true)
	view.refresh(0.016)
	orders.refresh()
	if count >= MAX_ADVANCES:
		_problem("timed out: %s" % label)
		return false
	return true


func _settle(ship_id: int, label: String) -> void:
	bridge.set_paused(false)
	bridge.advance(FRAME_SECONDS)
	_advance_until(func() -> bool: return unit(ship_id)["op"]["type"] == "idle", label)


func _press(key: String) -> bool:
	if not orders.press(key):
		_problem("order not available: %s" % key)
		return false
	return true


func _order(key: String) -> void:
	if _press(key):
		_settle(view.commanded_unit, key)


func _trip(rock_name: String, ore_name: String) -> void:
	view.select("unit", ship, 0)
	_order("Undock")
	var rock: int = rocks[rock_name]
	view.select("body", rock, 0)
	_order("Move to")
	if not bridge.current_view["bodies"][rock]["scanned"]:
		_order("Scan")
	view.select("body", rock, 0)
	_mine_on(rock)
	view.select("unit", station, 0)
	_order("Move to")
	_order("Dock")
	view.select("unit", ship, 0)
	_order("Unload %s" % ore_name)


func _mine_on(rock: int) -> void:
	var state: Dictionary = bridge.current_view
	for id: int in state["deposits"]:
		if state["deposits"][id]["body"] == rock:
			_order("Mine %d" % id)
			return
	_problem("no deposit shown on rock %d" % rock)


## Starts a job with the Jobs screen and waits for it to leave the view.
func _job(facility_type: String, recipe: String, runs: int) -> void:
	main.toggle_industry()
	var chosen := false
	for entry: Dictionary in IndustryLogic.facilities(unit(station), bridge.defs()["modules"]):
		if entry["type"] == facility_type:
			industry.choose_facility(entry)
			chosen = true
	if not chosen:
		_problem("no %s tab" % facility_type)
	industry._count.value = runs
	var started := false
	for row: Dictionary in industry._rows:
		if row["recipe"]["id"] == recipe:
			(row["start"] as Button).pressed.emit()
			started = true
	if not started:
		_problem("no %s row" % recipe)
	if not industry._message.text.is_empty():
		_problem("%s refused: %s" % [recipe, industry._message.text])
	main.toggle_industry()
	bridge.set_paused(false)
	bridge.advance(FRAME_SECONDS)
	_advance_until(func() -> bool: return bridge.current_view["jobs"].is_empty(), recipe)


func _open_fitting(target: int) -> void:
	view.select("unit", target, 0)
	main.toggle_fitting()


func _pick_part(item: String) -> void:
	var name_text: String = bridge.defs()["modules"][item]["name"]
	for button: Node in fitting._stock_box.get_children():
		if button is Button and (button as Button).text.begins_with(name_text):
			(button as Button).pressed.emit()
			return
	_problem("no stock button for %s" % item)


func _pick_slot(connector: String) -> void:
	for slot: Dictionary in FittingLogic.free_slots(fitting.unit(), fitting._modules):
		if slot["connector"] == connector:
			fitting.choose_slot(slot)
			return
	_problem("no free slot %s" % connector)


func _attach() -> void:
	if fitting._attach_button.disabled:
		_problem("attach disabled: %s" % fitting._verdict.text)
		return
	fitting._attach_button.pressed.emit()
	bridge.set_paused(false)
	bridge.advance(FRAME_SECONDS)
	bridge.set_paused(true)
	fitting.refresh()


## Check 10: the second laser is refused on heat, and one radiator fixes it.
func _fail_then_fix_the_fit() -> void:
	_open_fitting(ship)
	_pick_part("mining_laser_mk1")
	_pick_slot("side_b_nz")
	refusal = fitting._verdict.text
	if not fitting._attach_button.disabled:
		_problem("the second laser was not refused")
	_pick_part("heat_radiator_mk1")
	_pick_slot("side_c_nx")
	_attach()
	_pick_part("mining_laser_mk1")
	_pick_slot("side_b_nz")
	_attach()
	main.toggle_fitting()


func _expand_the_station() -> void:
	_open_fitting(station)
	_pick_part("ore_storage_mk1")
	_pick_slot("side_c_px")
	_attach()
	main.toggle_fitting()


func _find_the_drone() -> void:
	var state: Dictionary = bridge.current_view
	for id: int in state["units"]:
		if state["units"][id]["kind"] == "drone":
			drone = id
	if drone == 0:
		_problem("no drone in the view")


## Check 8: fit the core, use it, and repeat the route flown by hand.
func _hand_over_to_the_drone() -> void:
	if drone == 0:
		return
	_open_fitting(drone)
	_pick_part("assisted_core")
	_pick_slot("core")
	_attach()
	main.toggle_fitting()
	main.toggle_automation()
	view.select("unit", drone, 0)
	automation.refresh()
	var use_button: Button = null
	for child: Node in automation._core_box.get_children():
		if child is Button:
			use_button = child
	if use_button == null:
		_problem("no core button on the drone")
		return
	use_button.pressed.emit()
	bridge.set_paused(false)
	bridge.advance(FRAME_SECONDS)
	bridge.set_paused(true)
	automation.refresh()
	automation._repeat_button.pressed.emit()
	if not automation._message.text.is_empty():
		_problem("repeat refused: %s" % automation._message.text)
	bridge.set_paused(false)
	bridge.advance(FRAME_SECONDS)
	_advance_until(func() -> bool: return laps >= 1, "the drone's first lap")
