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
## arc that leaves at once arrives sooner. Each quote shows the other.
func test_cheap_waits_on_the_window_and_fast_leaves_at_once() -> void:
	var cheap := sim.quote(keys["Ship"], keys["Pebble"], 0)
	var fast := sim.quote(keys["Ship"], keys["Pebble"], 0, "fast")
	print("LAMBERT to the pebble: window %d kg arriving at %d; at once %d kg arriving at %d" % [
		cheap["cost_g"] / 1000, cheap["arrive_tick"], fast["cost_g"] / 1000, fast["arrive_tick"]])
	assert_false(cheap.get("timed", false), "the cheap plan is the window's")
	assert_true(fast.get("timed", false), "the fast plan leaves at once on an arc")
	assert_eq(fast["depart_tick"], 0)
	assert_lt(fast["arrive_tick"], cheap["arrive_tick"])
	assert_gt(fast["cost_g"], cheap["cost_g"])
	assert_eq(cheap["other"], { "arrive_tick": fast["arrive_tick"], "cost_g": fast["cost_g"] })
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
