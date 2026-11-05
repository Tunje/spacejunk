extends SceneTree
## Game-scale reach figures (task A23). For each candidate placement of a first planet, asks the
## real planner for a core-flown trip from the cluster at 1 AU to a ring around a 60 km moon of
## that planet, and back. Prints delta-v, trip time, window spacing and the starter probe's
## propellant. Measures only: nothing is flown and no state is saved.
##
## Run: godot --headless --path . -s tools/reach_run.gd

const GM_STAR := 132_712_440_018_000_000   # the Sun, in 1000 m^3/s^2
const GM_PLANET := 3_531_600_000           # a 600 km planet at Kerbin's density
const GM_MOON := 3_531_600                 # a 60 km moon at the same density
const AU_MM := 149_597_870_700_000
const MOON_A_MM := 12_000_000_000          # the moon's orbit around the planet, 12,000 km
const RING_A_MM := 66_000_000              # a ring a tenth of the moon's radius up
const PROBE_DRY_KG := 6780.0
const PROBE_TANK_KG := 2000.0
const EXHAUST_M_S := 3000.0
const DAY_TICKS := 864_000

## Planet distances from the star, in thousandths of an AU.
const PLACEMENTS := [700, 900, 1050, 1200, 1520]


func _init() -> void:
	print("Probe: %.0f kg dry, %.0f kg propellant, %.0f m/s exhaust, so %.0f m/s on a full tank" % [
		PROBE_DRY_KG, PROBE_TANK_KG, EXHAUST_M_S, EXHAUST_M_S * log((PROBE_DRY_KG + PROBE_TANK_KG) / PROBE_DRY_KG)])
	for milli_au: int in PLACEMENTS:
		_measure(milli_au)
	for cluster_km: int in [3_000, 8_000, 20_000, 30_000]:
		_measure_round_planet(cluster_km)
	quit()


func _measure(milli_au: int) -> void:
	var defs := DataLoader.load_defs()
	var sim := Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	var error := ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET,
				"orbit": { "parent": "star", "a_mm": AU_MM / 1000 * milli_au, "mean_anomaly_mdeg": 0 } },
			{ "key": "moon", "name": "Moon", "kind": "planet", "radius_mm": 60_000_000, "visual_seed": 3,
				"deposits": [], "gm": GM_MOON, "orbit": { "parent": "planet", "a_mm": MOON_A_MM } },
			{ "key": "home_rock", "name": "Home Rock", "kind": "asteroid", "frame": "cluster",
				"pos_mm": [20_000_000, 0, 0], "radius_mm": 300_000, "visual_seed": 4, "deposits": [] },
			{ "key": "moon_rock", "name": "Moon Rock", "kind": "asteroid", "frame": "ring",
				"pos_mm": [2_000_000, 0, 0], "radius_mm": 300_000, "visual_seed": 5, "deposits": [] },
		],
		"frames": [
			{ "key": "cluster", "name": "Cluster", "radius_mm": 1_000_000,
				"orbit": { "parent": "star", "a_mm": AU_MM, "mean_anomaly_mdeg": 0 } },
			{ "key": "ring", "name": "Ring", "radius_mm": 1_000_000,
				"orbit": { "parent": "moon", "a_mm": RING_A_MM } },
		],
		"units": [
			{ "key": "out", "template": "starter_ship", "name": "Out", "pos_mm": [150_000, 0, 0],
				"frame": "cluster", "inventory": [], "dock": null },
			{ "key": "back", "template": "starter_ship", "name": "Back", "pos_mm": [150_000, 0, 0],
				"frame": "ring", "inventory": [], "dock": null },
		],
	}, {})
	if error != "":
		print("%.2f AU: scenario refused: %s" % [milli_au / 1000.0, error])
		return
	var keys := {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	var planet: Dictionary = sim._state["bodies"][keys["Planet"]]
	var moon: Dictionary = sim._state["bodies"][keys["Moon"]]
	print("\n%.2f AU: planet sphere %d km, moon sphere %d km" % [milli_au / 1000.0,
		planet.get("soi_mm", 0) / 1_000_000, moon.get("soi_mm", 0) / 1_000_000])
	var out := _two_windows(sim, keys["Out"], keys["Moon Rock"])
	var back := _two_windows(sim, keys["Back"], keys["Home Rock"])
	if out.is_empty() or back.is_empty():
		return
	var dv_out: float = out["dv_um_s"] / 1e6
	var dv_back: float = back["dv_um_s"] / 1e6
	var r1 := 1.0
	var r2 := milli_au / 1000.0
	var v1 := 29784.7
	var floor_m_s := v1 * absf(sqrt(2.0 * r2 / (r1 + r2)) - 1.0) + v1 / sqrt(r2) * absf(1.0 - sqrt(2.0 * r1 / (r1 + r2)))
	print("  matching the planet's orbit round the star, each way, before any capture: %.0f m/s" % floor_m_s)
	print("  out:  %.0f m/s, %.1f days in flight, windows every %.1f days" % [
		dv_out, out["ticks"] / float(DAY_TICKS), out["spacing"] / float(DAY_TICKS)])
	print("  back: %.0f m/s, %.1f days in flight, windows every %.1f days" % [
		dv_back, back["ticks"] / float(DAY_TICKS), back["spacing"] / float(DAY_TICKS)])
	print("  probe propellant: out %.0f kg, round trip %.0f kg (tank %.0f kg)" % [
		_propellant_kg(dv_out), _propellant_kg(dv_out + dv_back), PROBE_TANK_KG])
	print("  round trip with the 370 m/s landing: %.0f m/s, %.0f kg" % [
		dv_out + dv_back + 370.0, _propellant_kg(dv_out + dv_back + 370.0)])


## The fallback: the cluster in orbit round the planet itself, at a radius in km, with the same moon.
## A one-level trip (A18).
func _measure_round_planet(cluster_km: int) -> void:
	var defs := DataLoader.load_defs()
	var sim := Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	var error := ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM } },
			{ "key": "moon", "name": "Moon", "kind": "planet", "radius_mm": 60_000_000, "visual_seed": 3,
				"deposits": [], "gm": GM_MOON, "orbit": { "parent": "planet", "a_mm": MOON_A_MM } },
			{ "key": "home_rock", "name": "Home Rock", "kind": "asteroid", "frame": "cluster",
				"pos_mm": [20_000_000, 0, 0], "radius_mm": 300_000, "visual_seed": 4, "deposits": [] },
			{ "key": "moon_rock", "name": "Moon Rock", "kind": "asteroid", "frame": "ring",
				"pos_mm": [2_000_000, 0, 0], "radius_mm": 300_000, "visual_seed": 5, "deposits": [] },
		],
		"frames": [
			{ "key": "cluster", "name": "Cluster", "radius_mm": 1_000_000,
				"orbit": { "parent": "planet", "a_mm": cluster_km * 1_000_000, "mean_anomaly_mdeg": 0 } },
			{ "key": "ring", "name": "Ring", "radius_mm": 1_000_000,
				"orbit": { "parent": "moon", "a_mm": RING_A_MM } },
		],
		"units": [
			{ "key": "out", "template": "starter_ship", "name": "Out", "pos_mm": [150_000, 0, 0],
				"frame": "cluster", "inventory": [], "dock": null },
			{ "key": "back", "template": "starter_ship", "name": "Back", "pos_mm": [150_000, 0, 0],
				"frame": "ring", "inventory": [], "dock": null },
		],
	}, {})
	if error != "":
		print("cluster at %d km: scenario refused: %s" % [cluster_km, error])
		return
	var keys := {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	var shadow := asin(600.0 / cluster_km) / PI
	var period_h := TAU * sqrt(pow(cluster_km * 1000.0, 3) / (GM_PLANET * 1000.0)) / 3600.0
	print("
Cluster round the planet at %d km: a %.1f h orbit, %.1f%% of it in shadow" % [
		cluster_km, period_h, shadow * 100.0])
	var out := _two_windows(sim, keys["Out"], keys["Moon Rock"])
	var back := _two_windows(sim, keys["Back"], keys["Home Rock"])
	if out.is_empty() or back.is_empty():
		return
	var dv_out: float = out["dv_um_s"] / 1e6
	var dv_back: float = back["dv_um_s"] / 1e6
	print("  out:  %.0f m/s, %.1f h in flight, windows every %.1f h" % [
		dv_out, out["ticks"] / 36000.0, out["spacing"] / 36000.0])
	print("  back: %.0f m/s, %.1f h in flight, windows every %.1f h" % [
		dv_back, back["ticks"] / 36000.0, back["spacing"] / 36000.0])
	print("  round trip with the 370 m/s landing: %.0f m/s, %.0f kg of the %.0f kg tank" % [
		dv_out + dv_back + 370.0, _propellant_kg(dv_out + dv_back + 370.0), PROBE_TANK_KG])


## Quotes the first window and the next, to give the spacing between them.
func _two_windows(sim: Sim, unit: int, target: int) -> Dictionary:
	var first := sim.quote(unit, target, 1)
	if first.get("kind", "") != Transfer.KIND:
		print("  %s: no trip: %s" % [sim._state["units"][unit]["name"], str(first)])
		return {}
	# Quoting again after the first arrival finds the next whole trip. Spacing is taken between
	# arrivals, because a trip home can leave the moon ring often but then waits at the planet for
	# the same window round the star.
	var second := sim.quote(unit, target, first["arrive_tick"] + 1)
	var spacing: int = second.get("arrive_tick", first["arrive_tick"]) - first["arrive_tick"]
	var result := first.duplicate()
	result["spacing"] = spacing
	return result


## Propellant for the dry probe to make dv, by the rocket equation.
func _propellant_kg(dv_m_s: float) -> float:
	return PROBE_DRY_KG * (exp(dv_m_s / EXHAUST_M_S) - 1.0)
