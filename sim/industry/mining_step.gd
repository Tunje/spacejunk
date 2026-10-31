class_name MiningStep
extends TaskStep
## The `start_mining` order. It runs until the hold is full or the deposit is empty, and either one
## is a finished step, not a failure (autonomy.md section 7). Matter moves as phase 6 deltas.

const OP_MINING := "mining"
const CAPABILITY := "mine"
const REASON_UNKNOWN_DEPOSIT := "unknown_deposit"
const REASON_EXHAUSTED := "deposit_exhausted"
const REASON_CARGO_FULL := "cargo_full"
const REASON_TOO_HARD := "too_hard"
## Grams per deposit taken by lower unit IDs this tick. Lives in ctx.flows, so it is never saved.
const CLAIMS_FLOW := "deposit_claims"


func type() -> String:
	return "start_mining"


func validate(ctx: SimContext, unit_id: int, args: Dictionary) -> Dictionary:
	if typeof(args.get("deposit")) != TYPE_INT or typeof(args.get("module")) != TYPE_INT:
		return SimSystem.reject(TaskSystem.REASON_MALFORMED)
	var state := ctx.state
	var part_id: int = args["module"]
	if not _is_laser_on(ctx, unit_id, part_id):
		return SimSystem.reject(TaskSystem.REASON_MODULE_MISSING)
	if state["parts"][part_id]["fault"] != "":
		return SimSystem.reject(TaskSystem.REASON_MODULE_FAULT)
	var module := Units.module_of(state, ctx.defs, part_id)
	var unit: Dictionary = state["units"][unit_id]
	var tier: int = Units.module_of(state, ctx.defs, unit["core"])["capabilities"]["ai_core"]["tier"]
	if module["min_ai_tier"] > tier:
		return SimSystem.reject(TaskSystem.REASON_TIER_TOO_LOW)
	if not unit["dock"].is_empty():
		return SimSystem.reject(TaskSystem.REASON_DOCKED)
	var deposit_id: int = args["deposit"]
	var deposits: Dictionary = state["deposits"]
	if not deposits.has(deposit_id) or not deposits[deposit_id]["found"]:
		return SimSystem.reject(REASON_UNKNOWN_DEPOSIT)
	var deposit: Dictionary = deposits[deposit_id]
	if unit["at_target"] != deposit["body"]:
		return SimSystem.reject(TaskSystem.REASON_OUT_OF_RANGE)
	if deposit["remaining_g"] == 0:
		return SimSystem.reject(REASON_EXHAUSTED)
	if deposit["hardness"] > module["capabilities"][CAPABILITY]["hardness_max"]:
		return SimSystem.reject(REASON_TOO_HARD)
	return SimSystem.ok()


func begin(ctx: SimContext, unit_id: int, args: Dictionary) -> void:
	TaskStep.set_op(ctx, unit_id, OP_MINING, args["deposit"], args["module"], 0)
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	op["mine_remainder"] = 0
	op["mined_g"] = 0
	op["end_reason"] = ""


## Phase 5. Takes what the rate gives, clamped to the deposit and the hold. A shed laser does nothing.
func run(ctx: SimContext, unit_id: int, system: SimSystem) -> void:
	var state := ctx.state
	var op: Dictionary = state["units"][unit_id]["op"]
	var part_id: int = op["part"]
	if not Units.can_run(state["parts"][part_id]):
		return
	var rate: int = Units.module_of(state, ctx.defs, part_id)["capabilities"][CAPABILITY]["rate_g_per_s"]
	var remainder: int = op["mine_remainder"]
	var wanted := Rate.amount(rate, remainder)
	var deposit_id: int = op["target"]
	var deposit: Dictionary = state["deposits"][deposit_id]
	var claims: Dictionary = ctx.flows.get_or_add(CLAIMS_FLOW, {})
	var left: int = deposit["remaining_g"] - claims.get(deposit_id, 0)
	var grams: int = mini(wanted, mini(left, _room(ctx, unit_id, deposit["item"])))
	if grams == wanted:
		op["mine_remainder"] = Rate.carry(rate, remainder)
	if grams > 0:
		claims[deposit_id] = claims.get(deposit_id, 0) + grams
		ctx.record_delta(unit_id, system, {
			"step": type(), "unit": unit_id, "deposit": deposit_id, "grams": grams,
		})


func apply_delta(ctx: SimContext, payload: Dictionary) -> void:
	var grams: int = payload["grams"]
	var deposit: Dictionary = ctx.state["deposits"][payload["deposit"]]
	var unit: Dictionary = ctx.state["units"][payload["unit"]]
	deposit["remaining_g"] -= grams
	Units.add_stock(unit["inventory"], deposit["item"], grams)
	unit["op"]["mined_g"] += grams


## Phase 6, after deltas, so a store that fills exactly ends on that tick.
func end_test(ctx: SimContext, unit_id: int) -> bool:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	var deposit: Dictionary = ctx.state["deposits"][op["target"]]
	if deposit["remaining_g"] == 0:
		op["end_reason"] = REASON_EXHAUSTED
	elif _room(ctx, unit_id, deposit["item"]) == 0:
		op["end_reason"] = REASON_CARGO_FULL
	return op["end_reason"] != ""


func report_end(ctx: SimContext, unit_id: int, reason: String) -> void:
	var op: Dictionary = ctx.state["units"][unit_id]["op"]
	ctx.emit_event("mining_stopped", unit_id, {
		"deposit": op["target"], "grams": op["mined_g"],
		"reason": reason if reason != "" else op["end_reason"],
	})


func _is_laser_on(ctx: SimContext, unit_id: int, part_id: int) -> bool:
	var parts: Dictionary = ctx.state["parts"]
	if not parts.has(part_id) or parts[part_id]["unit"] != unit_id:
		return false
	return Units.module_of(ctx.state, ctx.defs, part_id)["capabilities"].has(CAPABILITY)


## Grams of an item that still fit, by networks.md section 5.
func _room(ctx: SimContext, unit_id: int, item: String) -> int:
	var item_def: Dictionary = ctx.defs["items"][item]
	var entry: Dictionary = Units.cargo(ctx.state, ctx.defs, unit_id).get(item_def["cargo_class"], {})
	if entry.is_empty():
		return 0
	var density: int = item_def["density_g_l"]
	var held: int = ctx.state["units"][unit_id]["inventory"].get(item, 0)
	var free_l: int = entry["cap_l"] - entry["used_l"] - entry["reserved_l"]
	var by_mass: int = entry["cap_g"] - entry["used_g"] - entry["reserved_g"]
	var by_volume: int = IntMath.mul_div(maxi(0, free_l + Units.litres(held, density)), density, 1) - held
	return maxi(0, mini(by_mass, by_volume))
