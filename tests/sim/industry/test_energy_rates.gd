extends "res://tests/sim/industry/coast_fixture.gd"
## Factory rates (C30, the owner's ruling of 2026-11-07): a run needs its recipe's energy, and each
## tick goes at the lowest of the power its unit gives it, the power whose heat the radiators can
## still reject, and what the machine's throughput handles. Until B29 gives the data its energy,
## heat and throughput, they are derived from the old work, power_w and work_per_tick, which keeps
## every run's energy and duration.

const WIRING_WORK := 300
const WIRING_W := 50_000
## 50 kW for 300 / 1000 s.
const WIRING_J := 15_000
const COPPER_RUN_G := 10000
const WIRING_G := 10000
const FABRICATOR_W := 100_000

var sim: Sim
var state: Dictionary
var defs: Dictionary


func before_each() -> void:
	sim = _reference()
	sim._strict = true
	_tune(sim)
	state = sim._state
	defs = sim._ctx.defs


## Gives wiring a short run, on a copy of the definitions only this game uses.
func _tune(target: Sim) -> void:
	target._ctx.defs = target._ctx.defs.duplicate(true)
	target._ctx.defs["recipes"]["wiring"]["work"] = WIRING_WORK
	target._ctx.defs["recipes"]["wiring"]["power_w"] = WIRING_W


## Sets wiring's energy and heat, the fabricator's throughput and its rating, as B29's data will.
func _rated(target: Sim, energy_j: int, heat_j: int, throughput_g_per_s: int, rating_w: int = FABRICATOR_W) -> void:
	var target_defs: Dictionary = target._ctx.defs
	target_defs["recipes"]["wiring"]["energy_j"] = energy_j
	target_defs["recipes"]["wiring"]["heat_j"] = heat_j
	target_defs["modules"]["fabricator_mk1"]["capabilities"]["facility"]["throughput_g_per_s"] = throughput_g_per_s
	target_defs["modules"]["fabricator_mk1"]["power_w"] = rating_w
	target._ctx.index.clear()


func _start(recipe: String = "wiring", count: int = 1) -> Dictionary:
	return { "type": "start_job", "unit": STATION, "args": { "facility": FABRICATOR, "recipe": recipe, "count": count } }


func _the_job() -> Dictionary:
	return state["jobs"].values()[0]


## Steps until `count` runs have finished, and returns the tick each one finished on.
func _finish_ticks(count: int, limit: int = 100) -> Array[int]:
	var ticks: Array[int] = []
	for i in limit:
		sim.step()
		var matter: Dictionary = sim.ledger()["matter"]
		assert_eq(matter["total_g"], matter["start_g"], "tick %d" % sim.current_tick())
		for event in sim.take_events():
			if event["type"] == "job_finished":
				ticks.append(sim.current_tick())
		if ticks.size() == count:
			return ticks
	fail_test("only %d of %d runs finished" % [ticks.size(), count])
	return ticks


func test_until_b29_a_run_keeps_its_old_energy_timing_and_draw() -> void:
	_give(sim, STATION, "copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step()
	assert_eq(state["parts"][FABRICATOR]["draw_w"], WIRING_W)
	var shown: Dictionary = sim.view()["jobs"].values()[0]
	assert_eq([shown["energy_j"], shown["energy_left_j"], shown["rate_w"], shown["limit"]],
		[WIRING_J, WIRING_J - WIRING_W / 10, WIRING_W, "throughput"])
	assert_eq([shown["work"], shown["work_left"], shown["work_per_tick"]], [WIRING_J, WIRING_J - 5000, 5000],
		"the deprecated aliases give the same progress and time left")
	assert_eq(_finish_ticks(1), [3] as Array[int], "15 kJ at 5 kJ a tick: ticks 1 to 3")


func test_a_half_rate_facility_takes_twice_as_long_at_half_the_draw() -> void:
	defs["modules"]["fabricator_mk1"]["capabilities"]["facility"]["work_per_tick"] = 50
	sim._ctx.index.clear()
	_give(sim, STATION, "copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step()
	assert_eq(state["parts"][FABRICATOR]["draw_w"], WIRING_W / 2)
	assert_eq(_the_job()["energy_left_j"], WIRING_J - WIRING_W / 20)
	assert_eq(_finish_ticks(1), [6] as Array[int])
	assert_eq(state["units"][STATION]["inventory"]["wiring"], WIRING_G)
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_the_machines_throughput_holds_a_run() -> void:
	# 10 kg at 500 g/s is 20 s, so 1 MJ goes in at 50 kW.
	_rated(sim, 1_000_000, 0, 500)
	_give(sim, STATION, "copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step()
	var job := _the_job()
	assert_eq([job["rate_w"], job["limit"]], [50_000, "throughput"])
	assert_eq(job["limits_w"]["throughput"], 50_000)
	assert_eq(job["limits_w"]["heat"], -1, "a run that makes no heat has no heat limit")
	assert_eq(state["parts"][FABRICATOR]["draw_w"], 50_000)
	assert_eq(_finish_ticks(1, 300), [200] as Array[int])


func test_the_rating_caps_a_machine_that_could_handle_more() -> void:
	_rated(sim, 1_000_000, 0, 1_000_000)
	_give(sim, STATION, "copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step()
	assert_eq([_the_job()["rate_w"], _the_job()["limit"]], [FABRICATOR_W, "throughput"],
		"the machine's own rating is a limit of the machine")


func test_a_run_takes_the_power_left_when_the_unit_is_short() -> void:
	_rated(sim, 1_000_000_000_000, 0, 1_000_000_000, 100_000_000_000)
	_give(sim, STATION, "copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step()
	var flow: Dictionary = sim._ctx.flows[PowerSystem.FLOW_KEY][STATION]
	var job := _the_job()
	assert_eq(job["limit"], "power")
	assert_gt(job["rate_w"], 0)
	assert_eq(flow["consumed_w"], flow["budget_w"], "the job takes every watt the fixed loads leave")
	assert_eq(job["limits_w"]["power"], job["rate_w"])
	assert_eq(state["parts"][FABRICATOR]["draw_w"], job["rate_w"])
	assert_false(state["parts"][FABRICATOR]["shed"])
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_a_run_never_makes_heat_faster_than_the_radiators_take_it_off() -> void:
	# Ten joules of heat for every joule in, on a machine with power to spare.
	_rated(sim, 1_000_000_000, 10_000_000_000, 1_000_000_000, 100_000_000_000)
	_give(sim, STATION, "copper", COPPER_RUN_G)
	sim.submit(_start())
	for i in 20:
		sim.step()
		var heat: Dictionary = sim._ctx.flows[HeatSystem.FLOW_KEY][STATION]
		assert_lte(heat["input_w"], heat["reject_w"], "tick %d" % sim.current_tick())
	var job := _the_job()
	assert_eq(job["limit"], "heat")
	assert_gt(job["rate_w"], 0)
	assert_eq(job["limits_w"]["heat"], job["rate_w"])
	assert_eq(sim._ctx.flows[PowerSystem.FLOW_KEY][STATION]["job_heat_w"][FABRICATOR], job["rate_w"] * 10)
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_with_no_radiator_headroom_a_run_pauses_until_there_is_some() -> void:
	_rated(sim, 1_000_000, 1_000_000, 500)
	_give(sim, STATION, "copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step()
	var radiators: Array = UnitIndex.of(sim._ctx, STATION)["radiators"]
	assert_false(radiators.is_empty())
	var left: int = _the_job()["energy_left_j"]
	for entry: Array in radiators:
		state["parts"][entry[0]]["fault"] = "test"
	sim.take_events()
	sim.step(3)
	var job := _the_job()
	assert_eq([job["status"], job["reason"], job["limit"], job["rate_w"]], ["paused", "no_heat_headroom", "heat", 0])
	assert_eq(job["energy_left_j"], left, "no work without headroom")
	assert_false(state["parts"][FABRICATOR]["shed"], "held by heat, not shed")
	for entry: Array in radiators:
		state["parts"][entry[0]]["fault"] = ""
	sim.step()
	assert_eq(_the_job()["status"], "running")
	assert_lt(_the_job()["energy_left_j"], left)


func test_a_shed_tick_does_no_work_and_the_run_keeps_its_progress() -> void:
	_give(sim, STATION, "copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step()
	var job := _the_job()
	assert_eq(job["energy_left_j"], WIRING_J - 5000)
	state["parts"][FABRICATOR]["shed"] = true
	state["parts"][FABRICATOR]["shed_until_tick"] = sim.current_tick() + 4
	sim.step(3)
	assert_eq([job["status"], job["reason"], job["limit"]], ["paused", "no_power", "power"])
	assert_eq(job["energy_left_j"], WIRING_J - 5000, "no work while shed")
	assert_eq(_finish_ticks(1), [1 + 3 + 2] as Array[int], "the two ticks left, after the shed ones")


func test_a_cancelled_run_loses_its_progress() -> void:
	_give(sim, STATION, "copper", COPPER_RUN_G * 2)
	sim.submit(_start())
	sim.step(2)
	sim.submit({ "type": "cancel_job", "unit": STATION, "args": { "job": _the_job()["id"] } })
	sim.step()
	assert_eq(state["units"][STATION]["inventory"]["copper"], COPPER_RUN_G * 2)
	sim.submit(_start())
	var expected: Array[int] = [sim.current_tick() + 3]
	assert_eq(_finish_ticks(1), expected, "a fresh run takes all 3 ticks")


func _build_small_craft() -> void:
	defs["recipes"]["small_craft"]["work"] = 250
	for input: Dictionary in defs["recipes"]["small_craft"]["inputs"]:
		_give(sim, STATION, input["item"], input["grams"])
	sim.submit(_start("small_craft"))


func test_a_build_claims_its_port_only_on_its_last_tick_of_work() -> void:
	_build_small_craft()
	sim.step(2)
	assert_false(state["parts"][FREE_PORT].has("claimed_by"), "half a tick's energy left after tick 2")
	sim.step()
	var types: Array = sim.take_events().map(func(event: Dictionary) -> String: return event["type"])
	assert_true(types.has("unit_created"), "claimed and built on tick 3")


func test_a_build_whose_rate_rises_past_its_claim_waits_a_tick_for_its_port() -> void:
	_build_small_craft()
	sim.step(2)
	# As if the last tick had gone slowly: phase 4 sees too little to finish and claims nothing, then
	# phase 5 goes at the full rate. A joule is kept back, and the port is claimed the tick after.
	_the_job()["rate_w"] = 1
	sim.step()
	assert_eq(_the_job()["energy_left_j"], 1)
	assert_false(sim.take_events().any(func(event: Dictionary) -> bool: return event["type"] == "unit_created"))
	sim.step()
	var types: Array = sim.take_events().map(func(event: Dictionary) -> String: return event["type"])
	assert_true(types.has("unit_created"), "claimed and built on tick 4")
	assert_eq(sim.ledger()["violations"], PackedStringArray())


## Two copies with the same definitions, one to step and one to coast, a run under way.
func _pair(energy_j: int, heat_j: int, throughput: int, rating_w: int, runs: int) -> Array[Sim]:
	var stepped := _reference()
	_tune(stepped)
	_rated(stepped, energy_j, heat_j, throughput, rating_w)
	_give(stepped, STATION, "copper", COPPER_RUN_G * runs)
	stepped.submit(_start("wiring", runs))
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	_tune(coasted)
	_rated(coasted, energy_j, heat_j, throughput, rating_w)
	return [stepped, coasted] as Array[Sim]


func test_power_and_heat_limited_runs_coast_exactly() -> void:
	for heat_j: int in [0, 10_000_000_000]:
		var both := _pair(1_000_000_000, heat_j, 1_000_000_000, 100_000_000_000, 3)
		var calls := _same_both_ways(both[0], both[1], 30_000)
		assert_lt(calls, 3_000, "coasted, not stepped")


func test_throughput_limited_runs_coast_exactly_end_to_end() -> void:
	var both := _pair(1_000_000, 300_000, 333, FABRICATOR_W, 4)
	var calls := _same_both_ways(both[0], both[1], 2_000)
	assert_lt(calls, 40, "each run coasts to its last tick")
	assert_eq(both[0]._state["units"][STATION]["inventory"].get("wiring", 0), WIRING_G * 4)
