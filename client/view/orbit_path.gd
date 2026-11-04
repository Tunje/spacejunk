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
const HYPERBOLIC_STEPS := 60
## How far out an open path is drawn when its parent has no sphere of influence,
## in periapsis distances.
const OPEN_REACH := 12.0


## An escape path (A12): `a_mm` is its positive semi-axis, e is above 1, and the
## mean anomaly grows without wrapping from `m0_rad` at `motion_q60` per tick.
static func is_open(orbit: Dictionary) -> bool:
	return orbit.get("hyperbolic", false)


## Position in mm relative to the parent at a tick, as [x, y, z].
static func position(orbit: Dictionary, tick: float) -> PackedFloat64Array:
	var e := float(orbit["e_q30"]) / ONE
	if OrbitPath.is_open(orbit):
		return OrbitPath._at_h(orbit, OrbitPath._hyperbolic_anomaly(OrbitPath.mean_anomaly(orbit, tick), e))
	var big_e := OrbitPath._eccentric_anomaly(OrbitPath.mean_anomaly(orbit, tick), e)
	var x := float(orbit["a_mm"]) * (cos(big_e) - e)
	var y := float(orbit["b_mm"]) * sin(big_e)
	return OrbitPath._place(orbit, x, y)


static func _place(orbit: Dictionary, x: float, y: float) -> PackedFloat64Array:
	var p: Array = orbit["p_q30"]
	var q: Array = orbit["q_q30"]
	var out := PackedFloat64Array()
	for axis in 3:
		out.append((x * float(p[axis]) + y * float(q[axis])) / ONE)
	return out


## A point on an escape path at hyperbolic anomaly H.
static func _at_h(orbit: Dictionary, big_h: float) -> PackedFloat64Array:
	var e := float(orbit["e_q30"]) / ONE
	return OrbitPath._place(orbit, float(orbit["a_mm"]) * (e - cosh(big_h)), float(orbit["b_mm"]) * sinh(big_h))


## e sinh H - H = M by Newton, as the kernel's float reference does.
static func _hyperbolic_anomaly(m: float, e: float) -> float:
	var big_h := signf(m) * log(2.0 * absf(m) / e + 1.8)
	for i in HYPERBOLIC_STEPS:
		big_h -= (e * sinh(big_h) - big_h - m) / (e * cosh(big_h) - 1.0)
	return big_h


## Mean motion in radians per tick of an escape path.
static func motion(orbit: Dictionary) -> float:
	return float(orbit["motion_q60"]) / pow(2.0, 60)


static func period_ticks(orbit: Dictionary) -> float:
	return float(orbit["period_subticks"]) / SUB_TICKS


## Mean anomaly in radians at a tick: 0 to TAU round an orbit, and unbounded on
## an escape path, negative before periapsis.
static func mean_anomaly(orbit: Dictionary, tick: float) -> float:
	if OrbitPath.is_open(orbit):
		return float(orbit["m0_rad"]) / ONE + (tick - float(orbit["epoch_tick"])) * OrbitPath.motion(orbit)
	var period := OrbitPath.period_ticks(orbit)
	var dt := tick - float(orbit["epoch_tick"])
	return fposmod(float(orbit["m0_angle"]) / TURN * TAU + TAU * fposmod(dt, period) / period, TAU)


static func _eccentric_anomaly(m: float, e: float) -> float:
	var big_e := m + 0.85 * e * signf(sin(m))
	for i in KEPLER_STEPS:
		big_e -= (big_e - e * sin(big_e) - m) / (1.0 - e * cos(big_e))
	return big_e


## [periapsis, apoapsis] distances from the parent's centre, in mm. An escape
## path has no apoapsis, given as INF.
static func apsides_mm(orbit: Dictionary) -> PackedFloat64Array:
	var a := float(orbit["a_mm"])
	var e := float(orbit["e_q30"]) / ONE
	if OrbitPath.is_open(orbit):
		return PackedFloat64Array([a * (e - 1.0), INF])
	return PackedFloat64Array([a * (1.0 - e), a * (1.0 + e)])


## Whole ticks from `tick` until the orbit next reaches mean anomaly `target`:
## 0 for periapsis, PI for apoapsis. At least 1, since a burn needs a future tick.
## On an escape path only periapsis can be aimed for, and only while it is ahead:
## -1 means never.
static func ticks_until(orbit: Dictionary, tick: int, target: float) -> int:
	if OrbitPath.is_open(orbit):
		var m := OrbitPath.mean_anomaly(orbit, float(tick))
		if target != 0.0 or m >= 0.0:
			return -1
		return maxi(1, roundi(-m / OrbitPath.motion(orbit)))
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


## The path ahead from `tick`, as `count` + 1 world-mm points: one whole loop for
## an orbit, or for an escape path the branch out to `reach_mm` from the parent,
## its sphere of influence or else OPEN_REACH periapsis distances.
static func ahead(orbit: Dictionary, parent_world: Array, tick: int, count: int, reach_mm: float) -> Array[PackedFloat64Array]:
	if not OrbitPath.is_open(orbit):
		return OrbitPath.loop(orbit, parent_world, tick, count)
	var e := float(orbit["e_q30"]) / ONE
	var h_now := OrbitPath._hyperbolic_anomaly(OrbitPath.mean_anomaly(orbit, float(tick)), e)
	var h_end := maxf(h_now, OrbitPath._h_at_distance(orbit, OrbitPath.open_reach(orbit, reach_mm)))
	var points: Array[PackedFloat64Array] = []
	for index in count + 1:
		points.append(OrbitPath.shifted(OrbitPath._at_h(orbit, lerpf(h_now, h_end, float(index) / count)), parent_world))
	return points


static func open_reach(orbit: Dictionary, reach_mm: float) -> float:
	return reach_mm if reach_mm > 0.0 else OrbitPath.apsides_mm(orbit)[0] * OPEN_REACH


## Hyperbolic anomaly where r = a (e cosh H - 1) reaches `distance_mm`, outbound.
static func _h_at_distance(orbit: Dictionary, distance_mm: float) -> float:
	var e := float(orbit["e_q30"]) / ONE
	return acosh(maxf(1.0, (distance_mm / float(orbit["a_mm"]) + 1.0) / e))


## Ticks from `tick` until an escape path reaches `reach_mm`, for predict's span.
static func ticks_to_reach(orbit: Dictionary, tick: int, reach_mm: float) -> int:
	var e := float(orbit["e_q30"]) / ONE
	var h_end := OrbitPath._h_at_distance(orbit, OrbitPath.open_reach(orbit, reach_mm))
	var m_end := e * sinh(h_end) - h_end
	return maxi(1, ceili((m_end - OrbitPath.mean_anomaly(orbit, float(tick))) / OrbitPath.motion(orbit)))


## A body's world position at a tick, in 64-bit mm: its orbit's position at that
## tick plus its parent's, up the chain. A body not on an orbit stays where the
## view has it. For drawing paths that run into the future, when moons have moved.
static func body_world_at(view: Dictionary, body_id: int, tick: float) -> PackedFloat64Array:
	var body: Dictionary = view["bodies"].get(body_id, {})
	if body.is_empty():
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var orbit: Dictionary = body.get("orbit", {})
	if orbit.is_empty():
		return OrbitPath.shifted(WorldPosition.of(body), [0, 0, 0])
	var parent := OrbitPath.body_world_at(view, orbit["parent"], tick)
	var here := OrbitPath.position(orbit, tick)
	return PackedFloat64Array([here[0] + parent[0], here[1] + parent[1], here[2] + parent[2]])


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
