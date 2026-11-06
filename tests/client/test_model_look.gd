extends GutTest
## D21: generated models get their metal capped, so a metallic surface in shade shows
## its colour under the ambient light instead of a black reflection of space.

const MODELS: Array[String] = [
	"res://assets/models/starter_hull.glb",
	"res://assets/models/mining_laser_mk1.glb",
]


func _materials(root: Node) -> Array[BaseMaterial3D]:
	var found: Array[BaseMaterial3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for surface in mi.mesh.get_surface_count():
			var material := mi.get_active_material(surface) as BaseMaterial3D
			if material != null:
				found.append(material)
	return found


func test_every_generated_model_is_capped() -> void:
	for path in MODELS:
		var model := ModelLook.instantiate(path)
		assert_not_null(model, path)
		autofree(model)
		var materials := _materials(model)
		assert_gt(materials.size(), 0, path)
		for material in materials:
			assert_lte(material.metallic, ModelLook.METALLIC_CAP + ModelLook.TOLERANCE, path)


## A model like an old TRELLIS import: one mesh whose shared material is fully
## metallic. Delivered models now come with metallic 0, so the cap is a guard, and
## these tests give it something to cap.
func _metal_model(mesh: BoxMesh) -> Node3D:
	var root := Node3D.new()
	var surface := MeshInstance3D.new()
	surface.mesh = mesh
	root.add_child(surface)
	return autofree(root)


func _metal_mesh() -> BoxMesh:
	var material := StandardMaterial3D.new()
	material.metallic = 1.0
	material.albedo_color = Color(0.8, 0.6, 0.2)
	var mesh := BoxMesh.new()
	mesh.material = material
	return mesh


func test_a_fully_metallic_model_is_capped() -> void:
	var model := _metal_model(_metal_mesh())
	ModelLook.apply(model)
	var shown := _materials(model)[0]
	assert_almost_eq(shown.metallic, ModelLook.METALLIC_CAP, ModelLook.TOLERANCE)
	assert_eq(shown.albedo_color, Color(0.8, 0.6, 0.2), "its colour is kept")


func test_the_shared_material_is_left_alone() -> void:
	var mesh := _metal_mesh()
	var tamed := _metal_model(mesh)
	var other := _metal_model(mesh)
	ModelLook.apply(tamed)
	assert_eq((mesh.material as BaseMaterial3D).metallic, 1.0, "the mesh's own material is unchanged")
	assert_eq(_materials(other)[0].metallic, 1.0, "another instance still sees it")


func test_colour_and_maps_are_kept() -> void:
	var raw: Node3D = autofree((load(MODELS[0]) as PackedScene).instantiate())
	var tamed := ModelLook.instantiate(MODELS[0])
	autofree(tamed)
	var a := _materials(raw)[0]
	var b := _materials(tamed)[0]
	assert_eq(b.albedo_texture, a.albedo_texture)
	assert_eq(b.metallic_texture, a.metallic_texture)
	assert_eq(b.roughness, a.roughness)


func test_matte_materials_are_untouched() -> void:
	var matte := StandardMaterial3D.new()
	matte.metallic = 0.2
	assert_null(ModelLook.tame(matte))
	var shiny := StandardMaterial3D.new()
	shiny.metallic = 1.0
	shiny.albedo_color = Color(0.8, 0.6, 0.2)
	var tamed := ModelLook.tame(shiny)
	assert_almost_eq(tamed.metallic, ModelLook.METALLIC_CAP, ModelLook.TOLERANCE)
	assert_eq(tamed.albedo_color, shiny.albedo_color)
	assert_eq(shiny.metallic, 1.0, "the original is not changed")
	assert_null(ModelLook.tame(tamed), "capped once is enough")
	assert_null(ModelLook.tame(ShaderMaterial.new()))
