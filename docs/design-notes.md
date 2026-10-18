# Design notes

Decisions and reasoning from planning the game, first written 2026-09-30; the build order is kept current. The game itself is described in
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

1. Ship builder using pre-built sections (**built**)
2. Flying the ship in 3D, with local runs and star jumps (**built**)
3. Walking inside the ship, compartment to compartment, and the ports (**built**, rough)
4. Landing on moons and exploring on foot (**built**, rough)
5. Space walks, tethered to the ship, doing repairs (**built**, rough)
6. Crew: hire, fire and put to work (**built** in 0.9.0, rough)
7. Other ships and derelicts, with salvage panels and cargo holds (**built** in 0.10.0 to 0.10.2)
8. The trade report: the economy simulation made visible (**built** in 0.11.0)
9. Fitting salvaged parts, at their condition, for a fitting fee (**built** in 0.12.0)
10. Boarding derelicts: the log, the flight recorder, the crew and the odd survivor (**built** in 0.13.0)
11. Manufacturers: makers' versions of the external parts, cheaper at home (**built** in 0.14.0; the
    shipyard compares them side by side in 0.14.1)
12. Bigger holds and passenger cabins in three sizes; passengers local and long-haul, riding along
    with freight (**built** in 0.15.0)
13. The radio: clearance to dock and land, other ships (fuel, news, tows), distress calls, and voices
    made in code (**built** in 0.16.0); rival salvage crews and claim beacons (**built** in 0.16.1); the fixed
    lines recorded with Chatterbox, every variation, five species' voices (**built** in 0.16.2)

The ship builder came first because everything else reads from the ship it produces.

### Next, in roughly this order (planned)

14. **Frontier growth**: every site grows when it's kept supplied and shrinks when it isn't, down to
    abandoned; systems follow their sites, slower (**built** in 0.17.0, see below).
15. **Danger without combat**: debris fields on routes, solar storms that cook radiators, and
    claim-jumpers at derelicts. Risks to plan around rather than fights (**built** in 0.18.0, see
    below).

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

## Recorded voices (0.16.2)

- **Record everything fixed, speak no names.** Every comms and passenger line is recorded in every
  variation of its small value sets (berth 2 to 14, the fines, tonnes, crew, problem, species); names
  of ships, places and prices are left out of the spoken line and stay in the subtitle. 1,260 lines, 58
  speakers, 2,633 clips, 85 MB of OGG. Takes are accepted on Whisper's check alone once a voice has been
  listened to and approved; a new voice, setting or kind of line gets listened to again.
- **Licensed reference voices only.** VCTK and LibriTTS-R (CC BY 4.0, credited in Settings, the README
  and the site), not anyone's own voice or recordings scraped from elsewhere.
- **Species by processing, not casting.** Kesh lower and slower, Ilyan higher and quicker, Vey and Orun
  nearer human, done after generation. Praat's PSOLA ("Change gender", with a formant shift) keeps the
  words; a phase vocoder (librosa) blurred them so badly the first overnight run was redone (Whisper's
  error rate on a shifted human clip: 35% against 2%).
- **Checked by ear and by machine.** Each take is timed and transcribed (faster-whisper) after the
  species shift; bad ones are re-rolled up to three times, and doubtful ones listed for a person to hear.
- **Clean clips, radio in the mix.** The transmitter is an audio bus, so distance can change it per call
  and the same clips work aboard (passengers) unfiltered.
- **Aliens sound alien without losing the words.** Three layers, none of which blur the English: their
  own wording (Kesh duty, Ilyan economy, Vey community, Orun "we", from cultures.json), a translator
  conceit (a second of their own language and a chirp before the English), and a sound per species done
  live on audio buses (octave layers, phaser, chorus, reverb) so it can be tuned without re-recording.
- **The babble stays.** Anything unrecorded, and players who prefer it, get the generated voices.

## Frontier growth (0.17.0)

Decided with Ben, 2026-10-18:

- **The economy drives it, not a script.** Every site (the main port, fuel depot, moon station, belt
  works, moon base pad, mining camp, Sol's outer stations) has a size, and a size has a demand: tonnes
  a day it needs brought in. Each day the site is supplied by the NPC traffic of its system and by you.
  Supplied better than it needs, it grows; worse, it shrinks. The NPC share follows the system's real
  supply health in the economy simulation (what share of its demand its shelves met, against what they
  met when the game began), times a slow per-site fortune (good months and bad months), and falls off as
  a site outgrows what the traffic is used to serving.
- **What you do counts in full.** Every tonne you deliver to a site, or carry away from it, is supply
  on top of the NPCs'. Small sites need little, so hauling exclusively to Luna grows it in weeks.
- **No caps.** A site can grow past the biggest concourse the game draws, and its demand keeps rising.
  It can also shrink to nothing: below the lowest stage it is **abandoned**. Its people leave, its desks
  close, its freight stops, and what's left can be stripped for salvage. The pumps still work. An
  abandoned site can be resettled if its system booms.
- **Growth sticks, slowly.** What the traffic is used to serving drifts toward what a site actually is,
  over about three months. Grow a site and the haulers learn to keep it fed; let it decline and they
  learn to stop coming.
- **Sites fast, systems slow.** A system's own size moves toward its canon size plus half its sites'
  average growth, and toward better or worse supply health, over about a month. A system's size scales
  everything its works make and its exchange uses in the economy simulation, so a growing system ships
  and needs more freight, and if the haulers can't keep up, it stalls.
- **Stages** are the canon tiers, plus abandoned: abandoned, extreme frontier, frontier, outer,
  developed, core. Each site starts at its canon tier (the system's for its port, a step down for its
  stations, two down for the pad and the camp).
- **What a stage gives.** Freight, fuel and repairs from extreme frontier up, passengers from frontier,
  crew for hire from outer, and fuel and repairs 5% cheaper per stage above outer, dearer below it. A main port
  keeps its shipyard while anyone lives there (new games start at one); any other site opens one at
  core. The concourse's size, crowd
  and wear follow the stage, and so do the moon base's domes and the camp's huts.
- **Seen in three places.** The trade report has a Growth page (every site's stage, which way it's
  going, how well it's supplied and your share, and what changed lately); the place itself; and the
  radio's news.
- **Only in a game.** The economy's own calibration tests run without it, so its bands are unchanged.

## Danger without combat (0.18.0)

Decided with Ben, 2026-10-18:

- **Debris fields** lie across some routes: local hops and interstellar lanes, each field placed from
  the route and the month, so the same field is there all month and gone or moved the next. Flying a
  run yourself, you see it ahead (a cloud of rock with a marker) and can go round it, slow down, or
  let the autopilot fly it. Inside, hits come at a rate that grows with speed, and each hit hurts more
  the faster you're going. With the autopilot flying (course hold or stop-at-target), the rate is about
  a third: it dodges what it can see. Runs flown entirely on autopilot from the desk roll the same field
  at the autopilot's rate.
- **Solar storms** come and go in each system on a schedule of their own, a day or two long, frontier
  stars more often. Some are forecast a day or three ahead (radio news, the trade report, the port's
  notices); some only show on the ship's own sensors a few hours out; some arrive unannounced. Always
  some chance of being caught. In port you're shielded. Out in one, radiators cook (wear, and less
  cooling while it lasts) and the hull takes a little.
- **The local economy feels storms.** While a system has one, its haulers hold in port (no departures
  to or from it in the economy simulation) and its sites get almost nothing from them, so shelves dip
  and, through frontier growth, outposts feel it. Traffic control advises holding.
- **Claim-jumpers.** Some rival salvage crews don't care whose beacon is on a wreck. They come to yours,
  won't split, won't leave when told, and cut faster. You can report them: sometimes a patrol is near
  and they run; either way, if your beacon was first, the port authority pays a bounty on what they
  took and your standing goes up.

## Open questions and next ideas

- Locations with limited, changing supply and prices, and freight contracts. Today the player types
  how many tonnes a location "offers".
- Money loop (Freight, Profit, Ship): modules already carry a `cost`, but there is no economy yet.
- Atmospheric ships versus space-only ships need extra module attributes (heat protection,
  landing gear, structural limits).
- Crew, life support and consumables from the concept doc are not modelled yet.
- Damage by location: pressure loss, bulkheads sealing compartments. The door graph the builder
  already computes is the starting point.
