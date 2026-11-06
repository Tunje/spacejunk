extends GutTest
## Saving and loading midway through real jobs (accounting.md section 6, task A29): the reference
## station's refinery and fabricator run their real recipes at full length, by work points (C11),
## with slag already in its sink, and one job paused by a fault. A save then load must give the same
## bytes and the same play from there. A lab job proving a theory holds its science points across
## the save (C12).

const STATION := 8
const HUB := 9
const THEORY := "autonomous_navigation"
const PROVE := "prove_autonomous_navigation"
const REFINERY := 13
const FABRICATOR := 14
const HEMATITE_G := 300_000
const COPPER_G := 30_000

var sim: Sim


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	assert_not_null(sim, Sim.last_error())
	sim._strict = true
	_give("hematite", HEMATITE_G)
	_give("copper", COPPER_G)


## Puts stock at the station, counted as starting matter.
func _give(item: String, grams: int) -> void:
	Units.add_stock(sim._state["units"][STATION]["inventory"], item, grams)
	sim._state["matter_start_g"] += grams


func _start(facility: int, recipe: String, count: int) -> void:
	sim.submit({ "type": "start_job", "unit": STATION, "args": { "facility": facility, "recipe": recipe, "count": count } })


func _job_on(game: Sim, facility: int) -> Dictionary:
	for id: int in game._state["jobs"]:
		if game._state["jobs"][id]["facility"] == facility:
			return game._state["jobs"][id]
	return {}


func _run_ticks(recipe: String, facility: int) -> int:
	var rate := JobSystem.work_per_tick(sim._ctx, facility)
	return ceili(float(sim._ctx.defs["recipes"][recipe]["work"]) / rate)


func test_a_save_midway_through_real_jobs_with_slag_in_its_sink_loads_and_plays_the_same() -> void:
	_start(REFINERY, "refine_hematite", 3)
	# Into the refinery's second run, so the first run's slag is in its sink, with the fabricator
	# started so that it is midway through its first run of wiring then.
	var refine_ticks := _run_ticks("refine_hematite", REFINERY)
	var wiring_ticks := _run_ticks("wiring", FABRICATOR)
	sim.step(refine_ticks + refine_ticks / 2 - wiring_ticks / 2)
	_start(FABRICATOR, "wiring", 3)
	sim.step(wiring_ticks / 2)
	var refinery_job := _job_on(sim, REFINERY)
	assert_false(refinery_job.is_empty(), "the refinery job is still on")
	assert_eq(refinery_job["status"], "running")
	assert_between(refinery_job["work_left"], 1, sim._ctx.defs["recipes"]["refine_hematite"]["work"] - 1,
		"midway through a run")
	var sinks: Dictionary = sim.ledger()["matter"]["sinks"]
	assert_gt(sinks.values().reduce(func(total: int, grams: int) -> int: return total + grams, 0), 0,
		"some slag is already vented")
	# The fabricator faults mid-run, so its job is paused with its inputs and work held.
	sim._state["parts"][FABRICATOR]["fault"] = "test_fault"
	sim.step()
	var fabricator_job := _job_on(sim, FABRICATOR)
	assert_eq(fabricator_job.get("status", ""), "paused")
	assert_gt(fabricator_job["work_left"], 0)

	var saved := sim.to_save()
	var loaded := Sim.from_save(saved)
	assert_not_null(loaded, Sim.last_error())
	loaded._strict = true
	assert_eq(loaded.to_save(), saved, "byte-exact")
	assert_eq(loaded.state_hash(), sim.state_hash())

	# Mend the fault in both, and play every run out.
	for game: Sim in [sim, loaded]:
		game._state["parts"][FABRICATOR]["fault"] = ""
	sim.step(3 * refine_ticks)
	loaded.step(3 * refine_ticks)
	assert_eq(loaded.state_hash(), sim.state_hash(), "the same play after the load")
	assert_true(_job_on(sim, REFINERY).is_empty(), "the refinery's runs all finished")
	for game: Sim in [sim, loaded]:
		var ledger := game.ledger()
		assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
		assert_eq(ledger["violations"], PackedStringArray())


func test_a_save_midway_through_a_lab_test_keeps_its_points_held() -> void:
	sim._state["research"] = Research.empty_research()
	var lab := Units.add_part(sim._ctx, STATION, "research_lab_mk1", HUB, "side_d_px", "mount")
	sim._state["parts"][HUB]["children"].append(lab)
	sim._ctx.index.clear()
	for input: Dictionary in sim._ctx.defs["recipes"][PROVE]["inputs"]:
		Units.add_stock(sim._state["units"][STATION]["inventory"], input["item"], input["grams"])
	sim._state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	# Science as if measured: the theory's evidence, and its points with 7 to spare.
	var points: int = sim._ctx.defs["recipes"][PROVE]["points"]
	var science: Dictionary = sim._state["science"]
	science["points"] = points + 7
	science["earned"] = points + 7
	for key: String in ["survey:2", "survey:4", "survey:6", "gravity_field:20"]:
		science["paid"][key] = 1
	_start(lab, PROVE, 1)
	sim.step(_run_ticks(PROVE, lab) / 2)
	var job := _job_on(sim, lab)
	assert_eq(job.get("status", ""), "running", str(job.get("reason", "")))
	assert_eq(job["points_held"], points)
	assert_eq(sim.ledger()["science"], { "points": 7, "earned": points + 7, "spent": 0, "held": points })

	var saved := sim.to_save()
	var loaded := Sim.from_save(saved)
	assert_not_null(loaded, Sim.last_error())
	loaded._strict = true
	assert_eq(loaded.to_save(), saved, "byte-exact")
	assert_eq(loaded.ledger()["science"], sim.ledger()["science"], "the points are still held")

	sim.step(_run_ticks(PROVE, lab))
	loaded.step(_run_ticks(PROVE, lab))
	assert_eq(loaded.state_hash(), sim.state_hash(), "the same play after the load")
	for game: Sim in [sim, loaded]:
		assert_has(game._state["research"]["theories"], THEORY, "proven after the load too")
		assert_eq(game.ledger()["science"], { "points": 7, "earned": points + 7, "spent": points, "held": 0 })
		assert_eq(game.ledger()["violations"], PackedStringArray())
