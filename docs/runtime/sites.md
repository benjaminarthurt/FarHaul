# More of the moon: sites and hazards

Code: `scripts/surface_sites.gd`. Tuning: the `sites` block of `data/runtime/landing.json`.

Every system's moon has three more places beyond the base pad and the mining camp. They are placed from
the system id on the side away from the camp, so each moon has its own layout and it never changes.

There are no beacons and no jobs there. Take the helm at the base pad or the camp, fly over by hand, set
down, and walk out. In free flight on the moon, the readout lists how far each site is.

| Site | Distance from the pad | What is there |
|---|---|---|
| Abandoned outpost | 1.5–1.9 km | Its old landing pad (flat), three domes and a leaning mast. Strip 3 salvage parts every 20 days. |
| Ice mine | 2.0–2.4 km | A worked-out pit 60 m across and 9 m deep. Four ice cores to cut every 10 days, 600 cr each. |
| Glass crater | 2.9–3.3 km | A crater 300 m across and about 100 m deep. Two glass crystals on its floor every 30 days, 2,500 cr each. |

## Getting into the glass crater

The crater's walls are steeper than 30°, which is more than the suit can walk up. You have two ways in:

- **Land on its floor.** The middle of the floor is flat.
- **Walk in and use suit jets to get out.** You can walk down the wall, but only the jets get you back up.

## Hazards

| Hazard | On foot | When landing |
|---|---|---|
| **Boulders.** About 40 round each site and the camp, never on a pad. | You walk round them. | Setting down within 3 m of the edge of one costs 12% of the hull. |
| **Slopes.** | You cannot walk up ground steeper than 30°. | Landing on ground steeper than 10° costs 1.2% of the hull per degree over 10°. |

A hazard shows on screen for five seconds after the landing.

## Who buys what

| | Samples | Salvage | Ice cores | Glass crystals |
|---|---|---|---|---|
| Standard (dock, fuel desk) | 350 | 1,400 | 600 | 2,500 |
| Survey lab (hab) | 1.4 × | — | — | 1.4 × |
| Camp exchange | 0.8 × | 0.9 × | 1.3 × | 0.8 × |

A desk that takes nothing of a kind leaves it in your locker. The locker counters are `profile.samples`,
`salvage`, `ice` and `rare`.

## The ground mesh

The terrain is drawn finer: 220 squares a side, about 41 m each, so the crater reads as a crater. Its
heights are now worked out once per grid point instead of four times. That makes the mesh quicker to
build than before, even at the finer grid.

## Tests

`tests/test_sites.gd` checks:

- where the sites are, and that they stay put;
- the crater's depth and walls, and the outpost's flat pad;
- that boulders stay off the pads;
- the finds;
- a clean landing at the outpost, and damaged landings on a boulder and on the crater wall;
- that the wall stops you walking out, and the jets lift you out;
- walking round a boulder;
- cutting ice and bagging a crystal;
- what the lab and the exchange pay for them.

`tests/capture_sites.gd` renders the sites from the air and on the ground.
