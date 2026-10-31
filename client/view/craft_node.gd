class_name CraftNode extends Node3D
## One unit drawn as labelled placeholder parts built from `collision` data.
## Models replace the meshes later; layout and selection stay data-driven.

const LABEL_RANGE_M := 60.0
const FLANGE_M := 0.16

var unit_id := 0
var signature := ""
var part_transforms: Dictionary = {}
var fit_radius_m := 10.0
var heading := Quaternion.IDENTITY
var dock_blend := 0.0
## Where a docking approach began, in the host's frame.
var dock_start := Transform3D.IDENTITY
## The last docked transform, which an undock eases away from.
var undock_from := Transform3D.IDENTITY

var _materials: Dictionary = {}


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
	part_transforms = CraftLayout.part_transforms(root, modules)
	fit_radius_m = 2.0
	_add_part(root, modules)


func highlight(part_id: int) -> void:
	for id: int in _materials:
		var material: StandardMaterial3D = _materials[id]
		material.emission_enabled = id == part_id
		material.emission = ClientTheme.ORANGE
		material.emission_energy_multiplier = 0.45


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
