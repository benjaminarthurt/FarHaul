# Integrated Runtime

Far Haul now has a specification for the transition from static world data to a living simulation.

A typical causal chain can run:

**households consume goods → warehouse stock falls → company reorders → supplier produces → cargo lot is allocated → freight contract appears → carrier moves it → port and local networks consume capacity → consignee receives it → inventory recovers → payment and memories persist.**

The same machinery extends outward:

**survey information → investment → expedition → outpost → permanent settlement → new consumption and production → recurring freight → established trade route.**

And inward to the ship:

**cargo increases mass → acceleration changes → engines consume power/fuel and generate heat → damaged cooling limits output → maintenance consumes parts → parts demand enters the economy.**

## Simulation levels

The world does not simulate every person and truck at full fidelity. Near the player and for persistent entities, state is individual. At city, planet and remote-system scales, flows are aggregated and refined only when interaction requires it.

## Next engineering boundary

These files are mechanics specifications rather than a finished executable simulation engine. The next software task is implementing these contracts in code, beginning with the state model, deterministic tick scheduler, inventory ledger, ship-network solver and contract pipeline, then running the acceptance scenarios in `runtime_test_scenarios.json`.
