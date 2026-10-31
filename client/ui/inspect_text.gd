class_name InspectText extends RefCounted
## Turns view figures into the words and ratios the inspection panel shows.


static func watts(value: int) -> String:
	if value >= 1000000:
		return "%s MW" % String.num(value / 1000000.0, 1)
	if value >= 1000:
		return "%s kW" % String.num(value / 1000.0, 0)
	return "%d W" % value


static func joules(value: int) -> String:
	if value >= 1000000:
		return "%s MJ" % String.num(value / 1000000.0, 1)
	if value >= 1000:
		return "%s kJ" % String.num(value / 1000.0, 0)
	return "%d J" % value


static func ratio(part: int, whole: int) -> float:
	return clampf(float(part) / whole, 0.0, 1.0) if whole > 0 else 0.0


## How full a cargo class is, by whichever of mass or volume is tighter.
static func cargo_ratio(entry: Dictionary) -> float:
	var taken_g: int = entry["used_g"] + entry["reserved_g"]
	var taken_l: int = entry["used_l"] + entry["reserved_l"]
	return maxf(ratio(taken_g, entry["cap_g"]), ratio(taken_l, entry["cap_l"]))


static func cargo_line(entry: Dictionary) -> String:
	var line := "%s of %s, %d of %d L" % [
		OrderText.tonnes(entry["used_g"]), OrderText.tonnes(entry["cap_g"]), entry["used_l"], entry["cap_l"],
	]
	if entry["reserved_g"] > 0:
		line += ", %s reserved" % OrderText.tonnes(entry["reserved_g"])
	return line


static func inventory(stock: Dictionary, items: Dictionary) -> String:
	var ids: Array = stock.keys()
	ids.sort()
	var lines: PackedStringArray = []
	for id: String in ids:
		if stock[id] > 0:
			lines.append("%s %s" % [OrderText.tonnes(stock[id]), items.get(id, {}).get("name", id)])
	return ", ".join(lines)


static func status(unit: Dictionary, view: Dictionary) -> String:
	var op: Dictionary = unit["op"]
	var text := OrderText.operation(op["type"])
	if op["end_tick"] > op["start_tick"]:
		text += " %d%%" % int(ratio(view["tick"] - op["start_tick"], op["end_tick"] - op["start_tick"]) * 100.0)
	if not unit["dock"].is_empty():
		text += ", docked"
	var task: Dictionary = view["tasks"].get(unit["task"], {})
	if task.get("state", "") == "blocked":
		text += ". Blocked: %s" % OrderText.reason(task["reason"])
		if task["reason"] == "core_offline":
			var fault := CyclePlan.first_fault(unit)
			if not fault.is_empty():
				text += " (%s)" % OrderText.reason(fault["fault"])
	return text


static func core(unit: Dictionary) -> String:
	return "AI core: tier %d" % unit["core_tier"] if unit["core_tier"] > 0 else "No AI core"


static func part_line(part: Dictionary, module: Dictionary) -> String:
	var line: String = module["name"]
	match part["state"]:
		"fault":
			line += ": fault, %s" % OrderText.reason(part["fault"])
		"shed":
			line += ": shed"
		_:
			if part["draw_w"] > 0:
				line += ": %s" % InspectText.watts(part["draw_w"])
	return line


static func part_colour(part: Dictionary) -> Color:
	match part["state"]:
		"fault":
			return ClientTheme.ORANGE
		"shed":
			return ClientTheme.GOLD
	return Color.WHITE


static func flatten(part: Dictionary) -> Array[Dictionary]:
	var parts: Array[Dictionary] = [part]
	for child: Dictionary in part["children"]:
		parts.append_array(InspectText.flatten(child))
	return parts
