# Far Haul

*Build your ship. Haul the freight. Push the frontier.*

Far Haul is a first-person sci-fi freight, ship-building and exploration game. This repo is the
playable ship-builder prototype: a grid-based spaceship builder. Pick a prefab section, rotate it, and click to snap it onto
the ship. The ship is stored as plain data, so flight, interior walking and space walks can
all be built on top of the same thing later. A live panel shows the ship's engineering numbers.

Requires **Godot 4.4** (developed and tested on 4.4.1). Far Haul is a Windows desktop game and uses
the **Forward+** renderer (Vulkan, with Direct3D 12 available). On machines without Vulkan it falls back to
OpenGL. Graphics quality (Low, Medium or High) and the other settings are on the title screen's Settings
page; they are saved beside the saves.

## Run it

**Quickest:** double-click `play.bat`. It finds Godot 4, asks once if it can't, and launches the game.

Or from the editor:

1. Open Godot, click Import, and choose `project.godot` in this folder.
2. Press F5.

The game opens with a splash screen, a placeholder intro video, and a title screen (Continue, New game,
Load game, Settings, Quit). Any key skips the splash and the intro. Set `FARHAUL_SKIP_INTRO=1` to go straight to the title.

## How to play

1. **New game.** Choose a name, species, difficulty, starting system and one of five save slots. Species and
   systems come from `data/world/`; you can start at your species' home system, Concord, New Houston or Port
   Meridian. Difficulty sets your starting credits. Species gives no bonuses yet, and Settings is a placeholder. Replacing a used slot moves the old
   save aside; nothing is deleted.
2. **The dock.** You arrive at the yard of your starting system. The ship builder only opens from here.
   Continue and Load game return you to wherever you last saved: the dock or the shipyard.
3. **Build.** Name your ship (top right). Parts cost credits (refunded in full if you remove them). The ghost
   is green if a part fits and red with the reason if not. If your current rotation doesn't fit, it turns to
   one that does. Cyan rings mark open doorways: cap them so the hull is sealed.
4. **Check.** The panel on the right shows power, cooling, thrust-to-weight and warnings.
5. **Cargo preview.** Fill the hold to see and weigh the ship loaded. It does not buy or sell anything.
6. **Leave shipyard** (Esc) saves and returns you to the dock. Contracts and flight belong to the game proper.

A ship needs a cockpit, an engine, a sealed hull, an airlock, enough power and cooling, and enough
thrust-to-weight when loaded. Your game autosaves into its slot.

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
| `scripts/interiors.gd` | Per-module set dressing: cockpit seats and controls, reactor, bunks and galley, lockers, gantry |
| `scripts/module_library.gd` | The catalogue (13 placeholder modules defined in code) |
| `scripts/commodity_library.gd` | What can be hauled (placeholder goods and prices) |
| `scripts/cargo_manifest.gd` | What is aboard, per container: load, unload, capacity, value |
| `scripts/surface_textures.gd` | Procedural plating and hazard-stripe textures (no image assets) |
| `scripts/space_sky.gd` | Procedural star and nebula sky shader |
| `scripts/session.gd`, `save_slots.gd`, `worlds.gd` | The current game (profile, location), the five save slots, and the new-game choices read from `data/world/` (plus yard names and difficulty, which live in code) |
| `scripts/new_game_panel.gd`, `load_panel.gd`, `settings_panel.gd`, `dock.gd` | Title-screen panels and the dock scene |
| `scripts/contracts.gd` | Freight jobs and the checklist a ship must pass to run one (for the game proper; the builder does not use it) |
| `scripts/ship_history.gd` | Undo and redo snapshots |
| `scripts/ship_presets.gd` | Ready-made ships (the starter hauler) |
| `scripts/sfx.gd` | Synthesised sound effects |
| `scripts/ship_data.gd` | The ship as data: placement rules, removal, JSON save/load |
| `scripts/ship_stats.gd` | Mass, centre of mass, power, heat, thrust, warnings |
| `scripts/ship_view.gd` | Builds 3D nodes from `ShipData` |
| `scripts/builder.gd` | Camera, ghost, input, UI |
| `scripts/boot.gd` | Start-up flow: splash, intro video, title screen, hand-off to the builder |
| `scripts/brand.gd` | Name, tagline, palette, container codes, button style |
| `assets/brand/` | Logo, wordmark, icon and boot splash (generated, original) |
| `assets/video/intro.ogv` | **Placeholder** intro video. Replace it with the real one (Godot only plays Ogg Theora) |
| `tools/make_brand_assets.py` | Regenerates the brand images and placeholder video (needs Pillow, numpy, ffmpeg) |
| `tests/test_ship.gd` | Headless tests for the rules and stats |

Run the tests:

- Rules and stats: `godot --headless --script res://tests/test_ship.gd`
- Whole builder, a full play loop: `FARHAUL_NOSAVE=1 godot --headless --script res://tests/smoke_builder.gd`
  (the variable stops tests touching your autosave)

## Swapping in real art

Make a scene for a module (a hollow room built in Blender, say), then set `scene` on that
module's `ModuleDef`. Keep it inside its cell footprint and line its doorways up with the
sockets. Nothing else needs to change.

## Info site

`site/index.html` is a docs page with screenshots, help and a Download for Windows button pointing at the
latest GitHub Release. `.github/workflows/web.yml` publishes the `site/` folder to GitHub Pages on every
push to main (Settings > Pages > Source: **GitHub Actions**). Far Haul is a Windows desktop game; the
early browser build has been retired and `site/play/` is no longer tracked.

## Portable Windows build

`export_presets.cfg` also has a **Windows Desktop** preset: one `FarHaul.exe` (about 100 MB) with the game
packed inside, built to `build/windows/` (which git ignores). It needs no install. Copy it anywhere, a USB
stick included, and run it.

- **Saves** go in a `Far Haul saves` folder beside the exe, so they travel with it. If that folder cannot
  be written (the exe sits in Program Files, say), the game falls back to `%APPDATA%\Godot\app_userdata\Far Haul\saves`.
  The Load game screen shows which folder is in use. The editor and the web build are unchanged.
- **Build it from the editor** with Project > Export > Windows Desktop. To get the Far Haul icon and name
  in the exe, set Editor Settings > Export > Windows > rcedit; without rcedit the export still works,
  shows a warning and uses Godot's icon.
- **Build it from a script** with `tools/build_windows.sh [godot]`. It patches the icon and version info
  into a copy of the template with go-winres, then exports. This works on Linux with no Wine or rcedit.
- **First run:** Windows SmartScreen says "Windows protected your PC" because the exe is not code-signed.
  Choose More info, then Run anyway.
- **Sharing:** the exe is too big for the repo. Releases carry it (see below).

## Releases

Push a version tag and GitHub builds the Windows exe and publishes a release with the zip attached
(`.github/workflows/release.yml`). In GitHub Desktop: History, right-click the commit, Create Tag, name it
`v0.2.0`, then Push origin (Desktop pushes the tag with it). From a terminal: `git tag v0.2.0 && git push origin v0.2.0`.

- The tag sets the version shown on the title screen and stamped into the exe.
- Release notes come from `docs/releases/<tag>.md` (for example `docs/releases/v0.2.0.md`) if you commit
  one before tagging. Otherwise GitHub writes them from the commit list.
- `v0.x` tags and tags with a dash (`v1.0.0-beta.1`) are marked pre-release.
- A tag that is already pushed can be rebuilt from Actions > Release > Run workflow.
- The first run downloads Godot and its export templates (about 1.2 GB) and caches them. It takes a few
  minutes; later runs are quicker.

## Branding

Brand rules come from `docs/far-haul-concept.md` and `docs/design-reference/art-direction.md`:
industrial and function-over-form, hazard amber as the single accent, stencilled block lettering and
container-style codes (`FHCU 882193-4`). Change colours in `scripts/brand.gd` (and the matching
constants in `tools/make_brand_assets.py`). Everything is drawn from code, so there are no third-party
fonts or art to license.

## Docs

- [docs/far-haul-concept.md](docs/far-haul-concept.md): the full game concept (Far Haul).
- [docs/design-notes.md](docs/design-notes.md): technical decisions, build order, and plans.

## Next steps

1. Walk-through mode: spawn a character in the built ship, parented to the ship node.
2. Add collision to modules (floor and walls) so walking has something to stand on.
3. Real locations with limited, changing supply and prices (the Load button's Tonnes box stands in
   for that), then flight with a floating origin.
