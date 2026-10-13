# Hull damage

What happens as the hull loses integrity, and what happens at 0%. Tuning lives in
`data/runtime/flight_tuning.json` under `hull_faults` (rebuild the warm start after changing it).

## Taking damage (`scripts/flight_model.gd`)

- `damage` runs 0..1 (hull left is `1 - damage`). Every source goes through `hurt(amount)`: station
  collisions, hard landings, boulders and slopes.
- Damage stays on the ship (`profile.hull_damage`) until repaired, and each flight starts with it.
- Thrust falls with damage as before (`damage_thrust_loss`).

## Faults before 0%

| Hull left | Fault | Effect |
|---|---|---|
| below 75% | cracked radiators | cooling falls linearly to 50% of rated at 0% hull (`cooling_now_kw()`) |
| below 50% | fuel leak | up to 1.5 t/h at 0% hull (`leak_t_per_h()`); counted in `fuel_burned_t`, so it is billed; `leaked_t` keeps the total |
| below 25% | cargo knocks | each hurt adds `amount × 2` to `cargo_hurt` (capped at 60%) while carrying cargo |

`faults()` lists the live ones for the HUD and the remote.

## Disabled at 0%

- `disabled()` is true at damage ≥ 0.999. Thrust and lift scale to 0, throttle, braking, course hold
  and autoland go off, and pilot input does nothing (no rotation either; the ship keeps whatever spin
  it had).
- The flight scene's prompt switches to the rescue line. Esc (or the remote's tug button) ends the
  flight as a rescue: it works like running out of fuel (`tow_goes_on()` picks the nearer end of a
  run), plus a salvage fee and cargo loss.
- No jump can be started while disabled.

## Warnings (`scripts/flight.gd`)

- Marks at 75%, 50%, 25% and 10% (`warn_at_hull`) plus the breach. Passing one says a line in the
  prompt (red), plays the alarm (`Sfx` `&"alarm"`) and appends to `alerts`, which the remote shows.
- Marks already passed when a flight starts are not announced again.
- The HUD's heat line shows hull and faults: `RADIATORS 70%`, `LEAK 0.6 t/h`, `CARGO AT RISK`, `BREACHED`.

## Settling a flight (`scripts/session.gd`)

- The flight scene sets `Session.flight_extra = {rescue, cargo_hurt}` before calling a `finish_*`.
  `_settle_hull()` charges the salvage fee (`rescue_salvage_fraction_of_ship`, 8% of the ship's cost ×
  difficulty maintenance multiplier) and records spoiled cargo on the active contract as
  `cargo_hurt`, combined as `1 - (1 - old)(1 - new)`. A rescue also loses `rescue_cargo_loss` (30%).
  Passenger jobs take no cargo loss.
- On delivery, local and interstellar, the pay is cut by `cargo_hurt`. For sim-paid contracts the cut
  is paid back to the world and taken off the carrier's revenue, so the books balance.

## Ports and repairs

- `Session.hull_block(with_load)`: at 0% nothing departs (runs, autopilot, jumps, flying empty, the
  helm); below `unsafe_hull` (25%) nothing departs with a contract, but flying empty is allowed.
- The repair desk offers a full repair, a patch to what the credits buy (in `patch_step` steps of 5%),
  and, when the ship is below 30% and the captain can't pay to get there, an emergency patch to 30%
  on account, which can put the credits negative. `Session.patch_options()` and `patch_hull()`.

## Visible damage (`scripts/ship_damage.gd`)

- `ShipView.set_damage(d)` (skinned ships only). Sites are the outward faces of pressurised
  compartments in a fixed shuffled order per layout.
- Scorch decals (up to 16) appear in proportion to damage; vapour vents open below 50% (one), 25%
  (two) and at 0% (three); sparks fire below 25%, more often at 0%.
- `tests/capture_damage.gd` renders 100/60/30/10/0%.

## Tests

`tests/test_hull_damage.gd`: faults, disabled controls, port refusals, patches, salvage, cargo cuts at
delivery, warnings, the remote's state, and the rescue from the cockpit.
