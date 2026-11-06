class_name ResearchRules
extends RefCounted
## The rules of research that jobs and the player's design commands follow (research.md sections 2
## to 4, contracts section 5): which design a recipe makes and the state it is in, what a lab may
## start and run, what a finished run proves or qualifies, idea discovery, and design_variant.
## The state lives in state.research and state.science; Research (kernel) owns its shape.

const DESIGN_VARIANT := "design_variant"
const STATE_LOCKED := "locked"
const KIND_NORMAL := "normal"
const KIND_PROTOTYPE := "prototype"
const KIND_QUALIFY := "qualify"
const KIND_THEORY := "theory"
const REASON_MALFORMED := "malformed_command"
const REASON_THEORY_LOCKED := "theory_locked"
const REASON_ALREADY_PROVEN := "already_proven"
const REASON_ALREADY_QUALIFIED := "already_qualified"
const REASON_DESIGN_UNQUALIFIED := "design_unqualified"
const REASON_IDEA_LOCKED := "idea_locked"
const REASON_VARIANT_EXISTS := "variant_exists"
const REASON_TIER_TOO_LOW := "tier_too_low"
const REASON_MISSING_EVIDENCE := "missing_evidence"
const REASON_MISSING_POINTS := "missing_points"
const DISCOVERY_PPM := 1_000_000


## What a recipe makes, as { kind, id }: a theory it proves, a design it qualifies, a design's
## prototype, a design's normal build, or { kind: "" } for anything else.
static func what_recipe_makes(ctx: SimContext, recipe: Dictionary) -> Dictionary:
	for output: Dictionary in recipe["outputs"]:
		if output.has("theory"):
			return { "kind": KIND_THEORY, "id": output["theory"] }
		if output.has("qualifies"):
			return { "kind": KIND_QUALIFY, "id": output["qualifies"] }
	if recipe["id"].begins_with(ResearchDefs.PROTOTYPE_PREFIX):
		return { "kind": KIND_PROTOTYPE, "id": recipe["id"].trim_prefix(ResearchDefs.PROTOTYPE_PREFIX) }
	for output: Dictionary in recipe["outputs"]:
		if output.has("item") and not output.has("sink") and ctx.defs["modules"].has(output["item"]):
			return { "kind": KIND_NORMAL, "id": output["item"] }
	return { "kind": "" }


## A design's state: prototype or qualified as research records it, otherwise locked if a theory
## unlocks it and qualified if none does.
static func design_state(ctx: SimContext, design: String) -> String:
	var designs: Dictionary = ctx.state["research"]["designs"]
	if designs.has(design):
		return designs[design]
	return STATE_LOCKED if unlocking_theory(ctx, design) != "" else Research.QUALIFIED


## The theory that unlocks a design, or "".
static func unlocking_theory(ctx: SimContext, design: String) -> String:
	var theories: Dictionary = ctx.defs.get("theories", {})
	var ids: Array = theories.keys()
	ids.sort()
	for id: String in ids:
		if theories[id]["unlocks"].has(design):
			return id
	return ""


static func is_proven(ctx: SimContext, theory: String) -> bool:
	return ctx.state["research"]["theories"].has(theory)


## Why start_job or queue_job may not take this recipe for this unit, or "".
static func start_refusal(ctx: SimContext, unit_id: int, recipe: Dictionary) -> String:
	var made := what_recipe_makes(ctx, recipe)
	match made["kind"]:
		KIND_THEORY:
			if is_proven(ctx, made["id"]):
				return REASON_ALREADY_PROVEN
			var theory: Dictionary = ctx.defs["theories"][made["id"]]
			for needed: String in theory.get("requires", []):
				if not is_proven(ctx, needed):
					return REASON_THEORY_LOCKED
			if _tier_too_low(ctx, unit_id, theory):
				return REASON_TIER_TOO_LOW
		KIND_QUALIFY:
			match design_state(ctx, made["id"]):
				STATE_LOCKED:
					return REASON_THEORY_LOCKED
				Research.QUALIFIED:
					return REASON_ALREADY_QUALIFIED
		KIND_PROTOTYPE:
			if design_state(ctx, made["id"]) == STATE_LOCKED:
				return REASON_THEORY_LOCKED
		KIND_NORMAL:
			match design_state(ctx, made["id"]):
				STATE_LOCKED:
					return REASON_THEORY_LOCKED
				Research.PROTOTYPE:
					return REASON_DESIGN_UNQUALIFIED
	return ""


## Why a job must leave the queue before its run, because another job proved or qualified what it
## would, or "".
static func done_reason(ctx: SimContext, recipe: Dictionary) -> String:
	var made := what_recipe_makes(ctx, recipe)
	if made["kind"] == KIND_THEORY and is_proven(ctx, made["id"]):
		return REASON_ALREADY_PROVEN
	if made["kind"] == KIND_QUALIFY and design_state(ctx, made["id"]) == Research.QUALIFIED:
		return REASON_ALREADY_QUALIFIED
	return ""


## Why a lab run cannot start now, or "": the era gate, the theory's evidence, then its points.
static func run_blocker(ctx: SimContext, unit_id: int, recipe: Dictionary) -> String:
	var made := what_recipe_makes(ctx, recipe)
	if made["kind"] == KIND_THEORY:
		var theory: Dictionary = ctx.defs["theories"][made["id"]]
		if _tier_too_low(ctx, unit_id, theory):
			return REASON_TIER_TOO_LOW
		if not Science.evidence_met(ctx.state, theory):
			return REASON_MISSING_EVIDENCE
	if ctx.state["science"]["points"] < recipe.get("points", 0):
		return REASON_MISSING_POINTS
	return ""


## Proving a theory of era N needs an assigned core of tier N - 1 or more on the lab's unit.
static func _tier_too_low(ctx: SimContext, unit_id: int, theory: Dictionary) -> bool:
	return TaskSystem.tier_of(ctx, ctx.state["units"][unit_id]) < theory["era"] - 1


## Phase 6: a finished theory run proves its theory and makes its unlocks prototypes.
static func prove(ctx: SimContext, unit_id: int, theory_id: String) -> void:
	var research: Dictionary = ctx.state["research"]
	if research["theories"].has(theory_id):
		return
	research["theories"][theory_id] = ctx.tick
	var unlocks: Array = ctx.defs["theories"][theory_id]["unlocks"].duplicate()
	unlocks.sort()
	for design: String in unlocks:
		if not research["designs"].has(design):
			research["designs"][design] = Research.PROTOTYPE
	ctx.emit_event("theory_proven", unit_id, { "theory": theory_id })


## Phase 6: a finished bench test qualifies its design, and a variant's may discover an idea.
static func qualify(ctx: SimContext, unit_id: int, design: String) -> void:
	ctx.state["research"]["designs"][design] = Research.QUALIFIED
	ctx.emit_event("design_qualified", unit_id, { "design": design })
	var variant: Dictionary = ctx.state["research"]["variants"].get(design, {})
	if not variant.is_empty():
		_discover(ctx, unit_id, variant["base"])


## One draw from the research stream, if the base has hidden ideas still undiscovered. The ideas are
## walked in ID order, each taking its discover_ppm of the draw's range, capped at the whole range.
static func _discover(ctx: SimContext, unit_id: int, base: String) -> void:
	var discovered: Dictionary = ctx.state["research"]["discovered"]
	var hidden: Array[Dictionary] = []
	for idea: Dictionary in ctx.defs["modules"][base].get("ideas", []):
		if idea.get("hidden", false) and not discovered.has(discovered_key(base, idea["id"])):
			hidden.append(idea)
	if hidden.is_empty():
		return
	hidden.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	var draw := ctx.rng.below(Research.RNG_STREAM, DISCOVERY_PPM)
	var reach := 0
	for idea: Dictionary in hidden:
		reach = mini(DISCOVERY_PPM, reach + idea.get("discover_ppm", 0))
		if draw < reach:
			discovered[discovered_key(base, idea["id"])] = ctx.tick
			ctx.emit_event("idea_discovered", unit_id, { "base": base, "idea": idea["id"] })
			return


static func discovered_key(base: String, idea: String) -> String:
	return "%s:%s" % [base, idea]


## design_variant { base, ideas }, sent with unit 0. The checks follow contracts section 5's order.
static func validate_variant(ctx: SimContext, command: Dictionary) -> Dictionary:
	var args: Dictionary = command["args"]
	if command["unit"] != 0 or typeof(args.get("base")) != TYPE_STRING or typeof(args.get("ideas")) != TYPE_ARRAY:
		return SimSystem.reject(REASON_MALFORMED)
	var made := ResearchDefs.derive_variant(ctx.defs, args["base"], args["ideas"])
	if made.get("reason", "") == ResearchDefs.REASON_MALFORMED:
		return SimSystem.reject(REASON_MALFORMED)
	if design_state(ctx, args["base"]) != Research.QUALIFIED:
		return SimSystem.reject(REASON_DESIGN_UNQUALIFIED)
	var known := {}
	for idea: Dictionary in ctx.defs["modules"][args["base"]].get("ideas", []):
		known[idea["id"]] = idea
	for idea_id: String in args["ideas"]:
		var idea: Dictionary = known[idea_id]
		if idea.has("theory") and not is_proven(ctx, idea["theory"]):
			return SimSystem.reject(REASON_IDEA_LOCKED)
		if idea.get("hidden", false) \
				and not ctx.state["research"]["discovered"].has(discovered_key(args["base"], idea_id)):
			return SimSystem.reject(REASON_IDEA_LOCKED)
	if ctx.state["research"]["variants"].has(ResearchDefs.variant_id(args["base"], args["ideas"])):
		return SimSystem.reject(REASON_VARIANT_EXISTS)
	if made.has("reason"):
		return SimSystem.reject(made["reason"])
	return SimSystem.ok()


static func apply_variant(ctx: SimContext, command: Dictionary) -> void:
	var made := Research.add_variant(ctx, command["args"]["base"], command["args"]["ideas"])
	var ideas: Array = command["args"]["ideas"].duplicate()
	ideas.sort()
	ctx.emit_event("variant_designed", 0, { "variant": made["id"], "base": command["args"]["base"], "ideas": ideas })


## The view's science and research sections (contracts section 7).
static func fill_view(ctx: SimContext, view: Dictionary) -> void:
	var science: Dictionary = ctx.state["science"]
	view["science"] = {
		"points": science["points"], "earned": science["earned"], "spent": science["spent"],
		"paid": science["paid"].duplicate(), "evidence": Science.evidence(ctx.state),
	}
	view["research"] = ctx.state["research"].duplicate(true)
