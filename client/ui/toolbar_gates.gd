class_name ToolbarGates extends RefCounted
## Toolbar buttons that do nothing useful early on (D39): greyed, with a tooltip
## saying when they help, until their goal comes up or the player already has what
## they need. Greyed rather than hidden, so the bar never shifts. Their keys still work.
##
## A gate is { goal, tip }: `goal` is the goal that opens it, "" for the start's
## last goal. A start whose list lacks the goal has the button open from the start.

const GATES: Dictionary = {
	"research": { "goal": "research",
		"tip": "Research turns science points into new parts. It opens once you have a Research Lab, or when the goal Prove a new tech comes up." },
	"auto": { "goal": "handover",
		"tip": "Auto hands a repeating route to an Assisted Core. It opens once a craft has one, or when the goal Hand the job to an AI core comes up." },
	"policy": { "goal": "",
		"tip": "Policy sets standing orders for a whole fleet. It opens once your drones run routes by themselves, at the last goal." },
}


static func is_open(gate: String, tracker: GoalTracker, view: Dictionary, modules: Dictionary) -> bool:
	return ToolbarGates.goal_reached(gate, tracker) or ToolbarGates.has_what_it_needs(gate, view, modules)


## The gate's goal is current or done, or the start's list has no such goal.
static func goal_reached(gate: String, tracker: GoalTracker) -> bool:
	var goals: Array[Dictionary] = tracker.goals
	var goal: String = GATES[gate]["goal"]
	if goal.is_empty():
		goal = goals[goals.size() - 1]["id"]
	var at := -1
	for index in range(goals.size()):
		if goals[index]["id"] == goal:
			at = index
	if at < 0:
		return true
	var current := tracker.current()
	return current.is_empty() or goals.find(current) >= at or tracker.done.has(goal)


## Research: any Research Lab. Auto: any craft with a core that can repeat a route.
static func has_what_it_needs(gate: String, view: Dictionary, modules: Dictionary) -> bool:
	var ids: Array = view["units"].keys()
	ids.sort()
	for id: int in ids:
		var unit: Dictionary = view["units"][id]
		match gate:
			"research":
				for entry: Dictionary in IndustryLogic.facilities(unit, modules):
					if entry["type"] == "lab":
						return true
			"auto":
				if int(unit.get("core_tier", 0)) >= 2:
					return true
	return false
