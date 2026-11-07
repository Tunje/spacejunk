extends GutTest
## Leaving a frame and coasting at once (task A50). Right after a hand burn out of the new start's
## cluster the probe is still within the frame's join reach, where BurnSystem's join bound is 0, so
## the coast used to step it tick by tick until it was clear: 300 to 1,300 ticks. Each coming tick is
## now tried by _try_join's own test instead. Soak seed 17 (coast_soak.gd, A49) burns out and is
## ordered home; it must match stepping and spend no calls near the boundary.

const CoastSoak := preload("res://tests/sim/kernel/coast_soak.gd")


func test_leaving_the_cluster_coasts_past_its_join_reach() -> void:
	var result: Dictionary = CoastSoak.run_seed(17, 8_000)
	gut.p("seed 17: %d coast calls, capped by %s" % [result["calls"], str(result["caps"])])
	assert_true(result["ok"], result["message"])
	assert_eq(result["caps"].get("near_a_boundary", 0), 0, "no ticks stepped at the join reach")


## A unit put inside a frame's join distance, moving with it, joins on the next tick: the walk must
## stop before that tick and coasting must still match stepping.
func test_a_unit_about_to_join_is_stepped_into_the_frame() -> void:
	var world: GutTest = load("res://tests/sim/networks/test_transfers.gd").new()
	var stepped: Sim = world._build()
	var keys: Dictionary = world.keys
	world.free()
	var frame: Dictionary = stepped._state["frames"][keys["Home"]]
	var unit: Dictionary = stepped._state["units"][keys["Ship"]]
	var gm: int = stepped._state["bodies"][keys["Planet"]]["gm"]
	# On Home's own orbit, a little behind its centre and well within its join distance.
	var orbit: Dictionary = frame["orbit"].duplicate(true)
	orbit["m0_angle"] = (int(orbit["m0_angle"]) - OrbitMath.TURN / 10_000_000) & OrbitMath.ANGLE_MASK
	unit["orbit"] = orbit
	unit["frame"] = 0
	unit["pos_mm"] = OrbitMath.position_at(orbit, stepped.current_tick())
	unit["vel_um_s"] = [0, 0, 0]
	stepped._ctx.index.clear()
	var offset := IntMath.dist(unit["pos_mm"], OrbitMath.position_at(frame["orbit"], stepped.current_tick()))
	assert_lt(offset, int(frame["radius_mm"]) + BurnSystem.join_margin_mm(stepped._ctx, frame), "inside the join distance")
	var coasted := Sim.from_save(stepped.to_save())
	stepped.step(50)
	while coasted.current_tick() < 50:
		coasted.coast(50 - coasted.current_tick())
	assert_eq(stepped._state["units"][keys["Ship"]]["frame"], keys["Home"], "joined")
	assert_eq(coasted.to_save(), stepped.to_save(), "coasted the same, byte for byte")
