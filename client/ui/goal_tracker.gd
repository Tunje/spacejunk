class_name GoalTracker extends RefCounted
## Follows a start's goals from events and the view: the reference start's ten slice
## checks (spec section 7.6), or the new start's list. Goals can finish in any order,
## and the current goal is the first one still open.
##
## A goal is { id, title, hint } plus optional fields: `trigger`, what finishes it
## (its id when absent), `built_only`, counting only parts fitted to a unit built in
## this game, and `after`, a goal that must be done first.

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
		"hint": "Open Jobs (J), pick the Fabricator and Start Structural Frame." },
	{ "id": "install", "title": "Install a part on your ship",
		"hint": "Fabricate an Ore Container, dock your ship, open Fit (G), pick it and pick a free connector on the ship's hull." },
	{ "id": "drone", "title": "Build a mining drone",
		"hint": "Fabricate a Small Craft: it appears bare at a free station port. Fabricate a Small Solar Panel, Small Heat Radiator, Small Propellant Tank, Small Thruster, Small Ore Container and Small Mining Laser. Select the craft, open Fit (G) and fit them in that order. Solar and radiator go on first, because a bare craft refuses the laser and thruster. The thruster goes under the tank." },
	{ "id": "handover", "title": "Hand the job to an AI core",
		"hint": "Fabricate an Assisted Core, which takes a Basic Core. Fit it to the Small Craft: it fits only once the solar panel and radiator are on. Then in Auto (K) use it and press Repeat this route." },
	{ "id": "expand", "title": "Expand the station",
		"hint": "Fabricate Ore Storage, select the Station, open Fit (G) and attach it to a free connector." },
	{ "id": "fix", "title": "Hit a fitting limit and fix it",
		"hint": "Try a second Mining Laser on the ship: it fails on heat, 280 of 200 kW. Fit a Heat Radiator, then the laser." },
]
## Lists by scenario ID; any other start uses the reference list.
const NEW_START_GOALS: Array[Dictionary] = [
	{ "id": "scan", "title": "Scan a rock",
		"hint": "Open the Map (M), click a rock in the Cluster and press Move to. On arrival, press Scan in the Orders panel." },
	{ "id": "science", "title": "Earn your first science points",
		"hint": "A finished scan pays survey points. Stay at the rock and Measure its composition for more. New rocks and bodies are worth the most." },
	{ "id": "mine", "title": "Mine ore",
		"hint": "Click a scanned rock and choose Mine. Mine White Rock too: its water ice refines into propellant." },
	{ "id": "refine", "title": "Refine ore",
		"hint": "Open Jobs (J), pick the probe's Compact Refinery and Start a recipe. Refine Water Ice whenever propellant runs low." },
	{ "id": "fabricate", "title": "Fabricate a component",
		"hint": "Open Jobs (J), pick the Compact Fabricator and Start Structural Frame." },
	{ "id": "station", "title": "Build a station",
		"hint": "In Jobs (J), fabricate a Small Station on the Compact Fabricator. It is built docked at the probe's port." },
	{ "id": "install", "title": "Install a part on something you built", "built_only": true,
		"hint": "Fabricate a Solar Panel, select your station, open Fit (G) and attach it to a free connector on its hub." },
	{ "id": "fix", "title": "Hit a fitting limit and fix it",
		"hint": "Try fitting a part the station can't power yet, such as a Research Lab. Fit more Solar Panels or a Battery Bank, then fit it again." },
	{ "id": "haul", "title": "Haul ore to the station",
		"hint": "With the probe docked at your station, Unload ore into it. Fit an Ore Storage first if the station has no ore hold." },
	{ "id": "research", "title": "Prove a new tech",
		"hint": "Fit a Research Lab and a Basic Core on the station. Survey three rocks and map Frost's gravity field: select Frost and Measure. You can do that without landing: stay in the cluster for one lap. Prove Autonomous Navigation at the lab in Jobs (J), then fabricate the Assisted Core prototype and bench-test it at the lab. To land on Frost too, fill the tank from White Rock's ice first, empty the goods hold, and leave straight from the station. The landing and the climb back take most of a tank." },
	{ "id": "drone", "title": "Build a mining drone",
		"hint": "Fabricate a Small Craft: it appears bare at a free port. Fabricate a Small Solar Panel, Small Heat Radiator, Small Propellant Tank, Small Thruster, Small Ore Container and Small Mining Laser, and fit them in that order with Fit (G). The thruster goes under the tank." },
	{ "id": "handover", "title": "Hand the job to an AI core",
		"hint": "Fabricate an Assisted Core and fit it to the drone. Then in Auto (K) use it and press Repeat this route." },
	{ "id": "expand", "title": "Expand the station", "after": "handover",
		"hint": "Fabricate Ore Storage or another module, select the station, open Fit (G) and attach it." },
]
const LIMIT_REASONS: Array[String] = ["over_mass_limit", "over_power_budget", "over_heat_budget"]
## What makes a drone a working drone. By capability, so any part that gives one counts.
const DRONE_NEEDS: Array[String] = ["mine", "thruster", "ore", "propellant"]

var goals: Array[Dictionary] = GOALS
var done: Dictionary = {}
var _blocked_items: Dictionary = {}
## Units built in this game, from unit_created, for `built_only` goals.
var _built: Dictionary = {}


func _init(scenario := "") -> void:
	goals = GoalTracker.goals_for(scenario)


static func goals_for(scenario: String) -> Array[Dictionary]:
	if scenario == "new_start":
		return NEW_START_GOALS
	return GOALS


## What a save must keep: event-based goals cannot be worked out from a view.
func save_state() -> Dictionary:
	return { "done": done.duplicate(), "blocked_items": _blocked_items.duplicate(), "built": _built.keys() }


func restore_state(state: Dictionary) -> void:
	done = state.get("done", {}).duplicate()
	_blocked_items = state.get("blocked_items", {}).duplicate()
	_built.clear()
	for id: Variant in state.get("built", []):
		_built[int(id)] = true


func complete(id: String) -> bool:
	if done.has(id):
		return false
	done[id] = true
	return true


func done_count() -> int:
	return done.size()


## The first open goal, or {} when all are done.
func current() -> Dictionary:
	for goal: Dictionary in goals:
		if not done.has(goal["id"]):
			return goal
	return {}


## Goals finished by the view alone, for state that may predate this client run.
func observe_view(view: Dictionary, items: Dictionary, modules: Dictionary) -> Array[String]:
	var finished: Array[String] = []
	if not view["deposits"].is_empty():
		_finish(finished, "scan")
	# C12 and C13's goals that the view alone shows, so a loaded game is right too.
	if int(view.get("science", {}).get("earned", 0)) > 0:
		_finish(finished, "science")
	if view.get("research", {}).get("designs", {}).get("assisted_core", "") == "qualified":
		_finish(finished, "research")
	for id: int in view["units"]:
		var unit: Dictionary = view["units"][id]
		if unit["kind"] == "drone" and GoalTracker._is_working_drone(unit, modules):
			_finish(finished, "drone")
		if unit["kind"] != "station" and GoalTracker._holds_ore(unit, items):
			_finish(finished, "mine")
		if unit["kind"] == "station" and GoalTracker._holds_ore(unit, items):
			_finish(finished, "haul")
		if unit["kind"] == "station":
			_finish(finished, "station")
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
		"task_cycle_done":
			_finish(finished, "handover")
		"part_attached":
			_on_part_attached(finished, event["unit"], data["part"], view)
		"unit_created":
			_built[int(data.get("unit", 0))] = true
			if defs.get("templates", {}).get(data.get("def", ""), {}).get("kind", "") == "station":
				_finish(finished, "station")
		# C12's research events: absent until C12, so these wait on fields that exist.
		"science_gained":
			if int(data.get("points", 0)) > 0:
				_finish(finished, "science")
		"design_qualified":
			if data.get("design", "") == "assisted_core":
				_finish(finished, "research")
	return finished


## The fitting screen refuses a bad fit before it is sent, so no event says so.
func note_fit_blocked(item: String, reason: String) -> void:
	if LIMIT_REASONS.has(reason):
		_blocked_items[item] = true


func _on_part_attached(finished: Array[String], unit_id: int, part_id: int, view: Dictionary) -> void:
	var unit: Dictionary = view["units"].get(unit_id, {})
	if unit.is_empty():
		return
	if unit["kind"] == "station":
		_finish(finished, "expand")
	# An install counts on a ship, or, for a `built_only` goal, on anything built here.
	if unit["kind"] == "ship" or _built.has(unit_id):
		_finish(finished, "install", unit_id, unit["kind"] == "ship")
	for part: Dictionary in InspectText.flatten(unit["parts"]):
		if part["id"] == part_id and _blocked_items.has(part["def"]):
			_finish(finished, "fix")


## Finishes every open goal in this list with that trigger, unless it waits on an
## `after` goal. A `built_only` goal needs `unit_id` to be a unit built here; any
## other needs `plain`, which an install gives only on a ship.
func _finish(finished: Array[String], trigger: String, unit_id := 0, plain := true) -> void:
	for goal: Dictionary in goals:
		if goal.get("trigger", goal["id"]) != trigger:
			continue
		if goal.has("after") and not done.has(goal["after"]):
			continue
		if goal.get("built_only", false):
			if not _built.has(unit_id):
				continue
		elif not plain:
			continue
		if complete(goal["id"]):
			finished.append(goal["id"])


static func _holds_ore(unit: Dictionary, items: Dictionary) -> bool:
	for item: String in unit["inventory"]:
		if unit["inventory"][item] > 0 and items.get(item, {}).get("cargo_class", "") == "ore":
			return true
	return false


static func _is_working_drone(unit: Dictionary, modules: Dictionary) -> bool:
	var found: Dictionary = {}
	for part: Dictionary in InspectText.flatten(unit["parts"]):
		var capabilities: Dictionary = modules[part["def"]]["capabilities"]
		found.merge(capabilities)
		found.merge(capabilities.get("storage", {}))
	return found.has_all(DRONE_NEEDS)


func title_of(id: String) -> String:
	for goal: Dictionary in goals:
		if goal["id"] == id:
			return goal["title"]
	return id
