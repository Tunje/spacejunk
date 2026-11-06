extends SceneTree
## Game-scale reach figures (task A23). Asks the real planner for core-flown trips from the cluster
## to a 60 km moon of a first planet, and back, for three ways of placing the cluster:
## - round the star at 1 AU, with the planet at several distances (A22's two-level trips);
## - round the planet itself, at several radii (A18's one-level trips);
## - round the moon itself, landing straight from the cluster's orbit.
## Prints delta-v, times, window spacing, the starter probe's propellant and, round the moon, the
## shadow by A16's own test. Measures only: nothing is flown and no state is saved.
##
## Run: godot --headless --path . -s tools/reach_run.gd

const GM_STAR := 132_712_440_018_000_000   # the Sun, in 1000 m^3/s^2
const GM_PLANET := 3_531_600_000           # a 600 km planet at Kerbin's density
const GM_MOON := 3_531_600                 # a 60 km moon at the same density
const GM_MOON_HALF := 1_765_800            # the same moon at half the density
const AU_MM := 149_597_870_700_000
const PLANET_R_MM := 600_000_000
const MOON_R_MM := 60_000_000
const MOON_A_MM := 12_000_000_000          # the moon's orbit round the planet, 12,000 km
const RING_A_MM := 66_000_000              # a ring a tenth of the moon's radius up
const PROBE_DRY_KG := 6880.0               # B10's probe with B15's 100 kg landing legs
const PROBE_TANK_KG := 2000.0
const EXHAUST_M_S := 3000.0
## A23 priced landings with a flat 3%; since A27 the loss depends on thrust over weight.
const PROBE_THRUST_N := 10_000
const DAY_TICKS := 864_000
const HOUR_TICKS := 36_000

## Planet distances from the star, in thousandths of an AU.
const PLACEMENTS := [700, 900, 1050, 1200, 1520]
## Cluster radii round the planet, and round the moon, in km.
const ROUND_PLANET := [3_000, 8_000, 20_000, 30_000]
const ROUND_MOON := [300, 400, 600]


func _init() -> void:
	print("Probe: %.0f kg dry, %.0f kg propellant, %.0f m/s exhaust, so %.0f m/s on a full tank" % [
		PROBE_DRY_KG, PROBE_TANK_KG, EXHAUST_M_S, _tank_m_s()])
	var ring_landing := _landing(GM_MOON, RING_A_MM)
	print("Landing from the 66 km ring and back up: %.0f m/s (%.0f m/s at half the moon's density)" % [
		2 * ring_landing["dv_um_s"] / 1e6, 2 * _landing(GM_MOON_HALF, RING_A_MM)["dv_um_s"] / 1e6])
	for milli_au: int in PLACEMENTS:
		_round_star(milli_au)
	for km: int in ROUND_PLANET:
		_round_planet(km)
	for km: int in ROUND_MOON:
		_round_moon(km)
	quit()


# ------------------------------------------------------------------------------ the cases

func _round_star(milli_au: int) -> void:
	var built := _build(milli_au, { "parent": "star", "a_mm": AU_MM, "mean_anomaly_mdeg": 0 })
	if built.is_empty():
		return
	var sim: Sim = built["sim"]
	var keys: Dictionary = built["keys"]
	var r2 := milli_au / 1000.0
	var v1 := 29784.7
	var matching := v1 * absf(sqrt(2.0 * r2 / (1.0 + r2)) - 1.0) + v1 / sqrt(r2) * absf(1.0 - sqrt(2.0 / (1.0 + r2)))
	print("\n%.2f AU: planet sphere %d km, moon sphere %d km" % [r2,
		sim._state["bodies"][keys["Planet"]]["soi_mm"] / 1_000_000, sim._state["bodies"][keys["Moon"]]["soi_mm"] / 1_000_000])
	print("  matching the planet's orbit round the star, each way, before any capture: %.0f m/s" % matching)
	_trips(sim, keys, DAY_TICKS, "days")


func _round_planet(km: int) -> void:
	var built := _build(1000, { "parent": "planet", "a_mm": km * 1_000_000, "mean_anomaly_mdeg": 0 })
	if built.is_empty():
		return
	var period_h := TAU * sqrt(pow(km * 1000.0, 3) / (GM_PLANET * 1000.0)) / 3600.0
	print("\nCluster round the planet at %d km: a %.1f h orbit, %.1f%% of it behind the planet" % [
		km, period_h, asin(600.0 / km) / PI * 100.0])
	_trips(built["sim"], built["keys"], HOUR_TICKS, "h")


## Lands straight from the cluster's orbit and comes back up to it. Coming back, the ship is up to
## half a turn from the cluster, so the worst-case rejoin is quoted from a frame half a turn on.
func _round_moon(km: int) -> void:
	var cluster := { "parent": "moon", "a_mm": km * 1_000_000, "mean_anomaly_mdeg": 0 }
	var opposite := { "key": "opposite", "name": "Opposite", "radius_mm": 1_000_000,
		"orbit": { "parent": "moon", "a_mm": km * 1_000_000, "mean_anomaly_mdeg": 180_000 } }
	var built := _build(1000, cluster, [opposite])
	if built.is_empty():
		return
	var sim: Sim = built["sim"]
	var keys: Dictionary = built["keys"]
	var period_h := TAU * sqrt(pow(km * 1000.0, 3) / (GM_MOON * 1000.0)) / 3600.0
	print("\nCluster round the moon at %d km: a %.2f h orbit, moon sphere %d km" % [
		km, period_h, sim._state["bodies"][keys["Moon"]]["soi_mm"] / 1_000_000])
	var landing := _landing(GM_MOON, km * 1_000_000)
	var rejoin := sim.quote(keys["Lifted"], keys["Home Rock"], 1)
	var rejoin_dv: float = rejoin.get("dv_um_s", 0) / 1e6
	var rejoin_ticks: int = rejoin.get("arrive_tick", 1) - 1
	var down: float = landing["dv_um_s"] / 1e6
	var round_trip := 2.0 * down + rejoin_dv
	print("  down %.0f m/s in %.1f min; up the same; rejoining the cluster from half a turn away %.0f m/s in %.1f h" % [
		down, landing["ticks"] / 600.0, rejoin_dv, rejoin_ticks / float(HOUR_TICKS)])
	print("  round trip %.0f m/s, %.0f kg of the %.0f kg tank, so %.0f m/s spare" % [
		round_trip, _propellant_kg(round_trip), PROBE_TANK_KG, _tank_m_s() - round_trip])
	var half: float = 2.0 * _landing(GM_MOON_HALF, km * 1_000_000)["dv_um_s"] / 1e6
	print("  at half the moon's density: down and up %.0f m/s, plus the rejoin" % half)
	_shadow(sim, keys)


# ------------------------------------------------------------------------------ measuring

## The trips out to the ring and back, through the real planner.
func _trips(sim: Sim, keys: Dictionary, unit_ticks: int, unit_name: String) -> void:
	var out := _two_windows(sim, keys["Out"], keys["Moon Rock"])
	var back := _two_windows(sim, keys["Back"], keys["Home Rock"])
	if out.is_empty() or back.is_empty():
		return
	var dv_out: float = out["dv_um_s"] / 1e6
	var dv_back: float = back["dv_um_s"] / 1e6
	var landing: float = 2.0 * _landing(GM_MOON, RING_A_MM)["dv_um_s"] / 1e6
	print("  out:  %.0f m/s, %.1f %s in flight, windows every %.1f %s" % [
		dv_out, out["ticks"] / float(unit_ticks), unit_name, out["spacing"] / float(unit_ticks), unit_name])
	print("  back: %.0f m/s, %.1f %s from leaving the ring to arriving, windows every %.1f %s" % [
		dv_back, back["ticks"] / float(unit_ticks), unit_name, back["spacing"] / float(unit_ticks), unit_name])
	print("  round trip with the landing: %.0f m/s, %.0f kg of propellant (tank %.0f kg)" % [
		dv_out + dv_back + landing, _propellant_kg(dv_out + dv_back + landing), PROBE_TANK_KG])


## Quotes the first trip and the next whole one after it arrives. Spacing is taken between
## arrivals, because a trip home can leave the moon ring often but then waits at the planet for
## the same window round the star.
func _two_windows(sim: Sim, unit: int, target: int) -> Dictionary:
	var first := sim.quote(unit, target, 1)
	if first.get("kind", "") != Transfer.KIND:
		print("  %s: no trip: %s" % [sim._state["units"][unit]["name"], str(first)])
		return {}
	var second := sim.quote(unit, target, first["arrive_tick"] + 1)
	var result := first.duplicate()
	result["spacing"] = second.get("arrive_tick", first["arrive_tick"]) - first["arrive_tick"]
	return result


## LandingSystem's own cost of landing from a circular orbit at high_mm, or of taking off to it:
## the surface speed on the descent ellipse with the gravity loss, plus the burn at the top. The
## same integer sums as LandingSystem._plan, which needs a unit on an orbit to call. A23's figures
## used the flat 3% loss that A27 replaced, so a rerun now gives dearer landings.
func _landing(gm: int, high_mm: int) -> Dictionary:
	var a_t := (MOON_R_MM + high_mm) / 2
	var n := LandingSystem.twr_ppm(gm, MOON_R_MM, PROBE_THRUST_N, roundi((PROBE_DRY_KG + PROBE_TANK_KG) * 1000.0))
	var surface := IntMath.mul_div_ceil(OrbitMath.speed_um_s(gm, MOON_R_MM, a_t),
		LandingSystem.loss_permille(n, LandingSystem.LAND_EXTRA_PERMILLE), 1000)
	var top := absi(OrbitMath.speed_um_s(gm, high_mm, high_mm) - OrbitMath.speed_um_s(gm, high_mm, a_t))
	return { "dv_um_s": surface + top, "ticks": maxi(1, OrbitMath.period_sub(gm, a_t) / (2 * OrbitMath.SUB_TICKS)) }


## Samples the cluster's shadow every 3 s over ten orbits of the moon round the planet, by A16's
## cylinder test, with every orbit in one plane (the worst case). Prints the share of time behind
## the moon, behind the planet and in all, and the longest single eclipse.
func _shadow(sim: Sim, keys: Dictionary) -> void:
	var state := sim._state
	var unit: int = keys["Out"]
	var moon_period: int = state["bodies"][keys["Moon"]]["orbit"]["period_subticks"] / OrbitMath.SUB_TICKS
	var samples := 0
	var counts := { "moon": 0, "planet": 0, "any": 0 }
	var longest := 0
	var run := 0
	for tick in range(0, 10 * moon_period, 30):
		for table: String in ["bodies", "frames"]:
			for id: int in state[table]:
				var entry: Dictionary = state[table][id]
				if not entry["orbit"].is_empty():
					entry["pos_mm"] = OrbitMath.position_at(entry["orbit"], tick)
		var casters := RailSystem.shadow_casters(state)
		var by_moon := RailSystem.in_shadow(state, unit, casters.filter(func(c: Array) -> bool: return c[2] == MOON_R_MM))
		var by_planet := RailSystem.in_shadow(state, unit, casters.filter(func(c: Array) -> bool: return c[2] == PLANET_R_MM))
		samples += 1
		counts["moon"] += int(by_moon)
		counts["planet"] += int(by_planet)
		if by_moon or by_planet:
			counts["any"] += 1
			run += 30
			longest = maxi(longest, run)
		else:
			run = 0
	print("  shadow over %.0f h: %.2f%% behind the moon, %.2f%% behind the planet, %.2f%% in all; longest eclipse %.1f min" % [
		10 * moon_period / float(HOUR_TICKS), 100.0 * counts["moon"] / samples, 100.0 * counts["planet"] / samples,
		100.0 * counts["any"] / samples, longest / 600.0])


# ------------------------------------------------------------------------------ the world

## A star, the planet at milli_au thousandths of an AU, its moon, the cluster frame on the given
## orbit with a rock in it, and a ring round the moon with a rock in it. Unit Out sits in the
## cluster and Back in the ring; with an "opposite" frame, Lifted sits in that.
func _build(milli_au: int, cluster_orbit: Dictionary, extra_frames: Array = []) -> Dictionary:
	var defs := DataLoader.load_defs()
	var sim := Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	var frames := [
		{ "key": "cluster", "name": "Cluster", "radius_mm": 1_000_000, "orbit": cluster_orbit },
		{ "key": "ring", "name": "Ring", "radius_mm": 1_000_000, "orbit": { "parent": "moon", "a_mm": RING_A_MM } },
	]
	frames.append_array(extra_frames)
	var units := [
		{ "key": "out", "template": "starter_ship", "name": "Out", "pos_mm": [150_000, 0, 0],
			"frame": "cluster", "inventory": [], "dock": null },
		{ "key": "back", "template": "starter_ship", "name": "Back", "pos_mm": [150_000, 0, 0],
			"frame": "ring", "inventory": [], "dock": null },
	]
	if not extra_frames.is_empty():
		units.append({ "key": "lifted", "template": "starter_ship", "name": "Lifted", "pos_mm": [150_000, 0, 0],
			"frame": "opposite", "inventory": [], "dock": null })
	var error := ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": PLANET_R_MM, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET,
				"orbit": { "parent": "star", "a_mm": AU_MM / 1000 * milli_au, "mean_anomaly_mdeg": 0 } },
			{ "key": "moon", "name": "Moon", "kind": "planet", "radius_mm": MOON_R_MM, "visual_seed": 3,
				"deposits": [], "gm": GM_MOON, "orbit": { "parent": "planet", "a_mm": MOON_A_MM } },
			{ "key": "home_rock", "name": "Home Rock", "kind": "asteroid", "frame": "cluster",
				"pos_mm": [20_000_000, 0, 0], "radius_mm": 300_000, "visual_seed": 4, "deposits": [] },
			{ "key": "moon_rock", "name": "Moon Rock", "kind": "asteroid", "frame": "ring",
				"pos_mm": [2_000_000, 0, 0], "radius_mm": 300_000, "visual_seed": 5, "deposits": [] },
		],
		"frames": frames,
		"units": units,
	}, {})
	if error != "":
		print("scenario refused: %s" % error)
		return {}
	var keys := {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	return { "sim": sim, "keys": keys }


func _tank_m_s() -> float:
	return EXHAUST_M_S * log((PROBE_DRY_KG + PROBE_TANK_KG) / PROBE_DRY_KG)


## Propellant for the dry probe to make dv, by the rocket equation.
func _propellant_kg(dv_m_s: float) -> float:
	return PROBE_DRY_KG * (exp(dv_m_s / EXHAUST_M_S) - 1.0)
