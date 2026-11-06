class_name Science
extends RefCounted
## Science points (research.md section 1, contracts section 5): a finished measurement pays its
## kind's base points for the body's class, halved each time the same key has paid before. Points
## are integers in state.science and nothing here draws from an RNG.

const EVENT := "science_gained"
const SURVEY := "survey"
const CLASS_ASTEROID := "asteroid"
const CLASS_MOON := "moon"
const CLASS_PLANET := "planet"
## The one surface type every body has until planets.md's tables are in data.
const DEFAULT_SURFACE := "default"
## A shift past this is 0 for any base points that fit an int.
const MAX_SHIFT := 62


## The class a body's points are listed under: an asteroid, a moon (a body round a planet), a
## planet, or its kind for anything else.
static func body_class(state: Dictionary, body_id: int) -> String:
	var body: Dictionary = state["bodies"][body_id]
	match body["kind"]:
		"asteroid":
			return CLASS_ASTEROID
		"planet":
			var parent: int = body["orbit"].get("parent", 0)
			if parent != 0 and state["bodies"].has(parent) and state["bodies"][parent]["kind"] == "planet":
				return CLASS_MOON
			return CLASS_PLANET
	return body["kind"]


## The base points `kind` pays at `body_id`, or -1 if the kind does not apply there.
static func base_points(ctx: SimContext, kind: String, body_id: int) -> int:
	var definition: Dictionary = ctx.defs.get("science", {}).get(kind, {})
	return definition.get("points", {}).get(body_class(ctx.state, body_id), -1)


## The key whose payments diminish: kind and body, and the surface type for a surface sample.
static func key(kind: String, body_id: int) -> String:
	if kind == "surface":
		return "%s:%d:%s" % [kind, body_id, DEFAULT_SURFACE]
	return "%s:%d" % [kind, body_id]


## Pays a finished measurement and reports it, even at 0 points. Does nothing for a kind the
## definitions do not list, such as in a test world without science.
static func pay(ctx: SimContext, unit_id: int, kind: String, body_id: int) -> void:
	var base := base_points(ctx, kind, body_id)
	if base < 0:
		return
	var science: Dictionary = ctx.state["science"]
	var paid_key := key(kind, body_id)
	var times: int = science["paid"].get(paid_key, 0)
	var points := base >> times if times <= MAX_SHIFT else 0
	science["paid"][paid_key] = times + 1
	science["points"] += points
	science["earned"] += points
	ctx.emit_event(EVENT, unit_id, { "kind": kind, "target": body_id, "key": paid_key, "points": points })


## How many different keys of each kind have paid at least once.
static func evidence(state: Dictionary) -> Dictionary:
	var counts := {}
	var keys: Array = state["science"]["paid"].keys()
	keys.sort()
	for paid_key: String in keys:
		var kind := paid_key.get_slice(":", 0)
		counts[kind] = counts.get(kind, 0) + 1
	return counts


## True when every evidence entry of a theory is met: { kind, count } different keys paid.
static func evidence_met(state: Dictionary, theory: Dictionary) -> bool:
	var counts := evidence(state)
	for entry: Dictionary in theory.get("evidence", []):
		if counts.get(entry["kind"], 0) < entry["count"]:
			return false
	return true
