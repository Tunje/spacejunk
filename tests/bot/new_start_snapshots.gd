extends SceneTree
## Plays the new start from a new game through every stage and writes the save after each slow
## file's stages to tests/slow/new_start/, for those files to start from (C16). Run it after a data
## or rule change makes them stale:
##   godot --headless --path . -s tests/bot/new_start_snapshots.gd
## A stage with a problem stops it, after the snapshots of the stages before.

## The stage each slow file ends on, in order.
const FILE_ENDS: Array[int] = [
	NewStartBot.STAGE_CHAIN, NewStartBot.STAGE_PREP, NewStartBot.STAGE_LAB, NewStartBot.STAGE_FROST_DOWN,
	NewStartBot.STAGE_FROST_LAP, NewStartBot.STAGE_RETURN, NewStartBot.STAGE_RESEARCH,
]


func _init() -> void:
	var bot := NewStartBot.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NewStartBot.SNAPSHOT_DIR))
	for last in FILE_ENDS:
		bot.play_through(last)
		var problems := bot.problems + bot.ledger_problems + bot.range_problems
		if not problems.is_empty():
			printerr("stage %d: %s" % [last, "; ".join(problems)])
			quit(1)
			return
		var file := FileAccess.open(ProjectSettings.globalize_path(NewStartBot.snapshot_path(last)), FileAccess.WRITE)
		file.store_string(bot.sim.to_save())
		file.close()
		print("stage %d ends at tick %d; snapshot written" % [last, bot.sim.current_tick()])
	quit(0)
