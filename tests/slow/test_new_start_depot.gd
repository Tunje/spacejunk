extends GutTest
## The new start, stage 7 (C23, new_start_chain.md Part F2): the depot feeds itself. A compact
## refinery is built in place on the station where its LIDAR was, given standing ice and hematite
## jobs, and the drone's cycle fetches ice from White Rock as well as hematite from Red Rock, until
## the cycle blocks with the station's stores full. Starts from the game saved after
## test_new_start_drone.gd's stage.

var bot: NewStartBot


func before_all() -> void:
	bot = NewStartBot.from_snapshot(NewStartBot.STAGE_DRONE)
	var start := bot.total_ticks()
	bot.play_through(NewStartBot.STAGE_DEPOT)
	gut.p("the depot: ticks %d to %d (%.1f game hours in all)" % [start, bot.total_ticks(),
		bot.total_ticks() / 36000.0])
	for line in bot.report(start, ["depot_ore", "panels_on", "refinery_built", "cycle_stopped"]):
		gut.p(line)
	for i in bot.laps.size():
		gut.p("  lap %d: %s" % [i + 1, str(bot.laps[i])])
	gut.p("  runs %s, last runs %s, paused %s, skips %d, stop %s" % [str(bot.runs), str(bot.last_run),
		str(bot.paused_ticks), bot.skips, str(bot.stop)])


func test_the_stage_runs_with_every_ledger_balanced() -> void:
	assert_eq(bot.problems, PackedStringArray())
	assert_eq(bot.ledger_problems, PackedStringArray())
	assert_eq(bot.range_problems, PackedStringArray())
	assert_true(bot.marks.has("cycle_stopped"))
	assert_eq(bot.snapshot_mismatch(NewStartBot.STAGE_DEPOT), "", "the snapshot regenerates the same")


func test_the_refinery_is_built_where_the_lidar_was() -> void:
	var station: Dictionary = bot.marks["refinery_built"]["units"][bot.station]
	var defs: Array = InspectText.flatten(station["parts"]).map(func(part: Dictionary) -> String: return part["def"])
	assert_has(defs, "compact_refinery_mk1")
	assert_does_not_have(defs, "lidar_mk1")
	assert_eq(defs.count("solar_panel_mk1"), 4, "two on the depot's sides")
	assert_gt(bot.sim._state["units"][bot.station]["inventory"].get("lidar_mk1", 0), 0, "in the goods hold")


func test_the_depot_feeds_itself() -> void:
	assert_gt(bot.runs.get("refine_water_ice", 0), 0, "ice refined into the depot")
	assert_gt(bot.runs.get("refine_hematite", 0), 0, "hematite refined into the goods hold")
	assert_gt(bot.laps.size(), 1)
	var first: Dictionary = bot.laps[0]
	var last: Dictionary = bot.laps[-1]
	assert_gt(last["depot_g"], first["depot_g"], "the depot grows lap on lap")


func test_the_cycle_stops_cleanly_when_the_stores_are_full() -> void:
	assert_false(bot.stop.is_empty(), "it blocked rather than ran on")
	assert_eq(bot.stop.get("reason", ""), "cargo_full")
