extends GutTest
## PowerSystem's coast horizons in the cases that held it at 0 tick by tick in A33 (task A35).
## - D's case: the new start's probe at its cluster's shadow edge, where a 10 km slack capped
##   about 1,700 ticks in a row.
## - C's cases from C17: a full battery taking a trickle while mining, and on a gravity-field lap.
##   909 of 912 and 279 of 283 calls were capped by power.
## Each case steps one copy and coasts another over the same ticks, then compares the saves byte for
## byte and the events one for one, as test_coast.gd and tests/sim/industry/test_coast_industry.gd do.

const SHIP := 23
const ROCK := 2
const DEPOSIT := 3
const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 10_000_000_000
const AU_MM := 149_597_870_700_000
const ONE := OrbitMath.ONE

## What capped each coast call in the last _same_both_ways, by cap name, "" for none.
var caps := {}
## The longest run of calls in a row capped by power in the last _same_both_ways.
var longest_power_run := 0


func _same_both_ways(stepped: Sim, coasted: Sim, ticks: int, strict: bool = true) -> int:
	stepped._strict = strict
	stepped.step(ticks)
	var stepped_events := stepped.take_events()
	var coasted_events: Array[Dictionary] = []
	var calls := 0
	var left := ticks
	var run := 0
	caps = {}
	longest_power_run = 0
	while left > 0:
		var done: Dictionary = coasted.coast(left)
		left -= done["ticks"]
		calls += 1
		caps[done["capped_by"]] = caps.get(done["capped_by"], 0) + 1
		run = run + 1 if done["capped_by"] == "power" else 0
		longest_power_run = maxi(longest_power_run, run)
		coasted_events.append_array(coasted.take_events())
	gut.p("coast calls %d, capped by %s, longest run of power caps %d" % [calls, str(caps), longest_power_run])
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


func test_the_new_start_passes_its_shadow_edge_in_a_few_calls() -> void:
	var game := Sim.new_game("new_start", 1)
	# Up to just short of the edge D found near tick 130,800, by coasting, which the rest checks.
	while game.current_tick() < 110_000:
		game.coast(110_000 - game.current_tick())
	game.take_events()
	var coasted := _copy(game)
	var calls := _same_both_ways(game, coasted, 30_000, false)
	assert_lt(longest_power_run, 20, "an edge is coasted up to, not stepped through")
	assert_lt(calls, 40)


## C's mining repro: the ship parked at the reference rock mines to a full hold, its battery full and
## taking a trickle it can't store.
func test_mining_with_a_full_battery_coasts_with_few_calls() -> void:
	var stepped := Sim.new_game("reference", 12345)
	var ship: Dictionary = stepped._state["units"][SHIP]
	ship["dock"] = {}
	ship["at_target"] = ROCK
	ship["pos_mm"] = stepped._state["bodies"][ROCK]["pos_mm"].duplicate()
	stepped._state["deposits"][DEPOSIT]["found"] = true
	stepped._ctx.index.clear()
	var laser := 0
	for part: int in Units.sorted_part_ids(stepped._state, SHIP):
		if Units.module_of(stepped._state, stepped._ctx.defs, part)["capabilities"].has("mine"):
			laser = part
	stepped.submit({ "type": "start_mining", "unit": SHIP, "args": { "deposit": DEPOSIT, "module": laser } })
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	var calls := _same_both_ways(stepped, coasted, 2_500)
	assert_eq(stepped._state["units"][SHIP]["task"], 0, "the hold filled and the order ended")
	assert_lt(calls, 20, "was 912 calls before A35")


## C's gravity-field repro: the starter ship on a low orbit of a dense planet measures a lap of about
## 630 ticks.
func test_a_gravity_field_lap_coasts_with_few_calls() -> void:
	var defs := DataLoader.load_defs()
	var stepped := Sim.new()
	stepped._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(stepped._ctx, {
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
	for id: int in stepped._state["bodies"]:
		if stepped._state["bodies"][id]["name"] == "Planet":
			planet = id
	for id: int in stepped._state["units"]:
		ship = id
	var orbit := OrbitMath.make_orbit(GM_PLANET, 100_000_000, 0, [0, 0, ONE], [-ONE, 0, 0], 0, 0)
	orbit["parent"] = planet
	stepped._state["units"][ship]["orbit"] = orbit
	stepped._state["units"][ship]["pos_mm"] = OrbitMath.position_at(orbit, 0)
	stepped._ctx.index.clear()
	stepped.submit({ "type": "measure", "unit": ship, "args": { "target": planet, "kind": "gravity_field" } })
	stepped.step()
	stepped.take_events()
	var coasted := _copy(stepped)
	var calls := _same_both_ways(stepped, coasted, 800)
	assert_eq(stepped._state["science"]["paid"].size(), 1, "the lap paid")
	assert_lt(calls, 30, "was 283 calls before A35")
