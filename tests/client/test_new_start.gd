extends GutTest
## D25: the new start (data/scenarios/new_start.json) on the real Sim, chosen with
## `--scenario=new_start`: only the probe, in the cluster round Frost, no station.

var main: Node
var bridge: SimBridge
var view: LocalView


func before_each() -> void:
	main = load("res://client/main.tscn").instantiate()
	main.scenario = Main.NEW_START
	add_child_autofree(main)
	bridge = main.get_node("Bridge")
	bridge.set_paused(true)
	view = main.get_node("LocalView")


func _id_of(table: String, name: String) -> int:
	for id: int in bridge.current_view[table]:
		if bridge.current_view[table][id]["name"] == name:
			return id
	return 0


func test_the_launch_flag_chooses_the_start() -> void:
	var parsed := ScreenshotRunner.parse_args(PackedStringArray(["--scenario=new_start"]))
	assert_eq(parsed.get("scenario"), Main.NEW_START)
	assert_true(Main.STARTS.has(Main.NEW_START), "listed as a start")
	assert_true(Main.STARTS.has(Main.SCENARIO), "and the default still is")


func test_it_starts_with_only_the_probe_on_the_real_sim() -> void:
	assert_true(bridge.sim is Sim)
	assert_eq(bridge.current_view["units"].size(), 1)
	var probe_id := _id_of("units", "Probe")
	assert_ne(probe_id, 0)
	var probe: Dictionary = bridge.current_view["units"][probe_id]
	assert_ne(int(probe["frame"]), 0, "in the cluster")
	assert_true(probe["dock"].is_empty(), "nothing to dock to")
	assert_gt(int(probe["touchdown_mm_s"]), 0, "it has legs")
	assert_eq(view.commanded_unit, probe_id)


func test_the_map_shows_frost_the_planet_and_the_rocks() -> void:
	main.toggle_map()
	var labels: Array = main.system_map.entries.map(func(entry: Dictionary) -> String: return entry["label"])
	for name: String in ["Frost", "Planet", "Red Rock", "White Rock", "Probe"]:
		assert_has(labels, name)


func test_it_ticks_and_every_screen_opens_without_a_station() -> void:
	bridge.set_paused(false)
	bridge.advance(0.5)
	bridge.set_paused(true)
	view.refresh(0.016)
	assert_gt(bridge.current_view["tick"], 0)
	main.toggle_flight()
	assert_true(main.flight_screen.visible)
	main.flight_screen.refresh()
	main.toggle_industry()
	main.toggle_fitting()
	main.toggle_automation()
	main.goal_panel.visible = true
	await wait_process_frames(3)
	assert_ne(main.goal_panel.get_child_count(), 0, "the goals panel draws with no station")


func test_the_probe_can_be_sent_to_a_rock() -> void:
	view.select("body", _id_of("bodies", "White Rock"), 0)
	await wait_process_frames(1)
	assert_true(main.order_panel.press("Move to"), "the probe can fly to it")
