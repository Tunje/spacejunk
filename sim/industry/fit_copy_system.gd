class_name FitCopySystem
extends SimSystem
## copy_fit: fits this unit like another unit with the same root module, using parts from this unit
## or a unit docked to it. Every install is an ordinary attach_part, validated and applied by
## FittingSystem itself, so no fitting rule is bypassed. Like attach_part, it is instant in phase 1.
## One fit_copied event reports what was fitted, what stock is missing and what was refused.

const COPY := "copy_fit"
const EVENT := "fit_copied"
const REASON_MALFORMED := "malformed_command"
const REASON_UNKNOWN_UNIT := "unknown_unit"
const REASON_INVALID_TARGET := "invalid_target"
const REASON_NOT_DOCKED := "not_docked"
const REASON_FIT_MISMATCH := "fit_mismatch"
const REASON_PARENT_NOT_FITTED := "parent_not_fitted"
const REASON_MISSING_ITEM := "missing_inputs"

var _fitter := FittingSystem.new()


func commands() -> PackedStringArray:
	return PackedStringArray([COPY])


## Checks the command, then dry-runs the copy on a throwaway state for check's counts.
func validate(ctx: SimContext, command: Dictionary) -> Dictionary:
	var args: Dictionary = command["args"]
	if typeof(args.get("source")) != TYPE_INT or typeof(args.get("from")) != TYPE_INT:
		return SimSystem.reject(REASON_MALFORMED)
	var units: Dictionary = ctx.state["units"]
	var unit: int = command["unit"]
	var source: int = args["source"]
	var from: int = args["from"]
	if not units.has(source) or not units.has(from):
		return SimSystem.reject(REASON_UNKNOWN_UNIT)
	if source == unit:
		return SimSystem.reject(REASON_INVALID_TARGET)
	if from != unit and not Units.are_docked(ctx.state, unit, from):
		return SimSystem.reject(REASON_NOT_DOCKED)
	var parts: Dictionary = ctx.state["parts"]
	if parts[units[source]["root"]]["def"] != parts[units[unit]["root"]]["def"]:
		return SimSystem.reject(REASON_FIT_MISMATCH)
	var trial := SimContext.new(ctx.state.duplicate(true), ctx.defs)
	trial.tick = ctx.tick
	var report := _copy(trial, command)
	var missing := 0
	for item: String in report["missing"]:
		missing += report["missing"][item]
	var result := SimSystem.ok()
	result["detail"] = {
		"attach": report["attached"].size(), "missing": missing, "refused": report["refused"].size(),
	}
	return result


func apply(ctx: SimContext, command: Dictionary) -> void:
	var report := _copy(ctx, command)
	report["source"] = command["args"]["source"]
	ctx.emit_event(EVENT, command["unit"], report)


## Fits the source's parts in ascending part ID, which puts every parent before its children and
## repeats the order they were fitted in. Refused parts are retried in further passes until a pass
## fits nothing, for a source that was refitted out of ID order.
func _copy(ctx: SimContext, command: Dictionary) -> Dictionary:
	var state := ctx.state
	var parts: Dictionary = state["parts"]
	var unit: int = command["unit"]
	var source: int = command["args"]["source"]
	var from: int = command["args"]["from"]
	var source_root: int = state["units"][source]["root"]
	var mapped := { source_root: state["units"][unit]["root"] }
	var pending := Units.sorted_part_ids(state, source)
	pending.erase(source_root)
	var reasons := {}
	var attached: Array[int] = []
	var progress := true
	while progress and not pending.is_empty():
		progress = false
		var left: Array[int] = []
		for source_part in pending:
			var part: Dictionary = parts[source_part]
			if not mapped.has(part["parent"]):
				reasons[source_part] = REASON_PARENT_NOT_FITTED
				left.append(source_part)
				continue
			var parent: int = mapped[part["parent"]]
			var present := Units.child_at(state, parent, part["parent_connector"])
			if present != 0 and parts[present]["def"] == part["def"] \
					and parts[present]["connector"] == part["connector"]:
				mapped[source_part] = present
				progress = true
				continue
			var attach := {
				"id": command.get("id", 0), "tick": command.get("tick", 0), "type": FittingSystem.ATTACH, "unit": unit,
				"args": {
					"item": part["def"], "from": from, "parent_part": parent,
					"parent_connector": part["parent_connector"], "part_connector": part["connector"],
				},
			}
			var result := _fitter.validate(ctx, attach)
			if not result["ok"]:
				reasons[source_part] = result["reason"]
				left.append(source_part)
				continue
			var id: int = state["next_entity_id"]
			_fitter.apply(ctx, attach)
			mapped[source_part] = id
			attached.append(id)
			progress = true
		pending = left
	return { "attached": attached, "missing": _missing(ctx, from, pending), "refused": _refused(ctx, pending, reasons) }


## Whole parts still needed for the unfitted parts, beyond what `from` holds.
func _missing(ctx: SimContext, from: int, pending: Array[int]) -> Dictionary:
	var needed := {}
	for source_part in pending:
		var item: String = ctx.state["parts"][source_part]["def"]
		needed[item] = needed.get(item, 0) + 1
	var inventory: Dictionary = ctx.state["units"][from]["inventory"]
	var missing := {}
	var items: Array = needed.keys()
	items.sort()
	for item: String in items:
		var held_g: int = inventory.get(item, 0)
		var mass_g: int = ctx.defs["modules"][item]["mass_g"]
		var held: int = held_g / mass_g
		if needed[item] > held:
			missing[item] = needed[item] - held
	return missing


func _refused(ctx: SimContext, pending: Array[int], reasons: Dictionary) -> Array[Dictionary]:
	var refused: Array[Dictionary] = []
	for source_part in pending:
		refused.append({
			"source_part": source_part, "item": ctx.state["parts"][source_part]["def"],
			"reason": reasons[source_part],
		})
	return refused
