class_name FlightLogic extends RefCounted
## Text and orders for manual flight. What a burn does is always the Sim's answer,
## from check(plan_burn); nothing here works out an orbit or a drift.

const UM_PER_M := 1_000_000
## How far ahead the flight screen follows a descent, matching FlightScreen.
const PREDICT_HORIZON_TICKS := 3000
const AXES: Array[String] = ["prograde_um_s", "normal_um_s", "radial_um_s"]
## Words for each axis, positive then negative.
const AXIS_WORDS: Dictionary = {
	"prograde_um_s": ["prograde", "retrograde"],
	"normal_um_s": ["normal", "anti-normal"],
	"radial_um_s": ["radial out", "radial in"],
}


## A55's burn options: throttle in parts per million, and how the burn steers.
const FULL_THROTTLE_PPM := 1_000_000
const STEER_FIXED := "fixed"
## The steering choices in the burn panel, in its order, with their words.
const STEERS: Array[Array] = [
	["fixed", "Hold its direction"], ["orbit", "Follow the orbit"],
	["target", "Toward the target"], ["target_retrograde", "Null motion against the target"],
]

static func burn_command(unit_id: int, tick: int, components: Array, throttle_ppm := FULL_THROTTLE_PPM,
		steer := STEER_FIXED, target := 0) -> Dictionary:
	var args: Dictionary = { "tick": tick }
	for index in AXES.size():
		args[AXES[index]] = int(components[index])
	# A55: left out at their defaults, so a plain burn is the same command as before.
	if throttle_ppm != FULL_THROTTLE_PPM:
		args["throttle_ppm"] = throttle_ppm
	if steer != STEER_FIXED:
		args["steer"] = steer
	if target != 0:
		args["target"] = target
	return { "type": "plan_burn", "unit": unit_id, "args": args }


## The lowest throttle the craft's engines allow (B29's min_throttle_ppm, full when an
## engine gives none): the highest minimum among its thrusters, which all fire together.
static func min_throttle_ppm(unit: Dictionary, modules: Dictionary) -> int:
	var floor_ppm := 0
	var found := false
	for part: Dictionary in InspectText.flatten(unit.get("parts", {})):
		var capabilities: Dictionary = modules.get(part["def"], {}).get("capabilities", {})
		if capabilities.has("thruster"):
			var thruster: Dictionary = capabilities["thruster"]
			found = true
			floor_ppm = maxi(floor_ppm, int(thruster.get("min_throttle_ppm", FULL_THROTTLE_PPM)))
	return floor_ppm if found else FULL_THROTTLE_PPM


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
## Whether the craft's path, its burns flown, meets the ground (A55's surface_contact_tick):
## the condition for the descent readouts and a lander's upright heading. Stepped flight
## alone isn't it: every burn in orbit is stepped.
static func near_surface(unit: Dictionary) -> bool:
	return int(unit.get("surface_contact_tick", -1)) >= 0


static func place_text(view: Dictionary, unit_id: int) -> String:
	var unit: Dictionary = view["units"].get(unit_id, {})
	if unit.is_empty():
		return ""
	if not unit["dock"].is_empty():
		return "Docked at %s: undock to fly" % view["units"][unit["dock"]["target_unit"]]["name"]
	var low: int = unit.get("stepped", 0) if FlightLogic.near_surface(unit) else 0
	if low != 0:
		var radius: float = float(view["bodies"].get(low, {}).get("radius_mm", 0))
		var motion := FlightLogic.vertical_motion(unit["pos_mm"], unit["vel_um_s"])
		var height := roundi(Vector3(unit["pos_mm"][0], unit["pos_mm"][1], unit["pos_mm"][2]).length() - radius)
		return "Low over %s: %s above datum, %s" % [FlightLogic.body_name(view, low), OrderText.metres(height),
			FlightLogic.motion_text(motion)]
	var landed: Dictionary = unit.get("landed", {})
	if not landed.is_empty():
		var radius: float = float(view["bodies"].get(landed["body"], {}).get("radius_mm", 0))
		var height := roundi(Vector3(unit["pos_mm"][0], unit["pos_mm"][1], unit["pos_mm"][2]).length() - radius)
		var side := "above" if height >= 0 else "below"
		return "Landed on %s, hex %d, %s %s datum" % [FlightLogic.body_name(view, landed["body"]), landed["cell"],
			OrderText.metres(absi(height)), side]
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
	var apsides := FlightLogic.apsides_mm(orbit)
	if OrbitPath.is_open(orbit):
		return "periapsis %s, escaping" % OrderText.metres(roundi(apsides[0] - radius))
	return "%s x %s" % [OrderText.metres(roundi(apsides[0] - radius)), OrderText.metres(roundi(apsides[1] - radius))]


## Periapsis and apoapsis from the parent's centre, as the Sim gives them on an orbit
## (A57's periapsis_mm and apoapsis_mm). Until A57, worked out from the elements.
static func apsides_mm(orbit: Dictionary) -> PackedFloat64Array:
	if orbit.has("periapsis_mm"):
		return PackedFloat64Array([float(orbit["periapsis_mm"]), float(orbit.get("apoapsis_mm", -1))])
	return OrbitPath.apsides_mm(orbit)


## A closed orbit's turn in ticks, read off the Sim's own apsis ticks (A57): the next
## periapsis and apoapsis are half a turn apart. -1 for an open path, or before A57.
static func turn_ticks(orbit: Dictionary) -> int:
	var peri := int(orbit.get("next_periapsis_tick", -1))
	var apo := int(orbit.get("next_apoapsis_tick", -1))
	if peri < 0 or apo < 0:
		return -1
	return 2 * absi(apo - peri)


## The tick the orbit next reaches its periapsis (or with `apoapsis` its apoapsis), as the
## Sim gives it (A57's next_periapsis_tick and next_apoapsis_tick), or -1 for none, such
## as no apoapsis on an escape path. Until A57, worked out from the elements.
static func apsis_tick(orbit: Dictionary, apoapsis: bool, tick: int) -> int:
	var field := "next_apoapsis_tick" if apoapsis else "next_periapsis_tick"
	if orbit.has(field):
		return int(orbit[field])
	if orbit.is_empty() or (apoapsis and OrbitPath.is_open(orbit)):
		return -1
	var wait := OrbitPath.ticks_until(orbit, tick, PI if apoapsis else 0.0)
	return tick + wait if wait >= 0 else -1


## The preview's two lines from check's detail: cost, then what follows the burn.
static func preview_lines(detail: Dictionary, view: Dictionary, unit_id: int, ticks_per_second: int) -> PackedStringArray:
	var unit: Dictionary = view["units"][unit_id]
	var cost := "Delta-v %s, %s propellant, about %s" % [
		FlightLogic.speed(detail["dv_um_s"]), OrderText.tonnes(detail["propellant_g"]),
		OrderText.duration(float(detail["burn_ticks"]) / ticks_per_second),
	]
	if detail.get("approximate", false):
		cost += " (estimated: too long to fly through ahead)"
	# D46: a finite burn lands where an instant kick would only if it starts early by
	# its lead (A54's lead_ticks, half its length), so say how much once it matters.
	var lead := int(detail.get("lead_ticks", 0))
	if lead >= ticks_per_second:
		cost += ". Start it %s before the moment it's aimed at" % OrderText.duration(float(lead) / ticks_per_second)
	var aboard: int = unit["inventory"].get("propellant", 0)
	if detail["propellant_g"] > aboard:
		cost += ". Only %s aboard, so it will stop short" % OrderText.tonnes(aboard)
	var after := ""
	if FlightLogic.near_surface(unit) or not unit.get("landed", {}).is_empty():
		# A55 flies the burn exactly here: say where the flight ends, the ground or an orbit.
		var contact: Dictionary = detail.get("contact", {})
		var orbit_after: Dictionary = detail.get("orbit", {})
		if not contact.is_empty():
			after = "Then back on the ground in %s at %s" % [
				OrderText.duration(float(int(contact["tick"]) - int(view.get("tick", 0))) / ticks_per_second),
				FlightLogic.speed(int(contact.get("speed_um_s", 0)))]
			if String(contact.get("outcome", "")).begins_with("crash"):
				after += ": a crash"
		elif not orbit_after.is_empty():
			after = "Then in orbit, %s" % FlightLogic.orbit_text(view, orbit_after)
		else:
			after = "Then %s" % FlightLogic.motion_text(FlightLogic.vertical_motion(unit["pos_mm"], detail.get("vel_um_s", [0, 0, 0])))
	elif not unit.get("orbit", {}).is_empty():
		var orbit: Dictionary = detail.get("orbit", {})
		var parent := FlightLogic.body_name(view, orbit.get("parent", unit["orbit"]["parent"]))
		if orbit.is_empty():
			after = "That path is not flown yet"
		elif OrbitPath.is_open(orbit):
			var radius: float = float(view["bodies"].get(orbit.get("parent", 0), {}).get("radius_mm", 0))
			after = "Then escaping %s, periapsis %s" % [parent, OrderText.metres(roundi(FlightLogic.apsides_mm(orbit)[0] - radius))]
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


## [up speed, across speed] in um/s for a velocity at a position round a body:
## up is along the position from the centre, positive climbing.
static func vertical_motion(pos_mm: Array, vel_um_s: Array) -> Vector2:
	var up := Vector3(pos_mm[0], pos_mm[1], pos_mm[2]).normalized()
	var v := Vector3(vel_um_s[0], vel_um_s[1], vel_um_s[2])
	var climb := v.dot(up)
	return Vector2(climb, (v - up * climb).length())


static func motion_text(motion: Vector2) -> String:
	var vertical := "holding height"
	if roundi(motion.x) > 0:
		vertical = "climbing %s" % FlightLogic.speed(roundi(motion.x))
	elif roundi(motion.x) < 0:
		vertical = "falling %s" % FlightLogic.speed(roundi(-motion.x))
	return "%s, %s across" % [vertical, FlightLogic.speed(roundi(motion.y))]


## "Touchdown in 42 s at 12.3 m/s, hex 1234", from predict's contact.
static func contact_text(found: Dictionary, tick: int, ticks_per_second: int) -> String:
	if found.is_empty():
		return "No touchdown in the next %s." % OrderText.duration(float(PREDICT_HORIZON_TICKS) / ticks_per_second)
	return "Touchdown in %s at %s, hex %d" % [OrderText.duration(float(maxi(0, found["tick"] - tick)) / ticks_per_second),
		FlightLogic.speed(found["speed_um_s"]), found["cell"]]


static func lands_safely(found: Dictionary, limit_mm_s: int) -> bool:
	return not found.is_empty() and limit_mm_s > 0 and found["speed_um_s"] <= limit_mm_s * 1000


static func legs_text(limit_mm_s: int) -> String:
	if limit_mm_s <= 0:
		return "No landing legs: any touchdown is a crash."
	return "Legs take up to %s." % FlightLogic.speed(limit_mm_s * 1000)


## The land-or-crash verdict for the predicted touchdown.
static func verdict_text(found: Dictionary, limit_mm_s: int) -> String:
	if found.is_empty():
		return FlightLogic.legs_text(limit_mm_s)
	if limit_mm_s <= 0:
		return "CRASH: no landing legs, so any touchdown is a crash."
	if FlightLogic.lands_safely(found, limit_mm_s):
		return "Lands safely: the legs take up to %s." % FlightLogic.speed(limit_mm_s * 1000)
	return "CRASH at this speed: the legs take only %s. Burn radial out to slow down." % FlightLogic.speed(limit_mm_s * 1000)


## A land or take_off check as one line: "Descent: delta-v 1.20 km/s, 640 kg
## propellant, about 31 min", or the refusal.
static func trip_cost_text(result: Dictionary, what: String, ticks_per_second: int) -> String:
	if result.is_empty():
		return ""
	if not result["ok"]:
		return OrderText.reason(result["reason"], result["detail"])
	var detail: Dictionary = result["detail"]
	return "%s: delta-v %s, %s propellant, about %s" % [what, FlightLogic.speed(detail["dv_um_s"]),
		OrderText.tonnes(detail["propellant_g"]), OrderText.duration(float(detail["ticks"]) / ticks_per_second)]


## A36: a warning when landing would leave too little propellant to get back, or ""
## when it wouldn't. A39 prices the way back to `return_target`, the frame round the
## body (0 when none, and then the take-off alone). Landing stays the player's choice.
static func return_warning(result: Dictionary, propellant_aboard_g: int, frames: Dictionary = {}) -> String:
	var detail: Dictionary = result.get("detail", {})
	if not result.get("ok", false) or not detail.get("cannot_return", false):
		return ""
	var target := int(detail.get("return_target", 0))
	var back := "take off again" if target == 0 else "get back to the %s" % frames.get(target, {}).get("name", "frame")
	var need: int = detail.get("return_propellant_g", -1)
	if need < 0:
		return "You won't be able to %s from here." % back
	var left := maxi(0, propellant_aboard_g - int(detail["propellant_g"]))
	return "You won't have enough propellant to %s (need %s, will have %s)." % [
		back, OrderText.tonnes(need), OrderText.tonnes(left)]


## A planned burn's row: "In 12 s: 20.0 m/s prograde".
static func planned_text(burn: Dictionary, tick: int, ticks_per_second: int) -> String:
	return "In %s: %s%s" % [OrderText.duration(float(burn["tick"] - tick) / ticks_per_second), FlightLogic.components_text(burn),
		FlightLogic.options_text(burn)]


## ", at 40%, following the orbit" for a burn's A55 options; "" at full and held.
static func options_text(burn: Dictionary) -> String:
	var text := ""
	var throttle := int(burn.get("throttle_ppm", FULL_THROTTLE_PPM))
	if throttle != FULL_THROTTLE_PPM:
		text += ", at %d%%" % roundi(throttle / 10_000.0)
	var steer: String = burn.get("steer", STEER_FIXED)
	for choice: Array in STEERS:
		if choice[0] == steer and steer != STEER_FIXED:
			text += ", %s" % String(choice[1]).to_lower()
	return text


static func running_text(burn: Dictionary) -> String:
	return "Burning: %s of %s" % [FlightLogic.speed(burn["done_um_s"]), FlightLogic.speed(burn["dv_um_s"])]
