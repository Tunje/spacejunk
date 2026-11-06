extends GutTest
## The coast time warp (task A33, orbital_flight.md 11.22): Sim.coast must leave exactly what
## stepping leaves. Each case runs one game stepped in strict mode and a copy coasted, then compares
## the saves byte for byte and the events one for one. A probe orbits a Frost-sized moon low enough
## that a lap takes about an hour, so one lap passes through the moon's shadow and out again.

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const GM_MOON := 1_765_800
const AU_MM := 149_597_870_700_000
const MOON_R_MM := 60_000_000
## 25 km above the datum: above low flight, so the lap is pure rails.
const ORBIT_MM := 85_000_000
const ONE := OrbitMath.ONE
## Just over one lap, about 37,000 ticks.
const LAP_TICKS := 38_000

var keys := {}
var _last_coast_ms := 0.0


func _game() -> Sim:
	var defs := DataLoader.load_defs()
	var sim := Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM } },
			{ "key": "moon", "name": "Moon", "kind": "planet", "radius_mm": MOON_R_MM, "visual_seed": 3,
				"deposits": [], "gm": GM_MOON, "orbit": { "parent": "planet", "a_mm": 12_000_000_000 },
				"planet": { "seed": 31, "height_range_m": 1500 } },
		],
		"units": [
			{ "key": "probe", "template": "probe", "name": "Probe", "pos_mm": [0, 0, 0],
				"inventory": [{ "item": "propellant", "grams": 2_000_000 }], "dock": null },
		],
	}, {}), "")
	keys = {}
	for table: String in ["bodies", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	var probe: Dictionary = sim._state["units"][keys["Probe"]]
	# In the planet's orbital plane, so the lap crosses the moon's shadow.
	var plane: Dictionary = sim._state["bodies"][keys["Moon"]]["orbit"]
	probe["orbit"] = OrbitMath.make_orbit(GM_MOON, ORBIT_MM, 0, plane["p_q30"], plane["q_q30"], 0, 0)
	probe["orbit"]["parent"] = keys["Moon"]
	probe["pos_mm"] = OrbitMath.position_at(probe["orbit"], 0)
	# Half-charged batteries, so a lap both drains and charges them.
	for part_id in Units.part_ids(sim._state, keys["Probe"]):
		var part: Dictionary = sim._state["parts"][part_id]
		if part.has("stored_j") and part["stored_j"] > 0:
			part["stored_j"] /= 2
	sim._ctx.index.clear()
	return sim


## Steps one copy, in strict mode unless it is long, and coasts the other over the same ticks.
## Returns the coast's call count, for the cases that must have skipped.
func _same_both_ways(stepped: Sim, coasted: Sim, ticks: int, strict: bool = true) -> int:
	stepped._strict = strict
	var stepped_events: Array[Dictionary] = []
	var coasted_events: Array[Dictionary] = []
	stepped.step(ticks)
	stepped_events.append_array(stepped.take_events())
	var calls := 0
	var left := ticks
	var started := Time.get_ticks_usec()
	while left > 0:
		var done: Dictionary = coasted.coast(left)
		left -= done["ticks"]
		calls += 1
		coasted_events.append_array(coasted.take_events())
	_last_coast_ms = (Time.get_ticks_usec() - started) / 1000.0
	assert_eq(coasted.current_tick(), stepped.current_tick())
	if coasted.to_save() != stepped.to_save() and OS.has_environment("COAST_DUMP"):
		for pair: Array in [["coasted", coasted], ["stepped", stepped]]:
			var file := FileAccess.open(OS.get_environment("COAST_DUMP") + "/" + pair[0] + ".json", FileAccess.WRITE)
			file.store_string(pair[1].to_save())
	assert_eq(coasted.to_save(), stepped.to_save(), "the same state, byte for byte")
	assert_eq(coasted_events, stepped_events, "the same events on the same ticks")
	if strict:
		assert_eq(stepped.ledger()["violations"], PackedStringArray())
	return calls


func _copy(sim: Sim) -> Sim:
	var copy := Sim.from_save(sim.to_save())
	assert_not_null(copy, Sim.last_error())
	return copy


func test_a_lap_through_the_shadow_coasts_exactly_as_it_steps() -> void:
	var stepped := _game()
	var coasted := _copy(stepped)
	# The lap's reference copy runs unchecked, to keep the file quick: strict stepping is covered by
	# the shorter cases.
	var calls := _same_both_ways(stepped, coasted, LAP_TICKS, false)
	print("COAST a %d-tick lap with batteries and a shadow: %d coast calls" % [LAP_TICKS, calls])
	print("PERF coast: %.2f ms a call over the lap, %.0f ms in all (budget 2 ms a jump at slice size)" % [
		_last_coast_ms / calls, _last_coast_ms])
	assert_lt(calls, LAP_TICKS / 20, "most of the lap was skipped")
	assert_lt(_last_coast_ms / calls, 20.0, "ten times the budget fails; the PERF line is the measure")


func test_a_warm_loop_cools_the_same_when_coasted() -> void:
	var stepped := _game()
	stepped._state["units"][keys["Probe"]]["heat_stored_j"] = 40_000_000
	var coasted := _copy(stepped)
	_same_both_ways(stepped, coasted, 6_000)
	assert_lt(stepped._state["units"][keys["Probe"]]["heat_stored_j"], 40_000_000, "it cooled")


func test_a_landing_coasts_to_its_touchdown() -> void:
	var stepped := _game()
	var cell := LandingSystem.cell_below(stepped._ctx, keys["Moon"], stepped._state["units"][keys["Probe"]]["pos_mm"])
	var land := { "type": "land", "unit": keys["Probe"], "args": { "body": keys["Moon"], "cell": cell } }
	var checked := stepped.check(land)
	assert_true(checked["ok"], str(checked))
	stepped.submit(land)
	var coasted := _copy(stepped)
	var calls := _same_both_ways(stepped, coasted, checked["detail"]["ticks"] + 50)
	assert_false(stepped._state["units"][keys["Probe"]]["landed"].is_empty(), "landed")
	assert_lt(calls, 20, "the half ellipse was skipped")


func test_a_planned_burn_stops_the_coast_on_its_tick_and_caps_it() -> void:
	var stepped := _game()
	stepped.submit({ "type": "plan_burn", "unit": keys["Probe"], "args": {
		"tick": 3_000, "prograde_um_s": 2_000_000, "normal_um_s": 0, "radial_um_s": 0 } })
	var coasted := _copy(stepped)
	var first: Dictionary = coasted.coast(10_000)
	assert_eq(coasted.current_tick(), 3_000, "back on the burn's tick, which was stepped")
	assert_eq(first["capped_by"], "")
	assert_has(coasted.take_events().map(func(e: Dictionary) -> String: return e["type"]), "burn_started")
	assert_eq(coasted.coast(10_000), { "ticks": 1, "capped_by": "burning" })
	stepped.step(3_001)
	assert_eq(coasted.to_save(), stepped.to_save())


func test_a_task_caps_the_coast_and_it_still_matches() -> void:
	var stepped := Sim.new_game("reference", 12345)
	var coasted := _copy(stepped)
	stepped.submit({ "type": "undock", "unit": 23, "args": {} })
	coasted.submit({ "type": "undock", "unit": 23, "args": {} })
	var caps: Array = []
	for i in 5:
		caps.append(coasted.coast(50)["capped_by"])
	assert_has(caps, "tasks", "an undock under way steps the world: %s" % str(caps))
	stepped.step(coasted.current_tick())
	assert_eq(coasted.to_save(), stepped.to_save())


func test_strict_coast_steps_every_tick() -> void:
	var stepped := _game()
	var coasted := _copy(stepped)
	coasted._strict = true
	assert_eq(coasted.coast(500), { "ticks": 500, "capped_by": "" })
	stepped.step(500)
	assert_eq(coasted.to_save(), stepped.to_save())



