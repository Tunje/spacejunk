extends GutTest
## D22: a part shows the generated model its data names, through ModelLook, and a
## labelled placeholder when there is no model; picking, glow and growth work on both.

## Models allowed off their collision centre, and why. Each is still counted and placed.
## None now: B16's long-leg model fits its box. The mechanism stays for later.
const OFF_CENTRE_OK := {}

var modules: Dictionary
var craft: CraftNode


func before_each() -> void:
	modules = DataLoader.load_defs()["modules"]
	craft = add_child_autofree(CraftNode.new())


func _part(id: int, def: String, at: String, children: Array = []) -> Dictionary:
	return { "id": id, "def": def, "parent_connector": at, "connector": "mount", "state": "on",
		"fault": "", "draw_w": 0, "priority": 0, "children": children }


## The starter ship's middle: the hull, tank and thruster (models) and its core (no model in data).
func _build() -> void:
	var root := _part(1, "starter_hull", "", [
		_part(2, "basic_core", "core"),
		_part(3, "propellant_tank_mk1", "stack_bottom", [_part(4, "chemical_thruster_mk1", "stack_bottom")]),
	])
	root.erase("parent_connector")
	root.erase("connector")
	craft.build(7, root, modules)


func craft_def(id: int) -> String:
	return { 1: "starter_hull", 3: "propellant_tank_mk1", 4: "chemical_thruster_mk1" }[id]


## Every generated model, as placed, sits on its part's collision box: a model off
## its data origin (as the B9 hull was, 3 m low) shows parts floating off the hull.
func test_every_model_sits_on_its_collision_box() -> void:
	var checked := 0
	for id: String in modules:
		var visual: Dictionary = modules[id]["visual"]
		var path := CraftNode.model_path(visual)
		if path == "":
			continue
		var model: Node3D = autofree(ModelLook.instantiate(path))
		model.position = CraftNode.MODEL_SHIFTS.get(visual["model"], Vector3.ZERO)
		var box := AABB()
		var first := true
		for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
			var b := model.transform * (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		var centre := CraftLayout.to_metres(modules[id]["collision"]["center_mm"])
		if not OFF_CENTRE_OK.has(id):
			assert_lt(box.get_center().distance_to(centre), 0.5, "%s: model %s, data %s" % [id, box.get_center(), centre])
		checked += 1
	assert_gte(checked, 14, "the 13 B12 parts and the hull")


func _metallic_ok(node: Node) -> bool:
	for mi: Node in node.find_children("*", "MeshInstance3D", true, false):
		for surface in (mi as MeshInstance3D).mesh.get_surface_count():
			var material := (mi as MeshInstance3D).get_active_material(surface) as BaseMaterial3D
			if material != null and material.metallic > ModelLook.METALLIC_CAP + ModelLook.TOLERANCE:
				return false
	return true


func test_model_path_needs_a_name_and_a_file() -> void:
	assert_eq(CraftNode.model_path({ "model": "chemical_thruster_mk1" }),
		"res://assets/models/chemical_thruster_mk1.glb")
	assert_eq(CraftNode.model_path({ "model": null }), "")
	assert_eq(CraftNode.model_path({}), "")
	assert_eq(CraftNode.model_path({ "model": "no_such_model" }), "", "named but not generated")


func test_a_part_with_a_model_shows_it_and_one_without_keeps_its_placeholder() -> void:
	_build()
	for id: int in [1, 3, 4]:
		var shown: Node3D = craft._meshes[id]
		assert_false(shown is MeshInstance3D and (shown as MeshInstance3D).mesh is PrimitiveMesh,
			"part %d is its model, not a block" % id)
		assert_gt(shown.find_children("*", "MeshInstance3D", true, false).size(), 0)
		assert_eq(shown.position, CraftNode.MODEL_SHIFTS.get(modules[craft_def(id)]["visual"]["model"], Vector3.ZERO),
			"on the part's data origin")
		assert_true(_metallic_ok(shown), "through ModelLook")
	for id: int in [2]:
		var block: MeshInstance3D = craft._meshes[id]
		assert_true(block.mesh is PrimitiveMesh, "part %d keeps its placeholder" % id)
		assert_eq(block.material_override, craft._materials[id])


func test_picking_and_resting_height_still_come_from_data() -> void:
	_build()
	var bodies := craft.find_children("*", "StaticBody3D", true, false)
	assert_eq(bodies.size(), 4)
	for body: Node in bodies:
		assert_eq(body.find_children("*", "CollisionShape3D", false, false).size(), 1)
	# The thruster's collision bottom is the lowest point, model or not.
	var lowest := INF
	for body: Node in bodies:
		var shape: CollisionShape3D = body.find_children("*", "CollisionShape3D", false, false)[0]
		var half := (shape.shape as BoxShape3D).size.y * 0.5 if shape.shape is BoxShape3D \
			else (shape.shape as CylinderShape3D).height * 0.5
		lowest = minf(lowest, ((body as Node3D).transform * (shape.position - Vector3(0, half, 0))).y)
	assert_almost_eq(craft.bottom_m, lowest, 0.001)


func test_a_model_glows_when_selected() -> void:
	_build()
	var model: Node3D = craft._meshes[1]
	var surface: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	var own := surface.get_active_material(0) as BaseMaterial3D
	assert_has(craft._model_materials[1], own)
	assert_false(own.emission_enabled)
	craft.highlight(1)
	assert_true(craft._materials[1].emission_enabled)
	assert_true(own.emission_enabled, "the model glows")
	assert_almost_eq(own.emission_energy_multiplier, CraftNode.SELECT_ENERGY, 0.001)
	assert_false((craft._model_materials[4][0] as BaseMaterial3D).emission_enabled, "only that part")


func test_a_new_model_part_grows_in() -> void:
	_build()
	var root := _part(1, "starter_hull", "", [
		_part(2, "basic_core", "core"),
		_part(3, "propellant_tank_mk1", "stack_bottom", [_part(4, "chemical_thruster_mk1", "stack_bottom")]),
		_part(5, "docking_port_mk1", "stack_top"),
	])
	craft.build(7, root, modules)
	assert_eq(craft._growing.keys(), [5])
	craft._advance_growth(0.1)
	assert_lt(craft._meshes[5].scale.x, 1.0)
