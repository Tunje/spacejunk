extends GutTest
## Burns for the player's ship (task A11, orbital_flight.md section 11): plan_burn and cancel_burn,
## finite burns on an orbit and in a frame, drift, leaving and joining a frame, and predict.

const AU_MM := 149_597_870_700_000
const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const ONE := OrbitMath.ONE
## B13's figures for the medium thruster, patched in until that data is on main.
const THRUST_N := 3000
const EXHAUST_MM_S := 3_000_000
const FULL_TANK_G := 1_000_000

var sim: Sim
var keys := {}
## Thruster fields this file added to the loader's cached data, to take out again afterwards.
var _patched: Array[Dictionary] = []


## Patches the cached definitions themselves, so a loaded save sees the same data hash.
func before_all() -> void:
	var defs := DataLoader.load_defs()
	for id: String in defs["modules"]:
		var thruster: Dictionary = defs["modules"][id]["capabilities"].get("thruster", {})
		if not thruster.is_empty() and not thruster.has("thrust_n"):
			thruster["thrust_n"] = THRUST_N
			thruster["exhaust_mm_s"] = EXHAUST_MM_S
			_patched.append(thruster)


func after_all() -> void:
	for thruster in _patched:
		thruster.erase("thrust_n")
		thruster.erase("exhaust_mm_s")


func before_each() -> void:
	sim = _build()


## The first of a two-burn transfer from a circular orbit at r1 to r2, in um/s.
static func _hohmann_um_s(r1_m: float, r2_m: float) -> int:
	var mu := 3.5316e12
	return roundi((sqrt(mu * (2.0 / r1_m - 2.0 / (r1_m + r2_m))) - sqrt(mu / r1_m)) * 1e6)


func _build() -> Sim:
	var defs: Dictionary = DataLoader.load_defs().duplicate(true)
	var built := Sim.new()
	built._setup(Sim._new_state("reference", 7, defs), defs)
	var problem := ScenarioBuilder.populate(built._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM * 2 } },
			{ "key": "rock", "name": "Red Rock", "kind": "asteroid", "frame": "cluster",
				"pos_mm": [50_000_000, 0, 0], "radius_mm": 500_000, "visual_seed": 4, "deposits": [] },
		],
		"frames": [
			{ "key": "cluster", "name": "Cluster", "radius_mm": 1_000_000,
				"orbit": { "parent": "star", "a_mm": AU_MM } },
		],
		"units": [
			{ "key": "scout", "template": "starter_ship", "name": "Scout", "pos_mm": [150_000, 0, 0],
				"frame": "cluster", "inventory": [{ "item": "propellant", "grams": FULL_TANK_G }], "dock": null },
			{ "key": "orbiter", "template": "starter_ship", "name": "Orbiter", "pos_mm": [0, 0, 0],
				"inventory": [{ "item": "propellant", "grams": FULL_TANK_G }], "dock": null },
		],
	}, {})
	assert_eq(problem, "")
	built._strict = true
	keys = {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in built._state[table]:
			keys[built._state[table][id]["name"]] = id
	# The orbiter starts on a circular 700 km orbit around the planet.
	var orbiter: Dictionary = built._state["units"][keys["Orbiter"]]
	orbiter["orbit"] = OrbitMath.make_orbit(GM_PLANET, 700_000_000, 0, [ONE, 0, 0], [0, 0, -ONE], 0, 0)
	orbiter["orbit"]["parent"] = keys["Planet"]
	orbiter["pos_mm"] = OrbitMath.position_at(orbiter["orbit"], 0)
	built._ctx.index.clear()
	return built


func _burn(unit: String, tick: int, prograde: int, normal: int = 0, radial: int = 0) -> Dictionary:
	return { "type": "plan_burn", "unit": keys[unit], "args": {
		"tick": tick, "prograde_um_s": prograde, "normal_um_s": normal, "radial_um_s": radial } }


func _unit(name: String) -> Dictionary:
	return sim._state["units"][keys[name]]


## Steps until an event of this type, or a tick limit, returning every event seen.
func _until(event_type: String, limit: int) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	for i in limit:
		sim.step()
		var events := sim.take_events()
		seen.append_array(events)
		if events.any(func(e: Dictionary) -> bool: return e["type"] == event_type):
			return seen
	return seen


func _of_type(events: Array[Dictionary], event_type: String) -> Dictionary:
	for event in events:
		if event["type"] == event_type:
			return event
	return {}


func test_plan_burn_refusals() -> void:
	var cases := {
		"burn_in_past": _burn("Scout", 0, 1_000_000),
		"malformed_command": _burn("Scout", 5, 0),
	}
	for reason: String in cases:
		assert_eq(sim.check(cases[reason])["reason"], reason)
	var missing := _burn("Scout", 5, 1_000_000)
	missing["args"].erase("radial_um_s")
	assert_eq(sim.check(missing)["reason"], "malformed_command")
	for id: String in sim._ctx.defs["modules"]:
		sim._ctx.defs["modules"][id]["capabilities"].get("thruster", {}).erase("thrust_n")
	assert_eq(sim.check(_burn("Scout", 5, 1_000_000))["reason"], "module_missing")


func test_check_previews_a_prograde_burn_as_hohmann_predicts() -> void:
	var dv_um_s := _hohmann_um_s(700_000.0, 760_000.0)
	var checked := sim.check(_burn("Orbiter", 10, dv_um_s))
	assert_true(checked["ok"], str(checked))
	var detail: Dictionary = checked["detail"]
	var orbit: Dictionary = detail["orbit"]
	assert_eq(orbit["parent"], keys["Planet"])
	var apoapsis := float(orbit["a_mm"]) * (1.0 + float(orbit["e_q30"]) / ONE)
	assert_almost_eq(apoapsis, 760_000_000.0, 50_000.0)
	var mass_g := Units.unit_mass(sim._state, sim._ctx.defs, keys["Orbiter"])
	assert_almost_eq(detail["propellant_g"], OrbitMath.burn_g(mass_g, dv_um_s, EXHAUST_MM_S), 1)
	assert_almost_eq(detail["dv_um_s"], dv_um_s, 2)
	assert_gt(detail["burn_ticks"], 1)


func test_a_finite_burn_raises_the_orbit_and_balances_the_ledger() -> void:
	var dv_um_s := _hohmann_um_s(700_000.0, 760_000.0)
	sim.submit(_burn("Orbiter", 1, dv_um_s))
	var events := _until("burn_done", 50_000)
	var started := _of_type(events, "burn_started")
	var done := _of_type(events, "burn_done")
	assert_false(started.is_empty())
	assert_false(done.is_empty(), "the burn finishes")
	assert_almost_eq(done["data"]["dv_um_s"], dv_um_s, 2, "the delta-v asked for, to the rounding of its direction")
	var orbit: Dictionary = _unit("Orbiter")["orbit"]
	var apoapsis := float(orbit["a_mm"]) * (1.0 + float(orbit["e_q30"]) / ONE)
	print("BURN Hohmann first burn from 700 km, finite: apoapsis %.1f km, %d g in %d ticks" % [
		apoapsis / 1e6, done["data"]["propellant_g"], sim.current_tick()])
	assert_almost_eq(apoapsis, 760_000_000.0, 2_000_000.0, "a finite burn lands near the impulse's apoapsis")
	var exhaust: int = sim._state["sinks"][Travel.SINK][Travel.PROPELLANT]
	assert_eq(exhaust, done["data"]["propellant_g"])
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
	assert_eq(ledger["violations"], PackedStringArray())
	assert_eq(_unit("Orbiter")["op"]["type"], "idle")


func test_the_thruster_is_a_load_while_burning() -> void:
	sim.submit(_burn("Orbiter", 1, 50_000_000))
	sim.step(3)
	var op: Dictionary = _unit("Orbiter")["op"]
	assert_eq(op["type"], BurnSystem.OP_BURNING)
	var thruster := BurnSystem.thruster(sim._ctx, keys["Orbiter"])
	assert_eq(op["part"], thruster["part"])
	var power: int = Units.module_of(sim._state, sim._ctx.defs, thruster["part"])["power_w"]
	assert_eq(sim._state["parts"][thruster["part"]]["draw_w"], power)


func test_a_burn_in_a_frame_drifts_in_a_straight_line() -> void:
	sim.submit(_burn("Scout", 1, 2_000_000))
	_until("burn_done", 5000)
	var scout := _unit("Scout")
	var vel: Array = scout["vel_um_s"]
	assert_almost_eq(IntMath.dist(vel, [0, 0, 0]), 2_000_000, 2)
	var start: Array = scout["pos_mm"].duplicate()
	sim.step(100)
	for axis in 3:
		var expected := float(start[axis]) + float(vel[axis]) * 100 / Sim.TICKS_PER_SECOND / 1000.0
		assert_almost_eq(float(scout["pos_mm"][axis]), expected, 1.0, "axis %d" % axis)
	assert_eq(scout["frame"], keys["Cluster"])
	assert_eq(scout["at_target"], 0)


func test_a_move_to_in_the_frame_stops_the_drift() -> void:
	_unit("Scout")["vel_um_s"] = [1_000_000, 0, 0]
	sim.submit({ "type": "move_to", "unit": keys["Scout"], "args": { "target": keys["Red Rock"] } })
	_until("arrived", 3000)
	assert_eq(_unit("Scout")["vel_um_s"], [0, 0, 0])
	assert_eq(_unit("Scout")["at_target"], keys["Red Rock"])


func test_drifting_past_the_frame_puts_the_unit_on_an_orbit() -> void:
	var scout := _unit("Scout")
	scout["vel_um_s"] = [10_000_000_000, 0, 0]
	var local: Array = []
	var events: Array[Dictionary] = []
	for i in 4000:
		local = scout["pos_mm"].duplicate()
		sim.step()
		events = sim.take_events()
		if not _of_type(events, "frame_left").is_empty():
			break
	assert_false(_of_type(events, "frame_left").is_empty(), "left the frame")
	assert_eq(scout["frame"], 0)
	assert_eq(scout["orbit"]["parent"], keys["Star"])
	# A tick later, the new orbit should be where the frame plus the drift would have put it.
	sim.step()
	var frame_mm: Array = sim._state["frames"][keys["Cluster"]]["pos_mm"]
	var expected := [frame_mm[0] + local[0] + 2_000_000, frame_mm[1] + local[1], frame_mm[2] + local[2]]
	var gap := IntMath.dist(expected, RailSystem.world_mm(sim._state, "units", keys["Scout"]))
	print("BURN leaving the frame at 1 AU: the orbit is %d mm from the drift's place a tick later" % gap)
	assert_lt(gap, 1_000_000, "within the few hundred metres of integer orbits at 1 AU")


func test_a_slow_unit_near_a_frame_joins_it() -> void:
	var orbiter := _unit("Orbiter")
	var frame_orbit: Dictionary = sim._state["frames"][keys["Cluster"]]["orbit"]
	orbiter["orbit"] = frame_orbit.duplicate(true)
	orbiter["orbit"]["m0_angle"] += 10_000_000  # a few km behind along the orbit
	sim.step()
	var joined := _of_type(sim.take_events(), "frame_joined")
	assert_false(joined.is_empty())
	assert_eq(orbiter["frame"], keys["Cluster"])
	assert_eq(orbiter["orbit"], {})
	assert_lt(IntMath.dist(orbiter["pos_mm"], [0, 0, 0]), 1_000_000_000)
	assert_lt(IntMath.dist(orbiter["vel_um_s"], [0, 0, 0]), BurnSystem.JOIN_SPEED_UM_S)


func test_cancel_removes_a_planned_burn_and_stops_a_running_one() -> void:
	sim.submit(_burn("Orbiter", 50, 10_000_000))
	sim.step()
	var planned: int = _unit("Orbiter")["burns"][0]["id"]
	sim.submit({ "type": "cancel_burn", "unit": keys["Orbiter"], "args": { "burn": planned } })
	sim.step()
	assert_eq(_unit("Orbiter")["burns"], [])
	sim.submit(_burn("Orbiter", sim.current_tick() + 1, 50_000_000))
	sim.step(3)
	var running: int = _unit("Orbiter")["burn"]["id"]
	sim.submit({ "type": "cancel_burn", "unit": keys["Orbiter"], "args": { "burn": running } })
	sim.step()
	var short := _of_type(sim.take_events(), "burn_short")
	assert_eq(short["data"]["reason"], "cancelled")
	assert_gt(short["data"]["dv_um_s"], 0)
	assert_eq(_unit("Orbiter")["op"]["type"], "idle")
	assert_eq(sim.check({ "type": "cancel_burn", "unit": keys["Orbiter"], "args": { "burn": 9999 } })["reason"],
		"invalid_target")


func test_running_out_of_propellant_ends_the_burn_short() -> void:
	_unit("Orbiter")["inventory"]["propellant"] = 20
	sim._state["matter_start_g"] -= FULL_TANK_G - 20
	sim.submit(_burn("Orbiter", 1, 50_000_000))
	var short := _of_type(_until("burn_short", 100), "burn_short")
	assert_eq(short["data"]["reason"], "no_propellant")
	assert_lte(short["data"]["propellant_g"], 20)
	assert_eq(sim.ledger()["matter"]["total_g"], sim.ledger()["matter"]["start_g"])


func test_save_and_load_midway_through_a_burn_is_byte_exact() -> void:
	sim.submit(_burn("Orbiter", 1, 90_355_000))
	sim.submit(_burn("Scout", 1, 3_000_000, 1_000_000))
	sim.step(300)
	var saved := sim.to_save()
	var loaded := Sim.from_save(saved)
	assert_not_null(loaded, Sim.last_error())
	assert_eq(loaded.to_save(), saved)
	sim.step(2000)
	loaded.step(2000)
	assert_eq(loaded.state_hash(), sim.state_hash())


func test_predict_follows_the_orbit_and_the_drift() -> void:
	var orbit_path := sim.predict(keys["Orbiter"], 0, 100, 10)
	assert_eq(orbit_path["place"], { "orbit_parent": keys["Planet"] })
	assert_eq(orbit_path["points"].size(), 11)
	assert_eq(orbit_path["points"][3], OrbitMath.position_at(_unit("Orbiter")["orbit"], 30))
	_unit("Scout")["vel_um_s"] = [1_000_000, 0, 0]
	var drift := sim.predict(keys["Scout"], 0, 20, 10)
	assert_eq(drift["place"], { "frame": keys["Cluster"] })
	assert_eq(drift["points"][2], [152_000, 0, 0], "1 m/s for 2 s")
	assert_eq(sim.predict(keys["Scout"], 0, 1_000_000, 1), {}, "too many points")
	assert_eq(sim.predict(999, 0, 10, 1), {})


## A burn planned the moment the view shows a ship undocked starts on time: the undock step ends
## in phase 2 of the next tick, before the burn looks at whether the ship is free.
func test_a_burn_right_after_undocking_starts() -> void:
	var game := Sim.new_game("reference", 12345)
	var probe := 23
	game.submit({ "type": "undock", "unit": probe, "args": {} })
	while not game.view()["units"][probe]["dock"].is_empty():
		game.step()
	game.take_events()
	game.submit({ "type": "plan_burn", "unit": probe, "args": {
		"tick": game.current_tick() + 1, "prograde_um_s": 1_000_000, "normal_um_s": 0, "radial_um_s": 0 } })
	game.step()
	var types := game.take_events().map(func(e: Dictionary) -> String: return e["type"])
	assert_true(types.has("burn_started"), str(types))
	assert_false(types.has("burn_short"), str(types))


## A12: a prograde burn past escape speed leaves the planet on a hyperbola, and the unit moves
## into the star's sphere of influence on the tick it crosses the planet's.
func test_escaping_a_planet_crosses_into_the_stars_sphere() -> void:
	var planet: Dictionary = sim._state["bodies"][keys["Planet"]]
	assert_gt(planet["soi_mm"], 0)
	var orbiter := _unit("Orbiter")
	# Start on a hyperbola 1000 km inside the sphere, heading out at 5 km/s, so the crossing comes soon.
	var inside: int = planet["soi_mm"] - 1_000_000_000
	var escape := OrbitMath.from_state([inside, 0, 0], [5_000_000_000, 0, -300_000_000], GM_PLANET, 0)
	assert_true(escape["hyperbolic"])
	escape["parent"] = keys["Planet"]
	orbiter["orbit"] = escape
	var before: Array[int] = []
	var seen: Dictionary = {}
	for i in 5000:
		before = RailSystem.world_mm(sim._state, "units", keys["Orbiter"])
		sim.step()
		var crossed := _of_type(sim.take_events(), "soi_changed")
		if not crossed.is_empty():
			seen = crossed
			break
	assert_eq(seen.get("data", {}), { "from": keys["Planet"], "to": keys["Star"] })
	assert_eq(orbiter["orbit"]["parent"], keys["Star"])
	var after := RailSystem.world_mm(sim._state, "units", keys["Orbiter"])
	var step_mm := IntMath.dist(before, after)
	print("BURN escape: crossed the %d km sphere at tick %d, world step %d km" % [
		planet["soi_mm"] / 1_000_000, sim.current_tick(), step_mm / 1_000_000])
	assert_lt(step_mm, 10_000_000, "a tick's motion of a few km, with no jump")


func test_a_unit_falling_into_a_planets_sphere_changes_parent() -> void:
	var planet: Dictionary = sim._state["bodies"][keys["Planet"]]
	var around_star := OrbitMath.state_at(planet["orbit"], GM_STAR, 0)
	var offset: int = planet["soi_mm"] + 1_000_000
	var r: Array = around_star["r"]
	var v: Array = around_star["v"]
	var orbiter := _unit("Orbiter")
	orbiter["orbit"] = OrbitMath.from_state([r[0] + offset, r[1], r[2]], [v[0] - 5_000_000_000, v[1], v[2]], GM_STAR, 0)
	orbiter["orbit"]["parent"] = keys["Star"]
	var crossed := _of_type(_until("soi_changed", 20_000), "soi_changed")
	assert_eq(crossed.get("data", {}), { "from": keys["Star"], "to": keys["Planet"] })
	assert_eq(orbiter["orbit"]["parent"], keys["Planet"])
	assert_lt(IntMath.dist(orbiter["pos_mm"], [0, 0, 0]), planet["soi_mm"])


func test_save_and_load_on_a_hyperbola_is_byte_exact() -> void:
	var orbiter := _unit("Orbiter")
	orbiter["orbit"] = OrbitMath.from_state(orbiter["pos_mm"], [0, 0, -3_400_000_000], GM_PLANET, 0)
	orbiter["orbit"]["parent"] = keys["Planet"]
	sim.step(500)
	var saved := sim.to_save()
	var loaded := Sim.from_save(saved)
	assert_eq(loaded.to_save(), saved)
	sim.step(1000)
	loaded.step(1000)
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_eq(sim.ledger()["violations"], PackedStringArray())


func test_the_view_shows_burns() -> void:
	sim.submit(_burn("Orbiter", 1, 50_000_000))
	sim.submit(_burn("Orbiter", 900, 1_000_000))
	sim.step(2)
	var shown: Dictionary = sim.view()["units"][keys["Orbiter"]]
	assert_eq(shown["burns"].size(), 1)
	assert_eq(shown["burns"][0]["tick"], 900)
	assert_almost_eq(shown["burn"]["dv_um_s"], 50_000_000, 2)
	assert_gt(shown["burn"]["done_um_s"], 0)
	assert_eq(shown["vel_um_s"], [0, 0, 0])
	assert_eq(shown["op"]["type"], BurnSystem.OP_BURNING)
