# Newman Probe model briefs

Text briefs for the image-to-3d pipeline, one file per model. Codex draws each picture from its brief, and TRELLIS.2 builds the model from that one picture. No images are made or supplied here.

**Project:** a crewless space automation game. Every craft is built from separate parts stacked and bolted together, and a part may appear hundreds of times, so each one must read clearly at a glance.

## Shared style

This applies to every brief. Each brief also repeats what Codex needs, so it can be used alone.

**Shape**
- Chunky, rounded industrial hardware: cylinders, short tapers, tanks, thick flanged joints and bolted-on boxes.
- Slightly oversized and simplified. A part should look sturdy and a little toy-like in its proportions, while still believable as real machinery.
- Identity comes from the silhouette. Someone should be able to name a part from its outline alone.
- Each part ends in a thick collar or flange, which hides small gaps where parts join.

**Colour**
- Simple solid blocks, in four colours only:

| Colour | Hex | Use |
| ------ | --- | --- |
| Off-white | `#e8e4d8` | Main bodies and tanks |
| Mid grey | `#8a8d91` | Collars, flanges, machinery |
| Safety orange | `#e8641b` | Working tools and hazard parts |
| Foil gold | `#c9a227` | Insulation wraps and small accents |

- Painted metal with a soft satin finish. The foil is smooth, with no wrinkles, because fine creases come out ragged in 3D.
- A colour block is never narrower than about a twentieth of the part's length.

**Mood**
- Clean, bright and well kept. No rust, grime, scorch marks or battle damage.

**Never**
- People, seats, cockpits, windows, ladders, handrails or hatches. The craft are crewless.
- Lattices, grilles, mesh, thin rails, pipes, cables, antennas or fine vents.
- Stripes, decals, logos, lettering, numbers or warning marks.
- Moving parts, open doors, or visible interiors. A part that turns rotates as a whole, so each model is one solid mesh, and backs are simple closed shells.
- Anything copied from an existing game, film or real spacecraft. All designs are original.

## Triangle budget

The target must be set before generation, because reducing a model afterwards has shattered its textures.

| Kind | Target |
| ---- | ------ |
| Root parts, such as hulls | 12000 triangles |
| Modules | 6000 triangles |

A ship of 13 parts then comes to about 84000 triangles. These targets are proposals, and the style test decides whether they hold.

## Style test (task B9)

No batch is requested until this test passes. It builds these two models only:

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

If the test fails, the owner chooses between a heavier triangle budget and hand-made or kitbashed models.

## Request and delivery

A request is one message to the image-to-3d session giving the path to these briefs. The owner has given standing permission to send requests, so none waits for approval. The image-to-3d side creates `C:\Users\simon\PROGRAMING\newmanprobe-wt\GPU_HOLD` before it uses the GPU and removes it afterwards. While the file exists, `tools/test.ps1` refuses to run and no agent here starts Godot. The full batch after this test is task B12. Models arrive as `.glb` files in `image-to-3d/data/props/out/newmanprobe/` with a check sheet, and Agent B copies them into `assets/`. Models are visual only: size, mass, collision and attachment all come from `data/`.
