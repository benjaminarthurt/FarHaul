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
| Passenger | 1 to 3 people, a bed each, riding along with anything else | (0.25 + 0.35 per seat) × the trip cost, empty, in spare bunks; more in cabins | The hull takes damage on the way (a hard landing), or they're more than 2 days aboard | Half the fare, standing −3 (−2 late) |
| Sealed crate | A crate you do not open. Needs Known standing here | 1.7 × the trip cost | The hull takes damage on the way | 40% of the pay, standing −6 |
| Private contract | Offered only to captains Respected here (most sealed crates become these) | 2.4 × the trip cost | The hull takes damage on the way | Half the pay, standing −8 |

- **Rush jobs** are due sooner than the usual burn gets there. Fly it yourself (a hand-flown run counts
  as flat out, 65% of the usual time), or take the **hard burn** on autopilot: 65% of the time for 130%
  of the fuel. The usual autopilot burn arrives late. A rush job is only offered if your tank can take the
  hard burn with the load.
- **Passengers** are bookings, not contracts (0.15.0, `docs/runtime/passengers.md`): they ride along
  with freight, or on their own, and get off when the ship reaches their site. They need beds: spare crew
  bunks at the basic fare, or passenger cabins at more. One in five wants a cabin and won't take a bunk.
  The starter has no spare beds; `ShipPresets.STARTER_CABIN` adds two crew bunks behind the cockpit.

## Standing

Standing is per place since 0.20.0: see [reputation.md](reputation.md). What it does here:

- People's pay is multiplied by `Reputation.pay_mult` at the place (0.7 Barred to 1.25 Respected).
- Doubtful: two people ask instead of three. Unwelcome or worse: nobody does.
- Sealed crates need Known; private contracts need Respected (`min_tier` in people.json).
- Points per job: +1 for freight delivered (−2 if it arrived broken), +3 for a rush on time, +2 for a
  smooth passenger run, +4 for a sealed crate and +5 for a private contract delivered intact. Late or
  rough work costs points (above). They count with the place and, at half, with its people.

## Tests

`tests/test_people.gd` checks:

- standings and the bonus;
- that who asks is fixed for a day and is not on the board;
- that sealed work is locked;
- a rush on a hard burn on time, and at a profit;
- a rush late on the usual burn;
- passengers refused without a bed, then carried in the cabin starter with no contract taken, with half
  the fare after a hard landing;
- a sealed crate delivered intact;
- +1 standing for ordinary freight.

`tests/smoke_place.gd` checks that the bar lists the people.

## Cancelling a contract

`Session.cancel_contract()` backs out of the active contract before setting off (`cancel_block()`:
not arrived, and at the origin site or system). The load comes off the manifest; a contract taken from
the live economy is released with `EconomySim.player_cancel()`, which puts the freight back where it
was picked up (still reserved for its consignee, `lot.picked_from`), puts the contract back on offer
and frees the player's carrier; refused once the ship has left the origin system. The fee is
`cancel_fee_share` (10%) of the pay, never more than the captain has; jobs from people also cost
`cancel_rep` (2) standing. The freight desk, the station terminal and the ship remote offer it, each
asking for a second press. Tests: `tests/test_cancel_contract.gd`.
