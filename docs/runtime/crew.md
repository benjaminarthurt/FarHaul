# Crew

People hired at a bar who work the ship. Code: `scripts/crew.gd` (names, candidates, role effects and
the work rules, all static), `scripts/session.gd` (roster, hire, fire, migration, effects on trips and
deliveries), `scripts/sim/sim_world.gd` (`_crew`: payroll and pilot speed in the sim),
`scripts/flight/crew_work.gd` (`CrewWork`: the crew at work during a flight, and their figures
aboard), `scripts/place/place_desks.gd` (the bar's YOUR CREW and LOOKING FOR A BERTH sections).
Tuning: `data/runtime/crew.json` (rebuild the warm start after changing it). Tests: `tests/test_crew.gd`.
Render: `tests/capture_crew.gd`.

## The roster

`profile.crew` is an Array of `{id, name, species, role, skill, wage, line, hired_day}`. The captain is
not in it. `Session.crew_aboard()` is the roster plus one.

- `wage` is cr/day before the difficulty's `wage_mult`, fixed at hire from the role wage ×
  (`skill_wage.base` + `skill_wage.per_skill` × skill) × the hiring port's `SimShip.wage_index`.
- New games start with `crew: []`. A save with no `crew` key (before 0.9.0) is migrated on load
  (`Session._migrate_crew`): the ship's `crew_needed − 1` hands get names, skill 2, roles in the order
  engineer, deck tech, loadmaster, pilot, steward, at the old pay level.
- `Session.ship_stats` adds `crew_aboard`. A profile without `crew` reports `crew_needed`, so old code
  paths and tests that build profiles by hand behave as before.

## Hiring and letting go

- `Crew.candidates(port_id, day, wage_index, skip)`: `candidates_per_day` people, seeded by port and
  day so the list holds still all day. Roles are spread (`ROLES[(start + 2k) % 5]`), skill from
  `skill_odds`, species from `species_weight`, a line from `lines[role]`. Ids in `profile.crew_seen`
  (hired or let go) are skipped.
- Names follow `data/world/cultures.json`: human given + family; Kesh personal (first + end) +
  lineage; Ilyan personal + second name; Vey personal, usually + waters; Orun personal "of" junction.
- `Session.hire(id)`: needs a free berth (`berths − crew_aboard − passengers aboard`) and
  `hire_fee_days` of pay up front. `Session.fire(id)`: `severance_days` of pay (what the captain can
  cover, if broke). Both go through `_book` and then `_resync` the sim.
- The bar desk lists the crew (a click asks, a second click lets them go) and today's candidates.
- Bankruptcy (`Session.restructure`) trims the roster to the bank hauler's spare bunks.

## Payroll

`SimWorld._crew` runs on `create` and `sync`. With a roster, the sim carrier's `crew` is
`1 + roster.size()` and `wage` is the average of the owner's draw (at home rates) and each crew wage,
so `daily_cost` and every trip's wage cost use the real roster. `c.roster` keeps per-person lines for
`payroll_lines` (dock terminal, "Crew pay").

## Needing hands

`Contracts.check` has a **Crew aboard** row: `crew_aboard >= crew_needed` (`SimShip.crew_for`, one
more per 40 SCU of hold). A big ship needs hiring before it takes freight. **Crew berths** checks
berths against the larger of the two. Passenger seats are berths less the larger of the two.

## What each role does

The best skill aboard in a role counts; two of a kind don't stack. Multipliers floor at 0.2.

| Role | Effect | Tuning |
|---|---|---|
| Engineer | All wear × (1 − 0.08 × skill), in flight (`flight._wear_step`), on autopilot trips (`_autopilot_wear`) and on jumps. Services one part every `service_every_s / skill` game seconds in flight; `services_per_trip_hour × skill × hours` between trips. | `wear_cut_per_skill`, `service_every_s`, `services_per_trip_hour` |
| Deck tech | Fixes one hull mark every `fix_every_s / skill` s in flight, counting only while the ship is quiet (no throttle, braking, retro, strafe or spin, not jumping); `fixes_per_trip_hour × skill × hours` between trips. | `fix_every_s`, `fixes_per_trip_hour` |
| Pilot | Local fuel (`local_trip_cost`) and hours (`_depart_local`, `local_reposition`) × (1 − 0.04 × skill); between stars the sim speed ÷ that and burn × that. In flight: with the captain out of the seat on a run, engages the braking autopilot at `xfer.brake_now` (not while anyone is on a tether: it says so instead). Cuts throttle, braking, course hold, retro and strafe before a space walk. | `fuel_cut_per_skill`, `time_cut_per_skill` |
| Loadmaster | `cargo_hurt` from a flight × (1 − 0.15 × skill) (`_settle_hull`). Local unloading hours × the same. At a camp, the crew unload it: no camp crew share taken. | `cargo_hurt_cut_per_skill`, `unload_cut_per_skill` |
| Steward | Passenger fares × (1 + 0.05 × skill); at skill 3+ a passenger delivery earns +1 standing. | `fare_per_skill` |

Between-trip work (`Crew.work_between`) runs on waiting in port, flying empty, repositioning, local
autopilot runs and autopilot jumps. A flown jump does it on the flight's own hull and wear
(`CrewWork.after_jump`, which also applies the jump's engine and radiator wear: `Session.commit_jump`
no longer does, because the flight overwrites the profile's wear when it ends).

## The space-walk rules apply

The crew can't do more than the captain on a space walk:

- Hull marks are `ShipDamage`'s, in its order (`Crew.marks` mirrors `visible_marks` without a scene).
  `Crew.pick_mark` takes loose plating (even index) first, then a hole (odd) only with a patch kit,
  and nothing once the hull is at `eva.repair_cap_hull` (50%). Fixed marks go in `hull_patches`.
- Parts: `Crew.service_one` takes the worst part above `eva_floor`, using `Wear.eva_fixed`. A failed
  part needs a spares kit.

## In flight

`CrewWork` is made in `FlightScene._ready`, stepped after `_wear_step`. It says what the crew did in
the cockpit message line. The HUD has a CREW line. Walking the ship, each crew member stands at a post
(`POSTS`: engineer in engineering, deck tech in the airlock, pilot in the cockpit, loadmaster in the
hold, steward in quarters; any free room otherwise), clear of the helm, the airlock's middle and
hatches, facing into the room, turning their head as you pass. Close up, the prompt gives their name,
job and line. The figures only show while you're on your feet.
