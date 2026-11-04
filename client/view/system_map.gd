class_name SystemMap extends Node3D
## The 3D system map, centred on the commanded craft. Distance is logarithmic,
## so a nearby asteroid and the star fit one screen; rings show the real scale.
## It shares the local view's selection, so orders work the same from here.

const RADIUS_PER_DECADE := 6.0
const NEAR_DECADES := 2.0
const FAR_DECADE_FACTOR := 0.35
const KM_IN_M := 1000.0
const RINGS_KM: Array[float] = [1.0, 10.0, 100.0, 10000.0, 100000000.0]
const RING_SEGMENTS := 96
const RING_COLOUR := Color(0.2, 0.22, 0.27)
const ROUTE_SEGMENTS := 24
const CLICK_SLOP_PX := 5.0

var bridge: SimBridge
var local_view: LocalView
var entries: Array[Dictionary] = []
var eta_text := ""
var _press_position := Vector2.ZERO
var _pressed := false
var _orbiting := false

@onready var camera: OrbitCamera = $Camera
@onready var routes: MeshInstance3D = $Routes
@onready var rings: MeshInstance3D = $Rings
@onready var overlay: MapOverlay = %MapOverlay


## Maps a focus-relative position in metres to map space.
static func project(relative_m: Vector3) -> Vector3:
	var distance := float(relative_m.length())
	if distance <= 0.0:
		return Vector3.ZERO
	return relative_m / distance * map_radius(distance)


static func map_radius(distance_m: float) -> float:
	var decades := log(1.0 + distance_m / KM_IN_M) / log(10.0)
	if decades > NEAR_DECADES:
		decades = NEAR_DECADES + (decades - NEAR_DECADES) * FAR_DECADE_FACTOR
	return decades * RADIUS_PER_DECADE


static func ring_label(km: float) -> String:
	if km >= 1000000.0:
		return "%s million km" % String.num(km / 1000000.0, 0)
	return "%s km" % String.num(km, 0)


func bind(new_bridge: SimBridge, view: LocalView) -> void:
	bridge = new_bridge
	local_view = view
	overlay.map = self
	camera.current = false
	camera.pitch = -0.75
	camera.distance_m = 46.0
	camera.target_distance_m = 46.0
	rings.mesh = _build_rings()
	rings.material_override = _line_material()
	routes.mesh = ImmediateMesh.new()
	routes.material_override = _line_material()
	visible = false
	overlay.visible = false


func is_open() -> bool:
	return visible


func set_open(open: bool) -> void:
	visible = open
	overlay.visible = open
	local_view.visible = not open
	local_view.markers.visible = not open
	camera.current = open
	local_view.camera.current = not open
	if open:
		refresh(0.0)


func _process(delta: float) -> void:
	if visible:
		refresh(delta)


func refresh(delta: float) -> void:
	var after: Dictionary = bridge.current_view
	var before: Dictionary = bridge.previous_view
	var alpha := bridge.interpolation_alpha()
	var centre: int = local_view.commanded_unit
	var centre_before := WorldPosition.of(before["units"].get(centre, after["units"][centre]))
	var centre_after := WorldPosition.of(after["units"][centre])
	entries.clear()
	for id: int in after["bodies"]:
		var body: Dictionary = after["bodies"][id]
		var from_mm := WorldPosition.of(before["bodies"].get(id, body))
		_add_entry("body", id, body["name"], FloatingOrigin.relative_m(from_mm, WorldPosition.of(body), centre_before, centre_after, alpha))
	for id: int in after["units"]:
		var unit: Dictionary = after["units"][id]
		var from_mm := WorldPosition.of(before["units"].get(id, unit))
		_add_entry("unit", id, unit["name"], FloatingOrigin.relative_m(from_mm, WorldPosition.of(unit), centre_before, centre_after, alpha))
	_draw_routes(after, centre_after)
	eta_text = _eta_for_selection(after)
	camera.update_view(delta)
	overlay.update_entries()


func _add_entry(kind: String, id: int, label: String, relative: Vector3) -> void:
	entries.append({
		"kind": kind, "id": id, "label": label, "map_pos": SystemMap.project(relative),
		"selected": local_view.selected_kind == kind and local_view.selected_id == id,
	})


func _relative(mm: Array, centre: Array) -> Vector3:
	return FloatingOrigin.relative_m(mm, mm, centre, centre, 0.0)


## Straight routes bend on a log map, so each is drawn from sampled points.
func _draw_routes(view: Dictionary, centre: Array) -> void:
	var mesh: ImmediateMesh = routes.mesh
	mesh.clear_surfaces()
	for id: int in view["units"]:
		var unit: Dictionary = view["units"][id]
		if not unit["route"].is_empty():
			_add_line(mesh, _relative(WorldPosition.of(unit), centre),
				_relative(WorldPosition.local_to_world(unit, unit["route"]["to_mm"]), centre), ClientTheme.ORANGE)
	var target := _selected_position(view)
	if not target.is_empty() and view["units"].has(local_view.commanded_unit):
		var unit: Dictionary = view["units"][local_view.commanded_unit]
		if unit["route"].is_empty():
			_add_line(mesh, Vector3.ZERO, _relative(target, centre), ClientTheme.GOLD)


func _add_line(mesh: ImmediateMesh, from: Vector3, to: Vector3, colour: Color) -> void:
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for index in range(ROUTE_SEGMENTS + 1):
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(SystemMap.project(from.lerp(to, float(index) / ROUTE_SEGMENTS)))
	mesh.surface_end()


func _selected_position(view: Dictionary) -> Array:
	match local_view.selected_kind:
		"body":
			if view["bodies"].has(local_view.selected_id):
				return WorldPosition.of(view["bodies"][local_view.selected_id])
		"unit":
			if local_view.selected_id != local_view.commanded_unit and view["units"].has(local_view.selected_id):
				return WorldPosition.of(view["units"][local_view.selected_id])
	return []


## Travel time from check(), so the client never prices a route itself.
func _eta_for_selection(view: Dictionary) -> String:
	if _selected_position(view).is_empty():
		return ""
	var result: Dictionary = bridge.check({
		"type": "move_to", "unit": local_view.commanded_unit, "args": { "target": local_view.selected_id },
	})
	if not result["ok"]:
		return ""
	return OrderText.duration(float(result["detail"]["ticks"]) / bridge.ticks_per_second())


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var button := event as InputEventMouseButton
	if button != null:
		_handle_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _orbiting:
		camera.orbit(motion.relative)
		get_viewport().set_input_as_handled()


func _handle_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if button.pressed:
				camera.zoom(-1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				camera.zoom(1.0)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_orbiting = button.pressed
		MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pressed = true
				_press_position = button.position
			elif _pressed:
				_pressed = false
				if button.position.distance_to(_press_position) <= CLICK_SLOP_PX:
					click_at(button.position)


func click_at(screen: Vector2) -> void:
	var hit := overlay.pick(screen)
	if hit.is_empty():
		local_view.clear_selection()
	else:
		local_view.select(hit["kind"], hit["id"], hit["part"])


func _build_rings() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	for km: float in RINGS_KM:
		var radius := SystemMap.map_radius(km * KM_IN_M)
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for index in range(RING_SEGMENTS + 1):
			var angle := TAU * index / RING_SEGMENTS
			mesh.surface_set_color(RING_COLOUR)
			mesh.surface_add_vertex(Vector3(cos(angle), 0.0, sin(angle)) * radius)
		mesh.surface_end()
	return mesh


func _line_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	return material
