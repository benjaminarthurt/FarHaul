# Living Economy and Institutional Simulation

> Canon status: Draft

This document summarizes the mechanics-facing world layers added around freight operations. Structured JSON remains authoritative for game behavior.

## Credentials and crew

Commercial capability belongs partly to people, not only ships. Operator licenses, EVA certificates, reactor credentials, hazardous-cargo endorsements, passenger qualifications, survey credentials and salvage qualifications can be held by crew. Unless a rule explicitly requires the captain, an assigned qualified crew member can satisfy it.

This makes hiring operationally meaningful: a captain can expand into hazardous freight or survey work by hiring expertise rather than personally mastering every discipline.

## Trade and permits

System governments set duties and permit requirements. Biological imports, controlled chemicals, radioactive material, restricted technology, pharmaceuticals and protected survey samples can require permits. Rules vary by jurisdiction and can be temporarily waived or tightened.

Smuggling pressure should emerge from these differences.

## Ownership and finance

Ships can be individually owned, jointly owned, company owned, cooperative, financed or leased. Loans and yard finance create recorded liens. Insurance can be required by lenders even though governments do not universally require it.

Debt does not magically remove a ship. Repossession is an institutional process requiring lawful access.

## Commercial companies and supply chains

Companies now have explicit inputs, outputs and contract classes. Supply chains connect extraction, manufacturing, agriculture, distribution, construction and frontier support.

Shortages propagate with delay. A missed metal shipment can reduce machinery production; later, agricultural output can suffer; later still, food prices farther outward can rise.

## Ports, fuel and maintenance

Ports have finite berth, crane, tug, specialized-storage and fuel capacity. Congestion can therefore emerge from actual demand.

Fuel availability and price deteriorate outward. Captains choose reserve margins rather than being universally prohibited from risky departures.

Ship components have service intervals and condition. Deferred maintenance raises failure risk instead of creating deterministic breakdowns. Maintenance records affect resale, inspection and insurance.

## Persistent ships

A hull retains its build identity, names, owners, registries, liens, modifications, casualties, repairs, insurance claims, salvage history and notable voyages across owners.

Used ships should therefore feel like individual machines with provenance.

## Crew and passengers

Crew are hired into real roles with pay, credentials and contract expectations. Frontier labor is more expensive and scarce. Crew can remember unsafe treatment or unpaid obligations.

Passengers consume actual habitation, life support, provisions and emergency capacity. Worker transfers, specialists, medical passengers, expedition personnel and private charters create different markets.

## Exploration

Surveying is multidimensional: stellar, navigation, orbital mapping, atmosphere, geology, resource assay, biology and landing-site work each produce data of different quality.

Survey datasets can remain private, be sold exclusively, licensed, embargoed or made public.

## Settlement development

Frontier sites can progress from survey target to expedition camp, prospecting camp, supported outpost, permanent settlement and commercial port. Advancement requires population, infrastructure, transport and economic reasons to remain.

Progress is not guaranteed. Settlements can stagnate or fail.

## Entity graph

`data/world/entity_graph.json` defines the shared relationship vocabulary connecting systems, governments, ports, companies, ships, people, cargo, insurers, contracts, claims and survey data.

Static world files contain established entities. Runtime/save data will use the same IDs and relationship vocabulary for the player's ship, crew, policies, contracts and discoveries.

The design objective is a world where consequences emerge from connected records rather than isolated scripted systems.
