# Far Haul World Data

This directory is the machine-readable source of truth for the **Far Haul** known-space setting.

Narrative lore is intentionally stored alongside structured gameplay fields so the game, tools, procedural systems, UI, maps, and design documentation can all consume the same canonical data.

## Files

| File | Purpose |
|---|---|
| `known_space.json` | Top-level manifest and worldbuilding rules |
| `species.json` | Playable species, home systems, biology, culture and engineering identity |
| `systems.json` | Known populated systems, destinations, population, economy and narrative identity |
| `routes.json` | Direct trade/navigation relationships between systems |
| `corridors.json` | Named multi-system commercial corridors |\n| `yards.json` | Orbital shipyards, build tiers, service costs, hangars and starting-yard choices |\n| `commodities.json` | Freight goods, physical loading data, base values and handling requirements |
| `coordinates.json` | Draft 3D gameplay coordinates and travel/fuel model inputs |
| `markets.json` | Per-system commodity stock, demand and baseline local price multipliers |
| `ports.json` | Physical freight terminals, docks and spaceports with hull limits, fees and services |
| `worlds.json` | Detailed planets, moons, belts, habitats and stations: environment, settlement rationale, culture and visual identity |
| `history.json` | Shared calendar, setting eras and major historical events |
| `survey_regions.json` | Exploration states, frontier regions, supply gateways and survey design rules |
| `frontier_systems.json` | Named uninhabited systems beyond Lastlight, their bodies, survey state, hazards and commercial outlook |
| `settlements.json` | Cities, habitat districts and frontier towns that make inhabited worlds recognizable |
| `organizations.json` | Major manufacturers, standards bodies, survey authorities, cooperatives and salvage firms |
| `local_color.json` | Bars, markets, industrial landmarks and other memorable place-level details |
| `cultures.json` | Everyday culture, households, food, names, etiquette, work and death traditions for the five playable species |
| `shared_culture.json` | Trade Common, timekeeping, mixed-species accommodations, crew practice and freight slang |
| `civic_issues.json` | Grounded commercial, legal and civic tensions that can generate stories and contracts |
| `ship_culture.json` | Species-origin shipbuilding philosophies, hybrid commercial traditions and lived-in ship details |
| `naming.json` | Ship naming patterns and station nickname conventions |
| `manufacturers.json` | Spacecraft and equipment manufacturers with industrial histories and reputations |
| `ship_classes.json` | Recognizable current and legacy commercial freighter families |
| `equipment_brands.json` | Named engines, reactors, life-support, thermal and cargo equipment |
| `carriers.json` | Major, regional and cooperative freight operators |
| `incidents.json` | Industrial accidents, rescues, shortages and famous freight events |
| `notable_people.json` | Historic engineers, captains, surveyors and working frontier figures |
| `flavor_text.json` | In-world advertising, port signs, used-ship listings and freight-board copy |
| `rumors.json` | Grounded, explicitly uncertain rumors suitable for ambient dialogue and leads |
| `system_bodies.json` | Secondary planets, moons, belts and orbital geography for all 18 inhabited systems |
| `local_routes.json` | Intra-system freight lanes and the cargo flows that sustain local economies |
| `industrial_sites.json` | Named shipbreakers, test ranges, observatories, warehouses, mines and other working sites |
| `derelicts.json` | Retired infrastructure and ordinary salvage/legacy sites without mystery-box assumptions |
| `port_services_lore.json` | Dockers, surveyors, chandlers, brokers, tug crews, inspectors and frontier service availability |
| `daily_life.json` | Media, crew lodging, food/provisioning and commercial training |
| `law_customs.json` | Freight documents, customs practice and jurisdictional differences |
| `hazards.json` | Regional weather, traffic, environmental and navigation conditions affecting freight |
| `businesses.json` | Ordinary chandlers, surveyors, parts shops, lodging and frontier suppliers |
| `communications.json` | Relay networks, frontier data latency, radio terminology and example traffic |
| `insurance_finance.json` | Hull/cargo insurance, ship loans and owner-operator financial realities |
| `governments.json` | Independent system governments, jurisdictions and registry authorities |
| `ship_registration.json` | Vessel registration states, renewal, major modifications and yard compliance behavior |
| `insurance_rules.json` | Optional insurance certificates, restrictions, violations, detection and cancellation risk |
| `port_access_rules.json` | How core, industrial, outer, frontier and informal ports treat registration and insurance |

## Stable IDs

All relationships use stable snake_case IDs.

Examples:

```json
{
  "home_system_id": "keshar",
  "homeworld_id": "keshar_prime"
}
```

and:

```json
{
  "id": "new_houston_hesperus",
  "a": "new_houston",
  "b": "hesperus"
}
```

Display names may change without breaking references. IDs should only change when the underlying canonical entity changes.

## Narrative Is Data

Narrative information belongs in JSON when it describes a canonical entity.

A system therefore contains both simulation-facing information:

```json
{
  "population": 74000,
  "exports": ["rare minerals"]
}
```

and authored worldbuilding:

```json
{
  "narrative": {
    "summary": "Commercially exceptional mineral deposits triggered a rapid boom...",
    "gameplay_identity": "Highly profitable one-way freight with poor backhaul availability."
  }
}
```

This allows the same record to drive codex text, procedural contracts, economy balancing, map tooltips, NPC context and future worldbuilding tools.

## Relationship Model

`systems.json` defines places.

`routes.json` defines direct edges between them.

`corridors.json` groups those edges/systems into recognizable commercial regions.

Do not infer direct travel solely because two systems occur in the same corridor. Route records are the authoritative direct trade/navigation relationships.

The current route network is a **gameplay/trade topology**, not yet literal stellar geometry.

## Canon Status

The initial files use:

```json
"canon_status": "draft"
```

because stellar coordinates, travel distances, detailed planetary astronomy, political jurisdictions, chronology and many destination-level details remain to be defined.

Suggested future statuses:

- `draft` — accepted direction, still expandable/changeable
- `canon` — authoritative for implementation
- `deprecated` — retained for migration/history but no longer current

## Worldbuilding Rules

Every populated location must answer:

1. **Why did people settle here?**
2. **Why do people remain here?**
3. **What does this place need from somewhere else?**

The third question is particularly important because worldbuilding should create freight gameplay.

Additional setting assumptions:

- First contact occurred generations before game start.
- Multispecies commerce is ordinary.
- Species do not map cleanly to political borders.
- Joint colonies and multispecies ports are normal.
- Species affects biology, ergonomics, environmental preferences and cultural/engineering history, not RPG-style career bonuses.
- Exploration extends the commercial network rather than replacing it.

## Current Known Space

The initial dataset defines **18 primary known systems**:

- Sol
- Keshar
- Ilos
- Veyara
- Orun
- Concord
- New Houston
- Hesperus
- Iron Gate
- Carver
- Bradbury
- Pelagos
- Tidemark
- Foundry
- Port Meridian
- Talos
- Waystation
- Lastlight

It also defines five playable species:

- Humans
- Kesh
- Ilyan
- Vey
- Orun

## Frontier

Lastlight is currently the principal gateway from populated space toward:

```text
KNOWN SPACE
    ↓
SURVEYED / UNINHABITED
    ↓
PARTIALLY SURVEYED
    ↓
CATALOGED / UNVISITED
    ↓
UNMAPPED SPACE
```

Future discoveries should be representable using the same system schema. A discovered system can therefore move through survey and settlement states without requiring an entirely different data model.

## Planned Extensions

The current structure deliberately leaves room for:

- real/catalog stellar designations
- 3D stellar coordinates
- jump/travel distances
- travel-time calculation inputs
- planets and moons as richer standalone records
- orbital stations and surface ports
- factions and governments
- corporations
- manufacturers
- commodities
- dynamic markets
- environmental compatibility by species
- local laws and customs
- historical events
- settlement founding dates
- system discovery/survey status
- procedural contract weights
- reputation relationships
- route hazards
- changing populations and development states

These should reference existing IDs rather than duplicate entity definitions.

| `compliance_rules.json` | **Mechanics source of truth** for per-port and per-yard registration, insurance, enforcement, unregistered access, and insurer detection rules |
