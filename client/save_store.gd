class_name SaveStore extends RefCounted
## Save slots on disk. Each holds the simulation's own save text untouched, plus
## client state the simulation does not know about, such as finished goals.
## There are two slots: the manual one F5 writes, and the autosave, kept apart
## so an autosave never replaces a deliberate save.

const FORMAT := 1
const DEFAULT_PATH := "user://slot_1.save"
const DEFAULT_AUTOSAVE_PATH := "user://autosave.save"
const REASON_NO_SAVE := "no_save"
const REASON_CORRUPT := "corrupt"
const REASON_VERSION := "version_mismatch"

## Tests point these somewhere else, so they never touch the player's slots.
static var path := DEFAULT_PATH
static var autosave_path := DEFAULT_AUTOSAVE_PATH

## The last stamp written, so two saves in one run never share a stamp.
static var _last_stamp := 0


## An empty `at` means the manual slot.
static func exists(at := "") -> bool:
	return FileAccess.file_exists(_slot(at))


## Writes to a side file first, so a failed save cannot damage the last good one.
## Each save is stamped in microseconds of real time, so loads can pick the newer slot.
static func write(sim_text: String, client_state: Dictionary, at := "") -> bool:
	var target := _slot(at)
	var side_path := target + ".tmp"
	var file := FileAccess.open(side_path, FileAccess.WRITE)
	if file == null:
		return false
	_last_stamp = maxi(int(Time.get_unix_time_from_system() * 1_000_000.0), _last_stamp + 1)
	file.store_string(JSON.stringify({
		"format": FORMAT, "saved_us": _last_stamp, "sim": sim_text, "client": var_to_str(client_state),
	}))
	file.close()
	return DirAccess.rename_absolute(side_path, target) == OK


## Returns { sim, client, saved_us } on success, or { reason } on failure.
## A save from before stamps were added reads as stamp 0, the oldest possible.
static func read(at := "") -> Dictionary:
	var target := _slot(at)
	if not FileAccess.file_exists(target):
		return { "reason": REASON_NO_SAVE }
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(target)) != OK or not parser.data is Dictionary:
		return { "reason": REASON_CORRUPT }
	var data: Dictionary = parser.data
	if not data.has("format") or not data.get("sim") is String or not data.get("client") is String:
		return { "reason": REASON_CORRUPT }
	if int(data["format"]) != FORMAT:
		return { "reason": REASON_VERSION }
	var client: Variant = str_to_var(data["client"])
	if not client is Dictionary:
		return { "reason": REASON_CORRUPT }
	var stamp: Variant = data.get("saved_us", 0)
	if not (stamp is float or stamp is int):
		return { "reason": REASON_CORRUPT }
	return { "sim": data["sim"], "client": client, "saved_us": int(stamp) }


## Both slots, each marked with `auto`. Readable slots come first, newest first,
## with the manual slot ahead on a tie; slots that failed to read come last.
static func read_newest_first() -> Array[Dictionary]:
	var manual := read(path)
	manual["auto"] = false
	var auto := read(autosave_path)
	auto["auto"] = true
	var good: Array[Dictionary] = []
	var bad: Array[Dictionary] = []
	for slot: Dictionary in [manual, auto]:
		if slot.has("reason"):
			bad.append(slot)
		else:
			good.append(slot)
	if good.size() == 2 and int(good[1]["saved_us"]) > int(good[0]["saved_us"]):
		good.reverse()
	good.append_array(bad)
	return good


static func _slot(at: String) -> String:
	return path if at.is_empty() else at
