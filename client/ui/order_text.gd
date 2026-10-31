class_name OrderText extends RefCounted
## Display text for reason codes, operations and events. The sim only sends
## stable codes (contracts section 6); every word the player reads lives here.

const REASONS: Dictionary = {
	"cargo_full": "Cargo hold is full",
	"connector_occupied": "That port is already in use",
	"deposit_exhausted": "Deposit is exhausted",
	"docked": "Undock first",
	"float_in_command": "Invalid order",
	"invalid_target": "Not a valid target",
	"no_mining_laser": "No mining laser fitted",
	"no_propellant": "Out of propellant",
	"no_propulsion": "This craft has no thruster",
	"no_scanner": "No scanner fitted",
	"not_docked": "Not docked",
	"not_in_stub": "Not available in the stub simulation",
	"out_of_range": "Out of range",
	"player_order": "Replaced by a new order",
	"unknown_part": "Part no longer exists",
	"unknown_unit": "Craft no longer exists",
}
const OPERATIONS: Dictionary = {
	"idle": "Idle",
	"moving": "Moving",
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
	return text


static func operation(code: String) -> String:
	return OPERATIONS.get(code, code.capitalize())


static func metres(mm: int) -> String:
	if mm >= 1000000:
		return "%.1f km" % (mm / 1000000.0)
	return "%d m" % (mm / 1000)


static func tonnes(grams: int) -> String:
	if grams >= 1000000:
		return "%s t" % String.num(grams / 1000000.0, 1)
	return "%s kg" % String.num(grams / 1000.0, 1)


## One log line for an event, or "" if the player does not need to see it.
static func event(entry: Dictionary, unit_name: String, items: Dictionary) -> String:
	var data: Dictionary = entry["data"]
	match entry["type"]:
		"command_rejected", "attach_failed":
			return "%s: %s" % [unit_name, reason(data["reason"], data.get("detail", {}))]
		"task_blocked", "fault", "power_shed":
			return "%s: %s" % [unit_name, reason(data["reason"], data.get("detail", {}))]
		"mining_stopped":
			return "%s: mining stopped. %s" % [unit_name, reason(data["reason"])]
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
