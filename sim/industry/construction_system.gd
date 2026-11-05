class_name ConstructionSystem
extends SimSystem
## Puts built units into the world. Registered last, so a new unit appears after the power and heat
## networks have settled phase 6, and it first takes part in them on the next tick.
##
## A built unit docks at the port claimed for it, on the builder or on the unit the builder is docked
## to, and takes that unit's place: its frame, orbit or landed cell, and its position. So it stays
## where it was built when it undocks.

const FLOW_KEY := "builds"


## Queues a unit for this tick's phase 6, docked at a port that is already free for it.
static func queue(ctx: SimContext, host: int, port: int, template: String, job: int) -> void:
	ctx.flows.get_or_add(FLOW_KEY, []).append({
		"host": host, "port": port, "template": template, "job": job,
	})


func update_stores(ctx: SimContext) -> void:
	for build: Dictionary in ctx.flows.get(FLOW_KEY, []):
		_build(ctx, build)


func _build(ctx: SimContext, build: Dictionary) -> void:
	var host: int = build["host"]
	var template: String = build["template"]
	var unit_name: String = ctx.defs["templates"][template]["name"]
	var dock_unit: int = ctx.state["parts"][build["port"]]["unit"]
	var place: Dictionary = ctx.state["units"][_place_holder(ctx.state, dock_unit)]
	var id := Units.create(ctx, template, unit_name, place["pos_mm"])
	var unit: Dictionary = ctx.state["units"][id]
	unit["frame"] = place["frame"]
	unit["orbit"] = place["orbit"].duplicate(true)
	unit["landed"] = place["landed"].duplicate(true)
	unit["dock"] = {
		"port": Units.ports(ctx.state, ctx.defs, id)[0], "target_unit": dock_unit, "target_port": build["port"],
	}
	unit["at_target"] = dock_unit
	ctx.emit_event("unit_created", host, { "unit": id, "def": template, "job": build["job"] })


## The unit whose place a docked unit shares: the far end of its chain of docks.
static func _place_holder(state: Dictionary, unit_id: int) -> int:
	var current := unit_id
	while not state["units"][current]["dock"].is_empty():
		current = state["units"][current]["dock"]["target_unit"]
	return current
