class_name PlanetGrid
extends RefCounted
## The hex grid on a planet and its integer terrain (planets.md, orbital_flight.md section 8).
## Pure functions of (seed, cell, n): nothing is stored, and a save holds only the seed. Every cell
## is computed on demand, so the simulation never builds the whole planet. The client may.
##
## The grid is a Goldberg layout of 10 n^2 + 2 cells: the dual of an icosahedron with each edge cut
## into n. Twelve cells are pentagons and the rest hexagons. Cell IDs:
## - 0 is the north pole and 1 the south pole.
## - The rest are 2 + d n^2 + (i - 1) n + j, over 10 diamonds d, with i in 1..n and j in 0..n-1.
##
## A diamond is two faces of the icosahedron. Its chart has corners A at (0, 0), B at (n, 0),
## C at (n, n) and D at (0, n). North diamond k is (N, U_k, L_k, U_k+1) and south diamond k is
## (U_k+1, L_k, S, L_k+1), where U and L are the upper and lower rings of five corners.
## +Y is north, matching the simulation axes.

const ONE := OrbitMath.ONE
const DIAMONDS := 10
const NORTH := 0
const SOUTH := 1
## n is the radius over this, so a hex is about 7.2 km across on any planet (owner's ruling).
const MM_PER_N := 6_000_000
## Icosahedron corners in Q30: N, U_0..U_4, L_0..L_4, S.
const CORNERS := [[0, 1073741824, 0], [960383883, 480191942, 0], [296774941, 480191942, -913379351],
	[-776966883, 480191942, -564499483], [-776966883, 480191942, 564499483],
	[296774941, 480191942, 913379351], [776966883, -480191942, -564499483],
	[-296774941, -480191942, -913379351], [-960383883, -480191942, 0],
	[-296774941, -480191942, 913379351], [776966883, -480191942, 564499483], [0, -1073741824, 0]]
## Lattice steps to the six neighbours of a chart point.
const STEPS := [[1, 0], [-1, 0], [0, 1], [0, -1], [1, -1], [-1, 1]]
const MAX_HEIGHT_M := 8000
const NOISE_MAX := 65535
## Noise lattice spacing is an eighth of the radius for the first octave, halving each octave after.
const FIRST_OCTAVE_SHIFT := 27
const MOISTURE_SALT := 0x6D6F6973
const HASH_MULTIPLIER := 0x5BD1E995
const HASH_LAST := 0x2545F491
const MASK_31 := 0x7FFFFFFF


## The grid size for a planet of this radius: about 7 km per hex, at least 1.
static func n_for_radius(radius_mm: int) -> int:
	return maxi(1, (radius_mm + MM_PER_N / 2) / MM_PER_N)


static func cell_count(n: int) -> int:
	return DIAMONDS * n * n + 2


# ------------------------------------------------------------------------------ IDs

## The one cell at chart point (i, j) of diamond d, for i and j in 0..n. Points on a diamond's
## edge belong to one neighbour, and the poles to no diamond.
static func cell_at(d: int, i: int, j: int, n: int) -> int:
	var k := d % 5
	var south := d >= 5
	if i == 0 and j == 0:
		return NORTH if not south else cell_at((k + 1) % 5, n, 0, n)
	if i == 0:
		if not south:
			return cell_at((k + 1) % 5, j, 0, n)
		if j == n:
			return cell_at(5 + (k + 1) % 5, n, 0, n)
		return cell_at((k + 1) % 5, n, j, n)
	if j == n:
		if not south:
			return cell_at(5 + k, i, 0, n)
		if i == n:
			return SOUTH
		return cell_at(5 + (k + 1) % 5, n, i, n)
	return 2 + d * n * n + (i - 1) * n + j


## Every chart point [d, i, j] where a cell appears: one inside a diamond, two on an edge, and three
## or five at a corner of the icosahedron. The first is the cell's own.
static func chart_points(cell: int, n: int) -> Array:
	if cell == NORTH:
		return range(5).map(func(k: int) -> Array: return [k, 0, 0])
	if cell == SOUTH:
		return range(5).map(func(k: int) -> Array: return [5 + k, n, n])
	var rest := cell - 2
	var d := rest / (n * n)
	var i := (rest % (n * n)) / n + 1
	var j := rest % n
	var k := d % 5
	var points := [[d, i, j]]
	if d < 5:
		if j == 0:
			points.append([(k + 4) % 5, 0, i])
		if i == n:
			points.append([5 + (k + 4) % 5, 0, j])
	else:
		if j == 0:
			points.append([k, i, n])
		if i == n:
			points.append([5 + (k + 4) % 5, j, n])
	return points


## The cell's neighbours in ascending ID: five for the 12 pentagons, six for every other cell.
static func neighbours(cell: int, n: int) -> Array[int]:
	var found := {}
	for point: Array in chart_points(cell, n):
		for step: Array in STEPS:
			var i: int = point[1] + step[0]
			var j: int = point[2] + step[1]
			if i >= 0 and i <= n and j >= 0 and j <= n:
				found[cell_at(point[0], i, j, n)] = true
	found.erase(cell)
	var result: Array[int] = []
	result.assign(found.keys())
	result.sort()
	return result


# ------------------------------------------------------------------------------ geometry

## The cell's centre as a unit direction in Q30, in the planet's frame.
static func direction(cell: int, n: int) -> Array[int]:
	var point: Array = chart_points(cell, n)[0]
	return OrbitMath.unit(_flat_point(point[0], point[1], point[2], n))


## The centre in mm from the planet's centre, for a datum radius and a height in whole metres.
static func centre_mm(cell: int, n: int, radius_mm: int, height_m: int) -> Array[int]:
	var dir := direction(cell, n)
	var distance := radius_mm + height_m * 1000
	return [OrbitMath.smul_div(dir[0], distance, ONE), OrbitMath.smul_div(dir[1], distance, ONE),
		OrbitMath.smul_div(dir[2], distance, ONE)]


## The point (i, j) of a diamond on the flat icosahedron, in Q30. Exact before the final division,
## so a point shared by two diamonds lands within a unit of the same place from either.
static func _flat_point(d: int, i: int, j: int, n: int) -> Array[int]:
	var k := d % 5
	var a: Array
	var b: Array
	var c: Array
	var e: Array
	if d < 5:
		a = CORNERS[0]
		b = CORNERS[1 + k]
		c = CORNERS[6 + k]
		e = CORNERS[1 + (k + 1) % 5]
	else:
		a = CORNERS[1 + (k + 1) % 5]
		b = CORNERS[6 + k]
		c = CORNERS[11]
		e = CORNERS[6 + (k + 1) % 5]
	var out: Array[int] = [0, 0, 0]
	for axis in 3:
		var scaled: int
		if i + j <= n:
			scaled = (n - i - j) * a[axis] + i * b[axis] + j * e[axis]
		else:
			scaled = (i + j - n) * c[axis] + (n - j) * b[axis] + (n - i) * e[axis]
		out[axis] = OrbitMath.smul_div(scaled, 1, n)
	return out


# ------------------------------------------------------------------------------ terrain

## A hash of four integers to 0..2^31-1. Every product stays under 2^62, so nothing ever wraps.
static func hash4(seed: int, x: int, y: int, z: int) -> int:
	var h := seed & MASK_31
	for v: int in [x, y, z, HASH_LAST]:
		h = ((h ^ (v & MASK_31)) * HASH_MULTIPLIER) & MASK_31
		h ^= h >> 15
	return h


## A roll for one cell, such as a deposit chance: 0..2^31-1, the same for the same seed, cell and salt.
static func roll(seed: int, cell: int, salt: int) -> int:
	return hash4(seed, cell, salt, 0)


## Smooth value noise at a unit direction, 0..NOISE_MAX, as a weighted mix of octaves. Octave o has
## weight weights[o], with lattice spacing an eighth of the radius halving each octave. Each octave
## and the mix are convex combinations of values in range, so the result can never leave it.
static func noise(seed: int, dir: Array, weights: Array) -> int:
	var total := 0
	var weight_sum := 0
	for octave in weights.size():
		var weight: int = weights[octave]
		if weight == 0:
			continue
		var shift := FIRST_OCTAVE_SHIFT - octave
		var corner: Array[int] = []
		var t: Array[int] = []
		for axis in 3:
			var u: int = dir[axis] + ONE
			corner.append(u >> shift)
			var f := (u & ((1 << shift) - 1)) >> (shift - 16)
			t.append((f * f * (3 * 65536 - 2 * f)) >> 32)
		var mixed: Array[int] = []
		for c in 8:
			mixed.append(hash4(seed + octave, corner[0] + (c & 1), corner[1] + ((c >> 1) & 1),
				corner[2] + (c >> 2)) & NOISE_MAX)
		for axis in 3:
			var next: Array[int] = []
			for c in range(0, mixed.size(), 2):
				next.append(mixed[c] + (((mixed[c + 1] - mixed[c]) * t[axis]) >> 16))
			mixed = next
		total += mixed[0] * weight
		weight_sum += weight
	return total / weight_sum if weight_sum > 0 else 0


## Height in whole metres, -range_m..range_m, with range_m at most MAX_HEIGHT_M.
static func height_m(seed: int, dir: Array, weights: Array, range_m: int) -> int:
	assert(range_m >= 0 and range_m <= MAX_HEIGHT_M, "height range within the proven limit")
	return ((noise(seed, dir, weights) * (2 * range_m + 1)) >> 16) - range_m


## Moisture, 0..1000, from a second noise field with the same octaves.
static func moisture(seed: int, dir: Array, weights: Array) -> int:
	return (noise(seed + MOISTURE_SALT, dir, weights) * 1001) >> 16
