extends "res://tests/sim/industry/coast_fixture.gd"
## Mining cycles coasted lap after lap (C17, C19, C20): moves, docking, transfers and mining all in
## closed form, each byte-equal to stepping.


## A drone fitted as tests/sim/autonomy/test_cycles.gd fits it, on a cycle to a near rock.
func test_a_mining_cycle_coasts_exactly() -> void:
	var stepped := _mining_cycle({})
	var coasted := _copy(stepped)
	# Was 2,004 calls: docking, undocking and transfers now coast too (C20), and moves (A37).
	assert_lt(_same_both_ways(stepped, coasted, 6_000), 60, "laps are skipped, not stepped")
	assert_gt(stepped._state["units"][STATION]["inventory"].get("hematite", 0), 0, "a lap unloaded ore")


## C19: each lap of a cycle mines the step's amount and no more.
func test_a_cycle_mines_its_amount_each_lap_and_coasts_exactly() -> void:
	var stepped := _mining_cycle({ "grams": 30_000 })
	var coasted := _copy(stepped)
	assert_lt(_same_both_ways(stepped, coasted, 6_000), 150, "short laps, each a few calls")
	var unloaded: int = stepped._state["units"][STATION]["inventory"].get("hematite", 0)
	assert_gt(unloaded, 30_000, "more than one lap")
	assert_eq(unloaded % 30_000, 0, "every lap unloaded exactly the amount: %d" % unloaded)


func test_a_cycle_with_a_bad_amount_is_refused() -> void:
	var sim := _mining_cycle({ "grams": 0 }, false)
	var drone: int = sim._state["units"].keys().max()
	assert_eq(sim._state["units"][drone]["task"], 0, "no cycle set")
