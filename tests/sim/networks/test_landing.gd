extends "res://tests/sim/networks/landing_fixture.gd"
## Landing, takeoff and collisions (task A15, orbital_flight.md section 11, planets.md section 3.2),
## and the player's hand-flown landing in low flight (task A19). Flights that take half an orbit
## and can't be shortened are in tests/slow/test_landing_flights.gd (A24).


func test_landing_sets_the_ship_down_on_its_cell() -> void:
	_strong_thruster()
	var checked := sim.check(_land(4242))
	assert_true(checked["ok"], str(checked))
	var detail: Dictionary = checked["detail"]
	print("LAND from 700 km: %d m/s, %d kg, %d ticks" % [
		detail["dv_um_s"] / 1_000_000, detail["propellant_g"] / 1000, detail["ticks"]])
	assert_between(detail["dv_um_s"], 2_900_000_000, 3_200_000_000, "about 3.06 km/s, with 18% lost at 3.7 g (A27)")
	sim.submit(_land(4242))
	sim.step()
	assert_eq(_ship()["op"]["type"], LandingSystem.OP_LANDING)
	sim.step(detail["ticks"] - 5)
	assert_eq(_ship()["op"]["type"], LandingSystem.OP_LANDING, "still descending")
	var landed := _until("landed", 10)
	assert_eq(landed["data"], { "body": keys["Planet"], "cell": 4242 })
	assert_eq(_ship()["landed"], { "body": keys["Planet"], "cell": 4242 })
	assert_eq(_ship()["orbit"], {})
	var dir := PlanetGrid.direction(4242, 100)
	var height := PlanetGrid.height_m(48213, dir, LandingSystem.HEIGHT_WEIGHTS, 8000)
	assert_eq(_ship()["pos_mm"], PlanetGrid.centre_mm(4242, 100, RADIUS_MM, height), "at the cell's centre and height")
	var planet_world := RailSystem.world_mm(sim._state, "bodies", keys["Planet"])
	var world := RailSystem.world_mm(sim._state, "units", keys["Ship"])
	for axis in 3:
		assert_eq(world[axis], planet_world[axis] + int(_ship()["pos_mm"][axis]))
	assert_eq(sim._state["sinks"][Travel.SINK][Travel.PROPELLANT], detail["propellant_g"])
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
	assert_eq(ledger["violations"], PackedStringArray())
	sim.step(50)
	assert_eq(_ship()["pos_mm"], PlanetGrid.centre_mm(4242, 100, RADIUS_MM, height), "a landed ship stays put")


func test_landing_and_takeoff_refusals() -> void:
	var cases := {
		"invalid_target": _land(PlanetGrid.cell_count(100)),
		"malformed_command": { "type": "land", "unit": keys["Ship"], "args": { "body": keys["Planet"] } },
		"not_flying": { "type": "land", "unit": keys["Ship"], "args": { "body": keys["Star"], "cell": 0 } },
		"not_landed": { "type": "take_off", "unit": keys["Ship"], "args": { "altitude_mm": 100_000_000 } },
	}
	for reason: String in cases:
		assert_eq(sim.check(cases[reason])["reason"], reason, reason)
	assert_eq(sim.check(_land(5))["reason"], "thrust_too_low", "15 kN can't hold up 16 t at Kerbin's gravity")
	_strong_thruster()
	_ship()["inventory"]["propellant"] = 1000
	assert_eq(sim.check(_land(5))["reason"], "no_propellant")
	_ship()["inventory"]["propellant"] = PROPELLANT_G
	LandingSystem._set_down(sim._ctx, keys["Ship"], keys["Planet"], 5)
	var burn := { "type": "plan_burn", "unit": keys["Ship"], "args": {
		"tick": 5, "prograde_um_s": 1_000_000, "normal_um_s": 0, "radial_um_s": 0 } }
	assert_true(sim.check(burn)["ok"], "a burn on the ground is a lift-off (A19)")
	assert_eq(sim.check({ "type": "take_off", "unit": keys["Ship"], "args": { "altitude_mm": 0 } })["reason"],
		"malformed_command")


func test_an_orbit_into_the_ground_crashes_on_the_cell_below() -> void:
	# Too slow for orbit at 700 km: it falls and meets the surface on the far side.
	_put_in_orbit(OrbitMath.from_state([700_000_000, 0, 0], [0, 0, -1_000_000_000], GM_PLANET, 0))
	var crashed := _until("crashed", 20_000)
	assert_false(crashed.is_empty(), "it came down")
	var cell: int = crashed["data"]["cell"]
	assert_eq(_ship()["landed"], { "body": keys["Planet"], "cell": cell })
	# The cell below is the nearest one: no neighbour's centre points closer to where it came down.
	var impact := OrbitMath.unit(_ship()["pos_mm"])
	var mine := OrbitMath.dot(PlanetGrid.direction(cell, 100), impact)
	for other in PlanetGrid.neighbours(cell, 100):
		assert_lte(OrbitMath.dot(PlanetGrid.direction(other, 100), impact), mine)
	assert_eq(sim.ledger()["violations"], PackedStringArray())


## A burn still running when the ship hits the ground ends with the crash. The ship starts on a
## path that already falls, so the test needn't fly a long deorbit burn first (A20).
func test_a_burn_into_the_ground_ends_with_the_crash() -> void:
	_put_in_orbit(OrbitMath.from_state([700_000_000, 0, 0], [0, 0, -1_000_000_000], GM_PLANET, 0))
	sim.submit({ "type": "plan_burn", "unit": keys["Ship"], "args": {
		"tick": 1, "prograde_um_s": -1_000_000_000, "normal_um_s": 0, "radial_um_s": 0 } })
	var seen: Array[Dictionary] = []
	for i in 30_000:
		sim.step()
		seen.append_array(sim.take_events())
		if seen.any(func(e: Dictionary) -> bool: return e["type"] == "crashed"):
			break
	var types := seen.map(func(e: Dictionary) -> String: return e["type"])
	assert_true(types.has("crashed"), str(types))
	assert_false(_ship()["landed"].is_empty())


func test_a_landed_ship_cannot_move_to_or_burn() -> void:
	LandingSystem._set_down(sim._ctx, keys["Ship"], keys["Planet"], 9)
	assert_eq(sim.quote(keys["Ship"], keys["Star"], 0)["reason"], "unsupported_orbit")
	assert_eq(sim.predict(keys["Ship"], 0, 10, 5)["place"], { "landed": keys["Planet"] })
	assert_eq(sim.view()["units"][keys["Ship"]]["landed"], { "body": keys["Planet"], "cell": 9 })
	assert_eq(sim.view()["bodies"][keys["Planet"]]["planet"], { "seed": 48213, "height_range_m": 8000 })


## Mid-landing and landed. The landing itself is checked elsewhere, so this saves part-way through
## it, and again once set down, rather than flying the whole descent twice (A20).
func test_save_and_load_while_landing_and_landed_is_byte_exact() -> void:
	_strong_thruster()
	sim.submit(_land(4242))
	sim.step(200)
	var saved := sim.to_save()
	var loaded := Sim.from_save(saved)
	assert_eq(loaded.to_save(), saved)
	loaded.step(1500)
	sim.step(1500)
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_eq(_ship()["op"]["type"], LandingSystem.OP_LANDING, "still on the way down")
	_ship()["op"] = { "type": Units.IDLE_OP, "target": 0, "part": 0, "start_tick": 0, "end_tick": 0 }
	LandingSystem._set_down(sim._ctx, keys["Ship"], keys["Planet"], 4242)
	saved = sim.to_save()
	loaded = Sim.from_save(saved)
	assert_eq(loaded.to_save(), saved)
	loaded.step(300)
	sim.step(300)
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_false(_ship()["landed"].is_empty())


# ------------------------------------------------------------------------------ A16: planet shadow


## On the far side of the planet from the star, solar panels give nothing; on the near side, full.
func test_solar_power_stops_in_a_planets_shadow() -> void:
	var planet_mm := RailSystem.world_mm(sim._state, "bodies", keys["Planet"])
	var away := OrbitMath.unit(planet_mm)
	var behind: Array[int] = []
	var ahead: Array[int] = []
	for axis in 3:
		behind.append(OrbitMath.smul_div(away[axis], 700_000_000, ONE))
		ahead.append(-behind[axis])
	_ship()["orbit"] = {}
	_ship()["pos_mm"] = behind
	_ship()["orbit"] = OrbitMath.from_state(behind, [0, 1_000_000_000, 0], GM_PLANET, sim.current_tick())
	_ship()["orbit"]["parent"] = keys["Planet"]
	_ship()["inventory"]["propellant"] = PROPELLANT_G
	assert_true(RailSystem.in_shadow(sim._state, keys["Ship"]), "behind the planet")
	sim.step()
	assert_eq(sim.view()["units"][keys["Ship"]]["power"]["supply_w"], 0)
	_ship()["pos_mm"] = ahead
	assert_false(RailSystem.in_shadow(sim._state, keys["Ship"]), "between the star and the planet")
	_ship()["pos_mm"] = [behind[0], behind[1] + 700_000_000, behind[2]]
	assert_false(RailSystem.in_shadow(sim._state, keys["Ship"]), "behind, but beside the shadow")
	LandingSystem._set_down(sim._ctx, keys["Ship"], keys["Planet"], LandingSystem.cell_below(sim._ctx, keys["Planet"], ahead))
	assert_false(RailSystem.in_shadow(sim._state, keys["Ship"]), "landed on the day side")
	LandingSystem._set_down(sim._ctx, keys["Ship"], keys["Planet"], LandingSystem.cell_below(sim._ctx, keys["Planet"], behind))
	assert_true(RailSystem.in_shadow(sim._state, keys["Ship"]), "landed on the night side")


# ------------------------------------------------------------------------------ A19: hand-flown landing


func test_a_gentle_touchdown_lands() -> void:
	_hover(4242, 1000)  # 1 m up: about 4.4 m/s at the ground, under the 6 m/s legs
	var event := _until_any(["landed", "crashed"], 100)
	assert_eq(event.get("type", ""), "landed", str(event))
	assert_lt(event["data"]["speed_um_s"], GEAR_MM_S * 1000)
	assert_eq(_ship()["landed"], { "body": keys["Planet"], "cell": 4242 })
	assert_eq(_ship()["low_flight"], 0)


func test_a_hard_touchdown_crashes() -> void:
	_hover(4242, 100_000)  # 100 m up: about 44 m/s at the ground
	var event := _until_any(["landed", "crashed"], 200)
	assert_eq(event.get("type", ""), "crashed", str(event))
	assert_gt(event["data"]["speed_um_s"], GEAR_MM_S * 1000)
	assert_false(_ship()["landed"].is_empty())


func test_ground_contact_is_at_the_cells_real_height() -> void:
	var cell := 4242
	var ground := IntMath.dist(LandingSystem.cell_mm(sim._ctx, keys["Planet"], cell), [0, 0, 0])
	assert_ne(ground, RADIUS_MM, "this cell is not at the datum")
	_hover(cell, 1000)
	_until_any(["landed", "crashed"], 100)
	assert_eq(IntMath.dist(_ship()["pos_mm"], [0, 0, 0]), ground)


func test_predict_shows_the_contact_the_flight_meets() -> void:
	_hover(4242, 100_000)
	var ahead := sim.predict(keys["Ship"], sim.current_tick(), 500, 10)
	assert_eq(ahead["place"], { "low_flight": keys["Planet"] })
	var contact: Dictionary = ahead["contact"]
	assert_false(contact.is_empty())
	var event := _until_any(["crashed"], 500)
	assert_eq(sim.current_tick(), contact["tick"], "the predicted tick")
	assert_eq(event["data"]["speed_um_s"], contact["speed_um_s"], "the predicted speed")
	assert_eq(event["data"]["cell"], contact["cell"])


func test_an_orbit_dipping_low_enters_low_flight_and_climbing_leaves_it() -> void:
	# An ellipse from 700 km down to a 15 km periapsis, joined 1500 ticks before periapsis rather
	# than at apoapsis, half an orbit earlier (A24).
	var periapsis := RADIUS_MM + 15_000_000
	var a := (700_000_000 + periapsis) / 2
	var apo_speed := OrbitMath.speed_um_s(GM_PLANET, 700_000_000, a)
	var half_orbit := OrbitMath.period_sub(GM_PLANET, a) / OrbitMath.SUB_TICKS / 2
	var at_apoapsis := sim.current_tick() - (half_orbit - 1500)
	_put_in_orbit(OrbitMath.from_state([700_000_000, 0, 0], [0, 0, -apo_speed], GM_PLANET, at_apoapsis))
	assert_gt(LowFlight.altitude_mm(sim._ctx, keys["Planet"], _ship()["pos_mm"]), LowFlight.ENTER_MM, "it starts above low flight")
	var entered := _until_any(["low_flight_entered"], 20_000)
	assert_eq(entered.get("data", {}), { "body": keys["Planet"] })
	assert_eq(_ship()["orbit"], {})
	var left := _until_any(["low_flight_left", "crashed", "landed"], 20_000)
	assert_eq(left.get("type", ""), "low_flight_left", "it skims past periapsis and climbs out")
	assert_eq(_ship()["orbit"]["parent"], keys["Planet"])


func test_lift_off_needs_thrust_over_weight() -> void:
	LandingSystem._set_down(sim._ctx, keys["Ship"], keys["Planet"], 4242)
	# On this planet the starter ship's thrust is under its weight: it lifts, settles and lands again.
	sim.submit({ "type": "plan_burn", "unit": keys["Ship"], "args": {
		"tick": sim.current_tick() + 1, "prograde_um_s": 0, "normal_um_s": 0, "radial_um_s": 20_000_000 } })
	var event := _until_any(["landed", "crashed"], 200)
	assert_eq(event.get("type", ""), "landed", "settles back gently")
	# With almost no gravity the same burn climbs away.
	sim._state["bodies"][keys["Planet"]]["gm"] = 1000
	sim.submit({ "type": "plan_burn", "unit": keys["Ship"], "args": {
		"tick": sim.current_tick() + 1, "prograde_um_s": 0, "normal_um_s": 0, "radial_um_s": 20_000_000 } })
	sim.step(200)
	assert_eq(_ship()["low_flight"], keys["Planet"])
	assert_gt(LowFlight.altitude_mm(sim._ctx, keys["Planet"], _ship()["pos_mm"]), 10_000)


func test_atomic_land_needs_gear() -> void:
	_geared_off()
	assert_eq(sim.check(_land(4242))["reason"], "no_landing_gear")


func test_save_and_load_in_low_flight_is_byte_exact() -> void:
	_hover(4242, 2_000_000)
	sim.step(5)
	var saved := sim.to_save()
	var loaded := Sim.from_save(saved)
	assert_eq(loaded.to_save(), saved)
	sim.step(300)
	loaded.step(300)
	assert_eq(loaded.state_hash(), sim.state_hash())
	assert_eq(sim.ledger()["violations"], PackedStringArray())


## The walk from a hint, near or far, ends at the same cell as the walk from the corners, so a path
## that remembers its last cell meets the ground where the flight does.
func test_a_hinted_search_finds_the_same_cell() -> void:
	var planet: int = keys["Planet"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var far_misses := 0
	for i in 60:
		var pos: Array[int] = [rng.randi_range(-ONE, ONE), rng.randi_range(-ONE, ONE), rng.randi_range(-ONE, ONE)]
		if pos == [0, 0, 0]:
			continue
		var cold := LandingSystem.cell_below(sim._ctx, planet, pos)
		var near_pos: Array[int] = [pos[0] + ONE / 100, pos[1], pos[2]]
		var near := LandingSystem.cell_below(sim._ctx, planet, near_pos)
		assert_eq(LandingSystem.cell_below(sim._ctx, planet, pos, near), cold, "from a nearby cell")
		if LandingSystem.cell_below(sim._ctx, planet, pos, rng.randi_range(0, 4000)) != cold:
			far_misses += 1
	assert_eq(far_misses, 0, "from anywhere at all")


## D's finding on A19: a path skimming the ground looked up its cell from scratch every tick, about
## 2 s for this hop before the fix. A 300 m/s hop from 2 km up stays under the contact gate for
## about 670 ticks and crosses about 200 km of cells; predict must stay quick and still meet the
## ground where the flight does.
func test_predict_skimming_the_ground_is_quick_and_matches_the_flight() -> void:
	_hover(4242, 2_000_000)
	var up := OrbitMath.unit(_ship()["pos_mm"])
	var east := OrbitMath.unit(OrbitMath.cross(up, [0, ONE, 0]))
	var vel: Array[int] = []
	for axis in 3:
		vel.append(OrbitMath.smul_div(east[axis], 300_000_000, ONE) + OrbitMath.smul_div(up[axis], 300_000_000, ONE))
	_ship()["vel_um_s"] = vel
	var started := Time.get_ticks_usec()
	var ahead := sim.predict(keys["Ship"], sim.current_tick(), 3000, 10)
	var took_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("PREDICT near the ground: %.1f ms to contact at +%d ticks" % [took_ms, ahead["contact"].get("tick", 0) - sim.current_tick()])
	var contact: Dictionary = ahead["contact"]
	assert_false(contact.is_empty())
	assert_gt(contact["tick"] - sim.current_tick(), 500, "a long hop under the gate")
	assert_lt(took_ms, 500.0, "a quarter of the old cost at most, with room for a loaded machine")
	var event := _until_any(["crashed", "landed"], 3000)
	assert_eq(sim.current_tick(), contact["tick"], "the predicted tick")
	assert_eq(event["data"]["cell"], contact["cell"], "the predicted cell")
	assert_eq(event["data"]["speed_um_s"], contact["speed_um_s"], "the predicted speed")


# ------------------------------------------------------------------------------ A27: gravity loss


func test_gravity_loss_grows_as_thrust_over_weight_falls() -> void:
	assert_eq(LandingSystem.loss_permille(2_000_000, 660, 0), 1330, "1 + 0.66 / 2")
	assert_eq(LandingSystem.loss_permille(2_000_000, 320, 260), 1225, "1 + 0.32 / 2 + 0.26 / 4")
	assert_eq(LandingSystem.loss_permille(2_200_000, LandingSystem.LAND_LOSS_A, LandingSystem.LAND_LOSS_B), 1300,
		"a landing at 2.2 g loses 30%, as flown")
	assert_lte(LandingSystem.loss_permille(1_000_000_000, 660, 260), 1002, "almost nothing at a huge thrust")
	var costs: Array[int] = []
	for thrust_n: int in [300_000, 600_000, 1_200_000]:
		_strong_thruster()
		var part: int = BurnSystem.thruster(sim._ctx, keys["Ship"])["part"]
		Units.module_of(sim._state, sim._ctx.defs, part)["capabilities"]["thruster"]["thrust_n"] = thrust_n
		costs.append(sim.check(_land(4242))["detail"]["dv_um_s"])
	assert_gt(costs[0], costs[1], "less thrust, more loss")
	assert_gt(costs[1], costs[2])


func test_land_and_take_off_need_thrust_over_weight_above_one() -> void:
	# 16.6 t at 9.8 m/s^2 weighs 163 kN: just under it is refused, just over it is quoted.
	var weight_n := IntMath.mul_div(Units.unit_mass(sim._state, sim._ctx.defs, keys["Ship"]),
		GM_PLANET * 1_000_000 / RADIUS_MM, RADIUS_MM)
	_strong_thruster()
	var part: int = BurnSystem.thruster(sim._ctx, keys["Ship"])["part"]
	var thruster: Dictionary = Units.module_of(sim._state, sim._ctx.defs, part)["capabilities"]["thruster"]
	thruster["thrust_n"] = weight_n - 100
	assert_eq(sim.check(_land(4242))["reason"], "thrust_too_low")
	thruster["thrust_n"] = weight_n + 2000
	# Barely over its weight the loss is huge, so the tank may not cover it, but it is not refused
	# for thrust.
	assert_ne(sim.check(_land(4242)).get("reason", ""), "thrust_too_low")
	LandingSystem._set_down(sim._ctx, keys["Ship"], keys["Planet"], 4242)
	var take_off := { "type": "take_off", "unit": keys["Ship"], "args": { "altitude_mm": 100_000_000 } }
	assert_ne(sim.check(take_off).get("reason", ""), "thrust_too_low")
	thruster["thrust_n"] = weight_n - 100
	assert_eq(sim.check(take_off)["reason"], "thrust_too_low")
