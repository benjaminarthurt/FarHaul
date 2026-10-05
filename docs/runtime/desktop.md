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
| Wait a day | about 0.7 to 1.0 s | about 0.25 s (the carrier search below) |

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

- **Most of an economy hour was carriers searching the board.** Every idle AI ship re-evaluated every
  posted contract every hour. In `_dispatch_carriers`, a ship that found nothing worth taking is now
  skipped until the board it can see changes. The board counts as changed when contracts are added or
  removed, a lot shrinks, a rate moves, freight is taken earlier in the same hour, or a day turns. A day
  of the economy is about four times faster (628 ms down to about 170 ms on the slow test machine).
  - `tests/test_sim_speed.gd` runs the economy with and without the skip and checks the two end in the
    identical state: ten days from the warm start, and sixty from a cold start.
  - The first version of the skip missed freight taken earlier in the same hour. It changed results
    from about day 52 of a cold start. The known-space test caught it, and it is fixed.

## Sound (`scripts/world_audio.gd`, `tools/gen_world_audio.py`)

Like the jump, every sound is synthesised from tones and filtered noise. The files are in
`assets/audio/world/`, and any of them can be replaced by a recording.

- **Room tone:** the concourse's air handlers and distant voices; the hab's pumps and air recycler; the
  ship's reactor drone when you are aboard.
- **Footsteps:** on deck plating in ships and ports, and a softer crunch in moon dust.
- **Flying:** the main engine and the lift jets, following the throttle and lift. You don't hear them
  when you're outside on an airless moon.
- **The suit:** breathing, faster when you run, and a double beep every four seconds when air is low.
- **Cues:** a click on desks and buttons; a chime when you bag a find, set a beacon or finish a job; a
  thud when you set a crate down.
- **Jump loops fixed:** they used to restart after 0.8 s. The loop end was worked out from the
  compressed file size, so the 4 s hum was cut short. It now comes from the sound's length.

## Not yet

- The economy's hourly production and consumption step (about 70 ms a day on the slow machine) is now
  the largest cost.
- Key rebinding.
- A Direct3D 12 option.
- Loading screens between scenes.
