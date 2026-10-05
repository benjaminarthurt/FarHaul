# System identity

Every system's places look like that system, worked out from the world data rather than modelled one
by one (`scripts/identity/system_style.gd`, `SystemStyle`). A new system in `systems.json` gets a
style without any extra work.

## What sets the style

| Input | Comes from | Decides |
|---|---|---|
| Architecture | The home species (`home_species_ids`); "patchwork" for multispecies hubs; otherwise "colonial" | Colours, ceiling height, how heavy the columns and beams are, lamp colour, the station's hand |
| Tier | Classification: core, developed, outer, frontier, extreme frontier | Concourse size, how many people walk about, planters and banners, wear, how busy the station is |
| Role | Classification ("capital" for a home system) | Props in the concourse; for colonies, the company livery and a signature feature; the planet's colour |
| Port type | The system's main port in `ports.json` | The station's extra structure in space |
| Landmark | `local_color.json` | The bar's name where it is a bar, otherwise a sign pointing to the landmark |

A system's fuel depot, belt works and moon station use the system's style one tier down: they are
working sites rather than the front door. The moon base's hab and the mining camp's hut take the
system's colours partly (`PlaceBuilder._tint`) and its crowd.

## Architectures

| Style | Systems | Concourse | Station |
|---|---|---|---|
| Human | Sol | Blue trim, information screens | Baseline |
| Kesh | Keshar | Low and dark, heavy columns with orange bands, hazard strips | Heavy rear block, orange bands on the spine |
| Ilyan | Ilos | Tall and pale, slender columns, a gallery, teal light ribbons | A second fine ring, a long needle mast |
| Vey | Veyara | Sea greens, a water channel by the window, hanging plants, haze | Habitat bulbs behind the ring |
| Orun | Orun | Warm stone, low arches, amber lamps | Three stacked discs on the spine |
| Patchwork | Concord, Port Meridian, Lastlight | Mismatched panels, hand-made signs, a vendor's cart | Oddments bolted on at random |
| Colonial | Every other human colony | Livery and signature feature by role (below) | Baseline |

## Colonies by role

| Role | Systems | Livery | Signature |
|---|---|---|---|
| Industrial | New Houston, Iron Gate, Foundry | Yellow | An overhead crane rail with a load on the hook |
| Agricultural | Hesperus | Green, warm walls | Grow troughs hung under pink lamps |
| Extraction | Carver | Rust orange | An ore track by the window with loaded carts |
| Research | Bradbury | White, cyan | Lit sample cases |
| Oceanic | Pelagos | Teal | Sea-water tanks with fish |
| Resource | Tidemark | Ice blue | Frosted feed lines overhead |
| Boom colony | Talos | Raw orange | Container rooms and strings of work lights |
| Transit | Waystation | Red | A departures board over the walkway |

## Tiers

| Tier | Concourse | People walking | Extras |
|---|---|---|---|
| Core | 56 × 16 m | 6 | Planters, banners |
| Developed | 44 × 14 m | 3 | Planters |
| Outer | 36 × 12 m | 2 | Some wear |
| Frontier | 30 × 11 m | 1 | Stains, conduit on the ceiling, patched plates, failing lamps |
| Extreme frontier | 26 × 10 m | 1 | All the above, worse |

## Stations by port type

Freight terminals have a container yard aft. Industrial ports have smelter stacks and radiator fins.
Trade ports have a berth ring busy with visiting ships. Transfer ports have docking arms. Frontier ports
have bare scaffold and one solar wing. Surface and floating ports are orbital transfer platforms, with
a tether down to the world. Added structure stays behind or outside the ring, so the approach to the
collar along +Z stays clear. It is solid to the flight model.

## Tests and renders

- `tests/test_identity.gd`, for every system:
  - its style is complete, home systems use their species' style, and no two systems look the same;
  - every desk can be stood at and walked to from the gate, and walkers' routes keep to open floor;
  - the station leaves the approach clear.
- `tests/capture_identity.gd` renders each system's concourse three ways, then its hab and hut.
- `tests/capture_stations.gd` renders each system's station.
- `tests/print_styles.gd` prints the style each system gets.
