# Space walks

Out of the airlock in space on a tether, to fix the hull by hand. Code: `scripts/flight/space_walk.gd`
(the suit, the tether and the rules), `scripts/flight/on_foot.gd` (getting out and back, the repairs,
the gauges and the tools). Tuning: `data/runtime/flight_tuning.json` under `eva` (rebuild the warm start
after changing it). Tests: `tests/test_space_walk.gd`; renders: `tests/capture_space_walk.gd`.

## Going out

- At the airlock away from a berth (not on a moon, not mid-jump), E says "suit up and go out on the
  tether". At a berth the airlock still just lets you off.
- Nobody is at the helm: the ship carries on doing whatever it was (throttle, braking autopilot, course
  hold, spin). Time compression is held at x1 while someone's outside.
- The suit is in the ship view's own frame (the frame `ShipWalk` and `ShipDamage` use). WASD drift,
  Space/Ctrl up and down, Shift for more jet, mouse or arrows to look. With no input the suit's stabiliser
  bleeds drift off at 1.2 m/s². The hull (every module cell, pressurised ones out to the skin) is solid.
- Air comes from the suit (the same tanks as on the moon, `SurfaceWork.o2_capacity`). Out of air on the
  tether, the winch reels you in.
- Q at the hatch (or E there with nothing in reach) comes back in. The pause menu has REEL IN THE TETHER.

## The tether and strain

- 30 m (`tether_m`), clipped on just outside the hatch.
- A ship coasting at a steady speed carries the suit along and pulls on nothing. A ship that accelerates,
  brakes or spins does: the suit feels `-a_ship - ω × (ω × r)` in the ship's frame (r from the centre of
  mass), computed each frame from the ship's change in velocity and its angular velocity.
- Taut, the tether's load is the suit's mass (150 kg) times that pull along it, plus the jerk of stopping
  any outward drift (`mass × v_out / tether_give_s`). Over `tether_snap_n` (2,500 N) it snaps. Holding
  taut while the starter brakes at 2 m/s² is about 12% strain; being flung down 30 m of slack by a full
  burn snaps it.
- Snapped, you're adrift: no winch and no limit. The jets still work. More than `adrift_lost_m` (150 m)
  from the hatch, or out of air, and a tug fishes you out and tows the ship in: the tow fee, the flight
  ends (`Session.flight_extra.adrift`, settled in `_settle_hull`).

## Repairs

- The jobs are the scorch marks (`ShipDamage.visible_marks()`). Each is worth 1/16 of the hull
  (`ShipDamage.MAX_SCORCH`). Even-numbered marks are loose plating, odd ones are holes.
- Tools: 1 the wrench, 2 the torch (or the mouse wheel). Hold E or the left mouse button within 2.3 m of
  a mark. The wrench seats loose plating, free, in 4 s. The torch welds a patch over a hole in 7 s and
  uses a patch kit. The wrong tool says so.
- A space walk can't take the hull above 50% (`repair_cap_hull`); the last fix stops at 50%.
- A breached ship (0%) can be brought back: one fix and the helm answers again.
- Fixed marks are kept in `profile.hull_patches`. Holes show a welded plate (`ShipDamage` plates);
  seated plating just looks like plating. A full repair at a yard clears them.
- Patch kits: `profile.patch_kits`, bought at the fuel and repairs desk (`Session.buy_patch_kits`),
  400 cr each at the normal level and site rate, up to 8 aboard.

## On screen

- HUD lines: tether left (or distance adrift), air, the tool in hand and kits, hull and marks left.
- Gauges under them: air (red when low), tether paid out, and strain (green, amber, red).
- The tool in hand, in first person: the wrench rocks while it works, the torch lights a blue flame
  with a glow and lights the hull, and sparks fly from the mark.
