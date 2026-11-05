class_name LandingLegs extends RefCounted
## Fits real landing legs (B15's landing_legs_mk1) to a craft on the real Sim, for the
## landing tests and screenshot demos: an ordinary attach_part from the craft's own
## hold, on the first free connector check() accepts. A19 lands nothing without gear.

const ITEM := "landing_legs_mk1"


## True when fitted. The sim is stepped one tick to apply the order.
static func fit(sim: Sim, unit_id: int) -> bool:
	var modules: Dictionary = sim.defs()["modules"]
	var inventory: Dictionary = sim._state["units"][unit_id]["inventory"]
	inventory[ITEM] = inventory.get(ITEM, 0) + int(modules[ITEM]["mass_g"])
	sim._ctx.index.clear()
	var unit: Dictionary = sim.view()["units"][unit_id]
	for slot: Dictionary in FittingLogic.free_slots(unit, modules):
		var command := FittingLogic.attach_command(unit_id, { "item": ITEM, "from": unit_id }, slot)
		if sim.check(command)["ok"]:
			sim.submit(command)
			sim.step(1)
			return sim.view()["units"][unit_id]["touchdown_mm_s"] > 0
	return false
