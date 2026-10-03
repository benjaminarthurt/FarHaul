# Economy simulation prototype (step 1)

A headless, deterministic simulation that runs the world data without graphics, as proposed in
`next-development-phase.md`. It lives in `scripts/sim/` and is exercised by
`tests/test_economy_sim.gd`.

```
godot --headless --path . --script res://tests/test_economy_sim.gd
FARHAUL_SIM_VERBOSE=1 godot --headless --path . --script res://tests/test_economy_sim.gd   # prints the event log
python tools/check_world_data.py                                                        # data cross-checks
```

## What it does

Each hour it advances a clock and runs, in the order of `data/runtime/simulation_tick.json`:
consume, produce, procure, allocate lots, update markets, company decisions, contract offers,
carrier dispatch, freight movement, invariant checks.

| Piece | File | Notes |
|---|---|---|
| Route graph | `sim_network.gd` | `routes.json` + `ports.json`, shortest path by distance |
| Inventory ledger | `sim_ledger.gd` | Goods change only through events (produce, consume, reserve, ship, receive). Conservation and `on_hand >= reserved >= 0` are checked every hour |
| Economy | `economy_sim.gd` | Procurement, lots, freight contracts, NPC carriers, hub transfers, payments, prices |
| Scenario | `data/runtime/sim_scenario_hopewell.json` | Facilities, carriers and parameters. **Everything in it is an assumption** |

The chain it proves (no step is scripted):
Hopewell consumes filters, stock falls below its reorder point, procurement sources the filters,
the supplier reserves physical lots, a freight contract is offered, a carrier accepts it, the cargo
is picked up and travels (through hubs where the lot changes ship), Hopewell receives it and its
inventory rises, then the carrier and supplier are paid.

## Behaviours that were added because the long run broke without them

1. **Demand forecast uses demand, not fulfilment.** A first version averaged what was consumed, so a
   stock-out shrank the forecast and made the stock-out worse.
2. **Lead time is stock-aware and learned.** Reorder points cover the time to deliver from a supplier that
   can fill the order, corrected by observed deliveries (capped at 2.5x to avoid a bullwhip).
3. **Orders from a slower supplier also cover consumption during its transit.**
4. **Ships return to their home port when idle**, and count the empty return when pricing a job.
5. **Older freight gets priority**, otherwise small lots starve behind large profitable bundles.

## Baseline result (180 days, no player)

| Facility | Stock-out time | Freight cost / goods value |
|---|---|---|
| Hopewell Water Plant One | 4.2% | 0.65 |
| Tank Farm Co-op (Waystation) | 14.0% | 0.93 |
| Meridian Chandlers Union (distributor) | 18.2% | 1.05 |
| Beacon Heatplant (Lastlight) | 23.5% | 1.58 |

After calibration (2026-10-03): base rate 63 cr per SCU-ly (was 75), and the three loss-making hulls
(Sol Transit A, Redline Co-op A, Meridian Outbound E) removed, since the slice has far more hulls than
freight. Result over 180 days: 312 contracts delivered, about 12 days from offer to delivery, every
carrier solvent, fleet margin about 16% (canon band 8 to 24% in `economic_calibration.json`). The test now
checks both. Going lower than about 57 pushes small carriers underwater; going higher breaks the band.

## Findings for calibration

- **Freight costs as much as the goods (still true after calibration).** At the assumed ship, crew and fuel costs, moving filters three
  jumps (New Houston to Hopewell or Lastlight) costs 0.4 to 1.6 times their value. Lowering the
  per-SCU rate does not fix it: carriers then run at a loss. Faster ships do not fix it either. Cargo
  worth under roughly 1,500 cr per unit cannot be shipped to the frontier at these costs. The levers
  are crew per SCU, fuel price and ship size.
- **Scale beats independents.** Large trunk carriers earn well; a 45 SCU independent loses money on the
  New Houston to Concord leg. That contradicts the lore line about room for owner-operators, so
  either specialty/odd-load premiums or smaller fixed costs are needed.
- **Far producers make remote consumers fragile.** Beacon waits 40 to 60 days when the nearer
  distributor is out of stock. Distributors need real backorders and larger safety stock.
- **The slice is far smaller than the world.** `interstellar_routes.json` lists about 690 ship movements
  per 30 days on New Houston to Concord; this scenario has 13 ships.
- **Hopewell's seed example starts in a stock-out.** 47 filters at 13.4 per day is 3.5 days of cover and
  the fastest delivery is 4.3 days.

- **Stock-outs fixed (2026-10-03).** Buyers now (1) trust observed lead time up to 1.7x the slowest real
  supplier path rather than 2.5x the nearest one, (2) count only inbound shipments that arrive before the
  shelf empties, so a late shipment no longer blocks a second order, (3) never place sliver orders (at
  least 75% of a 14-day cycle), and (4) weight transit time heavily when the shelf will empty first. The
  Chandlers distributor keeps 100 units of safety stock instead of 40. Result over 180 days: Hopewell 4%,
  Beacon 8.5%, Tank Farm 5%, Chandlers 0% stock-out (was 4%, 23%, 14%, 18%). Most of what is left is the
  start-up transient and the long frontier lead time (30+ days).
- **Open:** freight still costs about 0.5 to 0.8 times the goods bought, and about 20% of contracts finish
  after their deadline.

## Assumptions to replace with data

Travel speed 1.5 ly/day (chosen because it gives Ben's 5 to 12 day window for Hopewell), fuel price and
mass units, crew wages and fixed costs, lot size, the filter producer (Roosevelt Filter Works) and
distributor stock, consumer budgets, carrier fleets and bases. No world file names a filter producer.

## Not modelled yet

Production inputs, port capacity and queues, information latency, cargo damage or loss, insurance,
financing, passenger traffic, and the player.
