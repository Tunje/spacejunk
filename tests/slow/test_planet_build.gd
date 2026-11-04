extends GutTest
## D13: a full 600 km planet, n = 100, built the way the client builds it: on its
## own thread, with the per-cell work spread over the worker pool.

const BUDGET_MS := 15000


func test_a_full_planet_builds_off_the_main_thread_in_budget() -> void:
	var settings := PlanetMesh.settings_of({ "radius_mm": 600_000_000, "seed": 48213, "height_range_m": 6000, "sea_level_m": -400 })
	var holder := [{}]
	var thread := Thread.new()
	var started := Time.get_ticks_msec()
	thread.start(func() -> void: holder[0] = PlanetMesh.build(settings, true))
	while thread.is_alive():
		await wait_process_frames(1)
	thread.wait_to_finish()
	var took := Time.get_ticks_msec() - started
	print("PLANET n=%d cells=%d triangles=%d build_ms=%d" % [settings["n"], holder[0]["cells"], holder[0]["triangles"], took])
	assert_eq(holder[0]["cells"], 100_002)
	assert_eq(holder[0]["triangles"], 200_000)
	assert_lt(took, BUDGET_MS)
