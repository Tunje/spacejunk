class_name SimSystem
extends RefCounted
## Base class for everything the tick loop runs. Systems keep all saved state in ctx.state, so
## a system object holds nothing but derived caches. Registration order is the phase-list order
## within each phase. Every phase method defaults to doing nothing.


## A horizon with nothing to wait for (orbital_flight.md 11.22).
const NO_LIMIT := 1 << 60


## Command types this system handles.
func commands() -> PackedStringArray:
	return PackedStringArray()


## Command types of commands() that may be sent with unit 0, meaning the player rather than a unit,
## such as designing a variant (C12). The kernel skips its unit check for these alone.
func unitless_commands() -> PackedStringArray:
	return PackedStringArray()


## Coast (orbital_flight.md 11.22, A33). Asked between ticks, just after one was stepped, with
## ctx.flows still holding that tick's figures: how many of the coming ticks this system can skip in
## closed form, nothing discrete happening in any of them. 0 means the next must be stepped; then set
## ctx.coast_cap to say why. The default is 0, so a system without a closed form blocks coasting.
func horizon(_ctx: SimContext) -> int:
	return 0


## Advances this system's state over the `ticks` ticks after state["tick"], exactly as stepping
## them would, where horizon allowed it. state["tick"] is moved on by the kernel afterwards.
func coast(_ctx: SimContext, _ticks: int) -> void:
	pass


## Phase 1 validation, and the body of Sim.check. Must not change anything.
func validate(_ctx: SimContext, _command: Dictionary) -> Dictionary:
	return SimSystem.ok()


## Phase 1 effect of a command that passed validate.
func apply(_ctx: SimContext, _command: Dictionary) -> void:
	pass


## Phase 2.
func update_tasks(_ctx: SimContext) -> void:
	pass


## Phase 3.
func calculate_power(_ctx: SimContext) -> void:
	pass


## Phase 4.
func allocate(_ctx: SimContext) -> void:
	pass


## Phase 5. Record changes to inventories and deposits with ctx.record_delta.
func run(_ctx: SimContext) -> void:
	pass


## Phase 6, called once per delta in ascending owner ID.
func apply_delta(_ctx: SimContext, _payload: Dictionary) -> void:
	pass


## Phase 6, after all deltas. Battery charge and heat.
func update_stores(_ctx: SimContext) -> void:
	pass


## Phase 7.
func detect(_ctx: SimContext) -> void:
	pass


## Adds this system's entities to a view.
func fill_view(_ctx: SimContext, _view: Dictionary) -> void:
	pass


## Adds this system's matter, energy and heat figures to a ledger.
func fill_ledger(_ctx: SimContext, _ledger: Dictionary) -> void:
	pass


static func ok() -> Dictionary:
	return { "ok": true, "reason": "", "detail": {} }


## A failed validation. Pass event and data to emit something other than command_rejected.
static func reject(
	reason: String, detail: Dictionary = {}, event: String = "command_rejected", data: Dictionary = {}
) -> Dictionary:
	return { "ok": false, "reason": reason, "detail": detail, "event": event, "data": data }
