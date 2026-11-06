class_name JobFixture
extends RefCounted
## A whole job record for tests that need a job in a given state without running one.

## Work for a run that never ends in a test: a million ticks at the full-size rate.
const LONG_WORK := 100_000_000


static func record(
	state: Dictionary, facility: int, recipe: String, status: String, reason: String = ""
) -> Dictionary:
	return {
		"id": 40, "unit": state["parts"][facility]["unit"], "facility": facility, "recipe": recipe,
		"count_left": 1, "status": status, "reason": reason, "start_tick": 0,
		"work_left": LONG_WORK, "since_tick": 0, "command": 0, "started": true,
		"held": {}, "reserved": {}, "port": 0, "queue_pos": 0,
	}
