extends GutTest
## Construction: building a drone's craft (check 7), and fabricated parts going onto a station (check 9)
## and a ship (check 6). Recipes run in a few ticks here to keep the suite fast.

const STATION := 8
const HUB := 9
const FREE_PORT := 11
const SHIP_PORT := 12
const FABRICATOR := 14
const SHIP := 23
const HULL := 24
const RUN_TICKS := 3
## A full-size facility's work_per_tick, so a recipe of RUN_TICKS * FULL_RATE work takes RUN_TICKS.
const FULL_RATE := 100
const CRAFT_G := 120000
## One tick of a small craft's build: 100 kW for a tenth of a second (C30).
const CRAFT_TICK_J := 10_000
const STATION_ORE_G := 50000000

var sim: Sim
var state: Dictionary
var defs: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	defs = sim._ctx.defs
	for recipe: String in ["small_craft", "ore_storage_mk1", "heat_radiator_mk1", "assisted_core"]:
		defs["recipes"][recipe]["work"] = RUN_TICKS * FULL_RATE


## Puts a recipe's inputs for `runs` runs in the station, counted as starting matter.
func _give_inputs(recipe: String, runs: int = 1) -> void:
	for input: Dictionary in defs["recipes"][recipe]["inputs"]:
		Units.add_stock(state["units"][STATION]["inventory"], input["item"], input["grams"] * runs)
		state["matter_start_g"] += input["grams"] * runs


## Puts one of each part in the station, counted as starting matter.
func _give_parts(items: Array[String]) -> void:
	for item: String in items:
		Units.add_stock(state["units"][STATION]["inventory"], item, defs["modules"][item]["mass_g"])
		state["matter_start_g"] += defs["modules"][item]["mass_g"]


func _start(recipe: String, count: int = 1) -> Dictionary:
	return { "type": "start_job", "unit": STATION, "args": { "facility": FABRICATOR, "recipe": recipe, "count": count } }


func _attach(unit: int, item: String, parent: int, connector: String) -> Dictionary:
	return {
		"type": "attach_part", "unit": unit,
		"args": { "item": item, "from": STATION, "parent_part": parent,
			"parent_connector": connector, "part_connector": "mount" },
	}


## Docks something at the free port, so the station has none left.
func _fill_free_port() -> int:
	var id := Units.create(sim._ctx, "small_craft", "Blocker", [0, 0, 0])
	state["units"][id]["dock"] = { "port": Units.ports(state, defs, id)[0], "target_unit": STATION, "target_port": FREE_PORT }
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	return id


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


func _first(events: Array[Dictionary], type: String) -> Dictionary:
	for event in events:
		if event["type"] == type:
			return event
	fail_test("no %s event" % type)
	return {}


func _step_balanced(ticks: int) -> void:
	for i in ticks:
		sim.step()
		var matter: Dictionary = sim.ledger()["matter"]
		assert_eq(matter["total_g"], matter["start_g"], "tick %d" % sim.current_tick())
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_a_built_craft_appears_docked_with_no_core_and_no_tank() -> void:
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	_step_balanced(RUN_TICKS)
	var events := sim.take_events()
	var created := _first(events, "unit_created")
	var id: int = created["data"]["unit"]
	assert_eq(created["unit"], STATION)
	assert_eq(created["data"]["def"], "small_craft")
	assert_true(_types(events).has("job_finished"))

	var view := sim.view()
	var drone: Dictionary = view["units"][id]
	assert_eq(drone["kind"], "drone")
	assert_eq(drone["def"], "small_craft")
	assert_eq(drone["core"], 0)
	assert_eq(drone["core_tier"], 0)
	assert_eq(drone["inventory"], {})
	assert_eq(drone["mass_g"], CRAFT_G)
	assert_eq(drone["at_target"], STATION)
	assert_eq(drone["pos_mm"], view["units"][STATION]["pos_mm"])
	var port: int = drone["parts"]["children"][0]["id"]
	assert_eq(drone["parts"]["children"].size(), 1, "a hull and a port")
	assert_eq(state["parts"][port]["def"], "small_docking_port_mk1")
	assert_eq(drone["dock"], { "port": port, "target_unit": STATION, "target_port": FREE_PORT })
	assert_eq(drone["cargo"].get("propellant", {}).get("cap_g", 0), 0)
	assert_eq(view["jobs"].size(), 0)



## Docks the station by its free port to a second station, so the builder has no free port of its own.
func _dock_station_to_host() -> int:
	var host := Units.create(sim._ctx, "starter_station", "Host", state["units"][STATION]["pos_mm"])
	var host_ports := Units.ports(state, defs, host)
	state["units"][STATION]["dock"] = { "port": FREE_PORT, "target_unit": host, "target_port": host_ports[0] }
	sim._ctx.index.clear()
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	assert_gt(host_ports.size(), 1, "the host has a spare port")
	for port: int in Units.ports(state, defs, STATION):
		assert_true(Units.port_in_use(state, port), "the builder's ports are all taken")
	return host


func test_a_builder_with_no_free_port_builds_onto_the_unit_it_is_docked_to() -> void:
	var host := _dock_station_to_host()
	var spare: int = Units.ports(state, defs, host)[1]
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	_step_balanced(RUN_TICKS)
	var created := _first(sim.take_events(), "unit_created")
	assert_eq(created["unit"], STATION, "reported by the builder")
	var id: int = created["data"]["unit"]
	var drone: Dictionary = sim.view()["units"][id]
	assert_eq(drone["dock"], { "port": Units.ports(state, defs, id)[0], "target_unit": host, "target_port": spare })
	assert_eq(drone["at_target"], host)
	assert_false(state["parts"][spare].has("claimed_by"))


func test_with_no_free_port_on_the_builder_or_its_host_the_run_waits() -> void:
	var host := _dock_station_to_host()
	var blocker := Units.create(sim._ctx, "small_craft", "Blocker", [0, 0, 0])
	state["units"][blocker]["dock"] = {
		"port": Units.ports(state, defs, blocker)[0], "target_unit": host, "target_port": Units.ports(state, defs, host)[1],
	}
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	_step_balanced(RUN_TICKS + 2)
	var shown: Dictionary = sim.view()["jobs"].values()[0]
	assert_eq([shown["status"], shown["reason"]], ["paused", "no_free_port"])
	assert_false(_types(sim.take_events()).has("unit_created"))

func test_building_moves_the_inputs_into_installed_parts() -> void:
	_give_inputs("small_craft")
	var installed: int = sim.ledger()["matter"]["installed_g"]
	sim.submit(_start("small_craft"))
	_step_balanced(1)
	assert_eq(sim.ledger()["matter"]["jobs_g"], CRAFT_G)
	_step_balanced(RUN_TICKS - 1)
	assert_eq(sim.ledger()["matter"]["jobs_g"], 0)
	assert_eq(sim.ledger()["matter"]["installed_g"], installed + CRAFT_G)


func test_a_built_unit_runs_on_the_next_ticks() -> void:
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	sim.step(RUN_TICKS)
	var id: int = _first(sim.take_events(), "unit_created")["data"]["unit"]
	_step_balanced(2)
	assert_eq(sim.view()["units"][id]["heat"]["limit_j"], 5000000, "the index sees the new unit")


func test_the_port_is_claimed_only_on_the_tick_the_run_ends() -> void:
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	sim.step(RUN_TICKS - 1)
	assert_false(state["parts"][FREE_PORT].has("claimed_by"), "free for the whole build")
	sim.step()
	assert_false(state["parts"][FREE_PORT].has("claimed_by"), "the claim ends with the docking")
	assert_true(Units.port_in_use(state, FREE_PORT))


func test_with_no_free_port_the_run_waits_with_its_inputs_held() -> void:
	var blocker := _fill_free_port()
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	sim.step(RUN_TICKS - 1)
	var job: int = sim.view()["jobs"].keys()[0]
	assert_eq(sim.view()["jobs"][job]["status"], "running")
	_step_balanced(5)
	var shown: Dictionary = sim.view()["jobs"][job]
	assert_eq(shown["status"], "paused")
	assert_eq(shown["reason"], "no_free_port")
	assert_eq(shown["energy_left_j"], CRAFT_TICK_J, "held with its last tick of work still to do")
	assert_eq(sim.ledger()["matter"]["jobs_g"], CRAFT_G)
	assert_eq(state["jobs"][job]["since_tick"], RUN_TICKS)
	var events := sim.take_events()
	assert_eq(_types(events).count("job_paused"), 1, "reported once")
	assert_false(_types(events).has("unit_created"))
	assert_eq(state["units"][STATION]["demand_w"], 7000, "a waiting build draws nothing")

	state["units"][blocker]["dock"] = {}
	_step_balanced(1)
	events = sim.take_events()
	assert_eq(_first(events, "job_resumed")["data"]["reason"], "no_free_port")
	assert_true(_types(events).has("unit_created"))
	assert_eq(sim.view()["jobs"].size(), 0)


func test_a_faulted_port_is_not_free() -> void:
	state["parts"][FREE_PORT]["fault"] = "test_fault"
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	sim.step(RUN_TICKS)
	var job: int = sim.view()["jobs"].keys()[0]
	assert_eq(sim.view()["jobs"][job]["reason"], "no_free_port")


func test_cancelling_a_build_waiting_for_a_port_returns_its_inputs() -> void:
	_fill_free_port()
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	sim.step(RUN_TICKS)
	sim.submit({ "type": "cancel_job", "unit": STATION, "args": { "job": sim.view()["jobs"].keys()[0] } })
	_step_balanced(1)
	assert_eq(sim.view()["jobs"].size(), 0)
	assert_eq(sim.ledger()["matter"]["jobs_g"], 0)
	assert_eq(state["units"][STATION]["inventory"]["structural_frame"], 100000)


func test_cancelling_a_claimed_port_releases_it() -> void:
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	sim.step(RUN_TICKS - 2)
	var job: int = sim.view()["jobs"].keys()[0]
	state["parts"][FABRICATOR]["shed"] = true
	state["parts"][FABRICATOR]["shed_until_tick"] = 1000
	state["jobs"][job]["energy_left_j"] = CRAFT_TICK_J
	sim.step()
	assert_eq(state["jobs"][job]["port"], FREE_PORT, "claimed, but the facility has no power")
	sim.submit({ "type": "cancel_job", "unit": STATION, "args": { "job": job } })
	_step_balanced(1)
	assert_false(state["parts"][FREE_PORT].has("claimed_by"))


func test_a_build_shed_on_its_last_tick_finishes_when_power_returns() -> void:
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	sim.step(RUN_TICKS - 2)
	var job: int = sim.view()["jobs"].keys()[0]
	state["parts"][FABRICATOR]["shed"] = true
	state["parts"][FABRICATOR]["shed_until_tick"] = sim.current_tick() + 3
	state["jobs"][job]["energy_left_j"] = CRAFT_TICK_J
	_step_balanced(5)
	assert_true(_types(sim.take_events()).has("unit_created"))


func test_a_second_drone_waits_when_the_first_takes_the_last_port() -> void:
	_give_inputs("small_craft", 2)
	var job_id := sim.submit(_start("small_craft", 2))
	assert_gt(job_id, 0)
	sim.step(RUN_TICKS * 2)
	var events := sim.take_events()
	assert_eq(_types(events).count("unit_created"), 1)
	assert_eq(sim.view()["jobs"].values()[0]["reason"], "no_free_port")


func test_a_new_drone_takes_a_core_and_has_it_fitted_without_one() -> void:
	_give_inputs("small_craft")
	_give_parts(["small_solar_panel_mk1", "small_heat_radiator_mk1", "assisted_core"])
	sim.submit(_start("small_craft"))
	sim.step(RUN_TICKS)
	var id: int = _first(sim.take_events(), "unit_created")["data"]["unit"]
	var hull: int = state["units"][id]["root"]
	var command := _attach(id, "assisted_core", hull, "core")
	assert_eq(_warnings(sim.check(command)), ["over_power_budget", "over_heat_budget"],
		"a core draws power and gives off heat too, but it fits (C30)")
	sim.submit(_attach(id, "small_solar_panel_mk1", hull, "side_a_px"))
	sim.submit(_attach(id, "small_heat_radiator_mk1", hull, "side_a_nx"))
	_step_balanced(1)
	sim.take_events()
	assert_eq(_warnings(sim.check(command)), [])
	sim.submit(command)
	_step_balanced(1)
	assert_eq(_types(sim.take_events()), ["part_attached"])
	assert_eq(sim.view()["units"][id]["mass_g"], CRAFT_G + 190000)


## C30: the fits go through, warned, until the craft has the power and radiators for them.
func test_a_bare_craft_is_warned_off_a_laser_or_thruster_until_it_has_a_budget() -> void:
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	sim.step(RUN_TICKS)
	var id: int = _first(sim.take_events(), "unit_created")["data"]["unit"]
	var hull: int = state["units"][id]["root"]
	_give_parts([
		"small_solar_panel_mk1", "small_heat_radiator_mk1", "small_mining_laser_mk1", "small_chemical_thruster_mk1",
	])
	var laser := _attach(id, "small_mining_laser_mk1", hull, "side_a_nz")
	var thruster := _attach(id, "small_chemical_thruster_mk1", hull, "stack_bottom")
	assert_true(_warnings(sim.check(laser)).has("over_power_budget"))
	assert_true(_warnings(sim.check(thruster)).has("over_power_budget"))
	sim.submit(_attach(id, "small_solar_panel_mk1", hull, "side_a_px"))
	_step_balanced(1)
	assert_eq(_warnings(sim.check(laser)), ["over_heat_budget"])
	assert_eq(_warnings(sim.check(thruster)), ["over_heat_budget"])
	sim.submit(_attach(id, "small_heat_radiator_mk1", hull, "side_a_nx"))
	_step_balanced(1)
	assert_eq(_warnings(sim.check(laser)), [])
	assert_eq(_warnings(sim.check(thruster)), [])


## The codes of a check that went through with warnings (C30); fails if the check was refused.
func _warnings(result: Dictionary) -> Array:
	assert_true(result["ok"], "allowed: %s" % result.get("reason", ""))
	return result.get("detail", {}).get("warnings", []).map(func(warning: Dictionary) -> String: return warning["code"])


## Check 9: output from the industry chain becomes a larger station.
func test_a_fabricated_module_expands_the_station() -> void:
	_give_inputs("ore_storage_mk1")
	assert_eq(sim.view()["units"][STATION]["cargo"]["ore"]["cap_g"], STATION_ORE_G)
	sim.submit(_start("ore_storage_mk1"))
	_step_balanced(RUN_TICKS)
	assert_eq(state["units"][STATION]["inventory"]["ore_storage_mk1"], 1000000)
	sim.take_events()
	sim.submit(_attach(STATION, "ore_storage_mk1", HUB, "side_c_px"))
	_step_balanced(1)
	assert_eq(_types(sim.take_events()), ["part_attached"])
	assert_eq(sim.view()["units"][STATION]["cargo"]["ore"]["cap_g"], STATION_ORE_G * 2)


## Check 6: a fabricated module goes onto the docked ship.
func test_a_fabricated_module_installs_on_a_docked_ship() -> void:
	_give_inputs("heat_radiator_mk1")
	var before: int = sim.view()["units"][SHIP]["heat"]["reject_w"]
	sim.submit(_start("heat_radiator_mk1"))
	sim.step(RUN_TICKS)
	sim.take_events()
	sim.submit(_attach(SHIP, "heat_radiator_mk1", HULL, "side_c_nx"))
	_step_balanced(1)
	assert_eq(_types(sim.take_events()), ["part_attached"])
	assert_eq(sim.view()["units"][SHIP]["heat"]["reject_w"], before + 200000)
	assert_false(state["units"][STATION]["inventory"].has("heat_radiator_mk1"))


## Saves now, loads it with this test's definitions, applies `change` to both games, and requires
## both to run on identically. The state keeps the real data hash, so the load is accepted.
func _assert_load_resumes(change: Callable, ticks: int = 8) -> void:
	sim.take_events()
	var loaded := Sim.from_save(sim.to_save())
	assert_not_null(loaded)
	loaded._ctx.defs = defs
	assert_eq(loaded.to_save(), sim.to_save(), "round trip")
	change.call(sim)
	change.call(loaded)
	sim.step(ticks)
	loaded.step(ticks)
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_eq(loaded.take_events(), sim.take_events(), "the same events")


func test_a_load_finishes_a_build_waiting_for_a_port() -> void:
	var blocker := _fill_free_port()
	_give_inputs("small_craft")
	sim.submit(_start("small_craft"))
	sim.step(RUN_TICKS + 1)
	assert_eq(sim.view()["jobs"].values()[0]["reason"], "no_free_port")
	_assert_load_resumes(func(game: Sim) -> void: game._state["units"][blocker]["dock"] = {})
	assert_eq(sim.view()["jobs"].size(), 0, "the unit was built")

