extends SceneTree
## Stage 0 of real orbits (task A54, real_orbits.md section 10): the measurements the later stages
## depend on, on the real sim with new_start.json's Frost and cluster orbit.
## - Precision: how exactly the integer orbits hold a relative state at docking scale. A burn of a
##   few mm/s through from_state, and two craft metres apart, against the same orbit records
##   propagated in doubles.
## - The cost of a flown quote: each piece timed, then a 50 km, 30 minute rendezvous priced as the
##   flown plan would be (two Lambert solves, the burns stepped, the coasts on rails), and as if
##   the whole trip were stepped.
## - A six-drone fleet's warp: six mining drones round Frost, all burning at once and then all
##   coasting, timed per tick of the real Sim.step.
## Measures only: nothing is saved, and no sim code is changed by it.
##
## Run: godot --headless --path . -s tools/real_orbits_measure.gd

const ONE := OrbitMath.ONE
const DRONES := 6
const RUNS := 2000

var sim: Sim
var keys := {}
var frost := 0
var gm := 0
var cluster: Dictionary


func _init() -> void:
	sim = Sim.new_game("new_start", 1)
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	frost = keys["Frost"]
	gm = sim._state["bodies"][frost]["gm"]
	cluster = sim._state["frames"][keys["Cluster"]]["orbit"]
	print("== Frost GM %d (1000 m^3/s^2), cluster a %d mm, e_q30 %d, period %d ticks" % [gm, cluster["a_mm"],
		cluster["e_q30"], int(cluster["period_subticks"]) / OrbitMath.SUB_TICKS])
	_precision()
	_costs()
	_fleet()
	quit()


# ------------------------------------------------------------------------------ precision

func _precision() -> void:
	print("\n== Precision at docking scale")
	var period := int(cluster["period_subticks"]) / OrbitMath.SUB_TICKS
	# 1. A burn's velocity change through from_state, at 64 places round the orbit.
	for dv_um_s: int in [0, 1_000, 10_000, 100_000, 1_000_000]:
		var worst_dv := 0
		var worst_r := 0
		for k in 64:
			var tick := period * k / 64
			var now := OrbitMath.state_at(cluster, gm, tick)
			var along := OrbitMath.unit(now["v"])
			var v: Array[int] = []
			for axis in 3:
				v.append(int(now["v"][axis]) + OrbitMath.smul_div(along[axis], dv_um_s, ONE))
			var after := OrbitMath.from_state(now["r"], v, gm, tick)
			after["parent"] = frost
			var back := OrbitMath.state_at(after, gm, tick)
			worst_r = maxi(worst_r, IntMath.dist(back["r"], now["r"]))
			worst_dv = maxi(worst_dv, IntMath.dist(back["v"], v))
		print("  burn of %7d um/s through from_state: worst velocity error %d um/s, position jump %d mm"
			% [dv_um_s, worst_dv, worst_r])
	# 2. Two craft 2 m apart, closing at 5 cm/s, for an orbit: the integer relative state against
	# the same two orbit records in doubles.
	var start := OrbitMath.state_at(cluster, gm, 0)
	var radial := OrbitMath.unit(start["r"])
	var along := OrbitMath.unit(start["v"])
	var r2: Array[int] = []
	var v2: Array[int] = []
	for axis in 3:
		r2.append(int(start["r"][axis]) + OrbitMath.smul_div(along[axis], 2_000, ONE))
		v2.append(int(start["v"][axis]) - OrbitMath.smul_div(along[axis], 50_000, ONE)
			+ OrbitMath.smul_div(radial[axis], 10_000, ONE))
	var other := OrbitMath.from_state(r2, v2, gm, 0)
	other["parent"] = frost
	var worst_pos := 0.0
	var worst_vel := 0.0
	var worst_jitter := 0.0
	var last_rel: Array = []
	var last_vel: Array = []
	var ticks := mini(period, 72_000)
	for t in range(0, ticks, 7):
		var a := OrbitMath.state_at(cluster, gm, t)
		var b := OrbitMath.state_at(other, gm, t)
		var fa := _float_state(cluster, t)
		var fb := _float_state(other, t)
		var rel: Array = []
		var vel: Array = []
		for axis in 3:
			rel.append(int(b["r"][axis]) - int(a["r"][axis]))
			vel.append(int(b["v"][axis]) - int(a["v"][axis]))
			worst_pos = maxf(worst_pos, absf(rel[axis] - (fb[0][axis] - fa[0][axis])))
			worst_vel = maxf(worst_vel, absf(vel[axis] - (fb[1][axis] - fa[1][axis])))
		last_rel = rel
		last_vel = vel
	# Tick-to-tick: the change in relative position over one tick against the relative velocity.
	for t in range(0, 3000):
		var a0 := OrbitMath.position_at(cluster, t)
		var b0 := OrbitMath.position_at(other, t)
		var a1 := OrbitMath.position_at(cluster, t + 1)
		var b1 := OrbitMath.position_at(other, t + 1)
		var va: Array = OrbitMath.state_at(cluster, gm, t)["v"]
		var vb: Array = OrbitMath.state_at(other, gm, t)["v"]
		for axis in 3:
			var moved := (b1[axis] - a1[axis]) - (b0[axis] - a0[axis])
			var expected: float = (vb[axis] - va[axis]) / 10000.0
			worst_jitter = maxf(worst_jitter, absf(moved - expected))
	print("  two craft 2 m apart closing at 5 cm/s, over %d ticks: relative position error %.1f mm, relative velocity error %.0f um/s"
		% [ticks, worst_pos, worst_vel])
	print("  one tick's relative motion against relative velocity x 0.1 s: worst %.1f mm" % worst_jitter)
	print("  (last relative state: %s mm, %s um/s)" % [str(last_rel), str(last_vel)])


## [r mm, v um/s] of an elliptic orbit record in doubles.
func _float_state(orbit: Dictionary, tick: int) -> Array:
	var a := float(orbit["a_mm"])
	var e := float(orbit["e_q30"]) / ONE
	var b := float(orbit["b_mm"])
	var period_s := float(orbit["period_subticks"]) / OrbitMath.SUB_TICKS / Sim.TICKS_PER_SECOND
	var m := TAU * float(orbit["m0_angle"]) / OrbitMath.TURN \
		+ TAU * float(tick - int(orbit["epoch_tick"])) * OrbitMath.SUB_TICKS / float(orbit["period_subticks"])
	var big_e := m
	for i in 30:
		big_e -= (big_e - e * sin(big_e) - m) / (1.0 - e * cos(big_e))
	var x := a * (cos(big_e) - e)
	var y := b * sin(big_e)
	var rate := TAU / period_s / (1.0 - e * cos(big_e))  # dE/dt
	var vx := -a * sin(big_e) * rate * 1000.0
	var vy := b * cos(big_e) * rate * 1000.0
	var r: Array = []
	var v: Array = []
	for axis in 3:
		var p := float(orbit["p_q30"][axis]) / ONE
		var q := float(orbit["q_q30"][axis]) / ONE
		r.append(x * p + y * q)
		v.append(vx * p + vy * q)
	return [r, v]


# ------------------------------------------------------------------------------ flown quote

func _costs() -> void:
	print("\n== The cost of a flown quote")
	var ctx := sim._ctx
	var now := OrbitMath.state_at(cluster, gm, 0)
	var position_us := _per_call(func() -> void: OrbitMath.position_at(cluster, 12_345))
	var state_us := _per_call(func() -> void: OrbitMath.state_at(cluster, gm, 12_345))
	var from_us := _per_call(func() -> void: OrbitMath.from_state(now["r"], now["v"], gm, 0))
	var held: Array = [0, 0, 0]
	var apply_us := _per_call(func() -> void: BurnSystem._apply(ctx, cluster.merged({ "parent": frost }), 0, [1000, 0, 0], held))
	var carry: Array = [0, 0, 0]
	var advance_us := _per_call(func() -> void: LowFlight.advance(ctx, frost, now["r"], now["v"], carry))
	print("  position_at %.1f us, state_at %.1f us, from_state %.1f us" % [position_us, state_us, from_us])
	print("  one burn tick on an orbit today (state_at + from_state): %.1f us" % apply_us)
	print("  one Cartesian step (LowFlight.advance, position, velocity, gravity): %.1f us" % advance_us)
	# A 50 km trip along the cluster's orbit in 30 minutes: Lambert from the craft to a point 50 km
	# ahead on the same circle.
	var ahead := cluster.duplicate(true)
	ahead["parent"] = frost
	ahead["m0_angle"] = (int(cluster["m0_angle"]) + IntMath.mul_div(OrbitMath.TURN, 50_000_000,
		int(cluster["a_mm"]) * 6283 / 1000)) & OrbitMath.ANGLE_MASK
	var normal := Relative.normal_of(cluster)
	for tries: int in [3_000, 6_000, 12_000, 18_000, 36_000, 60_000]:
		var tried := Lambert.solve(gm, now["r"], now["v"], ahead, 0, tries, normal)
		print("    Lambert over %d ticks: %s" % [tries, str(tried.get("miss_mm", "no hit"))])
		var flipped := Lambert.solve(gm, now["r"], now["v"], ahead, 0, tries, [-normal[0], -normal[1], -normal[2]])
		print("    ... with the normal flipped: %s" % str(flipped.get("miss_mm", "no hit")))
	var trip_ticks := 18_000
	var found := {}
	var lambert_us := _per_call(func() -> void:
		found = Lambert.solve(gm, now["r"], now["v"], ahead, 0, trip_ticks, normal), 20)
	var dv1 := 0
	var dv2 := 0
	if not found.is_empty():
		var v: Array = found["v"]
		dv1 = IntMath.dist([v[0] - now["v"][0], v[1] - now["v"][1], v[2] - now["v"][2]], [0, 0, 0])
		var arrive := OrbitMath.state_at(found["orbit"], gm, trip_ticks)
		var there := OrbitMath.state_at(ahead, gm, trip_ticks)
		dv2 = IntMath.dist([arrive["v"][0] - there["v"][0], arrive["v"][1] - there["v"][1],
			arrive["v"][2] - there["v"][2]], [0, 0, 0])
	print("  Lambert, 50 km ahead on the cluster's circle in 30 min: %.0f us, miss %s mm, dv %d + %d um/s"
		% [lambert_us, str(found.get("miss_mm", "none")), dv1, dv2])
	# Burn ticks for that trip at the probe's and a drone's thrust and mass.
	var probe: int = keys["Probe"]
	var drone := _drone("Measure drone", 0)
	for id: int in [probe, drone]:
		var mass := Units.unit_mass(sim._state, sim._ctx.defs, id)
		var thrust: int = BurnSystem.thruster(ctx, id)["thrust_n"]
		var burn_ticks := IntMath.mul_div_ceil(dv1 + dv2, mass * Sim.TICKS_PER_SECOND, thrust * 1_000_000_000)
		# Approach and small corrections: allow a tenth of the trip's burn again, at least 100 ticks.
		var stepped := burn_ticks + maxi(100, burn_ticks / 10)
		var flown_us := 2.0 * lambert_us + stepped * apply_us + 8.0 * state_us
		var flown_cartesian_us := 2.0 * lambert_us + stepped * advance_us + 8.0 * state_us
		var all_stepped_us := trip_ticks * advance_us
		print("  %s, %d kg, %d N: %d burn ticks. Flown quote %.1f ms with today's orbit burns, %.1f ms with Cartesian burns; the whole trip stepped %.1f ms"
			% [sim._state["units"][id]["name"], mass / 1000, thrust, burn_ticks, flown_us / 1000.0,
				flown_cartesian_us / 1000.0, all_stepped_us / 1000.0])
	sim._state["units"].erase(drone)
	sim._ctx.index.clear()


func _per_call(work: Callable, runs: int = RUNS) -> float:
	var best := -1
	for round in 5:
		var started := Time.get_ticks_usec()
		for i in runs:
			work.call()
		var took := Time.get_ticks_usec() - started
		best = took if best < 0 else mini(best, took)
	return float(best) / runs


# ------------------------------------------------------------------------------ fleet

## A mining drone on its own circle round Frost, k km above 400 km, with a full tank.
func _drone(name: String, k: int) -> int:
	var id := Units.create(sim._ctx, "mining_drone", name, [0, 0, 0])
	# On their own 400 km circle, well clear of the cluster's frame, so no frame join caps a coast.
	# In the cluster's plane and at its phase, where the sun is, so the solar panels run the engines.
	var orbit := OrbitMath.make_orbit(gm, 400_000_000 + 1_000_000 * k, 0, cluster["p_q30"], cluster["q_q30"],
		int(cluster["m0_angle"]) + OrbitMath.TURN / 36_000 * k, int(cluster["epoch_tick"]))
	orbit["parent"] = frost
	var unit: Dictionary = sim._state["units"][id]
	unit["orbit"] = orbit
	unit["pos_mm"] = OrbitMath.position_at(orbit, sim.current_tick())
	Units.add_stock(unit["inventory"], Travel.PROPELLANT, 200_000)
	sim._ctx.index.clear()
	return id


func _fleet() -> void:
	print("\n== Six drones round Frost")
	var drones: Array[int] = []
	for k in DRONES:
		drones.append(_drone("Fleet drone %d" % k, k))
	var base_game := sim
	sim = Sim.new_game("new_start", 1)
	var bare := _step_samples(400)
	var bare_started := Time.get_ticks_usec()
	var bare_skip := sim.coast(1_000_000)
	var bare_us := Time.get_ticks_usec() - bare_started
	print("  coast on the new start alone: skipped %d ticks (capped by %s) in %d us" % [bare_skip["ticks"],
		bare_skip["capped_by"], bare_us])
	sim = base_game
	var fleet_started := Time.get_ticks_usec()
	var fleet_skip := sim.coast(1_000_000)
	print("  coast with six idle drones: skipped %d ticks (capped by %s) in %d us" % [fleet_skip["ticks"],
		fleet_skip["capped_by"], Time.get_ticks_usec() - fleet_started])
	sim.step(10)
	_profile(200, "coasting")
	var coasting := _step_samples(400)
	print("  Sim.step on the new start alone, no drones: %d us per tick (median)" % bare)
	for id in drones:
		sim.submit({ "type": "plan_burn", "unit": id, "args": { "tick": sim.current_tick() + 2,
			"prograde_um_s": 20_000_000, "normal_um_s": 0, "radial_um_s": 0 } })
	sim.step(3)
	for event in sim.take_events():
		if str(event["type"]).begins_with("burn"):
			print("    event %s" % str(event))
	for id in drones:
		var unit: Dictionary = sim._state["units"][id]
		var part: int = BurnSystem.thruster(sim._ctx, id)["part"]
		print("    drone %d: burn %s, thruster can run %s, in shadow %s" % [id, str(not unit["burn"].is_empty()),
			str(Units.can_run(sim._state["parts"][part])), str(RailSystem.in_shadow(sim._state, id))])
		break
	_profile(200, "burning")
	var burning := _step_samples(1000)
	var running := 0
	for id in drones:
		if not sim._state["units"][id]["burn"].is_empty() and int(sim._state["units"][id]["burn"]["done_um_s"]) > 0:
			running += 1
	var burn_extra := float(burning - coasting) / DRONES
	print("  Sim.step with all six coasting: %d us per tick (median)" % coasting)
	print("  with all six burning (%d of 6 thrusting): %d us per tick, so %.1f us per burning drone" % [running,
		burning, burn_extra])
	for speed: int in [10, 100, 1000]:
		var need := speed * Sim.TICKS_PER_SECOND
		print("  warp %dx needs %d ticks a second: coasting fleet %.0f ms per real second, burning fleet %.0f ms"
			% [speed, need, need * coasting / 1000.0, need * burning / 1000.0])
	# Coast: once the burns are done, how far one coast call skips and what it costs.
	for id in drones:
		sim._state["units"][id]["burn"] = {}
		sim._state["units"][id]["op"] = { "type": Units.IDLE_OP, "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 }
	sim.step()
	var started := Time.get_ticks_usec()
	var skipped := sim.coast(1_000_000)
	print("  coast after the burns: skipped %d ticks (capped by %s) in %d us" % [skipped["ticks"],
		skipped["capped_by"], Time.get_ticks_usec() - started])


func _step_samples(count: int) -> int:
	var samples: Array[int] = []
	for i in count:
		var started := Time.get_ticks_usec()
		sim.step()
		samples.append(Time.get_ticks_usec() - started)
		sim.take_events()
	samples.sort()
	return samples[samples.size() / 2]


## The tick's time by system and phase, over `ticks` ticks run as Sim._run_tick runs them.
func _profile(ticks: int, label: String) -> void:
	var spent := {}
	var add := func(key: String, started: int) -> void:
		spent[key] = int(spent.get(key, 0)) + Time.get_ticks_usec() - started
	for n in ticks:
		var tick := sim.current_tick() + 1
		var ctx := sim._ctx
		ctx.begin_tick(tick)
		ctx.phase = 1
		var t0 := Time.get_ticks_usec()
		sim._apply_commands(tick)
		add.call("commands", t0)
		var phases := ["update_tasks", "calculate_power", "allocate", "run"]
		for i in phases.size():
			ctx.phase = i + 2
			for system in sim._systems:
				t0 = Time.get_ticks_usec()
				system.call(phases[i], ctx)
				add.call("%s.%s" % [system.get_script().get_global_name(), phases[i]], t0)
		ctx.phase = 6
		t0 = Time.get_ticks_usec()
		for delta in ctx.take_deltas():
			delta["system"].apply_delta(ctx, delta["payload"])
		add.call("deltas", t0)
		for system in sim._systems:
			t0 = Time.get_ticks_usec()
			system.update_stores(ctx)
			add.call("%s.update_stores" % system.get_script().get_global_name(), t0)
		ctx.phase = 7
		for system in sim._systems:
			t0 = Time.get_ticks_usec()
			system.detect(ctx)
			add.call("%s.detect" % system.get_script().get_global_name(), t0)
		ctx.phase = 8
		t0 = Time.get_ticks_usec()
		sim._commit(tick)
		add.call("commit", t0)
		sim.take_events()
	var keys_sorted := spent.keys()
	keys_sorted.sort_custom(func(a: String, b: String) -> bool: return spent[a] > spent[b])
	print("  profile, %s, us per tick:" % label)
	for key: String in keys_sorted.slice(0, 8):
		print("    %-36s %8.1f" % [key, float(spent[key]) / ticks])
