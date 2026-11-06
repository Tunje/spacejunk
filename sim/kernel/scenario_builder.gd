class_name ScenarioBuilder
extends RefCounted
## Builds a new game's entities from a scenario, issuing IDs in the order of schemas.md section
## 14: each body, then its deposits, then each frame, then each unit, then its parts.

const MAX_WORLD_G := 9_000_000_000_000_000_000
const PPM := 1_000_000
const MILLIDEGREES_PER_TURN := 360_000


## Fills the state from a scenario in sim units. Returns "" or what is wrong with it.
static func populate(ctx: SimContext, scenario: Dictionary, deposits: Dictionary) -> String:
	var keys := {}
	for body: Dictionary in scenario["bodies"]:
		_add_body(ctx, body, deposits, keys)
	for entry: Dictionary in scenario.get("frames", []):
		keys[entry["key"]] = ctx.new_id()
	var problem := _place_bodies(ctx, scenario, keys)
	if problem != "":
		return problem
	for entry: Dictionary in scenario["units"]:
		problem = _add_unit(ctx, entry, keys)
		if problem != "":
			return problem
	for entry: Dictionary in scenario["units"]:
		if entry["dock"] != null:
			problem = _dock(ctx, entry, keys)
			if problem != "":
				return problem
	problem = Research.start_theories(ctx, scenario.get("research", {}).get("theories", []))
	if problem != "":
		return problem
	return _set_world_total(ctx)


static func _add_body(ctx: SimContext, entry: Dictionary, deposits: Dictionary, keys: Dictionary) -> void:
	var id := ctx.new_id()
	keys[entry["key"]] = id
	var deposit_ids: Array[int] = []
	var body := {
		"id": id, "name": entry["name"], "kind": entry["kind"], "pos_mm": entry.get("pos_mm", [0, 0, 0]).duplicate(),
		"radius_mm": entry["radius_mm"], "visual_seed": entry["visual_seed"], "scanned": false,
		"frame": 0, "orbit": {}, "gm": entry.get("gm", 0), "soi_mm": 0, "planet": entry.get("planet", {}).duplicate(),
	}
	ctx.state["bodies"][id] = body
	for def: String in entry["deposits"]:
		var deposit: Dictionary = deposits[def]
		var deposit_id := ctx.new_id()
		deposit_ids.append(deposit_id)
		ctx.state["deposits"][deposit_id] = {
			"id": deposit_id, "body": id, "item": deposit["item"], "remaining_g": deposit["mass_g"],
			"hardness": deposit["hardness"], "found": false,
		}
	body["deposits"] = Array(deposit_ids)


## Frames, then each body's orbit or frame, once every key has its ID.
static func _place_bodies(ctx: SimContext, scenario: Dictionary, keys: Dictionary) -> String:
	for entry: Dictionary in scenario.get("frames", []):
		var orbit := _orbit(ctx, entry["orbit"], keys)
		if orbit.is_empty():
			return "frame %s orbits nothing with gravity" % entry["key"]
		var id: int = keys[entry["key"]]
		ctx.state["frames"][id] = {
			"id": id, "name": entry.get("name", entry["key"]), "radius_mm": entry["radius_mm"],
			"orbit": orbit, "pos_mm": OrbitMath.position_at(orbit, ctx.state["tick"]),
		}
	for entry: Dictionary in scenario["bodies"]:
		var body: Dictionary = ctx.state["bodies"][keys[entry["key"]]]
		if entry.has("orbit"):
			body["orbit"] = _orbit(ctx, entry["orbit"], keys)
			if body["orbit"].is_empty():
				return "body %s orbits nothing with gravity" % entry["key"]
			body["pos_mm"] = OrbitMath.position_at(body["orbit"], ctx.state["tick"])
			if body["gm"] > 0:
				var parent_gm: int = ctx.state["bodies"][body["orbit"]["parent"]]["gm"]
				body["soi_mm"] = OrbitMath.soi_mm(body["orbit"]["a_mm"], body["gm"], parent_gm)
		if entry.has("frame"):
			if not ctx.state["frames"].has(keys.get(entry["frame"], 0)):
				return "body %s is in an unknown frame" % entry["key"]
			body["frame"] = keys[entry["frame"]]
	for entry: Dictionary in scenario.get("frames", []):
		var problem := _frame_fits(ctx, ctx.state["frames"][keys[entry["key"]]])
		if problem != "":
			return "frame %s %s" % [entry["key"], problem]
	return ""


## "" if a frame, with the least leave margin past its radius, stays inside its parent's sphere of
## influence all round its orbit (orbital_flight.md 11.20). A frame has no gravity, so a unit
## drifting in it must become an orbit again before it could pass the SOI.
static func _frame_fits(ctx: SimContext, frame: Dictionary) -> String:
	var parent: Dictionary = ctx.state["bodies"][frame["orbit"]["parent"]]
	var soi: int = parent.get("soi_mm", 0)
	if soi <= 0:
		return ""
	var reach := BurnSystem.apoapsis_mm(frame["orbit"]) + int(frame["radius_mm"]) 		+ 2 * BurnSystem.MIN_LEAVE_MARGIN_MM
	if reach > soi:
		return "reaches past the sphere of influence of %s" % parent["name"]
	return ""


## An orbit record from scenario data, or {} if its parent is not a body with gravity. Data states
## the eccentricity in parts per million and angles in millidegrees, so no float is involved.
static func _orbit(ctx: SimContext, data: Dictionary, keys: Dictionary) -> Dictionary:
	var parent: int = keys.get(data["parent"], 0)
	var gm: int = ctx.state["bodies"].get(parent, {}).get("gm", 0)
	if gm <= 0:
		return {}
	var dirs := OrbitMath.directions(_angle(data, "inclination_mdeg"), _angle(data, "node_mdeg"),
		_angle(data, "periapsis_mdeg"))
	var e := IntMath.mul_div(data.get("e_ppm", 0), OrbitMath.ONE, PPM)
	var orbit := OrbitMath.make_orbit(gm, data["a_mm"], e, dirs[0], dirs[1],
		_angle(data, "mean_anomaly_mdeg"), 0)
	orbit["parent"] = parent
	return orbit


static func _angle(data: Dictionary, key: String) -> int:
	return IntMath.mul_div(posmod(data.get(key, 0), MILLIDEGREES_PER_TURN), OrbitMath.TURN, MILLIDEGREES_PER_TURN)


static func _add_unit(ctx: SimContext, entry: Dictionary, keys: Dictionary) -> String:
	var id := Units.create(ctx, entry["template"], entry["name"], entry["pos_mm"])
	keys[entry["key"]] = id
	if entry.has("frame"):
		if not ctx.state["frames"].has(keys.get(entry["frame"], 0)):
			return "unit %s is in an unknown frame" % entry["key"]
		ctx.state["units"][id]["frame"] = keys[entry["frame"]]
	_fill_batteries(ctx, id)
	var inventory: Dictionary = ctx.state["units"][id]["inventory"]
	for stock: Dictionary in entry["inventory"]:
		Units.add_stock(inventory, stock["item"], stock["grams"])
	return ""


## Batteries start full in a scenario, and empty anywhere else.
static func _fill_batteries(ctx: SimContext, unit: int) -> void:
	for part_id in Units.part_ids(ctx.state, unit):
		var battery: Dictionary = Units.module_of(ctx.state, ctx.defs, part_id)["capabilities"].get("battery", {})
		if not battery.is_empty():
			ctx.state["parts"][part_id]["stored_j"] = battery["capacity_j"]


## Docks a unit at the start, in the state it would have after arrival and docking.
static func _dock(ctx: SimContext, entry: Dictionary, keys: Dictionary) -> String:
	var plan: Dictionary = entry["dock"]
	var id: int = keys[entry["key"]]
	var host: int = keys[plan["host"]]
	var ports := Units.ports(ctx.state, ctx.defs, id)
	var host_ports := Units.ports(ctx.state, ctx.defs, host)
	if plan["port"] >= ports.size() or plan["host_port"] >= host_ports.size():
		return "%s docks at a port that does not exist" % entry["key"]
	var unit: Dictionary = ctx.state["units"][id]
	unit["dock"] = {
		"port": ports[plan["port"]], "target_unit": host, "target_port": host_ports[plan["host_port"]],
	}
	unit["at_target"] = host
	return ""


## Records the matter total and checks the world limit (contracts section 1).
static func _set_world_total(ctx: SimContext) -> String:
	var total := 0
	var units: Dictionary = ctx.state["units"]
	for id: int in units:
		var unit_g := Units.unit_mass(ctx.state, ctx.defs, id)
		if unit_g > MAX_WORLD_G - total:
			return "world matter is over the limit"
		total += unit_g
	var deposits: Dictionary = ctx.state["deposits"]
	for id: int in deposits:
		var deposit_g: int = deposits[id]["remaining_g"]
		if deposit_g > MAX_WORLD_G - total:
			return "world matter is over the limit"
		total += deposit_g
	ctx.state["matter_start_g"] = total
	return ""
