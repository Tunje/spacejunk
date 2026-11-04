class_name OrbitDiagram extends Control
## A flat, to-scale picture of an orbit and the orbit after a planned burn, drawn
## in the plane of the current orbit with the parent body at the centre. The map's
## log scale bends an ellipse out of shape, so orbits are shown here instead.
## Points arrive in 64-bit world mm and are only made small floats once relative
## to the parent and projected.

const HEIGHT_PX := 230.0
const MARGIN := 0.08
const BACKGROUND := Color(0.06, 0.07, 0.09)
const BODY_COLOUR := Color(0.35, 0.34, 0.32)
const PATH_COLOUR := Color(0.62, 0.65, 0.7)
const PLAN_COLOUR := Color(0.95, 0.42, 0.08)
const SHIP_COLOUR := Color(1.0, 1.0, 1.0)
const MARK_PX := 6.0

var body_radius_mm := 0.0
var body_name := ""
## Each a list of [u, v] in mm, in the current orbit's plane, relative to the parent.
var current: PackedVector2Array = []
var planned: PackedVector2Array = []
var ship := Vector2.ZERO
var marker := Vector2.ZERO
var has_marker := false
var _scale := 1.0


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT_PX)


## Projects world-mm points onto the plane of `orbit` (its P and Q directions),
## relative to the parent at `parent_world`.
func show_orbits(orbit: Dictionary, parent_world: Array, radius_mm: int, name: String,
		current_path: Array[PackedFloat64Array], planned_path: Array[PackedFloat64Array],
		ship_point: PackedFloat64Array, marker_point: PackedFloat64Array) -> void:
	body_radius_mm = float(radius_mm)
	body_name = name
	var axes := OrbitDiagram.plane_axes(orbit)
	current = OrbitDiagram.project(current_path, parent_world, axes)
	planned = OrbitDiagram.project(planned_path, parent_world, axes)
	ship = OrbitDiagram.project([ship_point], parent_world, axes)[0] if not ship_point.is_empty() else Vector2.ZERO
	has_marker = not marker_point.is_empty()
	if has_marker:
		marker = OrbitDiagram.project([marker_point], parent_world, axes)[0]
	queue_redraw()


## The orbit's P and Q directions as unit float vectors.
static func plane_axes(orbit: Dictionary) -> Array[PackedFloat64Array]:
	var axes: Array[PackedFloat64Array] = []
	for key: String in ["p_q30", "q_q30"]:
		var axis := PackedFloat64Array()
		for value: Variant in orbit[key]:
			axis.append(float(value) / OrbitPath.ONE)
		axes.append(axis)
	return axes


## Points relative to the parent, in mm, as coordinates along the two axes. The
## subtraction is done in 64 bits before anything becomes a 32-bit Vector2.
static func project(points: Array, parent_world: Array, axes: Array[PackedFloat64Array]) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Variant in points:
		var rel := PackedFloat64Array()
		for axis in 3:
			rel.append(float(point[axis]) - float(parent_world[axis]))
		var u := rel[0] * axes[0][0] + rel[1] * axes[0][1] + rel[2] * axes[0][2]
		var v := rel[0] * axes[1][0] + rel[1] * axes[1][1] + rel[2] * axes[1][2]
		out.append(Vector2(u, -v))
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	var reach := body_radius_mm
	for points: PackedVector2Array in [current, planned]:
		for point: Vector2 in points:
			reach = maxf(reach, point.length())
	reach = maxf(reach, ship.length())
	if reach <= 0.0:
		return
	_scale = minf(size.x, size.y) * (0.5 - MARGIN) / reach
	var centre := size / 2.0
	draw_circle(centre, maxf(2.0, body_radius_mm * _scale), BODY_COLOUR)
	_polyline(current, centre, PATH_COLOUR)
	_polyline(planned, centre, PLAN_COLOUR)
	draw_circle(centre + ship * _scale, 3.5, SHIP_COLOUR)
	if has_marker:
		var at := centre + marker * _scale
		draw_line(at - Vector2(MARK_PX, MARK_PX), at + Vector2(MARK_PX, MARK_PX), PLAN_COLOUR, 2.0)
		draw_line(at - Vector2(MARK_PX, -MARK_PX), at + Vector2(MARK_PX, -MARK_PX), PLAN_COLOUR, 2.0)
	var font := get_theme_default_font()
	draw_string(font, Vector2(8, size.y - 8), "%s, to scale: %s across" % [body_name, OrderText.metres(roundi(2.0 * reach))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PATH_COLOUR)


func _polyline(points: PackedVector2Array, centre: Vector2, colour: Color) -> void:
	if points.size() < 2:
		return
	var placed := PackedVector2Array()
	for point: Vector2 in points:
		placed.append(centre + point * _scale)
	draw_polyline(placed, colour, 1.5, true)
