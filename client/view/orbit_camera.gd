class_name OrbitCamera extends Camera3D
## Orbits a pivot, which the local view keeps on the focus.

const MIN_DISTANCE_M := 6.0
const MAX_DISTANCE_M := 120000.0
const ZOOM_STEP := 1.18
const ZOOM_RATE := 9.0
const PITCH_LIMIT := 1.5
const DRAG_RADIANS_PER_PIXEL := 0.006

var pivot := Vector3.ZERO
var yaw := 0.6
var pitch := -0.32
var distance_m := 60.0
var target_distance_m := 60.0


func _ready() -> void:
	near = 0.3
	far = 400000.0
	fov = 55.0


func orbit(pixels: Vector2) -> void:
	yaw -= pixels.x * DRAG_RADIANS_PER_PIXEL
	pitch = clampf(pitch - pixels.y * DRAG_RADIANS_PER_PIXEL, -PITCH_LIMIT, PITCH_LIMIT)


func zoom(steps: float) -> void:
	target_distance_m = clampf(target_distance_m * pow(ZOOM_STEP, steps), MIN_DISTANCE_M, MAX_DISTANCE_M)


func frame_radius(radius_m: float) -> void:
	target_distance_m = clampf(radius_m * 3.2, MIN_DISTANCE_M, MAX_DISTANCE_M)


func update_view(delta: float) -> void:
	distance_m = lerpf(distance_m, target_distance_m, 1.0 - exp(-ZOOM_RATE * delta))
	var offset := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, distance_m)
	look_at_from_position(pivot + offset, pivot)
