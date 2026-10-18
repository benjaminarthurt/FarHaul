# Frontier growth

Code: `scripts/sim/development.gd` (`Development`). Tuning: `data/runtime/development.json`. Since 0.17.0.

Every site in known space (each system's main port, fuel depot, moon station, belt works, moon base pad,
mining camp, and Sol's three outer stations: 111 in all) has a size, and grows or shrinks with how well
it's supplied. Systems follow their sites, more slowly. It's on in a game only: `SimWorld.create` calls
`Development.enable`, and an older save gets it on load. The economy's own calibration tests run without
it (`EconomySim.dev` empty), so their bands don't move.

## The numbers

| | |
|---|---|
| **Score** | A float. Stages: below 0.5 abandoned; then extreme frontier (1), frontier (2), outer (3), developed (4), core (5), each from half a point below. Nothing caps it: past 5.5 it's still core, and still growing. |
| **Canon** | The system's tier (its classification) for its port; one step down for the depot, moon station, belt works and outer stations; two down for the pad and camp. Never below 1. |
| **Need** | Tonnes a day it takes to keep a site as it is: `demand_t_per_day[kind] × 2^(score − 2)`. A frontier port needs 10 t a day, a developed moon station 12, a core port 80. |
| **NPC supply** | The share of its need the system's traffic brings: `health × e^luck × e^(−0.7 × (score − anchor))`. |
| **Health** | The system's fill rate (the share of its facilities' demand their shelves met, a 30-day average) against what's normal for it (a 180-day average, starting at 0.92). Clamped to 0.5–1.3. |
| **Luck** | A slow random walk per site (`fortune`: 40-day memory, 0.05 a day), seeded by site and day, so the same world grows the same way every time. |
| **Anchor** | What the traffic is used to serving. It follows the score with a 90-day lag, so growth sticks and decline sticks. |
| **You** | Tonnes you delivered there that day, plus half of what you carried away from it. Interstellar freight counts at the system's main port. Passengers count 0.1 t a seat. |

Each day: `ratio = npc + you / need`, and `score += 0.06 × inertia × (ratio − 1)`, capped at +0.2 and −0.06 a
day. `inertia = min(1, √(12 / need))`: anything bigger than a developed moon station turns more slowly.
Below 0.5 a site is abandoned. It stays empty unless its system booms (0.75 above canon), and then it has
a 2% chance a day of being resettled at 0.8.

A system's score moves a thirtieth of the way each day toward `canon + 0.5 × (its sites' average growth) +
1.5 × (health − 1)`. Its facilities in the economy make and use `2^(score − canon)` times as much
(`EconomySim.scale`), so a growing system posts more freight and needs more, and stalls if the haulers can't
keep up.

## What a stage gives

| Service | From | Where |
|---|---|---|
| Freight, dispatch, foreman, fuel, repairs, lab, exchange | Extreme frontier | `Development.has(sim, site, "freight")` |
| Passengers (the freight desk, the bar, people asking) | Frontier | `Session.site_has("passengers")` |
| Crew for hire | Outer | `Session.site_has("crew")` |
| A shipyard | A main port while anyone lives there; any other site at core | `"yard"` |

Fuel and repairs cost `1 − 0.05 × (stage − 3)` times the site's usual price: 10% dearer at extreme frontier,
10% cheaper at core (`Session.site_fuel_mult`, `site_repair_mult`). An abandoned site has a pump at twice the
price and no repairs.

**Abandoned.** No freight to or from it, nobody at the desks, a lamp in three on the emergency circuit. The
concourse has a fuel pump and a **Strip the fittings** desk: 3 salvage parts every 20 days
(`Session.strip_fittings`). The hab and the hut likewise.

**The local board** (`LocalSpace.board`). A site posts `jobs × √(size now / canon size)` runs (0.4 to 3
times), and picks destinations weighted by the same ratio, so growing sites draw freight. With nothing
grown, the board is exactly what it was before 0.17.0: the same jobs from the same draws.

**Looks.** `SystemStyle.for_site` takes the site's stage as its tier: the concourse's size, crowd, wear,
planters and banners. Outside the hab's and hut's windows stand 1 to 8 other buildings (`PlaceBuilder.outside_buildings`).

## Seen

- **Trade report, page 5 (Growth):** this system's sites, each with a bar from abandoned to core (canon
  marked), its stage, which way it's going, and why ("short: traffic brings 78% of the 5 t a day it needs";
  "you bring 67% of it"); what grew, shrank or emptied in the last 30 days; every system's stage
  (`TradeData.growth`).
- **Radio:** ships pass on what grew, shrank or emptied in your system in the last three weeks
  (`news_grew`, `news_shrank`, `news_empty`, in each species' own words), ahead of other news.

## State

`sim.dev`, saved with the sim: `sites` (score, canon, anchor, luck, need, npc, you, abandoned, since, 60
days of history), `systems` (score, canon, fill, fill_base, unmet, history), `today` (your tonnes so far
today), `events` (the last 80 stage changes) and `day`.

## Measured

180 days of known space with nobody playing (`tests/probe_development.gd`): about a quarter of sites move
a stage, about two up for every one down, two remote pads or camps empty, and no main port does. Hauling
10 t a day to Sol's moon station takes it from developed to core in about two weeks.

## Tests

`tests/test_development.gd` (about a minute): canon sizes; two runs grow the same; hauling to Luna
grows it to core in a month and opens a yard; a camp nobody supplies is abandoned and loses its services;
services by stage; a grown system's exchange draws double and the ledger balances; growth survives a
save; the local board skips an abandoned depot; stripping its fittings; its empty concourse; the radio's
lines; 180 days with nobody playing (some grow, some shrink, under 45% change, no port empties, ledger
clean). `tests/capture_growth.gd` renders the Growth page, an abandoned depot, a grown moon station and
the hab at frontier and core.
