extends "res://tests/sim/industry/coast_fixture.gd"
## Scan steps on real ranges (C34, stage4_gameplay_rules.md section 2). The instruments carry B30's
## steps: a LIDAR's shape at 25 km, and a spectrometer's class at 10 km and grade at 1 km. The ship
## stands at a real distance from Red Rock in the cluster, with no "is at" flag, so only Reach's
## range decides.

const LIDAR := 36
const HULL := 24
const SHAPE_TICKS := 300
const CLASS_TICKS := 600
const GRADE_TICKS := 6000

var sim: Sim
var state: Dictionary
var spectrometer := 0


func before_each() -> void:
	sim = _world()
	state = sim._state


## The reference game with B30's instruments: steps on the LIDAR, a spectrometer on the ship's
## hull, and the three scan-step science kinds.
func _world() -> Sim:
	var game := _reference()
	game._strict = true
	var defs: Dictionary = game._ctx.defs.duplicate(true)
	game._ctx.defs = defs
	defs["modules"]["lidar_mk1"]["capabilities"]["scan"] = { "steps": [
		{ "reveals": "shape", "range_m": 25_000, "ticks": SHAPE_TICKS },
	] }
	var spec: Dictionary = defs["modules"]["lidar_mk1"].duplicate(true)
	spec["id"] = "spectrometer_mk1"
	spec["capabilities"]["scan"] = { "steps": [
		{ "reveals": "class", "range_m": 10_000, "ticks": CLASS_TICKS },
		{ "reveals": "grade", "range_m": 1_000, "ticks": GRADE_TICKS },
	] }
	defs["modules"]["spectrometer_mk1"] = spec
	for kind: Array in [["shape", 3], ["class", 3], ["grade", 24]]:
		defs["science"][kind[0]] = { "id": kind[0], "place": "asteroid", "capability": "scan",
			"reveals": kind[0], "points": { "asteroid": kind[1] } }
	spectrometer = Units.add_part(game._ctx, SHIP, "spectrometer_mk1", HULL, "side_c_pz", "mount")
	game._state["parts"][HULL]["children"].append(spectrometer)
	game._ctx.index.clear()
	game._state["matter_start_g"] = game.ledger()["matter"]["total_g"]
	return game


## The ship undocked and still, `metres` from the rock's centre along x, in the rock's own place.
func _stand_off(metres: int, game: Sim = null) -> void:
	game = sim if game == null else game
	var ship: Dictionary = game._state["units"][SHIP]
	var rock: Dictionary = game._state["bodies"][ROCK]
	ship["dock"] = {}
	ship["at_target"] = 0
	ship["orbit"] = {}
	ship["route"] = {}
	ship["frame"] = rock["frame"]
	ship["vel_um_s"] = [0, 0, 0]
	ship["pos_mm"] = [int(rock["pos_mm"][0]) + metres * 1000, int(rock["pos_mm"][1]), int(rock["pos_mm"][2])]
	game._ctx.index.clear()


func _scan(args: Dictionary = {}) -> Dictionary:
	var full := { "target": ROCK }
	full.merge(args)
	return { "type": "scan", "unit": SHIP, "args": full }


## Submits a scan and steps until its task ends, returning every event on the way.
func _run(command: Dictionary, limit: int = 8_000) -> Array[Dictionary]:
	sim.submit(command)
	return _until_end(limit)


func _until_end(limit: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in limit:
		sim.step()
		var now := sim.take_events()
		events.append_array(now)
		for event in now:
			if event["type"] in ["task_finished", "task_cancelled", "command_rejected"]:
				return events
	fail_test("the scan did not end")
	return events


func _of(events: Array[Dictionary], type: String) -> Array:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


func test_the_lidar_sees_shape_from_twenty_km_and_nothing_of_the_minerals() -> void:
	_stand_off(20_000)
	var events := _run(_scan())
	assert_eq(_of(events, "task_finished").size(), 1)
	assert_eq(_of(events, "scan_finished")[0]["data"], { "target": ROCK, "deposits": [], "reveals": "shape" })
	assert_true(state["bodies"][ROCK]["scanned"])
	assert_false(state["deposits"][DEPOSIT]["found"])
	assert_eq(sim.view()["deposits"].size(), 0)
	assert_eq(state["science"]["paid"], { "shape:%d" % ROCK: 1 })


func test_the_spectrometer_names_the_mineral_at_five_km_but_not_how_much() -> void:
	_stand_off(5_000)
	var events := _run(_scan())
	var found: Array = _of(events, "deposit_found")
	assert_eq(found.size(), 1, "class is the deepest step in range")
	assert_eq(found[0]["data"], { "deposit": DEPOSIT, "item": state["deposits"][DEPOSIT]["item"] }, "no grams")
	var shown: Dictionary = sim.view()["deposits"][DEPOSIT]
	assert_eq([shown["remaining_g"], shown["hardness"]], [-1, -1])
	assert_false(state["bodies"][ROCK]["scanned"], "a spectrometer doesn't measure shape")
	assert_eq(state["science"]["paid"], { "class:%d" % ROCK: 1 })


func test_the_grade_at_a_km_gives_grams_and_hardness() -> void:
	_stand_off(5_000)
	_run(_scan())
	_stand_off(800)
	var events := _run(_scan())
	var graded: Array = _of(events, "deposit_graded")
	assert_eq(graded.size(), 1)
	assert_eq(graded[0]["data"]["grams"], state["deposits"][DEPOSIT]["remaining_g"])
	assert_eq(sim.view()["deposits"][DEPOSIT]["remaining_g"], state["deposits"][DEPOSIT]["remaining_g"])
	assert_eq(state["science"]["paid"], { "class:%d" % ROCK: 1, "grade:%d" % ROCK: 1 })


func test_a_grade_first_finds_and_grades_at_once() -> void:
	_stand_off(500)
	var events := _run(_scan())
	assert_eq(_of(events, "deposit_found")[0]["data"]["grams"], state["deposits"][DEPOSIT]["remaining_g"])
	assert_true(state["deposits"][DEPOSIT]["graded"])


func test_a_named_step_runs_even_where_a_deeper_one_reaches() -> void:
	_stand_off(500)
	var events := _run(_scan({ "reveals": "shape" }))
	assert_eq(_of(events, "scan_finished")[0]["data"]["reveals"], "shape")
	assert_false(state["deposits"][DEPOSIT]["found"])


func test_out_of_every_range_is_refused_with_how_far() -> void:
	_stand_off(30_000)
	var checked := sim.check(_scan())
	assert_eq(checked["reason"], "out_of_range")
	assert_eq(checked["detail"], { "range_m": 30_000, "need_m": 25_000 })
	_stand_off(20_000)
	assert_eq(sim.check(_scan({ "reveals": "class" }))["reason"], "out_of_range", "the LIDAR can't name minerals")
	assert_eq(sim.check(_scan({ "reveals": "luck" }))["reason"], "malformed_command")


func test_drifting_out_of_range_ends_the_scan_with_nothing() -> void:
	_stand_off(9_000)
	sim.submit(_scan())
	sim.step(100)
	state["units"][SHIP]["vel_um_s"] = [50_000_000, 0, 0]
	var events := _until_end(CLASS_TICKS)
	var ended: Array = _of(events, "task_cancelled")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0]["data"]["reason"], "out_of_range")
	assert_false(state["deposits"][DEPOSIT]["found"])
	assert_eq(state["science"]["paid"], {})


func test_a_scan_held_still_in_range_coasts_to_its_end() -> void:
	var coasted := _world()
	for game: Sim in [sim, coasted]:
		_stand_off(5_000, game)
		game.submit(_scan())
		game.step()
		game.take_events()
	var calls := _same_both_ways(sim, coasted, CLASS_TICKS + 10)
	assert_lt(calls, 10, "coasted, not stepped")
	assert_true(sim._state["deposits"][DEPOSIT]["found"])


func test_old_data_with_no_steps_scans_everything_at_the_body_as_before() -> void:
	sim._ctx.defs["modules"]["lidar_mk1"]["capabilities"]["scan"] = { "ticks": SHAPE_TICKS }
	state["parts"][spectrometer]["fault"] = "test_fault"
	_stand_off(400)
	var events := _run(_scan())
	assert_eq(_of(events, "scan_finished")[0]["data"]["reveals"], "legacy")
	assert_true(state["bodies"][ROCK]["scanned"])
	assert_true(state["deposits"][DEPOSIT]["graded"])
	assert_eq(_of(events, "deposit_found")[0]["data"]["grams"], state["deposits"][DEPOSIT]["remaining_g"])
	assert_eq(state["science"]["paid"], { "survey:%d" % ROCK: 1 })


func test_a_scan_drifting_slowly_in_range_coasts_exactly() -> void:
	var coasted := _world()
	for game: Sim in [sim, coasted]:
		_stand_off(5_000, game)
		game._state["units"][SHIP]["vel_um_s"] = [1_000_000, 0, 0]
		game.submit(_scan())
		game.step()
		game.take_events()
	_same_both_ways(sim, coasted, CLASS_TICKS + 10)
	assert_true(sim._state["deposits"][DEPOSIT]["found"], "60 m of drift keeps it well within 10 km")


## B30a lists the LIDAR's steps but keeps its old time beside them, and the probe gets its
## spectrometer only with B30b. Until the old time goes, the LIDAR scans everything, as before.
func test_steps_beside_the_old_time_still_scan_everything() -> void:
	sim._ctx.defs["modules"]["lidar_mk1"]["capabilities"]["scan"] = { "ticks": SHAPE_TICKS, "steps": [
		{ "reveals": "shape", "range_m": 25_000, "ticks": SHAPE_TICKS },
	] }
	state["parts"][spectrometer]["fault"] = "test_fault"
	_stand_off(400)
	var events := _run(_scan())
	assert_eq(_of(events, "scan_finished")[0]["data"]["reveals"], "legacy")
	assert_true(state["deposits"][DEPOSIT]["graded"])
