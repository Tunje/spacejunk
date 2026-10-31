extends GutTest
## Construction: building the drone (check 7), and fabricated parts going onto a station (check 9)
## and a ship (check 6). Recipes run in a few ticks here to keep the suite fast.

const STATION := 8
const HUB := 9
const FREE_PORT := 11
const SHIP_PORT := 12
const FABRICATOR := 14
const SHIP := 23
const HULL := 24
const RUN_TICKS := 3
const DRONE_G := 520000
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
	for recipe: String in ["mining_drone", "ore_storage_mk1", "heat_radiator_mk1", "assisted_core"]:
		defs["recipes"][recipe]["ticks"] = RUN_TICKS


## Puts a recipe's inputs for `runs` runs in the station, counted as starting matter.
func _give_inputs(recipe: String, runs: int = 1) -> void:
	for input: Dictionary in defs["recipes"][recipe]["inputs"]:
		Units.add_stock(state["units"][STATION]["inventory"], input["item"], input["grams"] * runs)
		state["matter_start_g"] += input["grams"] * runs


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
	var id := Units.create(sim._ctx, "mining_drone", "Blocker", [0, 0, 0])
	state["units"][id]["dock"] = { "port": state["units"][id]["root"], "target_unit": STATION, "target_port": FREE_PORT }
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


func test_a_built_drone_appears_docked_with_no_core_and_an_empty_tank() -> void:
	_give_inputs("mining_drone")
	sim.submit(_start("mining_drone"))
	_step_balanced(RUN_TICKS)
	var events := sim.take_events()
	var created := _first(events, "unit_created")
	var id: int = created["data"]["unit"]
	assert_eq(created["unit"], STATION)
	assert_eq(created["data"]["def"], "mining_drone")
	assert_true(_types(events).has("job_finished"))

	var view := sim.view()
	var drone: Dictionary = view["units"][id]
	assert_eq(drone["kind"], "drone")
	assert_eq(drone["def"], "mining_drone")
	assert_eq(drone["core"], 0)
	assert_eq(drone["core_tier"], 0)
	assert_eq(drone["inventory"], {})
	assert_eq(drone["mass_g"], DRONE_G)
	assert_eq(drone["at_target"], STATION)
	assert_eq(drone["pos_mm"], view["units"][STATION]["pos_mm"])
	assert_eq(drone["dock"], { "port": drone["parts"]["id"], "target_unit": STATION, "target_port": FREE_PORT })
	assert_eq(view["jobs"].size(), 0)


func test_building_moves_the_inputs_into_installed_parts() -> void:
	_give_inputs("mining_drone")
	var installed: int = sim.ledger()["matter"]["installed_g"]
	sim.submit(_start("mining_drone"))
	_step_balanced(1)
	assert_eq(sim.ledger()["matter"]["jobs_g"], DRONE_G)
	_step_balanced(RUN_TICKS - 1)
	assert_eq(sim.ledger()["matter"]["jobs_g"], 0)
	assert_eq(sim.ledger()["matter"]["installed_g"], installed + DRONE_G)


func test_a_built_unit_runs_on_the_next_ticks() -> void:
	_give_inputs("mining_drone")
	sim.submit(_start("mining_drone"))
	sim.step(RUN_TICKS)
	var id: int = _first(sim.take_events(), "unit_created")["data"]["unit"]
	_step_balanced(2)
	assert_eq(sim.view()["units"][id]["power"]["supply_w"], 30000, "the index sees the new unit")


func test_the_port_is_claimed_only_on_the_tick_the_run_ends() -> void:
	_give_inputs("mining_drone")
	sim.submit(_start("mining_drone"))
	sim.step(RUN_TICKS - 1)
	assert_false(state["parts"][FREE_PORT].has("claimed_by"), "free for the whole build")
	sim.step()
	assert_false(state["parts"][FREE_PORT].has("claimed_by"), "the claim ends with the docking")
	assert_true(Units.port_in_use(state, FREE_PORT))


func test_with_no_free_port_the_run_waits_with_its_inputs_held() -> void:
	var blocker := _fill_free_port()
	_give_inputs("mining_drone")
	sim.submit(_start("mining_drone"))
	sim.step(RUN_TICKS - 1)
	var job: int = sim.view()["jobs"].keys()[0]
	assert_eq(sim.view()["jobs"][job]["status"], "running")
	_step_balanced(5)
	var shown: Dictionary = sim.view()["jobs"][job]
	assert_eq(shown["status"], "paused")
	assert_eq(shown["reason"], "no_free_port")
	assert_eq(shown["end_tick"], 0)
	assert_eq(sim.ledger()["matter"]["jobs_g"], DRONE_G)
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
	_give_inputs("mining_drone")
	sim.submit(_start("mining_drone"))
	sim.step(RUN_TICKS)
	var job: int = sim.view()["jobs"].keys()[0]
	assert_eq(sim.view()["jobs"][job]["reason"], "no_free_port")


func test_cancelling_a_build_waiting_for_a_port_returns_its_inputs() -> void:
	_fill_free_port()
	_give_inputs("mining_drone")
	sim.submit(_start("mining_drone"))
	sim.step(RUN_TICKS)
	sim.submit({ "type": "cancel_job", "unit": STATION, "args": { "job": sim.view()["jobs"].keys()[0] } })
	_step_balanced(1)
	assert_eq(sim.view()["jobs"].size(), 0)
	assert_eq(sim.ledger()["matter"]["jobs_g"], 0)
	assert_eq(state["units"][STATION]["inventory"]["structural_frame"], 400000)


func test_cancelling_a_claimed_port_releases_it() -> void:
	_give_inputs("mining_drone")
	sim.submit(_start("mining_drone"))
	sim.step(RUN_TICKS - 2)
	var job: int = sim.view()["jobs"].keys()[0]
	state["parts"][FABRICATOR]["shed"] = true
	state["parts"][FABRICATOR]["shed_until_tick"] = 1000
	state["jobs"][job]["remaining_tick"] = 1
	sim.step()
	assert_eq(state["jobs"][job]["port"], FREE_PORT, "claimed, but the facility has no power")
	sim.submit({ "type": "cancel_job", "unit": STATION, "args": { "job": job } })
	_step_balanced(1)
	assert_false(state["parts"][FREE_PORT].has("claimed_by"))


func test_a_build_shed_on_its_last_tick_finishes_when_power_returns() -> void:
	_give_inputs("mining_drone")
	sim.submit(_start("mining_drone"))
	sim.step(RUN_TICKS - 2)
	var job: int = sim.view()["jobs"].keys()[0]
	state["parts"][FABRICATOR]["shed"] = true
	state["parts"][FABRICATOR]["shed_until_tick"] = sim.current_tick() + 3
	state["jobs"][job]["remaining_tick"] = 1
	_step_balanced(5)
	assert_true(_types(sim.take_events()).has("unit_created"))


func test_a_second_drone_waits_when_the_first_takes_the_last_port() -> void:
	_give_inputs("mining_drone", 2)
	var job_id := sim.submit(_start("mining_drone", 2))
	assert_gt(job_id, 0)
	sim.step(RUN_TICKS * 2)
	var events := sim.take_events()
	assert_eq(_types(events).count("unit_created"), 1)
	assert_eq(sim.view()["jobs"].values()[0]["reason"], "no_free_port")


func test_a_new_drone_takes_a_core_and_has_it_fitted_without_one() -> void:
	_give_inputs("mining_drone")
	Units.add_stock(state["units"][STATION]["inventory"], "assisted_core", 60000)
	state["matter_start_g"] += 60000
	sim.submit(_start("mining_drone"))
	sim.step(RUN_TICKS)
	var id: int = _first(sim.take_events(), "unit_created")["data"]["unit"]
	var body: int = state["units"][id]["root"]
	var command := _attach(id, "assisted_core", body, "core")
	assert_true(sim.check(command)["ok"])
	sim.submit(command)
	_step_balanced(1)
	assert_eq(_types(sim.take_events()), ["part_attached"])
	assert_eq(sim.view()["units"][id]["mass_g"], DRONE_G + 60000)


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
