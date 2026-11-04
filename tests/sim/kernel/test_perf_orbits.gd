extends GutTest
## The performance budget with orbits (task A17, perf_budget.md): the 20-times-slice load of
## test_perf.gd, but around a planet, with every kind of orbital work at once, plus the cost of the
## planning queries and the fastest time warp at the slice's real size. Numbers go to the log.

const SHIPS := 76
const SETTLE_TICKS := 40
const MEASURED_TICKS := 120
const MEAN_ALARM_USEC := 50_000
const SPIKE_ALARM_USEC := 100_000
const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const AU_MM := 149_597_870_700_000
const FRAMES := 4
const ONE := OrbitMath.ONE

var sim: Sim
var keys := {}
var ships: Array[Dictionary] = []


func before_each() -> void:
	var defs := DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	var bodies := [
		{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
			"visual_seed": 1, "deposits": [], "gm": GM_STAR },
		{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
			"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM } },
	]
	var frames := []
	for f in FRAMES:
		frames.append({ "key": "frame%d" % f, "name": "Frame %d" % f, "radius_mm": 1_000_000,
			"orbit": { "parent": "planet", "a_mm": 700_000_000 + 100_000_000 * f, "mean_anomaly_mdeg": 47_000 * f } })
		bodies.append({ "key": "rock%d" % f, "name": "Rock %d" % f, "kind": "asteroid", "frame": "frame%d" % f,
			"pos_mm": [30_000_000, 0, 0], "radius_mm": 300_000, "visual_seed": 10 + f, "deposits": [] })
	var units := []
	for i in SHIPS:
		units.append({ "key": "ship%d" % i, "template": "starter_ship", "name": "Ship %d" % i,
			"pos_mm": [150_000 + 1000 * i, 0, 0], "frame": "frame%d" % (i % FRAMES),
			"inventory": [{ "item": "propellant", "grams": 1_000_000 }], "dock": null })
	assert_eq(ScenarioBuilder.populate(sim._ctx, { "bodies": bodies, "frames": frames, "units": units }, {}), "")
	keys = {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	ships = []
	for i in SHIPS:
		var id: int = keys["Ship %d" % i]
		var job: String = ["route", "transfer", "burn", "coast"][i % 4]
		if job == "burn" or job == "coast":
			var unit: Dictionary = sim._state["units"][id]
			var dirs := OrbitMath.directions(0, 0, 0)
			unit["orbit"] = OrbitMath.make_orbit(GM_PLANET, 750_000_000 + 1_000_000 * i, ONE / 50, dirs[0], dirs[1],
				OrbitMath.TURN / SHIPS * i, 0)
			unit["orbit"]["parent"] = keys["Planet"]
			unit["frame"] = 0
		ships.append({ "id": id, "job": job, "home": i % FRAMES, "flip": false })
	sim._ctx.index.clear()


## Gives every idle ship its next order, so all orbital load types stay busy.
func _keep_busy() -> void:
	for ship: Dictionary in ships:
		var id: int = ship["id"]
		var unit: Dictionary = sim._state["units"][id]
		unit["inventory"]["propellant"] = 1_000_000
		match ship["job"]:
			"route":
				if unit["task"] == 0:
					ship["flip"] = not ship["flip"]
					var target: int = keys["Rock %d" % ship["home"]] if ship["flip"] else id
					if target != id:
						sim.submit({ "type": "move_to", "unit": id, "args": { "target": target } })
			"transfer":
				if unit["task"] == 0:
					var other: int = (ship["home"] + 1 + int(ship["flip"])) % FRAMES
					ship["flip"] = not ship["flip"]
					sim.submit({ "type": "move_to", "unit": id, "args": { "target": keys["Rock %d" % other] } })
			"burn":
				if unit["burn"].is_empty() and unit["burns"].is_empty():
					sim.submit({ "type": "plan_burn", "unit": id, "args": { "tick": sim.current_tick() + 1,
						"prograde_um_s": 2_000_000 if ship["flip"] else -2_000_000, "normal_um_s": 0, "radial_um_s": 0 } })
					ship["flip"] = not ship["flip"]


func _report(label: String, samples: Array[int]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0
	for sample: int in samples:
		total += sample
	var result := { "mean": total / samples.size(), "p99": sorted[samples.size() * 99 / 100], "max": sorted[-1] }
	print("PERF ORBITS %s: mean %d us, p99 %d us, max %d us" % [label, result["mean"], result["p99"], result["max"]])
	return result


func test_an_orbital_tick_with_one_view_stays_inside_the_budget() -> void:
	for i in SETTLE_TICKS:
		_keep_busy()
		sim.step()
		sim.take_events()
	var ticks: Array[int] = []
	var views: Array[int] = []
	var both: Array[int] = []
	var ops := {}
	for i in MEASURED_TICKS:
		_keep_busy()
		var start := Time.get_ticks_usec()
		sim.step()
		var stepped := Time.get_ticks_usec()
		sim.view()
		var viewed := Time.get_ticks_usec()
		sim.take_events()
		ticks.append(stepped - start)
		views.append(viewed - stepped)
		both.append(viewed - start)
		for ship: Dictionary in ships:
			ops[sim._state["units"][ship["id"]]["op"]["type"]] = true
	print("PERF ORBITS load: %d units, %d parts, operations seen %s" % [
		sim._state["units"].size(), sim._state["parts"].size(), str(ops.keys())])
	_report("step", ticks)
	_report("view", views)
	var total := _report("step+view", both)
	for op_type: String in ["moving", "waiting", "burning"]:
		assert_true(ops.has(op_type), op_type)
	assert_lt(total["mean"], MEAN_ALARM_USEC)
	assert_lt(total["p99"], SPIKE_ALARM_USEC)


func test_the_cost_of_planning_queries() -> void:
	var id: int = keys["Ship 1"]
	var start := Time.get_ticks_usec()
	for i in 50:
		sim.quote(id, keys["Rock 2"], i)
	var quote_us := float(Time.get_ticks_usec() - start) / 50
	var orbiter: int = keys["Ship 2"]
	var command := { "type": "plan_burn", "unit": orbiter, "args": {
		"tick": 1, "prograde_um_s": 50_000_000, "normal_um_s": 0, "radial_um_s": 0 } }
	start = Time.get_ticks_usec()
	var checked := sim.check(command)
	var check_us := Time.get_ticks_usec() - start
	print("PERF ORBITS queries: quote (window) %.0f us; check of a %d-tick burn %d us" % [
		quote_us, checked["detail"]["burn_ticks"], check_us])
	assert_lt(quote_us, 5000.0)


## The fastest time warp at the slice's real size: the reference scenario with the ship on a trip,
## stepping as fast as it can with one view per 8 ticks, as a frame at 8x would.
func test_time_warp_at_slice_size() -> void:
	var slice := Sim.new_game("reference", 12345)
	slice.submit({ "type": "undock", "unit": 23, "args": {} })
	slice.step(110)
	slice.submit({ "type": "move_to", "unit": 23, "args": { "target": 2 } })
	slice.step(2)
	var start := Time.get_ticks_usec()
	var count := 2000
	for i in count:
		slice.step()
		if i % 8 == 0:
			slice.view()
	var per_tick := float(Time.get_ticks_usec() - start) / count
	var warp := 1_000_000.0 / per_tick / Sim.TICKS_PER_SECOND
	print("PERF ORBITS slice: %.0f us per tick, so up to %.0fx time warp on one core" % [per_tick, warp])
	assert_gt(warp, 8.0)
