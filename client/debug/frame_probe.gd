class_name FrameProbe extends Node
## Measures real frame cost under load, for tools/frametime.ps1. Vsync is turned
## off for the run, so the numbers are what a frame costs, not the screen's rate.
## Arguments after `--`:
##   --frametime=<absolute json path>  turns the probe on
##   --warmup=<frames>  --samples=<frames>

const TARGET_MS := 1000.0 / 60.0

var main: Node3D
var path := ""
var warmup := 240
var samples := 1200

var _frames_ms: PackedFloat64Array = []
var _last_usec := 0
var _seen := 0
var _op_samples: Dictionary = {}


static func attach_if_requested(parent: Node3D, args: PackedStringArray) -> void:
	var parsed := ScreenshotRunner.parse_args(args)
	if not parsed.has("frametime"):
		return
	var probe := FrameProbe.new()
	probe.main = parent
	probe.path = parsed["frametime"]
	probe.warmup = int(parsed.get("warmup", "240"))
	probe.samples = int(parsed.get("samples", "1200"))
	parent.add_child(probe)


## Frame statistics in milliseconds. The verdict uses p95, so a rare hitch is
## reported through `worst_ms` without failing a run on its own.
static func stats(frames_ms: PackedFloat64Array) -> Dictionary:
	var sorted := frames_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for frame: float in sorted:
		total += frame
	var average := total / sorted.size()
	var p95 := FrameProbe.percentile(sorted, 0.95)
	return {
		"frames": sorted.size(),
		"average_ms": average,
		"average_fps": 1000.0 / average,
		"p50_ms": FrameProbe.percentile(sorted, 0.5),
		"p95_ms": p95,
		"p99_ms": FrameProbe.percentile(sorted, 0.99),
		"worst_ms": sorted[sorted.size() - 1],
		"target_ms": TARGET_MS,
		"passed": p95 <= TARGET_MS,
	}


static func percentile(sorted: PackedFloat64Array, fraction: float) -> float:
	var index := clampi(ceili(sorted.size() * fraction) - 1, 0, sorted.size() - 1)
	return sorted[index]


## Adds each ship's current operation to running totals, as proof of the load.
static func count_ops(view: Dictionary, totals: Dictionary) -> void:
	for id: int in view["units"]:
		var unit: Dictionary = view["units"][id]
		if unit["kind"] == "ship":
			var op: String = unit["op"]["type"]
			totals[op] = totals.get(op, 0) + 1


## The next useful order for an idle unit, or {} if it should carry on. Mining
## first, then scanning, then flying, so the load keeps every effect running.
static func next_order(view: Dictionary, unit_id: int, laser: int, rocks: Array) -> Dictionary:
	var unit: Dictionary = view["units"][unit_id]
	if unit["op"]["type"] != "idle":
		return {}
	if not unit["dock"].is_empty():
		return { "type": "undock", "unit": unit_id, "args": {} }
	var here: int = unit["at_target"]
	if view["bodies"].has(here):
		var ids: Array = view["deposits"].keys()
		ids.sort()
		for id: int in ids:
			if view["deposits"][id]["body"] == here and laser != 0:
				return { "type": "start_mining", "unit": unit_id, "args": { "deposit": id, "module": laser } }
		if not view["bodies"][here]["scanned"]:
			return { "type": "scan", "unit": unit_id, "args": { "target": here } }
	var index: int = (rocks.find(here) + 1 + unit_id) % rocks.size()
	return { "type": "move_to", "unit": unit_id, "args": { "target": rocks[index] } }


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_seen += 1
	_give_orders()
	if _seen <= warmup:
		return
	_frames_ms.append(frame_ms)
	FrameProbe.count_ops(main.bridge.current_view, _op_samples)
	if _frames_ms.size() >= samples:
		_finish()


func _give_orders() -> void:
	var bridge: SimBridge = main.bridge
	var view: Dictionary = bridge.current_view
	var modules: Dictionary = bridge.defs()["modules"]
	var rocks: Array = view["bodies"].keys().filter(
		func(id: int) -> bool: return view["bodies"][id]["kind"] == "asteroid")
	rocks.sort()
	for id: int in view["units"]:
		if view["units"][id]["kind"] == "ship":
			var laser := OrderList._part_with_capability(view["units"][id]["parts"], modules, "mine")
			var order := FrameProbe.next_order(view, id, laser, rocks)
			if not order.is_empty():
				bridge.submit(order)


func _op_share() -> Dictionary:
	var total := 0
	for op: String in _op_samples:
		total += _op_samples[op]
	var share: Dictionary = {}
	for op: String in _op_samples:
		share[op] = snappedf(float(_op_samples[op]) / total, 0.01)
	return share


func _finish() -> void:
	var result := FrameProbe.stats(_frames_ms)
	var view: Dictionary = main.bridge.current_view
	result["units"] = view["units"].size()
	result["ship_op_share"] = _op_share()
	result["ticks"] = view["tick"]
	result["bodies"] = view["bodies"].size()
	result["decorative_rocks"] = main.local_view.field.instance_total
	result["size"] = "%dx%d" % [get_viewport().size.x, get_viewport().size.y]
	result["gpu"] = RenderingServer.get_video_adapter_name()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	get_tree().quit(0 if result["passed"] else 5)
