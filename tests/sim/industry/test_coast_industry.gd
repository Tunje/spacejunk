extends GutTest
## Coast closed forms for jobs, tasks, mining and cycles (C17): Sim.coast must leave exactly what
## stepping leaves. Each case steps one copy in strict mode and coasts another over the same ticks,
## then compares the saves byte for byte and the events one for one, as tests/sim/kernel/
## test_coast.gd does for A's systems.

const STATION := 8
const REFINERY := 13
const FABRICATOR := 14
const FREE_PORT := 11
const SHIP := 23
const ROCK := 2
const DEPOSIT := 3
const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 10_000_000_000
const AU_MM := 149_597_870_700_000
const ONE := OrbitMath.ONE


## What capped each coast call in the last _same_both_ways, by cap name, "" for none.
var caps := {}


## Steps `stepped` strictly and coasts `coasted` for the same ticks, and returns the coast calls.
func _same_both_ways(stepped: Sim, coasted: Sim, ticks: int, strict: bool = true) -> int:
	stepped._strict = strict
	stepped.step(ticks)
	var stepped_events := stepped.take_events()
	var coasted_events: Array[Dictionary] = []
	var calls := 0
	var left := ticks
	caps = {}
	while left > 0:
		var done: Dictionary = coasted.coast(left)
		left -= done["ticks"]
		calls += 1
		caps[done["capped_by"]] = caps.get(done["capped_by"], 0) + 1
		coasted_events.append_array(coasted.take_events())
	gut.p("coast calls %d, capped by %s" % [calls, str(caps)])
	assert_eq(coasted.current_tick(), stepped.current_tick())
	assert_eq(coasted.to_save(), stepped.to_save(), "the same state, byte for byte")
	assert_eq(coasted_events, stepped_events, "the same events on the same ticks")
	if strict:
		assert_eq(stepped.ledger()["violations"], PackedStringArray())
	return calls


func _copy(sim: Sim) -> Sim:
	var copy := Sim.from_save(sim.to_save())
	assert_not_null(copy, Sim.last_error())
	return copy


func _reference() -> Sim:
	var sim := Sim.new_game("reference", 12345)
	return sim


func _give(sim: Sim, unit: int, item: String, grams: int) -> void:
	Units.add_stock(sim._state["units"][unit]["inventory"], item, grams)
	sim._state["matter_start_g"] = sim.ledger()["matter"]["total_g"]


func _submit_both(a: Sim, b: Sim, command: Dictionary) -> void:
	a.submit(command.duplicate(true))
	b.submit(command.duplicate(true))


func _job(facility: int, recipe: String, count: int, type: String = "start_job") -> Dictionary:
	return { "type": type, "unit": STATION, "args": { "facility": facility, "recipe": recipe, "count": count } }


func test_jobs_with_several_runs_and_a_queue_coast_exactly() -> void:
	var stepped := _reference()
	_give(stepped, STATION, "hematite", 300_000)
	_give(stepped, STATION, "iron", 200_000)
	stepped.submit(_job(REFINERY, "refine_hematite", 3))
	stepped.submit(_job(FABRICATOR, "structural_frame", 2))
	stepped.submit(_job(FABRICATOR, "structural_frame", 2, "queue_job"))
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	var calls := _same_both_ways(stepped, coasted, 3_000)
	assert_true(stepped._state["jobs"].is_empty(), "every run finished")
	assert_lt(calls, 60, "the runs were skipped, not stepped: %d calls" % calls)


func test_a_lab_job_coasts_exactly() -> void:
	var stepped := _reference()
	var hub := 9
	var lab := Units.add_part(stepped._ctx, STATION, "research_lab_mk1", hub, "side_d_px", "mount")
	stepped._state["parts"][hub]["children"].append(lab)
	stepped._state["research"] = Research.empty_research()
	stepped._state["science"]["points"] = 100
	stepped._state["science"]["earned"] = 100
	for key in ["survey:2", "survey:4", "survey:6", "gravity_field:20"]:
		stepped._state["science"]["paid"][key] = 1
	stepped._ctx.index.clear()
	for input: Dictionary in stepped._ctx.defs["recipes"]["prove_autonomous_navigation"]["inputs"]:
		_give(stepped, STATION, input["item"], input["grams"])
	stepped.submit({ "type": "start_job", "unit": STATION,
		"args": { "facility": lab, "recipe": "prove_autonomous_navigation", "count": 1 } })
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	assert_lt(_same_both_ways(stepped, coasted, 3_100), 20)
	assert_true(stepped._state["research"]["theories"].has("autonomous_navigation"))


## The ship parked at the rock, undocked, for a scan and mining.
func _ship_at_rock() -> Sim:
	var sim := _reference()
	var ship: Dictionary = sim._state["units"][SHIP]
	ship["dock"] = {}
	ship["at_target"] = ROCK
	ship["pos_mm"] = sim._state["bodies"][ROCK]["pos_mm"].duplicate()
	sim._state["deposits"][DEPOSIT]["found"] = true
	sim._ctx.index.clear()
	return sim


func test_a_scan_coasts_to_its_end() -> void:
	var stepped := _ship_at_rock()
	stepped.submit({ "type": "scan", "unit": SHIP, "args": { "target": ROCK } })
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	assert_lt(_same_both_ways(stepped, coasted, 400), 10)


func test_mining_coasts_in_closed_form_to_a_full_hold() -> void:
	var stepped := _ship_at_rock()
	var laser := 0
	for part: int in Units.sorted_part_ids(stepped._state, SHIP):
		if Units.module_of(stepped._state, stepped._ctx.defs, part)["capabilities"].has("mine"):
			laser = part
	stepped.submit({ "type": "start_mining", "unit": SHIP, "args": { "deposit": DEPOSIT, "module": laser } })
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	_same_both_ways(stepped, coasted, 2_500)
	assert_eq(stepped._state["units"][SHIP]["task"], 0, "the hold filled and the order ended")
	assert_gt(stepped._state["units"][SHIP]["inventory"].get("hematite", 0), 0)
	# Mining itself never caps: only its start and end. PowerSystem may still step the ship's full
	# battery tick by tick (reported to A), so the call count is A's to bring down.
	assert_lte(caps.get("tasks", 0), 2, "mining coasts in closed form: %s" % str(caps))


## A drone fitted as tests/sim/autonomy/test_cycles.gd fits it, on a cycle to a near rock.
func test_a_mining_cycle_coasts_exactly() -> void:
	var stepped := _reference()
	var state := stepped._state
	state["bodies"][ROCK]["pos_mm"] = [2_000_000, 0, 0]
	state["deposits"][DEPOSIT]["found"] = true
	var drone := Units.create(stepped._ctx, "small_craft", "Drone", state["units"][STATION]["pos_mm"])
	var root: int = state["units"][drone]["root"]
	var fits := {}
	for fit: Array in [["small_solar_panel_mk1", "side_a_px", root], ["small_heat_radiator_mk1", "side_a_nx", root],
			["small_propellant_tank_mk1", "stack_bottom", root]]:
		fits[fit[0]] = _fit(stepped, drone, fit[0], fit[2], fit[1])
	_fit(stepped, drone, "small_chemical_thruster_mk1", fits["small_propellant_tank_mk1"], "stack_bottom")
	_fit(stepped, drone, "small_ore_container_mk1", root, "side_a_pz")
	var laser := _fit(stepped, drone, "small_mining_laser_mk1", root, "side_a_nz")
	state["units"][drone]["core"] = _fit(stepped, drone, "assisted_core", root, "core")
	state["units"][drone]["dock"] = { "port": Units.ports(state, stepped._ctx.defs, drone)[0],
		"target_unit": STATION, "target_port": FREE_PORT }
	state["units"][drone]["at_target"] = STATION
	stepped._ctx.index.clear()
	state["matter_start_g"] = stepped.ledger()["matter"]["total_g"]
	var port: int = Units.ports(state, stepped._ctx.defs, drone)[0]
	stepped.submit({ "type": "set_cycle", "unit": drone, "args": { "steps": [
		{ "type": "load_cargo", "args": { "from": STATION, "item": "propellant" } },
		{ "type": "undock", "args": {} },
		{ "type": "move_to", "args": { "target": ROCK } },
		{ "type": "start_mining", "args": { "deposit": DEPOSIT, "module": laser } },
		{ "type": "move_to", "args": { "target": STATION } },
		{ "type": "dock", "args": { "port": port, "target_port": FREE_PORT } },
		{ "type": "unload_cargo", "args": { "to": STATION, "item": "hematite" } },
	] } })
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	_same_both_ways(stepped, coasted, 6_000)
	assert_gt(state["units"][STATION]["inventory"].get("hematite", 0), 0, "a lap unloaded ore")


func _fit(sim: Sim, unit: int, def: String, parent: int, connector: String) -> int:
	var part := Units.add_part(sim._ctx, unit, def, parent, connector, "mount")
	sim._state["parts"][parent]["children"].append(part)
	return part


## A ship on a low orbit of a dense planet, so a gravity-field lap is about 630 ticks.
func _orbiting() -> Sim:
	var defs := DataLoader.load_defs()
	var sim := Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 50_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM },
				"planet": { "seed": 48213, "height_range_m": 1000 } },
		],
		"frames": [], "units": [
			{ "key": "ship", "template": "starter_ship", "name": "Ship", "pos_mm": [0, 0, 0],
				"inventory": [], "dock": null },
		],
	}, {}), "")
	var planet := 0
	var ship := 0
	for id: int in sim._state["bodies"]:
		if sim._state["bodies"][id]["name"] == "Planet":
			planet = id
	for id: int in sim._state["units"]:
		ship = id
	var orbit := OrbitMath.make_orbit(GM_PLANET, 100_000_000, 0, [0, 0, ONE], [-ONE, 0, 0], 0, 0)
	orbit["parent"] = planet
	var unit: Dictionary = sim._state["units"][ship]
	unit["orbit"] = orbit
	unit["pos_mm"] = OrbitMath.position_at(orbit, 0)
	sim._ctx.index.clear()
	sim.submit({ "type": "measure", "unit": ship, "args": { "target": planet, "kind": "gravity_field" } })
	return sim


func test_a_gravity_field_lap_coasts_exactly() -> void:
	var stepped := _orbiting()
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	_same_both_ways(stepped, coasted, 800)
	assert_eq(stepped._state["science"]["paid"].size(), 1, "the lap paid")
	assert_lte(caps.get("tasks", 0), 2, "a running measurement never caps: %s" % str(caps))
