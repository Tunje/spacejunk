extends SceneTree
## What the reference chain would do if the cluster circled a 60 km moon (task A23). Runs B's
## ReferenceBot over today's reference game, with a planet, its moon and a cluster frame added at
## fresh IDs after the game loads, so the bot's fixed IDs still hold, and the station, ship and
## rocks moved into the frame at the same local positions. Inside the frame, trips are the same
## straight lines as before; the only change is A16's shadow, which cuts solar to nothing.
## Compares each placement and starting phase with the run as it is today.
##
## Run: godot --headless --path . -s tools/moon_power_run.gd

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const GM_MOON := 3_531_600
const AU_MM := 149_597_870_700_000
const MOON_A_MM := 12_000_000_000
const RADII_KM := [300, 400, 600]
## Starting phases, in millidegrees: the cluster round the moon, and the moon round the planet.
## The moon at 0 is straight behind the planet; at -3000 it is about 20 minutes from entering
## the planet's shadow, and at 180000 it is nowhere near it.
const CLUSTER_PHASES := [0, 90_000, 180_000, 270_000]
const MOON_PHASES := [-3_000, 180_000]


class MoonBot:
	extends ReferenceBot
	var cluster_km := 0
	var cluster_mdeg := 0
	var moon_mdeg := 0
	var shadow_ticks := 0
	var paused_ticks := 0
	var pauses := 0
	var frame := 0
	var _paused_at := -1

	func run() -> void:
		sim = Sim.new_game("reference", SEED)
		if cluster_km > 0:
			_move_to_moon()
		_part_a()
		_part_b()
		_part_c()
		_part_d()
		_part_e()

	## Adds a second star at the first's place (shadows use the first, so the geometry is the
	## same), the planet, the moon and the frame, then puts every rock and unit in the frame.
	func _move_to_moon() -> void:
		var star_mm: Array = sim._state["bodies"][1]["pos_mm"]
		var problem := ScenarioBuilder.populate(sim._ctx, {
			"bodies": [
				{ "key": "sun", "name": "Sun", "kind": "star", "pos_mm": star_mm.duplicate(), "radius_mm": 696_000_000_000,
					"visual_seed": 1, "deposits": [], "gm": GM_STAR },
				{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": 600_000_000, "visual_seed": 2,
					"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "sun", "a_mm": AU_MM } },
				{ "key": "moon", "name": "Moon", "kind": "planet", "radius_mm": 60_000_000, "visual_seed": 3,
					"deposits": [], "gm": GM_MOON,
					"orbit": { "parent": "planet", "a_mm": MOON_A_MM, "mean_anomaly_mdeg": moon_mdeg } },
			],
			"frames": [
				{ "key": "cluster", "name": "Cluster", "radius_mm": 1_000_000,
					"orbit": { "parent": "moon", "a_mm": cluster_km * 1_000_000, "mean_anomaly_mdeg": cluster_mdeg } },
			],
			"units": [],
		}, {})
		if problem != "":
			problems.append("could not add the moon: %s" % problem)
			return
		for id: int in sim._state["frames"]:
			frame = id
		for id: int in sim._state["bodies"]:
			if sim._state["bodies"][id]["kind"] == "asteroid":
				sim._state["bodies"][id]["frame"] = frame
		for id: int in sim._state["units"]:
			sim._state["units"][id]["frame"] = frame

	## ReferenceBot's job wait, except that a job paused for want of power waits for its resume, as
	## it would in play, and the time it spent paused is counted.
	func _job(facility: int, recipe: String, count: int) -> void:
		if not problems.is_empty():
			return
		var id := _command("start_job", STATION, { "facility": facility, "recipe": recipe, "count": count })
		var start := sim.current_tick() + 1
		var limit: int = 2 * sim.defs()["recipes"][recipe]["ticks"] * count + ORDER_LIMIT_TICKS + 60_000
		var job := 0
		var left := count
		for i in limit:
			for event in _step():
				var data: Dictionary = event["data"]
				match event["type"]:
					"command_rejected":
						if data["command"] == id:
							problems.append("%s refused: %s" % [recipe, data["reason"]])
							return
					"job_started":
						if data["command"] == id:
							job = data["job"]
					"job_paused":
						if data["job"] == job or job == 0:
							pauses += 1
							_paused_at = event["tick"]
					"job_resumed":
						if data["job"] == job and _paused_at >= 0:
							paused_ticks += event["tick"] - _paused_at
							_paused_at = -1
					"job_finished":
						if data["job"] == job:
							left -= 1
							if left == 0:
								steps.append({ "label": recipe, "start_tick": start, "ticks": event["tick"] - start + 1 })
								return
		problems.append("%s never finished" % recipe)

	## A craft built in a frame starts outside it today (ConstructionSystem gives it frame 0), so
	## the run moves each new craft into the frame. Reported to C; remove this once that is fixed.
	func _step() -> Array[Dictionary]:
		var stepped := super()
		if frame != 0:
			for event in stepped:
				if event["type"] == "unit_created":
					sim._state["units"][event["data"]["unit"]]["frame"] = frame
		if frame != 0 and RailSystem.in_shadow(sim._state, STATION):
			shadow_ticks += 1
		return stepped


func _init() -> void:
	var base := _run(0, 0, 0)
	if base.is_empty():
		quit()
		return
	_print("today, no shadow", base, base)
	for km: int in RADII_KM:
		for moon_mdeg: int in MOON_PHASES:
			for cluster_mdeg: int in CLUSTER_PHASES:
				var label := "%d km, cluster at %d deg, moon at %d deg" % [km, cluster_mdeg / 1000, moon_mdeg / 1000]
				var result := _run(km, cluster_mdeg, moon_mdeg)
				if not result.is_empty():
					_print(label, result, base)
	quit()


func _run(km: int, cluster_mdeg: int, moon_mdeg: int) -> Dictionary:
	var bot := MoonBot.new()
	bot.cluster_km = km
	bot.cluster_mdeg = cluster_mdeg
	bot.moon_mdeg = moon_mdeg
	bot.run()
	if not bot.problems.is_empty():
		print("%d km: problems: %s" % [km, ", ".join(bot.problems)])
	if not bot.marks.has("end"):
		return {}
	var drone_frame: int = bot.sim._state["units"][bot.drone]["frame"] if bot.drone != 0 else -1
	var laps: Array[int] = []
	var last := bot.cycle_start_tick
	for tick in bot.lap_ticks:
		laps.append(tick - last)
		last = tick
	return {
		"handover": bot.marks["core_assigned"]["tick"], "end": bot.marks["end"]["tick"], "laps": laps,
		"shadow": bot.shadow_ticks, "paused": bot.paused_ticks, "pauses": bot.pauses, "drone_frame": drone_frame, "frame": bot.frame,
	}


func _print(label: String, result: Dictionary, base: Dictionary) -> void:
	print("%s: handover at %.1f min (%+.1f), laps %s ticks (today %s), %.1f min of station shadow, %d job pauses for %.1f min%s" % [
		label, result["handover"] / 600.0, (result["handover"] - base["handover"]) / 600.0,
		str(result["laps"]), str(base["laps"]), result["shadow"] / 600.0, result["pauses"], result["paused"] / 600.0,
		"" if result["drone_frame"] == result["frame"] else ", DRONE NOT IN THE FRAME"])
