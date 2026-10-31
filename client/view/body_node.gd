class_name BodyNode extends StaticBody3D
## A star or targetable asteroid. Selection uses a plain sphere, never the mesh.

## The star is drawn larger than life so it reads as the scene's light source.
const STAR_DRAWN_SCALE := 5.0
const STAR_EMISSION := Color(1.0, 0.93, 0.78)
const STAR_ENERGY := 14.0

var body_id := 0
var radius_m := 1.0
var kind := ""


func build(id: int, body: Dictionary) -> void:
	body_id = id
	kind = body["kind"]
	radius_m = body["radius_mm"] * FloatingOrigin.MM_TO_M
	set_meta("body", id)

	var mesh := MeshInstance3D.new()
	if kind == "star":
		_build_star(mesh)
	else:
		mesh.mesh = RockMesh.get_mesh(RockMesh.variant_of(body["visual_seed"]), RockMesh.DETAILED)
		mesh.material_override = RockMesh.material()
		# A rock on the line to the star would otherwise eclipse a whole base.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var rng := RandomNumberGenerator.new()
		rng.seed = body["visual_seed"]
		mesh.rotation = Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
	add_child(mesh)

	var shape := CollisionShape3D.new()
	var collision := SphereShape3D.new()
	collision.radius = 1.0
	shape.shape = collision
	add_child(shape)


func _build_star(mesh: MeshInstance3D) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.emission_enabled = true
	material.emission = STAR_EMISSION
	material.emission_energy_multiplier = STAR_ENERGY
	mesh.mesh = sphere
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Places the body from its focus-relative position, compressing distant ones.
func place(relative_m: Vector3) -> void:
	var factor := FloatingOrigin.compression(relative_m.length())
	position = relative_m * factor
	scale = Vector3.ONE * radius_m * factor * (STAR_DRAWN_SCALE if kind == "star" else 1.0)
