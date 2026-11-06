class_name WarpLogic extends RefCounted
## The rules of the time warp (orbital_flight.md 11.22) for the bridge and the
## time controls: how each rung runs, which events drop it to 1×, the plain words
## for why a warp is capped, and the clock. The Sim decides what can coast; the
## client decides when to stop.

## Up to 8× the Sim steps tick by tick, as it always has.
const STEP_MAX := 8
## 50× runs batches of steps, sized by their measured cost.
const BATCH := 50

## Events that need the player, so a warp above 8× drops to 1× on their tick.
const ATTENTION: Array[String] = [
	"burn_started", "burn_short", "departed", "arrived", "landed", "crashed", "low_flight_entered",
	"job_paused", "power_shed", "fault", "theory_proven", "design_qualified", "idea_discovered",
	"command_rejected", "attach_failed", "task_blocked", "task_cancelled", "mining_stopped",
]
## Kept warping through when the player chose to.
const JOB_EVENTS: Array[String] = ["job_finished"]
## A queued job waiting on another job's output is the plan working, not news.
const QUIET_PAUSES: Array[String] = ["missing_inputs"]

## Why the Sim (A33) or the bridge capped a warp, in plain words.
const CAP_TEXT: Dictionary = {
	"command": "starting an order",
	"burning": "a burn is running",
	"low_flight": "flying low",
	"drifting": "drifting in the cluster",
	"near_a_boundary": "near a boundary",
	"planned_burn": "a burn is due",
	"transfer_leg": "a trip's next leg",
	"departure_or_arrival": "a departure or arrival",
	"landing_or_takeoff": "landing or taking off",
	"moving_in_frame": "ships moving in the cluster",
	"docking_or_cargo": "docking or moving cargo",
	"power": "power changing",
	"heat": "heat near its limit",
	"tasks": "orders under way",
	"jobs": "jobs running",
	"busy_world": "a busy world",
	"no_coast": "this game can't warp past 50× yet",
}
## Caps that last only as their event comes up, so they're shown only if they persist.
const MOMENTARY: Array[String] = [
	"command", "planned_burn", "transfer_leg", "departure_or_arrival", "landing_or_takeoff", "power", "heat",
]
const SECONDS_PER_DAY := 86400


## "step", "batch" or "coast" for a rung.
static func mode(speed: int) -> String:
	if speed <= STEP_MAX:
		return "step"
	return "batch" if speed <= BATCH else "coast"


## `live_jobs`, the view's jobs after these events: a finished run counts only when it
## was its job's last (the job has left the view), not every run of a 24-run job.
static func needs_attention(events: Array, through_jobs := false, live_jobs: Dictionary = {}) -> bool:
	for event: Dictionary in events:
		var data: Dictionary = event.get("data", {})
		if event["type"] == "job_paused" and QUIET_PAUSES.has(data.get("reason", "")):
			continue
		if ATTENTION.has(event["type"]):
			return true
		if not through_jobs and JOB_EVENTS.has(event["type"]) and not live_jobs.has(data.get("job", 0)):
			return true
	return false


static func cap_text(capped_by: String) -> String:
	return CAP_TEXT.get(capped_by, capped_by.replace("_", " "))


## "1x", "50x", "1kx", "10kx".
static func speed_label(speed: int) -> String:
	return "%dkx" % (speed / 1000) if speed >= 1000 and speed % 1000 == 0 else "%dx" % speed


## "≈3,200×" or "50×".
static func achieved_text(achieved: float) -> String:
	var value := roundi(achieved)
	var digits := str(value)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return "≈%s%s×" % [digits, grouped]


## "T+04:12:05", or "T+3 d 04:12" from the first day on.
static func clock_text(seconds: int) -> String:
	if seconds < SECONDS_PER_DAY:
		return "T+%02d:%02d:%02d" % [seconds / 3600, seconds / 60 % 60, seconds % 60]
	var days := seconds / SECONDS_PER_DAY
	var rest := seconds % SECONDS_PER_DAY
	return "T+%d d %02d:%02d" % [days, rest / 3600, rest / 60 % 60]
