# Flight

Free flight around the dock, reached from the dock's TAKE THE HELM button. No sim time passes and
nothing is spent, so it is practice until star jumps exist.

## Model (`scripts/flight_model.gd`)

Pure code, no 3D, tested headless (`tests/test_flight.gd`). It follows `data/runtime/flight_physics.json`:
acceleration is thrust over current mass, and mass is dry plus fuel plus cargo.

- Thrust pushes along the ship's forward (-Z) axis. Fuel burns in proportion to thrust at the specific
  impulse in `data/runtime/flight_tuning.json`, so the ship gets lighter and accelerates harder as it goes.
- Delta-v comes from the rocket equation and matches a full burn to the tank within 2%.
- Turning slows with mass (a loaded ship is sluggish) and with how far the thrust line sits off the
  centre of mass. The rotation assist damps spin when the pilot lets go.
- The braking autopilot (X) turns the ship retrograde and burns in proportion to the speed left.
- Docking needs the ship within 70 m of the station and under 4 m/s.

## Scene (`scripts/flight.gd`)

The player's saved ship (or the starter) is rebuilt around its centre of mass, with chase and
cockpit cameras and a HUD for speed, closing rate, distance, throttle, fuel, delta-v and mass.
Keys: W/S throttle, Z cut, arrows pitch and yaw, Q/E roll, X brake, R assist, C camera, F dock, Esc dock.

## Not built yet

Star jumps and their link to the economy (a trip is still resolved by the sim), heat and power
limits in flight, collisions, atmosphere and landing, docking alignment, and walking inside the ship.
All tuning numbers are placeholders.
