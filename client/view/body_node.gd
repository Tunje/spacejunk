class_name BodyNode extends StaticBody3D
## A star, planet or targetable asteroid. Selection uses a plain sphere, never the mesh.
## A planet starts as a plain sphere and becomes its terrain once PlanetMesh has built
## it on a worker thread. Its hex outlines show while `show_outlines` is on.

## The star is drawn larger than life so it reads as the scene's light source.
const STAR_DRAWN_SCALE := 5.0
const STAR_EMISSION := Color(1.0, 0.93, 0.78)
const STAR_ENERGY := 14.0
const PLANET_COLOUR := Color(0.42, 0.40, 0.37)
const OUTLINE_COLOUR := Color(1.0, 1.0, 1.0, 0.35)

## Hex outlines on every planet, toggled from the client (key O).
static var show_outlines := false

var body_id := 0
var radius_m := 1.0
var kind := ""
var surface: MeshInstance3D
var outline: MeshInstance3D
var planet_cells := 0


func build(id: int, body: Dictionary) -> void:
	body_id = id
	kind = body["kind"]
	radius_m = body["radius_mm"] * FloatingOrigin.MM_TO_M
	set_meta("body", id)

	var mesh := MeshInstance3D.new()
	if kind == "star":
		_build_star(mesh)
	elif kind == "planet":
		_build_planet(mesh, body)
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


func _build_planet(mesh: MeshInstance3D, body: Dictionary) -> void:
	surface = mesh
	outline = MeshInstance3D.new()
	var lines := StandardMaterial3D.new()
	lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lines.albedo_color = OUTLINE_COLOUR
	outline.material_override = lines
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline.visible = show_outlines
	add_child(outline)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	var material := StandardMaterial3D.new()
	material.albedo_color = PLANET_COLOUR
	material.roughness = 0.95
	mesh.mesh = sphere
	mesh.material_override = material
	var built := PlanetMesh.request(PlanetMesh.settings_of(body), self)
	if not built.is_empty():
		planet_built(built)


## The terrain arrived: swap it in for the placeholder sphere.
func planet_built(built: Dictionary) -> void:
	var meshes := PlanetMesh.to_meshes(built)
	surface.mesh = meshes[0]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	surface.material_override = material
	outline.mesh = meshes[1]
	planet_cells = built["cells"]


func set_outlines(on: bool) -> void:
	if outline != null:
		outline.visible = on


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
