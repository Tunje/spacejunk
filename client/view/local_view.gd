class_name LocalView extends Node3D
## The 3D local view: draws every view entity around the focus, runs the orbit
## camera and turns clicks into a selection. It reads views and never drives logic.

signal selection_changed

const CLICK_SLOP_PX := 5.0
const RAY_LENGTH_M := 400000.0
const FOCUS_SETTLE_RATE := 6.0
const HEADING_RATE := 3.0
const DOCK_BLEND_SECONDS := 1.0
const SHADOW_RANGE_FACTOR := 6.0
const MIN_SHADOW_RANGE_M := 120.0
const MAX_SHADOW_RANGE_M := 9000.0

var bridge: SimBridge
var selected_kind := ""
var selected_id := 0
var selected_part := 0
var commanded_unit := 0
var focus_kind := "unit"
var focus_id := 0
var crafts: Dictionary = {}
var bodies: Dictionary = {}
var field: AsteroidField

var _modules: Dictionary = {}
var _pivot_offset := Vector3.ZERO
var _press_position := Vector2.ZERO
var _pressed := false
var _orbiting := false
var _pending_click: Variant = null

@onready var camera: OrbitCamera = $Camera
@onready var sun: DirectionalLight3D = $Sun
@onready var fill: DirectionalLight3D = $Fill
@onready var markers: EntityMarkers = %Markers


func bind(new_bridge: SimBridge) -> void:
	bridge = new_bridge
	_modules = bridge.defs()["modules"]
	_sync_entities()
	field = AsteroidField.new()
	add_child(field)
	field.build(bridge.current_view)
	var first_ship := _first_unit("ship")
	commanded_unit = first_ship
	focus_on("unit", first_ship)
	select("unit", first_ship, 0)
	camera.distance_m = camera.target_distance_m
	refresh(0.0)


func _process(delta: float) -> void:
	if bridge != null and not bridge.current_view.is_empty():
		refresh(delta)


func _physics_process(_delta: float) -> void:
	if _pending_click == null:
		return
	var click: Vector2 = _pending_click
	_pending_click = null
	click_at(click)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		_handle_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _orbiting:
		camera.orbit(motion.relative)
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		_handle_key(key)


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
				if button.double_click:
					focus_on_selection()
			elif _pressed:
				_pressed = false
				if button.position.distance_to(_press_position) <= CLICK_SLOP_PX:
					_pending_click = button.position


func _handle_key(key: InputEventKey) -> void:
	if key.physical_keycode == KEY_F:
		focus_on_selection()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_TAB:
		_cycle_unit()
		get_viewport().set_input_as_handled()


func focus_on_selection() -> void:
	if selected_kind != "":
		focus_on(selected_kind, selected_id)


## Moves the focus. The old pivot carries over as an offset that settles to
## zero, so the camera glides instead of snapping.
func focus_on(kind: String, id: int) -> void:
	var node := _node_of(kind, id)
	if node == null:
		return
	_pivot_offset = camera.pivot - node.position
	focus_kind = kind
	focus_id = id
	var radius: float = node.fit_radius_m if node is CraftNode else node.radius_m
	camera.frame_radius(radius)


func select(kind: String, id: int, part: int) -> void:
	if selected_kind == "unit" and crafts.has(selected_id):
		crafts[selected_id].highlight(0)
	selected_kind = kind
	selected_id = id
	selected_part = part
	if kind == "unit":
		if crafts.has(id):
			crafts[id].highlight(part)
		if bridge.current_view["units"][id]["kind"] != "station":
			commanded_unit = id
	selection_changed.emit()


func clear_selection() -> void:
	select("", 0, 0)


## Must run in a physics step, because it queries the physics space.
func click_at(screen: Vector2) -> void:
	var from := camera.project_ray_origin(screen)
	var hit := pick_ray(from, camera.project_ray_normal(screen))
	if hit.is_empty():
		hit = markers.pick(screen)
	if hit.is_empty():
		clear_selection()
	else:
		select(hit["kind"], hit["id"], hit["part"])


func pick_ray(from: Vector3, direction: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RAY_LENGTH_M)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Object = hit["collider"]
	if collider.has_meta("unit"):
		return { "kind": "unit", "id": collider.get_meta("unit"), "part": collider.get_meta("part") }
	return { "kind": "body", "id": collider.get_meta("body"), "part": 0 }


func refresh(delta: float) -> void:
	_sync_entities()
	var alpha := bridge.interpolation_alpha()
	var before: Dictionary = bridge.previous_view
	var after: Dictionary = bridge.current_view
	var focus_before := _position_in(before, after, focus_kind, focus_id)
	var focus_after := _position_in(after, after, focus_kind, focus_id)
	for id: int in bodies:
		var entry: Dictionary = after["bodies"][id]
		var relative := FloatingOrigin.relative_m(
			before["bodies"].get(id, entry)["pos_mm"], entry["pos_mm"], focus_before, focus_after, alpha)
		bodies[id].place(relative)
		if bodies[id].kind == "star":
			sun.look_at_from_position(relative.normalized(), Vector3.ZERO)
			fill.look_at_from_position(-relative.normalized(), Vector3.ZERO)
	field.position = FloatingOrigin.relative_m(field.anchor_mm, field.anchor_mm, focus_before, focus_after, alpha)
	for docked_pass: bool in [false, true]:
		for id: int in crafts:
			if after["units"][id]["dock"].is_empty() != docked_pass:
				_place_craft(crafts[id], id, before, after, focus_before, focus_after, alpha, delta)
	_pivot_offset *= exp(-FOCUS_SETTLE_RATE * delta)
	camera.pivot = _node_of(focus_kind, focus_id).position + _pivot_offset
	camera.update_view(delta)
	sun.directional_shadow_max_distance = clampf(
		camera.distance_m * SHADOW_RANGE_FACTOR, MIN_SHADOW_RANGE_M, MAX_SHADOW_RANGE_M)
	markers.update_entities()


func _place_craft(craft: CraftNode, id: int, before: Dictionary, after: Dictionary,
		focus_before: Array, focus_after: Array, alpha: float, delta: float) -> void:
	var unit: Dictionary = after["units"][id]
	var relative := FloatingOrigin.relative_m(
		before["units"].get(id, unit)["pos_mm"], unit["pos_mm"], focus_before, focus_after, alpha)
	if not unit["route"].is_empty():
		var aim := CraftLayout.to_metres(unit["route"]["to_mm"]) - CraftLayout.to_metres(unit["route"]["from_mm"])
		if aim.length_squared() > 0.0:
			craft.heading = craft.heading.slerp(CraftLayout.heading_towards(aim), 1.0 - exp(-HEADING_RATE * delta))
	var free := Transform3D(Basis(craft.heading), relative)
	var docked := _docked_transform(craft, unit)
	var step := delta / DOCK_BLEND_SECONDS
	craft.dock_blend = move_toward(craft.dock_blend, 0.0 if unit["dock"].is_empty() else 1.0, step)
	if craft.dock_blend > 0.0 and docked != Transform3D.IDENTITY:
		craft.transform = free.interpolate_with(docked, smoothstep(0.0, 1.0, craft.dock_blend))
	else:
		craft.transform = free


func _docked_transform(craft: CraftNode, unit: Dictionary) -> Transform3D:
	if unit["dock"].is_empty():
		return Transform3D.IDENTITY
	var dock: Dictionary = unit["dock"]
	var host: CraftNode = crafts[dock["target_unit"]]
	var host_port := _find_part(bridge.current_view["units"][dock["target_unit"]]["parts"], dock["target_port"])
	var own_port := _find_part(unit["parts"], dock["port"])
	return CraftLayout.docked_root(
		host.transform * host.part_transforms[dock["target_port"]],
		CraftLayout.dock_connector(_modules[host_port["def"]]),
		CraftLayout.dock_connector(_modules[own_port["def"]]),
		craft.part_transforms[dock["port"]])


func _find_part(part: Dictionary, part_id: int) -> Dictionary:
	if part["id"] == part_id:
		return part
	for child: Dictionary in part["children"]:
		var found := _find_part(child, part_id)
		if not found.is_empty():
			return found
	return {}


func _sync_entities() -> void:
	var view: Dictionary = bridge.current_view
	for id: int in view["bodies"]:
		if not bodies.has(id):
			var body := BodyNode.new()
			body.build(id, view["bodies"][id])
			add_child(body)
			bodies[id] = body
	for id: int in bodies.keys():
		if not view["bodies"].has(id):
			bodies[id].queue_free()
			bodies.erase(id)
	for id: int in view["units"]:
		if not crafts.has(id):
			var craft := CraftNode.new()
			add_child(craft)
			crafts[id] = craft
		var root: Dictionary = view["units"][id]["parts"]
		if crafts[id].signature != CraftNode.signature_of(root):
			crafts[id].build(id, root, _modules)
	for id: int in crafts.keys():
		if not view["units"].has(id):
			crafts[id].queue_free()
			crafts.erase(id)


func _position_in(view: Dictionary, fallback: Dictionary, kind: String, id: int) -> Array:
	var section: String = "units" if kind == "unit" else "bodies"
	return view[section].get(id, fallback[section][id])["pos_mm"]


func _node_of(kind: String, id: int) -> Node3D:
	return crafts.get(id) if kind == "unit" else bodies.get(id)


func _first_unit(kind: String) -> int:
	var ids: Array = bridge.current_view["units"].keys()
	ids.sort()
	for id: int in ids:
		if bridge.current_view["units"][id]["kind"] == kind:
			return id
	return ids[0]


func _cycle_unit() -> void:
	var ids: Array = bridge.current_view["units"].keys()
	ids.sort()
	var next: int = ids[(ids.find(focus_id) + 1) % ids.size()]
	select("unit", next, 0)
	focus_on("unit", next)
