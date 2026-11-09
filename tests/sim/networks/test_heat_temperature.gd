extends GutTest
## Heat by temperature (task A60, the Lead's rule): a load's heat goes only to radiators at or below
## its temperature, and the store counts as 300 K. On the reference ship: one radiator rejecting
## 200 kW, a 2 kW core, a 120 kW laser and an 8 kW LIDAR, all 300 K unless a test sets otherwise.

const SHIP := 23
const CORE := 25
const RADIATOR := 34
const LASER := 35
const LIDAR := 36

var sim: Sim
var state: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	sim._ctx.defs = sim._ctx.defs.duplicate(true)


func _modules() -> Dictionary:
	return sim._ctx.defs["modules"]


func _radiator_at(temp_k: int) -> void:
	_modules()["heat_radiator_mk1"]["capabilities"]["radiator"]["temp_k"] = temp_k


func _laser_at(temp_k: int) -> void:
	_modules()["mining_laser_mk1"]["heat_temp_k"] = temp_k


func _run_laser() -> void:
	state["units"][SHIP]["op"] = { "type": "mining", "target": 3, "part": LASER, "start_tick": 0, "end_tick": 0 }


func _flow() -> Dictionary:
	return sim.ledger()["heat"][SHIP]


func test_all_at_300_k_is_the_loop_as_it_was() -> void:
	_run_laser()
	state["units"][SHIP]["heat_stored_j"] = 1_000_000
	sim.step()
	var flow := _flow()
	assert_eq(flow["input_w"], 122_000)
	assert_eq(flow["reject_w"], 200_000, "all of the radiator acts on the loop")
	assert_eq(flow["stranded_w"], 0)
	assert_eq(flow["rejected_j"], 20_000, "it takes this tick's heat and cools the store")


func test_a_hot_load_may_use_a_cold_radiator() -> void:
	_laser_at(500)
	_run_laser()
	sim.step()
	var flow := _flow()
	assert_eq(flow["stranded_w"], 0)
	assert_eq(flow["reject_w"], 200_000)


func test_a_cold_load_cannot_use_a_hot_radiator() -> void:
	_radiator_at(500)
	_run_laser()
	sim.step()
	var flow := _flow()
	assert_eq(flow["stranded_w"], 122_000, "the 300 K laser and core find nowhere to go")
	assert_eq(flow["reject_w"], 0)
	assert_eq(flow["after_j"] - flow["before_j"], 12_200, "the store warms by all of it")
	assert_eq(sim.view()["units"][SHIP]["heat"]["stranded_w"], 122_000)


## A hot load on a hot radiator rejects; its spare can't cool the 300 K store or take the core's heat.
func test_a_hot_radiators_spare_does_not_cool_the_store() -> void:
	_radiator_at(500)
	_laser_at(500)
	_run_laser()
	state["units"][SHIP]["heat_stored_j"] = 1_000_000
	sim.step()
	var flow := _flow()
	assert_eq(flow["stranded_w"], 2_000, "only the core's heat strands")
	assert_eq(flow["reject_w"], 120_000, "the laser's, and no spare")
	assert_eq(flow["after_j"], 1_000_200)


## Placement goes coldest first, so a cold load takes the cold radiator before a hot one can.
func test_placement_runs_coldest_load_first() -> void:
	var spares: Array = [[500, 100_000, 2], [300, 50_000, 1]]
	var placed := HeatSystem.place_all(spares, [[500, 120_000, 9], [300, 50_000, 8]])
	assert_eq(placed, 150_000, "the cold load fills the cold radiator, the hot one the hot")
	assert_eq(spares, [[500, 0, 2], [300, 0, 1]])
	var spares_b: Array = [[500, 100_000, 2], [300, 50_000, 1]]
	assert_eq(HeatSystem.place(spares_b, 500, 120_000), 120_000, "hottest first, then down")
	assert_eq(spares_b, [[500, 0, 2], [300, 30_000, 1]])


## A60 with C30: a job may only use radiators at or below its facility's temperature, and what it
## is given is placed in full. A 300 K fabricator job with only a hot radiator gets no headroom.
func test_a_cold_job_with_only_a_hot_radiator_pauses_on_heat() -> void:
	_radiator_at(500)
	_modules()["lidar_mk1"]["capabilities"]["facility"] = { "type": "fabricator", "work_per_tick": 100 }
	state["jobs"][40] = JobFixture.record(state, LIDAR, "wiring", "running")
	sim.step()
	assert_eq([state["jobs"][40]["status"], state["jobs"][40]["reason"]], ["paused", "no_heat_headroom"])


func test_a_hot_job_runs_on_a_hot_radiator_and_strands_nothing() -> void:
	_radiator_at(500)
	_modules()["lidar_mk1"]["heat_temp_k"] = 500
	_modules()["lidar_mk1"]["capabilities"]["facility"] = { "type": "fabricator", "work_per_tick": 100 }
	_modules()["basic_core"]["heat_w"] = 0
	state["jobs"][40] = JobFixture.record(state, LIDAR, "wiring", "running")
	sim.step()
	assert_eq(state["jobs"][40]["status"], "running")
	assert_eq(_flow()["stranded_w"], 0, "a job never strands heat")
	assert_gt(_flow()["input_w"], 0)
