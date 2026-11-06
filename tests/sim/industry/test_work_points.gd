extends GutTest
## Work points (C11): a run needs its recipe's `work`, and its facility does its `work_per_tick`
## each tick it runs, so a slower facility takes longer at the same recipe and draws less power.

const STATION := 8
const FABRICATOR := 14
const FREE_PORT := 11
const FULL_RATE := 100
const WIRING_WORK := 300
const WIRING_W := 50_000
const COPPER_RUN_G := 10000
const WIRING_G := 10000

var sim: Sim
var state: Dictionary
var defs: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	defs = sim._ctx.defs
	defs["recipes"]["wiring"]["work"] = WIRING_WORK
	defs["recipes"]["wiring"]["power_w"] = WIRING_W


func _give(item: String, grams: int) -> void:
	Units.add_stock(state["units"][STATION]["inventory"], item, grams)
	state["matter_start_g"] += grams


func _set_rate(work_per_tick: int) -> void:
	defs["modules"]["fabricator_mk1"]["capabilities"]["facility"]["work_per_tick"] = work_per_tick
	sim._ctx.index.clear()


func _start(recipe: String = "wiring", count: int = 1) -> Dictionary:
	return { "type": "start_job", "unit": STATION, "args": { "facility": FABRICATOR, "recipe": recipe, "count": count } }


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


func test_a_full_size_facility_keeps_the_old_timing_and_draw() -> void:
	_give("copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step()
	assert_eq(state["parts"][FABRICATOR]["draw_w"], WIRING_W)
	assert_eq(_finish_ticks(1), [3] as Array[int], "300 work at 100 a tick: ticks 1 to 3")


func test_a_half_rate_facility_takes_twice_as_long_at_half_the_draw() -> void:
	_set_rate(50)
	_give("copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step()
	assert_eq(state["parts"][FABRICATOR]["draw_w"], WIRING_W / 2)
	var shown: Dictionary = sim.view()["jobs"].values()[0]
	assert_eq([shown["work"], shown["work_per_tick"], shown["work_left"]], [WIRING_WORK, 50, WIRING_WORK - 50])
	assert_eq(_finish_ticks(1), [6] as Array[int], "300 work at 50 a tick: ticks 1 to 6")
	assert_eq(state["units"][STATION]["inventory"]["wiring"], WIRING_G)
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_the_draw_rounds_up() -> void:
	_set_rate(33)
	defs["recipes"]["wiring"]["power_w"] = 50_001
	_give("copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step()
	assert_eq(state["parts"][FABRICATOR]["draw_w"], 16_501, "50001 x 33 / 100 = 16500.33, rounded up")


func test_work_not_a_multiple_of_the_rate_rounds_each_run_up_and_carries_nothing() -> void:
	defs["recipes"]["wiring"]["work"] = 250
	_give("copper", COPPER_RUN_G * 2)
	sim.submit(_start("wiring", 2))
	assert_eq(_finish_ticks(2), [3, 6] as Array[int], "250 work at 100 a tick takes 3 ticks, each run")


func test_a_shed_tick_does_no_work_and_the_run_keeps_its_progress() -> void:
	_give("copper", COPPER_RUN_G)
	sim.submit(_start())
	sim.step()
	var job: int = sim.view()["jobs"].keys()[0]
	assert_eq(state["jobs"][job]["work_left"], WIRING_WORK - FULL_RATE)
	state["parts"][FABRICATOR]["shed"] = true
	state["parts"][FABRICATOR]["shed_until_tick"] = sim.current_tick() + 4
	sim.step(3)
	assert_eq(state["jobs"][job]["status"], "paused")
	assert_eq(state["jobs"][job]["reason"], "no_power")
	assert_eq(state["jobs"][job]["work_left"], WIRING_WORK - FULL_RATE, "no work while shed")
	var ticks := _finish_ticks(1)
	assert_eq(ticks, [1 + 3 + 2] as Array[int], "the two ticks of work left, after the shed ones")


func test_a_cancelled_run_loses_its_progress() -> void:
	_give("copper", COPPER_RUN_G * 2)
	sim.submit(_start())
	sim.step(2)
	var job: int = sim.view()["jobs"].keys()[0]
	sim.submit({ "type": "cancel_job", "unit": STATION, "args": { "job": job } })
	sim.step()
	assert_eq(state["units"][STATION]["inventory"]["copper"], COPPER_RUN_G * 2)
	sim.submit(_start())
	var expected: Array[int] = [sim.current_tick() + 3]
	assert_eq(_finish_ticks(1), expected, "a fresh run takes all 3 ticks")


func test_a_build_claims_its_port_only_on_its_last_tick_of_work() -> void:
	defs["recipes"]["small_craft"]["work"] = 250
	for input: Dictionary in defs["recipes"]["small_craft"]["inputs"]:
		_give(input["item"], input["grams"])
	sim.submit(_start("small_craft"))
	sim.step(2)
	assert_false(state["parts"][FREE_PORT].has("claimed_by"), "150 work left after tick 1, 50 after tick 2")
	assert_eq(state["jobs"][sim.view()["jobs"].keys()[0]]["work_left"], 50)
	sim.step()
	var types: Array = sim.take_events().map(func(event: Dictionary) -> String: return event["type"])
	assert_true(types.has("unit_created"), "claimed and built on tick 3")
