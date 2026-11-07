extends SceneTree
## Prints balance.md section 9's figures for the new start: plays NewStartBot's whole route once,
## then prices it for a person at each pace. Takes a few minutes. Run headless:
##   godot --headless --path . -s tools/new_start_balance.gd

## { label, think_s, speed, warp, warp_after_s }
const PACES: Array[Dictionary] = [
	{ "label": "Bot", "think_s": 0, "speed": 1, "warp": 0, "warp_after_s": 0 },
	{ "label": "Practised 8x, warps", "think_s": 4, "speed": 8, "warp": 1000, "warp_after_s": 10 },
	{ "label": "First-time 8x, warps", "think_s": 15, "speed": 8, "warp": 1000, "warp_after_s": 30 },
	{ "label": "Practised 8x, no warp", "think_s": 4, "speed": 8, "warp": 0, "warp_after_s": 0 },
	{ "label": "First-time 1x, warps", "think_s": 15, "speed": 1, "warp": 1000, "warp_after_s": 30 },
]


func _initialize() -> void:
	var run := NewStartPace.new()
	run.play_through(NewStartBot.STAGE_DRONE)
	var problems := run.problems + run.ledger_problems + run.range_problems
	if not problems.is_empty():
		printerr("; ".join(problems))
		quit(1)
		return
	print("route: %d ticks (%.1f game h), %d commands, goals at ticks %s" % [run.sim.current_tick(),
		run.sim.current_tick() / 36000.0, run.command_ticks.size(), str(run.goal_ticks)])
	var order: Array[String] = []
	for goal: Dictionary in GoalTracker.NEW_START_GOALS:
		order.append(goal["id"])
	for p: Dictionary in PACES:
		var paced := NewStartPace.pace(run.command_ticks, run.goal_ticks, p["think_s"], p["speed"], p["warp"],
			p["warp_after_s"])
		var goals: PackedStringArray = []
		for id in order:
			goals.append("%s %s" % [id, _minutes(paced["goals_real_s"].get(id, -60.0))])
		print("%s: %s real, %s warped, game %.1f h with %.1f min of slips | %s" % [p["label"],
			_minutes(paced["real_s"]), _minutes(paced["warped_s"]), paced["game_ticks"] / 36000.0,
			paced["slip_ticks"] / 600.0, ", ".join(goals)])
	quit(0)


func _minutes(seconds: float) -> String:
	return "%.1f min" % (seconds / 60.0)
