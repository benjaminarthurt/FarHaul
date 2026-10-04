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

## Not yet

- Taking off from a moon to start a run: you always leave from the base's orbital station.
- Atmospheres, other bodies, landing anywhere but a base, rovers.
- Lift-jet torque: the jets push through the centre of mass wherever the legs are bolted.
