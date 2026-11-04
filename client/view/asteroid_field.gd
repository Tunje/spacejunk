class_name AsteroidField extends Node3D
## Decorative rocks around the real asteroids, generated from the view's seed.
## They are client-only (contracts section 7): nothing selects or collides with
## them. Each variant is one MultiMesh, so large fields stay cheap.

const COUNT := 1500
const MAX_COUNT := 6000
const HALF_WIDTH_M := 16000.0
const HALF_HEIGHT_M := 3500.0
const MIN_SIZE_M := 4.0
const MAX_SIZE_M := 90.0
const CLEARANCE_M := 500.0
const REACH_MARGIN := 1.25

## Forces the rock count for tools/frametime.ps1. 0 means the normal count.
static var count_override := 0

var anchor_mm: Array = [0, 0, 0]
var instance_total := 0


## The anchor in the world for this view: the rocks share a frame that may move,
## so the local anchor gets the frame's offset of the first rock found.
func world_anchor(view: Dictionary) -> Array:
	var ids: Array = view["bodies"].keys()
	ids.sort()
	for id: int in ids:
		if view["bodies"][id]["kind"] == "asteroid":
			return WorldPosition.local_to_world(view["bodies"][id], anchor_mm)
	return anchor_mm


## The middle of the targetable asteroids, in sim millimetres.
static func anchor_of(view: Dictionary) -> Array:
	var total := [0, 0, 0]
	var found := 0
	for id: int in view["bodies"]:
		var body: Dictionary = view["bodies"][id]
		if body["kind"] == "asteroid":
			found += 1
			for axis in range(3):
				total[axis] += body["pos_mm"][axis]
	if found == 0:
		return total
	return [total[0] / found, total[1] / found, total[2] / found]


## Rocks to keep out of the way of, as { at_m, radius_m } relative to the anchor.
static func keep_clear(view: Dictionary, anchor: Array) -> Array[Dictionary]:
	var clear: Array[Dictionary] = []
	for id: int in view["bodies"]:
		var body: Dictionary = view["bodies"][id]
		if body["kind"] == "asteroid":
			clear.append({
				"at_m": FloatingOrigin.relative_m(body["pos_mm"], body["pos_mm"], anchor, anchor, 0.0),
				"radius_m": body["radius_mm"] * FloatingOrigin.MM_TO_M,
			})
	for id: int in view["units"]:
		if not view["units"][id].get("orbit", {}).is_empty():
			continue
		var pos: Array = view["units"][id]["pos_mm"]
		clear.append({ "at_m": FloatingOrigin.relative_m(pos, pos, anchor, anchor, 0.0), "radius_m": 300.0 })
	return clear


## Half the field's width, grown so it reaches everything worth keeping clear of.
static func half_width_for(clear: Array[Dictionary]) -> float:
	var reach := HALF_WIDTH_M
	for entry: Dictionary in clear:
		reach = maxf(reach, (entry["at_m"] as Vector3).length() * REACH_MARGIN)
	return reach


## Rock count that keeps the default density across a wider field.
static func count_for(half_width_m: float) -> int:
	if count_override > 0:
		return count_override
	var scale_up := half_width_m / HALF_WIDTH_M
	return mini(roundi(COUNT * scale_up * scale_up), MAX_COUNT)


## One Array of Transform3D per mesh variant. Same seed, same field.
static func generate(seed_value: int, clear: Array[Dictionary], count: int = COUNT, half_width_m: float = HALF_WIDTH_M) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var groups: Array = []
	for variant in range(RockMesh.VARIANTS):
		groups.append([])
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 4:
		attempts += 1
		var at := Vector3(
			rng.randf_range(-half_width_m, half_width_m),
			rng.randfn(0.0, HALF_HEIGHT_M * 0.5),
			rng.randf_range(-half_width_m, half_width_m))
		var size := lerpf(MIN_SIZE_M, MAX_SIZE_M, pow(rng.randf(), 4.0))
		var spin := Basis(Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized(), rng.randf() * TAU)
		var variant := rng.randi_range(0, RockMesh.VARIANTS - 1)
		if _is_clear(at, size, clear):
			groups[variant].append(Transform3D(spin.scaled(Vector3.ONE * size), at))
			placed += 1
	return groups


static func _is_clear(at: Vector3, size: float, clear: Array[Dictionary]) -> bool:
	for entry: Dictionary in clear:
		if at.distance_to(entry["at_m"]) < entry["radius_m"] + size + CLEARANCE_M:
			return false
	return true


func build(view: Dictionary) -> void:
	anchor_mm = AsteroidField.anchor_of(view)
	var clear := AsteroidField.keep_clear(view, anchor_mm)
	var half_width := AsteroidField.half_width_for(clear)
	var groups := AsteroidField.generate(view["seed"], clear, AsteroidField.count_for(half_width), half_width)
	instance_total = 0
	for variant in range(groups.size()):
		var transforms: Array = groups[variant]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = RockMesh.get_mesh(variant, RockMesh.SIMPLE)
		multimesh.instance_count = transforms.size()
		for index in range(transforms.size()):
			multimesh.set_instance_transform(index, transforms[index])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = RockMesh.material()
		# Scenery must not eclipse the player's craft.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		instance_total += transforms.size()
