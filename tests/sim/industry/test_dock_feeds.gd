extends "res://tests/sim/industry/coast_fixture.gd"
## Dock feeds (C26, C30): a run may start once the job's docked group holds its inputs. It takes
## what its own unit holds, and the rest comes through the docks into the run, along the path from
## the nearest unit that holds it, at the slowest port's rate on the path. While it feeds, every
## port on the path carries nothing else, and the source's stock is claimed. Undocking anywhere on
## the path cuts the feed. Outputs and anything handed back stay with the job's own unit.

const HEMATITE_RUN_G := 100_000
## docking_port_mk1 carries 50 kg/s, so 5 kg a tick.
const PORT_TICK_G := 5_000
const SHIP_PORT := 12
const HUB := 9

var sim: Sim
var state: Dictionary


func before_each() -> void:
	sim = _reference()
	sim._strict = true
	state = sim._state


func _stock(unit: int, item: String = "hematite") -> int:
	return state["units"][unit]["inventory"].get(item, 0)


func _the_job() -> Dictionary:
	return state["jobs"].values()[0]


func _run_held() -> int:
	return _the_job()["held"].get("hematite", 0)


## A new small craft docked by its own port at `target_port` of `target`.
func _craft_at(target: int, target_port: int) -> int:
	var id := Units.create(sim._ctx, "small_craft", "Craft", [0, 0, 0])
	var port: int = Units.ports(state, sim._ctx.defs, id)[0]
	state["units"][id]["dock"] = { "port": port, "target_unit": target, "target_port": target_port }
	state["units"][id]["pos_mm"] = state["units"][target]["pos_mm"].duplicate()
	state["units"][id]["frame"] = state["units"][target]["frame"]
	sim._ctx.index.clear()
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	return id


## A second small docking port on a craft's free stack_bottom.
func _extra_port(unit: int) -> int:
	var hull: int = state["units"][unit]["root"]
	var port := Units.add_part(sim._ctx, unit, "small_docking_port_mk1", hull, "stack_bottom", "mount")
	state["parts"][hull]["children"].append(port)
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	return port


func _refine(count: int = 1, facility: int = REFINERY) -> void:
	sim.submit({ "type": "start_job", "unit": STATION,
		"args": { "facility": facility, "recipe": "refine_hematite", "count": count } })


func _step_balanced(ticks: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in ticks:
		sim.step()
		events.append_array(sim.take_events())
		var ledger := sim.ledger()
		assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"], "tick %d" % sim.current_tick())
		assert_eq(ledger["violations"], PackedStringArray())
	return events


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


func test_a_run_feeds_its_input_from_a_docked_unit_at_the_port_rate() -> void:
	_give(sim, SHIP, "hematite", HEMATITE_RUN_G)
	_refine()
	_step_balanced(1)
	var job := _the_job()
	assert_eq([job["status"], job["limit"], job["rate_w"]], ["running", "feed", 0])
	assert_eq(job["feed"]["route"]["path"], [SHIP, STATION])
	assert_eq(job["feed"]["route"]["rate_g_per_s"], 50_000)
	assert_eq([_run_held(), _stock(SHIP)], [PORT_TICK_G, HEMATITE_RUN_G - PORT_TICK_G], "5 kg in the first tick")
	assert_eq(state["parts"][REFINERY]["draw_w"], 0, "no work, no power while it feeds")
	var events := _step_balanced(19)
	assert_eq(_types(events).count("job_fed"), 1, "all 100 kg in on tick 20")
	assert_eq([_run_held(), _stock(SHIP)], [HEMATITE_RUN_G, 0])
	assert_eq(job["feed"], {})
	assert_eq(job["energy_left_j"], JobSystem.run_energy_j(sim._ctx, job), "no work done yet")
	_step_balanced(1)
	assert_eq(job["limit"], "throughput")
	assert_gt(state["parts"][REFINERY]["draw_w"], 0)
	_step_balanced(700)
	assert_gt(_stock(STATION, "iron"), 0, "the iron is the station's")
	assert_eq(_stock(SHIP, "iron"), 0)


func test_the_jobs_own_unit_gives_first() -> void:
	_give(sim, STATION, "hematite", 60_000)
	_give(sim, SHIP, "hematite", 70_000)
	_refine()
	_step_balanced(1)
	assert_eq(_stock(STATION), 0, "all 60 kg of its own at once")
	assert_eq(_run_held(), 60_000 + PORT_TICK_G)
	_step_balanced(7)
	assert_eq(_the_job()["feed"], {})
	assert_eq(_stock(SHIP), 30_000, "then 40 kg fed from the ship, over 8 ticks")


func test_a_feed_runs_along_the_dock_chain_at_its_slowest_port() -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["small_docking_port_mk1"]["capabilities"]["port"]["transfer_g_per_s"] = 20_000
	var near := _craft_at(STATION, FREE_PORT)
	var far := _craft_at(near, _extra_port(near))
	_give(sim, far, "hematite", HEMATITE_RUN_G)
	_refine()
	_step_balanced(1)
	var route: Dictionary = _the_job()["feed"]["route"]
	assert_eq(route["path"], [far, near, STATION], "two docks away, through the craft between")
	assert_eq(route["ports"].size(), 4, "both ports of both docks")
	assert_eq(route["rate_g_per_s"], 20_000, "the small ports, not the station's")
	assert_eq(_run_held(), 2_000)
	_step_balanced(49)
	assert_eq([_run_held(), _stock(far), _stock(near)], [HEMATITE_RUN_G, 0, 0], "nothing stops in the middle")


func test_a_transfer_through_a_feeding_dock_waits_for_the_feed() -> void:
	_give(sim, SHIP, "hematite", HEMATITE_RUN_G)
	_give(sim, SHIP, "copper", 10_000)
	_refine()
	_step_balanced(1)
	sim.submit({ "type": "unload_cargo", "unit": SHIP, "args": { "to": STATION, "item": "copper" } })
	_step_balanced(10)
	assert_eq(_stock(SHIP, "copper"), 10_000, "the dock is the feed's")
	_step_balanced(10)
	assert_eq(_the_job()["feed"], {})
	_step_balanced(3)
	assert_eq(_stock(STATION, "copper"), 10_000, "and then the copper goes")


func test_a_feed_waits_for_a_transfer_already_using_the_dock() -> void:
	_give(sim, SHIP, "hematite", HEMATITE_RUN_G)
	_give(sim, SHIP, "copper", 100_000)
	sim.submit({ "type": "unload_cargo", "unit": SHIP, "args": { "to": STATION, "item": "copper" } })
	_step_balanced(2)
	_refine()
	_step_balanced(5)
	var job := _the_job()
	assert_eq([job["status"], job["limit"], _run_held()], ["running", "feed", 0], "waiting for the dock")
	assert_eq(_stock(SHIP), HEMATITE_RUN_G)
	_step_balanced(40)
	assert_eq(_stock(STATION, "copper"), 100_000)
	assert_eq(job["feed"], {}, "fed once the copper was across")


func test_undocking_on_the_path_cuts_the_feed_and_keeps_what_came() -> void:
	_give(sim, SHIP, "hematite", HEMATITE_RUN_G)
	_refine()
	_step_balanced(5)
	var dock: Dictionary = state["units"][SHIP]["dock"].duplicate()
	state["units"][SHIP]["dock"] = {}
	var events := _step_balanced(2)
	var job := _the_job()
	assert_eq([job["status"], job["reason"]], ["paused", "missing_inputs"], "nothing else in the group has ore")
	assert_eq(_run_held(), 5 * PORT_TICK_G, "what came stays held")
	assert_eq(_stock(SHIP), HEMATITE_RUN_G - 5 * PORT_TICK_G)
	assert_true(_types(events).has("job_paused"))
	state["units"][SHIP]["dock"] = dock
	_step_balanced(15)
	assert_eq(job["feed"], {}, "fed the rest once docked again")
	assert_eq(_run_held(), HEMATITE_RUN_G)


func test_a_unit_outside_the_group_does_not_count() -> void:
	var loose := Units.create(sim._ctx, "small_craft", "Loose", [0, 0, 0])
	sim._ctx.index.clear()
	_give(sim, loose, "hematite", HEMATITE_RUN_G)
	_refine()
	_step_balanced(1)
	assert_eq(_the_job()["reason"], "missing_inputs")
	assert_eq(_stock(loose), HEMATITE_RUN_G)


func test_the_source_stock_a_feed_takes_is_claimed() -> void:
	var second := Units.add_part(sim._ctx, STATION, "compact_refinery_mk1", HUB, "side_c_px", "mount")
	state["parts"][HUB]["children"].append(second)
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	_give(sim, SHIP, "hematite", HEMATITE_RUN_G + 40_000)
	_refine()
	_refine(1, second)
	_step_balanced(3)
	var jobs: Array = state["jobs"].values()
	assert_eq(jobs[0]["limit"], "feed")
	assert_eq(jobs[1]["reason"], "missing_inputs", "the first run's 100 kg is claimed, so 40 kg is all there is")
	assert_eq(jobs[1]["held"], {})


func test_a_cancelled_run_hands_its_inputs_to_the_jobs_own_unit() -> void:
	_give(sim, SHIP, "hematite", HEMATITE_RUN_G)
	_refine()
	_step_balanced(10)
	sim.submit({ "type": "cancel_job", "unit": STATION, "args": { "job": _the_job()["id"] } })
	_step_balanced(2)
	assert_eq(_stock(STATION), 10 * PORT_TICK_G, "what came goes to the station")
	assert_eq(_stock(SHIP), HEMATITE_RUN_G - 10 * PORT_TICK_G, "the rest never left the ship")
	assert_true(state["jobs"].is_empty())


func test_fed_runs_coast_exactly() -> void:
	_give(sim, STATION, "hematite", 50_000)
	_give(sim, SHIP, "hematite", 250_000)
	_refine(3)
	sim.step()
	sim.take_events()
	var coasted := _copy(sim)
	assert_lt(_same_both_ways(sim, coasted, 4_000), 120, "feeds step, the runs between them coast")
	assert_eq(_stock(STATION) + _stock(SHIP), 0, "all three runs took their ore")
