class_name Research
extends RefCounted
## The kernel side of research (C12, contracts version 5): the science and research state, the
## per-game definitions overlay, the theories a scenario starts with, and the science ledger.
## C's ResearchDefs derives the entries; C's systems run measuring, labs and variant design.
##
## The overlay: a game reads the authored definitions plus everything research derives from them
## (the prototype and qualify items and recipes of every theory-unlocked module) and from the
## variants this game has designed. Nothing derived is saved or hashed: the data hash covers the
## authored definitions, and a loaded game rebuilds its variants from research.variants.

const PROTOTYPE := "prototype"
const QUALIFIED := "qualified"
## The random stream for idea discovery, so its draws never shift another stream's.
const RNG_STREAM := "research"
const DERIVED_TABLES: Array[String] = ["modules", "items", "recipes"]


static func empty_science() -> Dictionary:
	return { "points": 0, "earned": 0, "spent": 0, "paid": {} }


static func empty_research() -> Dictionary:
	return { "theories": {}, "designs": {}, "variants": {}, "discovered": {} }


## A game's definitions, from the authored ones and its state. Copy-on-write: the top level and the
## tables that gain entries are copied, and authored entries stay shared with DataLoader's cache, so
## nothing derived ever reaches the cache or another game.
static func overlay(authored: Dictionary, state: Dictionary) -> Dictionary:
	var defs := authored.duplicate()
	for table in DERIVED_TABLES:
		defs[table] = authored.get(table, {}).duplicate()
	if not authored.get("theories", {}).is_empty():
		var derived := ResearchDefs.derive_static(defs)
		defs["items"].merge(derived["items"], true)
		defs["recipes"].merge(derived["recipes"], true)
	var variants: Dictionary = state.get("research", {}).get("variants", {})
	var ids := variants.keys()
	ids.sort()
	for id: String in ids:
		var made := ResearchDefs.derive_variant(defs, variants[id]["base"], variants[id]["ideas"])
		if made.has("reason"):
			push_error("Variant %s no longer derives: %s" % [id, made["reason"]])
			continue
		_add_made(defs, made)
	return defs


## Designs a variant in this game: derives it, adds its module, items and recipes to the game's
## definitions, and records it in research as a prototype. Returns ResearchDefs.derive_variant's
## result, or { reason } with nothing changed.
static func add_variant(ctx: SimContext, base: String, ideas: Array) -> Dictionary:
	var made := ResearchDefs.derive_variant(ctx.defs, base, ideas)
	if made.has("reason"):
		return made
	_add_made(ctx.defs, made)
	var sorted := ideas.duplicate()
	sorted.sort()
	ctx.state["research"]["variants"][made["id"]] = { "base": base, "ideas": sorted, "complexity": made["complexity"] }
	ctx.state["research"]["designs"][made["id"]] = PROTOTYPE
	return made


static func _add_made(defs: Dictionary, made: Dictionary) -> void:
	defs["modules"][made["id"]] = made["module"]
	defs["items"].merge(made["items"], true)
	defs["recipes"].merge(made["recipes"], true)


## Proves a scenario's starting theories at tick 0, with every design they unlock qualified.
## Returns "" or what is wrong.
static func start_theories(ctx: SimContext, ids: Array) -> String:
	var theories: Dictionary = ctx.defs.get("theories", {})
	for id: Variant in ids:
		if typeof(id) != TYPE_STRING or not theories.has(id):
			return "research starts with an unknown theory %s" % str(id)
		ctx.state["research"]["theories"][id] = 0
		for design: String in theories[id].get("unlocks", []):
			ctx.state["research"]["designs"][design] = QUALIFIED
	return ""


## Science held by running lab jobs.
static func held_points(state: Dictionary) -> int:
	var held := 0
	var jobs: Dictionary = state["jobs"]
	var ids := jobs.keys()
	ids.sort()
	for id: int in ids:
		held += int(jobs[id].get("points_held", 0))
	return held


## The science ledger: every point earned is still spendable, held by a lab job, or spent.
static func science_violations(state: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	var science: Dictionary = state["science"]
	var held := held_points(state)
	if science["earned"] != science["points"] + science["spent"] + held:
		found.append("science: earned %d is not points %d + spent %d + held %d" % [
			science["earned"], science["points"], science["spent"], held])
	if science["points"] < 0 or science["spent"] < 0:
		found.append("science: points %d or spent %d below 0" % [science["points"], science["spent"]])
	return found


## The state's research and science maps hold the fields contracts section 7 gives them.
static func has_shape(state: Dictionary) -> bool:
	for pair: Array in [[state["science"], empty_science()], [state["research"], empty_research()]]:
		for key: String in pair[1]:
			if not pair[0].has(key) or typeof(pair[0][key]) != typeof(pair[1][key]):
				return false
	return true
