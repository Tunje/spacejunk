class_name BeamNode extends MeshInstance3D
## A straight glowing beam with a bright point where it lands.

const COLOURS: Dictionary = {
	Feedback.BEAM_MINE: Color(1.0, 0.45, 0.12),
	Feedback.BEAM_SCAN: Color(0.55, 0.85, 1.0),
}
const WIDTHS_M: Dictionary = { Feedback.BEAM_MINE: 0.28, Feedback.BEAM_SCAN: 0.08 }
const ENERGY := 7.0
const IMPACT_SCALE := 6.0

var length_m := 0.0
var _material := StandardMaterial3D.new()
var _impact := MeshInstance3D.new()


func _init() -> void:
	var beam := CylinderMesh.new()
	beam.top_radius = 1.0
	beam.bottom_radius = 1.0
	beam.height = 1.0
	beam.radial_segments = 8
	mesh = beam
	_material.albedo_color = Color.BLACK
	_material.emission_enabled = true
	_material.emission_energy_multiplier = ENERGY
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var point := SphereMesh.new()
	point.radius = 1.0
	point.height = 2.0
	_impact.mesh = point
	_impact.material_override = _material
	_impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_impact)
	visible = false


## Stretches the beam between two render-space points.
func aim(from: Vector3, to: Vector3, kind: String, time: float) -> void:
	var along := to - from
	length_m = along.length()
	if length_m <= 0.001:
		visible = false
		return
	visible = true
	_material.emission = COLOURS[kind]
	var width: float = WIDTHS_M[kind] * (1.0 + 0.18 * sin(time * 41.0))
	var turn := CraftLayout.heading_towards(along)
	transform = Transform3D(Basis(turn) * Basis.from_scale(Vector3(width, length_m, width)), from + along * 0.5)
	# The impact is a child of a stretched node, so undo that stretch here.
	_impact.position = Vector3(0, 0.5, 0)
	_impact.scale = Vector3(IMPACT_SCALE, IMPACT_SCALE * width / length_m, IMPACT_SCALE)
