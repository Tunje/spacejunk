class_name ConstructionSystem
extends SimSystem
## Puts built units into the world. Registered last, so a new unit appears after the power and heat
## networks have settled phase 6, and it first takes part in them on the next tick.

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
	var id := Units.create(ctx, template, unit_name, ctx.state["units"][host]["pos_mm"])
	var unit: Dictionary = ctx.state["units"][id]
	unit["dock"] = {
		"port": Units.ports(ctx.state, ctx.defs, id)[0], "target_unit": host, "target_port": build["port"],
	}
	unit["at_target"] = host
	ctx.emit_event("unit_created", host, { "unit": id, "def": template, "job": build["job"] })
