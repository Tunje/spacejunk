class_name Reach
extends RefCounted
## The one reach test of gameplay (C34, stage4_gameplay_rules.md section 1): how far a unit is
## from a body or another unit, and how fast they close, from real relative positions. Scans,
## measurements, mining and cycle placement all ask here, so none of them holds its own geometry.
##
## Built on A54's relative state (Relative), the same tracks the simulation moves things on: a
## docked unit is where its host is, a landed one rides its body, and frames still count until
## A53's stage 4 removes them.

const MM_PER_M := 1000


## The distance from the unit to the target's centre, now, in millimetres. Until A53's stage 4
## removes the "is at" flag, a unit flagged at the target is at it, range 0, as everything placed
## by the flag has been; the flag goes with the frames, and this with it.
static func range_mm(ctx: SimContext, unit_id: int, target: int) -> int:
	if Units.at(ctx.state, unit_id, target):
		return 0
	return _now(ctx, unit_id, target)["range_mm"]


## The distance from the unit to a body's surface, now: the range less its radius, floored at 0.
static func surface_mm(ctx: SimContext, unit_id: int, body_id: int) -> int:
	return maxi(0, range_mm(ctx, unit_id, body_id) - int(ctx.state["bodies"][body_id]["radius_mm"]))


## The relative speed of the target seen from the unit, now, in µm/s.
static func speed_um_s(ctx: SimContext, unit_id: int, target: int) -> int:
	return _now(ctx, unit_id, target)["speed_um_s"]


## True when the unit is at or within `limit_mm` of the target's centre.
static func within(ctx: SimContext, unit_id: int, target: int, limit_mm: int) -> bool:
	return range_mm(ctx, unit_id, target) <= limit_mm


## The ticks before the range could cross `limit_mm`, for coasting an op held within range. Two
## things standing still in one place keep their range, so that coasts without limit. Anything
## else steps every tick, until A gives the bound from the gap and the largest relative speed
## (stage4_gameplay_rules.md section 1).
static func horizon(ctx: SimContext, unit_id: int, target: int, _limit_mm: int) -> int:
	if Units.at(ctx.state, unit_id, target):
		return SimSystem.NO_LIMIT  # the flag changes only on a stepped tick
	var mine := Relative.unit_track(ctx, unit_id)
	var theirs := Relative.thing_track(ctx, target)
	if _still(mine) and _still(theirs) and mine["place"] == theirs["place"]:
		return SimSystem.NO_LIMIT
	return 0


## Whole metres from a data range.
static func mm_of_m(range_m: int) -> int:
	return range_m * MM_PER_M


static func _still(track: Dictionary) -> bool:
	return track["kind"] == "line" and track["vel"] == [0, 0, 0]


static func _now(ctx: SimContext, unit_id: int, target: int) -> Dictionary:
	var tick: int = ctx.state["tick"]
	return Relative.state_between(ctx, Relative.unit_track(ctx, unit_id), Relative.thing_track(ctx, target), tick)
