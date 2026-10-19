# Planets with air

Code: `scripts/planets.gd` (`Planets`: data, hops, weather, fresh food), `scripts/flight/planet_terrain.gd`
(`PlanetTerrain`), `scripts/flight/planet_scenery.gd` (`PlanetScenery`), the air in `scripts/flight_model.gd`,
the entry in `scripts/flight/landing.gd`. Tuning: `data/runtime/planets.json`. Since 0.19.0.

## Where

Every system's main world has two new sites (`LocalSpace` kinds, both surface sites):

| Kind | What | Beacon |
|---|---|---|
| `world` | The downport: a big lit pad, terminal, tower, hangars and tanks, a few km outside the world's city | Yes |
| `field` | A rough landing field about 5 km from the downport (`field_distance_m`): graded pad, flares, a shed, a windsock | No |

Sol has a third, `mars` (Northern Corridor Downport), with no field. Carver, Port Meridian and Waystation have
no planet to land on (habitats only), so 15 systems have `world` and `field`.

Worlds, gravity and air come from `data/world/worlds.json`; city names from `settlements.json` and
`secondary_settlements.json` where the canon names one (New Houston, Greenline, Keelward, Lowell, Crosswater,
Anchor Seven, Deepworks, Hopewell, Beacon), invented in the canon's spirit otherwise. Roosevelt's downport is
the canon's own New Houston Surface Port.

Each entry in `planets.json` "worlds" has: gravity (g), air (`density` against Earth's sea level,
`scale_km`, `breathable`: species ids or "all"), the land (`land`, `relief_m`, `sea`, colours), the sky and
haze, the city (`city`, `population`, `city_style`), the weather mix and the field's name.

## Hops

To and from a planet the hop isn't the same both ways (`Planets.hop`, through `LocalSpace.hop(a, b, system)`):

- Down: the space part plus `down_dv_kms` (0.4): the air does the braking.
- Up: the space part plus `up_dv_kms × √g` (2.3 km/s at one g; 2.7 on Keshar, 1.7 on Ilos).
- Downport to field: 0.8 km/s, an hour.
- Mars: its own table (`mars_hops`) plus its climb and, to or from Earth's surface, Earth's.

`pay_dv_kms` is the climb either way, so a load brought down pays what a load taken up does. Planet runs
pay `surface_rate_mult` (1.6) over that.

## The board

A planet run only shows to a ship whose lift jets can set a worthwhile load down there and lift it off
again (`LocalSpace.max_landing_cargo_t(stats, system, kind)` at that world's gravity, both ends). The moon's
lander legs (70 kN) can't hold a ship up at one g; **heavy lander legs** (`heavy_legs`: 320 kN, 2.6 t,
36,000 cr) can, three of them for the loaded starter. The contract check's row is "Lift for 0.84 g".

**Fresh produce** (`fresh_produce`, refrigerated, perishable): about a third of the runs from a downport or a
field (not Mars) carry it, at 1.35 times the rate. It keeps for 36 hours from loading (`fresh_hours`), then
loses 2% of its pay an hour down to 30% (`Planets.fresh_left`). The station boards never post it, and the
interstellar economy doesn't trade it (`goods_roles.json` skips it).

## The air

`FlightModel.air` is empty in space and over the moon. Over a planet: density at y = 0 (sea level) falling
off with `scale_m`, drag coefficients, heating and damage.

**Drag** presses on three faces of the ship, its outline from below (`belly_m2`), the front (`front_m2`) and
the side (`side_m2`), worked out from the cells by `ShipStats`. Each face takes `0.5 ρ Cd A v|v|` of the
airflow across it (`cd_flat` 1.15 for belly and side, `cd_nose` 0.45 for the front), so the force follows
the ship's attitude: belly first it brakes hard; tilted, the push on the belly has a sideways part and the
ship glides; nose first it barely slows. The wind (`FlightModel.wind`) is the air's own movement.

**Heat** (`skin_heat`, 0 cold to 1 at the limit): `heat_k · √ρ · v³`, times up to `heat_nose_mult` (1.7) when
the nose takes the flow, less a heat shield's share when the belly does, and shedding `heat_shed_per_s` of
itself a second. Over 1 the hull takes `heat_damage_per_s` per unit over, a second, and the radiators and legs
wear (`heat_wear_per_s`). The entry glow follows `heat_rate`.

**Heat shield** (`heat_shield`, external, under a hull cell: 0.5 t, 8,000 cr): `shield` is the share of the
pressure hull's belly the plates cover. Belly first, a full shield takes the heat down to 1/`shield_tolerance`
(1/1.6). The starter fitted for planets has half its belly covered.

Numbers from the tests, loaded starter with three heavy legs (73.6 t):

| | Earth | Mars | Ilos | Tidemark |
|---|---|---|---|---|
| Heat peak, autopilot, half shield | 67% | 2% | 58% | 64% |
| Same, no shield | 82% | | | |
| Nose first, by hand | 520%, hull gone | | | |
| Fuel to land | 5.4 t | 12 t | 2.3 t | 5.6 t |
| Time, top of the air to the pad | 4 min | 5.5 min | 8 min | 4 min |

## Coming down

A run to a downport or field arrives at the top of the air (`_begin_entry`): 52 km up (scaled by the air's
scale height), 1,900 m/s at 13° down (slower on thin air), belly to the airflow. Where it starts is worked out
by flying the entry ahead of time on the flight model's own air (`Landing.entry_range`), so that drag alone
would bring the ship down `aim_short_m` (2.5 km) short of the pad.

Phase `entry` until the ship is under 9 km and 260 m/s (or 1.5 km up); then `descent`, the landing as on the
moon. Time compression: x5 above 25 km, x2 above 4 km.

**By hand:** arrows and Q/E keep the belly to the air (the HUD's BELLY TO THE AIR); tilt it to steer; Space
lights the lift jets, which belly first push against the fall; W the main engine.

**The autopilot** (T, `FlightModel._autoentry`):
1. Belly to the airflow while it's fast.
2. Under 320 m/s, leans the belly up to 28° toward the pad: the air pushes it over.
3. The landing burn when `burn_due`: the jets plus half the air's braking must stop the fall by 250 m up. In
   thick air it waits below 6 km. In thin air (Mars) it starts high, and once started it leans to take out the
   drift over the ground too.
4. Under 450 m up, slow and not drifting: hands over to the landing autopilot (`autoland`), which flies to the
   pad at up to 55 m/s and sets her down.

The field has no beacon: the autopilot brings her down near it and hands back to the pilot hovering.

**Water**: touching down in the sea (`PlanetTerrain.is_water`) costs `sea_damage` and needs the crawler (a boat
today). Tidemark is open ocean: its downport and field stand on platforms.

## Going up

From a downport or field the run starts landed (`ascent`). Lift off on the jets (T for auto) to 3 km
(`ascent_clear_m`), then `Landing._reach_orbit` burns the climb all at once (`LocalSpace.burn_t` at the ship's
mass for `Planets.up_dv`). If the tanks can't cover it the ship stays in the air and says how short it is.

## The ground

`PlanetTerrain` (a `SurfaceTerrain`, so the flight model's ground code works unchanged): a 40 km height map
(1,024 px, on a worker thread during the cruise) of the world's kind of land, plus a fine noise for the hills
you land among. Sea level is y = 0. The pad, the field and the city are graded flat. Past the map the land
settles to its average.

Kinds of land: coast, islands, ocean, plains, desert, rock, escarpment (great flat benches between cliffs),
plateau (high ground cut by valleys), volcanic (cones).

`PlanetScenery` draws a coarse 40 km mesh with the square under the ship cut out, and a fine 3.2 km mesh that
follows the ship (rebuilt on a worker thread); a skirt to the horizon; the sea; the downport; the field; the
city. The sky (`make_sky`, `update_sky`) goes from the world's colour by day to black up at the edge of space
and at night; the sun follows the world's hour (`local_hour`); the haze thickens with the weather.

**The city** stands about 4.8 km from the downport (`city_xz`), on the skyline. Buildings by population
(`city_size`: 40 for a hamlet, up to 2,400 for ten million), taller and denser toward the middle, in the
world's style (`STYLES`: old, towers, kesh, spires, vey, orun, industrial, agri, research, floating, rigs, vents,
boomtown, frontier, domes). The site's growth stage scales them, as it does a moon base's buildings. At night
the windows light up, street lights come on, and the city throws a glow into the air.

## On the ground

Walking out works as on the moon (`OnFoot`, `SurfaceOps`). Where the air is breathable for the player's species
(`Planets.breathable`) the suit has no tank to run down ("visor up") and there's no breathing hiss. Keshar's
air is breathable to the Kesh only, Ilos's to the Ilyan only; nobody breathes Mars or Foundry. Moon finds and
surface missions are the moon's.

The downport's terminal is a concourse whose window looks out on the planet: the apron, your ship on its pad,
the hangars and the city on the skyline, lit for the hour. The field's shed is a hut.

## Weather

`Planets.weather(system, kind, hour)`: every six hours a draw from the world's own mix (calm, breezy, windy,
gale, rain, dust, snow), with wind speed, gustiness and fog. A solar storm in the system (`Hazards`) can whip it
up into a gale. `Planets.wind_at` adds gusts and more wind aloft. The wind pushes the ship through drag; in a
gale the glide drifts and the landing costs more fuel (Earth: 9.5 t against 5.4).

Below 4 km and on foot, rain, snow and blown dust fall round the camera (`PlanetScenery.set_weather`).
Shown on the descent HUD, the place's info, the freight desk (gales), and downport control's clearance
("Wind 22 m/s from the north-west"); in a gale control says so (`downport_gale`).

## Growth

`world`, `field` and `mars` are sites in frontier growth (`development.json`): the downport at the system's
tier, the field two stages down, Mars one; demand 10, 2 and 4 t a day. Older saves gain them at canon size
(`Development.add_missing`).

## Tests

`tests/test_planets.gd`: which worlds, the hops, the board (lift, fresh food and its spoiling), the ground
(deterministic, flat where it should be, sea and platforms), the air you can breathe, the weather, and entries
on the autopilot onto the pad on Earth, Mars, Ilos, Veyara, Tidemark, Foundry and Lastlight; nose first burns;
the shield runs cooler; Keshar with a light load. `tests/smoke_planet.gd`: the whole run in the flight scene,
down onto Roosevelt, outside, unloaded and delivered; the terminal; the climb to orbit and the refusal when
the tanks are short. `tests/capture_planet.gd` renders the entry, the glide, the city from the air, the pad,
and the city from the ground by day and by night. `tests/capture_worlds.gd` flies down to any list of worlds (with a given
weather, `pelagos:rain`) and renders each from 1.5 km and from the pad.
