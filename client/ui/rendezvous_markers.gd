class_name RendezvousMarkers extends Control
## The rendezvous target in the local view (D46): a bracket round the target, and
## round the craft being flown, where its motion relative to the target points
## ("toward", a ring with a cross) and away from it (a plain ring). The relative
## velocity is the Sim's (RendezvousLogic); nothing here is worked out by the client.

const BRACKET_PX := 22.0
const BRACKET_ARM_PX := 8.0
const MARKER_PX := 9.0
## How far from the craft, in metres, a direction is placed to find its screen spot.
const DIRECTION_REACH_M := 50.0
const TARGET_COLOUR := Color(0.55, 0.85, 1.0)
const TOWARD_COLOUR := Color(0.95, 0.78, 0.2)

var local_view: LocalView
var flight: FlightScreen


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


## Screen spots for the drawing, or {} when there is nothing to draw:
## { target, toward, away }, each a Vector2 or absent when behind the camera.
func spots() -> Dictionary:
	# Only while flying, when the flight screen keeps the relative state fresh.
	if local_view == null or flight == null or not local_view.visible or not flight.visible or flight.target_id == 0:
		return {}
	var camera: Camera3D = local_view.camera
	var found: Dictionary = {}
	var target: Node3D = local_view._node_of(flight.target_kind, flight.target_id)
	if target != null and not camera.is_position_behind(target.global_position):
		found["target"] = camera.unproject_position(target.global_position)
	var craft: Node3D = local_view._node_of("unit", flight.unit_id())
	var relative: Array = flight.rendezvous.get("rel_vel_um_s", [])
	if craft != null and relative.size() == 3:
		# The Sim gives the target's velocity less the craft's; the craft moves the other way.
		var motion := -Vector3(float(relative[0]), float(relative[1]), float(relative[2]))
		if motion.length() > 0.0:
			var reach := motion.normalized() * DIRECTION_REACH_M
			for pair: Array in [["toward", reach], ["away", -reach]]:
				var point: Vector3 = craft.global_position + pair[1]
				if not camera.is_position_behind(point):
					found[pair[0]] = camera.unproject_position(point)
	return found


func _draw() -> void:
	var found := spots()
	if found.has("target"):
		_bracket(found["target"])
	if found.has("toward"):
		draw_arc(found["toward"], MARKER_PX, 0.0, TAU, 24, TOWARD_COLOUR, 2.0)
		draw_line(found["toward"] - Vector2(MARKER_PX, 0), found["toward"] + Vector2(MARKER_PX, 0), TOWARD_COLOUR, 2.0)
		draw_line(found["toward"] - Vector2(0, MARKER_PX), found["toward"] + Vector2(0, MARKER_PX), TOWARD_COLOUR, 2.0)
	if found.has("away"):
		draw_arc(found["away"], MARKER_PX, 0.0, TAU, 24, TOWARD_COLOUR, 2.0)


## Four corner arms round a point.
func _bracket(at: Vector2) -> void:
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var tip := at + corner * BRACKET_PX
		draw_line(tip, tip - Vector2(corner.x, 0) * BRACKET_ARM_PX, TARGET_COLOUR, 2.0)
		draw_line(tip, tip - Vector2(0, corner.y) * BRACKET_ARM_PX, TARGET_COLOUR, 2.0)
