class_name NewStartPace
extends NewStartBot
## Paces the new start as a person would, for docs/design/balance.md section 9 (B23). It plays C's
## NewStartBot route on the real Sim and records the tick of every command and every goal, scored by
## the client's own GoalTracker. pace() then prices that record for a person:
##
## - Every command takes `think_s` real seconds. The game runs at `speed` meanwhile, so when the bot
##   gave its next command sooner than that, the person is late, and the whole chain slips by the
##   difference. The bot does one step at a time, so its route is a ceiling on game time; the slips
##   are added on top.
## - A wait longer than `warp_after_s` real seconds, at `speed`, is warped at `warp` for the rest.
##   `warp` 0 means the person never warps.
##
## This is an estimate on the bot's route, not a second player. reference.json's person-paced run is
## tools/person_run.gd, which stays as the station fixture's.

## Every command's tick, in order.
var command_ticks: Array[int] = []
## Every command, in order: { tick, type, unit, stage, what, count }, for B24's order count.
var commands: Array[Dictionary] = []
## The tick each goal finished, by goal ID.
var goal_ticks := {}
var tracker := GoalTracker.new("new_start")
## The item of each attach_part command, by command ID, so a refused fit reaches the tracker as the
## fitting screen's refusal does in the client.
var _attach_items := {}


func _command(type: String, unit: int, args: Dictionary) -> int:
	command_ticks.append(sim.current_tick())
	commands.append({ "tick": sim.current_tick(), "type": type, "unit": unit, "stage": stage,
		"what": str(args.get("recipe", args.get("item", args.get("kind", args.get("target", ""))))),
		"count": int(args.get("count", 1)) })
	var id := super._command(type, unit, args)
	if type == "attach_part":
		_attach_items[id] = args["item"]
	return id


func _took() -> Array[Dictionary]:
	var new_events := super._took()
	if new_events.is_empty():
		return new_events
	var view := sim.view()
	var defs := sim.defs()
	for id in tracker.observe_view(view, defs["items"], defs["modules"]):
		goal_ticks[id] = sim.current_tick()
	for event in new_events:
		if event["type"] in ["command_rejected", FittingSystem.FAILED_EVENT] \
				and _attach_items.has(event["data"].get("command", 0)):
			tracker.note_fit_blocked(_attach_items[event["data"]["command"]], event["data"]["reason"])
		for id in tracker.observe_event(event, view, defs):
			goal_ticks[id] = sim.current_tick()
	return new_events


## Prices a run's record for a person. Returns { real_s, game_ticks, slip_ticks, goals_real_s,
## warped_s }: total real seconds, game ticks with the slips, the slips alone, each goal's real
## seconds from the start, and the real seconds spent warping.
static func pace(commands: Array[int], goals: Dictionary, think_s: int, speed: int, warp: int,
		warp_after_s: int) -> Dictionary:
	var marks: Array[Dictionary] = []
	var previous := 0
	for tick in commands:
		marks.append({ "tick": tick, "goal": "" })
	for id: String in _sorted_keys(goals):
		marks.append({ "tick": goals[id], "goal": id })
	marks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["tick"] < b["tick"] or (a["tick"] == b["tick"] and a["goal"] > b["goal"]))
	var real := 0.0
	var warped := 0.0
	var slip := 0
	var since_command := 0.0
	var goals_real := {}
	for mark: Dictionary in marks:
		var gap: int = mark["tick"] - previous
		previous = mark["tick"]
		var priced := _gap_real(gap, since_command, think_s, speed, warp, warp_after_s)
		real += priced["real_s"]
		warped += priced["warped_s"]
		since_command += priced["real_s"]
		if mark["goal"] != "":
			goals_real[mark["goal"]] = real
			continue
		# A command: the person can't give it before think_s since the last one.
		if since_command < think_s:
			var late := think_s - since_command
			real += late
			slip += int(late * speed * Sim.TICKS_PER_SECOND)
		since_command = 0.0
	return { "real_s": real, "game_ticks": previous + slip, "slip_ticks": slip, "goals_real_s": goals_real,
		"warped_s": warped }


## Real seconds for `gap` game ticks, `since` real seconds after the last command: at `speed`
## until warp_after_s of waiting past the think time, then at `warp`.
static func _gap_real(gap: int, since: float, think_s: int, speed: int, warp: int,
		warp_after_s: int) -> Dictionary:
	var at_speed := float(gap) / (Sim.TICKS_PER_SECOND * speed)
	if warp <= 0:
		return { "real_s": at_speed, "warped_s": 0.0 }
	var before_warp := maxf(0.0, think_s + warp_after_s - since)
	if at_speed <= before_warp:
		return { "real_s": at_speed, "warped_s": 0.0 }
	var rest_ticks := gap - before_warp * Sim.TICKS_PER_SECOND * speed
	var warped := rest_ticks / (Sim.TICKS_PER_SECOND * warp)
	return { "real_s": before_warp + warped, "warped_s": warped }


static func _sorted_keys(table: Dictionary) -> Array:
	var keys := table.keys()
	keys.sort()
	return keys
