class_name SystemMap extends Node3D
## The 3D system map, centred on the commanded craft. Distance is logarithmic,
## so a nearby asteroid and the star fit one screen; rings show the real scale.
## It shares the local view's selection, so orders work the same from here.

const RADIUS_PER_DECADE := 6.0
const NEAR_DECADES := 2.0
const FAR_DECADE_FACTOR := 0.35
const KM_IN_M := 1000.0
const AU_KM := 149597870.7
## Distance rings (D39): decades close in, then 1-3-10 steps across to the planets,
## in AU once past three million km.
const RINGS_KM: Array[float] = [
	1.0, 10.0, 100.0, 300.0, 1000.0, 3000.0, 10000.0, 30000.0, 100000.0, 300000.0,
	1000000.0, 3000000.0, 0.1 * AU_KM, 0.3 * AU_KM, AU_KM, 3.0 * AU_KM,
]
const RING_SEGMENTS := 96
const RING_COLOUR := Color(0.2, 0.22, 0.27)
const ROUTE_SEGMENTS := 24
const CLICK_SLOP_PX := 5.0
## quote() may search for a window, so the selection's trip is asked at most this often.
const QUOTE_REFRESH_MS := 250

var bridge: SimBridge
var local_view: LocalView
var entries: Array[Dictionary] = []
## Frames (such as a rock cluster) by name, as { label, map_pos }: a small name at
## the frame's centre, not something to click.
var frame_labels: Array[Dictionary] = []
var eta_text := ""
## The System view (D37): the star at the centre and every orbit drawn, instead of
## distances round the commanded craft. Y or the map's button toggles it.
var system_view := false
## Orbit rings colour in the System view.
const ORBIT_COLOUR := Color(0.32, 0.36, 0.44)
var _press_position := Vector2.ZERO
var _pressed := false
var _orbiting := false
var _eta_key := ""
var _eta_ms := -QUOTE_REFRESH_MS

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
	if km >= 0.05 * AU_KM:
		return "%s AU" % String.num(km / AU_KM, 1).trim_suffix(".0")
	if km >= 1000000.0:
		return "%s million km" % String.num(km / 1000000.0, 0)
	return "%s km" % SystemMap.thousands(roundi(km))


## 300000 as "300,000".
static func thousands(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + grouped


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


func toggle_system() -> void:
	system_view = not system_view
	rings.mesh = _build_rings() if not system_view else ImmediateMesh.new()
	refresh(0.0)


func refresh(delta: float) -> void:
	if system_view:
		_refresh_system(delta)
		return
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
	frame_labels.clear()
	for id: int in after.get("frames", {}):
		var frame: Dictionary = after["frames"][id]
		if (frame.get("world_mm", []) as Array).size() != 3:
			continue
		var from_mm := WorldPosition.of(before.get("frames", {}).get(id, frame))
		var relative := FloatingOrigin.relative_m(from_mm, WorldPosition.of(frame), centre_before, centre_after, alpha)
		frame_labels.append({ "label": frame["name"], "map_pos": SystemMap.project(relative) })
	_draw_routes(after, centre_after)
	eta_text = _eta_for_selection(after)
	camera.update_view(delta)
	overlay.update_entries()


## The System view: positions and orbit rings from SystemLayout, no routes.
func _refresh_system(delta: float) -> void:
	var view: Dictionary = bridge.current_view
	var placed := SystemLayout.positions(view)
	entries.clear()
	# At this scale the rocks of a frame and other craft crowd their moon's name, so
	# the view lists the star, planets and moons and the craft in command; a frame
	# shows by its name.
	for kind: String in ["body", "unit"]:
		var table: Dictionary = view["bodies"] if kind == "body" else view["units"]
		for id: int in table:
			if kind == "body" and table[id]["kind"] == "asteroid":
				continue
			if kind == "unit" and id != local_view.commanded_unit:
				continue
			entries.append({
				"kind": kind, "id": id, "label": table[id]["name"], "map_pos": placed["%s:%d" % [kind, id]]["pos"],
				"selected": local_view.selected_kind == kind and local_view.selected_id == id,
			})
	frame_labels.clear()
	for id: int in view.get("frames", {}):
		frame_labels.append({ "label": view["frames"][id]["name"], "map_pos": placed["frame:%d" % id]["pos"] })
	var mesh: ImmediateMesh = rings.mesh
	mesh.clear_surfaces()
	for ring: Dictionary in SystemLayout.orbit_rings(view, placed):
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for index in range(RING_SEGMENTS + 1):
			var angle := TAU * index / RING_SEGMENTS
			mesh.surface_set_color(ORBIT_COLOUR)
			mesh.surface_add_vertex(ring["centre"] + (ring["p"] * cos(angle) + ring["q"] * sin(angle)) * ring["radius"])
		mesh.surface_end()
	(routes.mesh as ImmediateMesh).clear_surfaces()
	eta_text = _eta_for_selection(view)
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
		elif not unit.get("transfer", {}).is_empty() and not unit.get("orbit", {}).is_empty():
			_add_arc(mesh, SystemMap.transfer_arc(view, unit, ROUTE_SEGMENTS), centre, ClientTheme.ORANGE)
		elif unit["op"]["type"] == "waiting" and not unit["op"].get("plan", {}).get("legs", []).is_empty():
			_add_arc(mesh, SystemMap.plan_arc(view, unit["op"]["plan"], ROUTE_SEGMENTS), centre, ClientTheme.GOLD)
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


## An autopilot transfer (A13) rides its orbit on rails from now to arrival, so its
## arc comes straight from the orbit record, in 64-bit world mm.
## A trip across a sphere of influence (A18) is a chain of legs, each an orbit
## from its tick to the next leg's: the current orbit until the first leg still to
## come, then each in turn up to arrival.
static func transfer_arc(view: Dictionary, unit: Dictionary, segments: int) -> Array[PackedFloat64Array]:
	var transfer: Dictionary = unit["transfer"]
	var pieces: Array[Dictionary] = [{ "orbit": unit["orbit"], "from_tick": view["tick"] }]
	for leg: Dictionary in transfer.get("legs", []):
		pieces.append(leg)
	return SystemMap.chain_arc(view, pieces, transfer["arrive_tick"], segments)


## Before departure, the waiting op's plan (the trip quote() gives) as the same chain.
static func plan_arc(view: Dictionary, plan: Dictionary, segments: int) -> Array[PackedFloat64Array]:
	var pieces: Array[Dictionary] = []
	for leg: Dictionary in plan.get("legs", []):
		pieces.append(leg)
	return SystemMap.chain_arc(view, pieces, plan["arrive_tick"], segments)


## Points along a chain of { orbit, from_tick }, each piece up to the next piece's
## tick and the last up to `end_tick`, each placed by its own parent body.
static func chain_arc(view: Dictionary, pieces: Array[Dictionary], end_tick: int, segments: int) -> Array[PackedFloat64Array]:
	var points: Array[PackedFloat64Array] = []
	for index in pieces.size():
		var orbit: Dictionary = pieces[index]["orbit"]
		var from: int = maxi(pieces[index]["from_tick"], view["tick"])
		var to: int = pieces[index + 1]["from_tick"] if index + 1 < pieces.size() else end_tick
		if to <= from or not view["bodies"].has(orbit.get("parent", 0)):
			continue
		for step in segments + 1:
			var tick := lerpf(from, to, float(step) / segments)
			# The parent where it will be then: a moon moves a long way in a trip.
			var parent := OrbitPath.body_world_at(view, orbit["parent"], tick)
			points.append(OrbitPath.shifted(OrbitPath.position(orbit, tick), parent))
	return points


func _add_arc(mesh: ImmediateMesh, points: Array[PackedFloat64Array], centre: Array, colour: Color) -> void:
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point: PackedFloat64Array in points:
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(SystemMap.project(OrbitPath.relative_m(point, centre)))
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


## Travel time from the Sim, so the client never prices a trip itself: quote() where
## the Sim has it (A13), which gives a transfer's window, otherwise check().
func _eta_for_selection(view: Dictionary) -> String:
	if _selected_position(view).is_empty():
		return ""
	var under_way := SystemMap.trip_under_way(view, local_view.commanded_unit, local_view.selected_id,
		bridge.ticks_per_second())
	if under_way != "":
		return under_way
	if bridge.sim.has_method("quote"):
		var key := "%d:%d" % [local_view.commanded_unit, local_view.selected_id]
		var now := Time.get_ticks_msec()
		if key == _eta_key and now - _eta_ms < QUOTE_REFRESH_MS:
			return eta_text
		_eta_key = key
		_eta_ms = now
		return SystemMap.trip_text(bridge.sim.quote(local_view.commanded_unit, local_view.selected_id, view["tick"]),
			view["tick"], bridge.ticks_per_second())
	var result: Dictionary = bridge.check({
		"type": "move_to", "unit": local_view.commanded_unit, "args": { "target": local_view.selected_id },
	})
	if not result["ok"]:
		return ""
	return OrderText.duration(float(result["detail"]["ticks"]) / bridge.ticks_per_second())


## The trip already ordered to `target`, waiting for its window or flying, so the map
## doesn't quote a new one beside it; "" when there is none.
static func trip_under_way(view: Dictionary, unit_id: int, target: int, ticks_per_second: int) -> String:
	var unit: Dictionary = view["units"].get(unit_id, {})
	if unit.is_empty():
		return ""
	var tick: int = view["tick"]
	var plan: Dictionary = unit.get("op", {}).get("plan", {})
	if not plan.is_empty() and int(plan.get("target", 0)) == target:
		return "Waiting for the window: departs in %s, arrives in %s" % [
			OrderText.duration(float(maxi(0, int(plan["depart_tick"]) - tick)) / ticks_per_second),
			OrderText.duration(float(maxi(0, int(plan["arrive_tick"]) - tick)) / ticks_per_second)]
	var trip: Dictionary = unit.get("transfer", {})
	if not trip.is_empty() and int(trip.get("target", 0)) == target:
		return "On the way, arrives in %s" % OrderText.duration(float(maxi(0, int(trip["arrive_tick"]) - tick)) / ticks_per_second)
	return ""


## "12 min", or for a transfer "Departs in 40 min, 31 min trip". "" if refused.
static func trip_text(quote: Dictionary, tick: int, ticks_per_second: int) -> String:
	if quote.is_empty() or quote.has("reason"):
		return ""
	var trip := OrderText.duration(float(quote["ticks"]) / ticks_per_second)
	if quote.get("kind", "") != "transfer":
		return trip
	var wait: int = quote["depart_tick"] - tick
	# A41a: a trip between planes burns into the target's plane first, part of its delta-v.
	var plane := int(quote.get("plane_change_dv_um_s", 0))
	var plane_text := "" if plane <= 0 else ", including a %s plane change" % FlightLogic.speed(plane)
	if wait <= 0:
		return "%s trip%s" % [trip, plane_text]
	return "Departs in %s, %s trip%s" % [OrderText.duration(float(wait) / ticks_per_second), trip, plane_text]


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_Y:
		toggle_system()
		get_viewport().set_input_as_handled()
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
