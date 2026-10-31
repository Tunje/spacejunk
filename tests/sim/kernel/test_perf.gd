extends GutTest
## The performance budget of docs/design/perf_budget.md: every load type at once, at the
## starting load, with one view() per tick as the client would call it. Numbers go to the log.

const SHIPS := 76
const MODULES_WANTED := 1000
const SETTLE_TICKS := 40
const MEASURED_TICKS := 120
## Regression alarms at about three times the budget, because timing on a shared machine is noisy.
const MEAN_ALARM_USEC := 50_000
const SPIKE_ALARM_USEC := 100_000
const RED_ROCK := 2
const BRASS_ROCK := 4
const GREEN_ROCK := 6
const RED_DEPOSIT := 3
const FULL_TANK_G := 2_000_000
const TRANSFER_G := 200_000

var sim: Sim
var state: Dictionary
var ships: Array[Dictionary] = []


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	state = sim._state
	ships = []
	state["deposits"][RED_DEPOSIT]["found"] = true
	var partner := 0
	for i in SHIPS:
		var id := Units.create(sim._ctx, "starter_ship", "Ship %d" % i, [1_000_000 * i, 0, 0])
		_fill_batteries(id)
		Units.add_stock(state["units"][id]["inventory"], "propellant", FULL_TANK_G / 2)
		var job: String = ["move", "mine", "scan", "transfer"][i % 4]
		if job == "transfer":
			if partner == 0:
				partner = id
				job = "partner"
			else:
				_dock_to(id, partner)
				partner = 0
		ships.append({ "id": id, "job": job, "flip": false })
		match job:
			"mine":
				state["units"][id]["at_target"] = RED_ROCK
			"scan":
				state["units"][id]["at_target"] = GREEN_ROCK


func _fill_batteries(id: int) -> void:
	for part_id in Units.part_ids(state, id):
		if state["parts"][part_id].has("stored_j"):
			state["parts"][part_id]["stored_j"] = 360_000_000


func _dock_to(id: int, host: int) -> void:
	var ports := Units.ports(state, sim._ctx.defs, id)
	var host_ports := Units.ports(state, sim._ctx.defs, host)
	state["units"][id]["dock"] = { "port": ports[0], "target_unit": host, "target_port": host_ports[0] }
	state["units"][id]["pos_mm"] = state["units"][host]["pos_mm"].duplicate()
	state["units"][id]["at_target"] = host


func _laser(id: int) -> int:
	for part_id in Units.part_ids(state, id):
		if Units.module_of(state, sim._ctx.defs, part_id)["capabilities"].has("mine"):
			return part_id
	return 0


## Gives every idle unit its next order, so all load types stay busy throughout.
func _keep_busy() -> void:
	for ship: Dictionary in ships:
		var id: int = ship["id"]
		if state["units"][id]["task"] == 0:
			var order := _next_order(ship)
			if not order.is_empty():
				sim.submit({ "type": order["type"], "unit": id, "args": order["args"] })


func _next_order(ship: Dictionary) -> Dictionary:
	var id: int = ship["id"]
	var inventory: Dictionary = state["units"][id]["inventory"]
	match ship["job"]:
		"move":
			ship["flip"] = not ship["flip"]
			inventory["propellant"] = FULL_TANK_G
			return { "type": "move_to", "args": { "target": RED_ROCK if ship["flip"] else BRASS_ROCK } }
		"mine":
			inventory.erase("hematite")
			return { "type": "start_mining", "args": { "deposit": RED_DEPOSIT, "module": _laser(id) } }
		"scan":
			return { "type": "scan", "args": { "target": GREEN_ROCK } }
		"transfer":
			ship["flip"] = not ship["flip"]
			var host: int = state["units"][id]["dock"]["target_unit"]
			if ship["flip"]:
				return { "type": "load_cargo", "args": { "from": host, "item": "propellant", "grams": TRANSFER_G } }
			return { "type": "unload_cargo", "args": { "to": host, "item": "propellant", "grams": TRANSFER_G } }
	return {}


func _module_count() -> int:
	return state["parts"].size()


func _report(label: String, samples: Array[int]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0
	for sample: int in samples:
		total += sample
	var result := {
		"mean": total / samples.size(),
		"p99": sorted[samples.size() * 99 / 100],
		"max": sorted[-1],
	}
	print("PERF %s: mean %d us, p99 %d us, max %d us" % [label, result["mean"], result["p99"], result["max"]])
	return result


func test_a_full_tick_with_one_view_stays_inside_the_budget() -> void:
	assert_gte(_module_count(), MODULES_WANTED)
	for i in SETTLE_TICKS:
		_keep_busy()
		sim.step()
		sim.take_events()
	var ticks: Array[int] = []
	var views: Array[int] = []
	var both: Array[int] = []
	for i in MEASURED_TICKS:
		_keep_busy()
		var start := Time.get_ticks_usec()
		sim.step()
		var stepped := Time.get_ticks_usec()
		sim.view()
		var viewed := Time.get_ticks_usec()
		sim.take_events()
		ticks.append(stepped - start)
		views.append(viewed - stepped)
		both.append(viewed - start)
	print("PERF load: %d units, %d modules, %d tasks" % [
		state["units"].size(), _module_count(), state["tasks"].size()])
	_report("step", ticks)
	_report("view", views)
	var total := _report("step+view", both)
	assert_gt(state["tasks"].size(), SHIPS / 2, "the fleet stayed busy")
	assert_lt(total["mean"], MEAN_ALARM_USEC, "mean step and view")
	assert_lt(total["p99"], SPIKE_ALARM_USEC, "99th percentile step and view")


func test_the_measured_fleet_does_every_kind_of_work() -> void:
	var seen := {}
	for i in 60:
		_keep_busy()
		sim.step()
		for ship: Dictionary in ships:
			seen[state["units"][ship["id"]]["op"]["type"]] = true
	for op_type: String in ["moving", "mining", "scanning", "loading"]:
		assert_true(seen.has(op_type), op_type)
