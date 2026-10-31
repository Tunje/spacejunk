class_name FittingMarkers extends Control
## Free connectors drawn on the 3D hull while fitting. Clicks here pick a slot;
## anything else passes through, so the camera still orbits and zooms.

const RADIUS_PX := 9.0
const PICK_RADIUS_PX := 15.0
const OK_COLOUR := Color(0.55, 0.95, 0.65)

var screen: FittingScreen
var _shown: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false


func _process(_delta: float) -> void:
	if visible:
		update_slots()


func update_slots() -> void:
	_shown.clear()
	var view := screen.local_view
	var craft: CraftNode = view.crafts.get(view.commanded_unit)
	if craft == null:
		return
	var unit := screen.unit()
	var modules: Dictionary = screen._modules
	var parts := InspectText.flatten(unit["parts"])
	for slot: Dictionary in FittingLogic.free_slots(unit, modules):
		var world := craft.transform * (craft.part_transforms[slot["part"]] as Transform3D) * _connector_point(parts, slot, modules)
		if not view.camera.is_position_behind(world):
			_shown.append({ "slot": slot, "at": view.camera.unproject_position(world), "ok": screen.slot_ok(slot) })
	queue_redraw()


func pick(at: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_gap := PICK_RADIUS_PX
	for entry: Dictionary in _shown:
		var gap: float = (entry["at"] as Vector2).distance_to(at)
		if gap <= best_gap:
			best_gap = gap
			best = entry["slot"]
	return best


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		var slot := pick(button.position)
		if not slot.is_empty():
			screen.choose_slot(slot)
			accept_event()


func _connector_point(parts: Array[Dictionary], slot: Dictionary, modules: Dictionary) -> Vector3:
	for part: Dictionary in parts:
		if part["id"] == slot["part"]:
			return CraftLayout.to_metres(CraftLayout.find_connector(modules[part["def"]], slot["connector"])["pos_mm"])
	return Vector3.ZERO


func _draw() -> void:
	for entry: Dictionary in _shown:
		var colour: Color = OK_COLOUR if entry["ok"] else ClientTheme.ORANGE
		draw_arc(entry["at"], RADIUS_PX, 0.0, TAU, 24, colour, 2.0, true)
		if entry["slot"] == screen.slot:
			draw_circle(entry["at"], RADIUS_PX * 0.55, colour)
