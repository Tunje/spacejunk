extends GutTest
## Autopilot trips two levels apart (task A22): from an orbit around a central body out to a ring
## around a moon of its planet, and back, through a parking circle around the planet. A compact
## system, as in test_soi_transfers.gd, keeps the trips short. In tests/slow because each trip
## steps tens of thousands of ticks.

const GM_ROOT := 400_000_000_000_000   # 4e17 m^3/s^2
const GM_PLANET := 40_000_000_000      # 4e13 m^3/s^2, a sphere of about 750 km
const GM_MOON := 400_000_000           # 4e11 m^3/s^2, a sphere of about 63 km
const ONE := OrbitMath.ONE
# The compact system is quick in ticks but dear in delta-v (over 30 km/s each way), so the
# test ship carries far more than a real one would.
const PROPELLANT_G := 1_000_000_000_000

var sim: Sim
var keys := {}


func before_each() -> void:
	var defs := DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "root", "name": "Root", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 5_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_ROOT },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 100_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET,
				"orbit": { "parent": "root", "a_mm": 30_000_000_000, "mean_anomaly_mdeg": 45_000 } },
			{ "key": "moon", "name": "Moon", "kind": "planet", "radius_mm": 10_000_000, "visual_seed": 3,
				"deposits": [], "gm": GM_MOON,
				"orbit": { "parent": "planet", "a_mm": 400_000_000, "mean_anomaly_mdeg": 100_000 } },
			{ "key": "home_rock", "name": "Home Rock", "kind": "asteroid", "frame": "home", "pos_mm": [20_000_000, 0, 0],
				"radius_mm": 300_000, "visual_seed": 4, "deposits": [] },
			{ "key": "moon_rock", "name": "Moon Rock", "kind": "asteroid", "frame": "ring", "pos_mm": [2_000_000, 0, 0],
				"radius_mm": 300_000, "visual_seed": 5, "deposits": [] },
		],
		"frames": [
			{ "key": "home", "name": "Home", "radius_mm": 1_000_000, "orbit": { "parent": "root", "a_mm": 20_000_000_000 } },
			{ "key": "ring", "name": "Ring", "radius_mm": 1_000_000,
				"orbit": { "parent": "moon", "a_mm": 30_000_000, "mean_anomaly_mdeg": 70_000 } },
		],
		"units": [
			{ "key": "ship", "template": "starter_ship", "name": "Ship", "pos_mm": [150_000, 0, 0], "frame": "home",
				"inventory": [{ "item": "propellant", "grams": PROPELLANT_G }], "dock": null },
		],
	}, {}), "")
	sim._strict = true
	keys = {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id


func _ship() -> Dictionary:
	return sim._state["units"][keys["Ship"]]


## Flies a move_to, recording each tick's step in world position. Returns { arrived, steps, snap,
## quote }, where snap is the arrival tick's step and steps leaves it out.
func _fly(target: String) -> Dictionary:
	var quoted := sim.quote(keys["Ship"], keys[target], sim.current_tick() + 1)
	assert_eq(quoted.get("kind", ""), Transfer.KIND, str(quoted))
	sim.submit({ "type": "move_to", "unit": keys["Ship"], "args": { "target": keys[target] } })
	sim.step(quoted["depart_tick"] - sim.current_tick())
	var last := RailSystem.world_mm(sim._state, "units", keys["Ship"])
	var steps: Array[int] = []
	var snap := 0
	var arrived := false
	while sim.current_tick() < quoted["arrive_tick"] + 2:
		sim.step()
		var here := RailSystem.world_mm(sim._state, "units", keys["Ship"])
		var moved := IntMath.dist(here, last)
		last = here
		if sim.take_events().any(func(e: Dictionary) -> bool: return e["type"] == "arrived"):
			arrived = true
			snap = moved
			continue
		steps.append(moved)
	return { "arrived": arrived, "steps": steps, "snap": snap, "quote": quoted }


## No step is more than twice the larger of its neighbours: speeds change at burns, but nothing jumps.
func _assert_no_jump(steps: Array[int]) -> void:
	var worst := 0.0
	for i in range(1, steps.size() - 1):
		var around := maxi(steps[i - 1], steps[i + 1])
		if around > 0:
			worst = maxf(worst, float(steps[i]) / around)
	assert_lt(worst, 2.0, "the largest step against its neighbours")


## The arrival lands within 5 ticks of the final approach's own motion of where the path ends.
func _assert_parks(flown: Dictionary) -> void:
	var steps: Array[int] = flown["steps"]
	var recent := 0
	for i in range(maxi(0, steps.size() - 20), steps.size()):
		recent += steps[i]
	recent /= mini(20, maxi(1, steps.size()))
	print("TWO LEVELS park: snap %d m, recent step %d m" % [flown["snap"] / 1000, recent / 1000])
	assert_lt(flown["snap"], recent * 5, "parks where the path ends")


func test_out_to_a_moon_ring_through_the_planet() -> void:
	var flown := _fly("Moon Rock")
	var quoted: Dictionary = flown["quote"]
	var legs: Array = quoted["legs"]
	print("TWO LEVELS out: depart %d, %d ticks, %d legs, %d m/s; arrival snap %d m" % [
		quoted["depart_tick"], quoted["ticks"], legs.size(), quoted["dv_um_s"] / 1_000_000, flown["snap"] / 1000])
	assert_eq(legs.size(), 6, "three legs per crossing")
	assert_eq(legs[2]["orbit"]["parent"], keys["Planet"], "the parking circle")
	assert_eq(legs[5]["orbit"]["parent"], keys["Moon"])
	assert_true(flown["arrived"])
	assert_eq(_ship()["frame"], keys["Ring"])
	assert_eq(_ship()["at_target"], keys["Moon Rock"])
	_assert_no_jump(flown["steps"])
	_assert_parks(flown)
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
	assert_eq(ledger["violations"], PackedStringArray())


func test_back_from_a_moon_ring_through_the_planet() -> void:
	_fly("Moon Rock")
	sim.step(3)
	# Refuel: the way back alone needs most of a load.
	var inventory: Dictionary = _ship()["inventory"]
	sim._state["matter_start_g"] += PROPELLANT_G - inventory["propellant"]
	inventory["propellant"] = PROPELLANT_G
	var flown := _fly("Home Rock")
	var quoted: Dictionary = flown["quote"]
	print("TWO LEVELS back: depart %d, %d ticks, %d legs, %d m/s; arrival snap %d m" % [
		quoted["depart_tick"], quoted["ticks"], quoted["legs"].size(), quoted["dv_um_s"] / 1_000_000,
		flown["snap"] / 1000])
	assert_true(flown["arrived"])
	assert_eq(_ship()["frame"], keys["Home"])
	_assert_no_jump(flown["steps"])
	_assert_parks(flown)


func test_the_price_counts_every_stage() -> void:
	var quoted := sim.quote(keys["Ship"], keys["Moon Rock"], 1)
	var mass := Units.unit_mass(sim._state, sim._ctx.defs, keys["Ship"])
	var exhaust: int = BurnSystem.thruster(sim._ctx, keys["Ship"])["exhaust_mm_s"]
	assert_eq(quoted["cost_g"], OrbitMath.burn_g(mass, quoted["dv_um_s"], exhaust))
	# Both crossings and both phasings are in the delta-v: more than either crossing alone.
	var planet_ring := OrbitMath.make_orbit(GM_PLANET, 218_000_000, 0, [ONE, 0, 0], [0, 0, -ONE], 0, 0)
	planet_ring["parent"] = keys["Planet"]
	var first := SoiTransfer._outbound(sim._ctx, sim._state["frames"][keys["Home"]]["orbit"], planet_ring, 1, false)
	print("TWO LEVELS price: %d m/s in all, %d m/s to the planet circle, %d m/s from it" % [quoted["dv_um_s"] / 1_000_000,
		first["dv_um_s"] / 1_000_000, (quoted["dv_um_s"] - first["dv_um_s"]) / 1_000_000])
	assert_gt(quoted["dv_um_s"], first["dv_um_s"])
