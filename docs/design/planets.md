# Generated Planets

Status: **proposal for the owner**, task design/planets. Nothing here is built, and nothing changes `data/`, `sim/`, the client or the contracts until the owner decides. This is the planet half; the flight half, with the integer maths, is [orbital_flight.md](orbital_flight.md) by Agent A.

## The short answer

- **Yes, this works, and it is cheap to store.** A planet is a seed plus about eight settings. The simulation never stores its 100,002 hexes. It works out any hex on demand from the seed, and saves only what the player has changed: deposits found or mined, and things built or landed.
- **Each hex gets one integer height and one surface type.** The type comes from a small rule table on height, latitude, moisture and slope, so there are ice caps, seas, deserts, highlands and cliffs without hand placement.
- **Variety comes from planet kinds**, not from the seed alone. A kind (airless moon, desert world, ocean world, ice world, temperate world) sets the ranges for sea level, roughness, temperature and palette, and the seed picks within them. That stops every planet looking like the same continents in a different colour.
- **A hex is a place, not a block of rock.** At 600 km radius a hex is about 7 km across, so it works as a claim: at most one landing or build site, and a chance of one hidden deposit. It is not dug out cell by cell.
- **One choice for you: a fixed count or a fixed size.** Your figure gives every planet 100,002 hexes, so a small moon's hexes are 2.4 km and a large world's are 14.5 km. The alternative fixes every hex at about 7 km, so a 200 km moon has about 11,000 hexes and a 1,200 km world about 400,000. I lean towards fixed size, since a hex then means the same in play everywhere, but both are the same code (section 5).
- **Recommended look: smooth terrain over hex data**, as KSP does it, with the hex grid shown only as an overlay in map and build modes. Hex columns are cheaper but look like a board game and show visible steps from orbit.
- **The boundary:** whatever decides play (height, type, slope, deposits) is integer and deterministic, and Agent A proves it. Everything below hex size (bumps, rocks, colour blending, clouds, water) is client-only float detail and never reaches the simulation.
- **Cost:** the client's planet renderer is the largest piece. Nothing here belongs in the slice. All of it can wait until after the M4 judgement, and only a paper proof and one throwaway picture make sense before it.

## 1. What a planet is

| Setting | Example | What it does |
| ------- | ------- | ------------ |
| `seed` | 48213 | Lays out every height, moisture and deposit roll |
| `kind` | `temperate` | Picks the ranges below and the rule table |
| `radius_km` | 600 | Datum sphere. Also sets hex size (section 5) |
| `height_range_m` | 8000 | Highest peak and deepest basin, either side of the datum |
| `roughness` | 0 to 1000 | How rugged: more small-scale noise, more cliffs |
| `sea_level_m` | -200, or none | Height below which hexes are sea. None means a dry world |
| `temperature` | 0 to 1000 | Overall warmth. Later this can come from distance to the star |
| `moisture_bias` | -300 to +300 | Shifts the world wetter or drier |
| `palette` | `temperate_a` | Colours only. Never read by the simulation |

All settings are integers. The seed picks values for each setting inside the kind's range, so a kind can describe thousands of planets and a scenario can still fix one exactly.

**Why noise and not randomness.** Each hex's height is a sum of smooth noise at several scales: broad continents, mountain ranges (a ridged layer), and local roughness. Neighbouring hexes get similar values, so land forms coasts, ranges and basins. Pure random heights give static.

## 2. Surface types

### 2.1 Inputs

Every input is an integer the simulation can compute for one hex on demand.

| Input | Source |
| ----- | ------ |
| Height | Agent A's noise for this seed and cell, scaled by `height_range_m` and `roughness` |
| Latitude | From the cell's centre: the height of the centre above the equator as a fraction of the radius, in thousandths. No trigonometry needed |
| Temperature | `temperature`, minus a share for latitude, minus a share for height, so poles and peaks are cold |
| Moisture | A second noise field, 0 to 1000, plus `moisture_bias` |
| Slope | The largest height difference to any of the cell's six (or five) neighbours |

Moisture is plain noise, not distance from the sea. Working out distance to the coast means walking the whole grid, which breaks "any hex on demand". The rule table can still make coasts wetter by using height near sea level.

### 2.2 Rule table

The first rule that matches wins. The table is data, one per planet kind, so a new kind needs no new code.

| # | Type | Rule | Buildable | Landable |
| - | ---- | ---- | --------- | -------- |
| 1 | Deep sea | height below sea level by more than the shelf depth | No | No |
| 2 | Shallow sea | height below sea level | No | No |
| 3 | Ice | temperature below freezing | Yes | Yes |
| 4 | Cliff | slope above the cliff limit | No | No |
| 5 | Highland rock | height above the highland line | Yes | Yes, if slope allows |
| 6 | Dust plain | moisture below the dry line | Yes | Yes |
| 7 | Lowland | moisture between the dry and wet lines | Yes | Yes |
| 8 | Wetland | moisture above the wet line | Yes | Yes |

That is the first palette: eight types. On an airless or dry world, rules 1 and 2 never fire and rule 8 is left out, so a moon comes out as dust, highland, cliff and polar ice. Whether a lowland reads as green or as dark basalt is a palette choice, not a simulation one.

The validator checks that every table covers every combination of inputs, so no hex can end up without a type.

### 2.3 Avoiding sameness

| Lever | Effect |
| ----- | ------ |
| Kind | Changes which rules fire and the setting ranges: an ocean world is 80% sea, a desert world has none |
| Seed | Changes the layout: where continents, ranges and basins sit |
| Noise layer weights per kind | Some kinds favour broad continents, others ranges or rough badlands |
| Palette | Several per kind, picked by the seed, so two desert worlds differ in colour |
| Rare features (later) | Crater stamps on airless worlds, rift lines, a single huge volcano. Each is an integer stamp on cell heights, picked by the seed |

## 3. What a hex means in play

### 3.1 Today's model

Today a deposit is an entity on a body. A scenario lists bodies (`star` or `asteroid`), each with a list of deposit definitions (item, `mass_kg`, `hardness`). A scan of the whole body reveals all its deposits, and a laser mines one from a ship at the body. Deposit IDs are issued at scenario load (`schemas.md` sections 9 and 11, `contracts.md` section 6). [spec.md](spec.md) section 4 already lists four ores found only on planets (Uraninite, Monazite, Xenotime, Spodumene), plus Sulfur, Bismuth, and ice that planets share with the belt.

### 3.2 On a planet

**Deposits.** Each hex has a deposit roll from the seed. Most hexes hold nothing. A small share hold one deposit, and the surface type and height set which ore is likely: ice at the poles and in cold highlands, sulfur near rifts, the planet-only ores in highland rock. A table per kind holds the chances, as data.

- A deposit stays virtual until it is found. Finding it creates the deposit entity, with an ID from the normal counter. Since finding only happens through commands, IDs stay deterministic.
- From then on it is an ordinary deposit, with item, grams and hardness, depleted by mining and counted in the matter ledger. The ledger counts found deposits only. Unfound rock is outside the game's matter until it is found, in the same way an unscanned asteroid's deposits are fixed numbers nobody has touched.
- Deposit sizes stay abstract, in the same range as the asteroids' (tens to hundreds of tonnes), not the real tonnage of 45 km² of crust. Otherwise one hex would feed the whole game.

**Scanning.** Scanning a whole planet in one go would reveal thousands of hexes. Proposed instead: a scan from orbit covers a patch of hexes under the ship, with the patch size set by the scanner and the altitude, and reports which hexes hold *something*. A scan from the ground, or a low pass, identifies the deposit. This gives the probe a reason to survey.

**Build sites.** One surface site per hex. A site needs a buildable type and a slope below the build limit. A surface base is the same as a station today: a unit made from parts with the same attachment rules, but with a landed state and a cell in place of a free position. Seven kilometres is far larger than any base, so the hex is a claim, not a footprint.

**Landing.** A craft lands on a hex, not on a point. Landing is allowed on a landable type with slope below the craft's limit. The landed position is the cell's centre at its integer height. How a craft gets there is Agent A's flight question. This page only fixes where it may end up.

### 3.3 What changes

| Today | With planets |
| ----- | ------------ |
| Body kind `star` or `asteroid` | Add `planet`, with a seed and settings in place of a deposit list |
| Deposits listed in the scenario, IDs fixed at load | Asteroid deposits unchanged. Planet deposits are created when found |
| `scan` reveals a whole body | On a planet, `scan` covers a patch of cells |
| Units are at a position, or docked | Add landed: body plus cell |
| `view()` lists every targetable body and found deposit | Hexes stay out of `view()`. The client asks for cells through a separate read-only query, or runs the same pure generator itself |
| Mining from a ship near the body | Mining from a unit landed on that hex, or the next one |

Each of these is a contract change, so it goes through the Lead.

## 4. The boundary with the simulation

Agreed with Agent A (pending their reply, see section 8).

**The simulation reads, and Agent A proves:**
- The cell grid: IDs, neighbours and integer cell centres.
- The integer noise: height, moisture and the deposit roll for one cell, from the seed and cell ID, the same on every machine and every run.
- Latitude, temperature and slope from those values, in integers.
- The surface type, from the rule table in `data/`.
- Found deposits, built sites and landed units, which are ordinary saved state.

**Client only, floats allowed, never read by the simulation:**
- Smooth terrain between cell heights, and all detail smaller than a hex: bumps, boulders, small craters, erosion.
- Colours, colour blending between types, textures, normal maps.
- Water surface, clouds, atmosphere glow, ice sheen.

**One rule ties them together:** at the hex scale the client uses the simulation's own integer heights, not its own noise. The generator is plain `RefCounted` code with no state, so the client can call it directly. Godot's built-in float noise is fine for client-only detail but never for hex heights, because it is not guaranteed to match.

As with ship models, nothing generated for display ever decides play.

## 5. Scale

| Radius | Hexes (n = 100) | Hex width | Hex area |
| ------ | --------------- | --------- | -------- |
| 200 km | 100,002 | 2.4 km | 5 km² |
| 600 km | 100,002 | 7.2 km | 45 km² |
| 1,200 km | 100,002 | 14.5 km | 181 km² |

Exactly 12 of the hexes are pentagons, wherever the grid is laid. They are slightly smaller, and the rules treat them as cells with five neighbours.

**The owner's choice: a fixed count or a fixed size.**

| | Fixed count (owner's figure) | Fixed size |
| - | ---------------------------- | ---------- |
| Rule | `n` = 100 on every planet | `n` from the radius, so a hex is about 7 km |
| 200 km moon | 100,002 hexes, 2.4 km each | `n` = 33, about 11,000 hexes |
| 1,200 km world | 100,002 hexes, 14.5 km each | `n` = 200, about 400,000 hexes |
| For | Same cost to generate and draw on every planet | A hex means the same everywhere: one site, the same deposit odds, the same landing scale. Small moons are cheap |
| Against | Hex size, and with it site spacing and deposit density, changes from world to world | Large worlds cost four times as much to draw |

B leans towards fixed size. Either is the same code, since `n` is one setting.

## 6. The look

The art style is KSP-like with original designs: no KSP planet names, textures or layouts are used. Planets need no models from the image-to-3d pipeline, so they cost no GPU holds.

### Option A: hex columns

Each hex is a flat-topped prism at its height, coloured by type.

- For: simple and cheap to build. Every hex reads clearly, which suits a strategy map.
- Against: it is not the KSP look. With heights spread over thousands of metres, neighbouring columns differ by hundreds of metres, so the planet shows steps even from orbit. Close up, a craft lands on a 7 km flat table edged by cliffs.

### Option B: smooth terrain over hex data (recommended)

The cell centres become the vertices of a smooth surface. The grid's dual is a mesh of about 200,000 triangles with one vertex per cell, so the base surface comes straight out of the data. Colour blends between neighbouring types. Hex outlines are drawn on top only when needed: in the map, when picking a landing site, and when placing a base.

- For: it matches the KSP look, a planet reads as a planet, and play keeps all the clarity of hexes through the overlay.
- Against: more client work, mostly the close-up detail in section 7.

Recommendation: **B**. The hexes stay the rules, and the player sees them when choosing where to land or build, but the world looks like a place.

## 7. Close up: landing inside a 7 km hex

The base mesh has a vertex every 7 km, which is flat cardboard from a lander's camera. Close up needs:

1. **Level of detail by chunks.** The surface splits into patches that subdivide near the camera, down to about a metre at the landing site. This is the main client job. Godot has no built-in planet terrain, so the client builds it.
2. **Float detail noise**, client only, added on top of the smooth surface: hills, rocks and small craters, scattered from the planet's visual seed. Boulders are drawn as instances.
3. **Landing pads are flat.** Around a landed craft or a base, the detail fades out within a set radius, about 200 m, so the craft sits exactly at the simulation's height and never clips into a visual hill.
4. **Precision.** Single-precision floats on a 600 km sphere are good to about 6 cm, and the client's floating origin already keeps the camera near zero. Chunks are built relative to their own origin.
5. **Collision is not needed** for landing as a state. If Agent A's flight lets a craft descend under its own control, the ground height at a point should come from integer interpolation of the cell heights, defined on A's page, and never from the visual mesh.

## 8. Open with Agent A

- Cell ID scheme, neighbours and integer cell centres.
- The integer noise function, its range proof and its cost per cell in GDScript. A whole planet is 100,000 cells times several noise layers. The simulation only needs a few cells at a time, but the client needs every cell to draw the planet, so this cost decides whether drawing needs a cache or a background thread.
- Whether the planet rotates, and the frame for landed units.
- Height unit and range, and the datum radius.
- Ground height between cell centres, if descent is flown rather than ordered.

## 9. Cost

None of this is in the slice. The slice has one asteroid field and no planets, and the M4 judgement is on that loop. The station and the slice's rocks stay one cluster sharing a solar orbit, so this page adds no transfer windows to the slice's automation. This holds only if each rock's orbit is the same size as the station's: a rock 50 km nearer the star drifts about 54 m an hour, shifting a trip by 5 to 9 ticks over a 4-hour session (Agent C, [orbital_automation.md](orbital_automation.md)). Rocks therefore sit ahead of, behind, above or below the station on its orbit, never nearer to or farther from the star. Windows arrive only with a later planet scenario, where a station in orbit trades with a surface or a separate ring. Radii and periods are in [orbital_flight.md](orbital_flight.md).

| Who | Work | Rough size |
| --- | ---- | ---------- |
| Lead | Contract changes: body kind `planet`, landed state, cell IDs, scan patch, cell query, new events and reason codes | One contract round |
| A | Grid, integer noise, range and determinism proofs, frames, landing state, a perf test for whole-planet generation | 3 to 4 tasks, part of the flight work |
| B | Spec and schema updates; `data/` for planet kinds, rule tables, palettes and deposit chances; validator checks; balance figures for planet deposits | 2 to 3 tasks |
| C | Patch scanning, deposits created when found, mining from a landed unit, surface build sites | 2 to 3 tasks |
| D | Planet renderer with chunked detail, hex overlay, landing-site picker, system map planets | 4 to 6 tasks, the largest share |

**Checks and figures.** New tests: a golden hash over every cell of one fixed planet, so any change to generation shows up; every rule table covers all inputs; deposit tables name real items; the matter ledger still holds when a deposit is created on discovery; a generation perf test; and client screenshots of one planet from orbit and from the ground. The reference scenario and balance report stay as they are, since they cover the slice. A planet scenario gets its own figures later.

**Before M4, if the owner wants to see it early:** Agent A's paper proof, and one throwaway client picture of a seeded planet using option B, kept off `main`. Both are small and take nothing from M3, but D's time on M3 comes first.

**After M4:** everything else, starting with the contract round, then A and B in parallel, then C and D.
