class_name OrderText extends RefCounted
## Display text for reason codes, operations and events. The sim only sends
## stable codes (contracts section 6); every word the player reads lives here.

const REASONS: Dictionary = {
	"cargo_full": "Cargo hold is full",
	"corrupt": "The save file is damaged",
	"data_mismatch": "The save was made with different game data",
	"no_save": "No saved game yet",
	"unknown_scenario": "The save names an unknown scenario",
	"unsupported_orbit": "Can't fly there from here yet",
	"version_mismatch": "The save is from a different version",
	"bad_cycle": "That cycle is not valid",
	"burn_in_past": "That time has already passed",
	"busy_docking": "Wait for the craft to finish at the port",
	"cancelled": "Cancelled",
	"connector_occupied": "That connector is already in use",
	"connector_size_mismatch": "Only a core fits a core connector",
	"connector_type_mismatch": "Connector types do not match",
	"core_offline": "AI core is offline",
	"deposit_exhausted": "Deposit is exhausted",
	"docked": "Undock first",
	"facility_busy": "Facility is busy",
	"fit_mismatch": "Only a craft on the same hull can be copied",
	"job_busy": "That job has already started",
	"float_in_command": "Invalid order",
	"invalid_target": "Not a valid target",
	"missing_inputs": "Missing inputs",
	"module_fault": "A required module has a fault",
	"module_missing": "A required module is missing",
	"no_core": "No AI core assigned",
	"no_free_port": "No free docking port",
	"no_power": "Not enough power",
	"no_propellant": "Out of propellant",
	"no_safe_step": "Cannot resume safely",
	"not_docked": "Not docked",
	"not_flying": "Undock first",
	"not_landed": "Not on the ground",
	"no_landing_gear": "No landing legs fitted",
	"not_in_stub": "Not available in the stub simulation",
	"not_whole_unit": "Must be whole units",
	"out_of_range": "Move there first",
	"output_full": "No room for the output",
	"over_heat_budget": "Over the heat budget",
	"over_heat_limit": "Heat limit exceeded",
	"over_load_limit": "Too much mass on that connector",
	"over_mass_limit": "Over the mass limit",
	"over_power_budget": "Over the power budget",
	"parent_not_fitted": "The part it sits on was not fitted",
	"part_busy": "That part is in use",
	"player_order": "Replaced by a new order",
	"player_stop": "Stopped",
	"port_busy": "Docking port is busy",
	"queue_full": "The queue is full",
	"root_part": "The root part cannot be removed",
	"tier_too_low": "AI core tier is too low",
	"too_hard": "Too hard for this laser",
	"unknown_deposit": "Deposit not found",
	"malformed_command": "Invalid order",
	"unknown_command": "Not available yet",
	"unknown_job": "Job no longer exists",
	"unknown_recipe": "Recipe not found",
	"wrong_facility": "Wrong facility for this recipe",
	"unknown_part": "Part no longer exists",
	"unknown_unit": "Craft no longer exists",
}
const OPERATIONS: Dictionary = {
	"idle": "Idle",
	"moving": "Moving",
	"waiting": "Waiting for window",
	"landing": "Landing",
	"taking_off": "Taking off",
	"burning": "Burning",
	"docking": "Docking",
	"undocking": "Undocking",
	"loading": "Loading",
	"unloading": "Unloading",
	"mining": "Mining",
	"scanning": "Scanning",
}


static func reason(code: String, detail: Dictionary = {}) -> String:
	var text: String = REASONS.get(code, code.replace("_", " ").capitalize())
	if detail.has("need_mm") and detail.has("have_mm"):
		text += " (%s, needs %s)" % [metres(detail["have_mm"]), metres(detail["need_mm"])]
	elif detail.has("need_w") and detail.has("have_w"):
		text += ": needs %s, has %s" % [InspectText.watts(detail["need_w"]), InspectText.watts(detail["have_w"])]
	elif detail.has("need_g") and detail.has("have_g"):
		text += ": needs %s, has %s" % [tonnes(detail["need_g"]), tonnes(detail["have_g"])]
	return text


static func operation(code: String) -> String:
	return OPERATIONS.get(code, code.capitalize())


## `busy_docking` covers both directions, so the operation comes from the view.
static func busy(op_type: String) -> String:
	return "Wait for %s to finish" % operation(op_type).to_lower()


static func metres(mm: int) -> String:
	if mm >= 1000000:
		return "%.1f km" % (mm / 1000000.0)
	return "%d m" % (mm / 1000)


static func duration(seconds: float) -> String:
	var whole := ceili(seconds)
	if whole < 60:
		return "%d s" % whole
	if whole < 3600:
		return "%d min %d s" % [whole / 60, whole % 60]
	return "%d h %d min" % [whole / 3600, whole / 60 % 60]


static func tonnes(grams: int) -> String:
	if grams >= 1000000:
		return "%s t" % String.num(grams / 1000000.0, 1)
	return "%s kg" % String.num(grams / 1000.0, 1)


## One log line for an event, or "" if the player does not need to see it.
static func event(entry: Dictionary, unit_name: String, items: Dictionary, bodies: Dictionary = {}) -> String:
	var data: Dictionary = entry["data"]
	match entry["type"]:
		"command_rejected", "attach_failed":
			return "%s: %s" % [unit_name, reason(data["reason"], data.get("detail", {}))]
		"task_blocked", "fault", "power_shed":
			return "%s: %s" % [unit_name, reason(data["reason"], data.get("detail", {}))]
		"mining_stopped":
			return "%s: mining stopped. %s" % [unit_name, reason(data["reason"])]
		"job_finished":
			return "%s: finished %s" % [unit_name, data["recipe"].replace("_", " ").capitalize()]
		"job_cancelled":
			return "%s: cancelled %s" % [unit_name, data["recipe"].replace("_", " ").capitalize()]
		"job_paused":
			return "%s: job held. %s" % [unit_name, reason(data["reason"])]
		"fit_copied":
			return OrderText.fit_copied(data, unit_name, items)
		"burn_started":
			return "%s: burn started" % unit_name
		"burn_done":
			return "%s: burn done, %s" % [unit_name, FlightLogic.speed(data["dv_um_s"])]
		"burn_short":
			var why: String = "The craft was busy with another order" if data["reason"] == "part_busy" else reason(data["reason"])
			return "%s: burn stopped at %s. %s" % [unit_name, FlightLogic.speed(data["dv_um_s"]), why]
		"landed":
			var place: String = bodies.get(data["body"], {}).get("name", "the surface")
			if data.has("speed_um_s"):
				return "%s landed on %s at %s" % [unit_name, place, FlightLogic.speed(data["speed_um_s"])]
			return "%s landed on %s" % [unit_name, place]
		"took_off":
			return "%s took off from %s" % [unit_name, bodies.get(data["body"], {}).get("name", "the surface")]
		"crashed":
			var place: String = bodies.get(data["body"], {}).get("name", "the surface")
			if data.has("speed_um_s"):
				return "%s crashed on %s at %s" % [unit_name, place, FlightLogic.speed(data["speed_um_s"])]
			return "%s crashed on %s" % [unit_name, place]
		"low_flight_entered":
			return "%s is flying low over %s" % [unit_name, bodies.get(data["body"], {}).get("name", "the surface")]
		"low_flight_left":
			return "%s is back in orbit round %s" % [unit_name, bodies.get(data["body"], {}).get("name", "its body")]
		"soi_changed":
			var to_name: String = bodies.get(data["to"], {}).get("name", "another body")
			return "%s: now orbiting %s" % [unit_name, to_name]
		"frame_left":
			return "%s drifted out of its frame onto an orbit" % unit_name
		"frame_joined":
			return "%s joined a frame" % unit_name
		"transfer_done":
			var moved: String = items.get(data["item"], {}).get("name", data["item"])
			return "%s: moved %s of %s" % [unit_name, tonnes(data["grams"]), moved]
		"arrived":
			return "%s arrived" % unit_name
		"docked":
			return "%s docked" % unit_name
		"undocked":
			return "%s undocked" % unit_name
		"scan_finished":
			var found: int = data["deposits"].size()
			return "%s: scan finished, %d deposit%s found" % [unit_name, found, "" if found == 1 else "s"]
		"deposit_found":
			var item: String = items.get(data["item"], {}).get("name", data["item"])
			return "%s: found %s, %s" % [unit_name, item, tonnes(data["grams"])]
	return ""


## "Probe: fitted 5 parts. Missing Solar Slab x1. Mining Laser: Over the power budget"
static func fit_copied(data: Dictionary, unit_name: String, items: Dictionary) -> String:
	var attached: int = data["attached"].size()
	var text := "%s: fitted %d part%s" % [unit_name, attached, "" if attached == 1 else "s"]
	var missing: Array = data["missing"].keys()
	missing.sort()
	if not missing.is_empty():
		var names: PackedStringArray = []
		for item: String in missing:
			names.append("%s x%d" % [items.get(item, {}).get("name", item), data["missing"][item]])
		text += ". Missing %s" % ", ".join(names)
	for refused: Dictionary in data["refused"]:
		if refused["reason"] != "missing_inputs":
			text += ". %s: %s" % [items.get(refused["item"], {}).get("name", refused["item"]), reason(refused["reason"])]
	return text
