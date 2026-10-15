# The ship remote

A small web server inside the game (`scripts/remote/ship_remote.gd`, `ShipRemote`) serves one page
(`remote/index.html`) so a phone or tablet on the same network can be a second cockpit screen:
the trip, the map, the gauges and the helm. It follows the game: it can only do what the keys do.

## Switching it on

Settings: **Ship remote (phone or tablet)**. Off by default. When on, Settings and the F10 menu show
the address (`http://<this computer's private IPv4>:8417`) and a six-digit code. **New code** makes
a fresh code and unpairs every device. Windows asks once to let Far Haul through the firewall; allow
it on private networks. The server is a node on the scene tree's root, started and stopped by
`ShipRemote.sync()` as each scene opens (`GameSettings.apply_scene`) and when the setting changes, and
it keeps answering while the game is paused.

## Security

- **Local network only.** Requests from anything but loopback, private (10/8, 172.16/12, 192.168/16),
  link-local or IPv6 local addresses get a 403.
- **Pairing.** `POST /api/pair {"code"}` returns a token (a hash of the code); every other `/api` call
  needs it in `X-Remote-Token`. Five wrong codes from one address lock it out for a minute. A new
  code changes the token, so every paired device must pair again.
- Plain HTTP, one request per connection, requests capped at 16 KB.

## The API

| Route | |
|---|---|
| `GET /` | The page |
| `POST /api/pair` | `{code}` → `{token}` |
| `GET /api/state` | Where you are, credits and day; in flight also the gauges, the run, the autopilots, time compression and its cap, what can be done (dock, traffic control, tug) and the cockpit's prompt (`FlightScene.remote_state()`) |
| `GET /api/chart` | The system chart (bodies and sites, from `StarMap`); `?view=space` for known space |
| `POST /api/cmd` | `{action, value, id}` → `{ok, message}` |

Commands go through `FlightScene.pilot(action, value)`, the same function the keys call:
`throttle` (0..1, like holding W/S, and it takes the controls back from the braking autopilot),
`cut`, `brake`, `course`, `assist`, `warp_up`, `warp_down`, `warp_reset`, `dock` (in range),
`traffic` (on the approach: T), `tug` (out of fuel or breached: T), `retro` (braking thrusters, B),
`slide_left` / `slide_right` / `slide_up` / `slide_down` (manoeuvring thrusters, Ctrl + arrows), `jump`
(J, when `_jump_blocker()` allows), `reel_in` (from a space walk, the pause menu's reel-in). Steering
stays at the helm.

`retro` and the slides are holds: each one lasts `FlightScene.REMOTE_HOLD_S` (0.45 s) and the page sends
it again every 250 ms while the button is down, then `value 0` on release. A phone that loses signal
mid-hold lets go by itself. They act like the keys: any of them takes the controls back from the
braking autopilot.

## The page

One self-contained file, no outside fonts or scripts (it has to work with no internet). It polls the
state twice a second and the chart when the system or view changes. Phone: a single column (trip,
map, gauges, helm) with the cockpit's prompt pinned at the bottom; 900 px and wider: the map on the
left, gauges and helm on the right. The throttle is a lever you drag; buttons light when their
system is on; dock, traffic control and the tug only show when the game would let you.

`tests/test_ship_remote.gd` covers the server; `tests/serve_remote.gd` runs a flight with the remote
on for looking at the page in a browser.

## Hull alarms

`/api/state` in flight also carries `disabled`, `can_tug`, `faults`, `leak_t_h`, `cargo_hurt` and
`alerts` (the flight's hull warnings, newest last). The page shows the faults under the hull gauge,
a red banner for the latest alert (the phone vibrates when one is new; OK dismisses it, except a
breach, which stays), greys out the dead controls and offers the rescue tug when disabled.

## Space walks

In a space walk, `/api/state` carries `eva`: `{air, air_max, tether_m, tether_left, distance, strain,
snapped, tool, at_hatch, repairs}`. The page shows a space walk card above the map: air as a clock and
a bar, tether paid out, strain, an adrift warning when the tether has snapped, **Reel me in** (`reel_in`)
and **Cut the engines** (`cut`).

## The ship panel

`status` (in flight and in port, `ShipRemote.status_block`): hull, crew aboard and berths, every
working part's condition (`Wear.parts`), patch and spares kits, the hold, the load. Each crew row has a
`doing` line: in flight from `CrewWork.status()` (the engineer's and deck tech's next job and why
they're waiting, whether the pilot has the helm, the loadmaster and steward), in port a line about
where they are ashore.

## In flight: the radio

`/api/state` in flight carries `comms` (`Comms.state()`): the contacts in range with their options
(`{id, text, enabled, why}`), the last lines said, and what's being said now. The page shows them as a
Comms card; a tap sends action `comms` with id `contact|option` (`Comms.act_id`). See
`docs/runtime/comms.md`.

## In port: the desks

When the current scene is the place scene or the station terminal (`ShipRemote._in_port`: a saved game,
not the shipyard, not a flight), `/api/state` carries `port` (`ShipRemote.port_state()`, cached until
credits, day, site, crew, contract status or kits change, or 5 s): the active contract and what it
allows (`can_depart`, `hard_burn`, `can_deliver`, `camp`), the freight board plus people with work
(`board`, rows with `id`; with a contract on, only passengers, who ride along), the long-haul passengers
(Passengers.long_haul), the passengers aboard (`passengers`), the crew with wages and severance, today's
candidates, free berths, and the repair desk's prices. Port actions take an `id` where they need one:

`accept` (board id), `depart`, `hard_burn`, `deliver`, `wait` (a day), `hire` / `fire` (person id),
`buy_patch_kit`, `buy_spares_kit`, `repair`, `overhaul`. Each is the Session call the desk makes.
After one, an open desk redraws (`_refill`); after departing, delivering or waiting the scene reloads
so the place matches where the ship now is. Port actions are refused in flight ("berth first") and in
the shipyard. Flying a run yourself still starts at the gate in the game. Letting crew go takes two
taps on the page.

The page swaps the helm and gauges for **The desks** (Freight, Crew, Repairs tabs) in port. Lists are
redrawn only when their data changes, so a tap isn't lost to the twice-a-second poll.

`tests/serve_remote.gd -- seconds hull flight|eva|port` serves each case for a browser.
