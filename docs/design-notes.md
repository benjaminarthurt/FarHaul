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

## Built: cargo sections

Far Haul is a freight game, so cargo capacity is part of the builder from the start.

- Two modules in their own palette group (`group` on `ModuleDef`: hull, cargo, external):
  - **Cargo hold 1x2**: pressurised and walkable. Doors at both ends, containers along both sides of
    a 1.4 m aisle. 4 slots, 24 t. Protected, reachable from inside.
  - **Cargo rack 1x2**: open gantry bolted to the hull, 4 full-size containers, 40 t. Cheaper and
    lighter per tonne, but exposed (the concept doc's atmosphere, damage and EVA ideas hook in here).
- Each module declares `cargo_slots` and `cargo_capacity` (tonnes when full).
- `ShipStats.compute(ship, cargo_load)`: load runs 0 to 1. Cargo mass is spread at each module's
  centre, so a lopsided rack shifts the centre of mass. Reports capacity, cargo mass, loaded mass, and
  thrust/weight empty and loaded. Warning if the ship has no cargo capacity.
- **Manifest** (`CargoManifest`, plain data like the ship): every cargo module has `cargo_slots`
  equal containers. A container holds one commodity and can be part full, so a location with less
  freight than the ship has room for is a normal case, not an error.
- Loading `load(commodity, tonnes)` returns how much actually went aboard (never more than fits).
  It tops up part-full containers of that commodity first, then opens empty ones. Unloading takes
  from the least full containers first so loads consolidate.
- Containers are keyed by module origin cell and slot number, so they survive edits to other modules.
  A module holding cargo can't be removed until unloaded. Saves carry the manifest; entries that no
  longer fit the ship are dropped or clamped on load.
- Stats take the manifest: cargo mass, loaded mass, centre of mass (cargo sits at its module), thrust
  to weight empty and loaded, containers in use, cargo value. Without a manifest `compute` can still
  assume a fraction full, for what-if checks.
- Builder: CARGO panel with a commodity picker, a Tonnes box, Load, Unload, Unload all. In the 3D
  view containers are coloured by commodity and as tall as they are full.
- Commodities (`CommodityLibrary`) are placeholders: water, iron ore, food, machinery, electronics,
  with flat prices per tonne.
- Not modelled yet: volume versus mass limits, hazardous or perishable goods, per-location supply and
  prices (the Tonnes box stands in for a market), and contracts.

## Built: look and feel (placeholder art pass)

Everything is generated in code, so there are no image assets yet.

- Industrial palette: dark muted hulls, neutral trim on every cell edge, warm accents.
- Procedural plating texture (seams, rivets, scuffs, grime) mapped in object space so panel size stays
  constant on any box. Hazard-stripe thresholds on every doorway. Corrugated containers with corner
  castings, stencilled with the commodity name. "FUEL" on tanks.
- Lit details: cockpit canopy, reactor vents, engine throat, floor strips in big rooms.
- Sky: stars plus a faint nebula from a small sky shader. Filmic tone mapping and glow so lit parts bloom.
- Lighting: warm key light with shadows, cool fill without. Shadows are fine for the small builder scene
  but need a budget in flight and on planets; check performance on the Surface Pro.
- Real art later: set `scene` on a module to replace its generated look. Containers keep working if the
  scene tags container nodes with the same `slot`, `height` and `bottom_y` metadata.

## Built: the shipyard loop

The builder is a small game on its own, so it can be played and judged before flight exists.

- **Credits**: 150,000 to start. Credits = start funds + profit - cost of the ship, so there is nothing to
  keep in sync. Removing a part refunds it fully. Can't place what you can't afford.
- **Sealed hull and airlock**: a doorway onto space (empty cell or an external part) is a hull breach, shown
  as a pulsing cyan ring. The airlock module is the crew's way out, which the later EVA work needs anyway.
- **Contracts** (`Contracts`): five freight jobs, each with a commodity, tonnes on offer, rate per tonne and a
  minimum loaded thrust-to-weight. If the ship can't carry the lot it takes what fits and is paid for that.
  A checklist shows what's missing: cockpit, engines, sealed hull, airlock, power, cooling, T/W, cargo.
- **Run contract**: a stand-in for flight. If every box is green the ship launches, the cargo is delivered and
  the pay is added to profit. This is the loop to replace with real flight.
- **Starter hauler** (`ShipPresets`): built through the normal rules, passes every check, leaves about 57k.
- **UX**: auto-rotate to a rotation that fits, a cursor tooltip with the reason or the cost, undo/redo (whole-ship
  snapshots), eased camera and frame-ship, hide upper decks, parts pop into place, synthesised sounds, autosave.
- Numbers are placeholders. In particular a cargo rack is very cheap per tonne, which will want a downside
  (exposure to damage or heat) once those systems exist.

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

- Locations with limited, changing supply and prices, and freight contracts. Today the player types
  how many tonnes a location "offers".
- Money loop (Freight, Profit, Ship): modules already carry a `cost`, but there is no economy yet.
- Atmospheric ships versus space-only ships need extra module attributes (heat protection,
  landing gear, structural limits).
- Crew, life support and consumables from the concept doc are not modelled yet.
- Damage by location: pressure loss, bulkheads sealing compartments. The door graph the builder
  already computes is the starting point.
