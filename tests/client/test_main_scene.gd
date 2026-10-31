extends GutTest
## Runs the real scene for a few frames, which load() alone does not do.


func test_scene_starts_and_ticks() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var bridge: SimBridge = main.get_node("Bridge")
	assert_not_null(bridge.sim, "backend started")
	bridge.advance(0.5)
	assert_gt(bridge.current_view["tick"], 0)
	await wait_process_frames(2)
	assert_ne(main.get_node("Overlay/TimeControls")._clock.text, "")
