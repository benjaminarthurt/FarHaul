# Ship Builder (Godot 4 starter)

A grid-based spaceship builder. Pick a prefab section, rotate it, and click to snap it onto
the ship. The ship is stored as plain data, so flight, interior walking and space walks can
all be built on top of the same thing later. A live panel shows the ship's engineering numbers.

Requires **Godot 4.3 or newer** (developed and tested on 4.4.1). The project uses the
Compatibility renderer, which is the safest choice for integrated GPUs and ARM Surface devices.

## Run it

1. Open Godot, click Import, and choose `project.godot` in this folder.
2. Press F5.

## Controls

| Input | Action |
|---|---|
| Left click | Place the ghost module (green = valid, red = invalid) |
| Shift + left click | Remove the module under the cursor |
| R | Rotate 90 degrees |
| 1-9, 0 or `[` `]` or palette buttons | Choose a module |
| Q / E | Move build deck down / up |
| Right-drag | Orbit camera |
| Middle-drag or arrow keys | Pan |
| Mouse wheel | Zoom |
| S / L / C | Save / load / clear (saved to `user://ship.json`) |

## Modules

Hull (pressurised, walkable, connect with doors): corridor, corner, T-junction, ladder shaft,
2x2 room, cockpit, engineering (reactor).

External (bolt-on): frame, 1x2 fuel tank, radiator, engine.

## Rules

- A new module must not overlap existing cells.
- After the first module, it must attach to the ship: a door lining up with a matching door,
  or a mount point touching a mount point.
- External parts also bolt onto any bare hull face of a pressurised module, but not over a doorway.
- Removing a module is refused if it would split the ship into disconnected pieces.
- Ship front is -Z. One cell is 3 m.

## Ship stats panel

Mass, cost, fuel, thrust, thrust-to-weight, power and heat balance, and centre of mass. The
yellow ball in the scene marks the centre of mass (balance is judged with tanks full). Warnings
appear for: no cockpit, power shortfall, more heat than cooling, engines not pointing aft, and
thrust line far from the centre of mass. Units: tonnes, credits, kW, kN, metres.

The numbers are placeholders to get the loop working. Edit them in `scripts/module_library.gd`.

## Layout

| File | What it does |
|---|---|
| `scripts/ship_grid.gd` | Cell size, rotation maths, cell/world conversion |
| `scripts/module_socket.gd` | A connection point: cell, direction, kind (door or mount) |
| `scripts/module_def.gd` | One prefab type: footprint, sockets, stats, placeholder visuals |
| `scripts/module_library.gd` | The catalogue (11 placeholder modules defined in code) |
| `scripts/ship_data.gd` | The ship as data: placement rules, removal, JSON save/load |
| `scripts/ship_stats.gd` | Mass, centre of mass, power, heat, thrust, warnings |
| `scripts/ship_view.gd` | Builds 3D nodes from `ShipData` |
| `scripts/builder.gd` | Camera, ghost, input, UI |
| `tests/test_ship.gd` | Headless tests for the rules and stats |

Run the tests: `godot --headless --script res://tests/test_ship.gd`

## Swapping in real art

Make a scene for a module (a hollow room built in Blender, say), then set `scene` on that
module's `ModuleDef`. Keep it inside its cell footprint and line its doorways up with the
sockets. Nothing else needs to change.

## Docs

- [docs/far-haul-concept.md](docs/far-haul-concept.md): the full game concept (Far Haul).
- [docs/design-notes.md](docs/design-notes.md): technical decisions, build order, and plans.

## Next steps

1. Walk-through mode: spawn a character in the built ship, parented to the ship node.
2. Add collision to modules (floor and walls) so walking has something to stand on.
3. Cargo containers as placeable objects, then flight with a floating origin.
