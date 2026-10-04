# Working on foot: the suit, surface missions and unloading

Tuning: `data/runtime/surface_work.json`. Code: `scripts/surface_work.gd` (rules and data),
`scripts/surface_ops.gd` (the suit, mission points and crates while you are outside), and the `Session`
functions they call.

## Going outside

- From a moon base pad or a mining camp, the airlock desk (the gate) has **SUIT UP AND GO OUTSIDE**.
  You can also walk aboard and out through the ship's airlock as before.
- **E** uses whatever is in front of you: a sample, the wreck, a mission point, a crate.
- **Q** at the hatch goes back aboard.

## The suit

| | |
|---|---|
| Air | 15 minutes in a plain suit. Running uses it 1.5 times as fast. Below 20% the readout says to head back. |
| Out of air | The crew drag you aboard and bill you 800 cr. Any mission you hold fails. |
| Readout (top left) | Air, jets, the mission and its clock, crates, and the scanner's bearing. |

Coming aboard refills the suit.

The **suit store** in a moon base hab sells:

| Kit | Price | What it does |
|---|---|---|
| Bigger air tank | 4,000 cr | +10 minutes of air (25 in all) |
| Twin air tanks | 9,000 cr | +10 more (35 in all); needs the bigger tank |
| Grip boots | 3,000 cr | Walk and run 30% faster |
| Ground scanner | 6,000 cr | Points to the mission's next point, or the nearest find within 1.5 km, as a distance and clock bearing. Without it, sample tags only show within 45 m. |
| Suit jets | 15,000 cr | Hold Space in the air for 4 s of lift (1.4 × the moon's gravity). About 20 m up from a jump on a grey moon. |

Owned kit is kept in `profile.gear`.

## Surface missions

Two are posted at a time. The hab's **dispatch** desk posts them around the base pad; the camp
**foreman** posts them around the camp. New ones come every two days.

| Mission | Where | What you do | Pay |
|---|---|---|---|
| Place survey beacons | Pad, camp | Walk to three marked points, E at each | 2.6 cr per metre walked, at least 1,200 cr, standing +2 |
| Reach a surveyor out of air | Pad, camp | Get to one point, 350 to 650 m out, and E | 4 cr per metre, at least 2,000 cr, standing +4 |
| Fix a stalled drill | Camp only | Hold E for 5 s on the drill head | 3 cr per metre, at least 1,500 cr, standing +2 |

- **The clock** runs only while you are outside. It allows 1.5 times the walk at 1.6 m/s, plus 90 s.
  Running out of time fails the mission (standing −2), and so does giving it up at the desk.
- Points are marked with a lamp and a label you can see from anywhere. They turn green when done.
- One mission at a time. It is kept in `profile.mission` with its progress and clock.

## Unloading at the camp

The camp has no crane. Delivering there at the foreman's desk offers two ways:

- **Pay the camp crew:** they take 15% of the pay, and unloading takes 8 hours.
- **Unload it yourself:** you go out in the suit and carry the load in 2 t crates.
  - E at the hatch takes a crate. Carrying one, you move at 60% speed and cannot jump.
  - E inside the ring by the hut puts it on the stack.
  - The last crate delivers the load at full pay, with no hours lost.

Elsewhere, unloading still takes the board's usual hours, and the delivery message now says so.
Passengers walk off on their own.

## Tests

- `tests/smoke_surface_work.gd`:
  - buying kit (and the order of the tanks);
  - a survey done on foot and paid;
  - running out of time, and out of air;
  - the jets;
  - a drill freed by holding E;
  - unloading at the camp by hand (full pay, no hours) and by the crew (15%, 8 hours).
- `tests/smoke_place.gd`: the store, dispatch's missions and the suit-up gate.
- `tests/capture_surface_work.gd`: renders a survey point, the readout and carrying a crate (xvfb-run).
