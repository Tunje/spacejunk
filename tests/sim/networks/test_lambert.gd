extends GutTest
## Timed trips on Lambert arcs (task A47, stage one: one plane, near-circular orbits, one parent).
## A trip can leave at once instead of waiting for its window, on an arc found by shooting with the
## rails' own integer propagation. The world is test_transfers.gd's: Home at 700 km holds the ship,
## Ahead in the same ring 20 degrees on holds a pebble, and Far at 900 km holds a rock.

const Transfers := preload("res://tests/sim/networks/test_transfers.gd")

var sim: Sim
var keys := {}
var _world: GutTest


func before_each() -> void:
	_world = Transfers.new()
	sim = _world._build()
	keys = _world.keys


func after_each() -> void:
	_world.free()


func _ship() -> Dictionary:
	return sim._state["units"][keys["Ship"]]


func test_the_solver_hits_the_target_where_it_will_be() -> void:
	var gm: int = sim._state["bodies"][keys["Planet"]]["gm"]
	var mine := Transfer.unit_orbit(sim._ctx, keys["Ship"])
	var theirs := Transfer.target_orbit(sim._ctx, keys["Pebble"])
	var now := OrbitMath.state_at(mine, gm, 0)
	var normal := OrbitMath.unit(OrbitMath.cross(mine["p_q30"], mine["q_q30"]))
	for ticks: int in [600, 1200, 1800, 2600]:
		var hit := Lambert.solve(gm, now["r"], now["v"], theirs, 0, ticks, normal)
		assert_false(hit.is_empty(), "an arc in %d ticks" % ticks)
		if hit.is_empty():
			continue
		var there := OrbitMath.position_at(hit["orbit"], ticks)
		var miss := IntMath.dist(there, OrbitMath.position_at(theirs, ticks))
		assert_lte(miss, Lambert.HIT_MM, "the arc's own integer orbit meets the target: %d mm off" % miss)


## The pebble is 20 degrees ahead in the ship's own ring. Waiting on a phasing orbit is cheaper; an
## arc that leaves at once arrives sooner. Cheap is the window's plan and searches no arc unless
## asked to compare; fast plans both. Each shows the other, the arc marked timed.
func test_cheap_waits_on_the_window_and_fast_leaves_at_once() -> void:
	var plain := sim.quote(keys["Ship"], keys["Pebble"], 0)
	assert_false(plain.has("other"), "a cheap quote searches no arc")
	var cheap := sim.quote(keys["Ship"], keys["Pebble"], 0, "cheap", true)
	assert_eq(cheap["arrive_tick"], plain["arrive_tick"], "comparing doesn't change the cheap plan")
	var fast := sim.quote(keys["Ship"], keys["Pebble"], 0, "fast")
	print("LAMBERT to the pebble: window %d kg arriving at %d; at once %d kg arriving at %d" % [
		cheap["cost_g"] / 1000, cheap["arrive_tick"], fast["cost_g"] / 1000, fast["arrive_tick"]])
	assert_false(cheap.get("timed", false), "the cheap plan is the window's")
	assert_true(fast.get("timed", false), "the fast plan leaves at once on an arc")
	assert_eq(fast["depart_tick"], 0)
	assert_lt(fast["arrive_tick"], cheap["arrive_tick"])
	assert_gt(fast["cost_g"], cheap["cost_g"])
	assert_eq(cheap["other"], { "arrive_tick": fast["arrive_tick"], "cost_g": fast["cost_g"], "timed": true })
	assert_eq(fast["other"], { "arrive_tick": cheap["arrive_tick"], "cost_g": cheap["cost_g"] })


func test_a_timed_trip_flies_arrives_and_pays_its_quote() -> void:
	sim._strict = true
	var fast := sim.quote(keys["Ship"], keys["Pebble"], 1, "fast")
	assert_true(fast.get("timed", false), str(fast))
	sim.submit({ "type": "move_to", "unit": keys["Ship"], "args": { "target": keys["Pebble"], "prefer": "fast" } })
	var before: int = _ship()["inventory"]["propellant"]
	sim.step(fast["arrive_tick"] + 3)
	assert_eq(_ship()["frame"], keys["Ahead"], "arrived in the pebble's frame")
	assert_eq(_ship()["at_target"], keys["Pebble"])
	assert_eq(before - int(_ship()["inventory"]["propellant"]), fast["cost_g"], "paid what was quoted")
	var ledger := sim.ledger()
	assert_eq(ledger["matter"]["total_g"], ledger["matter"]["start_g"])
	assert_eq(ledger["violations"], PackedStringArray())


func test_a_timed_trip_saves_and_coasts_exactly() -> void:
	var fast := sim.quote(keys["Ship"], keys["Pebble"], 1, "fast")
	sim.submit({ "type": "move_to", "unit": keys["Ship"], "args": { "target": keys["Pebble"], "prefer": "fast" } })
	var coasted := Sim.from_save(sim.to_save())
	var ticks: int = fast["arrive_tick"] + 5
	var mid: int = fast["arrive_tick"] / 2
	sim.step(mid)
	assert_false(_ship()["transfer"].is_empty(), "under way at the save")
	var loaded := Sim.from_save(sim.to_save())
	assert_eq(loaded.to_save(), sim.to_save(), "byte-exact mid-trip")
	sim.step(ticks - mid)
	loaded.step(ticks - mid)
	assert_eq(loaded.to_save(), sim.to_save(), "the same play after the load")
	while coasted.current_tick() < ticks:
		coasted.coast(ticks - coasted.current_tick())
	assert_eq(coasted.to_save(), sim.to_save(), "coasted the same, byte for byte")


## A49: from an eccentric orbit no window can be worked out, so cheap and fast alike leave at once on
## an arc. B's case: the new start's probe burns 20 m/s retrograde out of its cluster, onto an orbit
## of eccentricity about 0.45 round Frost, and is ordered home. It used to be unsupported_orbit.
func test_from_an_eccentric_orbit_a_move_home_leaves_at_once_and_arrives() -> void:
	var bot := NewStartBot.new()
	bot.sim = Sim.new_game("new_start", NewStartBot.SEED)
	bot._command("plan_burn", NewStartBot.PROBE, { "tick": 1, "prograde_um_s": -20_000_000, "normal_um_s": 0, "radial_um_s": 0 })
	bot._until("burn_done", NewStartBot.PROBE, 1000)
	var game := bot.sim
	var probe: Dictionary = game._state["units"][NewStartBot.PROBE]
	assert_gt(probe["orbit"]["e_q30"], Transfer.MAX_E_Q30 * 10, "well off a circle")
	var started := Time.get_ticks_usec()
	var cheap := game.quote(NewStartBot.PROBE, NewStartBot.RED_ROCK, game.current_tick())
	var cheap_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("LAMBERT home from e %.2f: %d kg, %.1f h, a cheap quote %.1f ms" % [float(probe["orbit"]["e_q30"]) / OrbitMath.ONE,
		cheap.get("cost_g", 0) / 1000, (cheap.get("arrive_tick", 0) - game.current_tick()) / 36_000.0, cheap_ms])
	assert_true(cheap.get("timed", false), "an arc: %s" % str(cheap))
	assert_eq(cheap["depart_tick"], game.current_tick())
	var before: int = probe["inventory"]["propellant"]
	game.submit({ "type": "move_to", "unit": NewStartBot.PROBE, "args": { "target": NewStartBot.RED_ROCK } })
	# The arc is long, so it is coasted, which leaves what stepping does (A33).
	var end: int = cheap["arrive_tick"] + 5
	var mid: int = (game.current_tick() + end) / 2
	while game.current_tick() < mid:
		game.coast(mid - game.current_tick())
	var loaded := Sim.from_save(game.to_save())
	assert_eq(loaded.to_save(), game.to_save(), "byte-exact mid-arc")
	for sim_copy: Sim in [game, loaded]:
		while sim_copy.current_tick() < end:
			sim_copy.coast(end - sim_copy.current_tick())
	assert_eq(loaded.to_save(), game.to_save(), "the same flight after the load")
	assert_eq(probe["frame"], 12, "home in the cluster")
	assert_eq(before - int(probe["inventory"]["propellant"]), cheap["cost_g"], "paid what was quoted")


## A49: between planes the arc's plane is the one through the unit now and the target at arrival,
## and it still hits. test_plane_change.gd's tilted world, 10 degrees, from Home to Far's rock.
func test_an_arc_between_planes_hits_the_target() -> void:
	var tilted: GutTest = load("res://tests/sim/networks/test_plane_change.gd").new()
	var world: Sim = tilted._build(10_000)
	var ship: int = tilted.keys["Ship"]
	var mine := Transfer.unit_orbit(world._ctx, ship)
	var gm: int = world._state["bodies"][tilted.keys["Planet"]]["gm"]
	# Many arcs on this small, fast planet dip below its surface and are rightly refused, so look
	# over a few starts and both tilted targets for one that stays up.
	var plan := {}
	var theirs := {}
	for target: String in ["Rock", "Pebble"]:
		for start: int in [0, 300, 600, 900, 1200, 1500]:
			theirs = Transfer.target_orbit(world._ctx, tilted.keys[target])
			plan = Transfer._timed_plan(mine, theirs, tilted.keys[target], gm, Units.unit_mass(world._state, world._ctx.defs, ship),
				start, BurnSystem.thruster(world._ctx, ship), world._state["bodies"][tilted.keys["Planet"]], Transfer.NO_WINDOW)
			if plan.get("timed", false):
				break
		if plan.get("timed", false):
			break
	tilted.free()
	assert_true(plan.get("timed", false), str(plan))
	if not plan.get("timed", false):
		return
	var arc: Dictionary = plan["legs"][0]["orbit"]
	var own := OrbitMath.unit(OrbitMath.cross(mine["p_q30"], mine["q_q30"]))
	var arcs := OrbitMath.unit(OrbitMath.cross(arc["p_q30"], arc["q_q30"]))
	assert_lt(OrbitMath.dot(own, arcs), Transfer.MIN_COPLANAR_Q30, "the arc leaves the ship's plane")
	var miss := IntMath.dist(OrbitMath.position_at(arc, plan["arrive_tick"]), OrbitMath.position_at(theirs, plan["arrive_tick"]))
	assert_lte(miss, Lambert.HIT_MM, "and meets the tilted frame: %d mm off" % miss)
