class_name SimBridge extends Node
## The client's only route to the simulation. Runs steps at the tick rate,
## keeps the last two views for interpolation, and hands events to the UI.
## The backend is held as RefCounted so StubSim and Sim swap in `start`.

signal view_updated
signal events_received(events: Array[Dictionary])
signal time_changed

const SPEEDS: Array[int] = [1, 2, 4, 8]
const MAX_STEPS_PER_FRAME := 8

var sim: RefCounted
var paused := false
var speed: int = SPEEDS[0]
var previous_view: Dictionary = {}
var current_view: Dictionary = {}

var _ticks_per_second := 10
var _ticks_owed := 0.0
var _last_span := 1


func _process(delta: float) -> void:
	advance(delta)


func start(new_sim: RefCounted) -> void:
	sim = new_sim
	_ticks_per_second = sim.TICKS_PER_SECOND
	_ticks_owed = 0.0
	_last_span = 1
	current_view = sim.view()
	previous_view = current_view
	view_updated.emit()


func set_paused(value: bool) -> void:
	if paused != value:
		paused = value
		time_changed.emit()


func set_speed(value: int) -> void:
	if speed != value and SPEEDS.has(value):
		speed = value
		time_changed.emit()


## Runs the steps owed for `delta` seconds of real time. Steps beyond the
## per-frame cap are dropped, so a slow frame cannot snowball.
func advance(delta: float) -> void:
	if sim == null or paused:
		return
	_ticks_owed += delta * _ticks_per_second * speed
	var steps := mini(floori(_ticks_owed), MAX_STEPS_PER_FRAME)
	if steps < 1:
		return
	_ticks_owed = minf(_ticks_owed - steps, 1.0)
	sim.step(steps)
	_last_span = steps
	previous_view = current_view
	current_view = sim.view()
	view_updated.emit()
	var events: Array[Dictionary] = sim.take_events()
	if not events.is_empty():
		events_received.emit(events)


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


func game_seconds() -> float:
	return float(current_view.get("tick", 0)) / _ticks_per_second
