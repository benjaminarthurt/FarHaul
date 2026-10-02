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
| `corridors.json` | Named multi-system commercial corridors |
| `yards.json` | Orbital shipyards, build tiers, service costs, hangars and starting-yard choices |
| `commodities.json` | Freight goods, physical loading data, base values and handling requirements |
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
| `registration_economics.json` | Registration fees, validity periods, registry modifiers, inspection types and violation fines |
| `insurance_products.json` | Insurance products, premiums, deductibles, region/history factors and certificate requirements |
| `contract_compliance.json` | Machine-readable registration, insurance and ship-endorsement requirements by contract class |
| `compliance_inspections.json` | Inspection triggers, detection probabilities, scrutiny modifiers and enforcement outcomes |

| `customs.json` | Per-system customs profiles, declarations, inspection methods, scrutiny and clearance outcomes |
| `crime_law.json` | Civil/criminal offenses, legal record states and cross-system record exchange |
| `smuggling.json` | Concealment methods, detection model and smuggling pressure by cargo circumstance |
| `salvage_claims.json` | Salvage asset states, ownership interests, claim types and adjudication outcomes |
| `reputation.json` | Per-organization multidimensional reputation, propagation and decay |
| `organization_relationships.json` | Government/company/institution relationship graph and information-sharing edges |
| `crew_credentials.json` | Captain/crew licenses, endorsements, prerequisites and validity |
| `trade_regulations.json` | System duties, permits and controlled trade categories |
| `ship_ownership_finance.json` | Ownership forms, ship loans, liens, leases and repossession states |
| `law_enforcement.json` | Distinct customs, security, police, investigation, rescue and registry institutions |
| `commercial_companies.json` | Producers, manufacturers, distributors and contract issuers with explicit inputs/outputs |
| `supply_chains.json` | Connected production chains and delayed shortage propagation |
| `branded_cargo.json` | Named commercial products tied to producers and commodity classes |
| `port_capacity.json` | Berths, cranes, tugs, specialized storage, fuel storage and congestion rules |
| `fuel_economy.json` | Fuel types, regional availability, pricing and reserve guidance |
| `maintenance.json` | Component service intervals, condition, deferred maintenance and repair classes |
| `ship_history.json` | Persistent vessel provenance, owners, liens, casualties, repairs and valuation effects |
| `crew_labor.json` | Crew roles, pay, labor markets, contracts and employment relationships |
| `passenger_economy.json` | Passenger classes, requirements, demand and physical capacity |
| `survey_mechanics.json` | Multidiscipline survey progress, data quality, value and publication state |
| `settlement_development.json` | Frontier development stages, needs, advancement and regression |
| `entity_graph.json` | Stable entity types, IDs and relationship vocabulary connecting world and runtime systems |
| `density_manifest.json` | World-density expansion marker |
| `coverage_requirements.json` | Required fields at each geographic and economic scale |
| `system_demographics.json` | Population, major bodies and sectors for inhabited systems |
| `planetary_regions.json` | Regional population and industry aggregates |
| `financial_institutions.json` | Commercial finance providers |
| `port_compliance_profiles.json` | Port operating requirement profiles |
| `commercial_ecosystem.json` | Producers, manufacturers, services and logistics firms |
| `settlement_network.json` | Expanded cities, habitats and frontier settlements |
| `municipal_utilities.json` | Power, water, heat, life-support and municipal utility operators |
| `telecom_media.json` | Local communications providers and media outlets |
| `retail_hospitality.json` | Grocery, hardware, lodging and crew-service chains |
| `housing_property.json` | Housing types, occupancy and property operators |
| `construction_sector.json` | Civil engineering and construction firms |
| `waste_recycling.json` | Municipal/industrial waste and material recovery |
| `local_logistics.json` | Surface freight, rail, drayage and local carriers |
| `employment_economy.json` | Employment-sector distributions by economy type |
| `business_density.json` | Aggregate ordinary-business counts per population |
| `food_systems.json` | Local food production, imports, exports and food security |
| `health_education_networks.json` | Medical and education networks |
| `government_agencies.json` | System and local agencies beyond top-level governments |
| `banking_payments.json` | Consumer/commercial banking and payment infrastructure |
| `leisure_culture.json` | Ordinary recreation, entertainment and civic culture |
| `surface_freight_facilities.json` | Throughput-rated inland ports, depots and terminals |
| `inventory_logistics.json` | Safety stocks, reorder behavior and shortage propagation |
| `land_use.json` | Settlement land-use patterns |
| `demographics_households.json` | Household composition, migration and commuting |
| `small_business_archetypes.json` | Generated ordinary-business types and freight inputs |
| `economic_rhythms.json` | Daily, seasonal and industrial demand cycles |
| `metro_areas.json` | Metropolitan populations, districts, satellites, commuting and freight throughput |
| `municipal_finance.json` | Municipal revenue, budgets and public expenditure |
| `real_estate_costs.json` | Residential, retail and warehouse cost pressure |
| `household_income.json` | Household income levels and boomtown purchasing power |
| `passenger_transit.json` | Metropolitan passenger networks and ridership |
| `surface_vehicle_fleets.json` | Local freight and service vehicle populations |
| `postal_parcel.json` | Mail, parcel and small-parts distribution |
| `factories_processors.json` | Individual industrial plants with labor and throughput |
| `agricultural_sites.json` | Farms, greenhouse and livestock production |
| `mining_sites.json` | Named mines and extraction operations |
| `education_capacity.json` | School and technical/university capacity |
| `medical_capacity.json` | Hospitals, clinics, staffing and specialties |
| `emergency_services.json` | Fire, rescue and emergency medical capacity |
| `daily_city_rhythms.json` | Ordinary weekday traffic and demand schedules |
| `public_procurement.json` | Government and civic freight contract generation |
| `city_generation_standard.json` | Required fields and validation for complete cities |
| `metro_network_expansion.json` | Additional metropolitan regions across known space |
| `secondary_settlements.json` | Secondary cities, towns, camps and outposts |
| `infrastructure_capacity.json` | Power, water, waste, data, civic and storage capacities |
| `population_coverage.json` | Named-versus-aggregate population coverage ledger |
| `warehousing_distribution.json` | Warehouse classes, capacities and distribution centers |
| `utility_plants.json` | Individual power, water and heat infrastructure |
| `ordinary_services.json` | Civilian service-business archetypes |
| `economic_shocks.json` | Local disruption and dependency propagation |
| `world_validation_rules.json` | Cross-dataset consistency and completeness rules |
| `physical_geography.json` | Continental regions, plains, basins, mountains and resource-bearing terrain |
| `hydrology_watersheds.json` | Watersheds, rivers, reservoirs, outlets and water-use constraints |
| `climate_regions.json` | Operational climate zones affecting infrastructure and freight |
| `resource_provinces.json` | Regional mineral, soil and resource endowments |
| `agricultural_belts.json` | Large-scale farming regions, yields and freight nodes |
| `intercity_transport.json` | Rail, road and other corridors connecting planetary settlements |
| `planetary_power_grids.json` | Generation, load, storage and regional grid topology |
| `industrial_corridors.json` | Regional concentrations of linked industry and freight |
| `rural_regions.json` | Rural population, economies and service-access geography |
| `suburban_belts.json` | Commuter belts, housing and metropolitan edge logistics |
| `region_generation_standard.json` | Required physical/economic fields for dense planetary regions |
| `planetary_regions_complete.json` | Complete regional coverage for inhabited worlds |
| `planetary_service_profiles.json` | World-scale civic and infrastructure coverage |
| `system_infrastructure.json` | Orbital depots, relays and transfer facilities |
| `system_traffic.json` | System traffic, support and information density |
| `navigation_infrastructure.json` | Navigation, market relay and rescue-reference infrastructure |
| `interstellar_routes.json` | Mechanics-facing route legs, navigation quality and traffic |
| `rescue_network.json` | Commercial/public rescue coverage and priorities |
| `scheduled_services.json` | Baseline scheduled carrier services |
| `commodity_provenance.json` | Commodity origins, producers and normal destinations |
| `cargo_documents.json` | Origin, custody, biosecurity and controlled-cargo records |
| `commercial_entities_expanded.json` | Insurers, lenders, warehouses and logistics firms |
| `commercial_relationships_expanded.json` | Expanded institutional relationship graph |
| `underwriting_profiles.json` | Insurer preferences and exclusions |
| `baseline_freight_flows.json` | Recurring system-to-system commodity volumes |
| `market_dynamics.json` | Inventory-driven pricing and shortage states |
| `system_trade_balance.json` | System-level structural surpluses and deficits |
| `orbital_interfaces.json` | Surface-to-orbit costs, access and transfer modes |
| `cargo_transfer_services.json` | Crossdock, shuttle, heavy-lift and specialist transfers |
| `ship_operating_modes.json` | Planetary versus orbital freighter tradeoffs |
| `calendar_cycles.json` | Shared calendar, seasons and recurring economic cycles |
| `active_projects.json` | Long-lived projects consuming freight and adding capacity |
| `world_evolution.json` | Simulation update cadence and autonomous world change |
| `asset_histories.json` | Persistent infrastructure histories |
| `sample_vessel_histories.json` | Individual vessel provenance examples |
| `urban_histories.json` | District and neighborhood evolution |
