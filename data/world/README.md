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
