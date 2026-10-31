class_name FixtureSystem
extends SimSystem
## A minimal system for kernel tests. It owns one `test_add` command, which changes a unit's
## inventory through a phase 6 delta, and vents 3 g per second from every unit into a sink.

const COMMAND := "test_add"
const SINK := "slag_vent"
const ITEM := "slag"

## Phase names in the order they ran. Not saved.
var calls: Array[String] = []
var delta_owners: Array[int] = []
## Added to the inventory total, to prove the ledger catches an imbalance.
var injected_g := 0
## Events to emit in phase 5, as [unit, type] pairs.
var extra_events: Array = []


static func add_unit(state: Dictionary, id: int, grams: int) -> void:
	state["units"][id] = { "inventory": { "hematite": grams }, "mined_remainder": 0, "pos_mm": [0, 0, 0] }


func commands() -> PackedStringArray:
	return PackedStringArray([COMMAND])


func validate(_ctx: SimContext, command: Dictionary) -> Dictionary:
	if command["args"].get("grams", 0) < 0:
		return SimSystem.reject("negative_grams", { "grams": command["args"]["grams"] })
	if command["args"].get("fit_fail", false):
		return SimSystem.reject("over_mass_limit", {}, "attach_failed", { "item": "hull" })
	return SimSystem.ok()


func apply(ctx: SimContext, command: Dictionary) -> void:
	calls.append("apply")
	ctx.emit_event("arrived", command["unit"], { "target": command["args"].get("grams", 0) })
	ctx.record_delta(command["unit"], self, { "unit": command["unit"], "grams": command["args"].get("grams", 0) })


func update_tasks(_ctx: SimContext) -> void:
	calls.append("update_tasks")


func calculate_power(_ctx: SimContext) -> void:
	calls.append("calculate_power")


func allocate(_ctx: SimContext) -> void:
	calls.append("allocate")


func run(ctx: SimContext) -> void:
	calls.append("run")
	for pair: Array in extra_events:
		ctx.emit_event(pair[1], pair[0], {})
	var units: Dictionary = ctx.state["units"]
	var ids: Array = units.keys()
	ids.sort()
	for id: int in ids:
		var unit: Dictionary = units[id]
		var grams := Rate.amount(3, unit["mined_remainder"])
		unit["mined_remainder"] = Rate.carry(3, unit["mined_remainder"])
		if grams > 0:
			ctx.record_delta(id, self, { "unit": id, "grams": 0, "vent": grams })


func apply_delta(ctx: SimContext, payload: Dictionary) -> void:
	calls.append("apply_delta")
	var unit: int = payload["unit"]
	delta_owners.append(unit)
	var inventory: Dictionary = ctx.state["units"][unit]["inventory"]
	inventory["hematite"] += payload["grams"]
	var vent: int = payload.get("vent", 0)
	if vent > 0:
		var grams: int = mini(vent, inventory["hematite"])
		inventory["hematite"] -= grams
		var sink: Dictionary = ctx.state["sinks"].get_or_add(SINK, {})
		sink[ITEM] = sink.get(ITEM, 0) + grams


func update_stores(_ctx: SimContext) -> void:
	calls.append("update_stores")


func detect(_ctx: SimContext) -> void:
	calls.append("detect")


func fill_ledger(ctx: SimContext, ledger: Dictionary) -> void:
	var total := injected_g
	var units: Dictionary = ctx.state["units"]
	for id: int in units:
		total += units[id]["inventory"]["hematite"]
	ledger["matter"]["inventories_g"] += total
