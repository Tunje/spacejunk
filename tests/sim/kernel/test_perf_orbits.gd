extends GutTest
## The performance budget with orbits (task A17, perf_budget.md): the 20-times-slice load of
## test_perf.gd, but around a planet, with every kind of orbital work at once, plus the cost of the
## planning queries and the fastest time warp at the slice's real size. Numbers go to the log.

const SHIPS := 76
const SETTLE_TICKS := 40
const MEASURED_TICKS := 120
## How long the coast PERF line keeps the CPU busy before its sustained-clock window (A40).
const SUSTAIN_MS := 6_000
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
	var result := { "mean": total / samples.size(), "median": sorted[samples.size() / 2],
		"p99": sorted[samples.size() * 99 / 100], "max": sorted[-1] }
	print("PERF ORBITS %s: mean %d us, median %d us, p99 %d us, max %d us" % [label, result["mean"],
		result["median"], result["p99"], result["max"]])
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
	# As test_perf.gd: the quietest window's median, an alarm over budget and a failure at three
	# times it; the 99th percentile is reported (A45, A45b).
	preload("res://tests/sim/kernel/timing.gd").alarm(self, "ORBITS step+view", both, MEAN_ALARM_USEC)
	if total["p99"] >= SPIKE_ALARM_USEC:
		print("PERF ALARM: 99th percentile step and view %d us, over %d us" % [total["p99"], SPIKE_ALARM_USEC])


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
	# A fast quote also searches the Lambert arc that leaves at once (A47): reported, with a generous
	# limit, since cores and cycles quote cheap and only a player's fast order or comparison pays it.
	start = Time.get_ticks_usec()
	for i in 10:
		sim.quote(id, keys["Rock 2"], i, "fast")
	var fast_us := float(Time.get_ticks_usec() - start) / 10
	print("PERF ORBITS queries: quote (window) %.0f us; fast quote with the arc %.0f us; check of a %d-tick burn %d us" % [
		quote_us, fast_us, checked["detail"]["burn_ticks"], check_us])
	assert_lt(quote_us, 5000.0)
	assert_lt(fast_us, 100_000.0, "a fast quote stays well under a frame's worth of work")


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


## The coast warp's cost at 20 times the slice (A35; budget 8 ms a jump, orbital_flight.md 11.22):
## the same 76 ships and 4 frames with no orders, so every ship sits still in its frame or rides
## its orbit, and each coast call is one horizon pass, one closed-form pass and one step. The ships
## on orbits move out from 2,000 km: in the frames' band, at 700 to 1,000 km, they would always be
## close enough to join one, which rightly stops a coast.
func test_a_coast_jump_at_twenty_times_the_slice() -> void:
	var dirs := OrbitMath.directions(0, 0, 0)
	for i in SHIPS:
		var unit: Dictionary = sim._state["units"][ships[i]["id"]]
		if unit["orbit"].is_empty():
			continue
		unit["orbit"] = OrbitMath.make_orbit(GM_PLANET, 2_000_000_000 + 10_000_000 * i, ONE / 50, dirs[0], dirs[1],
			OrbitMath.TURN / SHIPS * i, 0)
		unit["orbit"]["parent"] = keys["Planet"]
		unit["pos_mm"] = OrbitMath.position_at(unit["orbit"], 0)
	sim._ctx.index.clear()
	sim.step(SETTLE_TICKS)
	# The budget is judged at the clock a long session runs at (A40). A CPU's turbo lasts a few
	# seconds: the first window is at turbo only if the CPU was idle before it, as when this test
	# runs alone, and the second, after SUSTAIN_MS more of the same work, is at the sustained clock.
	# Both are reports: gate machines run loaded.
	var first := _coast_window()
	var busy := Time.get_ticks_msec()
	while Time.get_ticks_msec() - busy < SUSTAIN_MS:
		sim.coast(100_000)
	var later := _coast_window()
	for window: Array in [["at the start (turbo if the CPU was idle)", first], ["after 6 s of work (sustained clock)", later]]:
		var figures: Dictionary = window[1]
		print("PERF ORBITS coast at 20x slice, %s: %.2f ms a jump (a stepped tick and a horizon pass, budget 8 ms at the sustained clock), %.2f ms a call, %d ticks a call, capped by %s; a plain step %.2f ms" % [
			window[0], figures["per_round"], figures["per_call"], figures["ticks_per_call"], str(figures["caps"]),
			figures["per_step"]])
	assert_gt(first["ticks_per_call"], 1, "the world coasts rather than stepping")
	assert_lt(later["per_call"], 80.0, "ten times the budget fails; the PERF line is the measure")


## Some ticks stepped, then 40 coast calls, timed: { per_step, per_call, per_round, ticks_per_call,
## caps }.
func _coast_window() -> Dictionary:
	var stepped := Time.get_ticks_usec()
	sim.step(20)
	var per_step := (Time.get_ticks_usec() - stepped) / 1000.0 / 20
	var calls := 0
	var ticks := 0
	var caps := {}
	var rounds := sim.coast_rounds
	var start := Time.get_ticks_usec()
	while calls < 40:
		var done: Dictionary = sim.coast(100_000)
		ticks += done["ticks"]
		calls += 1
		caps[done["capped_by"]] = caps.get(done["capped_by"], 0) + 1
	var spent_ms := (Time.get_ticks_usec() - start) / 1000.0
	return { "per_step": per_step, "per_call": spent_ms / calls, "per_round": spent_ms / (sim.coast_rounds - rounds),
		"ticks_per_call": ticks / calls, "caps": caps }
