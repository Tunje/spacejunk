class_name ModelLook extends RefCounted
## Makes generated models read well in space. The image-to-3d models come with full
## metallic maps (factor 1.0, the map alone sets it), and a fully metallic surface
## has no diffuse colour: lit only by reflections of a black sky, its shaded side
## renders pure black, as starter_hull's gold foil band did in B9. Capping the metal
## gives every surface some diffuse colour for the scene's ambient light to show,
## while the sunlit highlight barely changes. Visual only: nothing in sim/ reads it.

## The most metallic any generated surface may be. Godot multiplies the metallic
## map by this, so it scales the whole map: bare metal ends up here, paint stays put.
const METALLIC_CAP := 0.55
## Materials keep 32-bit floats, so a capped one reads back a hair over the cap.
const TOLERANCE := 0.001


## Loaded models, kept so a craft rebuilt later doesn't decode the model and its
## textures again once the last instance is gone.
static var _scenes: Dictionary = {}


## Loads a generated model and tames its materials. Null if the path doesn't load.
static func instantiate(path: String) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	var scene: PackedScene = _scenes[path]
	if scene == null:
		return null
	var root := scene.instantiate() as Node3D
	apply(root)
	return root


## Caps metal on every material under `root`, mesh and override alike. Materials are
## shared through the imported scene's cache, so each is duplicated before it changes.
static func apply(root: Node) -> void:
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node: Node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var source := mi.get_surface_override_material(surface)
			if source == null:
				source = mi.mesh.surface_get_material(surface)
			var tamed := tame(source)
			if tamed != null:
				mi.set_surface_override_material(surface, tamed)


## A copy of `material` with its metal capped, or null if it needs no change (or
## isn't a BaseMaterial3D).
static func tame(material: Material) -> BaseMaterial3D:
	var base := material as BaseMaterial3D
	if base == null:
		return null
	if base.metallic <= METALLIC_CAP + TOLERANCE:
		return null
	var copy := base.duplicate() as BaseMaterial3D
	copy.metallic = METALLIC_CAP
	return copy
