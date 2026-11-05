extends SceneTree
## Shows a generated model close up, as B9's art test did, to check ModelLook by eye:
##   run windowed: godot -s res://client/debug/model_view.gd -- <options>
##   --model=res://assets/models/starter_hull.glb   --look=on|off   --env=b9|game
##   --out=<png path>
## `b9` is the art test's lighting; `game` is the flight scene's own environment.

const SHOT_FRAMES := 20


func _initialize() -> void:
	var args := {}
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	var path: String = args.get("model", "res://assets/models/starter_hull.glb")
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var world := WorldEnvironment.new()
	world.environment = _environment(args.get("env", "b9"))
	root3d.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_energy = 1.6
	root3d.add_child(sun)
	var model: Node3D
	if args.get("look", "on") == "on":
		model = ModelLook.instantiate(path)
	else:
		model = (load(path) as PackedScene).instantiate()
	model.position = Vector3(0, 3.0, 0)
	root3d.add_child(model)
	var cam := Camera3D.new()
	cam.fov = 60
	root3d.add_child(cam)
	cam.look_at_from_position(Vector3(5, 4.5, 7), Vector3(0.5, 2.5, 0))
	_shoot.call_deferred(args.get("out", "user://model_view.png"))


func _environment(kind: String) -> Environment:
	if kind == "game":
		var main := (load("res://client/main.tscn") as PackedScene).instantiate()
		var env: Environment = (main.get_node("WorldEnvironment") as WorldEnvironment).environment
		main.free()
		return env
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.35, 0.4)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	return e


func _shoot(out: String) -> void:
	for i in SHOT_FRAMES:
		await process_frame
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit(0)
