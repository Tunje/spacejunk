extends SceneTree
## New-start figures (task A26), flown and quoted on the real sim with new_start.json: the probe in
## the cluster 300 km from Frost's centre.
## - Leaving the cluster: a burn in the frame, the drift out, and how far the orbit it leaves on is
##   from the one gravity would have given.
## - Landing at 10 kN, flown by burns a second apart, as a player would, with the delta-v measured,
##   against the land command's quote and its 3% gravity allowance.
## - Taking off again to the cluster's height, flown the same way, against take_off's quote, and
##   rejoining the cluster through the planner.
## - The belt: the planner's trip from the cluster to a belt field 2.7 AU from the star, and back.
## Measures only: nothing is saved, and no sim code is changed by it.
##
## Run: godot --headless --path . -s tools/frost_run.gd

const BELT_A_MM := 403_914_250_890_000  # 2.7 AU (docs/design/belt.md)
## The deorbit burn aims the periapsis this far above Frost's datum, over its highest ground.
const PERIAPSIS_ALT_M := 5000.0
const TOUCHDOWN_M_S := 1.5
const GUIDE_TICKS := 10

var sim: Sim
var keys := {}
var gm_frost := 0.0  # m^3/s^2


func _init() -> void:
	if "--sweep" in OS.get_cmdline_user_args():
		_sweep()
		quit()
		return
	_new()
	var probe := _probe()
	var wet_g := Units.unit_mass(sim._state, sim._ctx.defs, keys["Probe"])
	var fuel_g: int = probe["inventory"].get("propellant", 0)
	var stats := BurnSystem.thruster(sim._ctx, keys["Probe"])
	print("Probe: %.0f kg dry, %.0f kg propellant, so %.0f m/s on a full tank at 3000 m/s; %s" % [
		(wet_g - fuel_g) / 1000.0, fuel_g / 1000.0, 3000.0 * log(float(wet_g) / (wet_g - fuel_g)), str(stats)])
	print("Frost: GM %.0f m^3/s^2, sphere %d km; cluster %d km from its centre, %d km across" % [
		gm_frost, sim._state["bodies"][keys["Frost"]]["soi_mm"] / 1_000_000,
		_frame()["orbit"]["a_mm"] / 1_000_000, 2 * _frame()["radius_mm"] / 1_000_000])
	_leaving_the_cluster()
	_new()
	_onto_cluster_orbit()
	_flown_landing()
	_flown_take_off()
	for bolder: Array in [[0.4, 200.0], [0.6, 100.0]]:
		_profile = bolder
		_new()
		_onto_cluster_orbit()
		_flown_landing()
	_new()
	_belt()
	quit()


func _new() -> void:
	sim = Sim.new_game("new_start", 1)
	keys = {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	gm_frost = sim._state["bodies"][keys["Frost"]]["gm"] * 1000.0


func _probe() -> Dictionary:
	return sim._state["units"][keys["Probe"]]


func _frame() -> Dictionary:
	return sim._state["frames"][keys["Cluster"]]


func _steps(count: int) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	for i in count:
		sim.step()
		seen.append_array(sim.take_events())
	return seen


func _burn_args(prograde: int, radial: int) -> Dictionary:
	return { "type": "plan_burn", "unit": keys["Probe"], "args": { "tick": sim.current_tick() + 1,
		"prograde_um_s": prograde, "normal_um_s": 0, "radial_um_s": radial } }


## Plans a burn for the next tick and flies until it ends. Returns the delta-v it delivered.
func _burn(prograde: int, radial: int, limit: int = 20_000) -> int:
	sim.submit(_burn_args(prograde, radial))
	for i in limit:
		for event in _steps(1):
			if event["type"] == "burn_done" or event["type"] == "burn_short":
				return event["data"]["dv_um_s"]
	return 0


# ------------------------------------------------------------------------------ leaving the cluster

## A retrograde burn in the frame, as for a landing, then the drift until the probe leaves.
func _leaving_the_cluster() -> void:
	var frame := _frame()
	var r_c: float = frame["orbit"]["a_mm"] / 1000.0
	var v_c := sqrt(gm_frost / r_c)
	var a_t := (r_c + 60_000.0 + PERIAPSIS_ALT_M) / 2.0
	var deorbit := v_c - sqrt(gm_frost * (2.0 / r_c - 1.0 / a_t))
	var start := sim.current_tick()
	var frame_state := OrbitMath.state_at(frame["orbit"], int(gm_frost / 1000.0), start + 1)
	var done := _burn(-roundi(deorbit * 1e6), 0)
	# Had the probe been on an orbit, this is the orbit the same burn would have given.
	var honest_v: Array[int] = []
	var dir := OrbitMath.unit(frame_state["v"])
	for axis in 3:
		honest_v.append(int(frame_state["v"][axis]) - OrbitMath.smul_div(dir[axis], done, OrbitMath.ONE))
	var honest := OrbitMath.from_state(frame_state["r"], honest_v, int(gm_frost / 1000.0), start + 1)
	var left := sim.current_tick() if _probe()["frame"] == 0 else 0  # over 2 m/s, it leaves mid-burn
	for i in 200_000:
		if left != 0:
			break
		if _steps(1).any(func(e: Dictionary) -> bool: return e["type"] == "frame_left"):
			left = sim.current_tick()
	if left == 0:
		print("\nLeaving the cluster: the probe never left the frame")
		return
	var orbit: Dictionary = _probe()["orbit"]
	print("\nLeaving the cluster with a %.1f m/s retrograde burn in the frame:" % (done / 1e6))
	print("  it drifts %.1f min (%.0f%% of a cluster orbit) before it leaves, %d km from the cluster's centre" % [
		(left - start) / 600.0, 100.0 * (left - start) * OrbitMath.SUB_TICKS / frame["orbit"]["period_subticks"],
		IntMath.dist(_probe()["pos_mm"], frame["pos_mm"]) / 1_000_000])
	print("  periapsis %.1f km from Frost's centre, against %.1f km had it burnt on an orbit" % [
		orbit["a_mm"] * (1.0 - float(orbit["e_q30"]) / OrbitMath.ONE) / 1e6,
		honest["a_mm"] * (1.0 - float(honest["e_q30"]) / OrbitMath.ONE) / 1e6])


# ------------------------------------------------------------------------------ landing

## Puts the probe on the cluster's own orbit, half a turn from it so it doesn't join the frame:
## an orbit, as if it had left the cluster without the drift error measured above.
func _onto_cluster_orbit() -> void:
	var probe := _probe()
	probe["frame"] = 0
	probe["orbit"] = _frame()["orbit"].duplicate(true)
	probe["orbit"]["m0_angle"] = (int(probe["orbit"]["m0_angle"]) + OrbitMath.TURN / 2) & OrbitMath.ANGLE_MASK
	probe["pos_mm"] = OrbitMath.position_at(probe["orbit"], sim.current_tick())
	probe["vel_um_s"] = [0, 0, 0]
	sim._ctx.index.clear()


## The land command's quote from here, and the take_off quote back up, for comparison.
func _quotes() -> Array[int]:
	var cell := LandingSystem.cell_below(sim._ctx, keys["Frost"], _probe()["pos_mm"])
	var land := sim.check({ "type": "land", "unit": keys["Probe"], "args": { "body": keys["Frost"], "cell": cell } })
	return [land.get("detail", {}).get("dv_um_s", 0), cell]


## Position and velocity relative to Frost, in metres and m/s, on an orbit or in low flight.
func _now() -> Array:
	var probe := _probe()
	if probe["low_flight"] != 0:
		return [_vec(probe["pos_mm"], 1e-3), _vec(probe["vel_um_s"], 1e-6)]
	if not probe["landed"].is_empty():
		var ground := LandingSystem.cell_mm(sim._ctx, keys["Frost"], probe["landed"]["cell"])
		return [_vec(ground, 1e-3), Vector3.ZERO]
	var now := OrbitMath.state_at(probe["orbit"], int(gm_frost / 1000.0), sim.current_tick())
	return [_vec(now["r"], 1e-3), _vec(now["v"], 1e-6)]


func _vec(v: Array, scale: float) -> Vector3:
	return Vector3(v[0] * scale, v[1] * scale, v[2] * scale)  # for guidance only, never sim state


func _ground_m(pos_m: Vector3) -> float:
	var mm := [roundi(pos_m.x * 1000.0), roundi(pos_m.y * 1000.0), roundi(pos_m.z * 1000.0)]
	var cell := LandingSystem.cell_below(sim._ctx, keys["Frost"], mm)
	return IntMath.dist(LandingSystem.cell_mm(sim._ctx, keys["Frost"], cell), [0, 0, 0]) / 1000.0


func _accel() -> float:
	var stats: Dictionary = Units.module_of(sim._state, sim._ctx.defs, BurnSystem.thruster(sim._ctx, keys["Probe"])["part"])["capabilities"]["thruster"]
	return stats["thrust_n"] * 1000.0 / Units.unit_mass(sim._state, sim._ctx.defs, keys["Probe"])


## One second of guided thrust: a vertical and a level part of the acceleration wanted, capped at
## the thruster's. A burn of a second's worth starts on the next tick; a part under full thrust
## ends early, as a player's short burn would. Returns the delta-v delivered.
func _guided(a_up: float, a_level: float, sign: float) -> int:
	var cap := _accel()
	a_up = clampf(a_up, -cap, cap)
	a_level = minf(a_level, sqrt(maxf(cap * cap - a_up * a_up, 0.0)))
	var prograde := roundi(sign * a_level * 1e6)
	var radial := roundi(a_up * 1e6)
	if absi(prograde) < 1000 and absi(radial) < 1000:
		_steps(GUIDE_TICKS)
		return 0
	sim.submit(_burn_args(prograde, radial))
	var delivered := 0
	for i in GUIDE_TICKS:
		for event in _steps(1):
			if event["type"] in ["burn_done", "burn_short"]:
				delivered += event["data"]["dv_um_s"]
			if event["type"] in ["landed", "crashed"]:
				_outcome = event
	if not _probe()["burn"].is_empty():
		sim.submit({ "type": "cancel_burn", "unit": keys["Probe"], "args": { "burn": _probe()["burn"]["id"] } })
		for event in _steps(1):
			if event["type"] == "burn_short":
				delivered += event["data"]["dv_um_s"]
	return delivered


var _outcome := {}
## The descent's share of thrust held back for stopping vertically, and the height to reach as the
## level speed runs out: a careful pilot, then a bolder one.
var _profile := [0.2, 300.0]


func _flown_landing() -> void:
	var quote := _quotes()
	var r_c: float = _frame()["orbit"]["a_mm"] / 1000.0
	var radius := 60_000.0
	var a_t := (r_c + radius + PERIAPSIS_ALT_M) / 2.0
	var deorbit := sqrt(gm_frost / r_c) - sqrt(gm_frost * (2.0 / r_c - 1.0 / a_t))
	var at_ground := sqrt(gm_frost * (2.0 / (radius + PERIAPSIS_ALT_M) - 1.0 / a_t))
	var start := sim.current_tick()
	var total := _burn(-roundi(deorbit * 1e6), 0)
	# Coast down to the braking height.
	while true:
		var s: Array = _now()
		var r: float = s[0].length()
		if r - _ground_m(s[0]) < PERIAPSIS_ALT_M + 1500.0 or s[0].dot(s[1]) > 0.0:
			break
		_steps(GUIDE_TICKS)
	var braking := sim.current_tick()
	_outcome = {}
	for i in 20_000:
		if not _outcome.is_empty() or not _probe()["landed"].is_empty():
			break
		var s: Array = _now()
		var pos: Vector3 = s[0]
		var vel: Vector3 = s[1]
		var r := pos.length()
		var up := pos / r
		var vz := vel.dot(up)
		var level := vel - up * vz
		var h := level.length()
		var alt := r - _ground_m(pos)
		var cap := _accel()
		# Come down no faster than a fifth of the thrust could stop, and while braking, no sooner
		# than the level speed is gone: reach 300 m as it is.
		var stoppable := -sqrt(2.0 * _profile[0] * cap * maxf(alt - 20.0, 0.0)) - TOUCHDOWN_M_S
		var want_vz := maxf(stoppable, -40.0)
		if h > 1.0:
			want_vz = maxf(want_vz, -maxf(alt - _profile[1], 0.0) / maxf(h / (0.9 * cap), 1.0))
		var a_up := gm_frost / (r * r) - h * h / r + (want_vz - vz) / 2.0
		total += _guided(a_up, minf(h, cap), -1.0)
	var ideal := deorbit + at_ground
	_result = { "outcome": _outcome.get("type", ""), "speed": _outcome.get("data", {}).get("speed_um_s", 0) / 1e6,
		"flown": total / 1e6 }
	if _quiet:
		return
	print("
Landing on Frost from the cluster's orbit, holding %.0f%% of thrust for stopping vertically:" % (100.0 * _profile[0]))
	print("  %s at %.1f m/s after %.1f min, %.1f min of it braking" % [
		_outcome.get("type", "no touchdown"), _outcome.get("data", {}).get("speed_um_s", 0) / 1e6,
		(sim.current_tick() - start) / 600.0, (sim.current_tick() - braking) / 600.0])
	print("  delta-v flown %.0f m/s; impulsive %.0f m/s (deorbit %.0f, then %.0f at the ground), so %.1f%% lost" % [
		total / 1e6, ideal, deorbit, at_ground, 100.0 * (total / 1e6 - ideal) / ideal])
	print("  the land command quotes %.0f m/s from the same orbit (3%% allowance)" % (quote[0] / 1e6))
	_landed_dv = total


var _landed_dv := 0
## The take-off's climb: vertical speed wanted below a height, and above it.
var _climb := [20.0, 2000.0, 5.0]
var _quiet := false
var _result := {}


# ------------------------------------------------------------------------------ the A27 sweep

## Lands and takes off at several thrusts, keeping the cheapest descent that touches down at no
## more than half the legs' limit and the cheapest climb that reaches the cluster's height. Prints
## each as a factor on the land and take_off commands' surface speed, against thrust-to-weight at
## Frost's surface. Run: godot --headless --path . -s tools/frost_run.gd -- --sweep
func _sweep() -> void:
	_quiet = true
	var landing_profiles := [[0.1, 400.0], [0.2, 300.0], [0.3, 250.0], [0.4, 200.0], [0.5, 150.0], [0.6, 100.0]]
	var climbs := [[10.0, 1000.0, 3.0], [20.0, 2000.0, 5.0], [40.0, 3000.0, 10.0], [60.0, 5000.0, 15.0]]
	print("thrust kN, n landing, best landing factor (profile, flown m/s, touchdown m/s), n take-off, best take-off factor (climb, flown m/s)")
	for thrust_n: int in [5_000, 6_500, 8_000, 10_000, 13_000, 16_000, 20_000, 30_000]:
		var best_land := {}
		var n_land := 0.0
		for profile: Array in landing_profiles:
			_profile = profile
			_new()
			_set_thrust(thrust_n)
			_onto_cluster_orbit()
			n_land = _twr()
			var parts := _command_parts()
			_flown_landing()
			if _result["outcome"] == "landed" and _result["speed"] <= 3.0:
				var factor: float = (_result["flown"] - parts[0]) / parts[1]
				if best_land.is_empty() or factor < best_land["factor"]:
					best_land = { "factor": factor, "profile": profile, "flown": _result["flown"], "speed": _result["speed"] }
		var best_up := {}
		var n_up := 0.0
		for climb: Array in climbs:
			_climb = climb
			_new()
			_set_thrust(thrust_n)
			LandingSystem._set_down(sim._ctx, keys["Probe"], keys["Frost"], 777)
			sim._ctx.index.clear()
			n_up = _twr()
			var parts := _command_parts()
			_flown_take_off()
			if _result.get("low_km", 0.0) > 250.0:
				var factor: float = (_result["flown"] - parts[0]) / parts[1]
				if best_up.is_empty() or factor < best_up["factor"]:
					best_up = { "factor": factor, "climb": climb, "flown": _result["flown"] }
		print("%5.1f  %.2f  %s  %.2f  %s" % [thrust_n / 1000.0, n_land,
			"none safe" if best_land.is_empty() else "%.3f (%s, %.0f, %.1f)" % [best_land["factor"], str(best_land["profile"]), best_land["flown"], best_land["speed"]],
			n_up, "none" if best_up.is_empty() else "%.3f (%s, %.0f)" % [best_up["factor"], str(best_up["climb"]), best_up["flown"]]])


func _set_thrust(thrust_n: int) -> void:
	var part: int = BurnSystem.thruster(sim._ctx, keys["Probe"])["part"]
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	Units.module_of(sim._state, sim._ctx.defs, part)["capabilities"]["thruster"]["thrust_n"] = thrust_n


## Thrust over weight at Frost's datum, at the probe's mass now.
func _twr() -> float:
	return _accel() / (gm_frost / (60_000.0 * 60_000.0))


## The command's sums from the cluster's height: [the burn at the top, the surface speed], m/s.
func _command_parts() -> Array:
	var gm: int = sim._state["bodies"][keys["Frost"]]["gm"]
	var high: int = _frame()["orbit"]["a_mm"]
	var a_t := (60_000_000 + high) / 2
	var top := absi(OrbitMath.speed_um_s(gm, high, high) - OrbitMath.speed_um_s(gm, high, a_t))
	return [top / 1e6, OrbitMath.speed_um_s(gm, 60_000_000, a_t) / 1e6]


func _flown_take_off() -> void:
	if _probe()["landed"].is_empty():
		return
	var r_c: float = _frame()["orbit"]["a_mm"] / 1000.0
	var radius := 60_000.0
	var rail := sim.check({ "type": "take_off", "unit": keys["Probe"], "args": { "altitude_mm": roundi((r_c - radius) * 1000.0) } })
	var start := sim.current_tick()
	var total := 0
	# Climb and pitch over until the path's highest point reaches the cluster's height.
	for i in 20_000:
		var s: Array = _now()
		var pos: Vector3 = s[0]
		var vel: Vector3 = s[1]
		var r := pos.length()
		var energy := vel.length_squared() / 2.0 - gm_frost / r
		var a := -gm_frost / (2.0 * energy) if energy < 0.0 else INF
		var hvec := pos.cross(vel)
		var e := sqrt(maxf(0.0, 1.0 - hvec.length_squared() / (gm_frost * a))) if a < INF else 1.0
		if a * (1.0 + e) >= r_c:
			break
		var up := pos / r
		var vz := vel.dot(up)
		var h := (vel - up * vz).length()
		var alt := r - _ground_m(pos)
		var want_vz: float = _climb[0] if alt < _climb[1] else _climb[2]
		var a_up := gm_frost / (r * r) - h * h / r + (want_vz - vz) / 2.0
		total += _guided(a_up, _accel(), 1.0)
	# Coast to the top, then circle there.
	while true:
		var s: Array = _now()
		if s[0].dot(s[1]) <= 0.0:
			break
		_steps(GUIDE_TICKS)
	var s: Array = _now()
	var circle: float = sqrt(gm_frost / s[0].length()) - s[1].length()
	total += _burn(roundi(circle * 1e6), 0)
	var orbit: Dictionary = _probe()["orbit"]
	_result = { "flown": total / 1e6, "low_km": orbit.get("a_mm", 0) * (1.0 - float(orbit.get("e_q30", 0)) / OrbitMath.ONE) / 1e6 }
	if _quiet:
		return
	print("\nTaking off from Frost to the cluster's height, flown the same way:")
	print("  delta-v flown %.0f m/s in %.1f min, into an orbit of %.1f by %.1f km from the centre" % [
		total / 1e6, (sim.current_tick() - start) / 600.0,
		orbit.get("a_mm", 0) * (1.0 - float(orbit.get("e_q30", 0)) / OrbitMath.ONE) / 1e6,
		orbit.get("a_mm", 0) * (1.0 + float(orbit.get("e_q30", 0)) / OrbitMath.ONE) / 1e6])
	print("  take_off quotes %.0f m/s" % (rail.get("detail", {}).get("dv_um_s", 0) / 1e6))
	var rejoin := sim.quote(keys["Probe"], keys["Red Rock"], sim.current_tick() + 1)
	print("  rejoining the cluster from there: %.0f m/s, arriving in %.1f h" % [
		rejoin.get("dv_um_s", 0) / 1e6, (rejoin.get("arrive_tick", sim.current_tick()) - sim.current_tick()) / 36_000.0])
	var round_trip: float = (_landed_dv + total + rejoin.get("dv_um_s", 0)) / 1e6
	var wet_g := Units.unit_mass(sim._state, sim._ctx.defs, keys["Probe"])
	var fuel_g: int = _probe()["inventory"].get("propellant", 0)
	print("  round trip flown %.0f m/s; %.0f kg of propellant left after landing and take-off" % [
		round_trip, fuel_g / 1000.0])
	print("  spare on a full tank: %.0f m/s" % (_full_tank_m_s() - round_trip))


func _full_tank_m_s() -> float:
	var fresh := Sim.new_game("new_start", 1)
	var id := 0
	for unit_id: int in fresh._state["units"]:
		if fresh._state["units"][unit_id]["name"] == "Probe":
			id = unit_id
	var wet := float(Units.unit_mass(fresh._state, fresh._ctx.defs, id))
	var fuel := float(fresh._state["units"][id]["inventory"].get("propellant", 0))
	return 3000.0 * log(wet / (wet - fuel))


# ------------------------------------------------------------------------------ the belt

## A belt field round the star at 2.7 AU with one rock, then the planner's trips each way.
func _belt() -> void:
	var ctx := sim._ctx
	var star: int = keys["Star"]
	var field := ctx.new_id()
	var orbit := ScenarioBuilder._orbit(ctx, { "parent": "star", "a_mm": BELT_A_MM, "mean_anomaly_mdeg": 90_000 },
		{ "star": star })
	ctx.state["frames"][field] = { "id": field, "name": "Belt", "radius_mm": 1_000_000, "orbit": orbit,
		"pos_mm": OrbitMath.position_at(orbit, sim.current_tick()) }
	var rock := ctx.new_id()
	ctx.state["bodies"][rock] = { "id": rock, "name": "Belt Rock", "kind": "asteroid", "pos_mm": [20_000_000, 0, 0],
		"radius_mm": 300_000, "visual_seed": 9, "scanned": false, "frame": field, "orbit": {}, "gm": 0,
		"soi_mm": 0, "planet": {}, "deposits": [] }
	ctx.index.clear()
	print("\nThe belt at 2.7 AU, by the planner (A22's two-level trips):")
	var out := sim.quote(keys["Probe"], rock, 1)
	_print_trip("out from the cluster", out)
	var probe := _probe()
	probe["frame"] = field
	probe["pos_mm"] = [150_000, 0, 0]
	ctx.index.clear()
	var back := sim.quote(keys["Probe"], keys["Red Rock"], 1)
	_print_trip("back to the cluster", back)
	if out.has("dv_um_s") and back.has("dv_um_s"):
		var both: float = (out["dv_um_s"] + back["dv_um_s"]) / 1e6
		print("  both ways %.0f m/s, a mass ratio of %.1f at 3000 m/s and %.2f at 30,000 m/s" % [
			both, exp(both / 3000.0), exp(both / 30_000.0)])


func _print_trip(label: String, trip: Dictionary) -> void:
	if not trip.has("dv_um_s"):
		print("  %s: no trip: %s" % [label, str(trip)])
		return
	print("  %s: %.0f m/s, leaving in %.0f days, %.0f days in flight" % [label, trip["dv_um_s"] / 1e6,
		trip.get("depart_tick", 0) / 864_000.0, (trip["arrive_tick"] - trip.get("depart_tick", 0)) / 864_000.0])
	for leg: Dictionary in trip.get("legs", []):
		var orbit: Dictionary = leg["orbit"]
		print("    from day %.1f: round %s, a %.0f km%s" % [leg["from_tick"] / 864_000.0,
			sim._state["bodies"][orbit["parent"]]["name"], orbit["a_mm"] / 1e6,
			", hyperbolic" if orbit.get("hyperbolic", false) else ""])
	if not trip.has("legs"):
		print("    keys: %s" % str(trip.keys()))
