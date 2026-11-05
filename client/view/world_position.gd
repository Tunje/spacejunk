class_name WorldPosition extends RefCounted
## Where a view entry is in the world. Since contract version 3, `pos_mm` is in the
## entry's own place (relative to its orbit's parent, or local to its frame), and
## `world_mm` adds up the chain to the root body (contracts sections 1 and 7).
## A view without `world_mm`, from before version 3, is all in one place.


static func of(entry: Dictionary) -> Array:
	var world: Array = entry.get("world_mm", [])
	return world if world.size() == 3 else entry["pos_mm"]


## What to add to a position in the entry's own place to put it in the world.
static func offset(entry: Dictionary) -> Array:
	var world := WorldPosition.of(entry)
	var local: Array = entry["pos_mm"]
	return [world[0] - local[0], world[1] - local[1], world[2] - local[2]]


## A position in the entry's own place, such as a route end, in the world.
static func local_to_world(entry: Dictionary, local_mm: Array) -> Array:
	var shift := WorldPosition.offset(entry)
	return [local_mm[0] + shift[0], local_mm[1] + shift[1], local_mm[2] + shift[2]]


## Whether two entries share a place, so their local positions compare directly.
static func same_place(a: Dictionary, b: Dictionary) -> bool:
	return a.get("frame", 0) == b.get("frame", 0) and a.get("orbit", {}).is_empty() and b.get("orbit", {}).is_empty()
