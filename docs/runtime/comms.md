# Comms: the radio

0.16.0. Code: `scripts/comms/comms.gd` (Comms: who's in range, what you can say, what it costs),
`scripts/comms/radio_voice.gd` (RadioVoice: the voices and radio sounds, made in code),
`scripts/comms/comms_panel.gd` (CommsPanel: the panel and the subtitles). Tuning and every line:
`data/runtime/comms.json`.

## Using it

**Y** anywhere aboard in flight (at the helm, walking the ship, on a space walk, in the suit) opens the
panel: everyone in radio range, nearest first, each with what you can say to them. Click, or press the
number. **Y** or **Esc** closes it. The ship remote has the same list (`state.comms`, action `comms`
with id `contact|option`).

Whatever's being said shows at the bottom of the screen, typing out as it's spoken, panel open or not.
Your own lines are amber, distress calls red. The last 30 lines are kept in the log.

## Who's out there (`Comms.contacts()`)

| Contact | In range | What you can say |
|---|---|---|
| Traffic control | the station is up (not on a cruise), within 60 km | request clearance to dock |
| Pad control (moon base) or the foreman (camp) | coming down to or sitting on the surface | request clearance to land |
| Haulers parked by the port | 25 km | buy fuel; ask for news; a tow when you're dry |
| Movers, tenders, tugs, patrols | 25 km | ask for news; orbiters will tow when you're dry |
| A ship passing on a run | 25 km | news (it won't stop for fuel); a tow when you're dry |
| A ship in distress | 400 km | answer; sell them fuel; take the crew aboard; report them |
| The port tug, by relay | when you're out of fuel or breached | call the tug (the T key's tug) |

## Clearance

- Ask traffic control and you're **cleared to a berth**: the collar's lamps go green. 30% of the time you
  **hold** instead: a ship that was resting out of sight comes out of the collar now, and once it's
  1.5 km out (or 45 s have passed) control clears you.
- **Docking without clearance** (F) costs a fine (300 cr × the difficulty's port fee multiple) and 1
  standing, with traffic control's lecture in the flight's end message. Letting traffic control bring you
  in (T) counts as clearance.
- **Landing**: pad control at a moon base gives you a pad; a camp's foreman points at the flat bit.
  Landing unannounced is the same fine at a base, 120 cr at a camp.
- Coming in at more than 40 m/s within 2 km of the collar, traffic control tells you so (every 90 s).

## Ships

- **Fuel**: a parked hauler sells 2 to 8 t (fixed for the day) at 1.6 × the port's price, 0.4% off per
  point of standing up to 20%. It comes alongside at 30 m/s, matches you, and pumps 0.5 t/s while you
  aren't burning or turning; it nags if you do. What you buy comes off `fuel_burned_t` so the port
  doesn't sell it to you again.
- **News** (`Comms._news`): something from the economy (a facility short of goods, TradeData.tight; a
  system's prices moving 3% or more, TradeData.price_movers), a site in this system that grew, shrank or
  emptied in the last three weeks (Development.recent: `news_grew`, `news_shrank`, `news_empty`, twice as
  likely as the rest), a storm forecast for this system (`news_storm`, first in line: hazards.md), or a
  derelict near the station.
- **Storms**: asking for clearance while a solar storm rages, control advises holding first (`storm_advice`).
- **Claim-jumpers** (Rivals): some salvage crews ignore your beacon (`rival_jump`), won't deal
  (`rival_jump_no`), and can be reported (`you_report`, then `rival_report_go` or `rival_report_stay`). See
  hazards.md. One answer
  per contact per flight.
- **Tows**: dry or breached, any hauler, orbiter or passer in range offers a tow at 0.6 to 1.4 × the
  tug's fee (× 1.3 out on a run). It's the tug's tow with the difference settled at the end.

## Distress calls

On a flown local run (not down to the moon), 20% of runs have a living ship stranded along the route
(`Comms._distress_step`): out of fuel or with a dead drive, 1 to 4 aboard. It calls with an SOS beacon
and a mayday, is tagged in red, and the braking autopilot (X) stops you at it (`Traffic.stops`).
Within 280 m and under 5 m/s you can:

- **sell them fuel**: the 2 to 5 t they ask for, at 2.5 × the port's price; standing +1. The port tops
  you back up at its own price.
- **take the crew aboard**: they become rescued survivors (PortAuthority: the bounty at the next freight
  office, then sign them on or see them off); standing +3. Needs a free bed for each, or the jump seat.
- **report them** when there's no room: standing +1, and the port sends its own boat.

Flying past without helping costs 1 standing ("Somebody heard you hear the mayday").

## Settling up

Nothing is charged mid-flight. `Comms.settlement()` goes in `Session.flight_extra["comms"]` when the
flight ends, and `Session._settle_comms` (from `_settle_hull`) pays for fuel bought, pays out for fuel
sold, settles a hauler's tow against the tug's fee, charges fines, adds the standing and puts a line for
each in the flight's message.

## Voices (`RadioVoice`)

No recordings. Each line is made-up syllables (a buzzing source through three vowel formants, a
consonant burst on most) at the speaker's pitch and pace, then through a cheap transmitter: band-passed
320 to 2900 Hz, overdriven, quantised, hiss that grows with distance, and a fade in and out when far off.
Then a squelch click, and a click and roger beep at the end. Made on a worker thread at 11,025 Hz
(about 0.2 s per line).

| Species | Pitch | Pace | Sound |
|---|---|---|---|
| Human | 110 to 200 Hz | 1.0 | |
| Kesh | 85 to 105 Hz | 0.8 | low, slow, breathy |
| Ilyan | 210 to 260 Hz | 1.35 | high, clipped |
| Vey | 160 to 200 Hz | 1.15 | quick |
| Orun | 115 to 140 Hz | 0.85 | slow, warm, breathy |

Each speaker is seeded by who they are (the ship's name, the station), so the same voice comes back.
Traffic control speaks for the system's home species. Also: the two-tone hail chime and the SOS beacon
(Morse at 1 kHz). Since 0.16.2 the babble is the fallback: lines with a recording are spoken (below).

## Recorded voices (`VoiceBank`, 0.16.2)

`scripts/comms/voice_bank.gd` plays recordings from `assets/audio/voice/` (made by `tools/voice/`, see
its README): 1,260 lines, the aliens' own wording among them, every variation of the berth, fine, tonnes,
crew count, problem, species and price direction, 58 speakers, one to three takes each, 2,633 OGG clips
(mono, 22,050 Hz, 85 MB).

- **Finding the line.** `Comms._line()` remembers which line of which key it picked and what it filled in
  (`_pending`); `_say()` matches the text it's given back to those (`_refs_for`), so a news item picked
  from several, or two lines said together ("fuel_offer" then "fuel_coming"), are each known. Words added
  around a line mean no match. The id is build_lines.py's: `comms:cleared|0|berth=6`. Values are read the
  way the game writes them ("1,300 cr" is 1300; "Kesh" is kesh; the problem is its place in the list);
  names (ships, stations, places, prices) are never spoken, so they don't enter the id.
- **Who says it.** A speaker recorded for every line in the call, of the caller's species if there is one
  (else any in the role), picked by the caller's voice seed, so a station or a ship keeps its voice. A
  take is picked at random, skipping the last four played.
- **How it sounds.** Clips are clean; the transmitter is the `Radio` bus (into Effects): high-pass 320 Hz
  and low-pass 2,900 Hz at 24 dB, light overdrive, a compressor, thinner and grittier with distance. A
  looping carrier hiss plays under it (louder far off), with the squelch opening first (0.14 s) and the
  squelch close and roger beep after. The subtitle types out over the clip's length.
- **In their own words.** The aliens have their own versions of every line (comms.json
  `species_lines`, passengers.json `aboard_by_species`, written by `tools/voice/species_lines.py`): Kesh
  formal and dutiful, Ilyan clipped and exact, Vey warm and communal, Orun always "we". `_say()` swaps the
  caller's species' version in (`_in_their_words`, same arguments) and the recording's id becomes
  `comms:cleared@kesh|0|berth=6`. A line can be [shown, spoken] when the subtitle carries a name.
- **Their own sound** (comms.json `species_sound`). A call opens with `lead_s` of the caller's own language
  (RadioVoice.native, the babble, clean) and the translator's chirp, then the words; a caller heard before
  this flight gets `lead_again_s`. Each species has a bus before the radio (`Voice_<species>_radio`, or
  `_room` aboard): Vey a phaser and a little chorus, Orun a three-voice chorus and a cave reverb, Kesh and
  Ilyan a touch of reverb, plus layers played on their own buses with a pitch shift (Kesh an octave down at
  -8 dB, Ilyan an octave up at -21 dB). All tunable in the JSON; none of it touches the recordings.
- **Passengers** (`PassengersAboard`) say their line out loud once each time you walk up to them, from an
  AudioStreamPlayer3D at head height, unfiltered.
- **Fallback.** No recording for a line (or one part of a two-line call), no index, or Settings >
  Recorded voices off: RadioVoice's babble, as before.
- **Export.** `assets/audio/voice/index.json` is in the export preset's include filter; the clips are
  imported OGG like any other audio.

## Tests

`tests/test_voice_bank_real.gd`: the real bank: every line in `lines.json` has clips, each species' own
lines are said by that species, all 2,633 clips load and have sound, and each species' station clears
you in its own voice.
`tests/test_voice_bank.gd`: ids from game arguments for all 1,260 recorded lines, a speaker per species
and per caller, takes in turn, two lines together, the Radio bus, a recorded line's squelch, words and
close, the babble when off or unrecorded, and a passenger's line id (on a small fixture bank of tones in
`tests/fixtures/voice`).
`tests/test_comms.gd`: voices by species, a line's length, the chime and the beacon; contacts at the
station; clearance with a hold, the green lamps and the log; news; fuel from a hauler (amount, price,
not charged twice); docking cleared and not, and the fine and standing settled when the flight ends;
tug and tow offers when dry; a distress call on a run, out of reach, the braking autopilot stopping at it,
the crew taken aboard a liner, and the standing lost for flying past. Screenshots:
`tests/capture_comms.gd`.

## Rivals and claim beacons (0.16.1)

`scripts/comms/rivals.gd` (Rivals), tuning in comms.json `rivals`.

- **Claim beacons** (`profile.claim_beacons`, 2 to start, 4 at most, 150 cr × the port fee multiple at
  the repair desk and on the remote's shop). Within 2 km of a derelict, the radio lists it with "Fire a
  claim beacon at it". The claim goes in `profile.claims` (by the derelict's `id_base`, so for the day
  it exists): a green light on the wreck and "YOUR CLAIM" on its tag. A wreck someone else claimed has
  an amber light and "CLAIMED", and can't be beaconed.
- **Rivals**: the first time you come within 3 km of a derelict it rolls for a rival (35%, 20% for a
  dead ship out on a route), fixed by the wreck. 40% of those are already there with their beacon on
  it, unless you beaconed it first; the rest turn up 150 to 420 s later while you're within 8 km, fly
  in at 60 m/s, and beacon it if you haven't. Either way they call in.
- They park alongside and cut a piece every 35 to 60 s (a flickering torch light where they're
  working): panels, then the cargo hatch, then the hold (never survivors or the dead). What they take
  goes in `profile.salvage_taken`, gone for the day. Stripped, they leave and the claim lapses.
- **Hail them** (the radio lists "Salvage tug ..."):
  - **Split it**: of what's left, they take every other panel and hold item; the hatch opens for both.
  - **Clear off**: works 85% of the time if your beacon was first, 15% if theirs was, plus 0.5% a point
    of standing (up to 25%). Once only. If they go, the claim's yours.
- **Claim jumping**: taking a piece from a wreck they claimed (or from their half of a split) counts
  against you: at the end of the flight they complain to the port, standing −2.

Tests: `tests/test_rivals.gd` (beaconing, a rival arriving and cutting, warning them off, their claim
first and refusing, claim jumping, a split, buying beacons). Screenshot: `tests/capture_rivals.gd`.
