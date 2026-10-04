# Landing on a moon

Runs to a moon base can end on its surface pad instead of at its orbital station. You need lander legs
with enough lift for the load and enough fuel left to come down on the jets.

## The part

**Lander legs** (`lander_legs`, external) bolt under a hull cell: four struts to footpads, with lift jets
firing downward between them. Each set is 1 t, costs 12,000 cr, gives 70 kN of lift along the ship's +Y,
and draws 4 kW. The builder stats show the lift and the gravity it can land in at the current load.
Two sets let the starter land with a full hold. `ShipPresets.STARTER_LANDER` is the starter plus two
sets and a second fuel tank, and the tests use it.

## When a run lands

On a flown run (FLY THE RUN) to a moon base, the descent replaces the orbital approach when all of these
are true:

- the ship has lift jets, and they give at least 1.15 times the moon's gravity at the current mass
  (`min_lift_margin`);
- at least 1.5 t of fuel is left on arrival (`landing_reserve_t`).

Otherwise the ship docks at the base's orbital station as before. The board marks moon runs
"+25% if you land it" when the ship has legs.

## The descent

The ship arrives 1.2 km up and 900 m out, drifting toward the base at 25 m/s, level. The moon's
gravity is 1.62 m/s².

- **Space** fires the lift jets at full power. **H** holds a hover (the jets cancel the fall).
  Tilting with the arrows and Q/E steers, because the jets push along the ship's up axis. W/S still
  runs the main engine.
- **Esc** hands it to the autopilot. It holds about 150 m while it flies over the pad, then comes
  straight down. It never descends faster than the jets can stop it from that height, and it slows to
  under 1 m/s at the end. From the start point it lands the loaded starter-with-legs in about
  2.5 minutes for about 2 t of fuel.
- **Touchdown** is clean at under 3 m/s down, under 2 m/s of drift and under 15° of tilt. The ship
  settles level on its legs and stays put until the jets lift it again. Anything harder is a hard
  landing: hull damage scaled to the excess speed and tilt, and a bounce.
- **Landing zone:** within 120 m of the pad centre (pad radius 25 m). Down elsewhere, the prompt says
  to lift off and move closer. Out of fuel off the pad, F calls a crawler to tow you in (tow fee).
- **F** on the pad shuts down and unloads. The run is delivered with the surface bonus (+25% of the
  freight pay, `surface_bonus`).

## On foot outside

Once the ship is down, get up (G), walk to the airlock and press E to step out onto the surface.
`SurfaceWalker` handles the suit: walking at 1.6 m/s (Shift to run), Space to jump in the low gravity,
and the ship's cells as solid blocks (you can walk under the hull between the legs). E within 2.5 m of
the hatch takes you back aboard.

## The ground

`SurfaceTerrain` is deterministic per base: rolling relief, about 14 craters with raised rims, and the
ground graded flat within 90 m of the pad. The view is a 9 km vertex-coloured mesh, with a lit pad, edge
lights, the base's name and a few domes and huts.

## Tuning and code

- Tuning: `data/runtime/landing.json`.
- Physics: `FlightModel` gains `gravity`, `terrain`, `lift`, `autoland`, `landed`, `_ground()` and
  `_autoland()`. Lift jets burn fuel at the same specific impulse as the main engine.
- Scene: `flight.gd` adds `_begin_descent`, `_build_moon`, `go_outside` and `come_aboard`.
- Delivery: `Session.finish_local_flight(..., surface)` and the bonus in `_deliver_local`.

## Tests

- `tests/test_landing.gd`: the autopilot lands softly on the pad. It also checks a drop with no lift,
  a manual descent on the jets, liftoff, and that the plain starter cannot hover.
- `tests/smoke_land.gd`: the whole run in the flight scene. It descends, autolands, walks outside,
  checks the ship is solid, jumps, comes back aboard, unloads, and checks the bonus is paid.
- `tests/capture_land.gd`: renders the descent and the surface to `/tmp/land_frames` (xvfb-run).

## Surface work

Every system's moon has two places on its surface, both in `LocalSpace` (`SURFACE`):

- the **base pad** (`<system>__pad`, under the base's orbital station);
- a **mining camp** (`<system>__camp`, 3 km from the pad, `camp_offset_m`), with a rough pad, flares
  and no landing beacon.

**Hops** (`local_space.json`): to or from the surface costs 1.8 km/s more than to the base's station
(`surface_dv_kms`). Station to pad or camp is 1.8 km/s and 2 h; pad to camp is 0.9 km/s and 1 h.

**Surface jobs.** They show only to a ship whose lift jets can set a worthwhile load down on that moon
(`LocalSpace.can_land` and `max_landing_cargo_t`), so the starter's board and the economy calibration
are unchanged. They pay 1.5 times more per tonne-km/s (`surface_rate_mult`). The board shows them as
SURFACE, and `Contracts.check` adds a Lander legs row. Fly empty lists surface sites only for a lander.

**Flying them.** The surface part of the hop's delta-v is spent lifting off or landing; the rest is the
cruise:

- **To the surface:** depart, cruise, then descend onto the pad or camp. From the base's station it
  goes straight to the descent.
- **From the surface:** the run starts landed on the origin pad (the `ascent` phase). Lift off with
  Space, or Esc for full lift on auto. At 1.5 km (`ascent_clear_m`) the moon drops away, and the run
  either approaches the base's station or goes into the cruise.
- **Pad to camp:** a hop across the same ground, a descent from a standing start.
- **The camp has no beacon,** so no autopilot: you land it by hand, within 60 m (`camp_zone_m`).
- An orbital moon-base run landed on the pad leaves the ship at the pad and still pays the 25% bonus.

**At a surface site** the dock works as usual. Taking the helm puts you on the pad, landed: F shuts
down, and you can walk out. The bank's tug lifts a bankrupt captain's ship up to the station, because
the plain starter cannot lift off.

## Things on foot (`scripts/surface_finds.gd`)

- **Samples:** five glowing rock samples around the base pad and five around the camp, each tagged
  SAMPLE. Walk up and press E to bag one. They are placed fresh every 10 days.
- **Salvage:** a wrecked lander lies near the camp. E strips two salvage parts, and it can be
  stripped again every 20 days.
- **Selling:** finds go in the ship's locker (`profile.samples`, `profile.salvage`) and sell at any
  dock with SELL FINDS: 350 cr a sample and 1,400 cr a salvage part (`landing.json` "finds").
  `profile.finds_taken` remembers what has been taken.

## Kinds of world

Each system's moon is one of four bodies (`landing.json` "bodies"), picked from the system id through
`body_order`:

| Body | Gravity (m/s²) | Ground |
|---|---|---|
| Grey moon | 1.62 | grey |
| Ice moon | 0.9 | pale blue |
| Dust moon | 1.25 | tan |
| Heavy moon | 2.6 | rust |

Gravity sets the lift you need. The starter with two legs can land about 33 t on a grey moon but only
about 4.5 t on a heavy one, so heavy moons call for more legs. The descent heading shows the body's name.

## Tests for surface work

`tests/smoke_surface.gd` covers:

- the board shows surface work only to a lander, and it pays more;
- port to camp by hand, with no autopilot at the camp;
- lifting off the camp to the base's station;
- taking the helm at the pad;
- walking out to bag a sample (once only), stripping the wreck, and selling both;
- the moons differing from system to system.

`tests/capture_surface.gd` renders the camp, the wreck and a sample.

## Not yet

- Atmospheres and rovers. (Landing away from the pads, at the outpost, the ice mine and the glass crater, is in `sites.md`.)
- Lift-jet torque: the jets push through the centre of mass wherever the legs are bolted.
