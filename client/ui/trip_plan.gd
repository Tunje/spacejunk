class_name TripPlan extends RefCounted
## The trip panel (D41): one order for a whole trip to a rock, sent as a one-shot cycle
## (set_cycle with laps 1, C25 and C27), which even a Basic Core flies. On a rock not
## yet scanned: fly there, scan and measure (C28's scan step). On a scanned rock, one
## per deposit: fly there, measure what is unpaid, and mine the amount box's kilograms
## (a full hold at 0). Hidden deposits stay hidden, so mining waits for the scan.

const KEY_SCAN := "Trip scan"
const KEY_MINE := "Trip mine %d"


## The trip orders for a selected rock, as OrderList orders ({ key, label, command }).
static func orders(view: Dictionary, science: Dictionary, modules: Dictionary, items: Dictionary,
		unit_id: int, body: int, amount_kg: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var shown: Dictionary = view["bodies"].get(body, {})
	if shown.get("kind", "") != OrderList.SHOWN_KIND_ASTEROID or not view["units"].has(unit_id):
		return found
	var unit: Dictionary = view["units"][unit_id]
	var lead: Array[Dictionary] = []
	if not unit.get("dock", {}).is_empty():
		lead.append({ "type": "undock", "args": {} })
	lead.append({ "type": "move_to", "args": { "target": body } })
	var studies: Array[Dictionary] = []
	for command: Dictionary in OrderList.measure_everything(view, science, unit_id, body):
		studies.append({ "type": command["type"], "args": command["args"].duplicate(true) })
	if not shown.get("scanned", false):
		found.append(TripPlan._order(KEY_SCAN, "Fly there, scan and measure", unit_id, lead + studies))
		return found
	var laser := OrderList._part_with_capability(unit["parts"], modules, "mine")
	if laser == 0:
		return found
	var deposits: Array = view["deposits"].keys()
	deposits.sort()
	for id: int in deposits:
		var deposit: Dictionary = view["deposits"][id]
		if deposit["body"] != body:
			continue
		var mine := { "deposit": id, "module": laser }
		if amount_kg > 0:
			mine["grams"] = amount_kg * 1000
		var how_much := "%d kg" % amount_kg if amount_kg > 0 else "a hold"
		var label := "Fly there, %smine %s of %s" % ["measure, " if not studies.is_empty() else "", how_much,
			items.get(deposit["item"], {}).get("name", deposit["item"])]
		found.append(TripPlan._order(KEY_MINE % id, label, unit_id, lead + studies + [{ "type": "start_mining", "args": mine }]))
	return found


static func _order(key: String, label: String, unit_id: int, steps: Array) -> Dictionary:
	return { "key": key, "label": label,
		"command": { "type": "set_cycle", "unit": unit_id, "args": { "steps": steps, "laps": 1 } } }


## Whether an order is a trip, so the panel can show it apart.
static func is_trip(order: Dictionary) -> bool:
	return order["key"] == KEY_SCAN or order["key"].begins_with("Trip mine ")
