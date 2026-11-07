extends GutTest
## The coast fixture (A33, A35): a probe round a Frost-sized moon low enough that a lap takes about
## an hour, so one lap passes through the moon's shadow and out again, and a check that a game
## coasted and a copy stepped over the same ticks end the same, byte for byte and event for event.
## tests/sim/kernel/test_coast.gd has the quick cases and tests/slow/test_coast_lap.gd the long ones.

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
## How long the stepped copy took over the same ticks, for comparing the two (A46).
var _last_step_ms := 0.0


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
	var stepping := Time.get_ticks_usec()
	stepped.step(ticks)
	_last_step_ms = (Time.get_ticks_usec() - stepping) / 1000.0
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
