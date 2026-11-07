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
	while game.current_tick() < 125_000:
		game.coast(125_000 - game.current_tick())
	game.take_events()
	var coasted := _copy(game)
	var calls := _same_both_ways(game, coasted, 10_000, false)
	# Since A46 the edge itself is walked to within the horizon pass; what is left is the battery
	# filling to its last joule.
	assert_lt(longest_power_run, 10, "an edge is coasted up to, not stepped through")
	assert_lt(calls, 12)


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


## The battery window search as A33 wrote it, doubling up from 1, as the reference for A38's.
func _doubling_window(part: Dictionary, battery: Dictionary, limits: Dictionary) -> int:
	var low := 0
	var high := 1
	while high < PowerSystem.MAX_BATTERY_WINDOW and PowerSystem._battery_holds(part, battery, limits, high):
		low = high
		high *= 2
	while high - low > 1:
		var mid := (low + high) / 2
		if PowerSystem._battery_holds(part, battery, limits, mid):
			low = mid
		else:
			high = mid
	return low


## A38: the battery window found from a straight-line guess is the one doubling finds, for random
## stores, remainders, rates and limits, draining, charging and both.
func test_the_guessed_battery_window_is_the_doubling_one() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3801
	var checked := 0
	for n in 4000:
		var capacity := rng.randi_range(1, 50_000_000)
		var limits := { "capacity_j": capacity, "max_discharge_w": rng.randi_range(1, 20_000),
			"max_charge_w": rng.randi_range(1, 20_000) }
		var part := { "stored_j": rng.randi_range(0, capacity), "charge_remainder": rng.randi_range(0, 9),
			"discharge_remainder": rng.randi_range(0, 9) }
		var drawn := rng.randi_range(0, 20_000) if rng.randi_range(0, 2) > 0 else 0
		var charged := rng.randi_range(0, 20_000) if rng.randi_range(0, 2) > 0 else 0
		var battery := { "discharged_w": drawn, "charged_w": charged,
			"stored_w": charged * rng.randi_range(500, 1000) / 1000 }
		if drawn == 0 and charged == 0:
			continue
		# Only regimes that hold now are searched, as _battery_horizon screens the rest.
		if not PowerSystem._battery_holds(part, battery, limits, 0):
			continue
		checked += 1
		var expected := _doubling_window(part, battery, limits)
		var got := PowerSystem._battery_window(part, battery, limits)
		if got != expected:
			assert_eq(got, expected, "case %d: %s %s %s" % [n, str(part), str(battery), str(limits)])
			return
	gut.p("%d battery regimes compared" % checked)
	assert_gt(checked, 1000)


## PowerSystem's horizon worked out unit by unit, as A33 did, for A38's grouped one to match.
func _horizon_unit_by_unit(sim: Sim) -> int:
	var ctx := sim._ctx
	var power: PowerSystem
	for system in sim._systems:
		if system is PowerSystem:
			power = system
	var flows: Dictionary = ctx.flows[PowerSystem.FLOW_KEY]
	var casters := PowerSystem._coast_casters(ctx.state)
	var skip := SimSystem.NO_LIMIT
	var ids: Array = ctx.state["units"].keys()
	ids.sort()
	for id: int in ids:
		var index := UnitIndex.of(ctx, id)
		var shed := false
		for part_id: int in index["ids"]:
			shed = shed or ctx.state["parts"][part_id]["shed"]
			var until: int = ctx.state["parts"][part_id]["shed_until_tick"]
			if until > sim.current_tick():
				skip = mini(skip, until - sim.current_tick() - 1)
		if not index["generators"].is_empty() and not casters.is_empty():
			skip = mini(skip, PowerSystem._shadow_horizon(ctx, id, casters))
		var batteries: Dictionary = flows[id]["batteries"]
		var battery_ids: Array = batteries.keys()
		battery_ids.sort()
		for part_id: int in battery_ids:
			skip = mini(skip, power._battery_horizon(ctx, part_id, batteries[part_id], shed))
	return maxi(skip, 0)


## A38: the horizon with one shadow bound per frame for the units sitting still in it is the one
## worked out unit by unit, in the 20-times-slice world of test_perf_orbits.gd, its ships on orbits
## moved out from 2,000 km, through shadow edges and out again.
func test_the_grouped_power_horizon_is_the_unit_by_unit_one() -> void:
	var perf: GutTest = load("res://tests/sim/kernel/test_perf_orbits.gd").new()
	perf.before_each()
	var sim: Sim = perf.sim
	var dirs := OrbitMath.directions(0, 0, 0)
	for i in perf.ships.size():
		var unit: Dictionary = sim._state["units"][perf.ships[i]["id"]]
		if unit["orbit"].is_empty():
			continue
		unit["orbit"] = OrbitMath.make_orbit(perf.GM_PLANET, 2_000_000_000 + 10_000_000 * i, OrbitMath.ONE / 50,
			dirs[0], dirs[1], OrbitMath.TURN / perf.ships.size() * i, 0)
		unit["orbit"]["parent"] = perf.keys["Planet"]
		unit["pos_mm"] = OrbitMath.position_at(unit["orbit"], 0)
	sim._ctx.index.clear()
	sim.step(40)
	var power: PowerSystem
	for system in sim._systems:
		if system is PowerSystem:
			power = system
	var zero := 0
	# Spaced to pass shadow edges. Since A46 the unit-by-unit reference walks every unit near an edge
	# with no limit, so each comparison is dear; ten are enough.
	for n in 10:
		var grouped := power.horizon(sim._ctx)
		assert_eq(grouped, _horizon_unit_by_unit(sim), "at tick %d" % sim.current_tick())
		zero += int(grouped == 0)
		sim.step(150)
	perf.free()
	gut.p("10 horizons compared, %d of them 0" % zero)
	assert_lt(zero, 8, "most of them bound something")
