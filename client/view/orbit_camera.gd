class_name OrbitCamera extends Camera3D
## Orbits a pivot, which the local view keeps on the focus.

const MIN_DISTANCE_M := 6.0
const MAX_DISTANCE_M := 120000.0
const ZOOM_STEP := 1.18
const ZOOM_RATE := 9.0
const PITCH_LIMIT := 1.5
const DRAG_RADIANS_PER_PIXEL := 0.006
const FAR_M := 400000.0
const UP_RATE := 3.0

var pivot := Vector3.ZERO
var yaw := 0.6
var pitch := -0.32
var distance_m := 60.0
var target_distance_m := 60.0
## The camera's up: world +Y in open space, the local vertical near a body. Yaw
## and pitch turn about it, so the horizon stays level on a planet.
var up_dir := Vector3.UP


func _ready() -> void:
	near = 0.3
	far = FAR_M
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
	var tilt := Basis(Quaternion(Vector3.UP, up_dir.normalized())) if not up_dir.is_equal_approx(Vector3.UP) else Basis.IDENTITY
	look_at_from_position(pivot + tilt * offset, pivot, up_dir)


## Eases the up direction towards `wanted`, and makes the far plane reach `far_m`.
func settle_up(wanted: Vector3, far_m: float, delta: float) -> void:
	up_dir = up_dir.slerp(wanted.normalized(), 1.0 - exp(-UP_RATE * delta)).normalized()
	far = maxf(FAR_M, far_m)
