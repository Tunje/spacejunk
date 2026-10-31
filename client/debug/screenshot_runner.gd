class_name ScreenshotRunner extends Node
## Saves one rendered frame and quits, for tools/screenshot.ps1. Arguments come
## after `--` on the Godot command line:
##   --shot=<absolute png path>  turns the runner on
##   --frames=<n>                frames to wait first (default 30)

var path := ""
var frames := 30


static func parse_args(args: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for arg: String in args:
		if arg.begins_with("--") and arg.contains("="):
			parsed[arg.get_slice("=", 0).trim_prefix("--")] = arg.get_slice("=", 1)
	return parsed


static func attach_if_requested(parent: Node, args: PackedStringArray) -> ScreenshotRunner:
	var parsed := parse_args(args)
	if not parsed.has("shot"):
		return null
	var runner := ScreenshotRunner.new()
	runner.path = parsed["shot"]
	runner.frames = int(parsed.get("frames", "30"))
	parent.add_child(runner)
	return runner


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	for i in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit(0 if error == OK else 1)
