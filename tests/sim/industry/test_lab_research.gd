extends GutTest
## Lab jobs (C12): proving a theory with points and evidence, the era gate, prototypes and bench
## tests, and the locks on normal recipes. The reference station gets a research lab, and research
## starts empty, so the Assisted Core is locked as in the first playthrough.

const STATION := 8
const HUB := 9
const FABRICATOR := 14
const RUN_TICKS := 3
const FULL_RATE := 100
const THEORY := "autonomous_navigation"
const PROVE := "prove_autonomous_navigation"
const CORE := "assisted_core"
const PROTOTYPE := "prototype:assisted_core"
const QUALIFY := "qualify:assisted_core"
const POINTS := 80

var sim: Sim
var state: Dictionary
var defs: Dictionary
var lab := 0


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	defs = sim._ctx.defs
	for recipe: String in [PROVE, CORE, PROTOTYPE, QUALIFY, "basic_core"]:
		defs["recipes"][recipe]["work"] = RUN_TICKS * FULL_RATE
	state["research"] = Research.empty_research()
	lab = Units.add_part(sim._ctx, STATION, "research_lab_mk1", HUB, "side_d_px", "mount")
	state["parts"][HUB]["children"].append(lab)
	sim._ctx.index.clear()
	_count_matter()


func _count_matter() -> void:
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]


func _give(recipe: String, runs: int = 1) -> void:
	for input: Dictionary in defs["recipes"][recipe]["inputs"]:
		Units.add_stock(state["units"][STATION]["inventory"], input["item"], input["grams"] * runs)
	_count_matter()


## The bench test's own inputs, beside the prototype the station already holds.
func _give_bench() -> void:
	for input: Dictionary in defs["recipes"][QUALIFY]["inputs"]:
		if input["item"] != PROTOTYPE:
			Units.add_stock(state["units"][STATION]["inventory"], input["item"], input["grams"])
	_count_matter()


## Science as if measured: points earned, and evidence keys paid.
func _earn(points: int, keys: Array = []) -> void:
	state["science"]["points"] += points
	state["science"]["earned"] += points
	for key: String in keys:
		state["science"]["paid"][key] = 1


func _evidence() -> void:
	_earn(0, ["survey:2", "survey:4", "survey:6", "gravity_field:20"])


func _start(recipe: String, facility: int = 0, type: String = "start_job") -> Dictionary:
	return { "type": type, "unit": STATION,
		"args": { "facility": lab if facility == 0 else facility, "recipe": recipe, "count": 1 } }


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


func _step_checked(ticks: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in ticks:
		sim.step()
		events.append_array(sim.take_events())
		assert_eq(sim.ledger()["violations"], PackedStringArray(), "tick %d" % sim.current_tick())
	return events


func _job() -> int:
	return state["jobs"].keys()[0] if not state["jobs"].is_empty() else 0


func test_a_locked_design_refuses_its_normal_and_prototype_recipes() -> void:
	assert_eq(sim.check(_start(CORE, FABRICATOR))["reason"], "theory_locked")
	assert_eq(sim.check(_start(PROTOTYPE, FABRICATOR))["reason"], "theory_locked")
	assert_eq(sim.check(_start(QUALIFY))["reason"], "theory_locked")
	assert_true(sim.check(_start("basic_core", FABRICATOR))["ok"], "no theory unlocks the basic core")


func test_a_test_waits_for_evidence_then_points_and_holds_its_points() -> void:
	_give(PROVE)
	sim.submit(_start(PROVE))
	var events := _step_checked(1)
	assert_eq(state["jobs"][_job()]["reason"], "missing_evidence")
	_evidence()
	events = _step_checked(1)
	assert_eq(state["jobs"][_job()]["reason"], "missing_points")
	_earn(POINTS + 5)
	events = _step_checked(1)
	assert_eq(state["jobs"][_job()]["status"], "running")
	assert_eq(state["jobs"][_job()]["points_held"], POINTS)
	assert_eq(sim.view()["jobs"][_job()]["points_held"], POINTS)
	assert_eq(state["science"]["points"], 5)
	assert_eq(sim.ledger()["science"], { "points": 5, "earned": POINTS + 5, "spent": 0, "held": POINTS })


func test_a_finished_test_proves_its_theory_and_makes_its_design_a_prototype() -> void:
	_give(PROVE)
	_evidence()
	_earn(POINTS)
	sim.submit(_start(PROVE))
	var events := _step_checked(RUN_TICKS)
	assert_eq(_types(events).filter(func(type: String) -> bool: return type in ["theory_proven", "job_finished"]),
		["theory_proven", "job_finished"])
	assert_eq(state["research"]["theories"], { THEORY: RUN_TICKS })
	assert_eq(state["research"]["designs"], { CORE: "prototype" })
	assert_eq(sim.ledger()["science"], { "points": 0, "earned": POINTS, "spent": POINTS, "held": 0 })
	assert_eq(sim.ledger()["matter"]["sinks"].get("test_consumed", 0), 50_000 + 100_000, "the test's goods")
	assert_eq(sim.check(_start(PROVE))["reason"], "already_proven")
	assert_eq(sim.check(_start(CORE, FABRICATOR))["reason"], "design_unqualified")
	assert_true(sim.check(_start(PROTOTYPE, FABRICATOR))["ok"])
	assert_eq(sim.view()["research"]["theories"], { THEORY: RUN_TICKS })


func test_a_cancelled_test_refunds_its_points() -> void:
	_give(PROVE)
	_evidence()
	_earn(POINTS)
	sim.submit(_start(PROVE))
	_step_checked(1)
	sim.submit({ "type": "cancel_job", "unit": STATION, "args": { "job": _job() } })
	_step_checked(1)
	assert_eq(state["science"]["points"], POINTS)
	assert_eq(state["science"]["spent"], 0)
	assert_true(state["jobs"].is_empty())


func test_the_era_gate_needs_a_core_of_the_era_before() -> void:
	_give(PROVE)
	var core: int = state["units"][STATION]["core"]
	state["units"][STATION]["core"] = 0
	assert_eq(sim.check(_start(PROVE))["reason"], "tier_too_low", "era 2 needs a tier 1 core")
	state["units"][STATION]["core"] = core
	assert_true(sim.check(_start(PROVE))["ok"])


func test_a_queued_test_already_proven_by_another_leaves_the_queue() -> void:
	_give(PROVE, 2)
	_evidence()
	_earn(POINTS * 2)
	sim.submit(_start(PROVE))
	sim.submit(_start(PROVE, 0, "queue_job"))
	var events := _step_checked(RUN_TICKS + 1)
	var cancelled := events.filter(func(event: Dictionary) -> bool: return event["type"] == "job_cancelled")
	assert_eq(cancelled.size(), 1)
	assert_eq(cancelled[0]["data"]["reason"], "already_proven")
	assert_true(state["jobs"].is_empty())
	assert_eq(state["science"]["points"], POINTS, "it held nothing")


func test_prototype_then_bench_test_qualifies_the_design_and_unlocks_its_recipe() -> void:
	state["research"]["theories"][THEORY] = 0
	state["research"]["designs"][CORE] = "prototype"
	_give(PROTOTYPE)
	sim.submit(_start(PROTOTYPE, FABRICATOR))
	_step_checked(RUN_TICKS * 2)
	var inventory: Dictionary = state["units"][STATION]["inventory"]
	assert_eq(inventory.get(PROTOTYPE, 0), defs["modules"][CORE]["mass_g"])
	assert_gt(sim.ledger()["matter"]["sinks"].get("fab_scrap", 0), 0)
	assert_eq(sim.check({ "type": "attach_part", "unit": STATION, "args": { "item": PROTOTYPE, "from": STATION,
		"parent_part": HUB, "parent_connector": "side_d_nx", "part_connector": "mount" } })["ok"], false,
		"a prototype is a test article, not a part")
	_give_bench()
	sim.submit(_start(QUALIFY))
	var events := _step_checked(RUN_TICKS)
	assert_has(_types(events), "design_qualified")
	assert_eq(state["research"]["designs"][CORE], "qualified")
	assert_eq(inventory.get(PROTOTYPE, 0), 0, "used up by the test")
	assert_eq(sim.check(_start(QUALIFY))["reason"], "already_qualified")
	assert_true(sim.check(_start(CORE, FABRICATOR))["ok"])


## research.md section 5's route, from surveys to a built Assisted Core, on real jobs. Surveys are
## real scans; the gravity field is paid directly, as it needs an orbit the reference start lacks.
func test_the_first_playthrough_research_chain() -> void:
	var ship := 23
	for rock: int in [2, 4, 6]:
		Science.pay(sim._ctx, ship, "survey", rock)
	_earn(0, ["gravity_field:20"])
	_earn(POINTS)
	assert_eq(Science.evidence(state)["survey"], 3)
	_give(PROVE)
	sim.submit(_start(PROVE))
	_step_checked(RUN_TICKS)
	_give(PROTOTYPE)
	sim.submit(_start(PROTOTYPE, FABRICATOR))
	_step_checked(RUN_TICKS * 2)
	_give_bench()
	sim.submit(_start(QUALIFY))
	_step_checked(RUN_TICKS)
	_give(CORE)
	sim.submit(_start(CORE, FABRICATOR))
	_step_checked(RUN_TICKS)
	assert_eq(state["units"][STATION]["inventory"].get(CORE, 0), defs["modules"][CORE]["mass_g"])
	assert_eq(state["research"]["designs"][CORE], "qualified")
