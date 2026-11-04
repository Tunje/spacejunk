class_name Invariants
extends RefCounted
## The valid-range table from contracts section 1, asserted at commit in test runs. Ranges are
## matched by key name, so state fields must carry their unit suffix.

const MAX_MATTER_G := 1_000_000_000_000_000
const MAX_WORLD_G := 9_000_000_000_000_000_000
const WORLD_TOTAL_KEY := "matter_start_g"
const SINKS_KEY := "sinks"
const MAX_POWER_W := 1_000_000_000_000
const MAX_STORE_J := 1_000_000_000_000_000
const MAX_VOLUME_L := 1_000_000_000_000
const MAX_TICK := 1_000_000_000_000_000
const MAX_POSITION_MM := 4_000_000_000_000_000_000
## Orbit fields (orbital_flight.md section 11.4): Q30 ratios and directions, binary angles, periods
## in sub-ticks, and GM in units of 1000 m^3/s^2.
## Q30 values reach 2^40, so a hyperbola's eccentricity can be up to 1024.
const MAX_Q30 := 1 << 40
const MAX_SUBTICKS := 1 << 55
const MAX_GM := 9_000_000_000_000_000_000
const GM_KEY := "gm"
const MAX_SPEED_UM_S := 1_000_000_000_000
const INVENTORY_KEY := "inventory"


## Every out-of-range or non-plain value in a state tree. A clean state skips the slower walk that
## names each path, since test runs do this every tick.
static func violations(state: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	if not _is_clean(state, ""):
		_walk(state, "", "$", found)
	return found


static func _is_clean(value: Variant, key: String) -> bool:
	match typeof(value):
		TYPE_INT:
			return _in_range(value, key)
		TYPE_ARRAY:
			var values: Array = value
			for item: Variant in values:
				if not _is_clean(item, key):
					return false
			return true
		TYPE_DICTIONARY:
			var map: Dictionary = value
			for child_key: Variant in map:
				if not _is_clean(map[child_key], _child_key(child_key, key)):
					return false
			return true
		TYPE_BOOL, TYPE_STRING:
			return true
	return false


## The key a child's value is ranged by.
static func _child_key(child_key: Variant, parent_key: String) -> String:
	if parent_key == INVENTORY_KEY:
		return "stack_g"
	if parent_key == SINKS_KEY:
		return WORLD_TOTAL_KEY
	return child_key if typeof(child_key) == TYPE_STRING else ""


static func _walk(value: Variant, key: String, path: String, found: PackedStringArray) -> void:
	match typeof(value):
		TYPE_INT:
			_check_int(value, key, path, found)
		TYPE_ARRAY:
			var values: Array = value
			for i in values.size():
				_walk(values[i], key, "%s[%d]" % [path, i], found)
		TYPE_DICTIONARY:
			var map: Dictionary = value
			for child_key: Variant in map:
				_walk(map[child_key], _child_key(child_key, key), "%s.%s" % [path, child_key], found)
		TYPE_BOOL, TYPE_STRING:
			pass
		_:
			found.append("%s has type %s" % [path, type_string(typeof(value))])


static func _check_int(value: int, key: String, path: String, found: PackedStringArray) -> void:
	if not _in_range(value, key):
		var limits := _limits(key)
		found.append("%s = %d is outside %d to %d" % [path, value, limits[0], limits[1]])


static func _in_range(value: int, key: String) -> bool:
	var limits := _limits(key)
	return limits.is_empty() or (value >= limits[0] and value <= limits[1])


## The range for a key, as [low, high], or [] if the key has none.
static func _limits(key: String) -> Array:
	if key.is_empty():
		return []
	var low := 0
	var high := 0
	if key.ends_with("_remainder"):
		high = Sim.TICKS_PER_SECOND - 1
	elif key == WORLD_TOTAL_KEY:
		high = MAX_WORLD_G
	elif key.ends_with("_g"):
		high = MAX_MATTER_G
	elif key.ends_with("_w"):
		high = MAX_POWER_W
	elif key.ends_with("_j"):
		high = MAX_STORE_J
	elif key.ends_with("_l"):
		high = MAX_VOLUME_L
	elif key.ends_with("_mm"):
		low = -MAX_POSITION_MM
		high = MAX_POSITION_MM
	elif key == "tick" or key.ends_with("_tick"):
		high = MAX_TICK
	elif key.ends_with("_q30"):
		low = -MAX_Q30
		high = MAX_Q30
	elif key.ends_with("_angle"):
		high = OrbitMath.ANGLE_MASK
	elif key.ends_with("_subticks"):
		low = 1
		high = MAX_SUBTICKS
	elif key == GM_KEY:
		high = MAX_GM
	elif key.ends_with("_um_s"):
		low = -MAX_SPEED_UM_S
		high = MAX_SPEED_UM_S
	else:
		return []
	return [low, high]
