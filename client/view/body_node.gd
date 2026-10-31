class_name BodyNode extends StaticBody3D
## A star or asteroid. Placeholder shapes only; task D8 replaces the look.

var body_id := 0
var radius_m := 1.0
var kind := ""


func build(id: int, body: Dictionary) -> void:
	body_id = id
	kind = body["kind"]
	radius_m = body["radius_mm"] * FloatingOrigin.MM_TO_M
	set_meta("body", id)

	var rng := RandomNumberGenerator.new()
	rng.seed = body["visual_seed"]
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	if kind == "star":
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.95, 0.82)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		material.albedo_color = Color(0.24, 0.22, 0.20).lerp(Color(0.34, 0.30, 0.26), rng.randf())
		material.roughness = 0.95
		mesh.scale = Vector3(rng.randf_range(0.8, 1.1), rng.randf_range(0.7, 1.0), rng.randf_range(0.8, 1.1))
		mesh.rotation = Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
	mesh.material_override = material
	add_child(mesh)

	var shape := CollisionShape3D.new()
	var collision := SphereShape3D.new()
	collision.radius = 1.0
	shape.shape = collision
	add_child(shape)


## Places the body from its focus-relative position, compressing distant ones.
func place(relative_m: Vector3) -> void:
	var factor := FloatingOrigin.compression(relative_m.length())
	position = relative_m * factor
	scale = Vector3.ONE * radius_m * factor
