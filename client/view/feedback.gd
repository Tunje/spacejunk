class_name Feedback extends RefCounted
## Reads what a craft is doing from the view alone (contracts section 7), so the
## effects work unchanged on the real simulation. All of it is display only.

const BEAM_MINE := "mine"
const BEAM_SCAN := "scan"
const PULSING_OPS: Array[String] = ["scanning", "docking", "undocking", "mining"]


static func is_thrusting(unit: Dictionary) -> bool:
	return unit["op"]["type"] == "moving"


## The beam a unit is firing, as { part, body, kind }, or {} if none.
static func beam_of(unit: Dictionary, view: Dictionary) -> Dictionary:
	var op: Dictionary = unit["op"]
	match op["type"]:
		"mining":
			var deposit: Dictionary = view["deposits"].get(op["target"], {})
			if not deposit.is_empty():
				return { "part": op["part"], "body": deposit["body"], "kind": BEAM_MINE }
		"scanning":
			return { "part": op["part"], "body": op["target"], "kind": BEAM_SCAN }
	return {}


## The part an operation is using, which pulses while it runs. 0 means none.
static func working_part(unit: Dictionary) -> int:
	var op: Dictionary = unit["op"]
	if not PULSING_OPS.has(op["type"]):
		return 0
	if op["part"] != 0:
		return op["part"]
	return op.get("port", unit.get("dock", {}).get("port", 0))


## Loop heat from 0 to 1, for radiator glow.
static func heat_level(unit: Dictionary) -> float:
	var limit: int = unit["heat"]["limit_j"]
	if limit <= 0:
		return 0.0
	return clampf(float(unit["heat"]["stored_j"]) / limit, 0.0, 1.0)


static func has_capability(module: Dictionary, capability: String) -> bool:
	return module["capabilities"].has(capability)


## Every part ID in a tree.
static func part_ids(root: Dictionary) -> Array[int]:
	var ids: Array[int] = [root["id"]]
	for child: Dictionary in root["children"]:
		ids.append_array(Feedback.part_ids(child))
	return ids
