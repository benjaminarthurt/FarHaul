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

## Ships and difficulty

**Ship link.** `SimShip.profile(ship)` turns a builder ship into a carrier: cargo mass from the hold
tonnage, cargo volume at a nominal 1,000 kg per SCU, dry-plus-fuel mass, tank size, a crew count,
ownership cost from the ship's price (insurance, financing, depreciation) and speed from thrust-to-weight.
The sim enforces three physical limits per carrier: mass, volume, and fuel range (a leg must fit one
tank; a stop with no priced fuel also needs the way back). Tuning is in `data/runtime/ship_economy.json`.
The starter ship works out at 24 SCU, 24 t, 1 crew, 43 cr/day ownership, 1.5 ly/day, five reachable lanes.

**Parcels.** A ship smaller than a 40 SCU lot takes part of it: the contract is split on acceptance into
a parcel (pro-rata rate, its own lot) and the remainder, which stays on offer. Order totals, ledger
and money are unchanged by splitting (`tests/test_economy_parcels.gd`).

**Difficulty levels.** `data/runtime/economy_levels.json` holds easy / normal / hard (the same ids as
`Worlds.DIFFICULTIES`). Each level scales the player's freight pay, fuel price, port fees, wages,
ownership cost and maintenance. NPC carriers and prices never change with level; a carrier given a
`level` dictionary in the sim uses it. Freight pay above 1 is the owner-operator premium for small,
odd and urgent loads, paid by the consignee. `probe_ship()` is the quick analytic estimate of a ship's
margin on the world's direct lanes; the full simulation confirms it. Three starter ships over 180 days:

| Level | Probe | Simulated | Net per ship per day | Pay multiplier |
|---|---|---|---|---|
| Easy | 31% | 30% | about 290 cr | 1.00 |
| Normal | 17% | 15% | about 130 cr | 0.86 |
| Hard | 2% | 0-3% | a few cr | 0.84 (costs 10-20% higher) |

On hard the ship is a few credits a day from the red, and paid time is the skill: the benchmark is 65%
paid time with 74% of return legs carrying freight (it was 30% before the brine chain below gave the frontier outbound freight, and the pay multipliers were re-solved then; they are now at or below 1 because the world has more freight to find). A captain who idles more loses money. Tests:
`test_economy_levels.gd` (probe, quick) and `test_player_economy.gd` (simulation, about two minutes). To
retune, edit the targets or secondary multipliers and run `tests/solve_levels.gd`, which bisects the pay
multiplier to hit each target margin; rerun it whenever base rates, fuel, ship costs or the starter change.

## The player in the living world

`scripts/sim/sim_world.gd` builds one world per saved game and keeps the player's ship in it as a
manually flown carrier (`manual: true`, so the dispatcher never gives it work). `Session` owns the sim.

- **New game**: the sim warms up 14 days so orders are already in flight, then the player's carrier is
  added from the real ship (`SimShip.profile`) and the world runs on, off the player's books, until the
  home port has freight.
- **Time passes only when the player acts**: depart (runs to arrival), deliver, `wait_days`, and
  `travel_empty` (reposition with no cargo, the way out of a dead-end port). Every day costs wages and
  ownership, so idling and stranding hurt.
- **Board**: `Contracts.offers_from` shows live sim freight first. NPC carriers see new contracts only
  after `npc_board_delay_hours` (12), so the player gets first look. Oversize lots become parcels.
- **Money**: `profile.credits` follows the sim carrier's cash. `SimWorld.sync` folds builder spending into
  `cash_initial` so total money stays conserved.
- **Saving**: the sim is stored in the slot as `data["sim"]`, base64 of `var_to_bytes`. Do not use
  `var_to_str` for this: it rounds floats to about six digits, and reloading then loses credits and breaks
  conservation (this was a real bug, caught by `test_player_flow.gd`). Finished orders older than 20 days are pruned on save.

Tests: `test_player_flow.gd` plays accept, depart, deliver, wait, save, load, a builder spend and 60 days
of work, and checks ledger and money conservation throughout.

**Calibration note.** The solvency calibration is noisy: a single run's margins swing about 10 points with
small parameter changes, so tests use bands, not exact figures. A past commit briefly regressed the
scenario to 13 carriers with three insolvent; it is back to 11 carriers with at most one loser.

**Dock.** TAKE THE HELM flies the ship in free flight (see `flight.md`). The dock shows the day, running costs and how long cash lasts, plus WAIT A DAY and FLY EMPTY
(a nearest-first list with distance, days, estimated cost and freight posted at each stop). A warning
appears when cash covers under a week; a captain in debt with no contract is insolvent and the run is
over (`Session.insolvent`).

**Builder parts.** Crew berths (cockpit 1, crew bunk 1, crew quarters 2) must cover the crew a hold needs
(one, plus one per 40 t of hold). A short crew shows a builder warning and blocks departure. The jump
drive adds 30% cruising speed each (capped at 4 ly/day) and burns 15% more fuel per drive (`fuel_burn_per_drive_speed`), draws 40 kW, sheds 50 kW of heat and weighs
4 t, so it also cuts thrust-to-weight. The starter ship has neither and is unchanged.

**Return freight.** A second chain runs the other way so the frontier port Talos is no longer a dead end:
Hopewell Brine Works (assumed) sells rare dissolved minerals to Roosevelt Mineral Refinery (assumed) through
the Meridian and Concord hubs. The refinery stocks out about 13-16% of the time (tested under 25%), looser than
the filter consumers because its supply line is three hops. Freight nobody wants gets dearer without the
normal cap once it has waited 8 days (`stale_*` parameters), so stranded parcels move, and show up on the
player's board as fat contracts. The fleet is now 12 carriers.

**Flight and the economy.** A flight in free flight costs the fuel burned (at the port's price and the level's
fuel multiplier) plus hull repairs, and the clock moves on by the hours it took (`SimWorld.settle_flight`).

**Bankruptcy.** A captain in debt with no contract can let the bank step in (`Session.restructure`): it takes
the ship at half its price, clears what is owed, and lends a starter hauler with ten days of running costs.
It is recorded as a bankruptcy on the profile.

**Known gaps.** Crew wages are a flat rate per crew member in `ship_economy.json`; ownership cost does follow
the parts, because it is a share of the ship's total price. Lastlight and Waystation still have no outbound
freight of their own. When the sim is absent the legacy contract board is used. The sim covers two goods;
more commodities would make the board richer and need another calibration pass.

## Assumptions to replace with data

Travel speed 1.5 ly/day (chosen because it gives Ben's 5 to 12 day window for Hopewell), fuel price and
mass units, crew wages and fixed costs, lot size, the filter producer (Roosevelt Filter Works) and
distributor stock, consumer budgets, carrier fleets and bases. No world file names a filter producer.

## Not modelled yet

Production inputs, port capacity and queues, information latency, cargo damage or loss, insurance,
financing and passenger traffic.
