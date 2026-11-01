extends GutTest
## C7: the same seed and commands give the same state hash, with and without saves and loads
## midway. The run without is the bot's shared chain, so this pays for one replay only.

const SEED := ReferenceBot.SEED

var bot: ReferenceBot


func before_all() -> void:
	bot = ReferenceBot.shared()


## Ticks to save on: the middle of a trip, a refinery run, a fabrication run and the craft's build,
## then each lap's outbound trip, mining, and homeward docking.
func _save_ticks() -> Array[int]:
	var ticks: Array[int] = []
	for label: String in ["move_to", "refine_hematite", "mining_laser_mk1", "small_craft"]:
		for step in bot.steps:
			if step["label"] == label:
				ticks.append(step["start_tick"] + step["ticks"] / 2 + 3)
				break
	var lap_start := bot.cycle_start_tick
	for offset: int in [1000, 2800, 5200]:
		ticks.append(lap_start + offset)
	ticks.sort()
	return ticks


## Replays the bot's commands from a new game, saving and reloading at each of `save_ticks`.
func _replay(save_ticks: Array[int]) -> Sim:
	var sim := Sim.new_game("reference", SEED)
	var saves := save_ticks.duplicate()
	for entry: Dictionary in bot.commands:
		sim = _advance(sim, entry["tick"], saves)
		sim.submit(entry["command"])
	return _advance(sim, bot.sim.current_tick(), saves)


## Steps to a tick, reloading from a save at each one due on the way.
func _advance(sim: Sim, tick: int, saves: Array[int]) -> Sim:
	var current := sim
	while not saves.is_empty() and saves[0] <= tick:
		current.step(saves[0] - current.current_tick())
		saves.pop_front()
		current.take_events()
		var text := current.to_save()
		current = Sim.from_save(text)
		assert_not_null(current, "loads")
		assert_eq(current.to_save(), text, "round trip at tick %d" % current.current_tick())
	current.step(tick - current.current_tick())
	current.take_events()
	return current


func test_all_the_save_ticks_fall_inside_the_run() -> void:
	var ticks := _save_ticks()
	assert_eq(ticks.size(), 7)
	assert_gt(ticks[0], 0)
	assert_lt(ticks.back(), bot.sim.current_tick())


func test_the_run_replays_identically_through_saves_and_loads() -> void:
	var replayed := _replay(_save_ticks())
	assert_eq(replayed.current_tick(), bot.sim.current_tick())
	assert_eq(replayed.state_hash(), bot.sim.state_hash())
	var matter: Dictionary = replayed.ledger()["matter"]
	assert_eq(matter["total_g"], matter["start_g"])
