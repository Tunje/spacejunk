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


## Adds a unit with no parts, and the one item definition kernel tests need.
static func add_unit(sim: Sim, id: int, grams: int) -> void:
	sim._ctx.defs["items"]["hematite"] = { "cargo_class": "ore", "density_g_l": 5000 }
	var unit := Units.new_record(id, "", "ship", "", [0, 0, 0])
	unit["inventory"]["hematite"] = grams
	unit["mined_remainder"] = 0
	sim._state["units"][id] = unit


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


func update_tasks(ctx: SimContext) -> void:
	calls.append("update_tasks")
	if ctx.state["units"].size() > 0:
		ctx.state["last_draw"] = ctx.rng.next_u32("fixture")


func calculate_power(_ctx: SimContext) -> void:
	calls.append("calculate_power")


func allocate(_ctx: SimContext) -> void:
	calls.append("allocate")


func run(ctx: SimContext) -> void:
	calls.append("run")
	for pair: Array in extra_events:
		ctx.emit_event(pair[1], pair[0], {})
	_run_jobs(ctx)
	var units: Dictionary = ctx.state["units"]
	var ids: Array = units.keys()
	ids.sort()
	for id: int in ids:
		var unit: Dictionary = units[id]
		var grams := Rate.amount(3, unit["mined_remainder"])
		unit["mined_remainder"] = Rate.carry(3, unit["mined_remainder"])
		if grams > 0:
			ctx.record_delta(id, self, { "unit": id, "grams": 0, "vent": grams })


## A job holds its grams until its work_left counts down to 0, one per tick, then sends them to the sink.
func _run_jobs(ctx: SimContext) -> void:
	var jobs: Dictionary = ctx.state["jobs"]
	var ids: Array = jobs.keys()
	ids.sort()
	for id: int in ids:
		var job: Dictionary = jobs[id]
		job["work_left"] -= 1
		if job["work_left"] == 0:
			var sink: Dictionary = ctx.state["sinks"].get_or_add(SINK, {})
			sink[ITEM] = sink.get(ITEM, 0) + job["held"][ITEM]
			jobs.erase(id)


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


func fill_ledger(_ctx: SimContext, ledger: Dictionary) -> void:
	ledger["matter"]["inventories_g"] += injected_g
