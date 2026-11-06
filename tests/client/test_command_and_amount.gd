extends GutTest
## D31's rulings: every unit can be given orders, stations included, through "Take
## command of …" (selecting a station still targets it, to dock at say); and Unload
## and Load take an amount, all by default. On the real reference start.

var main: Node
var bridge: SimBridge
var view: LocalView
var panel: OrderPanel
var ship := 0
var station := 0


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = "reference"
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	view = main.local_view
	panel = main.order_panel
	for id: int in bridge.current_view["units"]:
		if bridge.current_view["units"][id]["kind"] == "station":
			station = id
		else:
			ship = id


func _step() -> void:
	bridge.set_paused(false)
	bridge.advance(1.0 / bridge.ticks_per_second())
	bridge.set_paused(true)


func test_a_station_is_targeted_on_select_and_commanded_on_request() -> void:
	view.select("unit", station, 0)
	assert_eq(view.commanded_unit, ship, "selecting it still targets it")
	assert_true(panel.take_command.visible)
	assert_eq(panel.take_command.text, "Take command of %s" % bridge.current_view["units"][station]["name"])
	panel.take_command.pressed.emit()
	assert_eq(view.commanded_unit, station)
	assert_string_starts_with(panel._commanded_label.text, "Orders: %s" % bridge.current_view["units"][station]["name"])
	assert_false(panel.take_command.visible, "it is the one in command now")


func test_auto_assigns_a_core_on_a_commanded_station() -> void:
	view.select("unit", station, 0)
	panel.take_command.pressed.emit()
	var core := 0
	for part: Dictionary in InspectText.flatten(bridge.current_view["units"][station]["parts"]):
		if bridge.defs()["modules"][part["def"]]["capabilities"].has("ai_core"):
			core = part["id"]
	assert_ne(core, 0, "the station has a core part")
	main.automation_screen.assign(core)
	_step()
	assert_eq(int(bridge.current_view["units"][station]["core"]), core, "Auto assigned the station's own core")


func test_an_amount_moves_whole_items_or_kilograms() -> void:
	var items := { "processor": { "unit_mass_g": 5000 }, "hematite": {} }
	var unload := { "type": "unload_cargo", "unit": 1, "args": { "to": 2, "item": "processor" } }
	OrderList.set_amount(unload, 10, items)
	assert_eq(unload["args"]["grams"], 50_000, "10 processors")
	var ore := { "type": "unload_cargo", "unit": 1, "args": { "to": 2, "item": "hematite" } }
	OrderList.set_amount(ore, 150, items)
	assert_eq(ore["args"]["grams"], 150_000, "150 kg")
	OrderList.set_amount(ore, 0, items)
	assert_false(ore["args"].has("grams"), "0 is all")


func test_load_moves_only_the_amount_asked() -> void:
	bridge.sim._state["units"][ship]["inventory"]["propellant"] = 0
	_step()
	view.select("", 0, 0)
	assert_true(panel._amount_row.visible, "docked, with Load on offer")
	panel.amount.value = 100
	var key := ""
	for order: Dictionary in panel._orders:
		if order["command"]["type"] == "load_cargo":
			key = order["key"]
	assert_ne(key, "")
	assert_true(panel.press(key))
	for i in 300:
		_step()
		if bridge.current_view["units"][ship]["op"]["type"] == "idle":
			break
	assert_eq(bridge.current_view["units"][ship]["inventory"].get("propellant", 0), 100_000, "100 kg, not a full tank")


func test_mine_takes_an_amount_in_kilograms() -> void:
	var mine := { "type": "start_mining", "unit": 1, "args": { "deposit": 5, "module": 9 } }
	OrderList.set_amount(mine, 350, {})
	assert_eq(mine["args"]["grams"], 350_000, "C19: 350 kg")
	OrderList.set_amount(mine, 0, {})
	assert_false(mine["args"].has("grams"), "0 mines until the hold is full")
