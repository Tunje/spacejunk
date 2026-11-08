extends GutTest
## The relative-state tools (task A54, real_orbits.md section 3.5): Sim.relative, closest approach,
## plane and phase, the stop burn, the docking readout, predict through planned burns, and
## plan_burn's lead and closest approach.

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const MU_M3 := 3.5316e12
const AU_MM := 149_597_870_700_000
const A_MM := 700_000_000
const ONE := OrbitMath.ONE
const PROPELLANT_G := 12_000_000

var sim: Sim
var keys := {}


func before_each() -> void:
	var defs := DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM } },
			{ "key": "rock", "name": "Rock", "kind": "asteroid", "frame": "home", "pos_mm": [30_000_000, 0, 0],
				"radius_mm": 300_000, "visual_seed": 3, "deposits": [] },
		],
		"frames": [{ "key": "home", "name": "Home", "radius_mm": 60_000_000,
			"orbit": { "parent": "planet", "a_mm": 900_000_000, "mean_anomaly_mdeg": 40_000 } }],
		"units": [
			{ "key": "ship", "template": "starter_ship", "name": "Ship", "pos_mm": [0, 0, 0],
				"inventory": [{ "item": "propellant", "grams": PROPELLANT_G }], "dock": null },
			{ "key": "other", "template": "starter_ship", "name": "Other", "pos_mm": [0, 0, 0],
				"inventory": [{ "item": "propellant", "grams": PROPELLANT_G }], "dock": null },
			{ "key": "drone", "template": "mining_drone", "name": "Drone", "pos_mm": [1_000_000, 0, 0],
				"frame": "home", "inventory": [], "dock": null },
		],
	}, {}), "")
	sim._strict = true
	keys = {}
	for table: String in ["bodies", "frames", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	_orbit("Ship", _circle(A_MM, 0, 0))
	_orbit("Other", _circle(A_MM, 0, OrbitMath.TURN / 18))


func _circle(a_mm: int, inclination: int, m0: int) -> Dictionary:
	var dirs := OrbitMath.directions(inclination, 0, 0)
	return OrbitMath.make_orbit(GM_PLANET, a_mm, 0, dirs[0], dirs[1], m0, 0)


func _orbit(name: String, orbit: Dictionary) -> void:
	orbit["parent"] = keys["Planet"]
	var unit: Dictionary = sim._state["units"][keys[name]]
	unit["orbit"] = orbit
	unit["frame"] = 0
	unit["pos_mm"] = OrbitMath.position_at(orbit, sim.current_tick())
	sim._ctx.index.clear()


func _period_ticks(a_mm: int) -> int:
	return OrbitMath.period_sub(GM_PLANET, a_mm) / OrbitMath.SUB_TICKS


func test_refusals() -> void:
	assert_eq(sim.relative(999_999, keys["Other"], 0)["reason"], "unknown_unit")
	assert_eq(sim.relative(keys["Ship"], keys["Ship"], 0)["reason"], "invalid_target")
	assert_eq(sim.relative(keys["Ship"], 999_999, 0)["reason"], "invalid_target")


## Same circle, 20 degrees apart: the chord, no closing speed, and the phase.
func test_same_circle_twenty_degrees_ahead() -> void:
	var seen := sim.relative(keys["Ship"], keys["Other"], 0)
	assert_eq(seen["parent"], keys["Planet"])
	var chord := 2.0 * A_MM * sin(deg_to_rad(10.0))
	assert_almost_eq(float(seen["range_mm"]), chord, 2.0, "the chord")
	# Both move at the same speed; the relative velocity is the turn of a fixed chord, all lateral.
	var v := sqrt(MU_M3 / (A_MM / 1000.0)) * 1_000_000.0
	assert_almost_eq(float(seen["speed_um_s"]), 2.0 * v * sin(deg_to_rad(10.0)), 20.0)
	assert_almost_eq(seen["closing_um_s"], 0, 20)
	assert_almost_eq(float(seen["lateral_um_s"]), float(seen["speed_um_s"]), 20.0)
	assert_almost_eq(seen["phase_mdeg"], 20_000, 2)
	assert_eq(seen["plane"]["inclination_mdeg"], 0)
	assert_eq(seen["plane"]["ascending_tick"], -1, "one plane: no node")
	assert_eq(seen["window"], {}, "same size: no Hohmann window")


func test_closing_and_lateral_make_up_the_speed() -> void:
	_orbit("Other", OrbitMath.make_orbit(GM_PLANET, 720_000_000, ONE / 20, [ONE, 0, 0], [0, 0, -ONE],
		OrbitMath.TURN / 30, 0))
	for tick in [0, 1234, 9876]:
		var seen := sim.relative(keys["Ship"], keys["Other"], tick)
		var total := sqrt(float(seen["closing_um_s"]) ** 2 + float(seen["lateral_um_s"]) ** 2)
		assert_almost_eq(total, float(seen["speed_um_s"]), 3.0)
		# Closing is the rate the range shrinks: compare over one tick either side.
		var before: int = sim.relative(keys["Ship"], keys["Other"], tick - 1)["range_mm"]
		var after: int = sim.relative(keys["Ship"], keys["Other"], tick + 1)["range_mm"]
		var shrink_um_s := (before - after) * 1000.0 * Sim.TICKS_PER_SECOND / 2.0
		assert_almost_eq(shrink_um_s, float(seen["closing_um_s"]), absf(shrink_um_s) * 0.01 + 5000.0)


## Two rings 1 km apart, the higher 0.1 degree ahead: the lower one catches it up where the phase
## closes, and passes 1 km beneath.
func test_closest_approach_of_two_rings_is_where_the_phase_closes() -> void:
	_orbit("Other", _circle(A_MM + 1_000_000, 0, OrbitMath.TURN / 3600))
	var n1 := sqrt(MU_M3 / pow(A_MM / 1000.0, 3))
	var n2 := sqrt(MU_M3 / pow((A_MM + 1_000_000) / 1000.0, 3))
	var expected_ticks := deg_to_rad(0.1) / (n1 - n2) * Sim.TICKS_PER_SECOND
	var seen := sim.relative(keys["Ship"], keys["Other"], 0)
	assert_almost_eq(float(seen["closest"]["tick"]), expected_ticks, expected_ticks * 0.01)
	assert_almost_eq(seen["closest"]["range_mm"], 1_000_000, 2_000)


## The sampled and refined search finds the same minimum as checking every tick.
func test_closest_approach_matches_every_tick() -> void:
	# Crossing planes, the same size, nearly at the crossing: a fast pass.
	_orbit("Other", _circle(A_MM, OrbitMath.TURN / 36, (OrbitMath.TURN - OrbitMath.TURN / 200) & OrbitMath.ANGLE_MASK))
	var horizon := 4000
	var seen := sim.relative(keys["Ship"], keys["Other"], 0, horizon)
	var mine := Relative.unit_track(sim._ctx, keys["Ship"])
	var theirs := Relative.unit_track(sim._ctx, keys["Other"])
	var best := -1
	var best_tick := -1
	for t in horizon + 1:
		var r := Relative.range_at(sim._ctx, mine, theirs, t)
		if best < 0 or r < best:
			best = r
			best_tick = t
	assert_eq(seen["closest"]["range_mm"], best)
	assert_eq(seen["closest"]["tick"], best_tick)
	assert_gt(seen["closest"]["speed_um_s"], 100_000, "a fast pass, not a drift")


func test_plane_inclination_and_nodes() -> void:
	_orbit("Other", _circle(A_MM, OrbitMath.TURN / 36, 0))
	# The ship starts on the line of nodes, so look from a little later.
	var seen := sim.relative(keys["Ship"], keys["Other"], 100)
	assert_almost_eq(seen["plane"]["inclination_mdeg"], 10_000, 3)
	var up: int = seen["plane"]["ascending_tick"]
	var down: int = seen["plane"]["descending_tick"]
	assert_gt(up, 0)
	assert_gt(down, 0)
	var other_normal := Relative.normal_of(sim._state["units"][keys["Other"]]["orbit"])
	var orbit: Dictionary = sim._state["units"][keys["Ship"]]["orbit"]
	assert_lt(OrbitMath.dot(OrbitMath.position_at(orbit, up - 1), other_normal), 0, "below before ascending")
	assert_gte(OrbitMath.dot(OrbitMath.position_at(orbit, up), other_normal), 0, "above at it")
	assert_gte(OrbitMath.dot(OrbitMath.position_at(orbit, down - 1), other_normal), 0, "above before descending")
	assert_lt(OrbitMath.dot(OrbitMath.position_at(orbit, down), other_normal), 0, "below at it")
	assert_almost_eq(absi(up - down), _period_ticks(A_MM) / 2, 2, "half a turn apart")


func test_window_is_the_hohmann_geometry() -> void:
	_orbit("Other", _circle(800_000_000, 0, OrbitMath.TURN / 18))
	var seen := sim.relative(keys["Ship"], keys["Other"], 100)
	var mine: Dictionary = sim._state["units"][keys["Ship"]]["orbit"]
	var theirs: Dictionary = sim._state["units"][keys["Other"]]["orbit"]
	var plan := Transfer._hohmann(sim._ctx, mine, theirs, GM_PLANET, 100)
	assert_eq(seen["window"], { "depart_tick": plan["depart_tick"], "ticks": plan["ticks"] })


func test_stop_burn_at_current_thrust_and_mass() -> void:
	_orbit("Other", _circle(720_000_000, 0, 0))
	var seen := sim.relative(keys["Ship"], keys["Other"], 0)
	var mass := Units.unit_mass(sim._state, sim._ctx.defs, keys["Ship"])
	var found := BurnSystem.thruster(sim._ctx, keys["Ship"])
	var speed: int = seen["speed_um_s"]
	var ticks := IntMath.mul_div_ceil(speed, mass * Sim.TICKS_PER_SECOND, found["thrust_n"] * 1_000_000_000)
	assert_eq(seen["stop"], { "burn_ticks": ticks, "lead_ticks": ticks / 2,
		"propellant_g": OrbitMath.burn_g(mass, speed, found["exhaust_mm_s"]) })


## A unit in a frame against one on an orbit, measured round the planet, and a body in that frame
## measured in the frame itself.
func test_places_lift_to_the_nearest_shared_one() -> void:
	sim.step()
	var seen := sim.relative(keys["Ship"], keys["Drone"], sim.current_tick())
	assert_eq(seen["parent"], keys["Planet"])
	var expected: Array = []
	var a := RailSystem.world_mm(sim._state, "units", keys["Ship"])
	var b := RailSystem.world_mm(sim._state, "units", keys["Drone"])
	for axis in 3:
		expected.append(b[axis] - a[axis])
	assert_eq(seen["rel_pos_mm"], expected, "the same as world positions, exactly")
	var near := sim.relative(keys["Drone"], keys["Rock"], sim.current_tick())
	assert_eq(near["parent"], keys["Home"])
	assert_eq(near["rel_pos_mm"], [29_000_000, 0, 0])
	assert_eq(near["speed_um_s"], 0)


## The capture limits are the stricter port's (B29): the drone's small port, 50 mm and 0.05 m/s.
## Until stage 4 the reason is the dock step's own: here the drone is not at the ship.
func test_dock_readout_takes_the_stricter_port() -> void:
	var seen := sim.relative(keys["Drone"], keys["Ship"], 0)
	assert_eq(seen["dock"]["capture_range_mm"], 50)
	assert_eq(seen["dock"]["capture_speed_um_s"], 50_000)
	assert_eq(seen["dock"]["range_mm"], seen["range_mm"])
	assert_eq(seen["dock"]["reason"], "out_of_range")
	assert_eq(sim.relative(keys["Ship"], keys["Rock"], 0)["dock"], {}, "no docking with a rock")


func test_a_docked_unit_is_measured_as_its_host() -> void:
	var drone: Dictionary = sim._state["units"][keys["Drone"]]
	drone["dock"] = { "target_unit": keys["Ship"], "port": 0, "target_port": 0 }
	var seen := sim.relative(keys["Drone"], keys["Other"], 0)
	var host := sim.relative(keys["Ship"], keys["Other"], 0)
	assert_eq(seen["rel_pos_mm"], host["rel_pos_mm"])
	assert_eq(seen["rel_vel_um_s"], host["rel_vel_um_s"])


## predict with_burns flies the planned burn as the simulation does: every point is where the
## unit really is.
func test_predict_with_burns_is_the_flown_path() -> void:
	sim.submit({ "type": "plan_burn", "unit": keys["Ship"], "args": { "tick": 20,
		"prograde_um_s": 30_000_000, "normal_um_s": 2_000_000, "radial_um_s": 0 } })
	sim.step()
	assert_false(sim.predict(keys["Ship"], 1, 10, 1).has("burns"), "the default is unchanged")
	var ahead := sim.predict(keys["Ship"], 1, 600, 1, true)
	assert_eq(ahead["burns"].size(), 1)
	assert_eq(ahead["burns"][0]["start_tick"], 20)
	var unit: Dictionary = sim._state["units"][keys["Ship"]]
	var ended := -1
	for t in range(2, 601):
		sim.step()
		for event in sim.take_events():
			if event["type"] == "burn_done":
				ended = t
		assert_eq(unit["pos_mm"], ahead["points"][t - 1], "tick %d" % t)
	assert_eq(ahead["burns"][0]["end_tick"], ended)
	var plain := sim.predict(keys["Ship"], 1, 600, 1)
	assert_ne(plain["points"][599], ahead["points"][599], "the burn changed the path")


func test_closest_planned_flies_the_planned_burns() -> void:
	_orbit("Other", _circle(720_000_000, 0, OrbitMath.TURN / 100))
	sim.submit({ "type": "plan_burn", "unit": keys["Ship"], "args": { "tick": 5,
		"prograde_um_s": 5_000_000, "normal_um_s": 0, "radial_um_s": 0 } })
	sim.step()
	var seen := sim.relative(keys["Ship"], keys["Other"], 1)
	assert_false(seen["closest_planned"].is_empty())
	assert_ne(seen["closest_planned"], seen["closest"])
	var flown := Relative.planned_track(sim._ctx, keys["Ship"], [])
	var at: int = seen["closest_planned"]["tick"]
	assert_eq(seen["closest_planned"]["range_mm"], Relative.range_at(sim._ctx, flown["track"],
		Relative.unit_track(sim._ctx, keys["Other"]), at))
	_orbit("Ship", _circle(A_MM, 0, 0))
	sim._state["units"][keys["Ship"]]["burns"] = []
	assert_eq(sim.relative(keys["Ship"], keys["Other"], 1)["closest_planned"], {}, "none planned")


func test_plan_burn_check_gives_lead_and_closest_to_a_target() -> void:
	_orbit("Other", _circle(720_000_000, 0, OrbitMath.TURN / 100))
	var burn := { "tick": 5, "prograde_um_s": 5_000_000, "normal_um_s": 0, "radial_um_s": 0 }
	var plain := sim.check({ "type": "plan_burn", "unit": keys["Ship"], "args": burn })
	assert_true(plain["ok"])
	assert_eq(plain["detail"]["lead_ticks"], plain["detail"]["burn_ticks"] / 2)
	assert_false(plain["detail"].has("closest"))
	var aimed := burn.duplicate()
	aimed["target"] = keys["Other"]
	var checked := sim.check({ "type": "plan_burn", "unit": keys["Ship"], "args": aimed })
	assert_true(checked["ok"])
	var closest: Dictionary = checked["detail"]["closest"]
	assert_gte(closest["tick"], 5)
	# The same as relative's planned closest once the burn is placed, over the same horizon.
	sim.submit({ "type": "plan_burn", "unit": keys["Ship"], "args": burn })
	sim.step()
	var flown := Relative.planned_track(sim._ctx, keys["Ship"], [])
	assert_eq(closest["range_mm"], Relative.range_at(sim._ctx, flown["track"],
		Relative.unit_track(sim._ctx, keys["Other"]), closest["tick"]))
	var wrong := burn.duplicate()
	wrong["target"] = 999_999
	assert_eq(sim.check({ "type": "plan_burn", "unit": keys["Ship"], "args": wrong })["reason"], "invalid_target")


func test_relative_changes_nothing() -> void:
	var before := sim.state_hash()
	sim.relative(keys["Ship"], keys["Other"], 0)
	sim.relative(keys["Drone"], keys["Ship"], 0)
	assert_eq(sim.state_hash(), before)
