# Walking the ship

From the pilot's seat in the flight scene, **G** gets up. You stand behind the seat in the cockpit, turned to
look down the ship, and walk its rooms in first person. **E** at the helm sits back down.

## Rules

- **The ship flies on without you.** Throttle, the braking autopilot and the rotation assist stay as they
  were left. Burn and get up, and the ship keeps burning. The prompt warns you about overheating, running dry,
  a hull impact or the brake point on a run, so you know to get back to the helm.
- **Deck gravity.** The deck plate is always down, whatever the ship is doing. Ship layouts put floors on
  -Y, and thrust pushes along -Z, so real thrust gravity would turn the aft wall into the floor. It is a
  simplification, and it can change later.
- **Doors** are the 1.4 m doorways where two modules' doors meet. Every other side of a pressurised cell is
  solid: the hull, blank walls, the windscreen and doors that open onto space.
- **Furniture and freight are solid.** Seats, the dash, the reactor, bunks, lockers and loaded containers all
  block. Empty container slots are open floor. Anything above 1.5 m (the hold's hook, overhead pipes) does not
  block.
- **Ladder shafts:** stand over the hatch and press E. You go up if you are looking up (or up is the only
  way), and down otherwise.
- **The airlock** lets you off when the ship is at a berth: docked, or still at the spot the flight started
  from and stopped. That ends the flight the same way docking or Esc would. Away from a berth the outer
  hatch stays shut. Space walks come later.
- **Time compression** (`,` `.`) still works while you walk on a local run, so you can cross the ship
  during a long coast.
- Walking is not allowed during a star jump's spool, warp and slowdown.

## Controls

WASD walk, mouse or arrow keys look, Shift run (4 m/s, walking is 2.2 m/s), E use. Esc frees the mouse,
and a click captures it again. In a browser, the first click or key press may be needed before the mouse
locks.

## Code

- `scripts/ship_walk.gd` (`ShipWalk`) is plain maths with no physics engine. The walker is a 0.25 m circle
  on one deck. Walls are slabs built from `ShipData` (cells, doors, which doors mate). Furniture is the
  floor footprint of every mesh the interiors and crates put on the deck between 0.1 m and 1.5 m, read from
  the built `ShipView`. `ModuleDef` tags those nodes `solid`, so new rooms need no extra collision data.
  Moves are taken in 0.1 m sub-steps and the circle is pushed out of anything it overlaps.
- `ModuleDef` tags ceilings, and `ShipView.set_interior(true)` makes them solid while walking. They are
  see-through so the builder can look in from above.
- The airlock's hatch is drawn on the inside of its outer wall as well as on the hull.
- `scripts/flight.gd` has `get_up`, `sit_down`, `use`, `_walk_step` and `_walk_prompt`. The camera rides
  the ship at the walker's eye height (1.65 m).

## Tests

- `tests/test_walk.gd` floods the starter's deck on a 0.1 m grid. From the airlock it can reach the helm,
  both ends of the hold and the front of engineering. It cannot reach a container, the fuel tank, the
  reactor or the windscreen. The test also checks the walls, doorways, running speed, and climbing between
  two decks joined by shafts.
- `tests/smoke_walk.gd` covers getting up and sitting down in the flight scene. The burn goes on while you
  walk, and W walks without touching the throttle. The airlock offers a way off at the berth and not under
  way.
- `tests/capture_walk.gd` renders views from inside the ship (run it under xvfb-run).

## Not yet

- Crew, interacting with anything but the helm, ladders and the airlock, doors that open and close,
  footsteps, and head bob.
- Getting thrown about by hard manoeuvres.
- Walking at the dock without taking the helm first.
- Engineering in the starter is tight: the reactor leaves a strip about 0.6 m deep in front of it.
