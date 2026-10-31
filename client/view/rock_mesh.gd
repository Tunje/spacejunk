class_name RockMesh extends RefCounted
## Chunky faceted unit rocks made by pushing a sphere around with noise. Meshes
## are shared by variant, so a large field costs one mesh per variant.

const VARIANTS := 6
const DETAILED := "detailed"
const SIMPLE := "simple"

static var _cache: Dictionary = {}
static var _material: StandardMaterial3D


static func variant_of(visual_seed: int) -> int:
	return absi(visual_seed) % VARIANTS


static func get_mesh(variant: int, detail: String) -> ArrayMesh:
	var key := "%s:%d" % [detail, variant]
	if not _cache.has(key):
		var segments := 36 if detail == DETAILED else 14
		_cache[key] = build(variant, segments, segments / 2)
	return _cache[key]


static func build(variant: int, segments: int, rings: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = segments
	sphere.rings = rings
	var noise := FastNoiseLite.new()
	noise.seed = variant * 7919 + 13
	noise.frequency = 0.9
	noise.fractal_octaves = 4
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in range(vertices.size()):
		var point := vertices[index]
		var push := noise.get_noise_3dv(point) * 0.55
		vertices[index] = point.normalized() * (0.82 + push)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var shaped := ArrayMesh.new()
	shaped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tool := SurfaceTool.new()
	tool.create_from(shaped, 0)
	tool.deindex()
	tool.generate_normals()
	return tool.commit()


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.17, 0.155, 0.14)
		_material.roughness = 0.96
	return _material
