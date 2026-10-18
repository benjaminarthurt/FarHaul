# Danger without combat

Code: `scripts/sim/hazards.gd` (`Hazards`), `scripts/flight/hazard_watch.gd` (`HazardWatch`), claim-jumpers in
`scripts/comms/rivals.gd`. Tuning: `data/runtime/hazards.json`. Since 0.18.0.

Three risks you plan around rather than fight. All of them are worked out from the system or route and the
calendar (`EconomySim.now_hour()`: hours since day 0), so the same storm and the same field are there for
everyone, every time.

## Solar storms

Each system gets at most one storm per ten-day window (`_storm_in`), more often further out: 12% of windows
in a core system, 30% on the frontier, 38% at the extreme frontier. A storm lasts 12 to 48 hours at an
intensity of 0.3 to 1.

| Warning | Share | Lead |
|---|---|---|
| Forecast: radio news, the port's notices, the trade report | 55% | 24–72 hours |
| Sensors only: the ship spots it in flight | 22% | 2–8 hours |
| None | 23% | |

`Hazards.known(system, hour, sensors)` lists what someone would know about; `storm_at` the one raging.

**Out in one** (in port you're shielded):
- **Flying it yourself** (`HazardWatch._storm_step`): the radiators lose `0.5 × intensity` of their cooling
  (`FlightModel.storm_cooling`), wear at 1.2% an hour at full intensity, and the hull takes 0.15% an hour.
  The cockpit says so when it starts, and the sensors warn of a sensor-only front when it's within their lead.
- **On autopilot from the desk** (`Session._en_route`): the same wear and hull for the storm-hours the trip
  overlapped (`Hazards.exposure`). Star jumps count four hours in each end system.

**The economy feels it**: while a system has a storm, no NPC carrier takes freight to, from or through it
(`EconomySim._eligible`, in a game only), and its sites get `1 − 0.8 × intensity` of their usual NPC supply
(`Development.day_turned`). Shelves dip, and through frontier growth, outposts feel it. Traffic control advises
holding when you ask for clearance mid-storm (`storm_advice`); passing ships give the forecast as news
(`news_storm`, first in line).

## Debris fields

A field lies across 30% of local hops (between two kinds of site, either way round) and 18% of interstellar
lanes, for a 30-day month at a time (`local_field`, `lane_field`). Each has a density (0.3–1), a radius (1.5–5 km),
where along the route it sits (30–70%) and how far off it (up to 1.1 radii, so some routes only skim it).

**Hits**: inside, `density × 0.6 hits per km flown`, a third of that with the autopilot flying (course hold or
stop-at-target), each costing `0.4% + 0.002% per m/s` of the hull, up to 6%. At 2 km/s a hit is 4.4%; at 100
m/s, 0.6%. So: go round it, slow down, or let the autopilot thread it. A hit sometimes shakes a part loose
(`Wear.knock`, 25% on autopilot trips; in flight, the flight's own knock rule).

- **Flown local runs** (`HazardWatch`): the field is drawn where it lies, a faint haze with 600 rocks and a
  DEBRIS FIELD marker you can see from far off. The cockpit announces it at the start and again within three
  radii.
- **From the desk**: the autopilot crosses the chord at about 600 m/s (`Hazards.desk_crossing`). Lanes have no
  geometry: an average of `1.2 × density` hits at the autopilot's rate.

Whatever a trip ran into is added to its message ("The autopilot threaded a debris field and missed most of
it: 1 hit, 2% of the hull."), and the hull damage counts as a rough ride for passengers.

## Claim-jumpers

30% of rival salvage crews (`Rivals._roll`) don't care whose beacon is on a wreck. On one of yours they arrive
saying so (`rival_jump`), cut 1.6 times as fast, and won't split or clear off (`rival_jump_no`). The radio adds
**Report them to the port authority**: 45% of the time a patrol is near and they run (`rival_report_go`); otherwise
they keep cutting (`rival_report_stay`). Either way, when the flight's over the port authority pays a bounty of
half the standard salvage price for each piece they took, and your standing goes up by 2.

## Seen

- Port HUD and the freight desk: the storm raging or forecast here.
- Trade report, page 5: KNOWN SPACE · SPACE WEATHER marks systems with a storm now (red) or forecast (amber).
- Radio: storm forecasts in the news, control's advisory, claim-jumpers.

## Tests

`tests/test_hazards.gd`: the frontier stormier than Sol; the same storm every time; forecasts, sensor-only and
unannounced storms; exposure; fields on a hop either way round; faster hits hurt more, up to a cap; the
autopilot's rate; chords; threading a dense field on autopilot; an autopilot trip through a storm and a field
(hull, wear, message); haulers held and the port's NPC supply cut mid-storm; in a flight, cooling lost and given
back, hits by hand and fewer on autopilot; a claim-jumper on your wreck that won't deal, is reported, and pays a
bounty. `tests/capture_hazards.gd` renders a field from 12 km and from inside. `Hazards.off` turns the weather
and the rocks off for tests about something else (test_crew, test_people).
