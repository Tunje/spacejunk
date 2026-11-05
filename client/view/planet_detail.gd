class_name PlanetDetail extends Node3D
## Close-up terrain, planets.md section 7. Near the surface of a planet drawn at
## true scale, a quadtree of square tiles in a tangent plane anchored under the
## camera splits towards the camera, down to about 2 m between vertices. Each tile
## is drawn over the base mesh, which sits a little lower.
##
## A vertex's height is the simulation's own smooth terrain, PlanetGrid.height_m at
## its direction (equal to the cell's height at every cell centre), plus float
## detail noise from the planet's visual seed. Within FLAT_OUTER_M of a landed craft
## the detail fades and the ground levels to the craft's cell height, so a craft
## sits exactly on the simulation's height and never clips into a visual hill.
##
## Tiles build on the worker pool. A new set of tiles is shown only when all of it
## is ready, so the view never has holes; until then the old set stays.

const ROOT_M := 65536.0
const SEGMENTS := 32
const MAX_LEVEL := 10
## A tile splits while the camera is nearer than this many tile widths.
const SPLIT_FACTOR := 1.0
## Close-up detail runs below this height above the datum.
const ACTIVE_ALTITUDE_M := 40000.0
## The anchor moves once the camera is this far from it along the surface.
const REANCHOR_M := 16000.0
const DETAIL_M := 35.0
const DETAIL_PERIOD_M := 700.0
const FINE_M := 1.5
const FINE_PERIOD_M := 30.0
const FLAT_INNER_M := 60.0
const FLAT_OUTER_M := 200.0
const MAX_TILES := 400
## The hex under a craft in low flight is levelled to its height across most of the
## hex, since the simulation's ground there is flat at that height (A19).
const HEX_INNER_M := 2500.0
const HEX_OUTER_M := 3400.0

var body_id := 0
var settings: Dictionary = {}
var visual_seed := 0
## Tangent frame of the anchor, as unit vectors in the planet's frame.
var centre_dir := Vector3.ZERO
var east := Vector3.ZERO
var north := Vector3.ZERO
## Landed sites on this body: { dir: Vector3, height_m: int }.
var sites: Array[Dictionary] = []
var tiles: Dictionary = {}
var shown: Array[String] = []
var wanted: Array[String] = []
var _sites_key := ""
var _material: StandardMaterial3D
var _lock := Mutex.new()
var _finished: Array[Dictionary] = []
## Tasks of dropped tiles still running: waited on once done, so none leak.
var _abandoned: Array[int] = []
## Raised whenever tiles are dropped, so a build started before then is ignored.
var _generation := 0


func _init() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95


## Per frame from the local view. `body` is the planet drawn at true scale near the
## camera, or null; `camera_planet` is the camera pivot in the planet's frame (m).
func update(body: BodyNode, body_view: Dictionary, camera_planet: Vector3, landed: Array[Dictionary]) -> void:
	_collect_finished()
	if body == null or body.planet.is_empty() or camera_planet.length() - body.radius_m > ACTIVE_ALTITUDE_M:
		clear()
		return
	var wanted_settings := PlanetMesh.settings_of(body_view)
	if body.body_id != body_id or PlanetMesh.key_of(wanted_settings) != PlanetMesh.key_of(settings):
		clear()
		body_id = body.body_id
		settings = wanted_settings
		visual_seed = int(body_view.get("visual_seed", 0))
	_set_sites(landed)
	var up := camera_planet.normalized()
	if centre_dir == Vector3.ZERO or centre_dir.angle_to(up) * body.radius_m > REANCHOR_M:
		_anchor(up)
	# Height above the ground under the camera, not the datum: one terrain lookup.
	var no_noise: Array[FastNoiseLite] = []
	var ground := PlanetDetail.height_at(up, settings, no_noise, sites)
	wanted = wanted_tiles(_plane_point(camera_planet), camera_planet.length() - body.radius_m - ground)
	for key: String in wanted:
		if not tiles.has(key):
			_start(key)
	if _all_ready(wanted) and wanted != shown:
		_show(wanted)
	_place(body)


func clear() -> void:
	_drop_all()
	wanted.clear()
	centre_dir = Vector3.ZERO
	body_id = 0


func _drop_all() -> void:
	_generation += 1
	for key: String in tiles:
		var node: MeshInstance3D = tiles[key].get("node")
		if node != null:
			node.queue_free()
		elif tiles[key].has("task"):
			_abandoned.append(tiles[key]["task"])
	tiles.clear()
	shown.clear()


func _exit_tree() -> void:
	for key: String in tiles:
		if tiles[key].has("task") and tiles[key].get("node") == null:
			_abandoned.append(tiles[key]["task"])
	for task: int in _abandoned:
		WorkerThreadPool.wait_for_task_completion(task)
	_abandoned.clear()


func is_active() -> bool:
	return centre_dir != Vector3.ZERO


func _anchor(up: Vector3) -> void:
	_drop_all()
	centre_dir = up
	east = up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	north = east.cross(up).normalized()


func _set_sites(landed: Array[Dictionary]) -> void:
	var key := str(landed)
	if key == _sites_key:
		return
	_sites_key = key
	sites = landed
	# Tiles near a site change, so build again from scratch.
	_drop_all()


## The camera's point in the tangent plane, in metres east and north of the anchor.
func _plane_point(camera_planet: Vector3) -> Vector2:
	var radius: float = settings["radius_mm"] / 1000.0
	var on_plane := camera_planet.normalized() * radius / maxf(0.001, camera_planet.normalized().dot(centre_dir))
	return Vector2(on_plane.dot(east), on_plane.dot(north))


## The quadtree's leaves for a camera at `point` in the plane, `height_m` up.
static func wanted_tiles(point: Vector2, height_m: float) -> Array[String]:
	var out: Array[String] = []
	PlanetDetail._visit(0, 0, 0, point, maxf(0.0, height_m), out)
	return out


static func _visit(level: int, ix: int, iy: int, point: Vector2, height_m: float, out: Array[String]) -> void:
	var size := ROOT_M / (1 << level)
	var centre := Vector2((ix + 0.5) * size - ROOT_M / 2.0, (iy + 0.5) * size - ROOT_M / 2.0)
	var reach := sqrt(point.distance_squared_to(centre) + height_m * height_m)
	if level < MAX_LEVEL and reach < size * SPLIT_FACTOR:
		for child in 4:
			PlanetDetail._visit(level + 1, ix * 2 + (child & 1), iy * 2 + (child >> 1), point, height_m, out)
	else:
		out.append("%d:%d:%d" % [level, ix, iy])


func _all_ready(keys: Array[String]) -> bool:
	for key: String in keys:
		if not tiles.has(key) or tiles[key].get("node") == null:
			return false
	return true


func _show(keys: Array[String]) -> void:
	for key: String in tiles:
		var node: MeshInstance3D = tiles[key].get("node")
		if node != null:
			node.visible = keys.has(key)
	shown = keys.duplicate()
	_trim()


## Drops built tiles that are neither shown nor wanted, oldest first, past MAX_TILES.
func _trim() -> void:
	if tiles.size() <= MAX_TILES:
		return
	for key: String in tiles.keys():
		if tiles.size() <= MAX_TILES:
			return
		if not shown.has(key) and not wanted.has(key) and tiles[key].get("node") != null:
			tiles[key]["node"].queue_free()
			tiles.erase(key)


func _start(key: String) -> void:
	var job := {
		"key": key, "settings": settings, "seed": visual_seed, "sites": sites.duplicate(),
		"centre": centre_dir, "east": east, "north": north, "anchor": PlanetMesh.key_of(settings) + str(centre_dir),
		"generation": _generation,
	}
	tiles[key] = { "task": WorkerThreadPool.add_task(_build_task.bind(job), false, "planet tile") }


func _build_task(job: Dictionary) -> void:
	var built := PlanetDetail.build_tile(job)
	_lock.lock()
	_finished.append(built)
	_lock.unlock()


func _collect_finished() -> void:
	var still: Array[int] = []
	for task: int in _abandoned:
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
		else:
			still.append(task)
	_abandoned = still
	_lock.lock()
	var done := _finished
	_finished = []
	_lock.unlock()
	for built: Dictionary in done:
		var key: String = built["key"]
		# A build from before the last drop, or for a tile already built, is stale.
		if built.get("generation", -1) != _generation or not tiles.has(key) or not tiles[key].has("task"):
			continue
		WorkerThreadPool.wait_for_task_completion(tiles[key]["task"])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, built["arrays"])
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = _material
		node.visible = false
		add_child(node)
		tiles[key] = { "node": node, "origin": built["origin"] }


## Each tile's origin is in the planet's frame in metres, so its place is the
## planet's drawn centre plus that.
func _place(body: BodyNode) -> void:
	for key: String in shown:
		if tiles.has(key) and tiles[key].get("node") != null:
			tiles[key]["node"].position = body.position + (tiles[key]["origin"] as Vector3)


# --- Building one tile (on a worker thread) ---

## Height above the datum in metres at a direction: the simulation's terrain, plus
## detail noise, levelled near landed sites.
static func height_at(dir: Vector3, settings: Dictionary, noise: Array[FastNoiseLite], sites: Array[Dictionary]) -> float:
	var q30 := [roundi(dir.x * PlanetGrid.ONE), roundi(dir.y * PlanetGrid.ONE), roundi(dir.z * PlanetGrid.ONE)]
	var base := float(PlanetGrid.height_m(settings["seed"], q30, settings["weights"], settings["range_m"]))
	var radius: float = settings["radius_mm"] / 1000.0
	var at := dir * radius
	var detail := 0.0
	if not noise.is_empty():
		detail = noise[0].get_noise_3dv(at) * DETAIL_M + noise[1].get_noise_3dv(at) * FINE_M
	for site: Dictionary in sites:
		var away: float = (site["dir"] as Vector3).angle_to(dir) * radius
		var outer: float = site.get("outer_m", FLAT_OUTER_M)
		if away < outer:
			var keep := smoothstep(site.get("inner_m", FLAT_INNER_M), outer, away)
			return lerpf(float(site["height_m"]), base + detail, keep)
	return base + detail


static func detail_noise(seed_value: int) -> Array[FastNoiseLite]:
	var broad := FastNoiseLite.new()
	broad.seed = seed_value
	broad.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	broad.fractal_type = FastNoiseLite.FRACTAL_FBM
	broad.fractal_octaves = 4
	broad.frequency = 1.0 / DETAIL_PERIOD_M
	var fine := FastNoiseLite.new()
	fine.seed = seed_value + 1
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fine.frequency = 1.0 / FINE_PERIOD_M
	return [broad, fine]


## The tile's mesh arrays, relative to its origin, with skirts round its edges to
## hide the cracks where it meets a coarser neighbour.
static func build_tile(job: Dictionary) -> Dictionary:
	var parts: PackedStringArray = (job["key"] as String).split(":")
	var level := int(parts[0])
	var size := ROOT_M / (1 << level)
	var x0 := int(parts[1]) * size - ROOT_M / 2.0
	var y0 := int(parts[2]) * size - ROOT_M / 2.0
	var settings: Dictionary = job["settings"]
	var radius: float = settings["radius_mm"] / 1000.0
	var centre: Vector3 = job["centre"]
	var east_dir: Vector3 = job["east"]
	var north_dir: Vector3 = job["north"]
	var noise := PlanetDetail.detail_noise(job["seed"])
	var sites_here: Array[Dictionary] = job["sites"]
	var count := SEGMENTS + 1
	var points: Array[Vector3] = []
	var dirs: Array[Vector3] = []
	var heights := PackedFloat64Array()
	var mid_dir := (centre * radius + east_dir * (x0 + size / 2.0) + north_dir * (y0 + size / 2.0)).normalized()
	var origin := mid_dir * (radius + PlanetDetail.height_at(mid_dir, settings, noise, sites_here))
	for row in count:
		for col in count:
			var u := x0 + size * col / SEGMENTS
			var v := y0 + size * row / SEGMENTS
			var dir := (centre * radius + east_dir * u + north_dir * v).normalized()
			var height := PlanetDetail.height_at(dir, settings, noise, sites_here)
			dirs.append(dir)
			heights.append(height)
			points.append(dir * (radius + height) - origin)
	var vertices := PackedVector3Array(points)
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	for row in count:
		for col in count:
			var index := row * count + col
			var right := points[row * count + mini(col + 1, SEGMENTS)] - points[row * count + maxi(col - 1, 0)]
			var up := points[mini(row + 1, SEGMENTS) * count + col] - points[maxi(row - 1, 0) * count + col]
			var normal := up.cross(right).normalized()
			if normal.dot(dirs[index]) < 0.0:
				normal = -normal
			normals.append(normal)
			var q30 := [roundi(dirs[index].x * PlanetGrid.ONE), roundi(dirs[index].y * PlanetGrid.ONE), roundi(dirs[index].z * PlanetGrid.ONE)]
			var wet := PlanetGrid.moisture(settings["seed"], q30, settings["weights"])
			colours.append(PlanetMesh.colour(roundi(heights[index]), wet, dirs[index].y, settings))
	var indices := PackedInt32Array()
	for row in SEGMENTS:
		for col in SEGMENTS:
			var a := row * count + col
			PlanetDetail._quad(indices, vertices, a, a + 1, a + count, a + count + 1, dirs[a])
	PlanetDetail._add_skirts(vertices, normals, colours, indices, dirs, size / SEGMENTS * 2.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	return { "key": job["key"], "anchor": job["anchor"], "generation": job.get("generation", 0), "arrays": arrays,
		"origin": origin, "heights": heights }


## Two triangles for a quad, wound clockwise seen from outside, Godot's front face.
static func _quad(indices: PackedInt32Array, vertices: PackedVector3Array, a: int, b: int, c: int, d: int, up: Vector3) -> void:
	for tri: Array in [[a, b, c], [b, d, c]]:
		var face := (vertices[tri[1]] - vertices[tri[0]]).cross(vertices[tri[2]] - vertices[tri[0]])
		if face.dot(up) > 0.0:
			indices.append_array([tri[0], tri[2], tri[1]])
		else:
			indices.append_array([tri[0], tri[1], tri[2]])


static func _add_skirts(vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray,
		indices: PackedInt32Array, dirs: Array[Vector3], depth: float) -> void:
	var count := SEGMENTS + 1
	var edges: Array = [[], [], [], []]
	for i in count:
		edges[0].append(i)
		edges[1].append(SEGMENTS * count + i)
		edges[2].append(i * count)
		edges[3].append(i * count + SEGMENTS)
	for edge: Array in edges:
		var first := vertices.size()
		for index: int in edge:
			vertices.append(vertices[index] - dirs[index] * depth)
			normals.append(normals[index])
			colours.append(colours[index])
		for step in SEGMENTS:
			var a: int = edge[step]
			var b: int = edge[step + 1]
			# Both windings, so a skirt shows from either side.
			indices.append_array([a, b, first + step, b, first + step + 1, first + step])
			indices.append_array([a, first + step, b, b, first + step, first + step + 1])
