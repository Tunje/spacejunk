class_name SimContext
extends RefCounted
## What a running tick hands to systems: the state, definitions, RNG, and the per-tick event and
## delta buffers. The buffers are empty between ticks, so nothing here but state is saved.

var state: Dictionary
var defs: Dictionary
var rng: SimRng
## The tick being run. state["tick"] still holds the previous tick until commit.
var tick := 0
var phase := 0
## Per-tick figures for the ledgers. Rebuilt each tick and never saved.
var flows := {}
## UnitIndex entries by unit ID. Derived, so never saved.
var index := {}
## LowFlight's ground memo by unit ID: the last cell under each unit in low flight and the ground
## radius of cells it has met. Only a starting point for the search, which ends at the same cell
## without it, so it is derived and never saved (A24).
var ground_memo := {}
## Why the last coast horizon was 0, set by the system that capped it (A33).
var coast_cap := ""
## The view's power.sun_tick by unit (A48), as { key, tick }: the tick holds while the unit's motion
## record, the key, is unchanged and the tick is still ahead, since everything else it depends on
## rides fixed rails. Derived, never saved, and never read by the simulation.
var sun_memo := {}
## During a coast's horizon pass, the most ticks it can skip whatever the system being asked says:
## the call's own limit and every horizon before it (A46). A system may stop work on a horizon once
## it reaches this, since more can't lengthen the skip. Derived, never saved.
var coast_limit := 0

var _events: Array[Dictionary] = []
var _deltas: Array[Dictionary] = []


func _init(state_value: Dictionary, defs_value: Dictionary) -> void:
	state = state_value
	defs = defs_value
	rng = SimRng.new(state["rng"], state["seed"])


func begin_tick(tick_value: int) -> void:
	tick = tick_value
	flows = {}


## Issues the next runtime entity ID.
func new_id() -> int:
	var id: int = state["next_entity_id"]
	state["next_entity_id"] = id + 1
	return id


## Buffers an event for phase 8. Use unit 0 for an event with no unit.
func emit_event(type: String, unit: int, data: Dictionary) -> void:
	_events.append({
		"tick": tick, "type": type, "unit": unit, "data": data,
		"phase": phase, "seq": _events.size(),
	})


## Records a change for phase 6. Deltas apply in ascending owner ID, then recording order.
func record_delta(owner_id: int, system: SimSystem, payload: Dictionary) -> void:
	_deltas.append({ "owner": owner_id, "seq": _deltas.size(), "system": system, "payload": payload })


func take_deltas() -> Array[Dictionary]:
	var deltas := _deltas
	_deltas = []
	deltas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["owner"] != b["owner"]:
			return a["owner"] < b["owner"]
		return a["seq"] < b["seq"])
	return deltas


## The tick's events in contract order: phase, then entity ID, then emission order.
func take_events() -> Array[Dictionary]:
	var events := _events
	_events = []
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["phase"] != b["phase"]:
			return a["phase"] < b["phase"]
		if a["unit"] != b["unit"]:
			return a["unit"] < b["unit"]
		return a["seq"] < b["seq"])
	for event in events:
		event.erase("phase")
		event.erase("seq")
	return events
