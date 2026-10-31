class_name StandingOrdersMock extends RefCounted
## Invented data and rules for the standing-orders spike (workplan section 4).
## It answers one question for the owner: is setting policy fun? Nothing here
## touches the simulation, and all of it can be deleted without other changes.

const FLEET_DRONES := 6
const RULES: Array[Dictionary] = [
	{ "id": "keep_ore", "text": "Keep ore stock above", "value": 200, "unit": "t", "max": 2000, "step": 50, "on": true },
	{ "id": "refuel", "text": "Refuel any craft below", "value": 25, "unit": "% propellant", "max": 90, "step": 5, "on": true },
	{ "id": "trip_limit", "text": "Refuse trips longer than", "value": 10, "unit": "min", "max": 120, "step": 5, "on": false },
	{ "id": "power_reserve", "text": "Hold back for the station", "value": 15, "unit": "% power", "max": 60, "step": 5, "on": true },
	{ "id": "replace_drones", "text": "Keep this many drones working", "value": 4, "unit": "drones", "max": 12, "step": 1, "on": true },
]
const GRANTS: Array[Dictionary] = [
	{ "id": "reassign", "text": "Reassign drones between jobs", "on": true },
	{ "id": "spend_propellant", "text": "Spend depot propellant", "on": true },
	{ "id": "fabricate", "text": "Start fabrication runs", "on": false },
	{ "id": "build_drones", "text": "Build new drones", "on": false },
]


static func new_rules() -> Array[Dictionary]:
	return RULES.duplicate(true)


static func new_grants() -> Array[Dictionary]:
	return GRANTS.duplicate(true)


## What the core says it would do. Rules are read in list order, so moving one
## up gives it first claim on the drones. Returns { state, text } lines, where
## state is `ok`, `limited` or `blocked`.
static func project(rules: Array[Dictionary], grants: Array[Dictionary]) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var allowed: Dictionary = {}
	for grant: Dictionary in grants:
		allowed[grant["id"]] = grant["on"]
	var free_drones := FLEET_DRONES
	for rule: Dictionary in rules:
		if rule["on"]:
			free_drones = _project_rule(rule, allowed, free_drones, lines)
	if lines.is_empty():
		lines.append({ "state": "limited", "text": "No standing orders. The core waits for you." })
	return lines


static func _project_rule(rule: Dictionary, allowed: Dictionary, free_drones: int, lines: Array[Dictionary]) -> int:
	match rule["id"]:
		"keep_ore":
			var needed := clampi(rule["value"] / 100, 1, FLEET_DRONES)
			if not allowed["reassign"]:
				lines.append({ "state": "blocked", "text": "Ore target needs drones moved, but you have not allowed reassignment." })
				return free_drones
			var used := mini(needed, free_drones)
			var state := "ok" if used == needed else "limited"
			lines.append({ "state": state, "text": "Ore: %d of %d drones needed on mining." % [used, needed] })
			return free_drones - used
		"refuel":
			if allowed["spend_propellant"]:
				lines.append({ "state": "ok", "text": "Fuel: craft refuel at %d%%, then return to work." % rule["value"] })
			else:
				lines.append({ "state": "blocked", "text": "Refuelling needs depot propellant, which you have not allowed." })
		"trip_limit":
			var state := "ok" if rule["value"] >= 15 else "limited"
			lines.append({ "state": state, "text": "Range: trips over %d min refused. The far asteroids take 15 min." % rule["value"] })
		"power_reserve":
			var state := "ok" if rule["value"] <= 30 else "limited"
			lines.append({ "state": state, "text": "Power: %d%% reserved, refinery runs on the rest." % rule["value"] })
		"replace_drones":
			if rule["value"] <= FLEET_DRONES:
				lines.append({ "state": "ok", "text": "Fleet: %d working, target %d." % [FLEET_DRONES, rule["value"]] })
			elif allowed["build_drones"] and allowed["fabricate"]:
				lines.append({ "state": "ok", "text": "Fleet: building %d more drones." % (rule["value"] - FLEET_DRONES) })
			else:
				lines.append({ "state": "blocked", "text": "Fleet target needs new drones. Allow fabrication and drone building." })
	return free_drones
