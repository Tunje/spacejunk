extends SceneTree

## Validates data/ from the command line. Exit code 0 means no errors.
## godot --headless --path . -s tools/validate_data.gd


func _init() -> void:
	var errors := DataValidator.validate(DataValidator.load_dir())
	for error: String in errors:
		print(error)
	print("%d data errors" % errors.size())
	quit(1 if not errors.is_empty() else 0)
