# Newman Probe model briefs

Text briefs for the image-to-3d pipeline, one file per model. Codex draws each picture from its brief, and TRELLIS.2 builds the model from that one picture. No images are made or supplied here.

**Project:** a crewless space automation game. Every craft is built from separate parts stacked and bolted together, and a part may appear hundreds of times, so each one must read clearly at a glance.

## Shared style

This applies to every brief. Each brief also repeats what Codex needs, so it can be used alone.

**Shape**
- Chunky, faceted industrial hardware: flat-faced prisms with sharp corners, short tapers, domed tanks, thick flanged joints and bolted-on boxes.
- Slightly oversized and simplified. A part should look sturdy and a little toy-like in its proportions, while still believable as real machinery.
- Identity comes from the silhouette. Someone should be able to name a part from its outline alone.
- Each part ends in a thick collar or flange, which hides small gaps where parts join.
- Nothing sticks out past the size in `data/`. On round parts the widest diameter, collars and bands included, equals the data diameter, so bands are flush with the body, set off by grooves, never raised rings. On faceted hulls the data diameter is measured across the flats, and the corners stand up to 8% beyond it.
- Hulls are never plain drums. The owner said the first hulls looked like barrels, not spaceship parts. A hull is a faceted prism (eight sides, or twelve for the station hub) with tapered shoulders stepping down to a smaller mounting face at each end, panel-seam grooves so it reads as bolted plating, and one feature on one side only, such as the core bay, so it isn't the same all round. Tanks get domed shoulders, and storage parts get facets or bevels, for the same reason. The first B12 pictures of both hulls, the hub, the tank and ore storage were drawn from an early brief that still said "cylinder", and this README then said "rounded hardware: cylinders", which Codex copied into its prompt. So those five briefs now open with a SHAPE line that names the shape and says what it is not, their end faces are faceted too, and the view asks for each flat face to be lit to its own tone.
- Side connector rows sit on plain, smooth body, clear of bands. In B9 the bands landed on the rows and buried the mounted parts' plates.

**Colour**
- Simple solid blocks, in four colours only:

| Colour | Hex | Use |
| ------ | --- | --- |
| Off-white | `#e8e4d8` | Main bodies and tanks |
| Mid grey | `#8a8d91` | Collars, flanges, machinery |
| Safety orange | `#e8641b` | Working tools and hazard parts |
| Gold | `#c9a227` | Insulation wraps, solar cells, lenses and small accents |

- Painted metal with a soft satin finish. Gold is satin, non-mirror: a soft painted sheen, never polished reflective metal. In B9 a metallic gold rendered pure black on its shaded side, because space has nothing for it to reflect. Gold is smooth, with no wrinkles, because fine creases come out ragged in 3D.
- Crisp machined edges, no hand-moulded lumps. Collars, bands, ribs, rims and grooves are true circles and straight lines, evenly thick all the way round. B9's were lumpy.
- A colour block is never narrower than about a twentieth of the part's length.

**Mood**
- Clean, bright and well kept. No rust, grime, scorch marks or battle damage.

**Never**
- People, seats, cockpits, windows, ladders, handrails or hatches. The craft are crewless.
- Lattices, grilles, mesh, thin rails, pipes, cables, antennas or fine vents.
- Stripes, decals, logos, lettering, numbers or warning marks.
- Moving parts, open doors, or visible interiors. A part that turns rotates as a whole, so each model is one solid mesh, and backs are simple closed shells.
- Anything copied from an existing game, film or real spacecraft. All designs are original.

**Connectors.** Every brief lists its connector spots from `data/modules.json`: position in metres from the origin and facing. TRELLIS bends flat faces, so image-to-3d flattens each mounting face onto an exact plane after generation, and Agent B checks in Godot that each face is flat and sits on its data connector. The list is generated from data, so rerun the brief generator if connectors change.

## Triangle budget

The target must be set before generation, because reducing a model afterwards has shattered its textures.

| Kind | Target |
| ---- | ------ |
| Root parts, such as hulls | 12000 triangles |
| Modules, and the small drone hull | 6000 triangles |

A ship of 13 parts then comes to about 84000 triangles. B9 confirmed these targets: 11628 and 5875 triangles, with textures intact.

## Placement

Each brief has a placement line, which image-to-3d applies after generation. Models are delivered on the data origin, not centred on their bounding box, so the client places them with no per-model offset.

| Kind | Origin | Facing |
| ---- | ------ | ------ |
| Hulls | Centre of the flat bottom face | Up is +Y |
| Side-mounted parts | Centre of the mounting plate's back face | Plate faces -Z, part extends along +Z, up is +Y |
| Parts hanging below a stack (thruster, tank) | Centre of the top mounting face | Mount faces +Y, part extends along -Y |
| Parts standing on a stack (docking port) | Centre of the bottom mounting face | Mount faces -Y, part extends along +Y |

## Style test (task B9)

The test passed on 2026-11-05, with fixes carried into B12. Its models are in `assets/models/` and are kept as test pieces. B12 replaces both with versions built from the revised briefs. It built these two models:

| Model | Brief | Why this one |
| ----- | ----- | ------------ |
| `starter_hull` | [starter_hull.md](starter_hull.md) | Largest single part. Off-white body on a white picture is the main risk. |
| `mining_laser_mk1` | [mining_laser_mk1.md](mining_laser_mk1.md) | Small, bright, solid colour, with a clear silhouette. |

Checks on the delivered models:

| Check | Pass means |
| ----- | ---------- |
| Style | Both read as the same family of chunky, clean hardware. |
| Off-white edges | The hull's outline is complete. No bites, holes or white halo where the body met the background. |
| Colour blocks | Bands stay distinct, with clean edges rather than ragged ones. |
| Triangles | Each model is at or under its target, with textures intact. |
| Solidity | One closed mesh per model, with no floating pieces or thin shards. |
| LOD | Godot's automatic LOD does not shatter the texture. |
| In place | Scaled from the size in its brief, the model sits on its connectors in `data/` and looks right beside a placeholder at game camera distance. |

Results: style, off-white edges, colour blocks, triangles and LOD passed. Each model is built from separate touching patches rather than one closed mesh, which is fine because collision comes from `data/`. Under forced LOD, light slivers show where the patches part, so keep Godot's default LOD threshold. The owner then judged the hull too barrel-like, so B12 hulls are faceted and plated. The fixes for B12 are hull shape, gold satin, crisp edges, sizes held to the data, connector rows clear of bands, and placement on the data origin.

## Batch B12

18 models, one brief each, in priority order:

| # | Model | Target |
| - | ----- | ------ |
| 1 | [starter_hull](starter_hull.md) | 12000 |
| 2 | [small_hull](small_hull.md) | 6000 |
| 3 | [command_hub](command_hub.md) | 12000 |
| 4 | [chemical_thruster_mk1](chemical_thruster_mk1.md) | 6000 |
| 5 | [docking_port_mk1](docking_port_mk1.md) | 6000 |
| 6 | [propellant_tank_mk1](propellant_tank_mk1.md) | 6000 |
| 7 | [battery_bank_mk1](battery_bank_mk1.md) | 6000 |
| 8 | [fabricator_mk1](fabricator_mk1.md) | 6000 |
| 9 | [goods_storage_mk1](goods_storage_mk1.md) | 6000 |
| 10 | [ore_storage_mk1](ore_storage_mk1.md) | 6000 |
| 11 | [ore_container_mk1](ore_container_mk1.md) | 6000 |
| 12 | [ore_refinery_mk1](ore_refinery_mk1.md) | 6000 |
| 13 | [heat_radiator_mk1](heat_radiator_mk1.md) | 6000 |
| 14 | [solar_panel_mk1](solar_panel_mk1.md) | 6000 |
| 15 | [solar_farm_mk1](solar_farm_mk1.md) | 6000 |
| 16 | [lidar_mk1](lidar_mk1.md) | 6000 |
| 17 | [mining_laser_mk1](mining_laser_mk1.md) | 6000 |
| 18 | [landing_legs_mk1](landing_legs_mk1.md) | 6000 |

Not in this batch:
- The two cores, which sit hidden in a hull's core slot.
- The `small_` versions of modules. Each is a later batch, or the client scales its full-size model.

**GPU memory:** the B9 hull ran out of GPU memory at the usual settings and only built with `max_num_tokens` 32768. Expect the same for the large parts: both hulls, the command hub, fabricator, both storage modules, the refinery and the solar farm. Starting them at that limit saves a failed run.

## Request and delivery

A request is one message to the image-to-3d session giving the path to these briefs. The owner has given standing permission to send requests, so none waits for approval. The image-to-3d side creates `C:\Users\simon\PROGRAMING\newmanprobe-wt\GPU_HOLD` before it uses the GPU and removes it afterwards. While the file exists, `tools/test.ps1` refuses to run and no agent here starts Godot. Models arrive as `.glb` files in `image-to-3d/data/props/out/newmanprobe/` with a check sheet, and Agent B copies them into `assets/`. Models are visual only: size, mass, collision and attachment all come from `data/`.
