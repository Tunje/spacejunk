extends GutTest
## Moves inside a frame under coast (task A37): a route is a straight leg at a set speed with a
## carried remainder, so it sums in closed form to the tick before it arrives, and the arrival tick
## is stepped. Each case steps one copy and coasts another over the same ticks, then compares the
## saves byte for byte and the events one for one.

const SHIP := 23
const ROCK := 2

## What capped each coast call in the last _same_both_ways, by cap name, "" for none.
var caps := {}


func _same_both_ways(stepped: Sim, coasted: Sim, ticks: int, strict: bool = true) -> int:
	stepped._strict = strict
	stepped.step(ticks)
	var stepped_events := stepped.take_events()
	var coasted_events: Array[Dictionary] = []
	var calls := 0
	var left := ticks
	caps = {}
	while left > 0:
		var done: Dictionary = coasted.coast(left)
		left -= done["ticks"]
		calls += 1
		caps[done["capped_by"]] = caps.get(done["capped_by"], 0) + 1
		coasted_events.append_array(coasted.take_events())
	gut.p("coast calls %d, capped by %s" % [calls, str(caps)])
	assert_eq(coasted.current_tick(), stepped.current_tick())
	assert_eq(coasted.to_save(), stepped.to_save(), "the same state, byte for byte")
	assert_eq(coasted_events, stepped_events, "the same events on the same ticks")
	if strict:
		assert_eq(stepped.ledger()["violations"], PackedStringArray())
	return calls


func _copy(sim: Sim) -> Sim:
	var copy := Sim.from_save(sim.to_save())
	assert_not_null(copy, Sim.last_error())
	return copy


## The reference ship, undocked and idle beside the station.
func _undocked() -> Sim:
	var sim := Sim.new_game("reference", 12345)
	sim.submit({ "type": "undock", "unit": SHIP, "args": {} })
	sim.step(110)
	sim.take_events()
	assert_true(sim._state["units"][SHIP]["dock"].is_empty(), "undocked")
	return sim


func test_the_route_horizon_stops_one_tick_short_of_arrival() -> void:
	var route := { "length_mm": 1_000, "progress_mm": 0, "speed_mm_s": 30, "speed_remainder": 0 }
	# 3 mm a tick: 333 ticks leave it at 999 mm, and the 334th arrives.
	assert_eq(CargoSystem.route_horizon(route), 333)
	route["speed_remainder"] = 7
	# 30 k + 7 < 10,000 for k up to 333.
	assert_eq(CargoSystem.route_horizon(route), 333)
	route["progress_mm"] = 999
	route["speed_remainder"] = 0
	route["speed_mm_s"] = 3
	assert_eq(CargoSystem.route_horizon(route), 3, "at 0.3 mm a tick, the 4th tick covers the last 1 mm")
	route["speed_remainder"] = 9
	assert_eq(CargoSystem.route_horizon(route), 0, "the next tick arrives")
	route["speed_mm_s"] = 0
	assert_eq(CargoSystem.route_horizon(route), SimSystem.NO_LIMIT, "a leg at no speed never arrives")


func test_a_move_coasts_to_its_arrival() -> void:
	var stepped := _undocked()
	stepped.submit({ "type": "move_to", "unit": SHIP, "args": { "target": ROCK } })
	stepped.step()
	stepped.take_events()
	assert_false(stepped._state["units"][SHIP]["route"].is_empty(), "on its way")
	var eta: int = stepped._state["units"][SHIP]["route"]["eta_tick"]
	var coasted := _copy(stepped)
	_same_both_ways(stepped, coasted, eta - stepped.current_tick() + 20)
	assert_eq(stepped._state["units"][SHIP]["at_target"], ROCK, "arrived")
	assert_eq(caps.get("moving_in_frame", 0), 0, "a route is coasted, not stepped")


## The new start's probe flies between rocks in its cluster while the cluster passes the edge of
## the moon's shadow (A35's case), so the shadow bound counts the route's speed with the frame's.
func test_moves_between_rocks_in_the_cluster_coast_through_a_shadow_edge() -> void:
	var stepped := Sim.new_game("new_start", 1)
	while stepped.current_tick() < 125_000:
		stepped.coast(125_000 - stepped.current_tick())
	stepped.take_events()
	var probe := 13
	var calls := 0
	for rock: int in [4, 8]:
		stepped.submit({ "type": "move_to", "unit": probe, "args": { "target": rock } })
		var coasted := _copy(stepped)
		calls += _same_both_ways(stepped, coasted, 3_000, false)
		assert_eq(stepped._state["units"][probe]["at_target"], rock, "arrived at %d" % rock)
		assert_eq(caps.get("moving_in_frame", 0), 0)
	assert_lt(calls, 60, "the legs and the shadow edge took a few calls each")
