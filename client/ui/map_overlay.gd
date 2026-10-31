class_name MapOverlay extends Control
## Names, scale rings and travel time for the system map.

var map: SystemMap
var _shown: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func update_entries() -> void:
	_shown.clear()
	for entry: Dictionary in map.entries:
		var position_3d: Vector3 = entry["map_pos"]
		if not map.camera.is_position_behind(position_3d):
			var shown: Dictionary = entry.duplicate()
			shown["at"] = map.camera.unproject_position(position_3d)
			_shown.append(shown)
	queue_redraw()


func pick(screen: Vector2) -> Dictionary:
	return EntityMarkers.pick_entry(_shown, screen)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for km: float in SystemMap.RINGS_KM:
		var edge := Vector3(0, 0, SystemMap.map_radius(km * SystemMap.KM_IN_M))
		if not map.camera.is_position_behind(edge):
			var at := map.camera.unproject_position(edge)
			draw_string(font, at, SystemMap.ring_label(km), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, ClientTheme.MID_GREY)
	EntityMarkers.draw_entries(self, _shown)
	if map.eta_text.is_empty():
		return
	for entry: Dictionary in _shown:
		if entry["selected"]:
			var below: Vector2 = entry["at"] + Vector2(EntityMarkers.DIAMOND_PX + 5, 22)
			draw_string(font, below, map.eta_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ClientTheme.GOLD)
