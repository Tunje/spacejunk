class_name SaveStore extends RefCounted
## One save slot on disk. It holds the simulation's own save text untouched, plus
## client state the simulation does not know about, such as finished goals.

const FORMAT := 1
const DEFAULT_PATH := "user://slot_1.save"
const REASON_NO_SAVE := "no_save"
const REASON_CORRUPT := "corrupt"
const REASON_VERSION := "version_mismatch"

## Tests point this somewhere else, so they never touch the player's slot.
static var path := DEFAULT_PATH


static func exists() -> bool:
	return FileAccess.file_exists(path)


## Writes to a side file first, so a failed save cannot damage the last good one.
static func write(sim_text: String, client_state: Dictionary) -> bool:
	var side_path := path + ".tmp"
	var file := FileAccess.open(side_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({ "format": FORMAT, "sim": sim_text, "client": var_to_str(client_state) }))
	file.close()
	return DirAccess.rename_absolute(side_path, path) == OK


## Returns { sim, client } on success, or { reason } on failure.
static func read() -> Dictionary:
	if not exists():
		return { "reason": REASON_NO_SAVE }
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return { "reason": REASON_CORRUPT }
	var data: Dictionary = parser.data
	if not data.has("format") or not data.get("sim") is String or not data.get("client") is String:
		return { "reason": REASON_CORRUPT }
	if int(data["format"]) != FORMAT:
		return { "reason": REASON_VERSION }
	var client: Variant = str_to_var(data["client"])
	if not client is Dictionary:
		return { "reason": REASON_CORRUPT }
	return { "sim": data["sim"], "client": client }
