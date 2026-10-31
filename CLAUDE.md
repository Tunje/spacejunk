# Newman Probe

3D space automation game in Godot 4.7.2 and statically typed GDScript. "Newman Probe" and "spacejunk" are both placeholder names.

Read `plan/workplan.md` before starting a task. `docs/design/contracts.md` is the authority on how systems talk to each other.

## Rules

- Work in your own git worktree under `C:\Users\simon\PROGRAMING\newmanprobe-wt\<role>`, never in the main checkout. Roles: `kernel`, `design`, `gameplay`, `client`.
- One branch per task, named `<role>/<task-id>`. Only the Lead merges to `main` and pushes.
- Edit only the folders your role owns (workplan section 5). Ask the owner for changes elsewhere. Only the Lead edits `project.godot`.
- Contracts change only through the Lead.
- A task is done when `tools/test.ps1` passes on its branch, its acceptance check holds, and new behaviour has tests.
- Client work also needs a screenshot read back by the agent.
- If blocked for more than a short attempt, report to the Lead (session `newmanprobe-14`) rather than work around it.

## GPU holds

The image-to-3d pipeline needs the GPU alone, and any Godot process, even headless, can corrupt its output. Never run Godot while `C:\Users\simon\PROGRAMING\newmanprobe-wt\GPU_HOLD` exists or after the Lead says stop. `tools/test.ps1` checks this file; check it yourself before running Godot any other way. Keep doing non-Godot work during a hold.

## Simulation code

- `sim/` is `RefCounted` typed GDScript with no Node or SceneTree references.
- All simulation state is integer. Follow the units and rounding rules in the contracts.
- Never iterate a Dictionary in simulation code without sorting its keys first.
- Content is data in `data/`. A new component should not need a new script.
- Generated 3D models are visual only. Nothing in the simulation reads them.
- The 3D look is in the style of Kerbal Space Program, using original designs only.
