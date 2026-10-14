# Boarding derelicts

Going inside a derelict from a space walk. scripts/flight/boarding.gd (Boarding, owned by OnFoot),
scripts/wreckage.gd (Wreckage: what's aboard), scripts/port_authority.gd (PortAuthority: handing it in),
tuning in data/runtime/traffic.json "boarding".

## The door

- Every derelict has an airlock door point (Traffic, kind "door", id "<wreck id>|door") just outside
  its airlock's outer hatch (`ShipWalk.build(wreck).airlock`), marked with a white frame and amber
  corners. The torch and `door_cut_s` of holding E cut it; the id goes in `profile.salvage_taken` and
  is saved at once, the frame gives way to a dark doorway with a glowing rim, and the point becomes
  kind "enter": hold E briefly to go in. Hands must be free.

## Inside

- `Boarding.enter` builds the wreck's rooms: a ShipView of its layout under the wreck's body (outside
  parts dropped, ceilings solid), powered down (ceiling lights off, glowing materials dark), with a
  red emergency light per compartment, flickering, and a suit lamp (SpotLight3D) on the camera.
  The scene's ambient light and sun are turned right down while you're aboard and restored after.
- You walk it with ShipWalk on mag boots, starting in their airlock. The space walk (sc.eva) carries
  on underneath: the suit's air runs (faster running), the tether waits at their door. Out of air
  inside, the winch drags you out and home (end_space_walk).
- The camera is the wreck body's transform times the walker's eye (FlightScene._apply_pose).
- E: out through the airlock (standing in it), or take what's in reach (`reach_m`). L at the helm:
  the log, up or down. Q in the airlock: out.

## What's aboard (Wreckage.roll, seeded by the wreck id)

- Crew: `crew` people, named in their species' style (Crew.make_name). Each is a survivor (at most
  one; `survivor_chance`, or `deep_survivor_chance` for a wreck stranded out on a route), dead
  (`dead_chance`), or gone in the pod.
- The log: the cause's lines (`causes`, picked from `deep_causes` or `near_causes`), who took the pod,
  who died and where they were laid out, the survivor in the cold bunk, and a last line.
- Items, each with the module it's in (`at`) and a spot: the flight recorder at the helm (bounty
  `recorder_bounty`, times `deep_recorder_mult` far out), `crates` crates of `crate_t` tonnes in the
  holds, `lockers` lockers of patch and spares kits in the airlock or engineering, the dead (bagged,
  `remains_t` each) in the bunks, the survivor (a Figure) in a bunk. Ids "<wreck id>|in|<k>"; taken ones
  stay gone once stowed.
- One thing in hand (SpaceWalk.carry), slower walking while carrying. Out through their airlock you're
  back on the space walk outside their door, still carrying it, and your own hatch stows it.

## Stowing (Salvage.stow) and handing in (PortAuthority, the freight office and the phone)

- Crates and lockers: as hold items. The recorder: `profile.recorders`, no hold space. The dead:
  `remains_t` of hold space each as `Salvage.REMAINS` ("Recovered remains", a runtime-only commodity)
  and `profile.remains`. A survivor goes in a free berth (`Session.free_berths`, which now counts
  survivors aboard), or failing that the ship's one jump seat (free_berths may go to -1, which keeps the
  bar and passengers out of it): `profile.rescued`. With no bunk and the jump seat taken, E reports them
  instead (PortAuthority.report): the port sends its own boat, the item counts as taken, and the freight
  office pays `finder_share` of the bounty and `finder_rep` standing. Nobody is left behind for want of a
  bed. A survivor or the dead aren't let go at a full hatch either: you keep them until there's room.
- At any port's freight office, PORT AUTHORITY: hand in the recorders (the insurer's bounty), hand over
  the remains (`recovery_fee` each, unloaded from the hold), hand over a survivor (`rescue_bounty` and
  `rescue_rep` standing), after which they'll sign on with no hiring fee at their wage, or be seen off.
  Totals in `profile.aboard_record`.
