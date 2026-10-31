extends GutTest
## Contract shape test (contracts sections 3, 7 and 11). Runs against the stub,
## and against the real Sim as soon as sim/kernel/sim.gd declares `class_name Sim`.

const SIM_SCRIPT := "res://sim/kernel/sim.gd"
const UNIT_FIELDS: Array[String] = [
	"def", "kind", "name", "pos_mm", "core", "core_tier", "task", "cycle_task", "last_cycle",
	"op", "route", "dock",
	"parts", "inventory", "mass_g", "cargo", "fit", "power", "heat",
]
const OP_FIELDS: Array[String] = ["type", "target", "part", "start_tick", "end_tick"]
const OP_TYPES: Array[String] = ["idle", "moving", "docking", "undocking", "loading", "unloading", "mining", "scanning"]
const PART_FIELDS: Array[String] = [
	"id", "def", "parent_connector", "connector", "state", "fault", "draw_w", "priority", "children",
]
const FIT_FIELDS: Array[String] = [
	"mass_g", "mass_limit_g", "power_budget_w", "power_rated_w", "heat_budget_w", "heat_rated_w",
]
const POWER_FIELDS: Array[String] = ["supply_w", "demand_w", "stored_j", "capacity_j", "max_discharge_w"]
const HEAT_FIELDS: Array[String] = ["stored_j", "limit_j", "reject_w", "input_w"]
const CARGO_FIELDS: Array[String] = ["used_g", "cap_g", "used_l", "cap_l", "reserved_g", "reserved_l"]
const TASK_FIELDS: Array[String] = [
	"id", "owner", "kind", "state", "reason", "hold", "steps", "step", "cycle", "since_tick", "command",
]
const DEFS_SECTIONS: Array[String] = ["modules", "items", "recipes", "templates", "sinks"]
const BODY_FIELDS: Array[String] = ["kind", "pos_mm", "radius_mm", "visual_seed", "scanned"]
const DEPOSIT_FIELDS: Array[String] = ["body", "item", "remaining_g", "hardness"]
const JOB_FIELDS: Array[String] = ["unit", "facility", "recipe", "count_left", "status", "reason", "start_tick", "end_tick"]


## A new game from each backend present. The kernel's built-in `empty` scenario
## has no entities, so the entity checks below only bite once scenarios exist.
func _backends() -> Array[RefCounted]:
	var backends: Array[RefCounted] = [StubSim.new_game("stub", 7)]
	if ResourceLoader.exists(SIM_SCRIPT):
		backends.append(load(SIM_SCRIPT).new_game("empty", 7))
	return backends


func _assert_fields(entry: Dictionary, fields: Array[String], label: String) -> void:
	for field: String in fields:
		assert_true(entry.has(field), "%s has %s" % [label, field])


func _assert_position(value: Variant, label: String) -> void:
	assert_true(value is Array, "%s is an Array, not a Vector3i" % label)
	assert_eq(value.size(), 3, label)
	for axis: Variant in value:
		assert_true(axis is int, "%s axis is int" % label)


func _assert_int_keys(entries: Dictionary, label: String) -> void:
	for key: Variant in entries:
		assert_true(key is int, "%s key %s is int" % [label, key])


func _assert_no_floats(value: Variant, label: String) -> void:
	assert_false(value is float, "%s holds a float" % label)
	if value is Array:
		for entry: Variant in value:
			_assert_no_floats(entry, label)
	elif value is Dictionary:
		for key: Variant in value:
			_assert_no_floats(value[key], "%s.%s" % [label, key])


func _assert_part(part: Dictionary) -> void:
	_assert_fields(part, PART_FIELDS, "part")
	assert_true(["on", "shed", "fault"].has(part["state"]), "part state")
	for child: Dictionary in part["children"]:
		_assert_part(child)


func _assert_unit(unit: Dictionary) -> void:
	_assert_fields(unit, UNIT_FIELDS, "unit")
	_assert_position(unit["pos_mm"], "unit pos_mm")
	_assert_fields(unit["op"], OP_FIELDS, "op")
	assert_true(OP_TYPES.has(unit["op"]["type"]), "op type")
	_assert_fields(unit["fit"], FIT_FIELDS, "fit")
	_assert_fields(unit["power"], POWER_FIELDS, "power")
	_assert_fields(unit["heat"], HEAT_FIELDS, "heat")
	for cargo_class: String in unit["cargo"]:
		_assert_fields(unit["cargo"][cargo_class], CARGO_FIELDS, "cargo")
	_assert_part(unit["parts"])


func _assert_view(view: Dictionary) -> void:
	for field: String in ["tick", "seed", "units", "bodies", "deposits", "jobs", "tasks"]:
		assert_true(view.has(field), "view has %s" % field)
	_assert_no_floats(view, "view")
	for section: String in ["units", "bodies", "deposits", "jobs", "tasks"]:
		_assert_int_keys(view[section], section)
	for id: int in view["units"]:
		_assert_unit(view["units"][id])
	for id: int in view["bodies"]:
		_assert_fields(view["bodies"][id], BODY_FIELDS, "body")
		_assert_position(view["bodies"][id]["pos_mm"], "body pos_mm")
	for id: int in view["deposits"]:
		_assert_fields(view["deposits"][id], DEPOSIT_FIELDS, "deposit")
	for id: int in view["tasks"]:
		_assert_fields(view["tasks"][id], TASK_FIELDS, "task")
	for id: int in view["jobs"]:
		_assert_fields(view["jobs"][id], JOB_FIELDS, "job")


func test_view_matches_contract_on_every_backend() -> void:
	for sim: RefCounted in _backends():
		_assert_view(sim.view())
		sim.step(1)
		_assert_view(sim.view())


func test_defs_have_every_section_on_every_backend() -> void:
	for sim: RefCounted in _backends():
		_assert_fields(sim.defs(), DEFS_SECTIONS, "defs")


func test_view_is_a_copy() -> void:
	for sim: RefCounted in _backends():
		var hash_before: String = sim.state_hash()
		var view: Dictionary = sim.view()
		view["tick"] = 999
		view["units"].clear()
		assert_eq(sim.state_hash(), hash_before)


func test_tick_counting_on_every_backend() -> void:
	for sim: RefCounted in _backends():
		assert_eq(sim.current_tick(), 0)
		sim.step(0)
		assert_eq(sim.current_tick(), 0)
		sim.step(3)
		assert_eq(sim.current_tick(), 3)
		assert_eq(sim.view()["tick"], 3)


func test_save_round_trips_byte_for_byte_on_every_backend() -> void:
	for sim: RefCounted in _backends():
		sim.step(5)
		var text: String = sim.to_save()
		var loaded: RefCounted = sim.get_script().from_save(text)
		assert_not_null(loaded)
		assert_eq(loaded.to_save(), text)
		assert_eq(loaded.state_hash(), sim.state_hash())


func test_check_reports_ok_reason_and_detail() -> void:
	for sim: RefCounted in _backends():
		var result: Dictionary = sim.check({ "type": "stop", "unit": 0, "args": {} })
		_assert_fields(result, ["ok", "reason", "detail"] as Array[String], "check result")
		assert_false(result["ok"], "unknown unit fails check")


func test_events_match_envelope_and_drain() -> void:
	for sim: RefCounted in _backends():
		sim.submit({ "type": "stop", "unit": 0, "args": {} })
		sim.step(1)
		var events: Array[Dictionary] = sim.take_events()
		assert_eq(events.size(), 1)
		_assert_fields(events[0], ["tick", "type", "unit", "data"] as Array[String], "event")
		assert_eq(events[0]["type"], "command_rejected")
		assert_true(sim.take_events().is_empty())
