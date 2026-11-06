extends GutTest
## Fabricating in place (C15): a module job with install_to fits its part where it names instead of
## putting it in a hold, so a part too big for any hold can be made. On the reference station.

const STATION := 8
const HUB := 9
const FABRICATOR := 14
const SHIP := 23
const HULL := 24
const RUN_TICKS := 3
const FULL_RATE := 100
const STORAGE := "ore_storage_mk1"
const SPOT := "side_c_px"

var sim: Sim
var state: Dictionary
var defs: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	defs = sim._ctx.defs
	for recipe: String in [STORAGE, "heat_radiator_mk1", "mining_laser_mk1", "wiring"]:
		defs["recipes"][recipe]["work"] = RUN_TICKS * FULL_RATE


func _give(recipe: String, runs: int = 1) -> void:
	for input: Dictionary in defs["recipes"][recipe]["inputs"]:
		Units.add_stock(state["units"][STATION]["inventory"], input["item"], input["grams"] * runs)
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]


func _target(unit: int = STATION, parent: int = HUB, connector: String = SPOT) -> Dictionary:
	return { "unit": unit, "parent_part": parent, "parent_connector": connector, "part_connector": "mount" }


func _job(recipe: String, target: Dictionary, count: int = 1, type: String = "start_job") -> Dictionary:
	return { "type": type, "unit": STATION,
		"args": { "facility": FABRICATOR, "recipe": recipe, "count": count, "install_to": target } }


func _steps(ticks: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in ticks:
		sim.step()
		events.append_array(sim.take_events())
		var matter: Dictionary = sim.ledger()["matter"]
		assert_eq(matter["total_g"], matter["start_g"], "tick %d" % sim.current_tick())
	assert_eq(sim.ledger()["violations"], PackedStringArray())
	return events


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])


func test_a_module_is_built_straight_onto_its_connector() -> void:
	_give(STORAGE)
	sim.submit(_job(STORAGE, _target()))
	sim.step()
	assert_eq(_types(sim.take_events()), ["job_started"])
	var job: int = state["jobs"].keys()[0]
	assert_eq(sim.view()["jobs"][job]["install_to"], _target())
	var events := _steps(RUN_TICKS - 1)
	assert_eq(_types(events), ["part_attached", "job_finished"])
	var part: int = events[0]["data"]["part"]
	assert_eq(events[0]["unit"], STATION)
	assert_eq(state["parts"][part]["def"], STORAGE)
	assert_eq(Units.child_at(state, HUB, SPOT), part)
	assert_eq(state["units"][STATION]["inventory"].get(STORAGE, 0), 0, "never in the hold")
	assert_eq(state["units"][STATION]["reserved"], {}, "and no hold space was reserved for it")


func test_a_part_is_built_onto_a_docked_ship() -> void:
	_give("heat_radiator_mk1")
	sim.submit(_job("heat_radiator_mk1", _target(SHIP, HULL, "side_c_nx")))
	var events := _steps(RUN_TICKS)
	assert_has(_types(events), "part_attached")
	assert_eq(state["parts"][Units.child_at(state, HULL, "side_c_nx")]["def"], "heat_radiator_mk1")


func test_a_job_built_in_place_is_refused_where_attach_part_would_be() -> void:
	_give(STORAGE)
	_give("mining_laser_mk1")
	assert_eq(sim.check(_job(STORAGE, _target(), 2))["reason"], "malformed_command", "one run only")
	assert_eq(sim.check(_job("wiring", _target()))["reason"], "malformed_command", "not a module")
	var bad := _target()
	bad.erase("part_connector")
	assert_eq(sim.check(_job(STORAGE, bad))["reason"], "malformed_command")
	var lone := Units.create(sim._ctx, "small_craft", "Lone", [1_000_000, 0, 0])
	assert_eq(sim.check(_job(STORAGE, _target(lone, state["units"][lone]["root"], "side_a_px")))["reason"],
		"not_docked")
	var occupied: int = Units.sorted_part_ids(state, STATION).filter(func(id: int) -> bool:
		return state["parts"][id]["parent"] == HUB and state["parts"][id]["parent_connector"].begins_with("side"))[0]
	assert_eq(sim.check(_job(STORAGE, _target(STATION, HUB, state["parts"][occupied]["parent_connector"])))["reason"],
		"connector_occupied")
	assert_eq(sim.check(_job("mining_laser_mk1", _target(SHIP, HULL, "side_b_nz")))["reason"], "over_heat_budget",
		"the ship's second laser, as in the reference chain")
	sim.submit(_job("mining_laser_mk1", _target(SHIP, HULL, "side_b_nz")))
	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["command_rejected"], "refused as this command, not as an attach")
	assert_eq(events[0]["data"]["reason"], "over_heat_budget")


func test_two_jobs_never_aim_at_one_spot() -> void:
	_give(STORAGE, 2)
	sim.submit(_job(STORAGE, _target()))
	sim.step()
	assert_eq(sim.check(_job(STORAGE, _target(), 1, "queue_job"))["reason"], "connector_occupied")


func test_a_blocked_install_holds_the_part_and_fits_it_when_the_spot_frees() -> void:
	_give(STORAGE)
	sim.submit(_job(STORAGE, _target()))
	sim.step()
	var blocker := Units.add_part(sim._ctx, STATION, "heat_radiator_mk1", HUB, SPOT, "mount")
	state["parts"][HUB]["children"].append(blocker)
	sim._ctx.index.clear()
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	var events := _steps(RUN_TICKS)
	var paused := events.filter(func(event: Dictionary) -> bool: return event["type"] == "job_paused")
	assert_eq(paused.size(), 1)
	assert_eq(paused[0]["data"]["reason"], "install_blocked")
	assert_eq(paused[0]["data"]["detail"], "connector_occupied")
	var job: Dictionary = state["jobs"].values()[0]
	assert_eq(job["held"], { STORAGE: defs["modules"][STORAGE]["mass_g"] }, "the built part, held")
	assert_eq(state["units"][STATION]["inventory"].get(STORAGE, 0), 0)
	assert_eq(sim.check({ "type": "move_job", "unit": STATION, "args": { "job": job["id"], "position": 1 } })["reason"],
		"job_busy")

	state["parts"][HUB]["children"].erase(blocker)
	state["parts"].erase(blocker)
	sim._ctx.index.clear()
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	events = _steps(1)
	assert_eq(_types(events), ["job_resumed", "part_attached", "job_finished"])
	assert_eq(state["parts"][Units.child_at(state, HUB, SPOT)]["def"], STORAGE)
	assert_true(state["jobs"].is_empty())


func test_cancelling_a_blocked_install_returns_the_part_or_is_refused_if_it_cannot_fit() -> void:
	_give(STORAGE)
	sim.submit(_job(STORAGE, _target()))
	sim.step()
	var blocker := Units.add_part(sim._ctx, STATION, "heat_radiator_mk1", HUB, SPOT, "mount")
	state["parts"][HUB]["children"].append(blocker)
	sim._ctx.index.clear()
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]
	_steps(RUN_TICKS)
	var job: int = state["jobs"].keys()[0]
	var cancel := { "type": "cancel_job", "unit": STATION, "args": { "job": job } }
	var goods: Dictionary = defs["modules"]["goods_storage_mk1"]["capabilities"]["storage"]["goods"]
	var volume_l: int = goods["volume_l"]
	goods["volume_l"] = 100
	sim._ctx.index.clear()
	assert_eq(sim.check(cancel)["reason"], "cargo_full", "a 20 m3 part cannot go back into the hold")
	goods["volume_l"] = volume_l
	sim._ctx.index.clear()
	sim.submit(cancel)
	assert_has(_types(_steps(1)), "job_cancelled")
	assert_eq(state["units"][STATION]["inventory"][STORAGE], defs["modules"][STORAGE]["mass_g"])
	assert_true(state["jobs"].is_empty())


func test_a_job_without_install_to_is_unchanged() -> void:
	_give("heat_radiator_mk1")
	sim.submit({ "type": "start_job", "unit": STATION,
		"args": { "facility": FABRICATOR, "recipe": "heat_radiator_mk1", "count": 1 } })
	_steps(RUN_TICKS)
	assert_eq(state["units"][STATION]["inventory"]["heat_radiator_mk1"], defs["modules"]["heat_radiator_mk1"]["mass_g"])
	assert_eq(sim.view()["jobs"], {})
