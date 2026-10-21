# Reputation

Code: `scripts/reputation.gd` (`Reputation`: the books, news, fading, tiers, curves, settling),
`scripts/session.gd` (`_add_rep`, `standing_here`, `standing_parts`, `rep_fee_mult`, `rep_pay_mult`,
`settle_record`), effects in `contracts.gd`, `people.gd`, `passengers.gd`, `comms/comms.gd`,
`place/place_desks.gd`, `dock.gd`. Tuning: `data/runtime/reputation.json`. Since 0.20.0.

## Three books

`profile.reputation = {places, species, auth, log, faded_h}`:

| Book | Key | Moved by |
|---|---|---|
| `places` | site id (port, depot, moon, belt, pad, camp, world, field, mars...) | work done there |
| `species` | human, kesh, ilyan, vey, orun | a share (`species_share`, 0.5) of deeds involving their people |
| `auth` | system id | the system's traffic control and port authority |

Standing at a site = `places[site]` + the mean of the site's peoples' views + the system's authority
view, clamped to ±100 (`limit`). A site's peoples are its system's `home_species_ids`, or its
`origin_species_ids`, or humans (`Reputation.peoples`).

## Deeds

`Session._add_rep(points, kind, species, site)` records a deed at the site you're at
(`Reputation.record`). `kind` picks the books (`deeds` in the json):

| Kind | Books | Used for |
|---|---|---|
| `work` | place, species | freight delivered (+1, or -2 when cargo arrived broken: `rep_freight_hurt`), people's jobs (rush, passengers, sealed, private), surface missions, cancelling a person's job |
| `radio` | species, authority | what the flight's radio settles: fuel sold to a ship in trouble, a crew taken aboard, a report, an ignored mayday, claim-jumping |
| `record` | authority | docking or landing without clearance (`fine_rep`), finder's fees for reported wrecks |
| `rescue` | species (the survivor's), authority | handing over a rescued survivor |

Points are the ones each feature already used (people.json, comms.json, port_authority.json and so on).
`profile.rep` is still kept as a running total of everything (floored at 0): what other captains have
heard. Rival crews and haulers selling fuel use it.

## News

The place book is local and immediate. Species and authority points go into `log` as
`{h, sys, sp: {species: points}, auth}` and are heard:

- in their own system at once;
- in another system after `lag_hours(a, b)`: the economy's route between them at its usual speed
  (`sim._path_hours`, port dwell included) plus `news_lag_hours` (6). Systems off the network hear
  after `unreachable_lag_days` (30). Without a sim (tests), distance at `news_ly_per_day` (1.5).

Another system's authorities count `authority_share_elsewhere` (0.75) of a mark. Once every system has
heard a deed, `tick` folds it into the totals and drops it from the log.

## Fading

`tick` also fades every negative value in the three books by `bad_fade_per_week` (10%) a week, from
`faded_h`. Positive values never fade. Deeds still in the log fade once they're folded in.

## Tiers and curves

| Points | Tier | Effect |
|---|---|---|
| ≤ -50 | Barred | no board, no people, clearance refused, fees 1.6 |
| ≤ -25 | Unwelcome | board only, no people or long-haul passengers, crew won't sign on |
| ≤ -10 | Doubtful | board keeps 2/3 of its offers (`doubtful_board_keep`), 2 people ask (`doubtful_people_per_site`) |
| -9 to 9 | Unknown | |
| ≥ 10 | Known | sealed crates (`people.json` sealed `min_tier`) |
| ≥ 25 | Trusted | priority berth: traffic control never makes you hold |
| ≥ 50 | Respected | private contracts (`people.json` private: 2.8× rate, 2.4× trip cost) |

`pay_mult` and `fee_mult` interpolate linearly between the points in the json:
pay 0.7, 0.75, 0.88, 1.0, 1.05, 1.12, 1.25 at -50, -25, -10, 0, 10, 25, 50; fees 1.6, 1.35, 1.15, 1.0,
0.98, 0.93, 0.88.

- **Pay**: `Contracts.shaped` multiplies board rates (local and interstellar) and remembers `rep_mult`.
  An interstellar job's `pay_total` is the sim's pay (`pay_base`) times `rep_mult`; on delivery the
  difference is paid in or taken back through the sim. People's jobs and long-haul passengers multiply
  their rate or fare the same way (`People.rep_bonus` = `pay_mult - 1`).
- **Fees**: `Session.site_fuel_mult` and `site_repair_mult` (fuel, repairs, patching), the berth fee in
  `local_trip_cost`, and every tow fee. Fines are not changed.
- **Crew**: a candidate refuses (`refuses`) when you're Unwelcome or worse there, or when their own
  species' view as heard there is at or below `crew_refuse_below` (-10).

## Traffic control

`Comms._request_dock` and `_request_land` look up the tier at the site:

- Barred: `standing_refused` / `pad_refused` / `camp_refused`, no clearance. Docking or landing anyway
  is the usual unannounced fine and another mark.
- Trusted or better: no hold for the collar.
- After a clearance (`_standing_word`): Respected always, Trusted half the time, say a warm line
  (`*_warm`); Doubtful or worse a cold one (`*_cold`). Traffic control speaks the `standing_*` lines,
  pad and downport control `pad_*`, camps `camp_*`; each species in its own words (`species_lines`),
  all recorded.

## Settling your record

At a port's freight office (`PlaceDesks._standing_section`): `Session.settle_record()` pays
`settle_cr_per_point` (400) × the difficulty's port fee level per point of the system's negative
authority view, then `Reputation.settle` zeroes that system's own marks still in the log (word that
hadn't left never does) and lifts the system's total to zero. Marks other systems already heard stay.

## Seeing it

- The freight office, dispatch and the foreman: YOUR STANDING (tier, what it means, fees), and SEE WHO
  THINKS WHAT: the place, its people, the authorities, every species' view as heard here, news still
  travelling, and other places that remember you.
- PEOPLE WITH WORK: the tier, the next one, and the pay against the usual.
- The place's info panel: "Standing here".
- The station terminal: "Standing here", with pay and fees.

## Old saves

`Reputation.state` makes the books on first use. A save with `profile.rep` gives that score to the port
it was saved at and half of it to that system's peoples.

## Tests

`tests/test_reputation.gd`: tiers and curves; the three books; news reaching another system after the
route's hours, at three quarters for authorities; folding; fading; settling; in a game: pay and fees at
Respected, private contracts, fewer offers when Doubtful, Unwelcome and Barred, crew refusing by
species, deeds and tier notes, a fine on the authorities' book, settling for credits; an old save;
traffic control refusing a Barred captain and giving a Respected one a priority berth and a warm word.
