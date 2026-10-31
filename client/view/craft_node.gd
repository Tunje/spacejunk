class_name CraftNode extends Node3D
## One unit drawn as labelled placeholder parts built from `collision` data.
## Models replace the meshes later; layout and selection stay data-driven.

const LABEL_RANGE_M := 60.0
const FLANGE_M := 0.16
const SELECT_ENERGY := 0.45
const PULSE_ENERGY := 1.6
const PULSE_RATE := 7.0
const HEAT_ENERGY := 3.0
const HEAT_COOL := Color(0.75, 0.12, 0.04)
const HEAT_HOT := Color(1.0, 0.62, 0.22)
const GROW_SECONDS := 1.4
const PLUME_LENGTH_FACTOR := 2.6

var unit_id := 0
var signature := ""
var part_transforms: Dictionary = {}
var fit_radius_m := 10.0
var heading := Quaternion.IDENTITY
var dock_blend := 0.0
var display_offset := Vector3.ZERO
## Where a docking approach began, in the host's frame.
var dock_start := Transform3D.IDENTITY
## The last docked transform, which an undock eases away from.
var undock_from := Transform3D.IDENTITY

var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var _tips: Dictionary = {}
var _plumes: Array[MeshInstance3D] = []
var _radiators: Array[int] = []
var _growing: Dictionary = {}
var _known_parts: Array[int] = []
var _selected_part := 0
var _working_part := 0
var _heat := 0.0
var _time := 0.0


static func signature_of(root: Dictionary) -> String:
	var ids: Array = [root["id"]]
	for child: Dictionary in root["children"]:
		ids.append(signature_of(child))
	return str(ids)


## Display colour from `visual.tint`, a hex string. The simulation never reads it.
static func tint_of(visual: Dictionary) -> Color:
	var tint: String = visual.get("tint", "")
	return Color.html(tint) if Color.html_is_valid(tint) else ClientTheme.OFF_WHITE


func build(id: int, root: Dictionary, modules: Dictionary) -> void:
	unit_id = id
	signature = signature_of(root)
	for child: Node in get_children():
		child.queue_free()
	_materials.clear()
	_meshes.clear()
	_tips.clear()
	_plumes.clear()
	_radiators.clear()
	part_transforms = CraftLayout.part_transforms(root, modules)
	fit_radius_m = 2.0
	_add_part(root, modules)
	var ids := Feedback.part_ids(root)
	if not _known_parts.is_empty():
		for part_id: int in ids:
			if not _known_parts.has(part_id):
				_growing[part_id] = 0.0
	_known_parts = ids
	_paint()


func highlight(part_id: int) -> void:
	_selected_part = part_id
	_paint()


## A part's tip and outward direction in the craft frame, for beams and heading.
func tip_of(part_id: int) -> Dictionary:
	return _tips.get(part_id, {})


func is_thrust_shown() -> bool:
	return not _plumes.is_empty() and _plumes[0].visible


func is_growing() -> bool:
	return not _growing.is_empty()


## Updates every effect from the unit's view.
func apply_feedback(unit: Dictionary, delta: float) -> void:
	_time += delta
	_working_part = Feedback.working_part(unit)
	_heat = Feedback.heat_level(unit)
	var thrusting := Feedback.is_thrusting(unit)
	for plume: MeshInstance3D in _plumes:
		plume.visible = thrusting
		if thrusting:
			plume.scale.y = 1.0 + 0.14 * sin(_time * 37.0 + plume.get_index())
	_advance_growth(delta)
	_paint()


func _advance_growth(delta: float) -> void:
	for id: int in _growing.keys():
		_growing[id] += delta / GROW_SECONDS
		var done: float = minf(_growing[id], 1.0)
		if _meshes.has(id):
			_meshes[id].scale = Vector3.ONE * lerpf(0.2, 1.0, ease(done, 0.4))
		if done >= 1.0:
			_growing.erase(id)


## Decides each part's glow. Selection wins, then a new part, then work, then heat.
func _paint() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * PULSE_RATE)
	for id: int in _materials:
		var material: StandardMaterial3D = _materials[id]
		var energy := 0.0
		var colour := ClientTheme.ORANGE
		if id == _selected_part:
			energy = SELECT_ENERGY
		elif _growing.has(id):
			energy = PULSE_ENERGY * (1.0 - minf(_growing[id], 1.0))
			colour = ClientTheme.GOLD
		elif id == _working_part:
			energy = PULSE_ENERGY * pulse
			colour = ClientTheme.GOLD
		elif _radiators.has(id) and _heat > 0.0:
			energy = HEAT_ENERGY * _heat
			colour = HEAT_COOL.lerp(HEAT_HOT, _heat)
		material.emission_enabled = energy > 0.0
		material.emission = colour
		material.emission_energy_multiplier = energy


func _add_part(part: Dictionary, modules: Dictionary) -> void:
	var module: Dictionary = modules[part["def"]]
	var xform: Transform3D = part_transforms[part["id"]]
	var collision: Dictionary = module["collision"]
	var centre := CraftLayout.to_metres(collision["center_mm"])
	var size := CraftLayout.to_metres(collision["size_mm"])
	fit_radius_m = maxf(fit_radius_m, (xform * centre).length() + size.length() * 0.5)

	var body := StaticBody3D.new()
	body.transform = xform
	body.set_meta("unit", unit_id)
	body.set_meta("part", part["id"])
	add_child(body)

	var material := StandardMaterial3D.new()
	material.albedo_color = CraftNode.tint_of(module["visual"])
	material.metallic = 0.25
	material.roughness = 0.55
	_materials[part["id"]] = material

	var shape := CollisionShape3D.new()
	shape.position = centre
	var mesh := MeshInstance3D.new()
	mesh.position = centre
	mesh.material_override = material
	_meshes[part["id"]] = mesh
	if Feedback.has_capability(module, "radiator"):
		_radiators.append(part["id"])
	_record_tip(part, module, xform, centre, size)
	if collision["shape"] == "cylinder":
		var cylinder_shape := CylinderShape3D.new()
		cylinder_shape.radius = size.x * 0.5
		cylinder_shape.height = size.y
		shape.shape = cylinder_shape
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = size.x * 0.5
		cylinder.bottom_radius = size.x * 0.5
		cylinder.height = size.y
		mesh.mesh = cylinder
		_add_flanges(mesh, size)
	else:
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
	body.add_child(shape)
	body.add_child(mesh)

	var label := Label3D.new()
	label.text = module["name"]
	label.position = centre
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0006
	label.font_size = 22
	label.outline_size = 8
	label.visibility_range_end = LABEL_RANGE_M
	body.add_child(label)

	for child: Dictionary in part["children"]:
		_add_part(child, modules)


## The far end of a part from its mount, which is where effects start. A root
## has no mount, so it uses its centre and faces along the nose.
func _record_tip(part: Dictionary, module: Dictionary, xform: Transform3D, centre: Vector3, size: Vector3) -> void:
	var mount := CraftLayout.find_connector(module, "mount")
	var outward := Vector3.UP
	if not mount.is_empty():
		outward = -(CraftLayout.AXES[mount["facing"]] as Vector3)
	var point := centre + outward * absf(outward.dot(size)) * 0.5
	_tips[part["id"]] = { "point": xform * point, "direction": xform.basis * outward }
	if Feedback.has_capability(module, "thruster"):
		_add_plume(xform * point, xform.basis * outward, size.x * 0.5)


func _add_plume(at: Vector3, direction: Vector3, radius_m: float) -> void:
	var length := radius_m * 2.0 * PLUME_LENGTH_FACTOR
	var cone := CylinderMesh.new()
	cone.top_radius = radius_m * 0.8
	cone.bottom_radius = 0.02
	cone.height = length
	cone.radial_segments = 12
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.emission_enabled = true
	material.emission = Color(1.0, 0.72, 0.36)
	material.emission_energy_multiplier = 5.0
	var plume := MeshInstance3D.new()
	plume.mesh = cone
	plume.material_override = material
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cone's wide end is its top, so it points back along the exhaust.
	plume.basis = Basis(CraftLayout.heading_towards(-direction))
	plume.position = at + direction * length * 0.5
	plume.visible = false
	add_child(plume)
	_plumes.append(plume)


## Dark collars at each end of a cylinder, which give the stacked KSP-style read.
func _add_flanges(parent: MeshInstance3D, size: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = ClientTheme.MID_GREY.darkened(0.35)
	material.metallic = 0.4
	material.roughness = 0.5
	for end: float in [-0.5, 0.5]:
		var collar := CylinderMesh.new()
		collar.top_radius = size.x * 0.5 + 0.04
		collar.bottom_radius = size.x * 0.5 + 0.04
		collar.height = FLANGE_M
		var ring := MeshInstance3D.new()
		ring.mesh = collar
		ring.material_override = material
		ring.position = Vector3(0, size.y * end, 0)
		parent.add_child(ring)
