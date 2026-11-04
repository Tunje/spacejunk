class_name FittingLogic extends RefCounted
## Works out what can be fitted and where. Whether a fit is allowed is always
## left to Sim.check, so the rules live in one place.

const ROOT_MOUNT := "mount"


## Uninstalled modules this unit can reach: its own stock and any docked host's.
static func stock(view: Dictionary, unit_id: int, modules: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var sources: Array[int] = [unit_id]
	var dock: Dictionary = view["units"][unit_id]["dock"]
	if not dock.is_empty():
		sources.append(dock["target_unit"])
	for source: int in sources:
		var inventory: Dictionary = view["units"][source]["inventory"]
		var ids: Array = inventory.keys()
		ids.sort()
		for id: String in ids:
			if modules.has(id) and inventory[id] >= modules[id]["mass_g"]:
				entries.append({
					"item": id, "from": source, "count": inventory[id] / modules[id]["mass_g"],
					"name": modules[id]["name"], "source": view["units"][source]["name"],
				})
	return entries


## Connectors with nothing on them, as { part, connector, type }. Dock
## connectors are for craft, and a part's mount faces its own parent.
static func free_slots(unit: Dictionary, modules: Dictionary) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for part: Dictionary in InspectText.flatten(unit["parts"]):
		var used: Array = part["children"].map(func(child: Dictionary) -> String: return child["parent_connector"])
		for connector: Dictionary in modules[part["def"]]["connectors"]:
			if connector["type"] != "dock" and connector["id"] != ROOT_MOUNT and not used.has(connector["id"]):
				slots.append({ "part": part["id"], "connector": connector["id"], "type": connector["type"], "size": connector["size"] })
	return slots


static func attach_command(unit_id: int, entry: Dictionary, slot: Dictionary) -> Dictionary:
	return { "type": "attach_part", "unit": unit_id, "args": {
		"item": entry["item"], "from": entry["from"], "parent_part": slot["part"],
		"parent_connector": slot["connector"], "part_connector": ROOT_MOUNT,
	} }


static func detach_command(unit_id: int, part: int, to: int) -> Dictionary:
	return { "type": "detach_part", "unit": unit_id, "args": { "part": part, "to": to } }


## Where removed parts go: the docked host if there is one, otherwise this unit.
static func detach_target(view: Dictionary, unit_id: int) -> int:
	var dock: Dictionary = view["units"][unit_id]["dock"]
	return dock["target_unit"] if not dock.is_empty() else unit_id


## One limit line, showing the projected figure when there is one.
static func limit_line(label: String, now: String, limit: String, projected: String) -> String:
	if projected.is_empty():
		return "%s: %s of %s" % [label, now, limit]
	return "%s: %s, then %s, of %s" % [label, now, projected, limit]


## C9 "Fit like this one": other craft built on the same root module, which are
## the only ones a fit can be copied from.
static func copy_sources(view: Dictionary, unit_id: int) -> Array[int]:
	var found: Array[int] = []
	var units: Dictionary = view["units"]
	if not units.has(unit_id):
		return found
	var ids: Array = units.keys()
	ids.sort()
	for id: int in ids:
		if id != unit_id and units[id]["parts"]["def"] == units[unit_id]["parts"]["def"]:
			found.append(id)
	return found


## Where copied parts come from: the docked host's stock first, then this craft's own.
static func copy_stock_units(view: Dictionary, unit_id: int) -> Array[int]:
	var found: Array[int] = []
	var dock: Dictionary = view["units"][unit_id]["dock"]
	if not dock.is_empty():
		found.append(dock["target_unit"])
	found.append(unit_id)
	return found


static func copy_command(unit_id: int, source: int, from: int) -> Dictionary:
	return { "type": "copy_fit", "unit": unit_id, "args": { "source": source, "from": from } }


## "Will fit 5, missing 1" from a copy_fit check's detail counts.
static func copy_summary(detail: Dictionary) -> String:
	var text := "Will fit %d" % detail.get("attach", 0)
	if detail.get("missing", 0) > 0:
		text += ", missing %d" % detail["missing"]
	if detail.get("refused", 0) > 0:
		text += ", %d won't fit" % detail["refused"]
	return text
