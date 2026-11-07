extends GutTest
## A whole-unit transfer's credit stays with that transfer (task A42). A cycle keeps one task across
## its steps. Wiring moves 10 kg at a time and a port 5 kg a tick, so every other tick keeps its
## grams as credit towards the next unit. A step that ends between the two, because the stock it
## loads from is gone (another unit or a job took the rest), leaves that credit behind. Before
## A42 it was added again on every tick of the next step's bulk propellant load, which then moved
## more than the ports allow.

const STATION := 8
const ROCK := 2
const FREE_PORT := 11
const WIRING_G := 100_000

var sim: Sim
var drone := 0


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	var state := sim._state
	state["bodies"][ROCK]["pos_mm"] = [2_000_000, 0, 0]
	drone = Units.create(sim._ctx, "small_craft", "Drone", state["units"][STATION]["pos_mm"])
	var root: int = state["units"][drone]["root"]
	var tank := _fit("small_propellant_tank_mk1", root, "stack_bottom")
	_fit("small_chemical_thruster_mk1", tank, "stack_bottom")
	_fit("small_solar_panel_mk1", root, "side_a_px")
	_fit("small_heat_radiator_mk1", root, "side_a_nx")
	_fit("goods_container_mk1", root, "side_b_pz")
	state["units"][drone]["core"] = _fit("assisted_core", root, "core")
	state["units"][drone]["dock"] = { "port": Units.ports(state, sim._ctx.defs, drone)[0],
		"target_unit": STATION, "target_port": FREE_PORT }
	state["units"][drone]["at_target"] = STATION
	Units.add_stock(state["units"][STATION]["inventory"], "wiring", WIRING_G)
	sim._ctx.index.clear()
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	sim._strict = true


func _fit(def: String, parent: int, connector: String) -> int:
	var part := Units.add_part(sim._ctx, drone, def, parent, connector, "mount")
	sim._state["parts"][parent]["children"].append(part)
	return part


## The grams a tick may move through the drone's dock: the slower port's rate, rounded up a tick.
func _per_tick_g() -> int:
	var dock: Dictionary = sim._state["units"][drone]["dock"]
	var rates := []
	for port: int in [dock["port"], dock["target_port"]]:
		rates.append(Units.module_of(sim._state, sim._ctx.defs, port)["capabilities"]["port"]["transfer_g_per_s"])
	return (int(rates.min()) + Sim.TICKS_PER_SECOND - 1) / Sim.TICKS_PER_SECOND


func test_a_bulk_load_after_a_cut_short_whole_unit_load_moves_no_more_than_its_rate() -> void:
	var port: int = Units.ports(sim._state, sim._ctx.defs, drone)[0]
	var cycle := { "type": "set_cycle", "unit": drone, "args": { "steps": [
		{ "type": "load_cargo", "args": { "from": STATION, "item": "wiring" } },
		{ "type": "load_cargo", "args": { "from": STATION, "item": "propellant", "grams": 40_000 } },
		{ "type": "undock", "args": {} },
		{ "type": "move_to", "args": { "target": ROCK } },
		{ "type": "move_to", "args": { "target": STATION } },
		{ "type": "dock", "args": { "port": port, "target_port": FREE_PORT } },
	] } }
	var checked := sim.check(cycle)
	assert_true(checked["ok"], str(checked))
	sim.submit(cycle)
	var allowed := _per_tick_g()
	var unit: Dictionary = sim._state["units"][drone]
	# Into the wiring load, to a tick that kept its grams as credit.
	for n in 200:
		sim.step()
		if unit["task"] != 0 and int(sim._state["tasks"][unit["task"]].get("credit_g", 0)) > 0:
			break
	assert_gt(int(sim._state["tasks"][unit["task"]].get("credit_g", 0)), 0, "a credit built up")
	# The rest of the station's wiring goes elsewhere, so the step ends with its credit unspent.
	var station: Dictionary = sim._state["units"][STATION]["inventory"]
	sim._state["matter_start_g"] -= station["wiring"]
	Units.remove_stock(station, "wiring", station["wiring"])
	var before: int = unit["inventory"].get("propellant", 0)
	var most := 0
	var loading_ticks := 0
	for n in 6_000:
		sim.step()
		var now: int = unit["inventory"].get("propellant", 0)
		if now != before:
			most = maxi(most, now - before)
			loading_ticks += int(now != before)
		before = now
		if now >= 40_000:
			break
	assert_eq(int(unit["inventory"].get("propellant", 0)), 40_000, "the load took its amount")
	assert_gt(loading_ticks, 0)
	assert_lte(most, allowed, "no tick of the bulk load moved more than the ports allow")
	assert_false(sim._state["tasks"][unit["task"]].has("credit_g") and
		int(sim._state["tasks"][unit["task"]]["credit_g"]) != 0, "no credit carried into the bulk load")
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
	assert_eq(ledger["violations"], PackedStringArray())
