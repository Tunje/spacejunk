class_name SimBridge extends Node
## The client's only route to the simulation. Runs steps at the tick rate,
## keeps the last two views for interpolation, and hands events to the UI.
## The backend is held as RefCounted so StubSim and Sim swap in `start`.

signal view_updated
signal events_received(events: Array[Dictionary])
signal time_changed
## The defs grew (C12: a designed variant adds its module, item and recipes), so any
## screen holding a copy should read them again. Sent before that tick's events.
signal defs_changed

## Up to 8× it steps tick by tick; 50× batches steps; 1k× and 10k× coast (A33),
## jumping to the next tick where anything can happen (orbital_flight.md 11.22).
const SPEEDS: Array[int] = [1, 2, 4, 8, 50, 1000, 10000]
const MAX_STEPS_PER_FRAME := 8
## Real time a frame may spend advancing the Sim above 8×, so the screen keeps 60 fps.
const FRAME_BUDGET_MS := 8.0
## One batch's share of that, sized by the measured cost of a step.
const BATCH_SLICE_MS := 4.0
## A momentary cap is shown only once it has lasted this long.
const CAP_SHOWN_AFTER_S := 0.5

var sim: RefCounted
var paused := false
var speed: int = SPEEDS[0]
var previous_view: Dictionary = {}
var current_view: Dictionary = {}
## Keep warping when a job finishes, rather than dropping to 1×.
var warp_through_jobs := false
## Game speed actually reached, smoothed, and why it was held back ("" when not).
var achieved_speed := 1.0
var capped_by := ""

var _ticks_per_second := 10
var _ticks_owed := 0.0
var _last_span := 1
## Measured cost of a step, 0 until measured; it rises at once and eases down.
var _ms_per_tick := 0.0
var _cap_seconds := 0.0


func _process(delta: float) -> void:
	advance(delta)


func start(new_sim: RefCounted) -> void:
	sim = new_sim
	_ticks_per_second = sim.TICKS_PER_SECOND
	_ticks_owed = 0.0
	_last_span = 1
	current_view = sim.view()
	previous_view = current_view
	# A new backend, such as a loaded save, may hold designed variants of its own.
	defs_changed.emit()
	view_updated.emit()


func set_paused(value: bool) -> void:
	if paused != value:
		paused = value
		time_changed.emit()


func set_speed(value: int) -> void:
	if speed != value and SPEEDS.has(value):
		speed = value
		_ticks_owed = minf(_ticks_owed, 1.0)
		achieved_speed = float(value) if value <= WarpLogic.STEP_MAX else achieved_speed
		capped_by = ""
		time_changed.emit()


## The cap to show: a lasting one at once, a momentary one only if it holds.
func shown_cap() -> String:
	if capped_by.is_empty():
		return ""
	if WarpLogic.MOMENTARY.has(capped_by) and _cap_seconds < CAP_SHOWN_AFTER_S:
		return ""
	return capped_by


## Runs the ticks owed for `delta` seconds of real time, then takes one view.
## Ticks beyond what a frame can do are dropped, so a slow frame cannot snowball.
func advance(delta: float) -> void:
	if sim == null or paused:
		return
	_ticks_owed += delta * _ticks_per_second * speed
	var due := floori(_ticks_owed)
	if due < 1:
		return
	var events: Array[Dictionary] = []
	var cap := ""
	var advanced := 0
	if WarpLogic.mode(speed) == "step":
		advanced = mini(due, MAX_STEPS_PER_FRAME)
		sim.step(advanced)
		events = sim.take_events()
	else:
		var result := _warp(due, events)
		advanced = result["ticks"]
		cap = result["capped_by"]
	_ticks_owed = minf(_ticks_owed - advanced, 1.0)
	_last_span = maxi(advanced, 1)
	_note_speed(advanced, delta, cap)
	previous_view = current_view
	current_view = sim.view()
	if speed > WarpLogic.STEP_MAX and WarpLogic.needs_attention(events, warp_through_jobs):
		set_speed(SPEEDS[0])
		_ticks_owed = 0.0
	view_updated.emit()
	if events.any(func(event: Dictionary) -> bool: return event["type"] == "variant_designed"):
		defs_changed.emit()
	if not events.is_empty():
		events_received.emit(events)


## Above 8×: coasts (1k× and up, when the Sim can) or batches of steps, within the
## frame's budget, stopping after any call that brings an event needing attention.
## A capped coast hands the rest of the frame to batches; the next frame tries again.
func _warp(due: int, events: Array[Dictionary]) -> Dictionary:
	var started := Time.get_ticks_usec()
	var coasting := WarpLogic.mode(speed) == "coast" and sim.has_method("coast")
	var cap := "no_coast" if WarpLogic.mode(speed) == "coast" and not coasting else ""
	var advanced := 0
	while advanced < due:
		if (Time.get_ticks_usec() - started) / 1000.0 >= FRAME_BUDGET_MS:
			if cap.is_empty():
				cap = "busy_world"
			break
		if coasting:
			var result: Dictionary = sim.coast(due - advanced)
			advanced += int(result["ticks"])
			if result["capped_by"] != "":
				cap = result["capped_by"]
				coasting = false
		else:
			# Unmeasured, one tick first, so a slow world can't blow the frame before it's known.
			var per_batch := 1 if _ms_per_tick <= 0.0 else maxi(1, floori(BATCH_SLICE_MS / _ms_per_tick))
			var batch := mini(due - advanced, per_batch)
			var before := Time.get_ticks_usec()
			sim.step(batch)
			var measured := (Time.get_ticks_usec() - before) / 1000.0 / batch
			_ms_per_tick = measured if measured > _ms_per_tick else lerpf(_ms_per_tick, measured, 0.3)
			advanced += batch
		var got: Array[Dictionary] = sim.take_events()
		events.append_array(got)
		if WarpLogic.needs_attention(got, warp_through_jobs):
			break
	return { "ticks": advanced, "capped_by": cap }


func _note_speed(advanced: int, delta: float, cap: String) -> void:
	var reached := advanced / maxf(delta * _ticks_per_second, 0.000001)
	achieved_speed = float(speed) if speed <= WarpLogic.STEP_MAX else lerpf(achieved_speed, reached, 0.2)
	_cap_seconds = _cap_seconds + delta if cap == capped_by and not cap.is_empty() else 0.0
	capped_by = cap


## How far display time has moved from previous_view to current_view. The
## display runs one tick behind, so this stays continuous across step batches.
func interpolation_alpha() -> float:
	return clampf((_last_span - 1 + _ticks_owed) / _last_span, 0.0, 1.0)


func submit(command: Dictionary) -> int:
	return sim.submit(command)


func check(command: Dictionary) -> Dictionary:
	return sim.check(command)


func defs() -> Dictionary:
	return sim.defs()


func ticks_per_second() -> int:
	return _ticks_per_second


func game_seconds() -> float:
	return float(current_view.get("tick", 0)) / _ticks_per_second
