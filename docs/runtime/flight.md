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

An active local contract can be flown instead of autopiloted: the dock's FLY THE RUN opens the flight scene in
transfer mode (`Session.flight_job`). There is no station. The destination is a diamond marker far off
(`TransferFlight.plan` sets the distance so a perfect full-burn, flip, full-brake run spends exactly the hop's
delta-v, which is the figure the board prices fuel on; tested to match to 0.2%). The ship leaves loaded and
about 35 degrees off the heading, and the pilot has to line up, burn, flip at the BRAKE NOW cue (X runs the
retrograde autopilot) and stop within 1.5 km at under 8 m/s. `,` and `.` change time compression (x1 to x60); it
drops to x1 when the target is near or closing fast. Fuel is whatever the flight actually burned, so sloppy flying
costs more than the DEPART autopilot's textbook figure. Esc turns back (fuel and hours charged, the load stays
aboard at the start). Running dry means a tug and a tow fee. Arriving settles fuel, the berth fee and the hop's
hours into the sim, then the run is delivered at the dock as before.

## Not built yet

Star jumps and their link to the economy (an interstellar trip is still resolved by the sim), a proper approach and docking at a local site (a flown run just stops at the marker), atmosphere and landing,
collision with anything but the station, and walking inside the ship.
All tuning numbers are placeholders.
