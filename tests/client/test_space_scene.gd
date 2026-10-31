extends GutTest

var view: Dictionary


func before_each() -> void:
	view = StubSim.new_game("stub", 7).view()


func _transforms(groups: Array) -> Array:
	var all: Array = []
	for group: Array in groups:
		all.append_array(group)
	return all


func test_same_seed_gives_the_same_field() -> void:
	var clear := AsteroidField.keep_clear(view, AsteroidField.anchor_of(view))
	assert_eq(AsteroidField.generate(7, clear, 200), AsteroidField.generate(7, clear, 200))


func test_different_seeds_give_different_fields() -> void:
	var clear := AsteroidField.keep_clear(view, AsteroidField.anchor_of(view))
	assert_ne(AsteroidField.generate(7, clear, 200), AsteroidField.generate(8, clear, 200))


func test_field_stays_clear_of_real_bodies_and_craft() -> void:
	var clear := AsteroidField.keep_clear(view, AsteroidField.anchor_of(view))
	assert_gt(clear.size(), view["units"].size())
	for xform: Transform3D in _transforms(AsteroidField.generate(7, clear, 800)):
		for entry: Dictionary in clear:
			assert_gt(xform.origin.distance_to(entry["at_m"]), entry["radius_m"])


func test_field_reaches_the_requested_count() -> void:
	var clear := AsteroidField.keep_clear(view, AsteroidField.anchor_of(view))
	assert_eq(_transforms(AsteroidField.generate(7, clear, AsteroidField.COUNT)).size(), AsteroidField.COUNT)


func test_anchor_is_the_middle_of_the_asteroids() -> void:
	var fake := { "bodies": {
		1: { "kind": "asteroid", "pos_mm": [100, 0, -300] },
		2: { "kind": "asteroid", "pos_mm": [300, 40, 300] },
		3: { "kind": "star", "pos_mm": [9000000, 0, 0] },
	} }
	assert_eq(AsteroidField.anchor_of(fake), [200, 20, 0])


func test_field_is_multimesh_with_no_collision() -> void:
	var field := AsteroidField.new()
	add_child_autofree(field)
	field.build(view)
	assert_eq(field.instance_total, AsteroidField.COUNT)
	for child: Node in field.get_children():
		assert_true(child is MultiMeshInstance3D)


func test_rock_meshes_are_shared_and_lumpy() -> void:
	var mesh := RockMesh.get_mesh(2, RockMesh.DETAILED)
	assert_same(mesh, RockMesh.get_mesh(2, RockMesh.DETAILED))
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shortest := INF
	var longest := 0.0
	for vertex: Vector3 in vertices:
		shortest = minf(shortest, vertex.length())
		longest = maxf(longest, vertex.length())
	assert_gt(longest - shortest, 0.15, "not a plain sphere")
	assert_lt(longest, 1.4)
	assert_gt(shortest, 0.3)


func test_rock_variants_differ() -> void:
	var first: PackedVector3Array = RockMesh.get_mesh(0, RockMesh.SIMPLE).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var second: PackedVector3Array = RockMesh.get_mesh(1, RockMesh.SIMPLE).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_ne(first, second)


func test_star_glows_and_is_drawn_larger_than_life() -> void:
	var star := BodyNode.new()
	add_child_autofree(star)
	star.build(1, { "kind": "star", "radius_mm": 1000000, "visual_seed": 0 })
	star.place(Vector3(10, 0, 0))
	assert_almost_eq(star.scale.x, 1000.0 * BodyNode.STAR_DRAWN_SCALE, 0.01)
	var mesh: MeshInstance3D = star.get_child(0)
	assert_true(mesh.material_override.emission_enabled)


func test_asteroid_scale_matches_its_radius() -> void:
	var rock := BodyNode.new()
	add_child_autofree(rock)
	rock.build(1, { "kind": "asteroid", "radius_mm": 200000, "visual_seed": 3 })
	rock.place(Vector3(10, 0, 0))
	assert_almost_eq(rock.scale.x, 200.0, 0.01)


func test_field_follows_the_focus_in_the_scene() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var local: LocalView = main.get_node("LocalView")
	var bridge: SimBridge = main.get_node("Bridge")
	bridge.set_paused(true)
	local.refresh(0.0)
	var unit: Dictionary = bridge.current_view["units"][local.focus_id]
	var expected := FloatingOrigin.relative_m(
		local.field.anchor_mm, local.field.anchor_mm, unit["pos_mm"], unit["pos_mm"], 0.0)
	assert_almost_eq(local.field.position.distance_to(expected), 0.0, 0.001)


func test_shadow_range_follows_the_camera() -> void:
	var main: Node = add_child_autofree(load("res://client/main.tscn").instantiate())
	var local: LocalView = main.get_node("LocalView")
	main.get_node("Bridge").set_paused(true)
	local.camera.distance_m = 40.0
	local.camera.target_distance_m = 40.0
	local.refresh(0.0)
	var near_range := local.sun.directional_shadow_max_distance
	local.camera.distance_m = 1000.0
	local.camera.target_distance_m = 1000.0
	local.refresh(0.0)
	assert_gt(local.sun.directional_shadow_max_distance, near_range)
