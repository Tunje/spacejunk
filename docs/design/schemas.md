# Data Schemas

Status: approved by the Lead (task B3). Changes go through the Lead.

This defines every file in `data/`. It expands section 10 of [contracts.md](contracts.md), which stays the authority. A3 builds the loader from this page, B4 builds the validator, and B5 authors the data. The rules for what balances are in section 3 of [accounting.md](accounting.md), and slice IDs are in section 7 of [spec.md](spec.md).

All numbers in the examples are illustrative. B5 sets the real ones.

## 1. Files

| File | Holds |
| ---- | ----- |
| `data/items.json` | Items other than modules |
| `data/modules.json` | Modules |
| `data/recipes.json` | Recipes |
| `data/deposits.json` | Deposit definitions |
| `data/templates.json` | Unit templates |
| `data/sinks.json` | Declared sinks |
| `data/scenarios/<id>.json` | One scenario per file (section 14) |

Every file has the same envelope, with entries sorted by `id` so diffs stay small:

```json
{ "schema_version": 1, "entries": [] }
```

## 2. Rules for all files

- Every field is required unless marked optional. Unknown fields are errors, so a typo cannot pass silently. `visual` is the one exception.
- IDs match `^[a-z][a-z0-9_]*$`.
- Items and modules share one namespace, and recipes, deposits, unit templates and sinks each have their own.
- Fields marked "whole" reject a fractional value.
- Every `density_kg_m3` is a positive whole number, because the kernel divides grams by it and 1 kg/m3 equals 1 g/L.

### Conversion to sim units

The loader applies these by field name, and `defs()` returns the converted names. Values must convert exactly (contracts section 1).

| Data field ends in | Sim field ends in | Factor |
| ------------------ | ----------------- | ------ |
| `_kg` | `_g` | 1000 |
| `_kw` | `_w` | 1000 |
| `_kj` | `_j` | 1000 |
| `_m3` | `_l` | 1000 |
| `_kg_per_s` | `_g_per_s` | 1000 |
| `_m_s` | `_mm_s` | 1000 |
| `_kn` | `_n` | 1000 |
| `seconds` | `ticks` | `TICKS_PER_SECOND` |
| `density_kg_m3` | `density_g_l` | 1 |
| `gm_km3_s2` | `gm`, in 1000 m³/s² | 10^6 |
| `_mm`, `_ppm`, `_mdeg` | Unchanged | 1 |

A whole number converts by integer multiplication, so a value such as the star's GM stays exact beyond 2^53 once multiplied.

`defs()` returns `{ modules, items, recipes, templates, sinks }`, each keyed by ID (contracts section 3). Deposit definitions are not in it. They are read only at scenario load, and clients must learn deposits through scanning.

## 3. Items

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `id` | string | Item ID |
| `name` | string | Display name |
| `stage` | whole, 2 to 5 | Economy stage (spec section 2) |
| `cargo_class` | `ore`, `goods` or `propellant` | |
| `density_kg_m3` | whole | Sets stack volume |
| `unit_mass_kg` | number, optional | Present only on discrete items |

```json
[
  { "id": "hematite", "name": "Hematite Ore", "stage": 2, "cargo_class": "ore", "density_kg_m3": 5000 },
  { "id": "wiring", "name": "Wiring", "stage": 5, "cargo_class": "goods", "density_kg_m3": 2000, "unit_mass_kg": 10 }
]
```

**Module items are derived, never authored.** The loader makes one item per module, with the same ID and `name`. An entry in `items.json` with a module's ID is an error.

| Field | Derived value |
| ----- | ------------- |
| `stage` | 5 |
| `cargo_class` | `goods` |
| `unit_mass_kg` | The module's `mass_kg` |
| `density_kg_m3` | The module's `mass_kg` divided by `volume_m3` |

**Volume and density.** This makes `volume_m3` the only source of a module's volume, so the two cannot disagree. The division must give a whole number, or the validator rejects the module. A stack of whole modules then takes exactly `volume_m3` each under the cargo formula. For example, a 400 kg module of 2 m3 is 200 kg/m3.

## 4. Modules

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `id` | string | Module ID |
| `name` | string | Display name |
| `mass_kg` | number | |
| `volume_m3` | number | Cargo volume while uninstalled. Not a fit limit. |
| `power_kw` | number | Non-negative draw while active. Generation is a capability. |
| `heat_kw` | number | Non-negative waste heat while active |
| `priority` | whole | Default power priority. Higher sheds last. |
| `durability` | whole | Stored but unused in the slice |
| `min_ai_tier` | whole, 1 to 6 | |
| `realism` | `established`, `extrapolation`, `speculative`, `fictional` | |
| `capabilities` | object | Section 5 |
| `fabrication` | object or null | `{ "recipe": id }`, or null for root parts, which are never items that get made |
| `connectors` | array | Section 6 |
| `collision` | object | Section 7 |
| `visual` | object | `{ "model": id or null, "tint": "#rrggbb" }`. Null `model` shows the labelled placeholder. `tint` is a lowercase hex string from the slice palette, so placeholders keep their colour blocks. Read by the client only, and it may add fields, but never numbers. |

`fabrication` names only the recipe, unlike the workplan's example. The recipe already states its facility, so a second copy could disagree.

```json
{
  "id": "mining_laser_mk1", "name": "Mining Laser",
  "mass_kg": 400, "volume_m3": 2,
  "power_kw": 150, "heat_kw": 120, "priority": 3, "durability": 1000,
  "min_ai_tier": 1, "realism": "extrapolation",
  "capabilities": { "mine": { "rate_kg_per_s": 20, "hardness_max": 6 } },
  "fabrication": { "recipe": "mining_laser_mk1" },
  "connectors": [
    { "id": "mount", "type": "side", "size": "medium", "pos_mm": [0, 0, 0],
      "facing": "-z", "up": "+y", "load_limit_kg": 400 }
  ],
  "collision": { "shape": "box", "center_mm": [0, 0, 700], "size_mm": [800, 800, 1400] },
  "visual": { "model": "mining_laser_mk1" }
}
```

## 5. Capabilities

`capabilities` is a closed list. A part may declare any mix, and a new key is a schema change through the Lead. These names are final, including `thruster`, `generate` and `radiator` for propulsion, power generation and heat rejection. Fields follow section 2 of the A0 network spec.

| Key | Fields | Used by |
| --- | ------ | ------- |
| `scan` | `seconds` (whole) | LIDAR |
| `mine` | `rate_kg_per_s`, `hardness_max` (whole) | Lasers |
| `ai_core` | `tier` (whole, 1 to 6) | Cores |
| `storage` | Per cargo class: `{ "mass_kg", "volume_m3" }` | Containers, tanks |
| `max_mass_kg` | number | Root parts only |
| `generate` | `power_kw` | Solar |
| `battery` | `capacity_kj`, `max_charge_kw`, `max_discharge_kw`, `charge_efficiency_ppm` (whole, up to 1000000) | Batteries |
| `radiator` | `reject_kw` | Radiators |
| `heat_capacity` | `limit_kj` | Summed to give the unit's heat limit |
| `port` | `transfer_kg_per_s`, `dock_seconds` (whole), `undock_seconds` (whole), `capture_range_mm` (whole), `capture_speed_m_s` | Docking ports |
| `thruster` | `speed_m_s`, `propellant_kg_per_s`, `rated_mass_kg`, `exhaust_m_s`, `thrust_kn` | Thrusters |
| `landing_gear` | `max_touchdown_m_s` | Landing legs |
| `facility` | `type`: `refinery`, `fabricator` or `lab`; `throughput_kg_per_s`; `work_per_tick` (whole, optional until C30 is on main) | Facilities. `throughput_kg_per_s`, above 0, is the most input mass a run takes in a second, and loads as `throughput_g_per_s` (C30, B29). The module's `power_kw` is the rating, the most a running job draws; `heat_kw` is only its fitting figure. `work_per_tick` goes with C30 |
| `always_on` | `true` | A load that runs whenever healthy, such as a command hub |

```json
{
  "storage": { "ore": { "mass_kg": 2000, "volume_m3": 2 }, "propellant": { "mass_kg": 500, "volume_m3": 1 } },
  "port": { "transfer_kg_per_s": 50, "dock_seconds": 20, "undock_seconds": 10, "capture_range_mm": 100,
    "capture_speed_m_s": 0.1 },
  "ai_core": { "tier": 2 }
}
```

A multi-role part has one `power_kw` and one `heat_kw`, which apply whenever it runs anything. The slice has none, since a drone is built from single-role parts like a ship.

A trip's cost is its travel time at `propellant_kg_per_s`, scaled by the unit's mass at departure over `rated_mass_kg`, and paid in one lump at departure ([autonomy.md](autonomy.md) section 4). The network spec holds the exact formula.

**Two kinds of thruster figure.** Trips inside a frame read `speed_m_s`, `propellant_kg_per_s` and `rated_mass_kg`, exactly as above. Burns outside a frame read only `exhaust_m_s` (loaded as `exhaust_mm_s`) and `thrust_kn` (loaded as `thrust_n`), through the rocket equation of [orbital_flight.md](orbital_flight.md) section 7. The two kinds are independent. `chemical_thruster_mk1` has `thrust_kn` 15 (tasks B11 and B11b), so a fully fuelled probe lifts off from Frost at about three times its gravity, and a hand-flown landing loses less to gravity. Its in-frame figures stay 1 kg/s at 500 m/s. A burn's propellant flow is `thrust_kn` over `exhaust_m_s`, 5 kg/s at 3000 m/s. `small_chemical_thruster_mk1` stays at 0.15 kN, where both kinds still agree. All five fields are required, and the validator checks them (task B13). A thruster is not a power or heat load during a trip, so in the slice its `power_kw` and `heat_kw` count only toward fitting budgets.

**Docking capture (task B29, for A54).** `capture_range_mm` is the distance between the two ports at which the capture latches engage, a whole number of millimetres above 0. `capture_speed_m_s` is the fastest closing speed at which they latch, above 0, and it loads as `capture_speed_mm_s`. A dock needs both: ports within range, closing no faster than the limit. The range is in mm because no loader rule turns metres into millimetres. The values follow real soft-capture systems, which latch at about 0.03 to 0.1 m/s within a few to tens of centimetres:
- `docking_port_mk1`: 100 mm at 0.1 m/s, like a medium androgynous port's guide petals;
- `small_docking_port_mk1`: 50 mm at 0.05 m/s, since a small craft has less mass to absorb the contact.

Rule: a pair of ports uses the lower of each limit. A54 shows these figures, and stage 4 enforces them.

**Landing gear.** `max_touchdown_m_s` is the fastest touchdown the part survives, above 0, and it loads as `max_touchdown_mm_s` (task B15). A unit's touchdown limit is the highest figure among its healthy parts with landing gear, and 0 when it has none. A touchdown at or under the limit lands, and one over it crashes. Hand-flown landings and the core autopilot's `land` both obey this, so a unit with no gear cannot land. `max_slope_mdeg` is reserved on this object for a later slope limit. It is not part of the schema yet, and the validator rejects nothing for its absence. Today's parts are `landing_legs_mk1` (6 m/s, 150 kg, three structural frames) and `small_landing_legs_mk1` (4 m/s, 50 kg, one frame), both side-mounted. The long legs mount on the four low side connectors of the probe's `propellant_tank_mk2`, 0.4 m above its bottom, and reach 2.8 m below their mount, which is 0.4 m below the thruster's nozzle (task B11). The client stands a landed craft on its lowest collision point, so the legs' collision box sets where it stands. It is provisional until the long-leg model arrives, and is then fitted to it.

**Factory rates (C30, B29).** A job runs at the lowest of three rates:
- the power supplied, up to the machine's `power_kw`;
- the power its share of radiator headroom allows, which is the headroom times `energy_kj` / `heat_kj`;
- the machine's throughput, or the recipe's if lower, times `energy_kj` per kg of input.

A run ends when its energy is spent. So a bigger machine is faster at the same recipe, and a heat-heavy step such as copper smelting is held back by the radiators, not by the power.

Today's one-step recipes carry interim values, each the real process the abstract recipe stands for, until the deep chains of [production_chains.md](production_chains.md) replace them:

| Recipe | Energy a run | Heat a run | What it stands for |
| --- | --- | --- | --- |
| `refine_hematite` | 352 MJ | 296 MJ | Hydrogen reduction of 100 kg of ore, then melting the 69 kg of iron at 2.2 MJ/kg |
| `refine_chalcopyrite` | 75 MJ | 400 MJ | Flash smelting, converting and electrorefining, exothermic |
| `refine_olivine` | 830 MJ | 518 MJ | Acid leach and carbothermic reduction, 19 kg of silicon |
| `refine_water_ice` | 2,576 MJ | 1,086 MJ | Melting, then electrolysis and liquefaction of 90 kg of water at 55 kWh per kg of hydrogen |
| `structural_frame` | 75 MJ | 75 MJ | Rolling, cutting and welding 50 kg at 1.5 MJ/kg |
| `wiring` | 12 MJ | 12 MJ | Drawing and insulating 10 kg of copper |
| `processor` | 130 MJ | 130 MJ | Two radiation-hard chips at 55 MJ each, plus the board |
| A part or a unit | 2 MJ per kg | the same | Machining, welding, integration and test of the part's mass, or of the template's parts |
| A lab test | its run at 100 kW | the same | Today's run length, until field trials replace the tests |

Machine throughputs:

| Machine | Throughput |
| --- | --- |
| `compact_fabricator_mk1` | 0.02 kg/s |
| `fabricator_mk1` | 0.05 kg/s |
| `compact_refinery_mk1` | 0.05 kg/s |
| `ore_refinery_mk1` | 0.2 kg/s |
| `research_lab_mk1` | 0.1 kg/s |

**This is far slower than today.** A frame takes 2,500 s on the compact fabricator, limited by throughput. A run of ice takes 25,760 s on the 100 kW compact refinery, limited by power. Real propellant from ice costs about 29 MJ per kg. So power, not machine count, becomes the new start's main limit.

## 6. Connectors

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `id` | string | Unique within the module |
| `type` | `stack`, `side`, `dock` | |
| `size` | `core`, `small`, `medium`, `large` | |
| `pos_mm` | three whole numbers | Relative to the module origin |
| `facing` | `+x`, `-x`, `+y`, `-y`, `+z`, `-z` | |
| `up` | Same values | At right angles to `facing` |
| `load_limit_kg` | number | Mass carried below this connector |

Two connectors join only if their types match and either both or neither are size `core`. `small`, `medium` and `large` do not decide a join, so any part fits any craft that can carry it, limited by load, mass, power and heat. `facing` and `up` are written in the module's own frame. A child part is turned as it mates, so that in the craft's frame the facings are opposite and the ups equal.

The `core` size is used only by cores and the core connector on root parts, which is what keeps other parts off it. Dock connectors take no part in a join, so a small port docks at a medium port.

## 7. Collision

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `shape` | `box`, `cylinder` | Cylinder axis is the module's Y |
| `center_mm` | three whole numbers | Relative to the module origin |
| `size_mm` | three whole numbers | Full extents `[x, y, z]`. A cylinder's diameter is `x` and its height is `y`, and its `z` must equal `x`. |

## 8. Recipes

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `id` | string | Recipe ID |
| `facility` | `refinery`, `fabricator` | Runs on a part with this `facility.type` |
| `energy_kj` | whole, at least 1 | The energy one run takes, in kJ, from real process figures (C30, B29). It loads as `energy_j` |
| `heat_kj` | whole, at least 0 | The heat one run gives off, in kJ, which the unit's radiators must reject. It loads as `heat_j`. It is the energy put in, less what the products store, plus any reaction heat, so an exothermic step can give off more heat than its energy |
| `throughput_kg_per_s` | number, optional | A slower material rate for this recipe than the machine's, such as an acid leach. The run uses the lower of the two |
| `work` | whole, above 0, optional | Work points (C11). Kept until C30 is on main, then removed, with `seconds` long gone (B11b) |
| `power_kw` | number, optional | The old fixed draw. Kept until C30 is on main, then removed |
| `inputs` | array | At least one entry |
| `outputs` | array | At least one entry |
| `abstract` | boolean | True for every slice recipe |

An input is `{ "item": id }` plus exactly one amount: `kg` for a continuous item, or `count` (whole) for a discrete one. Using `count` means a recipe cannot name part of a unit. The loader converts both to `grams`.

An output is one of three forms:

| Form | Example | Goes to |
| ---- | ------- | ------- |
| Item | `{ "item": "iron", "kg": 69 }` | Facility unit's inventory |
| Sink route | `{ "item": "slag", "kg": 31, "sink": "slag_vent" }` | The named sink, with no cargo space reserved |
| Unit | `{ "unit_template": "small_craft" }` | A new unit, whose mass comes from its template. The template must hold a port. |

A unit output must be the recipe's only output. An item appears at most once on each side of a recipe.

```json
[
  { "id": "refine_hematite", "facility": "refinery", "work": 60000, "power_kw": 200,
    "inputs": [{ "item": "hematite", "kg": 100 }],
    "outputs": [{ "item": "iron", "kg": 69 }, { "item": "slag", "kg": 31, "sink": "slag_vent" }],
    "abstract": true },
  { "id": "small_craft", "facility": "fabricator", "work": 60000, "power_kw": 100,
    "inputs": [{ "item": "structural_frame", "count": 2 }, { "item": "wiring", "count": 2 }],
    "outputs": [{ "unit_template": "small_craft" }],
    "abstract": true }
]
```

## 9. Deposits

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `id` | string | Deposit definition ID |
| `item` | string | The ore it yields |
| `mass_kg` | number | Starting amount. The contracts' `grams` is this field after loading. |
| `hardness` | whole, 1 to 10 | Compared with `mine.hardness_max` |

```json
{ "id": "hematite_medium", "item": "hematite", "mass_kg": 50000, "hardness": 5 }
```

A definition is a reusable kind of deposit. A scenario creates runtime deposits from it, each with its own entity ID and body.

## 10. Unit templates

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `id` | string | Becomes the unit's `def` |
| `name` | string | Display name |
| `kind` | `ship`, `station`, `drone` | |
| `root` | object | Root part node |

A node is `{ "part": module_id, "children": [] }`. A child node adds `parent_connector` (on its parent) and `connector` (on itself).

```json
{
  "id": "starter_ship", "name": "Starter Ship", "kind": "ship",
  "root": {
    "part": "starter_hull",
    "children": [
      { "part": "basic_core", "parent_connector": "core", "connector": "mount", "children": [] },
      { "part": "mining_laser_mk1", "parent_connector": "side_px", "connector": "mount", "children": [] }
    ]
  }
}
```

- Part IDs are issued walking the tree parent first, with children in listed order, so creation is deterministic.
- If a template contains a core, it is assigned at creation. A template holds at most one.
- A template holds parts only. Starting inventory comes from the scenario, so a built unit arrives with an empty inventory.

## 11. Sinks

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `id` | string | Sink ID |
| `name` | string | Display name |
| `items` | array of item IDs | What it accepts |

```json
[
  { "id": "propellant_exhaust", "name": "Exhaust", "items": ["propellant"] },
  { "id": "slag_vent", "name": "Slag Vent", "items": ["slag"] }
]
```

## 12. Cross-checks for the validator

B4 enforces these on top of section 3 of the accounting spec.

**References**
- Every item, module, recipe, sink, facility type and template reference resolves.
- A module's `fabrication.recipe` outputs that module.
- A template named by a unit output holds at least one part with `port`, so the unit can appear docked.
- A sink route's item is in that sink's `items`.
- An output of an item that a sink accepts must route to that sink, except propellant, which is also a product of `refine_water_ice` and may stay in the hold (task B11).
- Every module is buildable: the output of a recipe, or a part of a template that a recipe outputs. Roots such as `starter_hull`, `small_hub` and `command_hub` come only from templates (task B11).
- An `item` input or output is authored with `kg` if continuous and `count` if discrete.

**Parts**
- A root part declares `max_mass_kg`, has null `fabrication`, and has a `core` connector. Other modules have none of these, except cores, which carry one `side` connector of size `core`.
- A non-root module has exactly one connector with ID `mount`, at `[0, 0, 0]`, because its origin sits on its mount face. It may have further connectors, such as a dock connector or a stack connector for parts above it.
- A module with a `dock` connector has exactly one, and declares `port`.
- `up` is at right angles to `facing`.
- `min_ai_tier` is the tier of the lowest core that can use the part, so slice parts declare 1.

**Recipes and facilities**
- A recipe's `power_kw` is at most the `power_kw` of every module with that facility type.
- Every deposit's `hardness` is within at least one `mine.hardness_max`.

**Templates**
- Each template passes the fitting rules in contracts section 5, including mass, power, heat and connectors.
- A unit with any `heat_kw` above 0 has `heat_capacity`, since its limit is otherwise 0.
- A unit with `thruster` has `propellant` storage.

**Scenario places** (section 14)
- An orbit's `parent` is a body in the same scenario with `gm_km3_s2`, and is not the orbiting entry itself.
- Every `frame` key names a frame in the scenario. A docked unit has no `frame`.
- A body on an `orbit` has neither `pos_mm` nor `frame`. A body without an orbit has `pos_mm`.
- Orbits are whole numbers: `a_mm` from 1 to 10^15, `e_ppm` from 0 to 999999, and each angle from 0 to 359999 millidegrees. `gm_km3_s2` stays within the contract range of `gm` once converted.
- Frame keys share the one key space with bodies and units.
- A `planet` object appears only on a body of kind `planet`, within the ranges of section 14.

**Coverage**
- A source is a deposit, a recipe or scenario stock. A use is a recipe input, a fitted part, propellant burn or a sink (spec section 10).

## 13. Lead rulings

| # | Issue | Ruling |
| - | ----- | ------ |
| 1 | The A0 draft on `kernel/A0` names the sink `exhaust` and still burns per tick. The approved spec and accounting pages say `propellant_exhaust`, paid at departure. Keep `propellant_exhaust`. A corrects A0 before it merges. |
| 2 | Autonomy section 12 asks for a trip priced from current mass. The A0 draft says mass does not change burn. Mass is in the price, so a full hold costs more to fly. `thruster` gains `rated_mass_kg`, and A0 defines the formula. |
| 3 | A module and a recipe both state `power_kw`, and A0 does not say which a running job draws. | A running job draws the recipe's `power_kw`. The module's is its rating, which the fit check sums. Waste heat always comes from the module's `heat_kw`. |
| 4 | Contracts section 10 says mated connectors have opposite facings and equal ups, without saying in which frame. In the module's own frame, a part with one mount could fit only one side of a hull. | Read it as the craft's frame, as section 6 says. |
| 5 | The capability list in contracts section 10 stops at `max_mass_kg`, and `defs()` lists only some renames. Contracts section 10 now points at section 5 of this page. |

## 14. Scenarios

A scenario places bodies, deposits and units in the world and sets starting inventories. It is what `Sim.new_game(scenario_id, seed)` loads. The file holds one object, with no `entries` list, and its `id` matches the file name.

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `schema_version` | whole | 1 |
| `id` | string | Scenario ID |
| `name` | string | Display name |
| `seed` | whole | Seed the scenario is tested with. `new_game`'s argument still decides the run. |
| `bodies` | array | Listed in entity ID order |
| `frames` | array, optional | Co-moving frames, such as the rock cluster |
| `units` | array | Listed in entity ID order |

A body has `key`, `name`, `kind` (`star`, `asteroid` or `planet`), `pos_mm`, `radius_mm`, `visual_seed` and `deposits`, a list of deposit definition IDs. It may also have:

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `gm_km3_s2` | number, optional | Gravitational parameter. Loads as `gm` in 1000 m³/s². A body that others orbit must have it |
| `orbit` | object, optional | Its orbit, below. A body on an orbit needs no `pos_mm`, because its position is derived from the orbit and the tick |
| `frame` | frame key, optional | The frame it belongs to. Its `pos_mm` is then local to the frame |
| `planet` | object, optional | Terrain, below. Only on a body of kind `planet`. A planet without it is a smooth sphere |

A frame has `key`, `name`, `radius_mm` and `orbit`. It is not a body, and it never appears where bodies are listed as targets. Its `radius_mm` is the sphere within which a unit can join it ([orbital_flight.md](orbital_flight.md) section 11.2).

An orbit is an object of whole numbers, so no float reaches it:

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `parent` | body key | The body orbited. It must have `gm_km3_s2`, or the scenario is refused |
| `a_mm` | whole, positive | Semi-major axis. 1 AU is 149597870700000 |
| `e_ppm` | whole, optional, default 0 | Eccentricity in parts per million, below 1000000 |
| `inclination_mdeg` | whole, optional, default 0 | Angles in millidegrees |
| `node_mdeg` | whole, optional, default 0 | |
| `periapsis_mdeg` | whole, optional, default 0 | |
| `mean_anomaly_mdeg` | whole, optional, default 0 | At tick 0 |

A unit has `key`, `template`, `name`, `pos_mm`, `inventory` and `dock`, and an optional `frame` key. A unit in a frame has a local `pos_mm`. A docked unit takes its host's place, so it has no `frame` of its own. `inventory` is a list of `{ "item": id }` plus `kg` or `count`, as in recipe inputs. `dock` is null or `{ "host": key, "port": index, "host_port": index }`. An index counts the unit's `port` parts in part ID order, from 0.

`key` is a name used only inside the file, unique across bodies and units. Whole-number fields must stay within 2^53, because Godot parses JSON numbers as floats.

**Entity IDs.** The counter starts at 1 and issues IDs in file order: each body, then that body's deposits, then each frame, then each unit, then that unit's parts in template order. This makes IDs known in advance.

A `planet` object holds the terrain settings that both the simulation and the client read, so a hex's height is the same in both ([planets.md](planets.md) section 4):

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `seed` | whole | Lays out the terrain through `PlanetGrid` |
| `height_range_m` | whole, 0 to 8000 | Highest peak and deepest basin either side of the datum radius. 8000 is the proven limit |
| `sea_level_m` | whole, -8000 to 8000, optional | Cells below it are sea. Absent means a dry world |
| `weights` | list of 1 to 12 whole numbers, each 0 to 1000, optional | Octave weights for the height and moisture noise, broadest first, with at least one above 0. Default `[4, 2, 1]` |

The other settings in [planets.md](planets.md) section 1 (`kind`, `temperature`, `moisture_bias` and the palette) are not data yet. They arrive with the surface rule tables. `roughness` is not a scenario field. It is a planet-kind idea for a later generator that writes `weights`, so there is one source of truth for the noise.

**No sphere-of-influence field.** A body's sphere of influence is not data. A12 works it out at scenario load from Laplace's formula, a × (GM / parent GM)^(2/5), and stores it as `soi_mm` in the state. So it always agrees with the GMs and orbits.

**Validity.** A docked unit's `pos_mm` equals its host's, and starting inventory fits the unit's capacity, by mass and volume per cargo class. The validator checks both.

**Start state.** Batteries start full and heat loops start at 0. Every deposit starts unfound. A template with a core has it assigned (section 10). A docked unit starts with `at_target` set to its host, as after arrival.

## 15. Research (task B19, contract version 5)

Data for [research.md](research.md) under contract version 5 (C12). Both files are optional to the validator, so a dataset without research still passes.

**`theories.json`:** the usual `schema_version` and `entries`, plus a top-level `bench_test`.
- **`bench_test`** is the default bench test that qualifies a prototype: `{ inputs, work, power_kw }`, which loads as `power_w`. It is required once any theory exists. The data sets 10 processors, work 300000 and 100 kW.
- **An entry has:**
  - `id` and `name`;
  - `era`, whole, 2 to 6;
  - `requires`, theory IDs, with no cycles and none of a later era;
  - `evidence`, a list of `{ kind, count }`: `count` distinct keys of that `science.json` kind paid at least once;
  - `test`, a lab recipe whose output is `{ "theory": id }`;
  - `unlocks`, module IDs, each unlocked by one theory at most;
  - optionally `qualify`, inputs that replace the bench test's for the designs it unlocks.

**`science.json`:** each entry has:
- `id` and `name`;
- `place`: `asteroid`, `orbit` or `landed`;
- `capability`: the part capability that takes it, or `ai_core`;
- optionally `seconds`; without it, the time is the part's own, or one orbit;
- `points`, which maps body classes (`asteroid`, `moon`, `planet`) to base points.

The nth payment of a key such as `composition:12` is base >> n.

**Recipes:**
- the facility type `lab`;
- an optional `points` input, whole and above 0;
- the output `{ "theory": id }`, which weighs nothing and may sit only beside sink routes. Every lab recipe proves a theory.

**Derived, not authored:** `prototype:<design>`, which is both an item and its recipe, and `qualify:<design>`. ':' and '+' never appear in an authored ID; the ID pattern `^[a-z][a-z0-9_]*$` already excludes them.

**Sinks:**
- An `items` list of exactly `["*"]` accepts any item, derived prototypes included. `test_consumed` takes a test's goods, and `fab_scrap` takes a prototype's or variant's input mass beyond the part.
- A route is required only for waste: an item that no recipe takes as input, such as slag. Propellant may also stay in a hold.

**Modules:** optional `ideas`. An idea has:
- `id` and `name`;
- `points`;
- `complexity`, whole, from -10 to 10, and negative exactly when `simplifies` is true;
- `deltas`;
- optionally `theory` (no nulls: an idea needing none leaves it out), `simplifies`, `hidden` (a simplification only, which needs `discover_ppm`) and `discover_ppm` (1 to 1000000).

`deltas` maps a field path, such as `capabilities.mine.rate_kg_per_s`, to ppm of the base value. Each delta is whole, not 0, and above -1000000. The validator's direction table lists the allowed fields, and each idea makes at least one field better and one worse.

**Scenarios:** an optional `research: { theories: [...] }`. Those theories are proven at load, and their unlocks are qualified. `reference.json` proves all three of today's theories, because its station already carries the refinery and the solar farm. `new_start.json` proves none.
