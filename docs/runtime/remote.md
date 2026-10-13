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
| `POST /api/cmd` | `{action, value}` → `{ok, message}` |

Commands go through `FlightScene.pilot(action, value)`, the same function the keys call:
`throttle` (0..1, like holding W/S, and it takes the controls back from the braking autopilot),
`cut`, `brake`, `course`, `assist`, `warp_up`, `warp_down`, `warp_reset`, `dock` (in range),
`traffic` (on the approach: Esc), `tug` (out of fuel: Esc). Steering stays at the helm.

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
