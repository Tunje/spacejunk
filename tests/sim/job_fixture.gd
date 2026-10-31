class_name JobFixture
extends RefCounted
## A whole job record for tests that need a job in a given state without running one.

const LONG_TICKS := 1000000


static func record(
	state: Dictionary, facility: int, recipe: String, status: String, reason: String = ""
) -> Dictionary:
	return {
		"id": 40, "unit": state["parts"][facility]["unit"], "facility": facility, "recipe": recipe,
		"count_left": 1, "status": status, "reason": reason, "start_tick": 0, "end_tick": 0,
		"remaining_tick": LONG_TICKS, "since_tick": 0, "command": 0, "started": true,
		"held": {}, "reserved": {},
	}
