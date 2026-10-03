# Flight

Free flight around the dock, reached from the dock's TAKE THE HELM button. It is still free flight: it costs
fuel and repairs and takes some time, but there are no star jumps yet.

## Model (`scripts/flight_model.gd`)

Pure code, no 3D, tested headless (`tests/test_flight.gd`). It follows `data/runtime/flight_physics.json`:
acceleration is thrust over current mass, and mass is dry plus fuel plus cargo.

- Thrust pushes along the ship's forward (-Z) axis. Fuel burns in proportion to thrust at the specific
  impulse in `data/runtime/flight_tuning.json`, so the ship gets lighter and accelerates harder as it goes.
- Delta-v comes from the rocket equation and matches a full burn to the tank within 2%.
- Turning slows with mass (a loaded ship is sluggish) and with how far the thrust line sits off the
  centre of mass. The rotation assist damps spin when the pilot lets go.
- The braking autopilot (X) turns the ship retrograde and burns in proportion to the speed left.
- Power and heat follow `flight_physics.json`: the engines draw power and shed heat in proportion to throttle.
  A power shortfall browns the engines out (thrust scales by generation over demand); heat builds when the
  ship makes more than its radiators shed, and past the limit the engines shut down until they cool.
  The starter's radiators keep up at full burn; a design with too little cooling will overheat.
- The station is solid (spine and ring). A hit above 1.5 m/s bounces the ship and damages the hull, which also
  costs thrust; repairs are charged when the flight ends.
- Docking needs the nose pointed down the station's axis (within 25 degrees), within 8 m of that axis, within
  18 m of the port, and under 3 m/s. The ship leaves facing away, so the pilot has to turn round.
- Fuel burned and repairs are charged, and the clock advances, when the flight ends (see economy-sim.md).

## Scene (`scripts/flight.gd`)

The player's saved ship (or the starter) is rebuilt around its centre of mass, with chase and
cockpit cameras and a HUD for speed, closing rate, distance, throttle, fuel, delta-v and mass.
Keys: W/S throttle, Z cut, arrows pitch and yaw, Q/E roll, X brake, R assist, C camera, F dock, Esc dock.

## Flying a local run (`scripts/transfer_flight.gd`)

An active local contract can be flown instead of autopiloted: the dock's FLY THE RUN opens the flight scene with
the run (`Session.flight_job`). It has three phases.

1. **Depart.** The ship undocks from the origin site's station as in free flight, and the destination is a diamond
   marker about 35 degrees off the way the ship leaves. Time runs at x1 until the ship is 3 km clear.
2. **Cruise.** The station drops away. `TransferFlight.plan` sets the distance so a perfect full burn, flip and full
   brake spends exactly the hop's delta-v, the figure the board prices fuel on (tested to match to 0.2%). Line up,
   burn, flip at the BRAKE NOW cue (X runs the retrograde autopilot) and stop within 1.5 km at under 8 m/s.
   `,` and `.` change time compression (x1 to x60); it drops to x1 when the target is near or closing fast.
3. **Approach.** Arriving at the marker brings up the destination's station and rests the ship 1.5 km off its
   collar. Docking uses the free-flight rules (nose down the axis, close, under 3 m/s) and settles the run. Esc
   in this phase is an autopilot dock, so the approach is never a trap.

Fuel is whatever the flight actually burned, so sloppy flying costs more than the DEPART autopilot's textbook
figure; hull repairs from collisions are charged too. Esc or F at the origin during depart or cruise turns back
(fuel and hours charged, the load stays aboard at the start). Running dry means a tug and a tow fee. Settling
runs the hop's hours and the berth fee through the sim; the run is then delivered at the dock as before.

## Flying a star jump (`scripts/jump_fx.gd`)

An interstellar contract can be flown too (FLY THE JUMP at the dock; DEPART is still the instant autopilot).
The ship undocks, and once it is 3 km clear of the station, slower than 60 m/s and cool enough (under 90%
heat) the prompt offers J to engage the FTL drive. Then, in the flight scene with no cut:

1. **Spool** (5 s): the star field appears and the stars lengthen from dots to short dashes.
2. **Accelerate** (3.5 s): the stars stretch into long streaks and flow past ever faster, and the field of view
   widens from 70 to 118 degrees.
3. **Flash** (0.5 s): the screen goes white. At the height of it the sim runs the trip (fuel, fees, crew and the
   days it takes) and the world changes: the destination's station is named and the sun moves.
4. **Decelerate** (4.5 s): the white fades and the streaks collapse back to dots as the view returns to 70 degrees.
5. **Approach**: the ship is at rest 3 km off the destination's collar. Docking works as for a local run, and
   docking settles the manoeuvring fuel and any repairs.

**Sound** (`scripts/jump_audio.gd`, `data/runtime/jump_audio.json`): a hum, a rising whine and a rush of noise
play as loops whose volume and pitch follow the jump timeline (the whine's pitch and the rush's volume follow
the same streak value that stretches the stars); an engage chirp plays at J, a sub-bass boom at the flash
with everything ducked under it for about a second, and a soft thud as the ship settles. The six files are
synthesised by `tools/gen_jump_audio.py` (no samples, no licences; rerun it after changing the recipe) into
`assets/audio/jump/`. Any file can be swapped for a recording of the same name. Levels are placeholders to tune
by ear in `jump_audio.json`.

Inputs are locked from J until the approach. Before J, Esc or docking back turns the flight round (fuel
charged, the load stays aboard). `tests/smoke_jump.gd` runs the whole sequence headless;
`tests/capture_jump.gd` renders its frames to PNGs under xvfb-run for looking at it.

## Not built yet

Star jumps and their link to the economy (an interstellar trip is still resolved by the sim), atmosphere and landing,
collision with anything but the station, and walking inside the ship.
All tuning numbers are placeholders.
