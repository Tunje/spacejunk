class_name SystemLayout extends RefCounted
## The system map's System view (D37): the star at the centre, every body, frame
## and craft placed round what it orbits or sits in, and every orbit drawn as a
## ring. Each level uses the map's log scale of distance from its parent, shrunk
## by NEST_SHRINK per level, so a moon's ring sits beside its planet instead of
## swallowing the star. View only, from the bodies and frames in data: a belt shows
## up once its fields are frames round the star.

const NEST_SHRINK := 0.5
const ONE_Q30 := 1073741824.0


## The key of what an entity orbits or sits in, as "kind:id", or "" for the root.
static func parent_of(view: Dictionary, kind: String, id: int) -> String:
	match kind:
		"body":
			var body: Dictionary = view["bodies"][id]
			if int(body.get("frame", 0)) != 0:
				return "frame:%d" % int(body["frame"])
			var parent := int(body.get("orbit", {}).get("parent", 0))
			return "body:%d" % parent if parent != 0 and view["bodies"].has(parent) else ""
		"frame":
			var parent := int(view["frames"][id].get("orbit", {}).get("parent", 0))
			return "body:%d" % parent if view["bodies"].has(parent) else ""
		"unit":
			var unit: Dictionary = view["units"][id]
			if int(unit.get("frame", 0)) != 0:
				return "frame:%d" % int(unit["frame"])
			if not unit.get("landed", {}).is_empty():
				return "body:%d" % int(unit["landed"]["body"])
			if int(unit.get("stepped", 0)) != 0:
				return "body:%d" % int(unit["stepped"])
			if not unit.get("dock", {}).is_empty():
				return "unit:%d" % int(unit["dock"]["target_unit"])
			var parent := int(unit.get("orbit", {}).get("parent", 0))
			return "body:%d" % parent if parent != 0 else ""
	return ""


static func _entity(view: Dictionary, key: String) -> Dictionary:
	var kind := key.get_slice(":", 0)
	var id := int(key.get_slice(":", 1))
	var table: Dictionary = view.get({ "body": "bodies", "frame": "frames", "unit": "units" }[kind], {})
	return table.get(id, {})


## Map positions by "kind:id": the root at the origin, each child round its parent
## in its real direction, at the log distance shrunk once per level.
static func positions(view: Dictionary) -> Dictionary:
	var placed: Dictionary = {}
	var keys: Array[String] = []
	for id: int in view["bodies"]:
		keys.append("body:%d" % id)
	for id: int in view.get("frames", {}):
		keys.append("frame:%d" % id)
	for id: int in view["units"]:
		keys.append("unit:%d" % id)
	for key: String in keys:
		SystemLayout._place(view, key, placed, 0)
	return placed


## Places one entity (and its parents first), returning { pos, depth }.
static func _place(view: Dictionary, key: String, placed: Dictionary, guard: int) -> Dictionary:
	if placed.has(key):
		return placed[key]
	var parent := SystemLayout.parent_of(view, key.get_slice(":", 0), int(key.get_slice(":", 1)))
	if parent == "" or guard > 12 or SystemLayout._entity(view, parent).is_empty():
		placed[key] = { "pos": Vector3.ZERO, "depth": 0 }
		return placed[key]
	var above := SystemLayout._place(view, parent, placed, guard + 1)
	var offset := SystemLayout._offset_m(SystemLayout._entity(view, key), SystemLayout._entity(view, parent))
	var depth: int = above["depth"] + 1
	var length := offset.length()
	var pos: Vector3 = above["pos"]
	if length > 0.0:
		pos += offset / length * SystemMap.map_radius(length) * pow(NEST_SHRINK, depth - 1)
	placed[key] = { "pos": pos, "depth": depth }
	return placed[key]


## Child minus parent, in metres, from 64-bit world mm.
static func _offset_m(child: Dictionary, parent: Dictionary) -> Vector3:
	var a := WorldPosition.of(child)
	var b := WorldPosition.of(parent)
	return Vector3(float(a[0] - b[0]), float(a[1] - b[1]), float(a[2] - b[2])) / 1000.0


## One ring per body or frame on an orbit, as { centre, radius, p, q }: round its
## parent's position, at its semi-major axis on the same nested scale, in its plane.
static func orbit_rings(view: Dictionary, placed: Dictionary) -> Array[Dictionary]:
	var rings: Array[Dictionary] = []
	for kind: String in ["body", "frame"]:
		var table: Dictionary = view["bodies"] if kind == "body" else view.get("frames", {})
		var ids: Array = table.keys()
		ids.sort()
		for id: int in ids:
			var orbit: Dictionary = table[id].get("orbit", {})
			var parent := SystemLayout.parent_of(view, kind, id)
			if orbit.is_empty() or parent == "" or not placed.has(parent) or not orbit.has("a_mm"):
				continue
			var depth: int = placed[parent]["depth"] + 1
			var p: Array = orbit.get("p_q30", [ONE_Q30, 0, 0])
			var q: Array = orbit.get("q_q30", [0, 0, ONE_Q30])
			rings.append({
				"centre": placed[parent]["pos"],
				"radius": SystemMap.map_radius(float(orbit["a_mm"]) / 1000.0) * pow(NEST_SHRINK, depth - 1),
				"p": Vector3(float(p[0]), float(p[1]), float(p[2])) / ONE_Q30,
				"q": Vector3(float(q[0]), float(q[1]), float(q[2])) / ONE_Q30,
			})
	return rings
