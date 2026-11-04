class_name FlightLogic extends RefCounted
## Text and orders for manual flight. What a burn does is always the Sim's answer,
## from check(plan_burn); nothing here works out an orbit or a drift.

const UM_PER_M := 1_000_000
const AXES: Array[String] = ["prograde_um_s", "normal_um_s", "radial_um_s"]
## Words for each axis, positive then negative.
const AXIS_WORDS: Dictionary = {
	"prograde_um_s": ["prograde", "retrograde"],
	"normal_um_s": ["normal", "anti-normal"],
	"radial_um_s": ["radial out", "radial in"],
}


static func burn_command(unit_id: int, tick: int, components: Array) -> Dictionary:
	var args: Dictionary = { "tick": tick }
	for index in AXES.size():
		args[AXES[index]] = int(components[index])
	return { "type": "plan_burn", "unit": unit_id, "args": args }


static func cancel_command(unit_id: int, burn_id: int) -> Dictionary:
	return { "type": "cancel_burn", "unit": unit_id, "args": { "burn": burn_id } }


## m/s as typed in the screen to whole um/s for the order.
static func to_um_s(m_s: float) -> int:
	return roundi(m_s * UM_PER_M)


static func speed(um_s: int) -> String:
	var m_s := absf(um_s / float(UM_PER_M))
	if m_s >= 1000.0:
		return "%.2f km/s" % (m_s / 1000.0)
	return "%.1f m/s" % m_s


static func speed_of(vel_um_s: Array) -> int:
	return IntMath.dist(vel_um_s, [0, 0, 0])


## "20.0 m/s prograde, 5.0 m/s radial in", leaving out zero axes.
static func components_text(burn: Dictionary) -> String:
	var parts: PackedStringArray = []
	for axis: String in AXES:
		var value: int = burn.get(axis, 0)
		if value != 0:
			parts.append("%s %s" % [FlightLogic.speed(value), AXIS_WORDS[axis][0 if value > 0 else 1]])
	return ", ".join(parts) if not parts.is_empty() else "no change"


## Where the craft is and how it is moving, in one line.
static func place_text(view: Dictionary, unit_id: int) -> String:
	var unit: Dictionary = view["units"].get(unit_id, {})
	if unit.is_empty():
		return ""
	if not unit["dock"].is_empty():
		return "Docked at %s: undock to fly" % view["units"][unit["dock"]["target_unit"]]["name"]
	if not unit.get("orbit", {}).is_empty():
		var parent := FlightLogic.body_name(view, unit["orbit"]["parent"])
		if OrbitPath.is_open(unit["orbit"]):
			return "Escaping %s: %s" % [parent, FlightLogic.orbit_text(view, unit["orbit"])]
		return "Orbiting %s: %s" % [parent, FlightLogic.orbit_text(view, unit["orbit"])]
	var frame: Dictionary = view.get("frames", {}).get(unit.get("frame", 0), {})
	var where: String = "In %s" % frame["name"] if not frame.is_empty() else "In open space"
	var moving := FlightLogic.speed_of(unit.get("vel_um_s", [0, 0, 0]))
	return "%s, %s" % [where, "drifting %s" % FlightLogic.speed(moving) if moving > 0 else "holding still"]


static func body_name(view: Dictionary, body_id: int) -> String:
	return view["bodies"].get(body_id, {}).get("name", "its parent")


## "150 km x 220 km": periapsis and apoapsis heights above the parent's surface.
## An escape path has no apoapsis: "periapsis 150 km, escaping".
static func orbit_text(view: Dictionary, orbit: Dictionary) -> String:
	var radius: float = float(view["bodies"].get(orbit.get("parent", 0), {}).get("radius_mm", 0))
	var apsides := OrbitPath.apsides_mm(orbit)
	if OrbitPath.is_open(orbit):
		return "periapsis %s, escaping" % OrderText.metres(roundi(apsides[0] - radius))
	return "%s x %s" % [OrderText.metres(roundi(apsides[0] - radius)), OrderText.metres(roundi(apsides[1] - radius))]


## The preview's two lines from check's detail: cost, then what follows the burn.
static func preview_lines(detail: Dictionary, view: Dictionary, unit_id: int, ticks_per_second: int) -> PackedStringArray:
	var unit: Dictionary = view["units"][unit_id]
	var cost := "Delta-v %s, %s propellant, about %s" % [
		FlightLogic.speed(detail["dv_um_s"]), OrderText.tonnes(detail["propellant_g"]),
		OrderText.duration(float(detail["burn_ticks"]) / ticks_per_second),
	]
	if detail.get("approximate", false):
		cost += " (estimated: too long to fly through ahead)"
	var aboard: int = unit["inventory"].get("propellant", 0)
	if detail["propellant_g"] > aboard:
		cost += ". Only %s aboard, so it will stop short" % OrderText.tonnes(aboard)
	var after := ""
	if not unit.get("orbit", {}).is_empty():
		var orbit: Dictionary = detail.get("orbit", {})
		var parent := FlightLogic.body_name(view, orbit.get("parent", unit["orbit"]["parent"]))
		if orbit.is_empty():
			after = "That path is not flown yet"
		elif OrbitPath.is_open(orbit):
			var radius: float = float(view["bodies"].get(orbit.get("parent", 0), {}).get("radius_mm", 0))
			after = "Then escaping %s, periapsis %s" % [parent, OrderText.metres(roundi(OrbitPath.apsides_mm(orbit)[0] - radius))]
		else:
			after = "Then %s above %s" % [FlightLogic.orbit_text(view, orbit), parent]
	else:
		var moving := FlightLogic.speed_of(detail.get("vel_um_s", [0, 0, 0]))
		after = "Then drifting %s" % FlightLogic.speed(moving) if moving > 0 else "Then holding still"
		var frame: Dictionary = view.get("frames", {}).get(unit.get("frame", 0), {})
		if detail.get("leaves_frame", false) and not frame.is_empty():
			var seconds := OrbitPath.seconds_to_edge(unit["pos_mm"], detail["vel_um_s"], frame["radius_mm"])
			after += ", leaving %s in %s" % [frame["name"], OrderText.duration(seconds)] if seconds >= 0.0 else ""
	return PackedStringArray([cost, after])


## A burn whose tick finds the craft on another order is dropped (A11), so say so
## while it is busy. "" when it is free, or already burning.
static func busy_note(unit: Dictionary) -> String:
	var op: String = unit["op"]["type"]
	if op != "idle" and op != "burning":
		return "%s now: a burn that starts before that ends is dropped." % OrderText.operation(op)
	if not unit["route"].is_empty() or unit["task"] != 0:
		return "Busy with an order: a burn that starts before it ends is dropped."
	return ""


## A planned burn's row: "In 12 s: 20.0 m/s prograde".
static func planned_text(burn: Dictionary, tick: int, ticks_per_second: int) -> String:
	return "In %s: %s" % [OrderText.duration(float(burn["tick"] - tick) / ticks_per_second), FlightLogic.components_text(burn)]


static func running_text(burn: Dictionary) -> String:
	return "Burning: %s of %s" % [FlightLogic.speed(burn["done_um_s"]), FlightLogic.speed(burn["dv_um_s"])]
