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
- Braking thrusters (`retro_thrusters`, optional, external) fire toward the bow and push the ship backward:
  20 kN each, a quarter of an engine. Low profile (`ModuleDef.hug`): a slim fairing whose `Body` the ship
  view slides flat against the hull face it's bolted to (`ShipView._hug`). They mount on any bare side of the hull (sockets S, E, W, U, D), and
  count only when their nozzles face forward (`ShipStats` `retro`; the builder warns about any that don't).
  The pilot holds **B**; they burn fuel like the rest and scale with power, overheating and hull damage.
  The braking autopilot uses them, nose on, when the ship is moving within 30° of where it points and
  they can stop it within 40 s (`RETRO_STOP_S`), so a docking approach stays lined up; otherwise it flips
  and burns as before. Plumes are tagged `retro_flame` (`ShipView.set_retro_flames`).
  Tests: `tests/test_retro_thrusters.gd`; renders: `tests/capture_retro.gd`.
- Manoeuvring thrusters (`rcs_thrusters`, optional, external) slide the ship without turning it: 10 kN
  each way per pod, sideways (ship X) and up/down (ship Y). Mounts on any face, and is low profile like the
  braking thrusters (a puck under `Body`, slid flat against the hull). The side nozzles turn with
  the module, so a pod turned a quarter round gives no sideways push (`ShipStats` `rcs_x`, `rcs_y`; the
  builder warns). The pilot holds **Ctrl + arrows** (the arrows alone still pitch and yaw); they burn
  fuel and scale like the other thrusters, and do nothing while landed. When the braking autopilot is
  stopping on braking thrusters, it also uses these to take out sideways and vertical drift. Nozzle plumes
  are tagged `rcs_flame` with their push direction (`ShipView.set_rcs`).
  Tests: `tests/test_rcs_thrusters.gd`.
- Power and heat follow `flight_physics.json`: the engines draw power and shed heat in proportion to throttle.
  A power shortfall browns the engines out (thrust scales by generation over demand); heat builds when the
  ship makes more than its radiators shed, and past the limit the engines shut down until they cool.
  The starter's radiators keep up at full burn; a design with too little cooling will overheat.
- The station is solid (spine and ring). A hit above 1.5 m/s bounces the ship and damages the hull, which also
  costs thrust; repairs are charged when the flight ends.
- A damaged hull develops faults (cracked radiators, a fuel leak, cargo knocks) and at 0% the ship is disabled
  until the rescue tug comes. See hull.md.
- Docking needs the nose pointed down the station's axis (within 25 degrees), within 8 m of that axis, within
  18 m of the port, and under 3 m/s. The ship leaves facing away, so the pilot has to turn round.
- Fuel burned and repairs are charged, and the clock advances, when the flight ends (see economy-sim.md).

## Scene (`scripts/flight.gd`)

The player's saved ship (or the starter) is rebuilt around its centre of mass, with chase and
cockpit cameras and a HUD for speed, closing rate, distance, throttle, fuel, delta-v and mass.
Keys: W/S throttle, Z cut, B braking thrusters, arrows pitch and yaw, Q/E roll, X brake, R assist, C camera,
F dock, T traffic control or the tug, Esc the pause menu (which also ends a free flight or turns a run back:
`FlightScene.menu_actions()`).
G gets up from the seat to walk the ship (see walking.md).

### The hull and the engine (`scripts/ship_skin.gd`, `scripts/engine_parts.gd`)

In flight, on the title screen, in the dock and in the port's windows the ship wears an outer hull.
The builder leaves it off so you can see into the compartments.

- The skin stands 0.5 m off the pressure walls of every pressurised compartment and is plated over
  every outward face. Edges and corners between outward faces are rounded (radius up to 1.2 m, less
  where a window or hatch needs the flat plate). Only the outer quarter of each round is built, so
  nothing of it reaches back into a compartment.
- It leaves openings, each lined through to the pressure wall: the helm's windscreen and side
  windows, the airlock's outer hatch, and the reactor's vents. Unused doorways are plated over.
- Unpressurised parts (engine, radiators, tanks, jump drive, cargo racks) are moved out by the
  skin's depth so they sit on it rather than in it. Landing legs stay where they are.
- At an inside corner (the airlock against the main hull, say) each rounded edge runs on, point by
  point round its curve, until it meets the other compartment's hull, so the two close on each other
  even when their radii differ; flat plates run on under the neighbour's skin. `tests/test_ship_skin.gd`
  casts rays out from the gap between wall and skin and fails if any escape.
- With the skin on, ceilings are always solid: there is nothing to see in from above, and from inside
  you would otherwise see the hull through them.
- The engine is an open bell with a rolled copper lip and a glowing throat deep inside. The plume is
  a shader: a pale hot core with faint shock diamonds inside a wider, fading outer plume that spreads
  as it leaves the bell. Its length and brightness follow the throttle (`ShipView.set_throttle`).
  Lander lift jets are smaller bells with their own plumes. Seen end-on (the chase camera) a soft
  glow at the mouth stands in for the plume, fading as the view moves round to the side.

### Worlds in the sky (`scripts/flight/sky_worlds.gd`, `data/world/sky_worlds.json`)

Every system shows its own world, and Sol shows the real ones. Maps are equirectangular JPEGs in
`assets/planets/` made by `tools/make_planet_maps.py`: Earth's coastlines are NOAA GLOBE data (via the
`global-land-mask` package); Mars, Luna, Venus, Jupiter, Saturn, Europa and Titan follow their real
looks; every other world is generated from its canon in `data/world/worlds.json` (each generator
function quotes the line it draws on), so Keshar has shallow jade seas under a yellow haze, Ilos has
escarpments under violet air, Veyara is ocean with island arcs, Foundry has lava cracks, and so on.
Lived-on worlds have a `_mask.jpg` (water, city lights, lava).

The shader lights a day and a night side, adds drifting clouds tinted by the world's air, shining
water, city lights on the night side and glowing lava; a shell adds the air's glow on the sunlit
limb. Gas giants skip clouds and seas; Saturn (and Port Meridian's giant) get rings, with the
planet's shadow across them. `size` and `distance` in the data draw the giants bigger and further off
(the camera's far plane is 16 km for them). Each world turns its `face` longitude toward you.

| Site in Sol | In view | Far off |
|---|---|---|
| Main port, fuel depot | Earth | Luna |
| Moon station (and its pad and camp) | Luna | Earth |
| Belt works | Mars | Jupiter |
| Venus cloud port | Venus | Earth |
| Jovian works | Jupiter | Europa |
| Saturn ring yards | Saturn | Titan |

Other systems show their world from every site, with a neighbour from `data/world/system_bodies.json`
far off: usually the system's gas giant (Tor, Elen, Oruvai, Arbitrator, Longhorn, Rainmaker, Hammer,
Breaker, Stormhold), otherwise a moon or icy world. Carver, Port Meridian and Waystation have no
lived-on world in canon, so they show what is there: Carver's fuel giant Prospector with rocky Cinder,
the ringed giant Meridian that the port orbits with its icy moon Layover, and Crossroads, the airless
rock under the Waystation habitat, with Burnt Rock nearer the star.

Sol's landing body is always Luna (the grey moon); other systems pick one from `body_order`.

When a run reaches its destination (or a jump reaches the new system), the scenery is rebuilt for
the place you're arriving at (`SpaceScenery.rebuild_for`): its station and its worlds, not the ones
you left.

## The map (`scripts/star_map.gd`)

M opens the map in flight (sitting, walking or in a suit) and in ports, the moon hab and the camp hut.
Tab switches between the system chart and known space; the wheel or +/- zooms (out past the system
steps to known space, well in on known space steps back); drag pans; Home recentres; M or Esc closes.
The ship keeps flying while it's open. In a port the walking keys are held while it's open, and the
mouse is freed and given back when it closes.

- **System chart.** The star, orbits and belts, and every body in `data/world/system_bodies.json`
  (stubs skipped). Orbits are squashed (radius = square root of the orbit in AU; Sol uses the real AU,
  others a guess by body type) so inner worlds and giants fit together. Moons, habitats and stations
  sit round the system's main world. Sites are placed by kind: the port and depot by the main world,
  the moon base, pad and camp at its moon, the belt works on the belt, Sol's outer stations at their
  planets. A close-up, bottom left, names the crowded sites round the main world.
- **On a run** the route is drawn origin to destination, flown part solid, with the ship placed by
  progress (1 - range / run distance), a blue arrow for where it's going and a green one for where the
  nose points (signed angles off the route, seen from above). The panel gives distance, closing speed,
  arrival time (and the real time at the current compression), time compression and fuel.
- **Known space.** Every system at its `coordinates.json` position seen from above, the routes from
  `routes.json` (heavier traffic, thicker line), coloured by tier, your system ringed green and a jump's
  destination ringed amber with the jump line.

The scene hands the map its state through `StarMap.source` (`FlightScene.map_state()`,
`PlaceScene.map_state()`). `tests/test_star_map.gd` covers the layout and the keys;
`tests/capture_map.gd` renders it.

## Flying a local run (`scripts/transfer_flight.gd`)

An active local contract can be flown instead of autopiloted: the dock's FLY THE RUN opens the flight scene with
the run (`Session.flight_job`). It has three phases.

1. **Depart.** The ship undocks from the origin site's station as in free flight, and the destination is a diamond
   marker about 35 degrees off the way the ship leaves. Time compression unlocks 1 km out; the cruise starts 3 km clear.
2. **Cruise.** The station drops away. `TransferFlight.plan` sets the distance so a perfect full burn, flip and full
   brake spends exactly the hop's delta-v, the figure the board prices fuel on (tested to match to 0.2%). Line up,
   burn, flip at the BRAKE NOW cue and stop within 1.5 km at under 8 m/s. X hands the stop to the
   autopilot at any point in the cruise: it turns tail-first, coasts while there is room (the prompt
   counts down to the burn), then follows a stopping curve to the target (`FlightModel._brake`, planned
   on 80% of full thrust), taking out sideways drift as it goes. Started too late it says it will
   overshoot. Moving away from the target, or off a run, X stops the ship where it is. X again or any
   control takes over.
   Course hold (V): line the nose up within 5 degrees of the diamond and press V, and it keeps the
   direction of travel on the target from then on (`FlightModel._course`). It steers; the throttle stays
   the pilot's. Burning, it spends the push on any sideways drift first (taken out over about 4 s) and
   the rest toward the target; coasting, it trims drift over 0.3 m/s with small burns of its own (at
   most 20% throttle), then rests the nose on the target. A turn key, X (the braking autopilot takes
   over) or V again lets it go. Out of the 5 degrees, V says how far off you are.
   Out of fuel, T calls a tug to whichever is nearer: on to the destination, and the run is
   delivered (berth fee plus the tow), or back to the start. A tug can't land a ship, so a run to the
   surface is towed back. The prompt says which, and the fee.
   Finding the way: an orange arrow round the edge of the screen points to the target (or the station)
   when it is off screen, with its distance; a yellow arrow does the same for the direction of travel
   when that points elsewhere. On screen, the travel and reverse markers are labelled, and the readouts
   give the course error ("2.1° off target").
   `,` and `.` change time compression (x1 to x60) and `/` goes straight back to x1. The rate shows top
   right. What runs is the rate chosen, brought down to the limit where the ship is (`_warp_limit`):
   - x1 until 1 km out from the station (the readout counts it down), on the approach to the station,
     and at the brake point when flying by hand (so the BRAKE NOW cue can't flash past);
   - x5 within 25 km of the target and x2 within 5 km: reduced, not stopped;
   - never so fast that the target is less than 10 real seconds away at the current closing speed.
   The rate chosen comes back by itself as the limit lifts. When it is capped the readout shows the
   rate running, the rate chosen and why. Every press of `,` `.` or `/` answers on screen. The braking
   autopilot works at any rate.
3. **Approach.** Arriving at the marker brings up the destination's station and rests the ship 1.5 km off its
   collar. Docking uses the free-flight rules (nose down the axis, close, under 3 m/s) and settles the run. T
   in this phase is an autopilot dock, so the approach is never a trap.

Fuel is whatever the flight actually burned, so sloppy flying costs more than the DEPART autopilot's textbook
figure; hull repairs from collisions are charged too. TURN BACK in the pause menu (or F at the origin) during depart or cruise turns back
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

Inputs are locked from J until the approach. Before J, TURN BACK in the pause menu or docking back turns the flight round (fuel
charged, the load stays aboard). `tests/smoke_jump.gd` runs the whole sequence headless;
`tests/capture_jump.gd` renders its frames to PNGs under xvfb-run for looking at it.

## Not built yet

Atmosphere and landing, and collision with anything but the station. Walking inside the ship is in walking.md.
All tuning numbers are placeholders.
