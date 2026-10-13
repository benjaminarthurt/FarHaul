# Wear and tear

The ship's working parts wear out with use, and can be serviced on a space walk or overhauled at a
yard. Code: `scripts/wear.gd` (the rules, all static), `scripts/flight.gd` (`_wear_step`, warnings),
`scripts/flight/on_foot.gd` (servicing on a space walk), `scripts/session.gd` (autopilot wear, the
overhaul, spares kits). Tuning: `data/runtime/flight_tuning.json` under `wear` (rebuild the warm start
after changing it). Tests: `tests/test_wear.gd`.

## What wears

Engines, radiators, braking thrusters, manoeuvring thrusters and lander legs (`Wear.kind_of`). Wear
runs 0 (new) to 1 (failed) per fitted part, saved in `profile.wear` keyed `"<module index>:<id>"`, so
a part replaced in the shipyard starts new.

- A worn part gives `1 - loss × wear` of its output (`loss`: engine 0.4, radiator 0.6, thrusters and
  legs 0.5). A failed part gives nothing. `Wear.effective` recomputes the ship's thrust, cooling,
  braking, manoeuvring and lift with wear, the same sums `ShipStats` makes; `Wear.apply` puts them into
  the flight model (once a second, and whenever a part crosses a line).
- Every engine failed: nothing departs (`Session.hull_block`).

## How it wears

- Engines: `engine_per_s_full` per second at full throttle (game time), times `engine_hot_mult` above
  80% heat. About 20,000 s of full burn from new to failed.
- Radiators: running above 60% heat, faster the hotter; much faster while overheated.
- Braking and manoeuvring thrusters: `thruster_per_s` while firing.
- Lander legs: `legs_per_landing` per touchdown.
- Knocks: hull damage shakes one part loose (`knock_per_damage` × the damage, one part picked at random).
- Autopilot: a local run wears the engines and radiators by the tonnes it burns; jumps and flying
  empty between stars by a flat amount; repositioning between sites a little.

## Warnings

Crossing 75% worn (`worn_at`) says so; failing sounds the alarm. Both go into the remote's alerts.
The HUD and the remote list the parts in trouble ("Engine FAILED, Radiator 18%").

## Fixing

- **Space walk** (`space_walk.md`): worn or failed parts above `eva_floor` are jobs, tagged by name.
  The wrench services a worn part (free, 6 s, `eva_service` off, never below `eva_floor`: 50%
  condition). A failed part needs a spares kit (10 s) and comes back at `eva_replace_to` (40%).
- **Repair desk**: OVERHAUL THE WORKING PARTS sets everything to new for the parts' cost ×
  `overhaul_fraction_of_part` × wear, at the difficulty's maintenance rate and the site's repair rate.
  Spares kits are sold there (1,500 cr, 4 aboard at most).
