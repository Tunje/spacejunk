extends GutTest
## The worlds and the comparison the coast tests share (C17, C20): Sim.coast must leave exactly
## what stepping leaves. Each case steps one copy in strict mode and coasts another over the same
## ticks, then compares the saves byte for byte and the events one for one, as tests/sim/kernel/
## test_coast.gd does for A's systems. Not a test file itself; test_coast_industry.gd and
## test_coast_cargo.gd extend it.

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


func _laser(sim: Sim, unit: int) -> int:
	for part: int in Units.sorted_part_ids(sim._state, unit):
		if Units.module_of(sim._state, sim._ctx.defs, part)["capabilities"].has("mine"):
			return part
	return 0


## Returns the reference world with a drone docked at the station, given a mining cycle whose
## start_mining step carries `extra` args, after one tick.
func _mining_cycle(extra: Dictionary, accepted: bool = true) -> Sim:
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
	var mining := { "deposit": DEPOSIT, "module": laser }
	mining.merge(extra)
	stepped.submit({ "type": "set_cycle", "unit": drone, "args": { "steps": [
		{ "type": "load_cargo", "args": { "from": STATION, "item": "propellant" } },
		{ "type": "undock", "args": {} },
		{ "type": "move_to", "args": { "target": ROCK } },
		{ "type": "start_mining", "args": mining },
		{ "type": "move_to", "args": { "target": STATION } },
		{ "type": "dock", "args": { "port": port, "target_port": FREE_PORT } },
		{ "type": "unload_cargo", "args": { "to": STATION, "item": "hematite" } },
	] } })
	stepped.step()
	var types: Array = stepped.take_events().map(func(event: Dictionary) -> String: return event["type"])
	assert_eq(types.has("command_rejected"), not accepted, str(types))
	return stepped


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


## C20: the reference ship, docked at the station, for docks and transfers. The ship has an ore
## hold but no goods hold, so ore goes both ways and goods only out to the station.
func _docked() -> Sim:
	var sim := _reference()
	_give(sim, STATION, "hematite", 900_000)
	_give(sim, SHIP, "chalcopyrite", 400_000)
	return sim


func _then_same(stepped: Sim, ticks: int) -> int:
	stepped.step()
	stepped.take_events()
	return _same_both_ways(stepped, _copy(stepped), ticks)


func _held(sim: Sim, unit: int, item: String) -> int:
	return sim._state["units"][unit]["inventory"].get(item, 0)
