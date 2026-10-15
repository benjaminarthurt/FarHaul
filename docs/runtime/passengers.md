# Passengers, cabins and bigger holds

0.15.0. Code: `scripts/passengers.gd` (Passengers), `scripts/flight/passengers_aboard.gd`
(PassengersAboard). Tuning: `data/runtime/passengers.json`; local fares in `data/runtime/people.json`
(`passenger`).

## Bookings, not contracts

A party of passengers is a booking in `profile.passengers`, not the active contract, so a ship carries
freight and people at once, each party going where it's going:

`{id, person, seats, beds, fare, per_seat, local, dest_port_id, dest_system_id, dest_name, booked_day,
due_day, hull_at_accept, species, wants}`

- **Local** parties are asked for in person (People.posted, at the bar, the hab's dispatch desk and the
  camp foreman's), to another site in the system. Fare `(0.25 + 0.35 × seats) × the empty trip cost`
  in spare bunks (`per_seat` is that over the seats). Due in 2 days. One in five wants a cabin.
- **Long-haul** parties ask at the freight office (`Passengers.long_haul`): 2 to 4 parties a day per
  port, 1 to 4 people, to systems the ship can reach (SimWorld.destinations: needs a working drive).
  `per_seat = (150 + 70 × ly) × (1 + standing bonus)`, rounded to 10. Due in `ceil(days × 1.5) + 2`.
  30% want a cabin or better, 12% the stateroom (at most two of them).
- Taking one (`Session.accept_contract` hands a passenger offer to `Passengers.book`) works with or
  without a contract on. The id goes on `local_taken` or `pax_taken` so it leaves the board.

## Beds

| Tier | Where | Fare |
|---|---|---|
| 0 | A spare crew bunk: berths beyond the captain and crew aboard | 1.0× |
| 1 | Passenger cabin (1x1, one door, 2 beds, 7,000 cr) | 1.3× |
| 2 | Passenger quarters 2x2 (4 beds in curtained pods round a lounge, 16,000 cr) | 1.6× |
| 3 | Stateroom 2x2 (2 beds, a double bed, armchairs, a long viewport, 26,000 cr) | 2.5× |

ModuleDef `cabins` (beds) and `cabin_tier`; ShipStats `cabin_beds` ([0, cabin, quarters, stateroom])
and `cabins`. Cabin beds are not crew berths: crew can't be hired into them.

`Passengers.layout(stats)`: beds by tier, what bookings use, then rescued survivors (PortAuthority)
fill spare bunks first and then the cheapest free beds; `over` is survivors with no bed (the jump seat).
`Session.free_berths` is the spare crew bunks left minus `over`, for hiring and for survivors.

A party gets the best free beds when it boards (`assign`, best first, none below `wants`) and the fare
is fixed then: `per_seat × the tier's multiple`, per head (`fare_for`). `why_not` says why one can't
board: no drive for a long haul, no bed of the kind they want, or not enough beds.

## Setting down

`Passengers.set_down()` runs after every arrival: a flown local run or jump (`finish_local_flight`,
`finish_jump_flight`), autopilot (`_depart_local`, `depart_active_contract`), and flying empty
(`travel_empty`, `local_reposition`). Everyone whose stop it is gets off: local parties at their site
(or its moon base's pad), long-haul ones anywhere in their system. Each pays its fare, through
`Session._book`:

- new hull damage since they boarded: half, standing −3;
- otherwise past `due_day`: half, standing −2;
- otherwise standing +2;
- a steward aboard adds their `fare_mult` (and +1 standing at skill 3 or more) and the message says
  what of it was for their care.

`profile.pax_stats` counts parties and fares.

With no contract on, the freight office lists each party aboard with a way to take them there: fly a
local hop by hand (`Session.begin_ferry_flight`, a flight job of kind "run" with `ferry`), or on
autopilot (`local_reposition`, `travel_empty`). The bar lists them too. The station terminal's freight
board and the ship remote list the passengers aboard and the long-haul offers; the remote's board keeps
passenger offers while a contract is on.

## Aboard

`PassengersAboard` puts a Figure for each person (up to `max_figures`) in the room their bed is in,
spread out and clear of doorways, the helm and the airlock. They wear travelling clothes
(`Figure.make(..., "passenger")`): a long coat in a colour no crew job uses, a bright scarf, no belt or
badge, a brimmed hat half the time, a bag in hand. Walk up to one and the prompt says who they are,
where they're going, and what they think of the bed (`aboard` lines; `late` ones once they're overdue).
A steward's post is the passenger rooms first.

## Bigger holds

| Module | Size | Containers | Tonnes | Cost | Mass |
|---|---|---|---|---|---|
| Cargo hold 1x2 | 1x2 | 4 | 24 | 6,000 | 3.0 |
| Cargo hold 2x2 | 2x2 | 8 | 52 | 11,000 | 5.0 |
| Cargo bay 2x3 | 2x3 | 12 | 84 | 15,000 | 7.0 |

Both are walkable, with four doors. A hold two cells wide stacks its containers two high along the
outer walls with the floor open between (`ModuleDef._add_crates`), under a gantry with a bridge
(`Interiors._hold`).

## Old saves

A 0.14 save with a passenger run as its active contract loads with it turned into a booking, in spare
bunks, at the fare it was taken for, with no due day (`Passengers.migrate`).

## Tests

`tests/test_passengers.gd`: the holds (sizes, cheaper per tonne, twelve containers shown), the cabins,
the liner preset (`ShipPresets.STARTER_LINER`), beds best first, picky parties, survivors in spare beds,
a long-haul party in the stateroom riding with interstellar freight and paid in full on arrival, a rough
ride and a late one at half, a local party from the bar riding with a local load, a hand-flown hop with no
contract, an old save's passenger run, the passenger outfit, and what they say aboard.
`tests/test_people.gd` and `tests/test_crew.gd` (the steward) carry passengers the new way.
Screenshots: `tests/capture_passengers.gd`.
