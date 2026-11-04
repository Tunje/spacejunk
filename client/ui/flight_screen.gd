class_name FlightScreen extends PanelContainer
## Manual flight for the commanded craft (A11). Place a burn on the path, read the
## preview from check(plan_burn) and see the path after it beside the current one,
## then plan it or clear it. Works on an orbit, and in a frame, where a burn starts
## a straight drift. The current path comes from predict(), the planned one from
## check's orbit or velocity. Orbits are drawn to scale in the panel's diagram,
## since the map's log scale bends them; a drift is a short straight line, drawn
## in the local view and on the map.

const WIDTH_PX := 400
const MAX_DV_M_S := 5000.0
const DV_STEP_M_S := 0.5
const MAX_LEAD_S := 36000.0
const LOOP_POINTS := 128
const PREDICT_POINTS := 96
const DRIFT_SECONDS := 600.0
const DRIFT_POINTS := 24
const MARKER_LOCAL_FRACTION := 0.03
const MARKER_MAP := 0.35
const PATH_COLOUR := Color(0.62, 0.65, 0.7)
const PLAN_COLOUR := Color(0.95, 0.42, 0.08)

signal closed

var bridge: SimBridge
var local_view: LocalView
var system_map: SystemMap
## The burn's tick, absolute, so its place on the path holds while time runs.
var burn_tick := 0
var preview: Dictionary = {}
## World-mm point lists, from the last time the path data was worked out.
var current_path: Array[PackedFloat64Array] = []
var planned_path: Array[PackedFloat64Array] = []
var marker := PackedFloat64Array()
var _path_key := ""
var _burns_key := ""
var _title: Label
var _place: Label
var _diagram: OrbitDiagram
var _burns_box: VBoxContainer
var _when: SpinBox
var _now_button: Button
var _peri_button: Button
var _apo_button: Button
var _axes: Array[SpinBox] = []
var _cost: Label
var _after: Label
var _plan_button: Button
var _clear_button: Button
var _message: Label
var _local_mesh: MeshInstance3D
var _map_mesh: MeshInstance3D


func _ready() -> void:
	theme = ClientTheme.build()
	add_theme_stylebox_override("panel", ClientTheme.solid_panel())
	custom_minimum_size = Vector2(WIDTH_PX, 0)
	visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = _add_label(header)
	_title.modulate = ClientTheme.ORANGE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_button(header, "Close").pressed.connect(toggle)
	_place = _add_label(column)
	_diagram = OrbitDiagram.new()
	_diagram.visible = false
	column.add_child(_diagram)
	_burns_box = VBoxContainer.new()
	column.add_child(_burns_box)
	column.add_child(HSeparator.new())
	var when_row := HBoxContainer.new()
	column.add_child(when_row)
	var when_label := _add_label(when_row)
	when_label.text = "Burn in (s)"
	when_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_when = _add_spin(when_row, 0.0, MAX_LEAD_S, 0.1)
	_when.value_changed.connect(_on_when_changed)
	var jump_row := HBoxContainer.new()
	column.add_child(jump_row)
	_now_button = _add_button(jump_row, "Now")
	_now_button.pressed.connect(burn_now)
	_peri_button = _add_button(jump_row, "At periapsis")
	_peri_button.pressed.connect(burn_at_apsis.bind(0.0))
	_apo_button = _add_button(jump_row, "At apoapsis")
	_apo_button.pressed.connect(burn_at_apsis.bind(PI))
	for axis: String in ["Prograde", "Normal", "Radial out"]:
		var row := HBoxContainer.new()
		column.add_child(row)
		var label := _add_label(row)
		label.text = "%s (m/s)" % axis
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var spin := _add_spin(row, -MAX_DV_M_S, MAX_DV_M_S, DV_STEP_M_S)
		spin.value_changed.connect(func(_value: float) -> void: refresh())
		_axes.append(spin)
	_cost = _add_label(column)
	_after = _add_label(column)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_plan_button = _add_button(buttons, "Plan burn")
	_plan_button.pressed.connect(plan)
	_clear_button = _add_button(buttons, "Clear")
	_clear_button.pressed.connect(clear)
	_message = _add_label(column)
	_message.modulate = ClientTheme.ORANGE


func bind(new_bridge: SimBridge, view: LocalView, map: SystemMap) -> void:
	bridge = new_bridge
	local_view = view
	system_map = map
	_local_mesh = _path_mesh()
	local_view.add_child(_local_mesh)
	_map_mesh = _path_mesh()
	system_map.add_child(_map_mesh)
	bridge.view_updated.connect(refresh)
	local_view.selection_changed.connect(refresh)


func toggle() -> void:
	visible = not visible
	_local_mesh.visible = visible
	_map_mesh.visible = visible
	if visible:
		burn_tick = 0
		_message.text = ""
		refresh()
	else:
		closed.emit()


func unit_id() -> int:
	return local_view.commanded_unit


func unit() -> Dictionary:
	return bridge.current_view["units"].get(unit_id(), {})


## The burn as typed: three axes in um/s.
func components() -> Array[int]:
	var out: Array[int] = []
	for spin: SpinBox in _axes:
		out.append(FlightLogic.to_um_s(spin.value))
	return out


func set_components(prograde_m_s: float, normal_m_s := 0.0, radial_m_s := 0.0) -> void:
	for index in 3:
		_axes[index].set_value_no_signal([prograde_m_s, normal_m_s, radial_m_s][index])
	refresh()


func pending_command() -> Dictionary:
	if components() == [0, 0, 0]:
		return {}
	return FlightLogic.burn_command(unit_id(), burn_tick, components())


func burn_now() -> void:
	burn_tick = bridge.current_view["tick"] + 1
	refresh()


## Places the burn where the orbit next reaches mean anomaly `target`.
func burn_at_apsis(target: float) -> void:
	var orbit: Dictionary = unit().get("orbit", {})
	if orbit.is_empty():
		return
	var tick: int = bridge.current_view["tick"]
	burn_tick = tick + OrbitPath.ticks_until(orbit, tick, target)
	refresh()


func plan() -> void:
	var command := pending_command()
	if command.is_empty():
		return
	var result: Dictionary = bridge.check(command)
	if not result["ok"]:
		_message.text = OrderText.reason(result["reason"], result["detail"])
		return
	bridge.submit(command)
	_message.text = ""
	set_components(0.0)


func clear() -> void:
	_message.text = ""
	set_components(0.0)


func cancel_burn(burn_id: int) -> void:
	bridge.submit(FlightLogic.cancel_command(unit_id(), burn_id))


func refresh() -> void:
	if not visible or unit().is_empty():
		return
	var view: Dictionary = bridge.current_view
	var shown := unit()
	var tick: int = view["tick"]
	if burn_tick <= tick:
		burn_tick = tick + 1
	_title.text = "Flight: %s" % shown["name"]
	_place.text = FlightLogic.place_text(view, unit_id())
	_when.set_value_no_signal(float(burn_tick - tick - 1) / bridge.ticks_per_second())
	var flying: bool = shown["dock"].is_empty()
	var on_orbit: bool = not shown.get("orbit", {}).is_empty()
	_peri_button.disabled = not on_orbit
	_apo_button.disabled = not on_orbit
	_sync_burns(shown, tick)
	var command := pending_command()
	preview = {} if command.is_empty() or not flying else bridge.check(command)
	_show_preview(view, flying)
	_plan_button.disabled = not preview.get("ok", false)
	_update_paths(view, command)


func _on_when_changed(seconds: float) -> void:
	burn_tick = bridge.current_view["tick"] + 1 + roundi(seconds * bridge.ticks_per_second())
	refresh()


func _show_preview(view: Dictionary, flying: bool) -> void:
	_cost.modulate = ClientTheme.OFF_WHITE
	if not flying:
		_cost.text = "Undock to plan a burn."
		_after.text = ""
	elif preview.is_empty():
		_cost.text = "Set prograde, normal or radial to plan a burn."
		_after.text = ""
	elif not preview["ok"]:
		_cost.text = OrderText.reason(preview["reason"], preview["detail"])
		_cost.modulate = ClientTheme.ORANGE
		_after.text = ""
	else:
		var lines := FlightLogic.preview_lines(preview["detail"], view, unit_id(), bridge.ticks_per_second())
		_cost.text = lines[0]
		_after.text = lines[1]


## Rows for the running burn and each planned one, each with a button to drop it.
func _sync_burns(shown: Dictionary, tick: int) -> void:
	var running: Dictionary = shown.get("burn", {})
	var planned: Array = shown.get("burns", [])
	var key := "%s|%s" % [str(running.get("id", 0)), str(planned.map(func(burn: Dictionary) -> int: return burn["id"]))]
	if key != _burns_key:
		_burns_key = key
		for child: Node in _burns_box.get_children():
			_burns_box.remove_child(child)
			child.queue_free()
		if not running.is_empty():
			_add_burn_row(running["id"], "Stop")
		for burn: Dictionary in planned:
			_add_burn_row(burn["id"], "Cancel")
	var rows := _burns_box.get_children()
	var index := 0
	if not running.is_empty():
		(rows[0].get_child(0) as Label).text = FlightLogic.running_text(running)
		index = 1
	for burn: Dictionary in planned:
		(rows[index].get_child(0) as Label).text = FlightLogic.planned_text(burn, tick, bridge.ticks_per_second())
		index += 1


func _add_burn_row(burn_id: int, action: String) -> void:
	var row := HBoxContainer.new()
	_burns_box.add_child(row)
	var label := _add_label(row)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_button(row, action).pressed.connect(cancel_burn.bind(burn_id))


## Works the path data out again only when the tick or the burn changes.
func _update_paths(view: Dictionary, command: Dictionary) -> void:
	var key := "%d:%d:%s:%s" % [unit_id(), view["tick"], str(command), str(preview.get("ok", false))]
	if key == _path_key:
		return
	_path_key = key
	current_path = _current_path(view)
	planned_path = []
	marker = PackedFloat64Array()
	if preview.get("ok", false):
		marker = _position_at(view, burn_tick)
		var detail: Dictionary = preview["detail"]
		var shown := unit()
		if not detail.get("orbit", {}).is_empty():
			var orbit: Dictionary = detail["orbit"]
			var parent: int = orbit.get("parent", shown["orbit"].get("parent", 0))
			planned_path = OrbitPath.loop(orbit, WorldPosition.of(view["bodies"][parent]), burn_tick, LOOP_POINTS)
		elif not marker.is_empty() and shown.get("orbit", {}).is_empty():
			planned_path = OrbitPath.drift(marker, detail["vel_um_s"], DRIFT_SECONDS, DRIFT_POINTS)
	_show_diagram(view)


## On an orbit, the panel's diagram shows both orbits to scale.
func _show_diagram(view: Dictionary) -> void:
	var shown := unit()
	var orbit: Dictionary = shown.get("orbit", {})
	_diagram.visible = not orbit.is_empty() and shown["dock"].is_empty()
	if not _diagram.visible:
		return
	var body: Dictionary = view["bodies"][orbit["parent"]]
	var ship_point := current_path[0] if not current_path.is_empty() else OrbitPath.shifted(WorldPosition.of(shown), [0, 0, 0])
	_diagram.show_orbits(orbit, WorldPosition.of(body), body["radius_mm"], body["name"],
		current_path, planned_path, ship_point, marker)


## The current orbit or drift from predict(), in world mm. A Sim without predict
## (before A11) draws nothing.
func _current_path(view: Dictionary) -> Array[PackedFloat64Array]:
	var points: Array[PackedFloat64Array] = []
	var shown := unit()
	if not bridge.sim.has_method("predict") or not shown["dock"].is_empty():
		return points
	var ticks := roundi(DRIFT_SECONDS * bridge.ticks_per_second())
	if not shown.get("orbit", {}).is_empty():
		ticks = ceili(OrbitPath.period_ticks(shown["orbit"]))
	elif FlightLogic.speed_of(shown.get("vel_um_s", [0, 0, 0])) == 0:
		return points
	var path: Dictionary = bridge.sim.predict(unit_id(), view["tick"], ticks, maxi(1, ticks / PREDICT_POINTS))
	var base := _place_world(view, path["place"])
	for point: Array in path["points"]:
		points.append(OrbitPath.shifted(point, base))
	return points


## Where the craft will be at a tick on its current path, in world mm.
func _position_at(view: Dictionary, tick: int) -> PackedFloat64Array:
	if bridge.sim.has_method("predict"):
		var path: Dictionary = bridge.sim.predict(unit_id(), tick, 0, 1)
		if not path["points"].is_empty():
			return OrbitPath.shifted(path["points"][0], _place_world(view, path["place"]))
	return OrbitPath.shifted(WorldPosition.of(unit()), [0, 0, 0])


func _place_world(view: Dictionary, place: Dictionary) -> Array:
	if place.has("orbit_parent"):
		return WorldPosition.of(view["bodies"][place["orbit_parent"]])
	var frame: Dictionary = view.get("frames", {}).get(place.get("frame", 0), {})
	return frame.get("world_mm", [0, 0, 0]) if not frame.is_empty() else [0, 0, 0]


func _process(_delta: float) -> void:
	if visible and bridge != null:
		_draw_paths()


## Lines are rebuilt every frame from the stored 64-bit points, relative to where
## each view is centred now.
func _draw_paths() -> void:
	var view: Dictionary = bridge.current_view
	if not view["units"].has(unit_id()) or _diagram.visible:
		_local_mesh.mesh.clear_surfaces()
		_map_mesh.mesh.clear_surfaces()
		return
	var focus_section := "units" if local_view.focus_kind == "unit" else "bodies"
	if not view[focus_section].has(local_view.focus_id):
		return
	var local_centre := WorldPosition.of(view[focus_section][local_view.focus_id])
	var map_centre := WorldPosition.of(view["units"][unit_id()])
	var local_marker := local_view.camera.distance_m * MARKER_LOCAL_FRACTION
	_draw_into(_local_mesh.mesh, local_centre, func(v: Vector3) -> Vector3: return FlightScreen.local_point(v), local_marker)
	_draw_into(_map_mesh.mesh, map_centre, func(v: Vector3) -> Vector3: return SystemMap.project(v), MARKER_MAP)


func _draw_into(mesh: ImmediateMesh, centre: Array, place: Callable, marker_size: float) -> void:
	mesh.clear_surfaces()
	_add_strip(mesh, current_path, centre, place, PATH_COLOUR)
	_add_strip(mesh, planned_path, centre, place, PLAN_COLOUR)
	if not marker.is_empty():
		var at: Vector3 = place.call(OrbitPath.relative_m(marker, centre))
		for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			mesh.surface_set_color(PLAN_COLOUR)
			mesh.surface_add_vertex(at - axis * marker_size)
			mesh.surface_set_color(PLAN_COLOUR)
			mesh.surface_add_vertex(at + axis * marker_size)
			mesh.surface_end()


func _add_strip(mesh: ImmediateMesh, points: Array[PackedFloat64Array], centre: Array, place: Callable, colour: Color) -> void:
	if points.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point: PackedFloat64Array in points:
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(place.call(OrbitPath.relative_m(point, centre)))
	mesh.surface_end()


## The local view draws far things nearer, as BodyNode does, so a path round a
## planet stays with the planet.
static func local_point(relative_m: Vector3) -> Vector3:
	return relative_m * FloatingOrigin.compression(relative_m.length())


func _path_mesh() -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	return instance


func _add_label(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _add_button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button


func _add_spin(parent: Control, low: float, high: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.custom_minimum_size = Vector2(110, 0)
	parent.add_child(spin)
	return spin
