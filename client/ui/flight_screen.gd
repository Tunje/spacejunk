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
## Paths along an unchanged orbit or drift are worked out again at most this often.
## predict costs tens of milliseconds on an escape path, too much for every tick.
const PATH_REFRESH_MS := 250
## check(plan_burn) flies the burn tick by tick (A12), tens of ms for a long one.
## Typing waits this long after the last edit before asking; an unchanged burn on
## an unchanged craft is asked again at most every PATH_REFRESH_MS.
const EDIT_SETTLE_MS := 150
const TAKEOFF_KM := 100.0
## How far ahead a descent is followed: predict integrates one step per tick.
const DESCENT_TICKS := 3000
const DESCENT_STEP := 10
## predict near the ground costs a fraction of a millisecond per tick (A19), so a
## descent is worked out at most this often, and only as far as the last touchdown.
const DESCENT_REFRESH_MS := 1000
const DESCENT_MARGIN_TICKS := 100
## Paths take at most about 1 / COST_GAP of the time, however slow predict is.
const COST_GAP := 4
## The Lift off button's burn: straight up, now.
const LIFT_OFF_M_S := 30.0
const SAFE_COLOUR := Color(0.55, 0.85, 0.55)
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
var _path_ms := -PATH_REFRESH_MS
var _path_cost_ms := 0
var _preview_key := ""
var _preview_ms := -PATH_REFRESH_MS
## While typing, the earliest time the preview may be asked for.
var _settle_until := 0
## How many times check(plan_burn) has run, for tests.
var checks := 0
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
## Landing (A15): the chosen cell on the body being orbited, -1 for none.
var land_cell := -1
var picking := false
var land_preview: Dictionary = {}
var takeoff_preview: Dictionary = {}
var _land_key := ""
var _land_ms := -PATH_REFRESH_MS
var _passed_filter: Callable
var _land_box: VBoxContainer
var _land_title: Label
var _pick_button: Button
var _land_text: Label
## A36's cannot-return warning, by the Land button.
var _return_warning: Label
var _land_button: Button
var _takeoff_row: HBoxContainer
var _altitude: SpinBox
var _takeoff_button: Button
## Low flight and the ground (A19): where and how fast the craft meets the ground.
var contact: Dictionary = {}
var _contact_tick := 0
## How many descent predictions have run, for tests.
var predicts := 0
var touchdown := PackedFloat64Array()
var _descent_box: VBoxContainer
var _descent_text: Label
var _verdict: Label
var _lift_button: Button
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
		spin.value_changed.connect(func(_value: float) -> void: _edited())
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
	_build_landing(column)
	_build_descent(column)
	# Landing and descent sit under the place and diagram, seen first near a planet.
	column.move_child(_land_box, _diagram.get_index() + 1)
	column.move_child(_descent_box, _diagram.get_index() + 1)


## The hand-flown descent of A19: the predicted touchdown, the legs' limit and the
## verdict, plus a lift-off button on the ground.
func _build_descent(column: VBoxContainer) -> void:
	_descent_box = VBoxContainer.new()
	column.add_child(_descent_box)
	_descent_text = _add_label(_descent_box)
	_verdict = _add_label(_descent_box)
	_lift_button = _add_button(_descent_box, "Lift off")
	_lift_button.tooltip_text = "Fill in a burn straight up, now"
	_lift_button.pressed.connect(lift_off)
	_descent_box.visible = false


## Landing and takeoff, the atomic autopilot of A15: shown on an orbit round a
## planet, or on the ground.
func _build_landing(column: VBoxContainer) -> void:
	_land_box = VBoxContainer.new()
	column.add_child(_land_box)
	_land_box.add_child(HSeparator.new())
	_land_title = _add_label(_land_box)
	_land_title.modulate = ClientTheme.MID_GREY.lightened(0.35)
	var buttons := HBoxContainer.new()
	_land_box.add_child(buttons)
	_pick_button = _add_button(buttons, "Choose landing site")
	_pick_button.toggle_mode = true
	_pick_button.toggled.connect(set_picking)
	_land_button = _add_button(buttons, "Land")
	_land_button.pressed.connect(land)
	_takeoff_row = HBoxContainer.new()
	_land_box.add_child(_takeoff_row)
	var label := _add_label(_takeoff_row)
	label.text = "To orbit at (km)"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_altitude = _add_spin(_takeoff_row, 10.0, 5000.0, 10.0)
	_altitude.value = TAKEOFF_KM
	_altitude.value_changed.connect(func(_value: float) -> void: _edited())
	_takeoff_button = _add_button(_takeoff_row, "Take off")
	_takeoff_button.pressed.connect(take_off)
	_land_text = _add_label(_land_box)
	_return_warning = _add_label(_land_box)
	_return_warning.modulate = ClientTheme.ORANGE
	_return_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_return_warning.visible = false
	# The warning sits just above Land, so it's read before the choice.
	_land_box.move_child(_return_warning, _land_button.get_parent().get_index())


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
		set_picking(false)
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


## Sets the burn at once, as a button or the screenshot driver does, with no wait.
func set_components(prograde_m_s: float, normal_m_s := 0.0, radial_m_s := 0.0) -> void:
	for index in 3:
		_axes[index].set_value_no_signal([prograde_m_s, normal_m_s, radial_m_s][index])
	_settle_until = 0
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
	var wait := OrbitPath.ticks_until(orbit, tick, target)
	if wait > 0:
		burn_tick = tick + wait
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


## Above 8× nothing is flown by hand (orbital_flight.md 11.22): burns can still be
## planned, and the warp drops to 1× when one starts.
func _show_warp_limits() -> void:
	var warping := bridge.speed > WarpLogic.STEP_MAX
	var why := "Slow to %d× or less to fly by hand" % WarpLogic.STEP_MAX
	_now_button.disabled = warping
	_now_button.tooltip_text = why if warping else ""
	_lift_button.disabled = warping
	_lift_button.tooltip_text = why if warping else "Fill in a burn straight up, now"


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
	_show_warp_limits()
	_when.set_value_no_signal(float(burn_tick - tick - 1) / bridge.ticks_per_second())
	# A19: a burn on the ground is a lift-off, so only docking stops one.
	var flying: bool = shown["dock"].is_empty()
	var orbit: Dictionary = shown.get("orbit", {})
	_peri_button.disabled = orbit.is_empty() or OrbitPath.ticks_until(orbit, tick, 0.0) < 0
	_apo_button.disabled = orbit.is_empty() or OrbitPath.is_open(orbit)
	_sync_burns(shown, tick)
	var command := pending_command()
	_update_preview(shown, command, flying)
	_show_preview(view, flying)
	_plan_button.disabled = not preview.get("ok", false)
	_update_paths(view, command)
	_show_descent(view, shown)
	_show_landing(view, shown)


## Works the paths out again on the next refresh, whatever the wait, as tests need.
func force_paths() -> void:
	_path_ms = -PATH_REFRESH_MS
	_path_cost_ms = 0


func _on_when_changed(seconds: float) -> void:
	burn_tick = bridge.current_view["tick"] + 1 + roundi(seconds * bridge.ticks_per_second())
	_edited()


## A typed edit: refresh the rest now, and ask for the preview once typing settles.
func _edited() -> void:
	_settle_until = Time.get_ticks_msec() + EDIT_SETTLE_MS
	refresh()


## Asks check(plan_burn) only when the burn, or the craft it is planned on, has
## changed, or PATH_REFRESH_MS has passed; never while typing has not settled.
func _update_preview(shown: Dictionary, command: Dictionary, flying: bool) -> void:
	if command.is_empty() or not flying:
		preview = {}
		_preview_key = ""
		return
	var key := "%s|%s|%s|%d" % [str(command), str(shown.get("orbit", {})), str(shown.get("vel_um_s", [])),
		int(shown["inventory"].get("propellant", 0))]
	var now := Time.get_ticks_msec()
	if now < _settle_until:
		return
	if key == _preview_key and now - _preview_ms < PATH_REFRESH_MS:
		return
	_preview_key = key
	_preview_ms = now
	preview = bridge.check(command)
	checks += 1


func _show_preview(view: Dictionary, flying: bool) -> void:
	_cost.modulate = ClientTheme.OFF_WHITE
	if not flying:
		_cost.text = "Undock to plan a burn."
		_after.text = ""
	elif not preview.is_empty() and not preview["ok"] and preview["reason"] == "not_flying" \
			and not unit().get("landed", {}).is_empty():
		# A Sim before A19 refuses burns on the ground.
		_cost.text = "Take off to plan a burn."
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
		var busy := FlightLogic.busy_note(unit())
		if not busy.is_empty():
			_after.text += "\n" + busy


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
	var shown := unit()
	# Velocity changes every tick in low flight, so there it is left out: the time
	# limit below keeps a falling craft's path fresh without asking every tick. A
	# drift's velocity only changes with a burn, so a new drift is drawn at once.
	var low := int(shown.get("low_flight", 0))
	var drift := "" if low != 0 else str(shown.get("vel_um_s", []))
	var motion := "%s:%s" % [str(shown.get("orbit", {})), drift]
	# A running burn changes the orbit or drift every tick, so while it runs the
	# burn itself stands in for them and the time limit keeps the path fresh.
	if not shown.get("burn", {}).is_empty():
		motion = "burn %d" % int(shown["burn"]["id"])
	var key := "%d:%s:%d:%s:%s:%s:%s" % [unit_id(), motion, low,
		str(shown.get("landed", {})), str(shown["dock"]), str(command), str(preview.get("ok", false))]
	var now := Time.get_ticks_msec()
	var every := DESCENT_REFRESH_MS if int(shown.get("low_flight", 0)) != 0 else PATH_REFRESH_MS
	if key != _path_key:
		_contact_tick = 0
	elif now - _path_ms < maxi(every, _path_cost_ms * COST_GAP):
		return
	_path_key = key
	current_path = _current_path(view)
	planned_path = []
	marker = PackedFloat64Array()
	if preview.get("ok", false):
		marker = _position_at(view, burn_tick)
		var detail: Dictionary = preview["detail"]
		if not detail.get("orbit", {}).is_empty():
			var orbit: Dictionary = detail["orbit"]
			var parent: int = orbit.get("parent", shown["orbit"].get("parent", 0))
			var body: Dictionary = view["bodies"][parent]
			planned_path = OrbitPath.ahead(orbit, WorldPosition.of(body), burn_tick, LOOP_POINTS, float(body.get("soi_mm", 0)))
		elif not marker.is_empty() and shown.get("orbit", {}).is_empty():
			planned_path = OrbitPath.drift(marker, detail["vel_um_s"], DRIFT_SECONDS, DRIFT_POINTS)
	_show_diagram(view)
	# The wait runs from when the work ends, and grows with what it cost, so a slow
	# predict (tens of ms to a second near the ground) can't take over the frame.
	_path_ms = Time.get_ticks_msec()
	_path_cost_ms = _path_ms - now


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
	var orbit: Dictionary = shown.get("orbit", {})
	contact = {}
	touchdown = PackedFloat64Array()
	if int(shown.get("low_flight", 0)) != 0:
		return _descent_path(view)
	if not shown.get("landed", {}).is_empty():
		return points
	if OrbitPath.is_open(orbit):
		var soi: float = float(view["bodies"][orbit["parent"]].get("soi_mm", 0))
		ticks = OrbitPath.ticks_to_reach(orbit, view["tick"], soi)
	elif not orbit.is_empty():
		ticks = ceili(OrbitPath.period_ticks(orbit))
	elif FlightLogic.speed_of(shown.get("vel_um_s", [0, 0, 0])) == 0:
		return points
	var path: Dictionary = bridge.sim.predict(unit_id(), view["tick"], ticks, maxi(1, ticks / PREDICT_POINTS))
	if path.is_empty():
		return points
	var base := _place_world(view, path["place"])
	for point: Array in path["points"]:
		points.append(OrbitPath.shifted(point, base))
	return points


## In low flight, predict integrates the fall and says where it meets the ground.
func _descent_path(view: Dictionary) -> Array[PackedFloat64Array]:
	var points: Array[PackedFloat64Array] = []
	var ticks := DESCENT_TICKS
	if _contact_tick > view["tick"]:
		ticks = clampi(_contact_tick - view["tick"] + DESCENT_MARGIN_TICKS, DESCENT_STEP, DESCENT_TICKS)
	predicts += 1
	var path: Dictionary = bridge.sim.predict(unit_id(), view["tick"], ticks, DESCENT_STEP)
	if path.is_empty():
		return points
	var base := _place_world(view, path["place"])
	for point: Array in path["points"]:
		points.append(OrbitPath.shifted(point, base))
	contact = path.get("contact", {})
	_contact_tick = contact.get("tick", 0)
	if not contact.is_empty():
		var at: Dictionary = bridge.sim.predict(unit_id(), contact["tick"], 0, 1)
		if not at.get("points", []).is_empty():
			touchdown = OrbitPath.shifted(at["points"][0], base)
	return points


## Fills in a burn straight up, now: the ground's lift-off.
func lift_off() -> void:
	burn_now()
	set_components(0.0, 0.0, LIFT_OFF_M_S)


## The descent block: shown in low flight and on the ground.
func _show_descent(view: Dictionary, shown: Dictionary) -> void:
	var low := int(shown.get("low_flight", 0)) != 0
	var on_ground: bool = not shown.get("landed", {}).is_empty()
	_descent_box.visible = low or on_ground
	if not _descent_box.visible:
		return
	_lift_button.visible = on_ground
	var limit: int = shown.get("touchdown_mm_s", 0)
	_verdict.modulate = ClientTheme.OFF_WHITE
	if on_ground:
		_descent_text.text = "On the ground. A burn with radial out lifts off."
		_verdict.text = FlightLogic.legs_text(limit)
		return
	_descent_text.text = FlightLogic.contact_text(contact, view["tick"], bridge.ticks_per_second())
	_verdict.text = FlightLogic.verdict_text(contact, limit)
	if not contact.is_empty():
		_verdict.modulate = SAFE_COLOUR if FlightLogic.lands_safely(contact, limit) else ClientTheme.ORANGE


## Where the craft will be at a tick on its current path, in world mm.
func _position_at(view: Dictionary, tick: int) -> PackedFloat64Array:
	if bridge.sim.has_method("predict"):
		var path: Dictionary = bridge.sim.predict(unit_id(), tick, 0, 1)
		if not path.get("points", []).is_empty():
			return OrbitPath.shifted(path["points"][0], _place_world(view, path["place"]))
	return OrbitPath.shifted(WorldPosition.of(unit()), [0, 0, 0])


func _place_world(view: Dictionary, place: Dictionary) -> Array:
	if place.has("orbit_parent"):
		return WorldPosition.of(view["bodies"][place["orbit_parent"]])
	if place.has("low_flight"):
		return WorldPosition.of(view["bodies"][place["low_flight"]])
	var frame: Dictionary = view.get("frames", {}).get(place.get("frame", 0), {})
	return frame.get("world_mm", [0, 0, 0]) if not frame.is_empty() else [0, 0, 0]


func _process(_delta: float) -> void:
	if visible and bridge != null:
		if _settle_until > 0 and Time.get_ticks_msec() >= _settle_until:
			_settle_until = 0
			refresh()
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
	if not touchdown.is_empty():
		var safe := FlightLogic.lands_safely(contact, unit().get("touchdown_mm_s", 0))
		_add_cross(mesh, place.call(OrbitPath.relative_m(touchdown, centre)), marker_size, SAFE_COLOUR if safe else PLAN_COLOUR)
	if not marker.is_empty():
		var at: Vector3 = place.call(OrbitPath.relative_m(marker, centre))
		for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			mesh.surface_set_color(PLAN_COLOUR)
			mesh.surface_add_vertex(at - axis * marker_size)
			mesh.surface_set_color(PLAN_COLOUR)
			mesh.surface_add_vertex(at + axis * marker_size)
			mesh.surface_end()


func _add_cross(mesh: ImmediateMesh, at: Vector3, size: float, colour: Color) -> void:
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(at - axis * size)
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(at + axis * size)
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


# --- Landing and takeoff (A15) ---

## The body a land order would go to: the planet this craft orbits, or 0.
func land_body() -> int:
	var orbit: Dictionary = unit().get("orbit", {})
	if orbit.is_empty() or not unit()["dock"].is_empty():
		return 0
	var body: Dictionary = bridge.current_view["bodies"].get(orbit["parent"], {})
	return orbit["parent"] if body.get("kind", "") == "planet" else 0


## While on, a click on the orbited planet chooses the cell under it, and that
## planet's hex outlines show. Other clicks pass to the view as usual.
func set_picking(on: bool) -> void:
	if on == picking:
		return
	picking = on
	if _pick_button != null:
		_pick_button.set_pressed_no_signal(on)
	if on:
		_passed_filter = local_view.click_filter
		local_view.click_filter = _land_click
	else:
		local_view.click_filter = _passed_filter
	var body := _land_body_node()
	if body != null:
		body.set_outlines(on or BodyNode.show_outlines)
	refresh()


func _land_body_node() -> BodyNode:
	var body := land_body()
	return local_view.bodies.get(body) if body != 0 else null


func _land_click(hit: Dictionary) -> bool:
	var body := _land_body_node()
	if hit.get("kind", "") == "body" and body != null and hit["id"] == body.body_id:
		var cell := body.cell_at_point(hit["point"])
		if cell >= 0:
			choose_cell(cell)
		return false
	return not _passed_filter.is_valid() or _passed_filter.call(hit)


func choose_cell(cell: int) -> void:
	land_cell = cell
	var body := _land_body_node()
	if body != null:
		body.show_site(cell)
	_land_ms = -PATH_REFRESH_MS
	refresh()


func land_command() -> Dictionary:
	return { "type": "land", "unit": unit_id(), "args": { "body": land_body(), "cell": land_cell } }


func takeoff_command() -> Dictionary:
	return { "type": "take_off", "unit": unit_id(), "args": { "altitude_mm": roundi(_altitude.value * 1_000_000.0) } }


func land() -> void:
	var command := land_command()
	var result: Dictionary = bridge.check(command)
	if not result["ok"]:
		_land_text.text = OrderText.reason(result["reason"], result["detail"])
		return
	bridge.submit(command)
	set_picking(false)
	var body := _land_body_node()
	if body != null:
		body.show_site(-1)
	land_cell = -1


func take_off() -> void:
	var command := takeoff_command()
	var result: Dictionary = bridge.check(command)
	if not result["ok"]:
		_land_text.text = OrderText.reason(result["reason"], result["detail"])
		return
	bridge.submit(command)


func _show_landing(view: Dictionary, shown: Dictionary) -> void:
	var landed: Dictionary = shown.get("landed", {})
	var body := land_body()
	_land_box.visible = body != 0 or not landed.is_empty()
	if not _land_box.visible:
		if picking:
			set_picking(false)
		return
	var on_ground := not landed.is_empty()
	_return_warning.visible = false
	_pick_button.visible = not on_ground
	_land_button.visible = not on_ground
	_takeoff_row.visible = on_ground
	var now := Time.get_ticks_msec()
	var key := "%s|%d|%s|%s" % [str(landed), land_cell, str(shown.get("orbit", {})), str(_altitude.value)]
	var due := (key != _land_key or now - _land_ms >= PATH_REFRESH_MS) and now >= _settle_until
	if due:
		_land_key = key
		_land_ms = now
	if on_ground:
		_land_title.text = "On the ground"
		if due:
			takeoff_preview = bridge.check(takeoff_command())
		_land_text.text = FlightLogic.trip_cost_text(takeoff_preview, "Climb", bridge.ticks_per_second())
		_takeoff_button.disabled = not takeoff_preview.get("ok", false)
		return
	var planet_name := FlightLogic.body_name(view, body)
	_land_title.text = "Landing on %s" % planet_name
	if land_cell < 0:
		land_preview = {}
		if picking:
			_land_text.text = "Click a hex on %s." % planet_name
		else:
			_land_text.text = "Choose a landing site to see the cost."
		_land_button.disabled = true
		return
	if due:
		land_preview = bridge.check(land_command())
	_land_text.text = "Hex %d. %s" % [land_cell, FlightLogic.trip_cost_text(land_preview, "Descent", bridge.ticks_per_second())]
	_land_button.disabled = not land_preview.get("ok", false)
	_return_warning.text = FlightLogic.return_warning(land_preview, int(unit()["inventory"].get("propellant", 0)))
	_return_warning.visible = not _return_warning.text.is_empty()

