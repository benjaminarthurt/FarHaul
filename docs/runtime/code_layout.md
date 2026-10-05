# How the scene scripts are laid out

The two biggest scene scripts were split into smaller pieces. Each scene keeps its state, its
`_process` and input handling, and thin functions with the old names. Each piece is a helper object
in its own file that does one job. Behaviour did not change: every capture renders pixel for pixel
the same before and after the split, apart from screens with animation, which match to within
normal frame-to-frame noise.

## The flight scene: `scripts/flight.gd` (`FlightScene`), about 640 lines, was 1,710

| File | Class | What it does |
|---|---|---|
| `scripts/flight/space_scenery.gd` | `SpaceScenery` | Sky, sun, ambient light, dust motes, and the station with its rings, lights and name |
| `scripts/flight/landing.gd` | `Landing` | Whether a run lands or docks; arriving over the pad; descent and lift-off; the lift-jet command; the moon coming and going |
| `scripts/flight/moon_scenery.gd` | `MoonScenery` | The moon's ground and everything on it: base pad, camp, wreck, outpost, ice mine, crater, boulders, finds. Can be built without the scene |
| `scripts/flight/on_foot.gd` | `OnFoot` | Getting up and walking the ship, the airlock, the suit outside, picking up finds, coming back aboard |
| `scripts/flight/jump_sequence.gd` | `JumpSequence` | A flown star jump, from setting it up to arriving in the next system |
| `scripts/flight/flight_hud.gd` | `FlightHud` | The readouts and prompts for flying, landing, walking and the suit, and the flight markers |

## The port scene: `scripts/place.gd` (`PlaceScene`), about 350 lines, was 1,010

| File | Class | What it does |
|---|---|---|
| `scripts/place/place_builder.gd` | `PlaceBuilder` | The concourse, hab and hut: rooms, lights, furniture, desks, people, signs, the freight board, the window view |
| `scripts/place/place_desks.gd` | `PlaceDesks` | What each desk shows: freight, people, missions, fuel and repairs, bar, lab, exchange, suit store, gate |
| `scripts/place/strollers.gd` | `Strollers` | People walking loops of waypoints. Plain logic, so it can be tested on its own |
| `scripts/place/style_dressing.gd` | `StyleDressing` | Dresses a concourse in its system's style: architecture fittings, colony signature, role props, wear |
| `scripts/place/hints.gd` | `Hints` | First-time hints in places, remembered in the profile |
| `scripts/identity/system_style.gd` | `SystemStyle` | Each system's look, worked out from the world data (docs/runtime/identity.md) |

## How the helpers work

- Each helper gets the scene in its constructor and reaches the scene's state through `sc`, for
  example `sc.model` or `sc.walker`.
- Helper calls between pieces go through the scene's functions, so outside code and tests keep using
  the scene's names: `go_outside()`, `use_desk()` and so on.
- New tests can build a piece directly. `tests/test_components.gd` builds a `MoonScenery` and walks
  `Strollers` with no scene at all.
