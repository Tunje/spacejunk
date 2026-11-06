extends GutTest
## The world the landing tests share (A15, A19): a Kerbin-gravity planet round a star, and the
## starter ship on a 700 km orbit with landing gear. Not a test file itself; test_landing.gd and
## tests/slow/test_landing_flights.gd extend it (A24).

const GM_STAR := 132_712_440_018_000_000
const GM_PLANET := 3_531_600_000
const AU_MM := 149_597_870_700_000
const RADIUS_MM := 600_000_000
const ONE := OrbitMath.ONE
const PROPELLANT_G := 12_000_000

const GEAR_MM_S := 6000
const STRONG_THRUST_N := 600_000

var sim: Sim
var keys := {}
## The hull this file fitted with landing gear in the cached data, to take it off afterwards.
var _geared: Dictionary = {}


## Landing needs gear (A19), and B15's legs aren't in data yet, so the starter hull carries some.
## It is patched in the cached definitions so a loaded save sees the same data hash.
func before_all() -> void:
	var hull: Dictionary = DataLoader.load_defs()["modules"]["starter_hull"]["capabilities"]
	if not hull.has(LowFlight.GEAR):
		hull[LowFlight.GEAR] = { "max_touchdown_mm_s": GEAR_MM_S }
		_geared = hull


func after_all() -> void:
	_geared.erase(LowFlight.GEAR)


func before_each() -> void:
	var defs := DataLoader.load_defs()
	sim = Sim.new()
	sim._setup(Sim._new_state("reference", 7, defs), defs)
	assert_eq(ScenarioBuilder.populate(sim._ctx, {
		"bodies": [
			{ "key": "star", "name": "Star", "kind": "star", "pos_mm": [0, 0, 0], "radius_mm": 696_000_000_000,
				"visual_seed": 1, "deposits": [], "gm": GM_STAR },
			{ "key": "planet", "name": "Planet", "kind": "planet", "radius_mm": RADIUS_MM, "visual_seed": 2,
				"deposits": [], "gm": GM_PLANET, "orbit": { "parent": "star", "a_mm": AU_MM },
				"planet": { "seed": 48213, "height_range_m": 8000 } },
		],
		"units": [
			{ "key": "ship", "template": "starter_ship", "name": "Ship", "pos_mm": [0, 0, 0],
				"inventory": [{ "item": "propellant", "grams": PROPELLANT_G }], "dock": null },
		],
	}, {}), "")
	sim._strict = true
	keys = {}
	for table: String in ["bodies", "units"]:
		for id: int in sim._state[table]:
			keys[sim._state[table][id]["name"]] = id
	_put_in_orbit(OrbitMath.make_orbit(GM_PLANET, 700_000_000, 0, [ONE, 0, 0], [0, 0, -ONE], 0, 0))


func _ship() -> Dictionary:
	return sim._state["units"][keys["Ship"]]


func _put_in_orbit(orbit: Dictionary) -> void:
	orbit["parent"] = keys["Planet"]
	_ship()["orbit"] = orbit
	_ship()["pos_mm"] = OrbitMath.position_at(orbit, sim.current_tick())
	sim._ctx.index.clear()


## The land and take_off commands need thrust over weight above 1 (A27), and the starter ship's
## 15 kN can't hold up 16 t at Kerbin's gravity. Tests of the commands fit it with a 600 kN thruster,
## in this sim's own defs, so the cached data and its hash are untouched.
func _strong_thruster() -> void:
	sim._ctx.defs = sim._ctx.defs.duplicate(true)
	var part: int = BurnSystem.thruster(sim._ctx, keys["Ship"])["part"]
	Units.module_of(sim._state, sim._ctx.defs, part)["capabilities"]["thruster"]["thrust_n"] = STRONG_THRUST_N


func _land(cell: int) -> Dictionary:
	return { "type": "land", "unit": keys["Ship"], "args": { "body": keys["Planet"], "cell": cell } }


func _until(event_type: String, limit: int) -> Dictionary:
	for i in limit:
		sim.step()
		for event in sim.take_events():
			if event["type"] == event_type:
				return event
	return {}


## Puts the ship in low flight a height above the ground of a cell, still.
func _hover(cell: int, height_mm: int) -> void:
	var ground := LandingSystem.cell_mm(sim._ctx, keys["Planet"], cell)
	var up := OrbitMath.unit(ground)
	var ship := _ship()
	ship["orbit"] = {}
	ship["low_flight"] = keys["Planet"]
	ship["pos_mm"] = [ground[0] + OrbitMath.smul_div(up[0], height_mm, ONE),
		ground[1] + OrbitMath.smul_div(up[1], height_mm, ONE), ground[2] + OrbitMath.smul_div(up[2], height_mm, ONE)]
	ship["vel_um_s"] = [0, 0, 0]
	ship["drift_carry"] = [0, 0, 0]


func _until_any(types: Array, limit: int) -> Dictionary:
	for i in limit:
		sim.step()
		for event in sim.take_events():
			if types.has(event["type"]):
				return event
	return {}


func _geared_off() -> void:
	var defs: Dictionary = sim._ctx.defs.duplicate(true)
	defs["modules"]["starter_hull"]["capabilities"].erase(LowFlight.GEAR)
	sim._ctx.defs = defs
	assert_eq(LowFlight.touchdown_mm_s(sim._ctx, keys["Ship"]), 0)
