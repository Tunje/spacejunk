class_name CargoSystem
extends SimSystem
## Travel, docking and cargo transfer: the running half of networks.md sections 5 and 6. Steps set
## a unit's operation in phase 2, and this system carries it out.

const DELTA_BURN := "burn"
const DELTA_TRANSFER := "transfer"


## Ends a unit's open transfer, reporting what it moved.
static func close_transfer(ctx: SimContext, unit_id: int) -> void:
	var unit: Dictionary = ctx.state["units"][unit_id]
	if not unit.has(TransferStep.OPEN_KEY):
		return
	ctx.emit_event("transfer_done", unit_id, unit[TransferStep.OPEN_KEY])
	unit.erase(TransferStep.OPEN_KEY)


## Stops a unit where it is, with no refund (networks.md section 6).
static func halt(ctx: SimContext, id: int) -> void:
	ctx.state["units"][id]["route"] = {}
	_clear_followers(ctx, id)


static func release_ports(ctx: SimContext, op: Dictionary) -> void:
	if op.has("granted"):
		ctx.state["parts"][op["port"]].erase("claimed_by")
		ctx.state["parts"][op["target_port"]].erase("claimed_by")


func allocate(ctx: SimContext) -> void:
	for id: int in _sorted(ctx.state["units"]):
		var unit: Dictionary = ctx.state["units"][id]
		var op_type: String = unit["op"]["type"]
		if op_type == MoveStep.OP_MOVING and unit["op"]["start_tick"] == ctx.tick:
			_depart(ctx, id)
		elif op_type == MoveStep.OP_WAITING and unit["op"]["depart_tick"] <= ctx.tick \
				and not unit["op"].has("reason") and TaskSystem.is_running(ctx, unit):
			_depart(ctx, id)
		elif op_type == DockStep.OP_DOCKING and unit["task"] != 0 and not unit["op"].has("granted"):
			_grant_ports(ctx, id)


func run(ctx: SimContext) -> void:
	for id: int in _sorted(ctx.state["units"]):
		var unit: Dictionary = ctx.state["units"][id]
		if not unit["route"].is_empty():
			_advance(ctx, id)
		elif not unit["transfer"].is_empty() and ctx.tick >= unit["transfer"]["arrive_tick"]:
			_arrive(ctx, id)
		match unit["op"]["type"]:
			TransferStep.OP_LOADING, TransferStep.OP_UNLOADING:
				# A dock a job's feed holds this tick carries nothing else (C30).
				if TaskSystem.is_running(ctx, unit) and not unit["op"].has("reason") \
						and not JobSystem.dock_feeding(ctx, unit["op"]["from"], unit["op"]["to"]):
					_transfer(ctx, id)
			DockStep.OP_DOCKING:
				if ctx.tick >= unit["op"]["end_tick"] and unit["op"].has("granted"):
					_finish_dock(ctx, id)
			UndockStep.OP_UNDOCKING:
				if ctx.tick >= unit["op"]["end_tick"]:
					_finish_undock(ctx, id)
	_follow_hosts(ctx)


func apply_delta(ctx: SimContext, payload: Dictionary) -> void:
	var units: Dictionary = ctx.state["units"]
	if payload["kind"] == DELTA_BURN:
		Units.remove_stock(units[payload["unit"]]["inventory"], Travel.PROPELLANT, payload["grams"])
		var sink: Dictionary = ctx.state["sinks"].get_or_add(Travel.SINK, {})
		sink[Travel.PROPELLANT] = sink.get(Travel.PROPELLANT, 0) + payload["grams"]
	else:
		Units.remove_stock(units[payload["from"]]["inventory"], payload["item"], payload["grams"])
		Units.add_stock(units[payload["to"]]["inventory"], payload["item"], payload["grams"])


## Prices a trip from current state, claims the propellant and sets the route.
func _depart(ctx: SimContext, id: int) -> void:
	var unit: Dictionary = ctx.state["units"][id]
	var op: Dictionary = unit["op"]
	# A wait that has reached its window flies the plan it stored. Quoting afresh could move the
	# window by a tick through rounding, and the unit would never go. A wait that missed its window,
	# held by its task, quotes the next one: leaving late would miss the target.
	var quoted: Dictionary
	if op["type"] == MoveStep.OP_WAITING and op["depart_tick"] == ctx.tick and op.has("plan"):
		quoted = op["plan"].duplicate(true)
	else:
		quoted = Travel.quote(ctx, id, op["target"], MoveStep.prefer_of(op))
	if quoted.has("reason"):
		op["reason"] = quoted["reason"]
		return
	if quoted["kind"] == Transfer.KIND:
		if quoted["depart_tick"] > ctx.tick:
			MoveStep.wait_for(ctx, id, quoted["depart_tick"], quoted)
		else:
			_depart_transfer(ctx, id, quoted)
		return
	var cost_g: int = quoted["cost_g"]
	if cost_g > Reservations.free_stock(ctx, id, Travel.PROPELLANT):
		op["reason"] = MoveStep.REASON_NO_PROPELLANT
		return
	if cost_g > 0:
		Reservations.claim_stock(ctx, id, Travel.PROPELLANT, cost_g)
		ctx.record_delta(id, self, { "kind": DELTA_BURN, "unit": id, "grams": cost_g })
	op["end_tick"] = ctx.tick + quoted["ticks"] - 1
	unit["route"] = {
		"target": op["target"], "from_mm": quoted["from_mm"], "to_mm": quoted["to_mm"],
		"length_mm": quoted["length_mm"], "speed_mm_s": quoted["speed_mm_s"], "progress_mm": 0,
		"speed_remainder": 0, "eta_tick": op["end_tick"],
	}
	unit["at_target"] = 0
	unit["vel_um_s"] = [0, 0, 0]
	unit["drift_carry"] = [0, 0, 0]
	_clear_followers(ctx, id)


## Pays a transfer's whole price and puts the unit on the transfer orbit, on rails (A13). A missing
## load of propellant sends it back to waiting, held by `no_propellant`, and MoveStep.retry quotes the
## next window once the propellant is there: leaving late on an old window would miss the target.
func _depart_transfer(ctx: SimContext, id: int, quoted: Dictionary) -> void:
	var unit: Dictionary = ctx.state["units"][id]
	var target: int = quoted["target"]
	if quoted["cost_g"] > Reservations.free_stock(ctx, id, Travel.PROPELLANT):
		MoveStep.wait_for(ctx, id, ctx.tick)
		unit["op"]["reason"] = MoveStep.REASON_NO_PROPELLANT
		return
	# A unit that has dropped into low flight since it was quoted has no orbit to leave from (A39).
	if Transfer.unit_orbit(ctx, id).is_empty():
		unit["op"]["reason"] = Transfer.REASON_UNSUPPORTED
		return
	var legs: Array = quoted.get("legs", []).duplicate(true)
	var orbit: Dictionary = legs.pop_front()["orbit"] if not legs.is_empty() \
		else Transfer.departure_orbit(ctx, id, quoted, ctx.tick)
	if orbit.is_empty():
		unit["op"]["reason"] = Travel.REASON_OTHER_PLACE
		return
	if quoted["cost_g"] > 0:
		Reservations.claim_stock(ctx, id, Travel.PROPELLANT, quoted["cost_g"])
		ctx.record_delta(id, self, { "kind": DELTA_BURN, "unit": id, "grams": quoted["cost_g"] })
	unit["transfer"] = { "target": target, "depart_tick": ctx.tick, "arrive_tick": quoted["arrive_tick"],
		"legs": legs }
	unit["orbit"] = orbit
	unit["frame"] = 0
	unit["pos_mm"] = OrbitMath.position_at(orbit, ctx.tick)
	unit["vel_um_s"] = [0, 0, 0]
	unit["drift_carry"] = [0, 0, 0]
	unit["at_target"] = 0
	unit["op"] = { "type": MoveStep.OP_MOVING, "target": target, "part": 0, "start_tick": ctx.tick,
		"end_tick": quoted["arrive_tick"] }
	_clear_followers(ctx, id)
	# The window opened and the trip is paid and under way (A34), so a warping client can drop.
	ctx.emit_event("departed", id, { "target": target, "arrive_tick": quoted["arrive_tick"] })


## The end of a transfer: the unit takes the target's place, parked beside it.
func _arrive(ctx: SimContext, id: int) -> void:
	var unit: Dictionary = ctx.state["units"][id]
	var target: int = unit["transfer"]["target"]
	var place := RailSystem.target_place(ctx.state, target)
	if place > 0:
		var frame: Dictionary = ctx.state["frames"][place]
		var local: Array[int] = []
		for axis in 3:
			local.append(int(unit["pos_mm"][axis]) - int(frame["pos_mm"][axis]))
		var target_mm := _position_of(ctx, target)
		var total := IntMath.dist(local, target_mm)
		var stop: int = Travel._stop_distance(ctx, target)
		unit["frame"] = place
		unit["orbit"] = {}
		unit["pos_mm"] = Travel.stop_point(local, target_mm, total, stop) if total > stop else local
	else:
		var host: Dictionary = Transfer.target_orbit(ctx, target).duplicate(true)
		unit["orbit"] = host
		unit["pos_mm"] = OrbitMath.position_at(host, ctx.tick)
	unit["vel_um_s"] = [0, 0, 0]
	unit["drift_carry"] = [0, 0, 0]
	unit["at_target"] = target
	unit["transfer"] = {}
	ctx.emit_event("arrived", id, { "target": target })


static func _position_of(ctx: SimContext, target: int) -> Array:
	if ctx.state["bodies"].has(target):
		return ctx.state["bodies"][target]["pos_mm"]
	return ctx.state["units"][target]["pos_mm"]


## Nothing stays at a target that has left. Docked guests keep theirs and follow their host.
static func _clear_followers(ctx: SimContext, moved: int) -> void:
	var units: Dictionary = ctx.state["units"]
	var ids: Array = units.keys()
	ids.sort()
	for id: int in ids:
		if units[id]["at_target"] == moved and units[id]["dock"].is_empty():
			units[id]["at_target"] = 0


func _advance(ctx: SimContext, id: int) -> void:
	var unit: Dictionary = ctx.state["units"][id]
	var route: Dictionary = unit["route"]
	var remainder: int = route["speed_remainder"]
	var length_mm: int = route["length_mm"]
	route["progress_mm"] = mini(length_mm,
		route["progress_mm"] + Rate.amount(route["speed_mm_s"], remainder))
	route["speed_remainder"] = Rate.carry(route["speed_mm_s"], remainder)
	if route["progress_mm"] < length_mm:
		for axis in 3:
			unit["pos_mm"][axis] = Travel.along(route["from_mm"][axis], route["to_mm"][axis],
				route["progress_mm"], length_mm)
		return
	unit["pos_mm"] = route["to_mm"].duplicate()
	unit["at_target"] = route["target"]
	var target: int = route["target"]
	unit["route"] = {}
	ctx.emit_event("arrived", id, { "target": target })


func _grant_ports(ctx: SimContext, id: int) -> void:
	var op: Dictionary = ctx.state["units"][id]["op"]
	var parts: Dictionary = ctx.state["parts"]
	if Units.port_in_use(ctx.state, op["port"]) or Units.port_in_use(ctx.state, op["target_port"]):
		op["reason"] = DockStep.REASON_PORT_BUSY
		return
	parts[op["port"]]["claimed_by"] = id
	parts[op["target_port"]]["claimed_by"] = id
	op["granted"] = true


func _finish_dock(ctx: SimContext, id: int) -> void:
	var unit: Dictionary = ctx.state["units"][id]
	var op: Dictionary = unit["op"]
	release_ports(ctx, op)
	unit["dock"] = { "port": op["port"], "target_unit": op["target"], "target_port": op["target_port"] }
	unit["pos_mm"] = ctx.state["units"][op["target"]]["pos_mm"].duplicate()
	unit["at_target"] = op["target"]
	ctx.emit_event("docked", id, { "target": op["target"] })


func _finish_undock(ctx: SimContext, id: int) -> void:
	var unit: Dictionary = ctx.state["units"][id]
	var host: int = unit["dock"]["target_unit"]
	var host_mm: Array = ctx.state["units"][host]["pos_mm"]
	unit["dock"] = {}
	unit["pos_mm"] = [host_mm[0] + Travel.STANDOFF_MM, host_mm[1], host_mm[2]]
	unit["at_target"] = host
	ctx.emit_event("undocked", id, { "target": host })


func _transfer(ctx: SimContext, id: int) -> void:
	var unit: Dictionary = ctx.state["units"][id]
	var op: Dictionary = unit["op"]
	var task: Dictionary = ctx.state["tasks"][unit["task"]]
	var from: int = op["from"]
	var to: int = op["to"]
	var item: String = op["item"]
	var rate := _transfer_rate(ctx, from, to)
	var remainder: int = task.get("transfer_remainder", 0)
	var unit_mass_g: int = ctx.defs["items"][item].get("unit_mass_g", 0)
	# The credit is what a whole-unit item has built up towards its next unit. Only such an item
	# carries one (A42): a bulk item moves its grams as they come.
	var credit: int = task.get("credit_g", 0) if unit_mass_g != 0 else 0
	var grams: int = credit + Rate.amount(rate, remainder)
	task["transfer_remainder"] = Rate.carry(rate, remainder)
	var limit := mini(Reservations.free_stock(ctx, from, item), Reservations.free_space(ctx, to, item))
	if op["limit_g"] != 0:
		limit = mini(limit, op["limit_g"] - task.get("moved_g", 0))
	var moved := mini(grams, limit)
	if unit_mass_g != 0:
		moved -= moved % unit_mass_g
		task["credit_g"] = mini(grams - moved, unit_mass_g)
	if moved <= 0:
		return
	Reservations.claim_stock(ctx, from, item, moved)
	Reservations.claim_space(ctx, to, item, moved)
	ctx.record_delta(id, self, {
		"kind": DELTA_TRANSFER, "from": from, "to": to, "item": item, "grams": moved,
	})
	task["moved_g"] = task.get("moved_g", 0) + moved
	unit[TransferStep.OPEN_KEY]["grams"] += moved


## The smaller of the two docked ports' rates.
## The grams per second a dock between two docked units carries, for a job's feed (C30).
static func dock_rate(ctx: SimContext, a: int, b: int) -> int:
	return _transfer_rate(ctx, a, b)


static func _transfer_rate(ctx: SimContext, from: int, to: int) -> int:
	var units: Dictionary = ctx.state["units"]
	var dock: Dictionary = units[from]["dock"]
	if dock.get("target_unit", 0) != to:
		dock = units[to]["dock"]
	var near: Dictionary = Units.module_of(ctx.state, ctx.defs, dock["port"])["capabilities"]["port"]
	var far: Dictionary = Units.module_of(ctx.state, ctx.defs, dock["target_port"])["capabilities"]["port"]
	return mini(near["transfer_g_per_s"], far["transfer_g_per_s"])


## A docked unit takes its host's position, whenever the host moves.
## Coast (A33): docking or a cargo transfer is stepped. A flown transfer waits for its arrival, and
## a waiting one for its departure. A route coasts to the tick before its arrival (A37).
func horizon(ctx: SimContext) -> int:
	var skip := NO_LIMIT
	var now: int = ctx.state["tick"]
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		var unit: Dictionary = units[id]
		var op: Dictionary = unit["op"]
		if not unit["route"].is_empty():
			skip = mini(skip, route_horizon(unit["route"]))
		match op["type"]:
			TransferStep.OP_LOADING, TransferStep.OP_UNLOADING, DockStep.OP_DOCKING, UndockStep.OP_UNDOCKING:
				var bound := transfer_horizon(ctx, id) if op["type"] in [TransferStep.OP_LOADING,
					TransferStep.OP_UNLOADING] else dock_horizon(ctx, id)
				if bound <= 0:
					ctx.coast_cap = "docking_or_cargo"
					return 0
				skip = mini(skip, bound)
			MoveStep.OP_WAITING:
				skip = mini(skip, int(op["depart_tick"]) - now - 1)
			MoveStep.OP_MOVING:
				if int(op["start_tick"]) > now:
					skip = mini(skip, int(op["start_tick"]) - now - 1)
		if not unit["transfer"].is_empty():
			skip = mini(skip, int(unit["transfer"]["arrive_tick"]) - now - 1)
	if skip <= 0:
		ctx.coast_cap = "departure_or_arrival"
	return maxi(skip, 0)


## Coast (A33): docked units are where their hosts are. A route's progress over the ticks is the sum
## of its per-tick amounts, with its remainder carried, as _advance would add them one by one (A37).
## route_horizon keeps the coast short of arrival, so _advance's cap at the length never applies.
## A transfer moves the sum of its ticks the same way (C20); transfer_horizon keeps it short of
## every bound, so no tick of it would have been cut short. A dock or undock under way changes
## nothing until its end tick.
func coast(ctx: SimContext, ticks: int) -> void:
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		var unit: Dictionary = units[id]
		if unit["op"]["type"] in [TransferStep.OP_LOADING, TransferStep.OP_UNLOADING]:
			_coast_transfer(ctx, id, ticks)
		var route: Dictionary = unit["route"]
		if route.is_empty():
			continue
		var total: int = int(route["speed_mm_s"]) * ticks + int(route["speed_remainder"])
		route["progress_mm"] += total / Sim.TICKS_PER_SECOND
		route["speed_remainder"] = total % Sim.TICKS_PER_SECOND
		for axis in 3:
			unit["pos_mm"][axis] = Travel.along(route["from_mm"][axis], route["to_mm"][axis],
				route["progress_mm"], route["length_mm"])
	_follow_hosts(ctx)


## The ticks a dock or undock under way can skip before its end tick, which is stepped (C20). A dock
## whose ports are not yet granted steps, since granting is a change.
static func dock_horizon(ctx: SimContext, id: int) -> int:
	var op: Dictionary = ctx.state["units"][id]["op"]
	if op.has("reason") or (op["type"] == DockStep.OP_DOCKING and not op.has("granted")):
		return 0
	return maxi(0, int(op["end_tick"]) - int(ctx.state["tick"]) - 1)


## The most ticks a transfer can be summed over with every tick moving its full amount (C20): the
## sum stays strictly below the source's stock, the destination's room and the order's limit, so
## the tick that is cut short, and the one end_test ends it on, are stepped. Room falls by exactly
## the grams that go in, so the bound read now holds for the whole skip. It steps instead when it
## is held, when the item moves in whole units, when a credit is carried, or when another transfer
## or a miner shares either end, whose claims would share the bounds.
static func transfer_horizon(ctx: SimContext, id: int) -> int:
	var state := ctx.state
	var unit: Dictionary = state["units"][id]
	var op: Dictionary = unit["op"]
	if op.has("reason") or not TaskSystem.is_running(ctx, unit):
		return 0
	var item: String = op["item"]
	if ctx.defs["items"][item].get("unit_mass_g", 0) != 0:
		return 0
	var task: Dictionary = state["tasks"][unit["task"]]
	if task.get("credit_g", 0) != 0:
		return 0
	var from: int = op["from"]
	var to: int = op["to"]
	var ids: Array = state["units"].keys()
	ids.sort()
	for other: int in ids:
		if other == id:
			continue
		var other_op: Dictionary = state["units"][other]["op"]
		if other_op["type"] == MiningStep.OP_MINING and (other == from or other == to):
			return 0
		if other_op["type"] in [TransferStep.OP_LOADING, TransferStep.OP_UNLOADING] \
				and [from, to].any(func(end: int) -> bool: return end == other_op["from"] or end == other_op["to"]):
			return 0
	var room := mini(state["units"][from]["inventory"].get(item, 0),
		Units.grams_that_fit(state, ctx.defs, to, item))
	if op["limit_g"] != 0:
		room = mini(room, int(op["limit_g"]) - int(task.get("moved_g", 0)))
	var rate := _transfer_rate(ctx, from, to)
	if rate <= 0:
		return 0
	# The most ticks k with k * rate + remainder <= TICKS_PER_SECOND * room - 1.
	return maxi(0, (Sim.TICKS_PER_SECOND * room - 1 - int(task.get("transfer_remainder", 0))) / rate)


## A transfer's skipped ticks in one step, as _transfer and apply_delta would make them one by one.
func _coast_transfer(ctx: SimContext, id: int, ticks: int) -> void:
	var unit: Dictionary = ctx.state["units"][id]
	var op: Dictionary = unit["op"]
	var task: Dictionary = ctx.state["tasks"][unit["task"]]
	var total: int = ticks * _transfer_rate(ctx, op["from"], op["to"]) + int(task.get("transfer_remainder", 0))
	var grams := total / Sim.TICKS_PER_SECOND
	task["transfer_remainder"] = total % Sim.TICKS_PER_SECOND
	if grams <= 0:
		return
	var units: Dictionary = ctx.state["units"]
	Units.remove_stock(units[op["from"]]["inventory"], op["item"], grams)
	Units.add_stock(units[op["to"]]["inventory"], op["item"], grams)
	task["moved_g"] = task.get("moved_g", 0) + grams
	unit[TransferStep.OPEN_KEY]["grams"] += grams


## The most ticks a route can be summed over and still be short of its length, so the tick it
## arrives on, with its event, is stepped.
static func route_horizon(route: Dictionary) -> int:
	var speed: int = route["speed_mm_s"]
	if speed <= 0:
		return NO_LIMIT
	var room: int = (int(route["length_mm"]) - int(route["progress_mm"])) * Sim.TICKS_PER_SECOND \
		- int(route["speed_remainder"])
	if room <= 0:
		return 0
	# k ticks leave it short while k * speed < room.
	return (room + speed - 1) / speed - 1


func _follow_hosts(ctx: SimContext) -> void:
	var units: Dictionary = ctx.state["units"]
	for id: int in _sorted(units):
		var dock: Dictionary = units[id]["dock"]
		if not dock.is_empty() and units[id]["pos_mm"] != units[dock["target_unit"]]["pos_mm"]:
			units[id]["pos_mm"] = units[dock["target_unit"]]["pos_mm"].duplicate()


func _sorted(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids
