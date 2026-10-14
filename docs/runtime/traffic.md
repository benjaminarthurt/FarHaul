# Other ships and derelicts

Code: `scripts/npc_ship.gd` (`NpcShip`: someone else's ship to look at), `scripts/flight/traffic.gd`
(`Traffic`: who's where), `scripts/flight/on_foot.gd` (salvage on a space walk: `SALVAGE`,
`_eva_salvage`, `_eva_cut`, `_eva_stow`, `_eva_wreck_hulls`), `scripts/flight/space_walk.gd`
(`spheres`, `carrying`). Tuning: `data/runtime/traffic.json` (rebuild the warm start after changing
it). Tests: `tests/test_traffic.gd`. Render: `tests/capture_traffic.gd`.

## NpcShip

A ship built from a ShipPresets layout (the starters and `NPC_HAULER`): the outer hull
(`ShipSkin.build`) and the external parts, centred on the centre of mass under a `Body` node, nose to
-Z. No interiors. Nav lights (red port, green starboard, white strobes), the engine plume on
`set_flames`, a name tag (`show_tag`: name and distance, within range). A wreck (`wreck`) has the hull
dulled, `ShipDamage` at 85% (scorches, venting, sparks) and no lights. `radius` from ShipStats.

## Traffic

Built for the station the flight is at (`FlightScene._ready`) and rebuilt by `SpaceScenery.rebuild_for`
(a run's destination, a jump's arrival). Lives under a `Traffic` node in the flight scene's frame;
hidden while jumping, on a moon, or when the planet is hidden. Stepped with game time
(`FlightScene._process`).

- **Parked**: at a port, the economy's carriers in this system plus one, between 2 and `parked_max`;
  1 at out-sites. Behind the station (z -25 to -75 m) on a ring `parked_ring_m` out, clear of the
  docking approach from +Z. Named "<COMPANY>  <name>" from the carriers' companies and `names`.
- **Movers**: `movers_max` at ports (1 at out-sites): each rests out of sight for `mover_rest_s`, then
  flies between a point by the station and one `mover_far_m` out (easing in and out at about
  `mover_speed_m_s`), outbound with the engine lit, then the other way next time.
- **Passers**: on a run in cruise, every `passer_every_s` (game time) a ship appears `passer_ahead_m`
  along the route, `passer_side_m` off it, coming the other way at `passer_speed_m_s`; gone once well
  behind. Not near the end of a run.
- **Survey ship**: at ports, one extra mover built from `ShipPresets.NPC_SURVEYOR`, named
  "<survey.label>  <survey.names>", resting 10 to 60 s before its first trip.
- **Pods**: at ports with parked ships, `pods.count` station pods (`ShipPresets.NPC_POD`): each rests
  `pods.rest_s`, then flies at `pods.speed_m_s` from the station's rear module to just beside a parked
  ship and back, with a new parked ship each outbound trip. Tags show within a quarter of `label_range_m`.
- **Orbiters**: `orbiters.count` ships in circular orbit `orbiters.altitude_m` above the planet's surface
  (the last one around its child world, if it has one with a `radius` meta) at `orbiters.speed_m_s`, on
  a tilted plane, nose along the orbit. Named "<role>  <name>" from `orbiters.roles`. Solid like the rest.
- **Solid**: `bodies()` gives each as a sphere (60% of its radius) to `FlightScene.solid_bodies()`, so the
  flight model bounces off them like the planet (`crashed_ship`; the cockpit names the ship).

## Derelicts and salvage

- Per station and day (seeded), up to `derelicts.max` wrecks with `derelicts.chance` (halved for the
  second), `distance_m` from the station (pushed out of the planet if needed), at a random attitude,
  tagged "DERELICT <NAME>" with the distance from any range.
- Each has `points` salvage panels on its outer hull (`ShipDamage.skin_sites`, clear of the scorch
  marks and venting plates), marked with a faint orange cut outline, worth `parts_per_point` salvage
  parts. A panel's id is "<site>|<day>|<wreck>|<panel>"; taken ones are in `profile.salvage_taken` and
  stay gone.
- On a space walk (the ship parked within the tether's reach), panels within 60 m are targets
  (`SALVAGE` + index). The torch (2) and `cut_s` seconds of holding E cuts one free; the parts are then
  carried (`SpaceWalk.carrying`, one panel at a time) and stowed in the locker
  (`profile[SurfaceFinds.KINDS.salvage]`) at the hatch, or when reeled in. Lost if you go adrift.
  Sold at any exchange like other salvage.
- The wreck's compartments are solid to the suit (`SpaceWalk.spheres`, refreshed each step from
  `Traffic.wreck_spheres`).

## Stranded derelicts on the route

- Once per run (`job.key`, seeded "deep|<key>"), with `deep.chance`, while cruising or departing: a
  derelict placed `deep.along` of the way to the target and `deep.side_m` off the line, built from the
  FTL starter, the hauler or the surveyor layout. Tagged "DERELICT · FTL FAILED <NAME>" in orange;
  the cockpit says so once. Panel ids are "deep|<key>|<panel>". Same wreck, same place, if the scene
  is rebuilt on the same run.
- `Traffic.brake_target(target)`: the braking autopilot (X) stops `deep.stop_m` short of a derelict
  that is ahead (within 60 degrees of the velocity) and nearer than the target; brake off and on beside
  it to carry on to the target.
- `Traffic.deep_range(pos)`: time compression is held to x5 within 25 km and x2 within 5 km of it.

Each derelict also has a cargo hatch with a hold behind it: see derelict_hold.md. Deep derelicts are
not placed on runs down to a moon or a surface site, and the sensors' line waits until the cockpit
isn't already saying something.

Derelicts also have an airlock door to cut open and go aboard: see boarding.md.
