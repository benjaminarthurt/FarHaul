# Desktop build: renderer, settings and speed

Far Haul is a Windows desktop game. The browser build has been retired.

## Renderer

The game uses **Forward+** (Vulkan on Windows), with `rendering_device/fallback_to_opengl3` set, so a PC
without Vulkan still starts, on OpenGL. It used to use the Compatibility renderer, which the web needed.
With Forward+:

- **Sun shadows.** Hull walls now shadow the interiors, and ships cast shadows on the moon pad.
- **Interior lights.** Every pressurised cell has a warm ceiling light (an `OmniLight3D` tagged
  `interior_light`, added in `ModuleDef._build_hollow`), so rooms are lit from inside.
- **Glass.** The cockpit glass is darker and reflective instead of glowing.

## Settings (`scripts/game_settings.gd`, `scripts/settings_panel.gd`)

The title screen's Settings page is now real:

- graphics quality: Low, Medium or High;
- fullscreen and vertical sync;
- interface size;
- master, music and effects volume;
- mouse sensitivity.

Settings apply at once and are saved in `settings.cfg` beside the saves, so a portable copy carries them.

| Quality | Sun shadows | Anti-aliasing | Ambient occlusion |
|---|---|---|---|
| Low | off | FXAA | off |
| Medium (default) | on, 2048, 2 splits | MSAA 2x | off |
| High | on, 4096, 4 splits, soft | MSAA 4x | on |

Each scene calls `GameSettings.apply_scene(self, shadow_distance)` at the end of `_ready`. Music
plays on a `Music` bus; jump sounds and builder clicks play on an `Effects` bus.

## Speed

Measured with `tests/probe_speed.gd` (headless, development machine):

| Moment | Before | Now |
|---|---|---|
| New game | 10.3 s | 0.09 s |
| Moon descent opening | 0.65 s pause | built in the background during the cruise |
| Dock, shipyard and flight scenes | about 0.3 s each | unchanged |
| Wait a day | about 0.7 to 1.0 s | unchanged |

Where the new-game time went:

- **4 s: the economy's 14-day warm-up.** It is the same for every new game, so it is now computed once
  and shipped as `data/runtime/warm_start.bin` (121 KB, zstd).
  - The file carries a fingerprint of every world and runtime data file. If any of them changes, the
    game ignores the file and runs the warm-up as before.
  - `tests/test_startup.gd` fails until you rebuild it with
    `godot --headless --path . --script res://tests/make_warm_start.gd`.
- **6.4 s: waiting for interstellar freight that a sublight ship can never take.** After the warm-up,
  new-game setup waited up to 10 in-game days for interstellar freight to appear at the home port.
  Since the starter has had no FTL drive, that wait always ran out. It is now skipped for sublight
  ships, which work from the local board. New games start on day 14 instead of day 24.

## Not yet

- The economy step itself (about 22 ms per sim hour) is what makes waiting a day, and long interstellar
  trips, take a second or more. Speeding that up means profiling `EconomySim.step_hour`.
- Key rebinding.
- A Direct3D 12 option.
- Loading screens between scenes.
