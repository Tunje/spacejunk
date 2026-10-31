class_name FloatingOrigin extends RefCounted
## Turns integer sim positions into render positions around the camera focus.
## Positions are subtracted as integers first, so nothing jitters far from the
## sim origin. Bodies beyond NEAR_M are drawn nearer and smaller.

const MM_TO_M := 0.001
const NEAR_M := 50000.0
const FAR_M := 150000.0


## Position in metres relative to the focus, interpolated between two views.
## Each endpoint is relative to the focus at that view, so the focus itself
## always lands exactly on the render origin.
static func relative_m(prev_mm: Array, curr_mm: Array, prev_focus: Array, curr_focus: Array, alpha: float) -> Vector3:
	var result := Vector3.ZERO
	for axis in range(3):
		var before: int = prev_mm[axis] - prev_focus[axis]
		var after: int = curr_mm[axis] - curr_focus[axis]
		result[axis] = lerpf(float(before), float(after), alpha) * MM_TO_M
	return result


## Scale applied to a body's position and size at `distance_m`. It is 1 up to
## NEAR_M, then eases so nothing is ever drawn beyond FAR_M.
static func compression(distance_m: float) -> float:
	if distance_m <= NEAR_M:
		return 1.0
	return (NEAR_M + (FAR_M - NEAR_M) * (1.0 - NEAR_M / distance_m)) / distance_m
