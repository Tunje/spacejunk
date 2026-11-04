class_name PlanetMesh extends RefCounted
## The base mesh of a planet, option B of planets.md section 6: smooth terrain over
## the hex data. Each of the grid's 10 n^2 + 2 cells from PlanetGrid is one vertex,
## at its centre direction and height, and the grid's dual triangles join them. The
## hex outlines, drawn only when asked for, run between the centres of the
## triangles round each cell.
##
## Building is a pure function of the planet's settings, so it runs on a worker
## thread and the result is cached by those settings. The mesh is in units of the
## datum radius, so a BodyNode scales it like any body.
##
## Colour blends by height, moisture and latitude for now; B's surface types and
## palettes replace it once they are data.

## Octave weights for the height and moisture noise until a planet's roughness is
## data (planets.md section 1). The kernel's tests use the same.
const DEFAULT_WEIGHTS := [4, 2, 1]
const DEFAULT_RANGE_M := 8000
## Outlines sit this far above the surface, as a share of the radius, so they
## never sink into it.
const OUTLINE_LIFT := 0.0004

const DEEP_SEA := Color(0.07, 0.16, 0.30)
const SHALLOW_SEA := Color(0.14, 0.33, 0.48)
const DUST := Color(0.66, 0.56, 0.42)
const LOWLAND := Color(0.36, 0.45, 0.28)
const WETLAND := Color(0.20, 0.33, 0.21)
const ROCK := Color(0.45, 0.42, 0.40)
const SNOW := Color(0.90, 0.92, 0.94)
const SHELF_M := 1500.0
const POLAR_LINE := 0.82

static var _cache: Dictionary = {}
static var _cache_lock := Mutex.new()


## The settings a planet's look is built from, from a view body. Since A15 a body
## carries `planet { seed, height_range_m }`, the same settings the simulation's
## heights come from; an empty `planet` is a smooth sphere. A body from before A15
## falls back to its own fields, then to defaults.
static func settings_of(body: Dictionary) -> Dictionary:
	var source: Dictionary = body
	var range_default := DEFAULT_RANGE_M
	if body.has("planet"):
		source = body["planet"]
		range_default = 0
	return {
		"seed": int(source.get("seed", body.get("visual_seed", 0))),
		"radius_mm": int(body["radius_mm"]),
		"range_m": mini(int(source.get("height_range_m", range_default)), PlanetGrid.MAX_HEIGHT_M),
		"sea_level_m": body.get("sea_level_m", null),
		"weights": source.get("weights", body.get("weights", DEFAULT_WEIGHTS)),
		"n": PlanetGrid.n_for_radius(int(body["radius_mm"])),
	}


static func key_of(settings: Dictionary) -> String:
	return "%d:%d:%d:%s:%s:%d" % [settings["seed"], settings["radius_mm"], settings["range_m"],
		str(settings["sea_level_m"]), str(settings["weights"]), settings["n"]]


static func cached(settings: Dictionary) -> Dictionary:
	_cache_lock.lock()
	var found: Dictionary = _cache.get(PlanetMesh.key_of(settings), {})
	_cache_lock.unlock()
	return found


static func store(settings: Dictionary, built: Dictionary) -> void:
	_cache_lock.lock()
	_cache[PlanetMesh.key_of(settings)] = built
	_cache_lock.unlock()


## Cells per chunk when the per-cell work is spread over the worker pool.
const CHUNK_CELLS := 4096


## Builds the surface and outline arrays. Pure: same settings, same arrays, whether
## the per-cell work runs on one thread or across the pool. With `parallel`, the
## caller must not itself be a pool task, since it waits on a group task.
## Returns { surface: Array (Mesh.ARRAY_MAX), outline: Array, cells, triangles, heights, ms }.
static func build(settings: Dictionary, parallel := false) -> Dictionary:
	var started := Time.get_ticks_msec()
	var n: int = settings["n"]
	var count := PlanetGrid.cell_count(n)
	var chunks := ceili(float(count) / CHUNK_CELLS)
	var parts: Array = []
	parts.resize(chunks)
	if parallel:
		var lock := Mutex.new()
		var one_chunk := func(index: int) -> void:
			var part := PlanetMesh._cells(settings, index * CHUNK_CELLS, mini(count, (index + 1) * CHUNK_CELLS))
			lock.lock()
			parts[index] = part
			lock.unlock()
		var group := WorkerThreadPool.add_group_task(one_chunk, chunks, -1, false, "planet cells")
		WorkerThreadPool.wait_for_group_task_completion(group)
	else:
		for index in chunks:
			parts[index] = PlanetMesh._cells(settings, index * CHUNK_CELLS, mini(count, (index + 1) * CHUNK_CELLS))
	var heights := PackedInt32Array()
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	for part: Dictionary in parts:
		heights.append_array(part["heights"])
		vertices.append_array(part["vertices"])
		colours.append_array(part["colours"])
	var triangles := PlanetMesh.triangles(n, vertices)
	var normals := PackedVector3Array()
	normals.resize(count)
	for index in range(0, triangles.size(), 3):
		var a := vertices[triangles[index]]
		var face := (vertices[triangles[index + 1]] - a).cross(vertices[triangles[index + 2]] - a)
		for corner in 3:
			normals[triangles[index + corner]] += face
	for cell in count:
		normals[cell] = normals[cell].normalized()
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = vertices
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_COLOR] = colours
	surface[Mesh.ARRAY_INDEX] = triangles
	var outline := []
	outline.resize(Mesh.ARRAY_MAX)
	outline[Mesh.ARRAY_VERTEX] = PlanetMesh.outline_segments(triangles, vertices)
	var directions := PackedVector3Array()
	directions.resize(count)
	for cell in count:
		directions[cell] = vertices[cell].normalized()
	return {
		"surface": surface, "outline": outline, "cells": count, "triangles": triangles.size() / 3,
		"heights": heights, "directions": directions, "n": n, "ms": Time.get_ticks_msec() - started,
	}


## The cell whose centre is nearest a direction from the planet's centre, for
## picking a landing site. A plain scan: about 100,000 dot products, once per click.
static func nearest_cell(built: Dictionary, direction: Vector3) -> int:
	var directions: PackedVector3Array = built["directions"]
	var best := 0
	var best_dot := -2.0
	for cell in directions.size():
		var dot := directions[cell].dot(direction)
		if dot > best_dot:
			best_dot = dot
			best = cell
	return best


## A cell's hex (or pentagon) outline, in the mesh's units: its corners are the
## centres of the triangles it shares with each pair of neighbours, in turn round it.
static func cell_outline(built: Dictionary, cell: int) -> PackedVector3Array:
	var vertices: PackedVector3Array = built["surface"][Mesh.ARRAY_VERTEX]
	var centre := vertices[cell]
	var up := centre.normalized()
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := east.cross(up)
	var around: Array[int] = PlanetGrid.neighbours(cell, built["n"])
	around.sort_custom(func(a: int, b: int) -> bool:
		var da := vertices[a] - centre
		var db := vertices[b] - centre
		return atan2(da.dot(north), da.dot(east)) < atan2(db.dot(north), db.dot(east)))
	var corners := PackedVector3Array()
	for index in around.size():
		var corner := (centre + vertices[around[index]] + vertices[around[(index + 1) % around.size()]]) / 3.0
		corners.append(corner * (1.0 + OUTLINE_LIFT * 2.0))
	return corners


## Direction, height, moisture and colour for cells from..to-1: the slow part, as
## each cell runs the kernel's integer noise twice.
static func _cells(settings: Dictionary, from: int, to: int) -> Dictionary:
	var n: int = settings["n"]
	var radius_m: float = settings["radius_mm"] / 1000.0
	var heights := PackedInt32Array()
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	for cell in range(from, to):
		var dir := PlanetGrid.direction(cell, n)
		var height := PlanetGrid.height_m(settings["seed"], dir, settings["weights"], settings["range_m"])
		var wet := PlanetGrid.moisture(settings["seed"], dir, settings["weights"])
		var unit := Vector3(dir[0], dir[1], dir[2]) / float(PlanetGrid.ONE)
		heights.append(height)
		vertices.append(unit * (1.0 + height / radius_m))
		colours.append(PlanetMesh.colour(height, wet, unit.y, settings))
	return { "heights": heights, "vertices": vertices, "colours": colours }


## The dual triangles, two per lattice square of each diamond's chart, as cell IDs,
## wound so their faces point outwards (Godot's front faces wind clockwise).
static func triangles(n: int, vertices: PackedVector3Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for d in PlanetGrid.DIAMONDS:
		for i in n:
			for j in n:
				var a := PlanetGrid.cell_at(d, i, j, n)
				var b := PlanetGrid.cell_at(d, i + 1, j, n)
				var c := PlanetGrid.cell_at(d, i, j + 1, n)
				var e := PlanetGrid.cell_at(d, i + 1, j + 1, n)
				PlanetMesh._add_outward(out, vertices, a, b, c)
				PlanetMesh._add_outward(out, vertices, b, e, c)
	return out


static func _add_outward(out: PackedInt32Array, vertices: PackedVector3Array, a: int, b: int, c: int) -> void:
	var face := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
	if face.dot(vertices[a] + vertices[b] + vertices[c]) > 0.0:
		out.append_array([a, c, b])
	else:
		out.append_array([a, b, c])


## Line segments along the hex edges: between the centres of the two triangles that
## share each grid edge, so each edge is drawn once. Lifted a little off the surface.
static func outline_segments(triangles: PackedInt32Array, vertices: PackedVector3Array) -> PackedVector3Array:
	var first_face: Dictionary = {}
	var lines := PackedVector3Array()
	for face in triangles.size() / 3:
		var centre := (vertices[triangles[face * 3]] + vertices[triangles[face * 3 + 1]] + vertices[triangles[face * 3 + 2]]) / 3.0
		centre *= 1.0 + OUTLINE_LIFT
		for corner in 3:
			var a := triangles[face * 3 + corner]
			var b := triangles[face * 3 + (corner + 1) % 3]
			var edge := mini(a, b) * 2_000_000_000 + maxi(a, b)
			if first_face.has(edge):
				lines.append(first_face[edge])
				lines.append(centre)
				first_face.erase(edge)
			else:
				first_face[edge] = centre
	return lines


## A colour from height, moisture and latitude, standing in for B's surface types:
## sea below sea level, snow on peaks and at the poles, rock up high, and dust,
## lowland or wetland by moisture. Neighbouring cells blend across each triangle.
static func colour(height_m: int, moisture: int, north: float, settings: Dictionary) -> Color:
	var sea: Variant = settings["sea_level_m"]
	var range_m := maxf(1.0, float(settings["range_m"]))
	if sea != null and height_m < int(sea):
		return SHALLOW_SEA.lerp(DEEP_SEA, clampf((int(sea) - height_m) / SHELF_M, 0.0, 1.0))
	var high := clampf(height_m / range_m, -1.0, 1.0)
	var wet := clampf(moisture / 1000.0, 0.0, 1.0)
	var ground := DUST.lerp(LOWLAND, smoothstep(0.25, 0.5, wet)).lerp(WETLAND, smoothstep(0.6, 0.85, wet))
	ground = ground.lerp(ROCK, smoothstep(0.35, 0.65, high))
	var cold := maxf(smoothstep(0.7, 0.9, high), smoothstep(POLAR_LINE, 0.95, absf(north)))
	return ground.lerp(SNOW, cold)


## Turns built arrays into meshes, on the main thread.
static func to_meshes(built: Dictionary) -> Array[Mesh]:
	var surface := ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, built["surface"])
	var outline := ArrayMesh.new()
	outline.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, built["outline"])
	return [surface, outline]


# --- Building in the background ---

## Requests waiting on a build, by settings key: { task, waiting: [WeakRef] }.
static var _pending: Dictionary = {}


## The built planet now if it is cached, otherwise {} and a build on a worker
## thread, after which `node.planet_built(built)` is called on the main thread, if
## the node still exists. Builds of the same settings are shared.
static func request(settings: Dictionary, node: Object) -> Dictionary:
	var found := PlanetMesh.cached(settings)
	if not found.is_empty():
		return found
	var key := PlanetMesh.key_of(settings)
	if _pending.has(key):
		_pending[key]["waiting"].append(weakref(node))
		return {}
	OrbitMath.sin_cos(0)
	var thread := Thread.new()
	_pending[key] = { "thread": thread, "waiting": [weakref(node)] }
	thread.start(PlanetMesh._build_in_background.bind(settings), Thread.PRIORITY_LOW)
	return {}


## Runs on its own thread, so it may wait on the pool's group task.
static func _build_in_background(settings: Dictionary) -> void:
	var built := PlanetMesh.build(settings, true)
	PlanetMesh.store(settings, built)
	PlanetMesh._deliver.call_deferred(PlanetMesh.key_of(settings), built)


static func _deliver(key: String, built: Dictionary) -> void:
	var entry: Dictionary = _pending.get(key, {})
	_pending.erase(key)
	if entry.is_empty():
		return
	(entry["thread"] as Thread).wait_to_finish()
	for ref: WeakRef in entry["waiting"]:
		var node: Object = ref.get_ref()
		if node != null:
			node.planet_built(built)


## Whether any build is still running, for tests and screenshots.
static func busy() -> bool:
	return not _pending.is_empty()
