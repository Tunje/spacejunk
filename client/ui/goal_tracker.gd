class_name GoalTracker extends RefCounted
## Follows the ten slice checks (spec section 7.6) from events and the view. Goals
## can finish in any order, and the current goal is the first one still open.

const GOALS: Array[Dictionary] = [
	{ "id": "scan", "title": "Scan an asteroid",
		"hint": "Press Undock in the Orders panel, top right. Open the Map (M), click a rock, press Move to, then Scan on arrival." },
	{ "id": "mine", "title": "Mine ore",
		"hint": "Click the scanned rock and choose a Mine order. Stop when you have enough." },
	{ "id": "haul", "title": "Haul ore to the station",
		"hint": "Click Station, Move to, Dock, then Unload the ore." },
	{ "id": "refine", "title": "Refine ore into metal",
		"hint": "Open Jobs (J), pick the Ore Refinery and Start a recipe." },
	{ "id": "fabricate", "title": "Fabricate a component",
		"hint": "Open Jobs (J), pick the Fabricator and Start a component." },
	{ "id": "install", "title": "Install a part on your ship",
		"hint": "Fabricate a Heat Radiator, dock, open Fit (G), pick it and pick a connector on the hull." },
	{ "id": "drone", "title": "Build a mining drone",
		"hint": "Fabricate a Mining Drone. It appears at a free station port." },
	{ "id": "handover", "title": "Hand the job to an AI core",
		"hint": "Fit an Assisted Core to the drone, then in Auto (K) use it and press Repeat this route." },
	{ "id": "expand", "title": "Expand the station",
		"hint": "Fabricate Ore Storage, select the Station, open Fit (G) and attach it to a free connector." },
	{ "id": "fix", "title": "Hit a fitting limit and fix it",
		"hint": "Try a second Mining Laser on the ship: it fails on heat, 280 of 200 kW. Fit a Heat Radiator, then the laser." },
]
const LIMIT_REASONS: Array[String] = ["over_mass_limit", "over_power_budget", "over_heat_budget"]

var done: Dictionary = {}
var _blocked_items: Dictionary = {}


## What a save must keep: event-based goals cannot be worked out from a view.
func save_state() -> Dictionary:
	return { "done": done.duplicate(), "blocked_items": _blocked_items.duplicate() }


func restore_state(state: Dictionary) -> void:
	done = state.get("done", {}).duplicate()
	_blocked_items = state.get("blocked_items", {}).duplicate()


func complete(id: String) -> bool:
	if done.has(id):
		return false
	done[id] = true
	return true


func done_count() -> int:
	return done.size()


## The first open goal, or {} when all ten are done.
func current() -> Dictionary:
	for goal: Dictionary in GOALS:
		if not done.has(goal["id"]):
			return goal
	return {}


## Goals finished by the view alone, for state that may predate this client run.
func observe_view(view: Dictionary, items: Dictionary) -> Array[String]:
	var finished: Array[String] = []
	if not view["deposits"].is_empty():
		_finish(finished, "scan")
	for id: int in view["units"]:
		var unit: Dictionary = view["units"][id]
		if unit["kind"] == "drone":
			_finish(finished, "drone")
		if unit["kind"] != "station" and GoalTracker._holds_ore(unit, items):
			_finish(finished, "mine")
		if unit["kind"] == "station" and GoalTracker._holds_ore(unit, items):
			_finish(finished, "haul")
	return finished


## Goals finished by one event.
func observe_event(event: Dictionary, view: Dictionary, defs: Dictionary) -> Array[String]:
	var finished: Array[String] = []
	var data: Dictionary = event["data"]
	match event["type"]:
		"job_finished":
			match defs["recipes"].get(data["recipe"], {}).get("facility", ""):
				"refinery":
					_finish(finished, "refine")
				"fabricator":
					_finish(finished, "fabricate")
		"unit_created":
			_finish(finished, "drone")
		"task_cycle_done":
			_finish(finished, "handover")
		"part_attached":
			_on_part_attached(finished, event["unit"], data["part"], view)
	return finished


## The fitting screen refuses a bad fit before it is sent, so no event says so.
func note_fit_blocked(item: String, reason: String) -> void:
	if LIMIT_REASONS.has(reason):
		_blocked_items[item] = true


func _on_part_attached(finished: Array[String], unit_id: int, part_id: int, view: Dictionary) -> void:
	var unit: Dictionary = view["units"].get(unit_id, {})
	if unit.is_empty():
		return
	_finish(finished, "expand" if unit["kind"] == "station" else "install")
	for part: Dictionary in InspectText.flatten(unit["parts"]):
		if part["id"] == part_id and _blocked_items.has(part["def"]):
			_finish(finished, "fix")


func _finish(finished: Array[String], id: String) -> void:
	if complete(id):
		finished.append(id)


static func _holds_ore(unit: Dictionary, items: Dictionary) -> bool:
	for item: String in unit["inventory"]:
		if unit["inventory"][item] > 0 and items.get(item, {}).get("cargo_class", "") == "ore":
			return true
	return false


static func title_of(id: String) -> String:
	for goal: Dictionary in GOALS:
		if goal["id"] == id:
			return goal["title"]
	return id
