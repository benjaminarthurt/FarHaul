# Far Haul Runtime Model

This directory turns the world model into a simulation specification.

## Six runtime domains

1. **Calibration** — physical units, SCU, economic baselines and reconciliation.
2. **Ships** — modules, networks, mass, thrust, power, heat, life support, damage and repair.
3. **Living economy** — inventories, companies, warehouses, production and information-limited markets.
4. **Contracts/logistics** — procurement, cargo allocation, freight rates, NPC carriers and delivery.
5. **People/world** — schedules, relationships, memory, traffic and systemic events.
6. **Exploration/settlement** — physical system generation, surveying, claims, outposts, settlement growth and new trade.

`simulation_tick.json` defines update order. `save_state_contract.json` defines persistence. `runtime_test_scenarios.json` defines acceptance cases. `runtime_completion_manifest.json` maps the complete program.

Narrative explanations live in `docs/runtime/`. World identity and authored lore remain under `data/world/`.
