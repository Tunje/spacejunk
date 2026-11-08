class_name Reach
extends RefCounted
## The one reach test of gameplay (C34, stage4_gameplay_rules.md section 1): how far a unit is
## from a body or another unit, and how fast they close, from real relative positions. Scans,
## measurements, mining and cycle placement all ask here, so none of them holds its own geometry.
##
## Built on A59's static relative state (Relative.now_between, range_now_mm and range_horizon), the
## same code as Sim.relative: a docked unit is where its host is, a landed one rides its body, and
## frames still count until A53's stage 4 removes them. "Now" is the tick being run during phases 2
## to 7, and the last finished tick otherwise, as A59 gives it.

const MM_PER_M := 1000
## The range of a pair Relative can't place: the unit or the target is gone. Out of every range.
const GONE_MM := IntMath.MAX_INT


## The distance from the unit to the target's centre, now, in millimetres. Until A53's stage 4
## removes the "is at" flag, a unit flagged at the target is at it, range 0, as everything placed
## by the flag has been; the flag goes with the frames, and this with it.
static func range_mm(ctx: SimContext, unit_id: int, target: int) -> int:
	if Units.at(ctx.state, unit_id, target):
		return 0
	var found := Relative.range_now_mm(ctx, unit_id, target)
	return GONE_MM if found < 0 else found


## The distance from the unit to a body's surface, now: the range less its radius, floored at 0.
static func surface_mm(ctx: SimContext, unit_id: int, body_id: int) -> int:
	var found := range_mm(ctx, unit_id, body_id)
	if found == GONE_MM:
		return GONE_MM
	return maxi(0, found - int(ctx.state["bodies"][body_id]["radius_mm"]))


## The relative speed of the target seen from the unit, now, in µm/s; 0 for a pair that is gone.
static func speed_um_s(ctx: SimContext, unit_id: int, target: int) -> int:
	return Relative.now_between(ctx, unit_id, target).get("speed_um_s", 0)


## True when the unit is at or within `limit_mm` of the target's centre.
static func within(ctx: SimContext, unit_id: int, target: int, limit_mm: int) -> bool:
	return range_mm(ctx, unit_id, target) <= limit_mm


## The ticks before the range could cross `limit_mm`, for coasting an op held within range: A59's
## bound from the gap, the relative speed now and both pulls. A unit flagged at the target stays
## at range 0 until a stepped tick changes the flag.
static func horizon(ctx: SimContext, unit_id: int, target: int, limit_mm: int) -> int:
	if Units.at(ctx.state, unit_id, target):
		return SimSystem.NO_LIMIT
	return Relative.range_horizon(ctx, unit_id, target, limit_mm)


## Whole metres from a data range.
static func mm_of_m(range_m: int) -> int:
	return range_m * MM_PER_M
