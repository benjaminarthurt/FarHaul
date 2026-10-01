# Design notes

Decisions and reasoning from planning the game, as of 2026-09-30. The game itself is described in
[far-haul-concept.md](far-haul-concept.md); this file is about how we're building it.

Status key: **Built** is in the code and tested. **Planned** is the intended approach, not built
or validated yet.

## Goals and constraints

- A first-person sci-fi open-world game with procedurally generated worlds (see the concept doc).
- Must run and look good on a standard laptop or a Surface Pro. Not aiming for AAA graphics.
- Stylised, low-poly, flat-shaded art direction, which hides a lot on integrated GPUs and fits the
  industrial look in the concept doc.
- Engine: **Godot 4** (free and lightweight). Currently uses the Compatibility renderer, with no
  real-time shadows.
- Newer Surface Pros often use Snapdragon (ARM) chips, so test builds on the actual device early.

## Build order

Not all at once. In the order requested:

1. Ship builder using pre-built sections (**prototype built**)
2. Flying the ship in 3D
3. Walking inside the ship, compartment to compartment
4. Landing the ship on a planet and exploring it
5. Space walks, tethered to the ship, doing repairs

The ship builder comes first because everything else reads from the ship it produces.

## Built: ship builder architecture

- **The ship is plain data**: a list of `{id, cell, rot}`. No 3D nodes in it. Saving is JSON.
  Flight, interior walking, NPC ships and sharing all start from this same data.
- **Grid**: cells are 3 m cubes. Y is up, ship front is -Z. Rotation is in quarter-turns about Y,
  done by a single helper so data and visuals always agree.
- **Modules** are `ModuleDef` resources: footprint in cells, connection sockets, engineering stats,
  and a visual. Multi-cell modules (such as the 2x2 room) are supported.
- **Sockets** come in two kinds:
  - `door`: walkable connection between pressurised modules. Doors mate with facing doors.
  - `mount`: structural bolt-on point for external parts. Mounts mate with facing mounts, and also
    with any bare hull face of a pressurised module, but never over a doorway.
- **Placement rule**: no overlapping cells, and after the first module, the new one must attach to
  the ship through a door or mount.
- **Removal rule**: refused if it would split the ship into disconnected pieces.
- **Walkable from day one**: pressurised modules are hollow rooms with real doorways, so a ship
  built in the editor is already a navigable interior when walking is added.
- **Placeholder art**: the visuals are generated in code. Real art is swapped in by setting
  `scene` on a module definition, with no other changes.
- **Tests**: headless rule and stats tests in `tests/test_ship.gd`.

## Built: ship stats model

Units are tonnes, credits, kW, kN and metres. All numbers are placeholders to tune in
`scripts/module_library.gd`.

- Mass, cost, power (positive generates, negative consumes), heat (positive is waste heat,
  negative is cooling), thrust, fuel capacity.
- Centre of mass is computed with tanks full and shown as a marker in the builder.
- Warnings: no cockpit, power shortfall, more heat than cooling, engines not pointing aft, and thrust
  line far from the centre of mass. The last one stands in for the concept doc's idea that an
  unbalanced ship burns extra manoeuvring propellant.

## Planned: walking inside the ship

- Add collision to module floors and walls.
- Parent the player to the ship, moving in the ship's local space while the ship flies around.
- Use artificial gravity, so nothing needs floating simulation indoors.

## Planned: flight

- Ship as a rigid body (Godot ships with the Jolt physics engine), with thrust taken from the
  stats model.
- A **floating origin**: shift the world back toward zero as the ship travels, because
  floating-point precision breaks down far from the origin and causes jitter.

## Planned: planets

- **Flat, not a sphere**: an effectively infinite landscape. Dramatically simpler than a
  planet-scale sphere, and fine for a first version.
- Terrain generated in chunks around the player from a seeded noise function (the same seed gives
  the same world, so nothing needs storing), loaded and unloaded as the player moves.
- Build chunk meshes on background threads. Main-thread generation causes stutter, the most common
  problem in open-world games.
- Level of detail for distant chunks, and GPU instancing (MultiMesh) for rocks, plants and props so
  thousands cost one draw call.
- Cheap atmosphere (skybox, fog, colour grading) sells "alien planet" more than detailed geometry.
- **Space to planet**: no seamless descent, which is extremely hard. Use a fast fade and a scripted
  entry sequence into a separate planet scene.
- Scope: procedural worlds are easy to make big and hard to make interesting. Start with one biome
  and one core loop, and let the world grow around it.

## Planned: space walks

- A jointed rope tether plus zero-g movement. It sounds hardest but is the most self-contained, so
  it goes last.

## Open questions and next ideas

- Cargo containers as placeable, standardised objects (central to the concept doc's freight loop).
- Money loop (Freight, Profit, Ship): modules already carry a `cost`, but there is no economy yet.
- Atmospheric ships versus space-only ships need extra module attributes (heat protection,
  landing gear, structural limits).
- Crew, life support and consumables from the concept doc are not modelled yet.
- Damage by location: pressure loss, bulkheads sealing compartments. The door graph the builder
  already computes is the starting point.
