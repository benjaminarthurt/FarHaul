# Integrated World Model

Far Haul models civilization as connected layers rather than isolated lore entries.

1. **Known space** — systems, coordinates, corridors, frontier survey geography.
2. **Star systems** — bodies, orbital infrastructure, local traffic, relays, rescue and intra-system freight.
3. **Planets and habitats** — physical regions, climate, hydrology, resources, agriculture, grids and transport.
4. **Settlements** — metros, towns, rural regions, districts, housing, civic capacity and municipal finance.
5. **Institutions** — governments, customs, registries, insurers, lenders, employers, carriers and standards bodies.
6. **Production** — mines, farms, factories, utilities, warehouses and supply chains.
7. **Commerce** — canonical commodities, provenance, documents, inventories, markets and baseline freight flows.
8. **Transportation** — local drayage, planetary corridors, orbital transfer and interstellar scheduled services.
9. **People and daily life** — households, employment, education, healthcare, passengers, crew labor, retail and leisure.
10. **Time and history** — seasons, projects, maintenance, persistent ships/assets, settlement growth and economic shocks.

## Simulation principle

Every important consequence should have a path through the model. A shortage requires consumption and inventory. A boom requires jobs, migration and housing. A factory requires inputs, workers, power, water and outbound logistics. A frontier voyage requires fuel, navigation information and support assumptions.

Named entities provide memorable anchors. Aggregates provide believable scale. The player exists inside the economy rather than being its only cause.

## Authority

Mechanics-facing JSON marked `source_of_truth: true` controls behavior. Narrative documents explain intent and lived experience. Stable IDs connect layers. `tools/validate_world_data.py` and `reference_contracts.json` define the beginning of automated integrity enforcement.

All newly expanded material remains `draft` until explicitly promoted to canon.
