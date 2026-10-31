extends GutTest
## Runs the real scene on the real Sim and the reference scenario.

var main: Node
var bridge: SimBridge
var view: LocalView


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = "reference"
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	view = main.get_node("LocalView")


func test_the_backend_is_the_real_sim() -> void:
	assert_true(bridge.sim is Sim)


func test_every_real_entity_gets_a_node() -> void:
	assert_gt(bridge.current_view["units"].size(), 0)
	assert_eq(view.crafts.size(), bridge.current_view["units"].size())
	assert_eq(view.bodies.size(), bridge.current_view["bodies"].size())


func test_every_real_part_is_placed() -> void:
	var state: Dictionary = bridge.current_view
	for id: int in state["units"]:
		var parts := InspectText.flatten(state["units"][id]["parts"])
		assert_eq(view.crafts[id].part_transforms.size(), parts.size())


func test_the_scene_refreshes_and_ticks_without_errors() -> void:
	bridge.set_paused(false)
	bridge.advance(0.5)
	bridge.set_paused(true)
	view.refresh(0.016)
	assert_gt(bridge.current_view["tick"], 0)
	await wait_process_frames(2)


func test_panels_read_the_real_view() -> void:
	assert_ne(main.inspection_panel._title.text, "")
	assert_gt(main.inspection_panel.part_line_count(), 0)


func test_the_map_opens_on_real_data() -> void:
	main.toggle_map()
	assert_eq(main.system_map.entries.size(), bridge.current_view["units"].size() + bridge.current_view["bodies"].size())


func test_the_field_reaches_home_and_every_real_rock() -> void:
	var state: Dictionary = bridge.current_view
	var clear := AsteroidField.keep_clear(state, view.field.anchor_mm)
	var half_width := AsteroidField.half_width_for(clear)
	for entry: Dictionary in clear:
		assert_lt((entry["at_m"] as Vector3).length(), half_width)
	assert_lte(view.field.instance_total, AsteroidField.MAX_COUNT)


func test_the_first_view_faces_the_star() -> void:
	var state: Dictionary = bridge.current_view
	var to_sun: Vector3 = -view.sun.global_basis.z
	for id: int in state["bodies"]:
		if state["bodies"][id]["kind"] == "star":
			var camera_side: Vector3 = (view.camera.global_position - view.camera.pivot).normalized()
			assert_gt(camera_side.dot(-to_sun), 0.6, "camera is on the lit side")


func test_rocks_cast_no_shadow_so_none_can_eclipse_a_base() -> void:
	for id: int in view.bodies:
		var mesh: MeshInstance3D = view.bodies[id].get_child(0)
		assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_commands_the_kernel_lacks_read_cleanly() -> void:
	assert_eq(OrderText.reason("unknown_command"), "Not available yet")


func test_selecting_a_body_offers_real_checks() -> void:
	var ids: Array = bridge.current_view["bodies"].keys()
	ids.sort()
	view.select("body", ids[0], 0)
	assert_ne(main.order_panel._selection_label.text, "")
