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

## Not built yet

Star jumps and their link to the economy (a trip is still resolved by the sim), atmosphere and landing,
collision with anything but the station, and walking inside the ship.
All tuning numbers are placeholders.
