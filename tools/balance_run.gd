extends SceneTree

## Prints the figures behind docs/design/balance.md. Options change definitions in memory only.
## godot --headless --path . -s tools/balance_run.gd

const GOAL_ORDER: Array[String] = [
	"scan", "mine", "haul", "refine", "fabricate", "install", "drone", "handover", "expand", "fix",
]
const THINK_PRACTISED := 4
const THINK_FIRST_TIME := 15
const OPTIONS: Array[Dictionary] = [
	{ "name": "base" },
	{ "name": "rocks at half distance", "rocks": { "num": 1, "den": 2 } },
	{ "name": "scan 10 s", "scan": 100 },
	{ "name": "refining at half time", "recipes": { "refine_hematite": 300, "refine_chalcopyrite": 300, "refine_olivine": 450 } },
	{ "name": "processor 20 s", "recipes": { "processor": 200 } },
	{ "name": "processor 20 s, frame 15 s, wiring 10 s", "recipes": { "processor": 200, "structural_frame": 150, "wiring": 100 } },
	{ "name": "cores and drone at half time", "recipes": { "mining_drone": 1500, "basic_core": 600, "assisted_core": 1500 } },
	{ "name": "A: materials", "recipes": {
		"processor": 200, "structural_frame": 150, "wiring": 100,
		"refine_hematite": 300, "refine_chalcopyrite": 300, "refine_olivine": 450,
	} },
	{ "name": "B: materials and modules", "scan": 100, "recipes": {
		"processor": 200, "structural_frame": 150, "wiring": 100,
		"refine_hematite": 300, "refine_chalcopyrite": 300, "refine_olivine": 450,
		"mining_drone": 1500, "basic_core": 600, "assisted_core": 1500,
		"ore_storage_mk1": 1500, "mining_laser_mk1": 900, "heat_radiator_mk1": 450, "ore_container_mk1": 600,
	} },
	{ "name": "C: B and rocks at half", "scan": 100, "rocks": { "num": 1, "den": 2 }, "recipes": {
		"processor": 200, "structural_frame": 150, "wiring": 100,
		"refine_hematite": 300, "refine_chalcopyrite": 300, "refine_olivine": 450,
		"mining_drone": 1500, "basic_core": 600, "assisted_core": 1500,
		"ore_storage_mk1": 1500, "mining_laser_mk1": 900, "heat_radiator_mk1": 450, "ore_container_mk1": 600,
	} },
]


class ScaledBot:
	extends ReferenceBot
	var rock_scale := { "num": 1, "den": 1 }

	func run() -> void:
		sim = Sim.new_game("reference", SEED)
		PersonRun.scale_rocks(sim, rock_scale)
		_part_a()
		_part_b()
		_part_c()
		_part_d()
		_part_e()


func _init() -> void:
	var original: Dictionary = DataLoader.load_defs().duplicate(true)
	for option in OPTIONS:
		DataLoader._defs_cache = original.duplicate(true)
		_apply(option)
		print("=== %s" % option["name"])
		_report_bot(option)
		_report_person(option, "direct", PersonRun.PLAN_DIRECT, THINK_PRACTISED)
		_report_person(option, "chain", PersonRun.PLAN_CHAIN, THINK_FIRST_TIME)
	quit()


func _apply(option: Dictionary) -> void:
	var defs: Dictionary = DataLoader._defs_cache
	var recipes: Dictionary = option.get("recipes", {})
	for id: String in recipes:
		defs["recipes"][id]["ticks"] = recipes[id]
	if option.has("scan"):
		defs["modules"]["lidar_mk1"]["capabilities"]["scan"]["ticks"] = option["scan"]


func _report_bot(option: Dictionary) -> void:
	var bot := ScaledBot.new()
	bot.rock_scale = option.get("rocks", { "num": 1, "den": 1 })
	bot.run()
	if not bot.problems.is_empty():
		print("bot problems: %s" % ", ".join(bot.problems))
	var ticks := {}
	for label: String in bot.marks:
		ticks[label] = bot.marks[label]["tick"]
	print("bot marks %s" % str(ticks))
	print("bot laps %s start %d" % [str(bot.lap_ticks), bot.cycle_start_tick])
	var burn := _propellant(bot.marks["core_assigned"]) - _propellant(bot.marks["end"])
	print("bot drone burn over laps %d g, exhaust %s" % [burn, str(bot.sim.ledger()["matter"]["sinks"])])


func _propellant(view: Dictionary) -> int:
	var total := 0
	for id: int in view["units"]:
		total += view["units"][id]["inventory"].get("propellant", 0)
	return total


func _report_person(option: Dictionary, label: String, plan: Dictionary, think: int) -> void:
	for speed: int in [1, 8]:
		var person := PersonRun.new(plan, speed, think, option.get("rocks", { "num": 1, "den": 1 }))
		person.run()
		var line := PackedStringArray()
		for goal in GOAL_ORDER:
			line.append("%s=%d" % [goal, person.goal_ticks.get(goal, -1)])
		print("%s think %d x%d: %s" % [label, think, speed, " ".join(line)])
		print("  marks %s end %d commands %d" % [str(person.marks), person.sim.current_tick(), person.command_ticks.size()])
		print("  longest gaps %s" % str(person.longest_waits().slice(0, 4)))
		print("  refinery busy %d fabricator busy %d shed %d paused %s" % [
			person.refinery_ticks, person.fabricator_ticks, person.shed_events, str(person.paused_reasons),
		])
		if not person.end_view.is_empty():
			print("  stock %s" % str(person.end_view["units"][PersonRun.STATION]["inventory"]))
			print("  ship propellant %d" % person.end_view["units"][PersonRun.SHIP]["inventory"]["propellant"])
		if not person.problems.is_empty():
			print("  PROBLEMS %s" % ", ".join(person.problems))
