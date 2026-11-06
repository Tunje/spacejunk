extends SceneTree
## The coast soak's deep run (task A35): many seeds of tests/sim/kernel/coast_soak.gd, each a random
## game run once stepped and once coasted and compared at every coast return. The gate runs a few
## fixed seeds in tests/slow/test_coast_soak.gd; run this after changing a horizon or closed form.
##
## Run: godot --headless --path . -s tools/coast_soak.gd -- [first seed] [seed count] [ticks]

const CoastSoak := preload("res://tests/sim/kernel/coast_soak.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var first := int(args[0]) if args.size() > 0 else 1
	var count := int(args[1]) if args.size() > 1 else 100
	var ticks := int(args[2]) if args.size() > 2 else 8_000
	var failed := 0
	for seed in range(first, first + count):
		var started := Time.get_ticks_msec()
		var result: Dictionary = CoastSoak.run_seed(seed, ticks)
		print("seed %d: %s, %d ticks in %d calls, %d ms, capped by %s, events %s" % [seed, "ok" if result["ok"] else result["message"],
			result["ticks"], result["calls"], Time.get_ticks_msec() - started, str(result["caps"]), str(result["events"])])
		if not result["ok"]:
			failed += 1
	print("COAST SOAK %d of %d seeds failed" % [failed, count])
	quit(1 if failed > 0 else 0)
