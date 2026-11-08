extends "res://tests/sim/networks/landing_fixture.gd"
## One integrator for powered flight (task A55, real_orbits.md section 2): burns on an orbit are
## stepped by velocity Verlet and go back onto an exact orbit, throttle and steering, check flying
## the same steps, the view's surface_contact_tick, and A57's apsides and predict additions.

const BURN := { "tick": 3, "prograde_um_s": 40_000_000, "normal_um_s": 3_000_000, "radial_um_s": -2_000_000 }


func _plan(args: Dictionary) -> int:
	return sim.submit({ "type": "plan_burn", "unit": keys["Ship"], "args": args })


func _types() -> Array:
	var out: Array = []
	for event in sim.take_events():
		out.append(event["type"])
	return out


func _without_apsides(orbit: Dictionary) -> Dictionary:
	var plain := orbit.duplicate(true)
	for key: String in ["periapsis_mm", "apoapsis_mm", "next_periapsis_tick", "next_apoapsis_tick"]:
		plain.erase(key)
	return plain


func test_a_burn_on_an_orbit_is_stepped_and_ends_on_an_exact_orbit() -> void:
	_plan(BURN)
	sim.step(2)
	sim.take_events()
	sim.step()
	assert_has(_types(), "stepped_entered", "the burn's start steps the unit")
	assert_eq(_ship()["stepped"], keys["Planet"])
	assert_eq(_ship()["orbit"], {})
	var ended := _until("burn_done", 5000)
	assert_false(ended.is_empty())
	assert_eq(_ship()["stepped"], 0, "back on an orbit on the tick the burn ends")
	assert_false(_ship()["orbit"].is_empty())


func test_check_flies_the_burn_exactly() -> void:
	var checked := sim.check({ "type": "plan_burn", "unit": keys["Ship"], "args": BURN })
	assert_true(checked["ok"], str(checked))
	var detail: Dictionary = checked["detail"]
	assert_false(detail.has("approximate"))
	assert_eq(detail["lead_ticks"], int(detail["burn_ticks"]) / 2)
	_plan(BURN)
	var ended := _until("burn_done", 5000)
	assert_eq(ended["data"]["propellant_g"], detail["propellant_g"])
	assert_eq(ended["tick"] - BURN["tick"] + 1, detail["burn_ticks"])
	assert_eq(_ship()["orbit"], _without_apsides(detail["orbit"]), "the same orbit, to the last unit")
	assert_eq(detail["orbit"]["periapsis_mm"], OrbitMath.periapsis_radius_mm(_ship()["orbit"]))


## The path check draws is where the unit really goes, burn and all.
func test_checks_path_is_the_flown_path() -> void:
	var checked := sim.check({ "type": "plan_burn", "unit": keys["Ship"], "args": BURN })
	var path: Dictionary = checked["detail"]["path"]
	assert_eq(path["place"], { "orbit_parent": keys["Planet"] })
	assert_lte(path["points"].size(), BurnSystem.PATH_POINTS + 2)
	var step: int = path["step"]
	_plan(BURN)
	for k in range(1, mini(path["points"].size(), 40)):
		sim.step(step)
		assert_eq(_ship()["pos_mm"], path["points"][k], "point %d" % k)


## Velocity Verlet keeps an orbit honest: a full turn of stepped coasting comes back to the closed
## form within metres, at the same radius.
func test_verlet_coasting_matches_the_closed_form_over_a_turn() -> void:
	var orbit: Dictionary = _ship()["orbit"]
	var period := int(orbit["period_subticks"]) / OrbitMath.SUB_TICKS
	var at := OrbitMath.state_at(orbit, GM_PLANET, 0)
	var pos: Array = at["r"]
	var vel: Array = at["v"]
	var carry: Array = [0, 0, 0]
	var vcarry: Array = [0, 0, 0]
	var worst_radius := 0
	for t in range(1, period + 1):
		var next := LowFlight.advance(sim._ctx, keys["Planet"], pos, vel, carry, vcarry)
		pos = next["pos"]
		vel = next["vel"]
		carry = next["carry"]
		vcarry = next["vcarry"]
		worst_radius = maxi(worst_radius, absi(IntMath.dist(pos, [0, 0, 0]) - 700_000_000))
	var exact := OrbitMath.position_at(orbit, period)
	var off := IntMath.dist(pos, exact)
	print("Verlet over one turn (%d ticks): %d mm from the closed form, radius within %d mm" % [period, off, worst_radius])
	assert_lt(worst_radius, 20_000, "radius held to 20 m")
	assert_lt(off, 200_000, "within 200 m after a whole turn")


func test_throttle_scales_thrust_and_has_limits() -> void:
	var full: Dictionary = sim.check({ "type": "plan_burn", "unit": keys["Ship"], "args": BURN })["detail"]
	var half_args := BURN.duplicate()
	half_args["throttle_ppm"] = 500_000
	var half := sim.check({ "type": "plan_burn", "unit": keys["Ship"], "args": half_args })
	assert_true(half["ok"], str(half))
	assert_almost_eq(int(half["detail"]["burn_ticks"]), 2 * int(full["burn_ticks"]), 3)
	var floor_ppm := BurnSystem.min_throttle_ppm(sim._ctx, BurnSystem.thruster(sim._ctx, keys["Ship"])["part"])
	assert_eq(floor_ppm, 200_000, "B29's chemical thruster")
	for bad: int in [floor_ppm - 1, 1_000_001]:
		var args := BURN.duplicate()
		args["throttle_ppm"] = bad
		assert_eq(sim.check({ "type": "plan_burn", "unit": keys["Ship"], "args": args })["reason"], "throttle_out_of_range")


func test_steering_is_checked() -> void:
	var args := BURN.duplicate()
	args["steer"] = "sideways"
	assert_eq(sim.check({ "type": "plan_burn", "unit": keys["Ship"], "args": args })["reason"], "malformed_command")
	args["steer"] = "target"
	assert_eq(sim.check({ "type": "plan_burn", "unit": keys["Ship"], "args": args })["reason"], "invalid_target",
		"target steering needs a target")


## Orbit steering pushes along the motion of the moment: a prograde burn's push is along the velocity.
func test_orbit_steering_pushes_along_the_current_velocity() -> void:
	var burn := { "dir_q30": [ONE, 0, 0], "dv_um_s": 10_000_000, "done_um_s": 0, "dv_remainder": 0,
		"flow_remainder": 0, "steer": "orbit", "prograde_um_s": 10_000_000, "normal_um_s": 0, "radial_um_s": 0 }
	var stats: Dictionary = Units.module_of(sim._state, sim._ctx.defs,
		BurnSystem.thruster(sim._ctx, keys["Ship"])["part"])["capabilities"]["thruster"]
	var at := OrbitMath.state_at(_ship()["orbit"], GM_PLANET, 500)
	var push := BurnSystem.thrust_step(sim._ctx, burn, stats, 16_000_000, [keys["Planet"], at["r"], at["v"]], 500)
	var along := OrbitMath.dot(OrbitMath.unit(push["change"]), OrbitMath.unit(at["v"]))
	assert_gt(along, ONE - 1000)


## Against the velocity relative to a target, the burn stops once that is nulled.
func test_target_retrograde_nulls_the_relative_speed() -> void:
	var other := Units.create(sim._ctx, "starter_ship", "Other", [0, 0, 0])
	var orbit := OrbitMath.make_orbit(GM_PLANET, 700_000_000, 0, [ONE, 0, 0], [0, 0, -ONE], 0, 0)
	orbit["parent"] = keys["Planet"]
	# The ship's own orbit, nudged 3 m/s faster: the relative speed starts near 3 m/s.
	var at := OrbitMath.state_at(orbit, GM_PLANET, 0)
	var faster := OrbitMath.from_state(at["r"], [at["v"][0], at["v"][1], at["v"][2] - 3_000_000], GM_PLANET, 0)
	faster["parent"] = keys["Planet"]
	sim._state["units"][other]["orbit"] = faster
	sim._ctx.index.clear()
	_plan({ "tick": 3, "prograde_um_s": 50_000_000, "normal_um_s": 0, "radial_um_s": 0, "steer": "target_retrograde",
		"target": other })
	var ended := _until("burn_done", 3000)
	assert_false(ended.is_empty(), "it ends as done, not short")
	assert_lt(ended["data"]["dv_um_s"], 10_000_000, "it stopped when nulled, well before 50 m/s")
	var seen := sim.relative(keys["Ship"], other, sim.current_tick())
	assert_lt(seen["speed_um_s"], 20_000, "within 2 cm/s of the target's motion")


## A unit falling to the ground shows the tick it lands on, and it lands then.
func test_surface_contact_tick_is_when_it_lands() -> void:
	_hover(4242, 400_000)
	var shown: int = sim.view()["units"][keys["Ship"]]["surface_contact_tick"]
	assert_gt(shown, sim.current_tick())
	var touched := _until_any(["landed", "crashed"], 2000)
	assert_false(touched.is_empty())
	assert_eq(touched["tick"], shown)


func test_surface_contact_tick_is_minus_one_high_up() -> void:
	assert_eq(sim.view()["units"][keys["Ship"]]["surface_contact_tick"], -1)


## A57: the view's orbit carries its apsides, and the next periapsis tick is where it is lowest.
func test_view_orbits_carry_their_apsides() -> void:
	var dirs := OrbitMath.directions(0, 0, 0)
	_put_in_orbit(OrbitMath.make_orbit(GM_PLANET, 900_000_000, ONE / 10, dirs[0], dirs[1], OrbitMath.TURN / 3, 0))
	var shown: Dictionary = sim.view()["units"][keys["Ship"]]["orbit"]
	assert_eq(shown["periapsis_mm"], 810_000_000)
	assert_eq(shown["apoapsis_mm"], 990_000_000)
	var peri: int = shown["next_periapsis_tick"]
	var apo: int = shown["next_apoapsis_tick"]
	assert_gt(peri, 0)
	assert_gt(apo, 0)
	var orbit: Dictionary = _ship()["orbit"]
	var r := func(t: int) -> int: return IntMath.dist(OrbitMath.position_at(orbit, t), [0, 0, 0])
	assert_lte(r.call(peri), r.call(peri - 1))
	assert_lte(r.call(peri), r.call(peri + 1))
	assert_gte(r.call(apo), r.call(apo - 1))
	assert_gte(r.call(apo), r.call(apo + 1))
	var planet: Dictionary = sim.view()["bodies"][keys["Planet"]]["orbit"]
	assert_true(planet.has("periapsis_mm"))


## A57: predict's -1 is one turn, its world points are relative to the root.
func test_predict_one_turn_with_world_points() -> void:
	var orbit: Dictionary = _ship()["orbit"]
	var period := int(orbit["period_subticks"]) / OrbitMath.SUB_TICKS
	var ahead := sim.predict(keys["Ship"], 0, -1, 100)
	assert_eq(ahead["ended"], "revolution")
	assert_eq(ahead["points"].size(), period / 100 + 1)
	var planet := RailSystem.world_mm(sim._state, "bodies", keys["Planet"])
	for axis in 3:
		assert_eq(ahead["world_points"][0][axis], ahead["points"][0][axis] + planet[axis])


func test_save_and_load_mid_burn_is_byte_exact() -> void:
	_plan(BURN)
	sim.step(40)
	assert_ne(_ship()["stepped"], 0)
	var saved := sim.to_save()
	var loaded := Sim.from_save(saved)
	sim.step(300)
	loaded.step(300)
	assert_eq(loaded.state_hash(), sim.state_hash())
