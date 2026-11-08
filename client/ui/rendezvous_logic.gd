class_name RendezvousLogic extends RefCounted
## Words for the rendezvous readouts (D46), from the Sim's relative state to a target,
## Sim.relative(unit, target, from_tick, horizon_ticks) (A54, real_orbits.md 3.5):
## range, closing and lateral speed, closest approach now and with the planned burns,
## planes and nodes, phase and window, the burn to stop, and the docking condition.
## The client does no physics: every figure is the Sim's, only worded here. Units follow
## the contracts: mm, µm/s, mdeg, ticks, grams.

## Under this the planes count as one.
const SAME_PLANE_MDEG := 10
const UM_PER_CM := 10_000


## The Sim's relative state from a craft to a target, or {} when there is no target,
## the Sim has no query, or it refuses ({ reason }).
static func fetch(sim: RefCounted, unit_id: int, target_id: int, tick: int) -> Dictionary:
	if target_id == 0 or sim == null or not sim.has_method("relative"):
		return {}
	var found: Variant = sim.relative(unit_id, target_id, tick)
	return found if found is Dictionary and not (found as Dictionary).has("reason") else {}


# --- Distances and speeds, fine enough for docking at centimetres a second ---

## "35 cm", "4.2 m", "860 m", "12.4 km".
static func distance(mm: int) -> String:
	var metres := float(absi(mm)) / 1000.0
	if metres < 1.0:
		return "%d cm" % roundi(metres * 100.0)
	if metres < 10.0:
		return "%s m" % String.num(metres, 1)
	if metres < 1000.0:
		return "%d m" % roundi(metres)
	return "%s km" % String.num(metres / 1000.0, 1)


## "4 mm/s", "15 cm/s", "3.2 m/s", "1.20 km/s".
static func speed(um_s: int) -> String:
	var magnitude := absi(um_s)
	if magnitude < UM_PER_CM:
		return "%d mm/s" % roundi(magnitude / 1000.0)
	if magnitude < 1_000_000:
		return "%d cm/s" % roundi(float(magnitude) / UM_PER_CM)
	if magnitude < 1_000_000_000:
		return "%s m/s" % String.num(magnitude / 1_000_000.0, 1)
	return "%s km/s" % String.num(magnitude / 1_000_000_000.0, 2)


static func _in(tick: int, now: int, ticks_per_second: int) -> String:
	return "now" if tick <= now else "in %s" % OrderText.duration(float(tick - now) / ticks_per_second)


static func _for(ticks: int, ticks_per_second: int) -> String:
	return OrderText.duration(float(ticks) / ticks_per_second)


static func _degrees(mdeg: int) -> String:
	return "%s°" % String.num(mdeg / 1000.0, 1)


# --- The readout lines ---

## "Range 12.4 km".
static func range_text(state: Dictionary) -> String:
	return "Range %s" % RendezvousLogic.distance(int(state.get("range_mm", 0)))


## "Closing at 3.2 m/s, 40 cm/s across" or "Opening at …": the relative velocity along
## the line to the target, and the rest of it.
static func motion_text(state: Dictionary) -> String:
	var closing := int(state.get("closing_um_s", 0))
	var along := ("Closing at %s" if closing >= 0 else "Opening at %s") % RendezvousLogic.speed(closing)
	return "%s, %s across" % [along, RendezvousLogic.speed(int(state.get("lateral_um_s", 0)))]


## "Closest approach 1.2 km in 43 min, at 3.1 m/s", or with `planned` "With the planned
## burns: …". "" when there is none (no planned burn, for the second).
static func closest_text(state: Dictionary, planned: bool, now: int, ticks_per_second: int) -> String:
	var at: Dictionary = state.get("closest_planned" if planned else "closest", {})
	if at.is_empty():
		return ""
	return "%s %s %s, at %s" % ["With the planned burns:" if planned else "Closest approach",
		RendezvousLogic.distance(int(at.get("range_mm", 0))),
		RendezvousLogic._in(int(at.get("tick", 0)), now, ticks_per_second),
		RendezvousLogic.speed(int(at.get("speed_um_s", 0)))]


## "Planes 2.3° apart: ascending node in 12 min, descending in 58 min", or "Same plane".
## A node tick of -1 is no crossing.
static func planes_text(state: Dictionary, now: int, ticks_per_second: int) -> String:
	var plane: Dictionary = state.get("plane", {})
	if plane.is_empty():
		return ""
	var inclination := int(plane.get("inclination_mdeg", 0))
	if absi(inclination) < SAME_PLANE_MDEG:
		return "Same plane"
	var parts: PackedStringArray = []
	var ascending := int(plane.get("ascending_tick", -1))
	var descending := int(plane.get("descending_tick", -1))
	if ascending >= 0:
		parts.append("ascending node %s" % RendezvousLogic._in(ascending, now, ticks_per_second))
	if descending >= 0:
		parts.append("descending %s" % RendezvousLogic._in(descending, now, ticks_per_second))
	return "Planes %s apart%s" % [RendezvousLogic._degrees(inclination), "" if parts.is_empty() else ": " + ", ".join(parts)]


## "Target 14.2° ahead; next window in 3 h 5 min, a 2 h 10 min trip". The phase is
## -1 when the two share no parent; behind reads for a phase past half a turn.
static func phase_text(state: Dictionary, now: int, ticks_per_second: int) -> String:
	var parts: PackedStringArray = []
	var phase := int(state.get("phase_mdeg", -1))
	if phase >= 0:
		var behind := phase > 180_000
		parts.append("Target %s %s" % [RendezvousLogic._degrees(360_000 - phase if behind else phase), "behind" if behind else "ahead"])
	var window: Dictionary = state.get("window", {})
	if not window.is_empty():
		parts.append("next window %s, a %s trip" % [RendezvousLogic._in(int(window.get("depart_tick", 0)), now, ticks_per_second),
			RendezvousLogic._for(int(window.get("ticks", 0)), ticks_per_second)])
	var text := "; ".join(parts)
	return text.left(1).to_upper() + text.substr(1) if not text.is_empty() else ""


## The burn that would stop the relative motion: "To stop: a 1 min 10 s burn, start it
## 35 s early, 12.0 kg". "" when there is nothing to stop.
static func stop_text(state: Dictionary, ticks_per_second: int) -> String:
	var stop: Dictionary = state.get("stop", {})
	if stop.is_empty() or int(stop.get("burn_ticks", 0)) <= 0:
		return ""
	return "To stop: a %s burn, start it %s early, %s" % [
		RendezvousLogic._for(int(stop["burn_ticks"]), ticks_per_second),
		RendezvousLogic._for(int(stop.get("lead_ticks", 0)), ticks_per_second),
		OrderText.tonnes(int(stop.get("propellant_g", 0)))]


## The docking condition now: "Dock: ready (1.6 m of 2.0 m, 15 cm/s of 20 cm/s)", or
## why not, as the Sim's refusal would say. "" when the Sim gave none.
static func dock_text(state: Dictionary) -> String:
	var dock: Dictionary = state.get("dock", {})
	if dock.is_empty():
		return ""
	var figures := "%s of %s, %s of %s" % [
		RendezvousLogic.distance(int(dock.get("range_mm", 0))), RendezvousLogic.distance(int(dock.get("capture_range_mm", 0))),
		RendezvousLogic.speed(int(dock.get("speed_um_s", 0))), RendezvousLogic.speed(int(dock.get("capture_speed_um_s", 0)))]
	var reason := String(dock.get("reason", ""))
	if reason.is_empty():
		return "Dock: ready (%s)" % figures
	return "Dock: %s (%s)" % [OrderText.reason(reason, {}), figures]


## Every line the panel shows, in order, skipping those the Sim gave nothing for.
static func lines(state: Dictionary, now: int, ticks_per_second: int) -> PackedStringArray:
	var found: PackedStringArray = []
	if state.is_empty():
		return found
	for line: String in [RendezvousLogic.range_text(state), RendezvousLogic.motion_text(state),
			RendezvousLogic.closest_text(state, false, now, ticks_per_second),
			RendezvousLogic.closest_text(state, true, now, ticks_per_second),
			RendezvousLogic.planes_text(state, now, ticks_per_second),
			RendezvousLogic.phase_text(state, now, ticks_per_second),
			RendezvousLogic.stop_text(state, ticks_per_second), RendezvousLogic.dock_text(state)]:
		if not line.is_empty():
			found.append(line)
	return found
