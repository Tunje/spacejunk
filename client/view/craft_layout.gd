class_name CraftLayout extends RefCounted
## Places parts from connector data alone (contracts section 10): mated
## connectors have opposite facings and equal ups. All transforms are in metres.

const MM_TO_M := 0.001
const AXES: Dictionary = {
	"+x": Vector3.RIGHT, "-x": Vector3.LEFT,
	"+y": Vector3.UP, "-y": Vector3.DOWN,
	"+z": Vector3.BACK, "-z": Vector3.FORWARD,
}
## Half a turn about a connector's up axis, which reverses its facing.
const FLIP := Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)), Vector3.ZERO)


static func to_metres(mm: Array) -> Vector3:
	return Vector3(mm[0], mm[1], mm[2]) * MM_TO_M


## A connector's frame in its module: +Z along facing, +Y along up.
static func connector_transform(connector: Dictionary) -> Transform3D:
	var facing: Vector3 = AXES[connector["facing"]]
	var up: Vector3 = AXES[connector["up"]]
	return Transform3D(Basis(up.cross(facing), up, facing), to_metres(connector["pos_mm"]))


## The child module's transform in its parent's frame.
static func mate(parent_connector: Dictionary, child_connector: Dictionary) -> Transform3D:
	return connector_transform(parent_connector) * FLIP * connector_transform(child_connector).affine_inverse()


static func find_connector(module: Dictionary, connector_id: String) -> Dictionary:
	for connector: Dictionary in module["connectors"]:
		if connector["id"] == connector_id:
			return connector
	return {}


static func dock_connector(module: Dictionary) -> Dictionary:
	for connector: Dictionary in module["connectors"]:
		if connector["type"] == "dock":
			return connector
	return {}


## Maps every part ID in a tree to its transform in the craft's frame.
static func part_transforms(root: Dictionary, modules: Dictionary) -> Dictionary:
	var transforms: Dictionary = {}
	_collect(root, Transform3D.IDENTITY, modules, transforms)
	return transforms


static func _collect(part: Dictionary, xform: Transform3D, modules: Dictionary, transforms: Dictionary) -> void:
	transforms[part["id"]] = xform
	var module: Dictionary = modules[part["def"]]
	for child: Dictionary in part["children"]:
		var child_module: Dictionary = modules[child["def"]]
		var joint := mate(
			find_connector(module, child["parent_connector"]),
			find_connector(child_module, child["connector"]))
		_collect(child, xform * joint, modules, transforms)


## The docking craft's root, given where the target port sits in world space
## and the two dock connectors.
static func docked_root(target_port_world: Transform3D, target_connector: Dictionary,
		own_connector: Dictionary, own_port_in_craft: Transform3D) -> Transform3D:
	return target_port_world * mate(target_connector, own_connector) * own_port_in_craft.affine_inverse()


## Rotation taking a craft's nose (+Y) onto `direction`.
static func heading_towards(direction: Vector3) -> Quaternion:
	var aim := direction.normalized()
	if aim.dot(Vector3.UP) < -0.9999:
		return Quaternion(Vector3.RIGHT, PI)
	return Quaternion(Vector3.UP, aim)
