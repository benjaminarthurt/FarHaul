# Walking the port, the hab and the camp

When your ship is berthed, you are on your feet in the place it is berthed at (`scenes/place.tscn`,
`scripts/place.gd`), not in a menu. New games start there, and flights, the shipyard and the station
terminal all come back to it (`Session.PLACE_SCENE`).

| Where | Room | Desks |
|---|---|---|
| Port, fuel depot, belt works, moon base station | Concourse, 26 × 10 m to 56 × 16 m by the system's tier, with a long window | Freight office, fuel and repairs, shipyard (ports only), bar and bunks |
| Moon base pad | Hab, 20 × 20 m, under a dome | Dispatch, survey lab, suit store, pad fuel and repairs |
| Mining camp | Foreman's hut, 14 × 9 m | Foreman, ore and parts exchange |

Each system's places are built in its own style (architecture, tier and role): see
[identity.md](identity.md).

Every place also has a **terminal** (the old station menu, also on T) and a **gate** or airlock back to
your ship.

## Life in the place

- **People** are low-poly figures (`scripts/figure.gd`). They breathe, glance about, and turn to look
  at you when you come near.
- **Travellers** walk loops round the concourse, and a technician walks round the hab, pausing as they
  go. Their routes keep clear of the furniture. They stop rather than walk into you, and you bump into
  them rather than through them.
- **Through the concourse window** you can see:
  - your own ship, as built, berthed at the end of a boarding arm that meets its airlock;
  - the station's spine, with its trusses and red marker lights;
  - the system's world, far off.
- **The freight board** hangs over the terminal kiosk and lists what is posted here.
- **Through the hab's and the hut's windows** you can see the moon's ground in its own colours,
  boulders, the base's other domes, and your ship on its pad. The view is lit by a hard sun of its own
  (visual layer 2), so the room stays lit from inside.

## Controls

WASD to walk, mouse or arrows to look, Shift to run. E uses the desk in front of you (within 2.4 m).
T opens the terminal. Esc closes a desk, or frees the mouse. The terminal's STEP AWAY FROM THE TERMINAL
button brings you back.

## The desks

- **Freight office, dispatch, foreman:** the jobs posted here, with the fuel each would cost. Once you
  hold a job, the desk offers to fly it yourself or send it on autopilot, and to deliver it on arrival.
  Fly-empty hops are listed underneath. A bankrupt captain can let the bank step in here.
- **Fuel and repairs:** what fuel costs here, the state of the hull, and the price of fixing it. It also
  buys samples and salvage at the standard price.
- **Survey lab** (hab): pays 1.4 times the standard price for samples and takes no salvage.
- **Ore and parts exchange** (camp): buys samples at 0.8 times and salvage at 0.9 times the standard price.
- **Shipyard:** the way into the yard.
- **Bar and bunks:** wait a day.
- **Gate:** fly the run you hold, take the helm, or go aboard and walk the ship (you start at the airlock).

## Port prices and hull damage

- **Fuel** is charged at a price for the kind of site you leave from or land at
  (`local_space.json` `site_fuel_price`). Fuel depots sell at 0.85 times the system price, ports and
  moon stations at 1.0, belt works at 1.15, a moon base pad at 1.3 and a mining camp at 1.6.
- **Hull damage** from a hard landing now stays with the ship (`profile.hull_damage`) until it is
  repaired, and the flight scene starts with it. Repair rates also vary by site (`site_repair_rate`):
  belt works are cheapest at 0.9, a mining camp dearest at 1.5.
- Flights no longer charge a repair on arrival; the bill waits for the repair desk.

## Tests

- `tests/smoke_place.gd`: the concourse, hab and hut build with their desks; walls stop you; a job is
  taken at the freight office; the hull is repaired and paid for; going aboard puts you on your feet;
  the lab and exchange pay their rates.
- `tests/capture_place.gd`: renders the three places to `/tmp/place_frames` (xvfb-run).
- `tests/test_identity.gd`: every system's concourse, in its own style, still works (identity.md).
