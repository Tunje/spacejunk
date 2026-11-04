extends GutTest
## copy_fit (C9): fitting a bare craft like a fitted one, with parts from the station it docks at.
## Every install goes through attach_part's own rules.

const STATION := 8
const FREE_PORT := 11
const SOLAR := "small_solar_panel_mk1"
const RADIATOR := "small_heat_radiator_mk1"
const TANK := "small_propellant_tank_mk1"
const THRUSTER := "small_chemical_thruster_mk1"
const CONTAINER := "small_ore_container_mk1"
const LASER := "small_mining_laser_mk1"
const CORE := "assisted_core"
const DRONE_PARTS: Array[String] = [SOLAR, RADIATOR, TANK, THRUSTER, CONTAINER, LASER, CORE]

var sim: Sim
var state: Dictionary
var defs: Dictionary


func before_each() -> void:
	sim = Sim.new_game("reference", 12345)
	sim._strict = true
	state = sim._state
	defs = sim._ctx.defs


## A craft away from the station, fitted directly, so its fit order can be anything a test needs.
func _source(fits: Array[Array]) -> int:
	var id := Units.create(sim._ctx, "small_craft", "Source", [0, 0, 0])
	var made := { "hull": state["units"][id]["root"] }
	for fit in fits:
		var parent: int = made[fit[2]]
		var part := Units.add_part(sim._ctx, id, fit[0], parent, fit[1], "mount")
		state["parts"][parent]["children"].append(part)
		made[fit[0]] = part
	_count_matter()
	return id


## The drone of the reference chain, in the order the bot fits it.
func _drone() -> int:
	return _source([
		[SOLAR, "side_a_px", "hull"], [RADIATOR, "side_a_nx", "hull"], [TANK, "stack_bottom", "hull"],
		[THRUSTER, "stack_bottom", TANK], [CONTAINER, "side_a_pz", "hull"], [LASER, "side_a_nz", "hull"],
		[CORE, "core", "hull"],
	])


## A bare craft docked at the station's free port.
func _target() -> int:
	var id := Units.create(sim._ctx, "small_craft", "Target", state["units"][STATION]["pos_mm"])
	state["units"][id]["dock"] = { "port": Units.ports(state, defs, id)[0], "target_unit": STATION, "target_port": FREE_PORT }
	state["units"][id]["at_target"] = STATION
	_count_matter()
	return id


func _give_parts(items: Array[String]) -> void:
	for item in items:
		Units.add_stock(state["units"][STATION]["inventory"], item, defs["modules"][item]["mass_g"])
	_count_matter()


func _count_matter() -> void:
	state["matter_start_g"] = sim.ledger()["matter"]["total_g"]


func _copy(target: int, source: int, from: int = STATION) -> Dictionary:
	return { "type": "copy_fit", "unit": target, "args": { "source": source, "from": from } }


## Runs a copy for one tick and returns its fit_copied event's data.
func _run_copy(target: int, source: int) -> Dictionary:
	sim.submit(_copy(target, source))
	sim.step()
	var matter: Dictionary = sim.ledger()["matter"]
	assert_eq(matter["total_g"], matter["start_g"])
	assert_eq(sim.ledger()["violations"], PackedStringArray())
	var events := sim.take_events()
	assert_eq(events[-1]["type"], "fit_copied")
	return events[-1]["data"]


func _defs_of(unit: int) -> Array:
	var found: Array = Units.part_ids(state, unit).map(func(id: int) -> String: return state["parts"][id]["def"])
	found.sort()
	return found


func _part_of(unit: int, def: String) -> int:
	for part: int in Units.sorted_part_ids(state, unit):
		if state["parts"][part]["def"] == def:
			return part
	return 0


func _refused_reasons(report: Dictionary) -> Dictionary:
	var reasons := {}
	for refusal: Dictionary in report["refused"]:
		reasons[refusal["item"]] = refusal["reason"]
	return reasons


func test_a_bare_craft_is_fitted_like_a_fitted_drone() -> void:
	var source := _drone()
	var target := _target()
	_give_parts(DRONE_PARTS)
	assert_eq(sim.check(_copy(target, source)), {
		"ok": true, "reason": "", "detail": { "attach": 7, "missing": 0, "refused": 0 },
	})
	sim.submit(_copy(target, source))
	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["part_attached", "part_attached", "part_attached", "part_attached",
		"part_attached", "part_attached", "part_attached", "fit_copied"])
	var report: Dictionary = events[-1]["data"]
	assert_eq(report["source"], source)
	assert_eq(report["attached"].size(), 7)
	assert_eq(report["missing"], {})
	assert_eq(report["refused"], [])
	assert_eq(_defs_of(target), _defs_of(source))
	var view := sim.view()
	assert_eq(view["units"][target]["fit"], view["units"][source]["fit"])
	assert_eq(view["units"][target]["mass_g"], view["units"][source]["mass_g"])
	var thruster := _part_of(target, THRUSTER)
	assert_eq(state["parts"][state["parts"][thruster]["parent"]]["def"], TANK, "the thruster hangs off the tank")
	for item in DRONE_PARTS:
		assert_eq(state["units"][STATION]["inventory"].get(item, 0), 0, item)
	assert_eq(view["units"][target]["core"], 0, "the core is fitted but not assigned")


func test_missing_stock_is_reported_and_what_hangs_below_it_waits() -> void:
	var source := _drone()
	var target := _target()
	var parts := DRONE_PARTS.duplicate()
	parts.erase(TANK)
	_give_parts(parts)
	var detail: Dictionary = sim.check(_copy(target, source))["detail"]
	var report := _run_copy(target, source)
	assert_eq(report["attached"].size(), 5)
	assert_eq(report["missing"], { TANK: 1 }, "the thruster is in stock, so only the tank is missing")
	assert_eq(_refused_reasons(report), { TANK: "missing_inputs", THRUSTER: "parent_not_fitted" })
	assert_eq(detail, { "attach": 5, "missing": 1, "refused": 2 }, "check foresaw the result")
	assert_eq(state["units"][STATION]["inventory"][THRUSTER], defs["modules"][THRUSTER]["mass_g"])

	_give_parts([TANK])
	report = _run_copy(target, source)
	assert_eq(report["attached"].size(), 2, "a second copy fits only what was left")
	assert_eq(_defs_of(target), _defs_of(source))


func test_missing_counts_every_unfitted_part_beyond_stock() -> void:
	var source := _source([[SOLAR, "side_a_px", "hull"], [SOLAR, "side_b_nx", "hull"], [RADIATOR, "side_a_nx", "hull"]])
	var target := _target()
	var report := _run_copy(target, source)
	assert_eq(report["missing"], { RADIATOR: 1, SOLAR: 2 })
	assert_eq(report["attached"], [])


func test_a_source_fitted_out_of_order_is_retried_until_nothing_more_fits() -> void:
	var source := _source([
		[LASER, "side_a_nz", "hull"], [SOLAR, "side_a_px", "hull"], [RADIATOR, "side_a_nx", "hull"],
	])
	var target := _target()
	_give_parts([LASER, SOLAR, RADIATOR])
	var report := _run_copy(target, source)
	assert_eq(report["refused"], [])
	assert_eq(_defs_of(target), _defs_of(source))
	assert_lt(_part_of(target, SOLAR), _part_of(target, LASER), "the laser fitted on the second pass")


func test_no_rule_is_bypassed_a_part_attach_part_refuses_is_refused() -> void:
	var source := _source([[LASER, "side_a_nz", "hull"]])
	var target := _target()
	_give_parts([LASER])
	var attach := { "type": "attach_part", "unit": target, "args": { "item": LASER, "from": STATION,
		"parent_part": state["units"][target]["root"], "parent_connector": "side_a_nz", "part_connector": "mount" } }
	assert_eq(sim.check(attach)["reason"], "over_power_budget")
	var report := _run_copy(target, source)
	assert_eq(report["refused"], [{ "source_part": _part_of(source, LASER), "item": LASER, "reason": "over_power_budget" }])
	assert_eq(report["missing"], {}, "the laser is in stock, just refused")
	assert_eq(_part_of(target, LASER), 0)


func test_a_part_already_in_place_is_kept() -> void:
	var source := _drone()
	var target := _target()
	var hull: int = state["units"][target]["root"]
	var solar := Units.add_part(sim._ctx, target, SOLAR, hull, "side_a_px", "mount")
	state["parts"][hull]["children"].append(solar)
	var parts := DRONE_PARTS.duplicate()
	parts.erase(SOLAR)
	_give_parts(parts)
	var report := _run_copy(target, source)
	assert_eq(report["attached"].size(), 6)
	assert_eq(_part_of(target, SOLAR), solar)
	assert_eq(_defs_of(target), _defs_of(source))


func test_a_connector_holding_a_different_part_is_refused() -> void:
	var source := _source([[SOLAR, "side_a_px", "hull"], [RADIATOR, "side_a_nx", "hull"]])
	var target := _target()
	var hull: int = state["units"][target]["root"]
	var radiator := Units.add_part(sim._ctx, target, RADIATOR, hull, "side_a_px", "mount")
	state["parts"][hull]["children"].append(radiator)
	_give_parts([SOLAR, RADIATOR])
	var report := _run_copy(target, source)
	assert_eq(_refused_reasons(report), { SOLAR: "connector_occupied" })
	assert_eq(report["attached"].size(), 1)


func test_copy_fit_refuses_a_bad_source_or_parts_store() -> void:
	var source := _drone()
	var target := _target()
	_assert_refused(_copy(target, STATION), "fit_mismatch")
	_assert_refused(_copy(target, target), "invalid_target")
	_assert_refused(_copy(target, 999), "unknown_unit")
	_assert_refused(_copy(target, source, source), "not_docked")
	_assert_refused({ "type": "copy_fit", "unit": target, "args": { "source": source } }, "malformed_command")


func test_check_changes_nothing() -> void:
	var source := _drone()
	var target := _target()
	_give_parts(DRONE_PARTS)
	var before := sim.to_save()
	sim.check(_copy(target, source))
	assert_eq(sim.to_save(), before)


func _assert_refused(command: Dictionary, reason: String) -> void:
	assert_eq(sim.check(command)["reason"], reason)
	sim.submit(command)
	sim.step()
	var events := sim.take_events()
	assert_eq(_types(events), ["command_rejected"], reason)
	assert_eq(events[0]["data"]["reason"], reason)


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["type"])
