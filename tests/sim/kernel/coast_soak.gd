extends RefCounted
## The seeded coast soak (task A35): random games run once stepped and once coasted, compared at every
## coast return by state hash and events, and by save bytes at the end. Shared by
## tests/slow/test_coast_soak.gd, which runs a few fixed seeds in the gate, and tools/coast_soak.gd,
## which runs many for an occasional deep check.
##
## Most seeds are a probe round a Frost-sized moon, with random:
## - an orbit, eccentricity and phase;
## - battery charge and stored heat;
## - a planned burn, or a landing and then a take-off, each at a random tick, any of which may be
##   refused.
## Every fourth seed (3, 7, 11 ...) is the new start coasted to a random tick, then compared over a
## window in which the probe flies to up to three rocks in its cluster (A37).
## Seed 1 is D's shadow edge case from A35: new start seed 1, ticks 125,000 to 135,000.

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const GM_MOON := 1_765_800
const AU_MM := 149_597_870_700_000
const MOON_R_MM := 60_000_000
const ONE := OrbitMath.ONE


## Runs one seed over `ticks` ticks. Returns { ok, message, calls, ticks, caps, events }, with caps
## and events counted by name.
static func run_seed(seed: int, ticks: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	# Mixed, since RandomNumberGenerator gives near seeds near games.
	rng.seed = hash(seed * 2_654_435_761 + 97)
	var stepped: Sim
	var actions: Array = []
	if seed == 1:
		stepped = _new_start(1, 125_000)
		ticks = 10_000
	elif seed % 4 == 3:
		stepped = _new_start(rng.randi_range(1, 1000), rng.randi_range(0, 250_000))
		actions = _moves(stepped, rng, ticks)
	else:
		var built := _moon_probe(rng, ticks)
		stepped = built[0]
		actions = built[1]
		ticks = built[2]
	var coasted := Sim.from_save(stepped.to_save())
	if coasted == null:
		return _result(false, "seed %d: the copy didn't load: %s" % [seed, Sim.last_error()], 0, 0, {})
	return _compare(seed, stepped, coasted, ticks, actions)


## Up to three move_to orders for the new start's probe, to rocks in its frame at random ticks. One
## given before the last has arrived is refused or replaces it; either way both copies do the same.
static func _moves(sim: Sim, rng: RandomNumberGenerator, ticks: int) -> Array:
	var probe := 0
	for id: int in _sorted(sim._state["units"]):
		if sim._state["units"][id]["name"] == "Probe":
			probe = id
	if probe == 0:
		return []
	var frame: int = sim._state["units"][probe]["frame"]
	var rocks: Array = []
	for id: int in _sorted(sim._state["bodies"]):
		if sim._state["bodies"][id].get("frame", 0) == frame and frame != 0:
			rocks.append(id)
	var actions: Array = []
	if rocks.is_empty():
		return actions
	for n in rng.randi_range(1, 3):
		actions.append([rng.randi_range(0, ticks - 1), { "type": "move_to", "unit": probe,
			"args": { "target": rocks[rng.randi_range(0, rocks.size() - 1)] } }])
	actions.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	return actions


static func _sorted(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids


static func _result(ok: bool, message: String, calls: int, ticks: int, caps: Dictionary) -> Dictionary:
	return { "ok": ok, "message": message, "calls": calls, "ticks": ticks, "caps": caps, "events": {} }


## Coasts `coasted` and steps `stepped` by what each coast call advanced, comparing after every call.
## Each action is [tick, command] and goes to both at that tick.
static func _compare(seed: int, stepped: Sim, coasted: Sim, ticks: int, actions: Array) -> Dictionary:
	var start := stepped.current_tick()
	var end := start + ticks
	var calls := 0
	var caps := {}
	var next := 0
	var seen := {}
	while coasted.current_tick() < end:
		while next < actions.size() and actions[next][0] <= coasted.current_tick() - start:
			stepped.submit(actions[next][1].duplicate(true))
			coasted.submit(actions[next][1].duplicate(true))
			next += 1
		var until := end
		if next < actions.size():
			until = mini(end, start + actions[next][0])
		var done: Dictionary = coasted.coast(until - coasted.current_tick())
		calls += 1
		caps[done["capped_by"]] = caps.get(done["capped_by"], 0) + 1
		stepped.step(done["ticks"])
		var tick := coasted.current_tick()
		if stepped.current_tick() != tick:
			return _result(false, "seed %d: coasted to %d, stepped to %d" % [seed, tick, stepped.current_tick()],
				calls, tick - start, caps)
		var events := coasted.take_events()
		for event: Dictionary in events:
			var name: String = event["type"]
			if name == "command_rejected":
				name += ":" + str(event["data"].get("reason", ""))
			seen[name] = seen.get(name, 0) + 1
		if events != stepped.take_events():
			return _result(false, "seed %d: the events differ at tick %d" % [seed, tick], calls, tick - start, caps)
		if coasted.state_hash() != stepped.state_hash():
			return _result(false, "seed %d: the state differs at tick %d, after a coast capped by '%s'" % [
				seed, tick, done["capped_by"]], calls, tick - start, caps)
	if coasted.to_save() != stepped.to_save():
		return _result(false, "seed %d: the saves differ at the end" % seed, calls, ticks, caps)
	var result := _result(true, "", calls, ticks, caps)
	result["events"] = seen
	return result


static func _new_start(game_seed: int, from_tick: int) -> Sim:
	var game := Sim.new_game("new_start", game_seed)
	while game.current_tick() < from_tick:
		game.coast(from_tick - game.current_tick())
	game.take_events()
	return game


## [the game, its actions, the ticks to run]: the probe of test_coast.gd, randomised. A landing and
## take-off lengthen the run to take them in.
static func _moon_probe(rng: RandomNumberGenerator, ticks: int) -> Array:
	var defs := DataLoader.load_defs()
	var sim := Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	var error := ScenarioBuilder.populate(sim._ctx, {
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
	}, {})
	assert(error == "", error)
	var keys := {}
	for table: String in ["bodies", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	var probe_id: int = keys["Probe"]
	var moon_id: int = keys["Moon"]
	var probe: Dictionary = sim._state["units"][probe_id]
	# Above low flight at periapsis, in the planet's orbital plane so laps can cross the shadow.
	var periapsis := MOON_R_MM + rng.randi_range(25_000_000, 120_000_000)
	var e := rng.randi_range(0, ONE / 5)
	var a := IntMath.mul_div(periapsis, ONE, ONE - e)
	var plane: Dictionary = sim._state["bodies"][moon_id]["orbit"]
	probe["orbit"] = OrbitMath.make_orbit(GM_MOON, a, e, plane["p_q30"], plane["q_q30"],
		rng.randi_range(0, OrbitMath.TURN - 1), 0)
	probe["orbit"]["parent"] = moon_id
	probe["pos_mm"] = OrbitMath.position_at(probe["orbit"], 0)
	var charge := rng.randi_range(0, 100)
	for part_id in Units.part_ids(sim._state, probe_id):
		var part: Dictionary = sim._state["parts"][part_id]
		if part.has("stored_j") and part["stored_j"] > 0:
			part["stored_j"] = part["stored_j"] * charge / 100
	probe["heat_stored_j"] = [0, 0, rng.randi_range(0, 60_000_000)][rng.randi_range(0, 2)]
	sim._ctx.index.clear()
	var actions: Array = []
	# A burn, or a landing and a take-off, or neither: a planned burn holds the engine a landing needs.
	var plan := rng.randi_range(0, 4)
	if plan <= 1:
		var at := rng.randi_range(0, ticks - 1)
		actions.append([at, { "type": "plan_burn", "unit": probe_id, "args": {
			"tick": at + rng.randi_range(1, 2_000), "prograde_um_s": rng.randi_range(-3_000_000, 3_000_000),
			"normal_um_s": rng.randi_range(-500_000, 500_000), "radial_um_s": rng.randi_range(-500_000, 500_000) } }])
	elif plan <= 3:
		var at := rng.randi_range(0, ticks / 4)
		var cell := LandingSystem.cell_below(sim._ctx, moon_id, OrbitMath.position_at(probe["orbit"], at))
		var land := { "type": "land", "unit": probe_id, "args": { "body": moon_id, "cell": cell } }
		actions.append([at, land])
		# The descent's length from tick 0, near enough, so the take-off mostly comes after touchdown.
		var checked := sim.check(land)
		var descent: int = checked["detail"].get("ticks", 0) if checked["ok"] else 0
		var up := at + descent + rng.randi_range(-200, 2_000)
		actions.append([up, { "type": "take_off", "unit": probe_id, "args": {
			"altitude_mm": rng.randi_range(30_000_000, 100_000_000) } }])
		ticks = maxi(ticks, up + 2 * descent + 1_000)
	actions.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	return [sim, actions, ticks]
