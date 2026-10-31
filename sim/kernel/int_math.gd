class_name IntMath
extends RefCounted
## Exact integer arithmetic for ranged values. GDScript wraps silently on overflow, so any
## product of ranged values goes through here. An unrepresentable result is a push_error.

const MAX_INT := 9223372036854775807
const LIMB_BITS := 22
const LIMB_MASK := (1 << LIMB_BITS) - 1
const LIMB_COUNT := 6
const ROOT_BITS := 40
const ROOT_MASK := (1 << ROOT_BITS) - 1
## Three axes at this size still sum their squares inside 63 bits.
const NARROW_AXIS_LIMIT := 1_700_000_000


## floor(a * b / d) with a 128-bit intermediate. Arguments are non-negative and d is positive.
static func mul_div(a: int, b: int, d: int) -> int:
	assert(a >= 0 and b >= 0 and d > 0, "mul_div takes non-negative values")
	if a == 0 or b == 0:
		return 0
	if a <= MAX_INT / b:
		return a * b / d
	if b > a:
		var swap := a
		a = b
		b = swap
	# a * b / d = (a / d) * b + (a % d) * b / d, and the second term is built bit by bit from b.
	var whole := a / d
	var step_rem := a % d
	if whole != 0 and b > MAX_INT / whole:
		return _overflow("mul_div")
	var result := whole * b
	var quotient := 0
	var rem := 0
	for bit in range(_bit_length(b) - 1, -1, -1):
		quotient *= 2
		if rem >= d - rem:
			rem -= d - rem
			quotient += 1
		else:
			rem += rem
		if (b >> bit) & 1 == 1:
			if rem >= d - step_rem:
				rem -= d - step_rem
				quotient += 1
			else:
				rem += step_rem
	if result > MAX_INT - quotient:
		return _overflow("mul_div")
	return result + quotient


## Floored Euclidean distance between two 3-element integer positions.
static func dist(a: Array, b: Array) -> int:
	var dx := absi(int(a[0]) - int(b[0]))
	var dy := absi(int(a[1]) - int(b[1]))
	var dz := absi(int(a[2]) - int(b[2]))
	if maxi(dx, maxi(dy, dz)) <= NARROW_AXIS_LIMIT:
		return isqrt(dx * dx + dy * dy + dz * dz)
	return _dist_wide(dx, dy, dz)


## Floored square root of a non-negative integer.
static func isqrt(value: int) -> int:
	assert(value >= 0, "isqrt takes non-negative values")
	var root := 0
	var bit := 1 << 62
	while bit > value:
		bit >>= 2
	while bit != 0:
		if value >= root + bit:
			value -= root + bit
			root = (root >> 1) + bit
		else:
			root >>= 1
		bit >>= 2
	return root


## Digit-by-digit square root of dx^2 + dy^2 + dz^2, held in 22-bit limbs. The root and the
## running remainder can pass 63 bits, so both are split into high and low words.
static func _dist_wide(dx: int, dy: int, dz: int) -> int:
	var limbs: Array[int] = [0, 0, 0, 0, 0, 0]
	_add_square(dx, limbs)
	_add_square(dy, limbs)
	_add_square(dz, limbs)
	for i in LIMB_COUNT - 1:
		limbs[i + 1] += limbs[i] >> LIMB_BITS
		limbs[i] &= LIMB_MASK
	var rem_hi := 0
	var rem_lo := 0
	var root_hi := 0
	var root_lo := 0
	for limb in range(LIMB_COUNT - 1, -1, -1):
		for shift in range(LIMB_BITS - 2, -2, -2):
			rem_lo = rem_lo * 4 + ((limbs[limb] >> shift) & 3)
			rem_hi = rem_hi * 4 + (rem_lo >> ROOT_BITS)
			rem_lo &= ROOT_MASK
			var trial_lo := root_lo * 4 + 1
			var trial_hi := root_hi * 4 + (trial_lo >> ROOT_BITS)
			trial_lo &= ROOT_MASK
			root_lo *= 2
			root_hi = root_hi * 2 + (root_lo >> ROOT_BITS)
			root_lo &= ROOT_MASK
			if rem_hi > trial_hi or (rem_hi == trial_hi and rem_lo >= trial_lo):
				rem_lo -= trial_lo
				rem_hi -= trial_hi
				if rem_lo < 0:
					rem_lo += 1 << ROOT_BITS
					rem_hi -= 1
				root_lo |= 1
	if root_hi >= 1 << (63 - ROOT_BITS):
		return _overflow("dist")
	return (root_hi << ROOT_BITS) | root_lo


static func _add_square(value: int, limbs: Array[int]) -> void:
	var l0 := value & LIMB_MASK
	var l1 := (value >> LIMB_BITS) & LIMB_MASK
	var l2 := value >> (2 * LIMB_BITS)
	limbs[0] += l0 * l0
	limbs[1] += 2 * l0 * l1
	limbs[2] += 2 * l0 * l2 + l1 * l1
	limbs[3] += 2 * l1 * l2
	limbs[4] += l2 * l2


static func _bit_length(value: int) -> int:
	var length := 0
	while value != 0:
		value >>= 1
		length += 1
	return length


static func _overflow(operation: String) -> int:
	push_error("IntMath.%s result does not fit in 63 bits" % operation)
	return MAX_INT
