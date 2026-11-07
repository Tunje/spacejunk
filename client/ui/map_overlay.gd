class_name MapOverlay extends Control
## Names, scale rings and travel time for the system map.

## The trip text under a selected entry wraps at this width.
const ETA_WIDTH_PX := 380

var map: SystemMap
var _shown: Array[Dictionary] = []
var _frames: Array[Dictionary] = []
## Switches between the craft-centred map and the System view (D37); Y does too.
var system_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	system_button = Button.new()
	system_button.theme = ClientTheme.build()
	system_button.focus_mode = Control.FOCUS_NONE
	system_button.text = "System view (Y)"
	system_button.position = Vector2(360, 76)
	system_button.pressed.connect(func() -> void:
		map.toggle_system()
		system_button.text = "Around the craft (Y)" if map.system_view else "System view (Y)")
	add_child(system_button)


func update_entries() -> void:
	_shown.clear()
	for entry: Dictionary in map.entries:
		var position_3d: Vector3 = entry["map_pos"]
		if not map.camera.is_position_behind(position_3d):
			var shown: Dictionary = entry.duplicate()
			shown["at"] = map.camera.unproject_position(position_3d)
			_shown.append(shown)
	_frames.clear()
	for frame: Dictionary in map.frame_labels:
		if not map.camera.is_position_behind(frame["map_pos"]):
			_frames.append({ "label": frame["label"], "at": map.camera.unproject_position(frame["map_pos"]) })
	queue_redraw()


func pick(screen: Vector2) -> Dictionary:
	return EntityMarkers.pick_entry(_shown, screen)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	system_button.text = "Around the craft (Y)" if map.system_view else "System view (Y)"
	for km: float in SystemMap.RINGS_KM if not map.system_view else []:
		var edge := Vector3(0, 0, SystemMap.map_radius(km * SystemMap.KM_IN_M))
		if not map.camera.is_position_behind(edge):
			var at := map.camera.unproject_position(edge)
			draw_string(font, at, SystemMap.ring_label(km), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, ClientTheme.MID_GREY)
	for frame: Dictionary in _frames:
		draw_string(font, frame["at"] + Vector2(0, -14), frame["label"], HORIZONTAL_ALIGNMENT_CENTER, -1, 11, ClientTheme.MID_GREY)
	EntityMarkers.draw_entries(self, _shown)
	if map.eta_text.is_empty():
		return
	for entry: Dictionary in _shown:
		if entry["selected"]:
			var below: Vector2 = entry["at"] + Vector2(EntityMarkers.DIAMOND_PX + 5, 22)
			# Two lines when the trip has a faster plan (D40), each wrapped so it stays clear of the panels.
			draw_multiline_string(font, below, map.eta_text, HORIZONTAL_ALIGNMENT_LEFT, ETA_WIDTH_PX, 13, -1, ClientTheme.GOLD)
