extends GutTest
## Landing, takeoff and collisions (task A15, orbital_flight.md section 11, planets.md section 3.2),
## and the player's hand-flown landing in low flight (task A19).

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const AU_MM := 149_597_870_700_000
const RADIUS_MM := 600_000_000
const ONE := OrbitMath.ONE
const PROPELLANT_G := 12_000_000

const GEAR_MM_S := 6000

var sim: Sim
var keys := {}
## The hull this file fitted with landing gear in the cached data, to take it off afterwards.
var _geared: Dictionary = {}


## Landing needs gear (A19), and B15's legs aren't in data yet, so the starter hull carries some.
## It is patched in the cached definitions so a loaded save sees the same data hash.
func before_all() -> void:
	var hull: Dictionary = DataLoader.load_defs()["modules"]["starter_hull"]["capabilities"]
	if not hull.has(LowFlight.GEAR):
		hull[LowFlight.GEAR] = { "max_touchdown_mm_s": GEAR_MM_S }
		_geared = hull


func after_all() -> void:
	_geared.erase(LowFlight.GEAR)


func before_each() -> void:
	var defs := DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": RADIUS_MM, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM },
				"planet": { "seed": 48213, "height_range_m": 8000 } },
		],
		"units": [
			{ "key": "ship", "template": "starter_ship", "name": "Ship", "pos_mm": [0, 0, 0],
				"inventory": [{ "item": "propellant", "grams": PROPELLANT_G }], "dock": null },
		],
	}, {}), "")
	sim._strict = true
	keys = {}
	for table: String in ["bodies", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	_put_in_orbit(OrbitMath.make_orbit(GM_PLANET, 700_000_000, 0, [ONE, 0, 0], [0, 0, -ONE], 0, 0))


func _ship() -> Dictionary:
	return sim._state["units"][keys["Ship"]]


func _put_in_orbit(orbit: Dictionary) -> void:
	orbit["parent"] = keys["Planet"]
	_ship()["orbit"] = orbit
	_ship()["pos_mm"] = OrbitMath.position_at(orbit, sim.current_tick())
	sim._ctx.index.clear()


func _land(cell: int) -> Dictionary:
	return { "type": "land", "unit": keys["Ship"], "args": { "body": keys["Planet"], "cell": cell } }


func _until(event_type: String, limit: int) -> Dictionary:
	for i in limit:
		sim.step()
		for event in sim.take_events():
			if event["type"] == event_type:
				return event
	return {}


func test_landing_sets_the_ship_down_on_its_cell() -> void:
	var checked := sim.check(_land(4242))
	assert_true(checked["ok"], str(checked))
	var detail: Dictionary = checked["detail"]
	print("LAND from 700 km: %d m/s, %d kg, %d ticks" % [
		detail["dv_um_s"] / 1_000_000, detail["propellant_g"] / 1000, detail["ticks"]])
	assert_between(detail["dv_um_s"], 2_300_000_000, 2_700_000_000, "about 2.3 to 2.6 km/s, as planned")
	sim.submit(_land(4242))
	sim.step()
	assert_eq(_ship()["op"]["type"], LandingSystem.OP_LANDING)
	var landed := _until("landed", detail["ticks"] + 5)
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


func test_take_off_reaches_a_circular_orbit() -> void:
	LandingSystem._set_down(sim._ctx, keys["Ship"], keys["Planet"], 777)
	var command := { "type": "take_off", "unit": keys["Ship"], "args": { "altitude_mm": 100_000_000 } }
	var checked := sim.check(command)
	assert_true(checked["ok"], str(checked))
	sim.submit(command)
	var took := _until("took_off", 30_000)
	assert_false(took.is_empty())
	var orbit: Dictionary = _ship()["orbit"]
	assert_eq(orbit["parent"], keys["Planet"])
	assert_almost_eq(orbit["a_mm"], 700_000_000, 10_000, "a circle at 100 km altitude")
	assert_lt(orbit["e_q30"], ONE / 100_000)
	assert_eq(_ship()["landed"], {})


func test_landing_and_takeoff_refusals() -> void:
	var cases := {
		"invalid_target": _land(PlanetGrid.cell_count(100)),
		"malformed_command": { "type": "land", "unit": keys["Ship"], "args": { "body": keys["Planet"] } },
		"not_flying": { "type": "land", "unit": keys["Ship"], "args": { "body": keys["Star"], "cell": 0 } },
		"not_landed": { "type": "take_off", "unit": keys["Ship"], "args": { "altitude_mm": 100_000_000 } },
	}
	for reason: String in cases:
		assert_eq(sim.check(cases[reason])["reason"], reason, reason)
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

## Puts the ship in low flight a height above the ground of a cell, still.
func _hover(cell: int, height_mm: int) -> void:
	var ground := LandingSystem.cell_mm(sim._ctx, keys["Planet"], cell)
	var up := OrbitMath.unit(ground)
	var ship := _ship()
	ship["orbit"] = {}
	ship["low_flight"] = keys["Planet"]
	ship["pos_mm"] = [ground[0] + OrbitMath.smul_div(up[0], height_mm, ONE),
		ground[1] + OrbitMath.smul_div(up[1], height_mm, ONE), ground[2] + OrbitMath.smul_div(up[2], height_mm, ONE)]
	ship["vel_um_s"] = [0, 0, 0]
	ship["drift_carry"] = [0, 0, 0]


func _until_any(types: Array, limit: int) -> Dictionary:
	for i in limit:
		sim.step()
		for event in sim.take_events():
			if types.has(event["type"]):
				return event
	return {}


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
	# An ellipse from 700 km down to a 15 km periapsis.
	var periapsis := RADIUS_MM + 15_000_000
	var a := (700_000_000 + periapsis) / 2
	var apo_speed := OrbitMath.speed_um_s(GM_PLANET, 700_000_000, a)
	_put_in_orbit(OrbitMath.from_state([700_000_000, 0, 0], [0, 0, -apo_speed], GM_PLANET, sim.current_tick()))
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


func _geared_off() -> void:
	var defs: Dictionary = sim._ctx.defs.duplicate(true)
	defs["modules"]["starter_hull"]["capabilities"].erase(LowFlight.GEAR)
	sim._ctx.defs = defs
	assert_eq(LowFlight.touchdown_mm_s(sim._ctx, keys["Ship"]), 0)


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
