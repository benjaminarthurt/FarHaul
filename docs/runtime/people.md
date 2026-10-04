# People with work, and standing

Some work never reaches the freight board. People ask for it in person (`scripts/people.gd`,
`data/runtime/people.json`):

- at the **bar** in a concourse, where they wait by the stools;
- at **dispatch** in a moon base hab;
- at the **foreman's** desk in a mining camp.

Three people ask at each place, and different people come each day. Their jobs are local runs, like the
board's, but they pay a multiple of what the trip costs your ship, so the work covers the fuel when it
is done right.

## The three kinds

| Kind | What it is | Pays | Goes wrong when | Then |
|---|---|---|---|---|
| Rush | A small load, due in 75% of the usual trip time | 1.9 × the trip cost | It arrives after the due hour | Half pay, standing −4 |
| Passenger | 1 to 3 people, one spare berth each | (0.8 + 0.4 per seat) × the trip cost, empty | The hull takes damage on the way (a hard landing) | Half the fare, standing −3 |
| Sealed crate | A crate you do not open. Needs Known standing | 1.7 × the trip cost | The hull takes damage on the way | 40% of the pay, standing −6 |

- **Rush jobs** are due sooner than the usual burn gets there. Fly it yourself (a hand-flown run counts
  as flat out, 65% of the usual time), or take the **hard burn** on autopilot: 65% of the time for 130%
  of the fuel. The usual autopilot burn arrives late. A rush job is only offered if your tank can take the
  hard burn with the load.
- **Passengers** need spare berths: berths beyond the crew the ship needs. The starter has none.
  `ShipPresets.STARTER_CABIN` adds two crew bunks behind the cockpit.

## Standing

`profile.rep`, shown on the HUD while you walk.

| Points | Standing |
|---|---|
| 0 | Unknown |
| 10 | Known: sealed crates are offered |
| 25 | Trusted |
| 50 | Respected |

- Points: +1 for any freight delivered, +3 for a rush on time, +2 for a smooth passenger run, +4 for a
  sealed crate delivered intact. Late or rough work costs points (above).
- Each point adds 0.3% to what people offer, up to 15%.

## Tests

`tests/test_people.gd` checks:

- standings and the bonus;
- that who asks is fixed for a day and is not on the board;
- that sealed work is locked;
- a rush on a hard burn on time, and at a profit;
- a rush late on the usual burn;
- passengers refused without berths, then carried in the cabin starter, with half the fare after a hard
  landing;
- a sealed crate delivered intact;
- +1 standing for ordinary freight.

`tests/smoke_place.gd` checks that the bar lists the people.
