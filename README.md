# Ship Builder (Godot 4 starter)

A grid-based spaceship builder. Pick a prefab section, rotate it, and click to snap it onto
the ship. The ship is stored as plain data, so flight, interior walking and space walks can
all be built on top of the same thing later. A live panel shows the ship's engineering numbers.

Requires **Godot 4.3 or newer** (developed and tested on 4.4.1). The project uses the
Compatibility renderer, which is the safest choice for integrated GPUs and ARM Surface devices.

## Run it

1. Open Godot, click Import, and choose `project.godot` in this folder.
2. Press F5.

## How to play

You start with a small hauler and 150,000 credits.

1. **Build.** Parts cost credits (refunded in full if you remove them). The ghost is green if it fits and
   red with the reason if not. If your current rotation doesn't fit, it turns to one that does. Cyan
   rings mark open doorways: cap them so the hull is sealed.
2. **Pick a contract** (bottom panel), press **Take on cargo**, and make every requirement go green.
3. **Run contract.** The ship launches, delivers and you are paid. Spend it on a bigger, faster ship.

A ship needs a cockpit, an engine, a sealed hull, an airlock, enough power and cooling, and enough
thrust-to-weight when loaded. Your progress autosaves.

## Controls

| Input | Action |
|---|---|
| Left click | Place the ghost module (green = valid, red = invalid) |
| Shift + left click | Remove the module under the cursor |
| R | Rotate 90 degrees |
| 1-9, 0 or `[` `]` or palette buttons | Choose a module |
| Q / E | Move build deck down / up |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| F | Frame the whole ship |
| H | Hide decks above the current one |
| M | Mute sound |
| F1 | Show the welcome help |
| Right-drag | Orbit camera |
| Middle-drag or arrow keys | Pan |
| Mouse wheel | Zoom |
| S / L / C | Save / load / clear (saved to `user://ship.json`) |

## Modules

Hull (pressurised, walkable, connect with doors): corridor, corner, T-junction, ladder shaft,
2x2 room, cockpit, engineering (reactor), airlock (the crew's way in and out, with an outer hatch).

Cargo: **cargo hold 1x2** (pressurised and walkable, containers stacked along both sides of a
1.4 m aisle, 4 slots, 24 t) and **cargo rack 1x2** (open gantry carrying 4 full-size containers
outside, 40 t, cheap and light but exposed). Holds chain through doors, racks bolt on like any
external part.

External (bolt-on): frame, 1x2 fuel tank, radiator, engine.

## Rules

- A new module must not overlap existing cells.
- After the first module, it must attach to the ship: a door lining up with a matching door,
  or a mount point touching a mount point.
- External parts also bolt onto any bare hull face of a pressurised module, but not over a doorway.
- Removing a module is refused if it would split the ship into disconnected pieces, or if it still holds cargo.
- A doorway that opens onto empty space or an external part is a hull breach: fit a module to cap it.
- Ship front is -Z. One cell is 3 m.

## Cargo: loading and unloading

The CARGO panel (bottom right) loads and unloads freight so you can see how a real load changes the
ship. Pick a commodity, set Tonnes, then:

- **Load**: Tonnes is what the location has on offer. As much as fits goes aboard. If the location
  has less than you have room for, the spare space simply stays empty (partly full containers are fine).
- **Unload**: delivers that many tonnes of the chosen commodity.
- **Unload all**: empties the ship.

Each container holds one commodity. Loading tops up part-full containers of the same commodity before
opening empty ones; unloading empties the least full containers first. Containers in the 3D view are
coloured by commodity and as tall as they are full, and empty ones disappear. A module that still holds
cargo can't be removed: unload it first. Cargo is saved and loaded with the ship.

## Ship stats panel

Mass, cost, fuel, cargo capacity and what is aboard, thrust, thrust-to-weight (empty and loaded), power and
heat balance, and centre of mass. The yellow ball in the scene marks the centre of mass (balance
is judged with tanks full and the cargo actually loaded). Warnings appear for: no cockpit,
power shortfall, more heat than cooling, engines not pointing aft, thrust line far from the
centre of mass, and no cargo capacity. Units: tonnes, credits, kW, kN, metres.

The numbers are placeholders to get the loop working. Edit them in `scripts/module_library.gd`.

## Layout

| File | What it does |
|---|---|
| `scripts/ship_grid.gd` | Cell size, rotation maths, cell/world conversion |
| `scripts/module_socket.gd` | A connection point: cell, direction, kind (door or mount) |
| `scripts/module_def.gd` | One prefab type: footprint, sockets, stats, placeholder visuals |
| `scripts/module_library.gd` | The catalogue (13 placeholder modules defined in code) |
| `scripts/commodity_library.gd` | What can be hauled (placeholder goods and prices) |
| `scripts/cargo_manifest.gd` | What is aboard, per container: load, unload, capacity, value |
| `scripts/surface_textures.gd` | Procedural plating and hazard-stripe textures (no image assets) |
| `scripts/space_sky.gd` | Procedural star and nebula sky shader |
| `scripts/contracts.gd` | Freight jobs and the checklist a ship must pass to run one |
| `scripts/ship_history.gd` | Undo and redo snapshots |
| `scripts/ship_presets.gd` | Ready-made ships (the starter hauler) |
| `scripts/sfx.gd` | Synthesised sound effects |
| `scripts/ship_data.gd` | The ship as data: placement rules, removal, JSON save/load |
| `scripts/ship_stats.gd` | Mass, centre of mass, power, heat, thrust, warnings |
| `scripts/ship_view.gd` | Builds 3D nodes from `ShipData` |
| `scripts/builder.gd` | Camera, ghost, input, UI |
| `tests/test_ship.gd` | Headless tests for the rules and stats |

Run the tests:

- Rules and stats: `godot --headless --script res://tests/test_ship.gd`
- Whole builder, a full play loop: `FARHAUL_NOSAVE=1 godot --headless --script res://tests/smoke_builder.gd`
  (the variable stops tests touching your autosave)

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
3. Real locations with limited, changing supply and prices (the Load button's Tonnes box stands in
   for that), then flight with a floating origin.
