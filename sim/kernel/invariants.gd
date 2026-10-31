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
const INVENTORY_KEY := "inventory"


## Every out-of-range or non-plain value in a state tree.
static func violations(state: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	_walk(state, "", "$", found)
	return found


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
				_walk_child(map[child_key], child_key, key, "%s.%s" % [path, child_key], found)
		TYPE_BOOL, TYPE_STRING:
			pass
		_:
			found.append("%s has type %s" % [path, type_string(typeof(value))])


static func _walk_child(
	value: Variant, child_key: Variant, parent_key: String, path: String, found: PackedStringArray
) -> void:
	if parent_key == INVENTORY_KEY:
		_walk(value, "stack_g", path, found)
	elif parent_key == SINKS_KEY:
		_walk(value, WORLD_TOTAL_KEY, path, found)
	elif typeof(child_key) == TYPE_STRING:
		_walk(value, child_key, path, found)
	else:
		_walk(value, "", path, found)


static func _check_int(value: int, key: String, path: String, found: PackedStringArray) -> void:
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
	else:
		return
	if value < low or value > high:
		found.append("%s = %d is outside %d to %d" % [path, value, low, high])
