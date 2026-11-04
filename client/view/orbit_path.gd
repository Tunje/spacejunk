class_name OrbitPath extends RefCounted
## Orbit and drift points for drawing. Everything here is 64-bit float, as contracts
## section 7 asks: an orbit is drawn from its integer record the way position_float
## in tests/sim/kernel/test_orbit_math.gd does, never with Godot's 32-bit Vector3.
## Points stay in world millimetres as PackedFloat64Array triples until they are
## made relative to the camera centre, which is the only place Vector3 appears.

## Binary angle units per turn and the Q30 one, as OrbitMath stores them.
const TURN := 281474976710656.0
const ONE := 1073741824.0
const SUB_TICKS := 65536.0
const MM_TO_M := 0.001
const KEPLER_STEPS := 50


## Position in mm relative to the parent at a tick, as [x, y, z].
static func position(orbit: Dictionary, tick: float) -> PackedFloat64Array:
	var e := float(orbit["e_q30"]) / ONE
	var big_e := OrbitPath._eccentric_anomaly(OrbitPath.mean_anomaly(orbit, tick), e)
	var x := float(orbit["a_mm"]) * (cos(big_e) - e)
	var y := float(orbit["b_mm"]) * sin(big_e)
	var p: Array = orbit["p_q30"]
	var q: Array = orbit["q_q30"]
	var out := PackedFloat64Array()
	for axis in 3:
		out.append((x * float(p[axis]) + y * float(q[axis])) / ONE)
	return out


static func period_ticks(orbit: Dictionary) -> float:
	return float(orbit["period_subticks"]) / SUB_TICKS


## Mean anomaly in radians, 0 to TAU, at a tick.
static func mean_anomaly(orbit: Dictionary, tick: float) -> float:
	var period := OrbitPath.period_ticks(orbit)
	var dt := tick - float(orbit["epoch_tick"])
	return fposmod(float(orbit["m0_angle"]) / TURN * TAU + TAU * fposmod(dt, period) / period, TAU)


static func _eccentric_anomaly(m: float, e: float) -> float:
	var big_e := m + 0.85 * e * signf(sin(m))
	for i in KEPLER_STEPS:
		big_e -= (big_e - e * sin(big_e) - m) / (1.0 - e * cos(big_e))
	return big_e


## [periapsis, apoapsis] distances from the parent's centre, in mm.
static func apsides_mm(orbit: Dictionary) -> PackedFloat64Array:
	var a := float(orbit["a_mm"])
	var e := float(orbit["e_q30"]) / ONE
	return PackedFloat64Array([a * (1.0 - e), a * (1.0 + e)])


## Whole ticks from `tick` until the orbit next reaches mean anomaly `target`:
## 0 for periapsis, PI for apoapsis. At least 1, since a burn needs a future tick.
static func ticks_until(orbit: Dictionary, tick: int, target: float) -> int:
	var to_go := fposmod(target - OrbitPath.mean_anomaly(orbit, float(tick)), TAU)
	return maxi(1, roundi(to_go / TAU * OrbitPath.period_ticks(orbit)))


## One whole orbit from `tick`, as `count` + 1 points in world mm, the last closing
## the loop. `parent_world` is the parent body's world_mm.
static func loop(orbit: Dictionary, parent_world: Array, tick: int, count: int) -> Array[PackedFloat64Array]:
	var points: Array[PackedFloat64Array] = []
	var period := OrbitPath.period_ticks(orbit)
	for index in count + 1:
		points.append(OrbitPath.shifted(OrbitPath.position(orbit, tick + period * index / count), parent_world))
	return points


## A point in some place's coordinates moved into the world by that place's world_mm.
static func shifted(point: Variant, base_world: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for axis in 3:
		out.append(float(point[axis]) + float(base_world[axis]))
	return out


## A straight drift from `start` (world mm) at `vel_um_s`, for `seconds`.
static func drift(start: PackedFloat64Array, vel_um_s: Array, seconds: float, count: int) -> Array[PackedFloat64Array]:
	var points: Array[PackedFloat64Array] = []
	for index in count + 1:
		var t := seconds * index / count
		var point := PackedFloat64Array()
		for axis in 3:
			point.append(start[axis] + float(vel_um_s[axis]) * 0.001 * t)
		points.append(point)
	return points


## Seconds until a drift from `local` (mm, in the frame) at `vel_um_s` passes the
## frame's radius, or -1 if it never does (no drift).
static func seconds_to_edge(local: Array, vel_um_s: Array, radius_mm: int) -> float:
	var v := PackedFloat64Array()
	var p := PackedFloat64Array()
	for axis in 3:
		v.append(float(vel_um_s[axis]) * 0.001)
		p.append(float(local[axis]))
	var a := v[0] * v[0] + v[1] * v[1] + v[2] * v[2]
	if a <= 0.0:
		return -1.0
	var b := 2.0 * (p[0] * v[0] + p[1] * v[1] + p[2] * v[2])
	var c := p[0] * p[0] + p[1] * p[1] + p[2] * p[2] - float(radius_mm) * float(radius_mm)
	return maxf(0.0, (-b + sqrt(maxf(0.0, b * b - 4.0 * a * c))) / (2.0 * a))


## A world point relative to a centre, in metres. Both are 64-bit until the
## difference is taken, so nothing far from the origin loses precision.
static func relative_m(point: PackedFloat64Array, centre: Array) -> Vector3:
	return Vector3(
		(point[0] - float(centre[0])) * MM_TO_M,
		(point[1] - float(centre[1])) * MM_TO_M,
		(point[2] - float(centre[2])) * MM_TO_M)
