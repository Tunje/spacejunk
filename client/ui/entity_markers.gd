class_name EntityMarkers extends Control
## Screen markers and names for objects too small to see or click, drawn on the
## overlay. Clicks that miss every 3D shape fall back to the nearest marker.

const PICK_RADIUS_PX := 16.0
const HIDE_ABOVE_PX := 60.0
const DIAMOND_PX := 6.0
const FONT_SIZE := 14

var local_view: LocalView
var _entries: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func update_entities() -> void:
	_entries.clear()
	var view := local_view.bridge.current_view
	for id: int in local_view.bodies:
		var body: BodyNode = local_view.bodies[id]
		var label := "Star" if body.kind == "star" else "Asteroid %d" % id
		_add_entry("body", id, body, body.scale.x, label)
	for id: int in local_view.crafts:
		var craft: CraftNode = local_view.crafts[id]
		_add_entry("unit", id, craft, craft.fit_radius_m, view["units"][id]["name"])
	queue_redraw()


func pick(screen: Vector2) -> Dictionary:
	return EntityMarkers.pick_entry(_entries, screen)


static func pick_entry(entries: Array[Dictionary], screen: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_gap := PICK_RADIUS_PX
	for entry: Dictionary in entries:
		var gap: float = entry["at"].distance_to(screen)
		if gap <= best_gap:
			best_gap = gap
			best = { "kind": entry["kind"], "id": entry["id"], "part": 0 }
	return best


func _add_entry(kind: String, id: int, node: Node3D, radius_m: float, label: String) -> void:
	var camera := local_view.camera
	if camera.is_position_behind(node.position):
		return
	var gap := camera.global_position.distance_to(node.position)
	var pixels := radius_m / maxf(gap, 0.01) * get_viewport_rect().size.y
	if pixels > HIDE_ABOVE_PX:
		return
	_entries.append({
		"kind": kind, "id": id, "label": label, "at": camera.unproject_position(node.position),
		"selected": local_view.selected_kind == kind and local_view.selected_id == id,
	})


func _draw() -> void:
	EntityMarkers.draw_entries(self, _entries)


static func draw_entries(canvas: CanvasItem, entries: Array[Dictionary]) -> void:
	var font := ThemeDB.fallback_font
	var used: Array[Rect2] = []
	for entry: Dictionary in EntityMarkers.ordered_for_labels(entries):
		var at: Vector2 = entry["at"]
		var colour: Color = ClientTheme.ORANGE if entry["selected"] else ClientTheme.OFF_WHITE
		var diamond := PackedVector2Array([
			at + Vector2(0, -DIAMOND_PX), at + Vector2(DIAMOND_PX, 0),
			at + Vector2(0, DIAMOND_PX), at + Vector2(-DIAMOND_PX, 0), at + Vector2(0, -DIAMOND_PX),
		])
		canvas.draw_polyline(diamond, colour, 1.5, true)
		var size := font.get_string_size(entry["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var area := Rect2(at + Vector2(DIAMOND_PX + 5, -FONT_SIZE), size)
		if not used.any(func(other: Rect2) -> bool: return other.intersects(area)):
			used.append(area)
			canvas.draw_string(font, at + Vector2(DIAMOND_PX + 5, 5), entry["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)


## Selected entities first, so their names win when labels would overlap.
static func ordered_for_labels(entries: Array[Dictionary]) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = entries.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["selected"] and not b["selected"])
	return ordered
