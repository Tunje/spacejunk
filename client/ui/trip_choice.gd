class_name TripChoice extends RefCounted
## Fast or cheap (D40, from A43): where a trip can be flown two ways, quote() takes
## the cheaper and carries the other plan as `other`. The map shows both, and the
## Orders panel offers "Move to, faster" beside Move to. What each costs and when it
## arrives is the Sim's; this only words it and builds the order.

const FAST_KEY := "Move to faster"
## Where a plane change is burned (A41b's plane_change_at), for the trip line.
const PLANE_AT: Dictionary = {
	"start": "first, on the way out",
	"arrival": "joined to the arrival burn",
	"departure": "joined to the departure burn",
}


## "235 kg, arrives in 27 h 0 min", from a plan's cost and arrival.
static func plan_text(cost_g: int, arrive_tick: int, tick: int, ticks_per_second: int) -> String:
	return "%s, arrives in %s" % [OrderText.tonnes(cost_g),
		OrderText.duration(float(maxi(0, arrive_tick - tick)) / ticks_per_second)]


## True when the quote's other plan arrives sooner than the one it took.
static func has_faster(quote: Dictionary) -> bool:
	return quote.has("other") and not quote.has("reason") \
		and int(quote["other"]["arrive_tick"]) < int(quote["arrive_tick"])


## The map's second line: "Faster: 401 kg, arrives in 2 h 30 min", or "".
static func faster_line(quote: Dictionary, tick: int, ticks_per_second: int) -> String:
	if not TripChoice.has_faster(quote):
		return ""
	var other: Dictionary = quote["other"]
	return "Faster: %s" % TripChoice.plan_text(int(other["cost_g"]), int(other["arrive_tick"]), tick, ticks_per_second)


## ", with a 1.2 km/s plane change joined to the arrival burn", or "" in one plane.
static func plane_text(quote: Dictionary) -> String:
	var plane := int(quote.get("plane_change_dv_um_s", 0))
	if plane <= 0:
		return ""
	var where: String = PLANE_AT.get(quote.get("plane_change_at", ""), "")
	return ", including a %s plane change%s" % [FlightLogic.speed(plane), "" if where.is_empty() else " " + where]


## Relabels the first Move to with its cost and arrival, and adds "Move to, faster"
## after it when the quote has a faster plan. `orders` as OrderList.build gives them.
static func add_fast_option(orders: Array[Dictionary], quote: Dictionary, tick: int, ticks_per_second: int) -> void:
	if quote.is_empty() or quote.has("reason"):
		return
	for index in range(orders.size()):
		var order: Dictionary = orders[index]
		if order["command"]["type"] != "move_to" or int(order["command"]["args"]["target"]) != int(quote.get("target", -1)):
			continue
		if not TripChoice.has_faster(quote):
			return
		order["label"] = "Move to: %s" % TripChoice.plan_text(int(quote["cost_g"]), int(quote["arrive_tick"]), tick, ticks_per_second)
		var fast: Dictionary = order["command"].duplicate(true)
		fast["args"]["prefer"] = "fast"
		var other: Dictionary = quote["other"]
		orders.insert(index + 1, { "key": FAST_KEY, "command": fast,
			"label": "Move to, faster: %s" % TripChoice.plan_text(int(other["cost_g"]), int(other["arrive_tick"]), tick, ticks_per_second) })
		return
