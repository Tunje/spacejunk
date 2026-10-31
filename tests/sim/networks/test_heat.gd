extends GutTest
## The heat loop of networks.md section 4. The ship's limit is 20 MJ, and its one radiator rejects
## 200 kW. Its core makes 2 kW, the laser 120 kW and the LIDAR 8 kW.

const STATION := 8
const SHIP := 23
const CORE := 25
const RADIATOR := 34
const LASER := 35
const LIDAR := 36
const LIMIT_J := 20_000_000
const CLEAR_J := 16_000_000

var sim: Sim
var state: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state


func _run_op(part: int) -> void:
	state["units"][SHIP]["op"] = { "type": "mining", "target": 3, "part": part, "start_tick": 0, "end_tick": 0 }


func _set_reject(reject_w: int) -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	sim._ctx.defs["modules"]["heat_radiator_mk1"]["capabilities"]["radiator"]["reject_w"] = reject_w


func _set_heat(heat_j: int) -> void:
	state["units"][SHIP]["heat_stored_j"] = heat_j


func _heat() -> int:
	return state["units"][SHIP]["heat_stored_j"]


func _flow() -> Dictionary:
	return sim.ledger()["heat"][SHIP]


func _assert_balanced(flow: Dictionary) -> void:
	assert_eq(flow["after_j"] - flow["before_j"], flow["added_j"] - flow["rejected_j"], "heat balances")


func _events_of(type: String) -> Array:
	return sim.take_events().filter(func(event: Dictionary) -> bool: return event["type"] == type)


func test_waste_heat_comes_from_parts_that_ran() -> void:
	sim.step()
	assert_eq(_flow()["input_w"], 2000)
	_run_op(LASER)
	sim.step()
	assert_eq(_flow()["input_w"], 122_000)
	assert_eq(sim.view()["units"][SHIP]["heat"]["input_w"], 122_000)


func test_a_job_heats_with_the_module_figure_not_the_recipe() -> void:
	state["jobs"][40] = { "facility": 14, "recipe": "wiring", "status": "running", "reason": "", "held": {} }
	sim.step()
	assert_eq(sim.ledger()["heat"][STATION]["input_w"], 87_000, "80 kW fabricator, 5 hub, 2 core")


func test_a_shed_part_makes_no_heat() -> void:
	state["parts"][31]["stored_j"] = 0
	state["parts"][32]["stored_j"] = 0
	_run_op(LASER)
	sim.step()
	assert_eq(_flow()["input_w"], 2000)


func test_radiators_keep_a_cool_loop_at_zero() -> void:
	_run_op(LASER)
	for i in 50:
		sim.step()
		assert_eq(_heat(), 0)
		_assert_balanced(_flow())


func test_heat_rises_by_the_net_rate() -> void:
	_set_reject(100_000)
	_run_op(LASER)
	sim.step()
	assert_eq(_flow()["added_j"], 12_200)
	assert_eq(_flow()["rejected_j"], 10_000)
	assert_eq(_heat(), 2200)


func test_a_cold_radiator_builds_no_credit() -> void:
	_set_reject(5)
	sim._ctx.defs["modules"]["basic_core"]["heat_w"] = 0
	sim.step(100)
	assert_eq(_heat(), 0)
	_set_heat(1000)
	sim.step(10)
	assert_eq(_heat(), 1000 - 5, "5 W for one second, with nothing banked from the cold ticks")


func test_rejection_never_takes_a_loop_below_zero() -> void:
	_set_heat(7)
	sim.step()
	assert_eq(_heat(), 0)
	assert_eq(_flow()["rejected_j"], 207)


func test_heat_tracks_the_exact_rate_over_time() -> void:
	_set_reject(0)
	sim._ctx.defs["modules"]["basic_core"]["heat_w"] = 1003
	var added_j := 0
	for i in 1000:
		sim.step()
		added_j += _flow()["added_j"]
	assert_eq(added_j, 100_300)
	assert_eq(_heat(), added_j)


func test_a_faulted_radiator_rejects_nothing() -> void:
	state["parts"][RADIATOR]["fault"] = "over_heat_limit"
	_set_heat(CLEAR_J + 1)
	sim.step()
	assert_eq(_flow()["reject_w"], 0)
	assert_eq(sim.view()["units"][SHIP]["heat"]["reject_w"], 0)


func test_docking_does_not_join_loops() -> void:
	_set_reject(0)
	_set_heat(5000)
	sim.step()
	assert_eq(state["units"][STATION]["heat_stored_j"], 700)
	assert_eq(_heat(), 5000 + 200)


func test_exactly_at_the_limit_is_not_a_fault() -> void:
	_set_reject(0)
	sim._ctx.defs["modules"]["basic_core"]["heat_w"] = 0
	_run_op(LIDAR)
	sim._ctx.defs["modules"]["lidar_mk1"]["heat_w"] = 10
	_set_heat(LIMIT_J - 1)
	sim.step()
	assert_eq(_heat(), LIMIT_J)
	assert_eq(state["parts"][LIDAR]["fault"], "")
	sim.step()
	assert_eq(_heat(), LIMIT_J + 1)
	assert_eq(state["parts"][LIDAR]["fault"], "over_heat_limit")


func test_faults_take_lowest_priority_and_highest_id_first() -> void:
	_set_reject(5000)
	_set_heat(LIMIT_J)
	_run_op(LASER)
	state["jobs"][40] = { "facility": LIDAR, "recipe": "wiring", "status": "running", "reason": "", "held": {} }
	sim.step()
	var faulted: Array = _events_of("fault").map(func(event: Dictionary) -> int:
		return event["data"]["module"])
	assert_eq(faulted, [LIDAR, LASER], "both priority 3, higher ID first, and input still above 5 kW")
	assert_eq(state["parts"][CORE]["fault"], "", "2 kW is within rejection")


func test_faulting_stops_once_input_is_within_rejection() -> void:
	_set_reject(121_000)
	_set_heat(LIMIT_J + 1_000_000)
	_run_op(LASER)
	sim.step()
	assert_eq(state["parts"][LASER]["fault"], "over_heat_limit")
	assert_eq(state["parts"][CORE]["fault"], "")


func test_no_radiator_faults_everything_that_makes_heat() -> void:
	_set_reject(0)
	_set_heat(LIMIT_J)
	_run_op(LASER)
	sim.step()
	assert_eq(state["parts"][LASER]["fault"], "over_heat_limit")
	assert_eq(state["parts"][CORE]["fault"], "over_heat_limit")


func test_a_cooling_loop_over_its_limit_faults_nothing() -> void:
	_set_heat(LIMIT_J * 2)
	_run_op(LASER)
	sim.step()
	assert_eq(_events_of("fault"), [])


func test_a_fault_takes_effect_from_the_next_tick() -> void:
	_set_reject(0)
	_set_heat(LIMIT_J)
	_run_op(LASER)
	sim.step()
	assert_eq(_flow()["input_w"], 122_000, "it ran on the tick it faulted")
	assert_eq(state["parts"][LASER]["draw_w"], 150_000)
	assert_eq(sim.view()["units"][SHIP]["parts"]["children"][9]["state"], "fault")
	assert_eq(_events_of("fault").size(), 2)
	sim.step()
	assert_eq(_flow()["input_w"], 0)
	assert_eq(state["parts"][LASER]["draw_w"], 0)
	assert_eq(sim.view()["units"][SHIP]["power"]["demand_w"], 0)
	assert_eq(_events_of("fault").size(), 0, "a fault fires once")


func test_faults_clear_at_the_clear_level_and_not_above() -> void:
	_set_reject(100_000)
	_set_heat(LIMIT_J + 1)
	state["parts"][LASER]["fault"] = "over_heat_limit"
	sim.take_events()
	_set_heat(CLEAR_J + 10_000 + 1)
	sim.step()
	assert_eq(_heat(), CLEAR_J + 1 + 200, "core heat added, 10 kJ rejected")
	assert_eq(state["parts"][LASER]["fault"], "over_heat_limit")
	_set_heat(CLEAR_J + 10_000 - 200)
	sim.step()
	assert_eq(_heat(), CLEAR_J)
	assert_eq(state["parts"][LASER]["fault"], "")
	var cleared := _events_of("fault_cleared")
	assert_eq(cleared.size(), 1)
	assert_eq(cleared[0]["data"], { "module": LASER })


func test_a_clear_takes_effect_from_the_next_tick() -> void:
	state["parts"][LASER]["fault"] = "over_heat_limit"
	_run_op(LASER)
	sim.step()
	assert_eq(state["parts"][LASER]["fault"], "")
	assert_eq(_flow()["input_w"], 2000, "still off on the tick it cleared")
	sim.step()
	assert_eq(_flow()["input_w"], 122_000)


func test_other_fault_reasons_do_not_clear_here() -> void:
	state["parts"][LASER]["fault"] = "impact"
	sim.step()
	assert_eq(state["parts"][LASER]["fault"], "impact")


func test_a_full_overheat_recovers_without_any_command() -> void:
	_set_reject(100_000)
	_set_heat(LIMIT_J - 2000)
	_run_op(LASER)
	var saw_fault := false
	var saw_clear := false
	for i in 2500:
		sim.step()
		_assert_balanced(_flow())
		for event in sim.take_events():
			saw_fault = saw_fault or event["type"] == "fault"
			saw_clear = saw_clear or event["type"] == "fault_cleared"
		var ledger := sim.ledger()
		assert_eq(ledger["violations"], PackedStringArray())
	assert_true(saw_fault)
	assert_true(saw_clear)


func test_ledgers_hold_on_every_unit_while_overheating() -> void:
	_set_reject(50_000)
	_set_heat(LIMIT_J - 100_000)
	_run_op(LASER)
	for i in 200:
		sim.step()
		var ledger := sim.ledger()
		for unit: int in ledger["heat"]:
			_assert_balanced(ledger["heat"][unit])
		for unit: int in ledger["energy"]:
			var flow: Dictionary = ledger["energy"][unit]
			assert_eq(flow["generated_w"] + flow["discharged_w"],
				flow["consumed_w"] + flow["charged_w"] + flow["curtailed_w"])


func test_a_save_midway_through_an_overheat_matches_an_unbroken_run() -> void:
	_set_reject(100_000)
	_set_heat(LIMIT_J - 2000)
	_run_op(LASER)
	sim._ctx.defs["modules"]["heat_radiator_mk1"]["capabilities"]["radiator"]["reject_w"] = 200_000
	var other := Sim.from_save(sim.to_save())
	sim.step(60)
	other.step(30)
	other = Sim.from_save(other.to_save())
	other.step(30)
	assert_eq(other.state_hash(), sim.state_hash())
