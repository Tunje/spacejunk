class_name JobFixture
extends RefCounted
## A whole job record for tests that need a job in a given state without running one.

## Energy for a run that never ends in a test: about a day at 1 MW.
const LONG_ENERGY_J := 100_000_000_000


static func record(
	state: Dictionary, facility: int, recipe: String, status: String, reason: String = ""
) -> Dictionary:
	return {
		"id": 40, "unit": state["parts"][facility]["unit"], "facility": facility, "recipe": recipe,
		"count_left": 1, "status": status, "reason": reason, "start_tick": 0,
		"energy_left_j": LONG_ENERGY_J, "energy_remainder": 0, "rate_w": 0, "limit": "", "limits_w": {},
		"feed": {}, "since_tick": 0, "command": 0, "started": true,
		"held": {}, "reserved": {}, "port": 0, "queue_pos": 0, "points_held": 0, "install_to": {},
	}
