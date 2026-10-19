#!/usr/bin/env python3
"""The aliens' own way of saying the radio and passenger lines, written into data/runtime/comms.json
("species_lines") and data/runtime/passengers.json ("aboard_by_species"). Humans keep the base lines.

How each talks (from data/world/cultures.json):
  Kesh   high gravity, duty and care. Formal, weighty, complete sentences, no contractions. Things are
         "in our care"; work is signed off; safety is a moral matter.
  Ilyan  low gravity, mass and precision. Clipped, exact, metric, impatient with waste. Fragments.
  Vey    semi-aquatic, shared water, shared consequences. Warm, flowing, inclusive; currents and tides.
  Orun   communal burrowers. Always "we", never "I"; frank, no notion of privacy, everyone's listening;
         maintenance is everybody's job.

A line is a string (shown and spoken the same) or [shown, spoken] when the subtitle carries a name the
voice leaves out. Only the game's value names ({berth} {fine} {t} {crew} {problem} {dir}) may appear in
the spoken version; anything else ({place}, {goods}, {wreck}, {you}...) only in the shown one.

Run from the repo root: python tools/voice/species_lines.py   (then build_lines.py)
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

LINES = {
    "kesh": {
        "downport_cleared": [["Freighter, downport control. Pad {berth} is assigned to you. Wind {wind} from the {from}. Keep your exhaust from the terminal.", "Freighter, downport control. Pad {berth} is assigned to you. Keep your exhaust from the terminal."], ["Pad {berth} is cleared, freighter. The air is {wind} from the {from}. Belly first, and the city is not your landing zone.", "Pad {berth} is cleared, freighter. Belly first. The city is not your landing zone."]],
        "downport_gale": [["Freighter, pad {berth}. The wind is {wind} from the {from}. Hold into it and land with care, or do not land.", "Freighter, pad {berth}. The wind is strong. Hold into it and land with care, or do not land."], ["Pad {berth}, freighter. The gusts are {wind}. Three ships have bounced today. Each was entered in the record.", "Pad {berth}, freighter. The gusts are severe. Three ships have bounced today. Each was entered in the record."]],
        "field_cleared": ["Freighter. The field is clear. Land between the flares, upwind of the shed.", ["The ground by the flares has been tested. Wind {wind} from the {from}. Set down there.", "The ground by the flares has been tested. Mind the windsock. Set down there."]],
        "cleared": [
            "Freighter, this is traffic control. Berth {berth} is assigned to you. The collar is lit. Bring her in square.",
            "Acknowledged, freighter. Berth {berth} is yours. The collar has been inspected and signed off. Approach slowly.",
            "Freighter, you are cleared for berth {berth}. The paint was applied with care. Respect it."],
        "hold": [
            "Freighter, hold at two kilometres. A vessel is leaving the collar. Safety first, then you.",
            "Negative, freighter. The collar is occupied by a departing ship. Hold position. Patience is a load-bearing virtue."],
        "after_hold": [
            "Freighter, the departing ship is clear. Berth {berth} is now assigned to you.",
            "The collar is yours, freighter. Berth {berth}. Watch for their wash."],
        "already": [
            "Freighter, you are already cleared. Berth {berth}. A clearance given is a clearance kept."],
        "fined": [
            "Freighter, you docked without clearance. {fine}, and it is entered in the record. The record does not forget.",
            "Freighter, an uncleared docking is a breach of care. {fine}. Call in next time."],
        "pad_cleared": [
            "Freighter, pad control. Pad {berth} is assigned to you. The beacon is lit. Set her down evenly.",
            "Pad {berth} is yours, freighter. The surface has been checked. Gear down, and gently."],
        "camp_cleared": [
            "Freighter. The flat ground east of the hut has been tested. Land there and nowhere else.",
            "The pad is clear. The foreman is watching your descent. He will remember it."],
        "camp_fined": [
            "You landed on this camp without a word. {fine}. Our people were under you.",
            "No call, no clearance. {fine} for the danger. We will speak of this."],
        "speed": [
            "Freighter, you are fast inside two kilometres. Reduce speed. The station was built to last; do not test it.",
            "Freighter on approach, your speed is unsafe. Slow down. We will not say it twice."],
        "greet": [
            "We hear you. State your business.",
            "This is our vessel. Speak, freighter.",
            "We are on a schedule. Be brief, and be clear."],
        "patrol": [
            "System patrol. Keep your speed down near the station. We take care of what is ours.",
            "System patrol. All is in order. We intend to keep it so."],
        "fuel_offer": [
            ["We can spare {t} tonnes at {price} a tonne. The port is cheaper, but the port is far.", "We can spare {t} tonnes. The price is on your screen. The port is cheaper, but the port is far."],
            ["{t} tonnes, {price} a tonne. We will come alongside. Hold your vessel steady.", "{t} tonnes, price on your screen. We will come alongside. Hold your vessel steady."]],
        "fuel_coming": [
            "Coming alongside. Hold steady. We will do the rest.",
            "We are on our way. Make no sudden moves."],
        "fuel_wait": [
            "We cannot couple a hose to a moving ship. Hold still.",
            "Freighter, you are drifting. Hold still. This is for your safety and ours."],
        "fuel_done": [
            "Transfer complete. The fuel is in your care now.",
            "The fuel is in. The account is settled. Fly with care."],
        "fuel_no": [
            "We are moving fast in the other direction. Ask a ship at rest.",
            "We carry only our own reserve. A reserve is not for sale."],
        "tow_offer": [
            ["We will take your line. {fee}. Your ship will arrive whole.", "We will take your line. The fee is on your screen. Your ship will arrive whole."],
            ["We can tow you to port for {fee}. Or you may wait for the tug.", "We can tow you to port. The fee is on your screen. Or you may wait for the tug."]],
        "tug_offer": [
            ["Port tug. {fee} to bring you in. Remain still and we will do the work.", "Port tug. The usual fee to bring you in. Remain still and we will do the work."],
            ["Tug here. {fee}. Keep your hands from the throttle. We have this.", "Tug here. The usual fee. Keep your hands from the throttle. We have this."]],
        "news_tight": [
            ["{place} has been short of {goods} for days. A hauler with a conscience would go.", "Somebody near here has been short of something for days. A hauler with a conscience would go."],
            ["If you carry {goods}, {place} needs you. That is not a figure of speech.", "If you carry the right cargo, somebody near here needs you. That is not a figure of speech."]],
        "news_price": [
            ["Prices at {place} are {dir} {pct}. Plan accordingly.", "Prices are moving {dir} this week. Plan accordingly."],
            ["We hear {place} is {dir} {pct}. Someone has made a mistake, or a fortune.", "We hear prices went {dir}. Someone has made a mistake, or a fortune."]],
        "news_wreck": [
            ["There is a dead ship {km} kilometres out: {wreck}. Its crew deserved better care.", "There is a dead ship out by the station. Its crew deserved better care."],
            ["We passed a wreck, {km} kilometres out. {wreck}. Nobody has seen to it.", "We passed a wreck on the way in. Nobody has seen to it."]],
        "news_grew": [
            ["{place} is growing. Someone has kept it supplied, and it shows.", "A site in this system is growing. Someone has kept it supplied, and it shows."],
            ["We hear {place} has opened more berths. Care is rewarded.", "We hear a site nearby has opened more berths. Care is rewarded."]],
        "news_shrank": [
            ["{place} is failing. Its shelves were left empty. That is a failure of care.", "A site nearby is failing. Its shelves were left empty. That is a failure of care."],
            ["{place} has closed desks. Fewer ships call. It is a shame.", "A site nearby has closed desks. Fewer ships call. It is a shame."]],
        "news_empty": [
            ["{place} has been abandoned. Everyone has left. The record will remember who stopped coming.", "A site nearby has been abandoned. Everyone has left. The record will remember who stopped coming."],
            ["Nobody remains at {place}. Its fittings are unattended.", "Nobody remains at a site nearby. Its fittings are unattended."]],
        "storm_advice": [
            "Advisory: a solar storm is in progress. All vessels are to remain in port. Enter, and stay.",
            "Freighter, the storm is upon us. We are keeping every ship in our care. Come in and wait."],
        "news_storm": [
            ["The weather office warns of a solar storm here, {when}. Shelter is a duty to your ship.", "The weather office warns of a solar storm here soon. Shelter is a duty to your ship."],
            ["A storm is coming, {when}. Radiators suffer in it. We will be in port.", "A storm is coming soon. Radiators suffer in it. We will be in port."]],
        "rival_jump": [
            ["We see your beacon on the {wreck}. We see no patrol. We will be brief.", "We see your beacon. We see no patrol. We will be brief."],
            ["Your beacon is noted. It is not respected. Keep clear of our cutters.", "Your beacon is noted. It is not respected. Keep clear of our cutters."]],
        "rival_jump_no": [
            "No. That is the whole answer.",
            "We heard you. The answer has not changed."],
        "rival_report_stay": [
            "Report us, then. They must catch us first, and they are slow.",
            "File your report. We will be gone before it is read."],
        "rival_report_go": [
            "A patrol is coming? Then we are leaving. This is not an apology.",
            "Paperwork. Very well. We withdraw."],
        "news_none": [
            "There is no news. That is good news.",
            "Nothing to report. All is holding."],
        "news_again": [
            "We have told you all we know. We do not invent."],
        "sos": [
            "Mayday, mayday. Kesh vessel in distress. {problem} We require assistance.",
            "Any ship, any ship. {problem} {crew} aboard in our care. Please respond."],
        "sos_answer": [
            "You answered. We will not forget it. Come alongside.",
            "We see you, freighter. We are holding. Come as you can."],
        "sos_fuel": [
            ["Fuel. Thank you. {t} tonnes at {price} a tonne. We will pay in full.", "Fuel. Thank you. {t} tonnes. We will pay in full."],
            ["{t} tonnes, at {price}. Our household owes yours.", "{t} tonnes. Our household owes yours."]],
        "sos_crew": [
            "You will take us aboard? We will secure the ship first. Then we come.",
            "We are crossing to you. The ship will be recovered later. We will not."],
        "sos_room": [
            "You have no room. Then tell the port. We will keep the lights burning."],
        "sos_bye": [
            "We can reach port from here. Our thanks are not small.",
            "Fuelled and under way. This debt is recorded."],
        "rival_there": [
            "This wreck is in our care, freighter. Our beacon is on it.",
            "Salvage tug. That beacon is ours. Move on, or ask with respect."],
        "rival_claim": [
            "Salvage tug, approaching the wreck. We are placing our beacon now.",
            "This wreck is now in our care. The beacon is set. Do not interfere."],
        "rival_yours": [
            "We did not see your beacon. We should have. Half each, and no one is hurt?",
            "Your beacon, then. The wreck is large. We will take only what you leave."],
        "rival_split": [
            "Half each. We will take every other piece. Respect our half.",
            "Agreed. Your half, our half. The agreement is binding."],
        "rival_warned_ok": [
            "Your beacon was first. The wreck is yours. We withdraw.",
            "The claim is yours by right. We go."],
        "rival_warned_no": [
            "Our beacon was placed first. The law is with us. We remain.",
            "We were here first. You will leave, not us."],
        "rival_warned_no_yours": [
            "Beacon or not, we are cutting. Call the port.",
            "We have heard you. We continue."],
        "rival_done": [
            "We are finished. What remains is yours.",
            "Our hold is full. The wreck is yours to care for."],
    },
    "ilyan": {
        "downport_cleared": [["Downport control. Pad {berth}. Wind {wind}, {from}. Burn away from the glass.", "Downport control. Pad {berth}. Burn away from the glass."], ["Pad {berth}. Belly first. Wind {wind}. The city is not a pad.", "Pad {berth}. Belly first. The city is not a pad."]],
        "downport_gale": [["Pad {berth}. Wind {wind}, {from}. Gusting. Crab into it. Land firm.", "Pad {berth}. Strong wind. Gusting. Crab into it. Land firm."], ["Pad {berth}. Gusts {wind}. Three bounces today. Inefficient.", "Pad {berth}. Hard gusts. Three bounces today. Inefficient."]],
        "field_cleared": ["Field clear. Between the flares. Upwind of the shed.", ["Field. Wind {wind}, {from}, per the sock. Land.", "Field. Watch the sock. Land."]],
        "cleared": [
            "Freighter. Berth {berth}. Collar lit. Two metres a second, no more.",
            "Copy, freighter. Berth {berth}. Square approach. Polished yesterday.",
            "Cleared, berth {berth}. Mind the paint. Paint is mass we did not want to add twice."],
        "hold": [
            "Freighter. Hold at two kilometres. Departure in the collar. Ninety seconds.",
            "Negative. Collar occupied. Hold. Do not burn fuel waiting."],
        "after_hold": [
            "Collar clear. Freighter, berth {berth}.",
            "Freighter. Berth {berth}. Their wake decays in thirty seconds. Wait for it."],
        "already": [
            "Already cleared. Berth {berth}. Repeating costs air."],
        "fined": [
            "Freighter. Uncleared docking. {fine}. Logged.",
            "No clearance. {fine}. Next time, one call. It weighs nothing."],
        "pad_cleared": [
            "Pad control. Pad {berth}. Beacon on. Dust settles in four seconds here.",
            "Pad {berth}. Gear down. Light touch. Low gravity forgives, mostly."],
        "camp_cleared": [
            "Flat ground, forty metres north of the hut. Exactly there.",
            "Pad clear. Descend slowly. The foreman measures."],
        "camp_fined": [
            "No call. {fine}. The dust took an hour to settle.",
            "Uncleared landing. {fine}. And recalibration."],
        "speed": [
            "Freighter, you are fast inside two kilometres. Bleed it. Now.",
            "Too fast on approach. Slow down. The station's mass exceeds yours."],
        "greet": [
            "Go.",
            "Listening. Brief, please.",
            "Proceed. We are on a burn window."],
        "patrol": [
            "System patrol. Speed limits near the station. Observe them.",
            "System patrol. Nominal. Keep it nominal."],
        "fuel_offer": [
            ["{t} tonnes spare. {price} a tonne. Port is cheaper per tonne, not per hour.", "{t} tonnes spare. Price on your screen. Port is cheaper per tonne, not per hour."],
            ["{t} tonnes, {price}. Coming alongside. Hold attitude.", "{t} tonnes, price on your screen. Coming alongside. Hold attitude."]],
        "fuel_coming": [
            "Approaching. Hold attitude.",
            "Inbound. Zero thrust, please."],
        "fuel_wait": [
            "You are moving. Hose alignment fails. Hold.",
            "Stop drifting. We measure in centimetres."],
        "fuel_done": [
            "Transfer complete. Mass updated.",
            "Fuel in. Invoice sent. Efficient."],
        "fuel_no": [
            "Wrong vector. Ask a ship at rest.",
            "No margin. We carried exactly enough."],
        "tow_offer": [
            ["Line accepted. {fee}. Parking excluded.", "Line accepted. Fee on your screen. Parking excluded."],
            ["Tow to port, {fee}. Alternative: port tug, later.", "Tow to port, fee on your screen. Alternative: port tug, later."]],
        "tug_offer": [
            ["Port tug. {fee}. Standard. Hold still.", "Port tug. Standard fee. Hold still."],
            ["Tug. {fee}. Hands off the throttle.", "Tug. Standard fee. Hands off the throttle."]],
        "news_tight": [
            ["{place}: short of {goods}. Several days.", "Somebody near here: short of something. Several days."],
            ["{place} needs {goods}. Demand exceeds supply. Considerably.", "Somebody near here needs your cargo. Demand exceeds supply. Considerably."]],
        "news_price": [
            ["{place}, {dir} {pct}. Noted.", "Prices, {dir}. Noted."],
            ["Prices at {place}: {dir} {pct}. Act or don't.", "Prices: {dir}. Act or don't."]],
        "news_wreck": [
            ["Wreck, {km} kilometres. {wreck}. Untouched.", "Wreck near the station. Untouched."],
            ["Debris field, {km} kilometres out. {wreck}. Mass going to waste.", "Wreck on the way in. Mass going to waste."]],
        "news_grew": [
            ["{place}: growing. Supply up. Good.", "One site, growing. Supply up. Good."],
            ["{place} expanded. Efficient haulers somewhere.", "A site expanded. Efficient haulers somewhere."]],
        "news_shrank": [
            ["{place}: shrinking. Undersupplied. Wasteful.", "One site, shrinking. Undersupplied. Wasteful."],
            ["{place} lost desks. Predictable.", "A site lost desks. Predictable."]],
        "news_empty": [
            ["{place}: abandoned. Fittings still there.", "One site, abandoned. Fittings still there."],
            ["{place}, empty. Pumps run. Nothing else.", "A site, empty. Pumps run. Nothing else."]],
        "storm_advice": [
            "Advisory. Solar storm. Dock and stay docked.",
            "Storm active. Everyone holds. Come in. Wait."],
        "news_storm": [
            ["Storm forecast here, {when}. Shelter. Radiators fail otherwise.", "Storm forecast here. Soon. Shelter. Radiators fail otherwise."],
            ["Storm, {when}. We'll be in port. Sensible.", "Storm, soon. We'll be in port. Sensible."]],
        "rival_jump": [
            ["Your beacon, on the {wreck}. No patrol. Fast job.", "Your beacon. No patrol. Fast job."],
            ["Beacon noted. Ignored. Keep clear.", "Beacon noted. Ignored. Keep clear."]],
        "rival_jump_no": [
            "No.",
            "Still no. Stop transmitting."],
        "rival_report_stay": [
            "Report it. Patrol's hours out. We're minutes.",
            "Call it in. We'll be gone. Efficient."],
        "rival_report_go": [
            "Patrol inbound. Leaving.",
            "Paperwork. Not worth it. Off."],
        "news_none": [
            "No news. Efficient day.",
            "Nothing. Quiet."],
        "news_again": [
            "Already transmitted. Redundant."],
        "sos": [
            "Mayday, mayday. Ilyan vessel. {problem} Requesting assistance.",
            "Any ship. {problem} {crew} aboard. Air for six days."],
        "sos_answer": [
            "Acknowledged. Grateful. Match velocity when able.",
            "We see you. Relief exceeds expectation."],
        "sos_fuel": [
            ["{t} tonnes at {price}. Accepted. Thank you.", "{t} tonnes. Accepted. Thank you."],
            ["{t} tonnes. {price}. A fair exchange, for once.", "{t} tonnes. A fair exchange, for once."]],
        "sos_crew": [
            "Transferring. Personal mass under ten kilograms each. We are fast.",
            "Crossing now. The ship stays. We don't."],
        "sos_room": [
            "No room. Notify the port. We will conserve power."],
        "sos_bye": [
            "Sufficient to reach port. Thank you.",
            "Under way. Debt noted."],
        "rival_there": [
            "Our wreck. Our beacon. Move on.",
            "Salvage tug. Beacon placed. Claim valid."],
        "rival_claim": [
            "Salvage tug, inbound. Beacon deploying.",
            "Wreck claimed. Beacon away. Nothing personal."],
        "rival_yours": [
            "Your beacon. Missed it. Split? Fifty-fifty. Fair.",
            "Your claim. Large wreck. We take the remainder."],
        "rival_split": [
            "Fifty-fifty. Alternating pieces. Stay on yours.",
            "Agreed. Half each. Exactly half."],
        "rival_warned_ok": [
            "Your beacon was first. Leaving.",
            "Valid claim. Withdrawing. Inefficient trip."],
        "rival_warned_no": [
            "Our beacon was first. Check the timestamp. Staying.",
            "We arrived first. You leave."],
        "rival_warned_no_yours": [
            "Beacon noted. Cutting anyway.",
            "Heard. Continuing."],
        "rival_done": [
            "Done. Remainder yours.",
            "Hold full. Wreck yours."],
    },
    "vey": {
        "downport_cleared": [["Freighter, downport control. Pad {berth} is yours. The air's {wind} from the {from}. Keep the burn off the windows, people are waving.", "Freighter, downport control. Pad {berth} is yours. Keep the burn off the windows, people are waving."], "Pad {berth}, freighter. Come in belly first, like a diving bird. The city's for swimming in, not landing on."],
        "downport_gale": [["Freighter, pad {berth}. It's blowing {wind} from the {from}. Lean into it, like a current. Come down when the gust lets go.", "Freighter, pad {berth}. It's blowing hard. Lean into it, like a current. Come down when the gust lets go."], ["Pad {berth}. It's rough today, gusting {wind}. Three ships bounced. We caught them, mostly.", "Pad {berth}. It's rough today. Three ships bounced. We caught them, mostly."]],
        "field_cleared": ["Freighter? Welcome. Land between the flares, on the windward side of the shed.", ["Come down. The sock says {wind} from the {from}. The sock's never lied to us.", "Come down. Watch the sock. The sock's never lied to us."]],
        "cleared": [
            "Freighter, welcome in. Berth {berth} is ready for you. The collar's lit. Drift in easy.",
            "Copy, friend. Berth {berth} is yours. Come in gently, like the tide.",
            "Cleared for berth {berth}, freighter. Mind the paint. Someone took a long time over it."],
        "hold": [
            "Freighter, ease off at two kilometres. Someone's leaving the collar. Let them go first.",
            "Not yet, friend. The collar's busy with someone going home. Hold, and breathe."],
        "after_hold": [
            "They're clear, freighter. Berth {berth}'s yours now. Come in.",
            "The collar's yours, friend. Berth {berth}. Their wake will settle. Give it a moment."],
        "already": [
            "You're already cleared, friend. Berth {berth}. It's waiting for you."],
        "fined": [
            "Freighter, you docked without a word. {fine}. Everyone in the collar felt that.",
            "No clearance, friend. {fine}. It isn't the money. It's everyone else."],
        "pad_cleared": [
            "Freighter, pad control. Pad {berth} is yours. Beacon's on. The dust goes everywhere. Go gently.",
            "Pad {berth} is ready for you. Gear down, and soft. The ground remembers."],
        "camp_cleared": [
            "Freighter? Welcome. The flat ground past the water tanks. Not near the tanks.",
            "The pad's clear. Come down slow. The foreman's growing beans out there."],
        "camp_fined": [
            "You came down without calling. {fine}. You shook the whole camp.",
            "No word before you landed? {fine}. Everyone here felt it."],
        "speed": [
            "Freighter, you're coming in fast inside two kilometres. Ease off, for all of us.",
            "Freighter on approach, slow down, please. Everything you do here, everyone feels."],
        "greet": [
            "We hear you, friend. Go ahead.",
            "This is us. What do you need?",
            "Go ahead. We're listening, all of us."],
        "patrol": [
            "System patrol. Keep it gentle near the station, and we'll all get along.",
            "System patrol. Calm waters today. Let's keep them that way."],
        "fuel_offer": [
            ["We can share {t} tonnes, at {price} a tonne. The port's cheaper, but the port's a long swim.", "We can share {t} tonnes. The price is on your screen. The port's cheaper, but the port's a long swim."],
            ["{t} tonnes, {price} a tonne. We'll drift alongside. Stay still for us.", "{t} tonnes, price on your screen. We'll drift alongside. Stay still for us."]],
        "fuel_coming": [
            "Drifting alongside now. Stay still for us.",
            "On our way, friend. Nothing sudden."],
        "fuel_wait": [
            "You're drifting, friend. We can't line up the hose. Hold still.",
            "Stay with us. Still. There."],
        "fuel_done": [
            "That's your fuel. Go well.",
            "The fuel's in. The bill follows. Safe currents."],
        "fuel_no": [
            "We're flowing the other way, friend. Ask someone at rest.",
            "We've only enough for ourselves. Try a hauler at the port."],
        "tow_offer": [
            ["We'll take your line, friend. {fee}. Nobody gets left out here.", "We'll take your line, friend. The fee's on your screen. Nobody gets left out here."],
            ["We can bring you in for {fee}. Or wait for the tug. Your choice.", "We can bring you in. The fee's on your screen. Or wait for the tug. Your choice."]],
        "tug_offer": [
            ["Port tug. {fee}, same as always. We've got you.", "Port tug. The usual fee. We've got you."],
            ["Tug here. {fee}. Let go of the throttle, friend.", "Tug here. The usual fee. Let go of the throttle, friend."]],
        "news_tight": [
            ["{place} has been short of {goods} for days. They're struggling.", "Somebody near here has been short of something for days. They're struggling."],
            ["If you've got {goods}, {place} needs it more than you do.", "If you've got the right cargo, somebody near here needs it more than you do."]],
        "news_price": [
            ["Prices at {place} are {dir} {pct}. Someone's having a hard week.", "Prices went {dir} this week. Someone's having a hard week."],
            ["Heard {place} is {dir} {pct}. It always comes back round.", "Heard prices went {dir}. It always comes back round."]],
        "news_wreck": [
            ["There's a dead ship {km} kilometres out. {wreck}. Somebody should see to it.", "There's a dead ship out by the station. Somebody should see to it."],
            ["We passed a wreck, {km} kilometres out. {wreck}. Sad, drifting thing.", "We passed a wreck on the way in. Sad, drifting thing."]],
        "news_grew": [
            ["{place} is growing. The current's been kind to it, and somebody kept it fed.", "A site near here is growing. The current's been kind to it, and somebody kept it fed."],
            ["Heard {place} filled out. More hands, more mouths, more work for all of us.", "Heard a site near here filled out. More hands, more mouths, more work for all of us."]],
        "news_shrank": [
            ["{place} is drying up. Not enough coming in. It worries everyone downstream.", "A site near here is drying up. Not enough coming in. It worries everyone downstream."],
            ["{place} is quieter every week. Somebody should take it something.", "A site near here is quieter every week. Somebody should take it something."]],
        "news_empty": [
            ["{place} is empty now. They all left. It's a sad stretch of water.", "A site near here is empty now. They all left. It's a sad stretch of water."],
            ["Nobody at {place} any more. Take what's left, but take it kindly.", "Nobody at one of the sites any more. Take what's left, but take it kindly."]],
        "storm_advice": [
            "Advisory: there's a solar storm on. Come in and stay in. Everyone's waiting it out together.",
            "The storm's up, freighter. We're keeping everyone in harbour. Come in and wait with us."],
        "news_storm": [
            ["The weather people say a storm's coming here, {when}. Find shelter, and tell whoever's behind you.", "The weather people say a storm's coming here soon. Find shelter, and tell whoever's behind you."],
            ["Storm, {when}. Radiators boil in it. We'll all be in port, like sensible fish.", "Storm coming soon. Radiators boil in it. We'll all be in port, like sensible fish."]],
        "rival_jump": [
            ["We saw your beacon on the {wreck}. No patrol, though. We'll take a little and go.", "We saw your beacon. No patrol, though. We'll take a little and go."],
            ["Beacons are just lights, friend. The current takes what it likes. So do we.", "Beacons are just lights, friend. The current takes what it likes. So do we."]],
        "rival_jump_no": [
            "No, friend. Sorry.",
            "We heard you. It's still no."],
        "rival_report_stay": [
            "Report us if you like. The patrol swims slower than we do.",
            "Go on and call it in. We'll be downstream by then."],
        "rival_report_go": [
            "A patrol? Then we're leaving. No hard feelings.",
            "Paperwork. Oh, the paperwork. We're going."],
        "news_none": [
            "No news. Calm water.",
            "Nothing worth the airtime. Quiet, everywhere."],
        "news_again": [
            "We've told you all we know, friend."],
        "sos": [
            "Mayday, mayday. Vey ship in trouble. {problem} Is anyone out there?",
            "Any ship, any ship. {problem} {crew} of us aboard. Please."],
        "sos_answer": [
            "You heard us. Oh, thank you. Come alongside, we're not going anywhere.",
            "We see you, friend. We're so glad we see you."],
        "sos_fuel": [
            ["Fuel. Thank you. {t} tonnes at {price}, and you'll eat with us one day.", "Fuel. Thank you. {t} tonnes, and you'll eat with us one day."],
            ["{t} tonnes. {price} a tonne. We'll remember this.", "{t} tonnes. We'll remember this."]],
        "sos_crew": [
            "You'll take us? We're coming. Someone bring the plants.",
            "We're crossing over. The ship can wait. We can't."],
        "sos_room": [
            "No room? Then tell the port about us. We'll keep the lights on."],
        "sos_bye": [
            "We'll make it from here. Thank you. Really.",
            "Fuelled and flowing home. We owe you."],
        "rival_there": [
            "That wreck's ours, friend. Our beacon's on it.",
            "Salvage tug here. That's our beacon. Move along, or ask nicely."],
        "rival_claim": [
            "Salvage tug, coming in on the wreck. Our beacon's going on it.",
            "That wreck's ours now. Beacon's away. Nothing personal."],
        "rival_yours": [
            "Didn't see your beacon, friend. Half each, and nobody gets hurt?",
            "Your beacon, is it? Plenty here for everyone. We'll take what you leave."],
        "rival_split": [
            "Half each. We'll take every other piece. Leave ours be.",
            "Deal. Your half, our half. Share and share alike."],
        "rival_warned_ok": [
            "Your beacon was first. It's yours. We'll go.",
            "Fair enough. We're going. Look after it."],
        "rival_warned_no": [
            "Our beacon was first, friend. We're staying.",
            "We were here first. We'd rather you went."],
        "rival_warned_no_yours": [
            "Beacon or not, we're cutting. Call the port if you have to.",
            "We hear you. We're still cutting."],
        "rival_done": [
            "We're done. The rest is yours.",
            "Our hold's full. Everything left is yours."],
    },
    "orun": {
        "downport_cleared": [["Freighter, this is all of us at downport control. Pad {berth}. Wind {wind} from the {from}. Keep your burn off the terminal. We are all at the window.", "Freighter, this is all of us at downport control. Pad {berth}. Keep your burn off the terminal. We are all at the window."], "Pad {berth}, freighter. Belly first. Not the city. Everyone in the city is watching."],
        "downport_gale": [["Freighter, pad {berth}. We are all having a gale, {wind} from the {from}. Hold into it. We will all hold our breath.", "Freighter, pad {berth}. We are all having a gale. Hold into it. We will all hold our breath."], ["Pad {berth}. Gusting {wind}. Three ships bounced today. We went and looked at all of them.", "Pad {berth}. Hard gusts. Three ships bounced today. We went and looked at all of them."]],
        "field_cleared": ["Freighter? Yes. Land by the flares. We are all in the shed. Not on the shed.", ["Come down. The sock says {wind} from the {from}. We all trust the sock.", "Come down. Watch the sock. We all trust the sock."]],
        "cleared": [
            "Freighter, we see you. We are giving you berth {berth}. The collar is lit. We are all watching.",
            "Copy, freighter. Berth {berth} is ours and now yours. Come in slow. We just polished it together.",
            "Cleared for berth {berth}, freighter. We painted that collar. All of us."],
        "hold": [
            "Freighter, hold at two kilometres. One of us is coming out of the collar. You will see them.",
            "Not yet, freighter. We are moving a ship out. Hold, and we will call you."],
        "after_hold": [
            "Freighter, they are out. We are giving you berth {berth}.",
            "The collar is yours, freighter. Berth {berth}. We will all mind their wake."],
        "already": [
            "We already cleared you, freighter. Berth {berth}. We all heard us say it."],
        "fined": [
            "Freighter, you docked without calling. {fine}. We all saw.",
            "Nobody cleared you. {fine}. And we will talk about it at supper."],
        "pad_cleared": [
            "Freighter, this is us at pad control. Pad {berth} is yours. Beacon on. We are watching the dust.",
            "Pad {berth} for you, freighter. Gear down. We will come and look at your legs after."],
        "camp_cleared": [
            "Freighter? Yes. We are all at the hut. Land on the flat bit. We will wave.",
            "The pad is clear. Come down slow. Everyone is watching. Everyone always is."],
        "camp_fined": [
            "You landed on us without calling. {fine}. We were having lunch.",
            "No word? {fine}. We will all remember."],
        "speed": [
            "Freighter, we see you fast inside two kilometres. Slow down. We are all inside this station.",
            "Freighter on approach, you are hot. Slow down. We live here."],
        "greet": [
            "We hear you. Go ahead.",
            "This is us. All of us. What do you need?",
            "Go ahead, freighter. We are all listening."],
        "patrol": [
            "System patrol. We keep it slow near the station. You will too.",
            "System patrol. Nothing to report. We like it that way."],
        "fuel_offer": [
            ["We can spare {t} tonnes at {price} a tonne. The port is cheaper, but we are closer.", "We can spare {t} tonnes. The price is on your screen. The port is cheaper, but we are closer."],
            ["{t} tonnes, {price}. We will come alongside. Hold still. We are good at close.", "{t} tonnes, price on your screen. We will come alongside. Hold still. We are good at close."]],
        "fuel_coming": [
            "We are coming alongside. Close. Hold still.",
            "On our way. All of us. Do not do anything clever."],
        "fuel_wait": [
            "We cannot line up the hose with you moving. Hold still.",
            "Stop wriggling, freighter. We are trying to help, together."],
        "fuel_done": [
            "That is your fuel. Our tanks thank your account.",
            "Fuel in. Bill sent. We will think of you warmly."],
        "fuel_no": [
            "We are all going the other way. Ask a ship that has stopped.",
            "We have just enough for us. And there are many of us."],
        "tow_offer": [
            ["We will take your line. {fee}. We do not discuss the parking.", "We will take your line. The fee is on your screen. We do not discuss the parking."],
            ["We can tow you in for {fee}. Or wait for the tug. We would wait with you.", "We can tow you in. The fee is on your screen. Or wait for the tug. We would wait with you."]],
        "tug_offer": [
            ["Port tug. {fee}, same as always. Sit tight. We have you.", "Port tug. The usual fee. Sit tight. We have you."],
            ["Tug here. {fee}. Hands off the throttle. We are holding it.", "Tug here. The usual fee. Hands off the throttle. We are holding it."]],
        "news_tight": [
            ["{place} is short of {goods}. We heard it from everyone.", "Somebody near here is short of something. We heard it from everyone."],
            ["If you carry {goods}, take it to {place}. They need it. We would.", "If you carry the right cargo, somebody near here needs it. We would take it."]],
        "news_price": [
            ["Prices at {place} are {dir} {pct}. Everyone is talking about it.", "Prices went {dir} this week. Everyone is talking about it."],
            ["We heard {place} is {dir} {pct}. We hear everything.", "We heard prices went {dir}. We hear everything."]],
        "news_wreck": [
            ["There is a dead ship {km} kilometres out: {wreck}. Nobody has gone in. We would.", "There is a dead ship out by the station. Nobody has gone in. We would."],
            ["We passed a wreck, {km} kilometres out. {wreck}. Somebody should fix it, or take it.", "We passed a wreck on the way in. Somebody should fix it, or take it."]],
        "news_grew": [
            ["We are all hearing that {place} is growing. We are pleased. We helped, probably.", "We are all hearing that a site nearby is growing. We are pleased. We helped, probably."],
            ["{place} is bigger now. We counted the ships. All of us.", "A site nearby is bigger now. We counted the ships. All of us."]],
        "news_shrank": [
            ["We hear {place} is shrinking. We are worried together.", "We hear a site nearby is shrinking. We are worried together."],
            ["{place} has fewer of us every week. We do not like it.", "A site nearby has fewer of us every week. We do not like it."]],
        "news_empty": [
            ["{place} is empty. All of them left at once, the way we would.", "A site nearby is empty. All of them left at once, the way we would."],
            ["Nobody is at {place}. We checked. Twice. Together.", "Nobody is at one of the sites. We checked. Twice. Together."]],
        "storm_advice": [
            "Advisory: we are all having a solar storm. Everyone is in port. Come in and be in port with us.",
            "The storm is up. We are keeping all of us in. Come in and wait. Together."],
        "news_storm": [
            ["We are all hearing a storm is coming here, {when}. We will be in port. All of us.", "We are all hearing a storm is coming here soon. We will be in port. All of us."],
            ["Storm, {when}. Our radiators hate it. So do we.", "Storm coming soon. Our radiators hate it. So do we."]],
        "rival_jump": [
            ["We see your beacon on the {wreck}. We see no patrol. We will all be quick.", "We see your beacon. We see no patrol. We will all be quick."],
            ["We have discussed your beacon. We decided to ignore it. All of us.", "We have discussed your beacon. We decided to ignore it. All of us."]],
        "rival_jump_no": [
            "No. We voted.",
            "We heard you. We voted again. Still no."],
        "rival_report_stay": [
            "Report us. We will all be gone before they arrive.",
            "Call it in. We are already packing. Slowly."],
        "rival_report_go": [
            "A patrol? We are all leaving now. Together.",
            "Paperwork. We do not like paperwork. Goodbye."],
        "news_none": [
            "No news. We are as surprised as you.",
            "Nothing. Quiet out here. Too quiet for us."],
        "news_again": [
            "We told you everything we know. Twice would be gossip."],
        "sos": [
            "Mayday, mayday. Orun ship, all of us aboard. {problem} Anyone?",
            "Any ship, any ship. {problem} {crew} of us here. Together, but stuck."],
        "sos_answer": [
            "You heard us! We all heard you hear us. Come alongside.",
            "We see you. All of us see you. Please do not be a salvage crew."],
        "sos_fuel": [
            ["Fuel! {t} tonnes at {price}. We will all owe you supper.", "Fuel! {t} tonnes. We will all owe you supper."],
            ["{t} tonnes, {price} a tonne. We will name a tunnel after you.", "{t} tonnes. We will name a tunnel after you."]],
        "sos_crew": [
            "You will take us? We are packing. Together. This could take a while.",
            "We are coming across. All of us. The ship can wait."],
        "sos_room": [
            "No room? Then tell the port. We will keep the lights on and each other company."],
        "sos_bye": [
            "We will make it from here. Thank you, from all of us.",
            "Fuelled and limping home together. We owe you."],
        "rival_there": [
            "That is our wreck, freighter. Our beacon. We all agreed.",
            "Salvage tug. That beacon is ours. Move along, or come and ask us nicely."],
        "rival_claim": [
            "Salvage tug, coming in on the wreck. We are putting our beacon on it.",
            "That wreck is ours now. Beacon away. Nothing personal. We like you."],
        "rival_yours": [
            "We did not see your beacon. We did not look. Half each, and we all go home?",
            "Your beacon? The wreck is big. We will take the bits you do not want. We share."],
        "rival_split": [
            "Half each. We take every other piece. Stay off our half.",
            "Deal. Your half, our half. We will all remember which is which."],
        "rival_warned_ok": [
            "Fine. Fine! It is yours. We will find another. Together.",
            "Your beacon, your wreck. We are going. Enjoy it."],
        "rival_warned_no": [
            "Our beacon was first. We all saw it. We are staying.",
            "Clear off? We were here first. All of us."],
        "rival_warned_no_yours": [
            "Beacon or not, we are cutting. Call the port. We will wait.",
            "We heard you. All of us. We are still cutting."],
        "rival_done": [
            "We are done. Pleasure, mostly. Mostly for us.",
            "We are full. What is left is yours. We left you good bits."],
    },
}

ABOARD = {
    "kesh": {
        "bunk": ["This bunk was built for a lighter people. I will manage.", "A crew bunk. It is clean. That is what matters.", "Someone keeps this bunk well. I can tell."],
        "cabin": ["The cabin is small, but the door is solid. I approve of the door.", "The viewport is small. The frame around it is good.", "We are on schedule? Good. I do not need to be told twice."],
        "quarters": ["The lounge furniture would not survive my homeworld.", "Someone in pod two is snoring. It is not me. We do not snore.", "Adequate. The fittings are light, but adequate."],
        "stateroom": ["I asked for a window. There is a window. This ship keeps its word.", "The plant is real. Someone waters it. That is care.", "Tell the captain the stateroom is well kept. That is high praise."],
        "late": ["We were promised arrival by now. A promise is a load.", "I have counted the rivets. They are sound. We are still late."],
    },
    "ilyan": {
        "bunk": ["Crew bunk. Efficient. Smells of someone.", "Short bunk. I fold.", "Personal items: not mine. Mass: unnecessary."],
        "cabin": ["Small cabin. Correct size, actually.", "Viewport: twenty centimetres. Sufficient.", "Are we on schedule? Checking. Yes. Good."],
        "quarters": ["Three films in the lounge. Ninety megabytes of redundancy.", "Snoring, pod two. Not me.", "Curtains overlap by minus two centimetres. Noted."],
        "stateroom": ["A window. Exact specification. Remarkable.", "The plant is real. Seventeen grams of soil. Unnecessary. Pleasant.", "Tell the captain: the sheets are within tolerance."],
        "late": ["We are late. By my count, eleven hours.", "Rivets counted. Four hundred and twelve. Still late."],
    },
    "vey": {
        "bunk": ["Someone sleeps here usually. I can feel them.", "It's dry in here. So dry. I'll manage.", "Somebody's name is on the pillow. I'll keep it warm for them."],
        "cabin": ["It's small, but it's ours. Mine. For now.", "The air's a little dry. Could someone mist it?", "We're fine. Are we nearly there? We're fine."],
        "quarters": ["The lounge has a screen and three films. We've all watched them together.", "Someone in pod two is snoring. It's soothing, honestly.", "The curtains don't quite meet. Nothing ever quite does."],
        "stateroom": ["A window. I can watch the stars drift by. Like water.", "The plant's real. I checked. It's thirsty.", "Tell the captain the room is lovely. And a little dry."],
        "late": ["We were meant to be there by now. The tide waits for no one.", "We're late. Everyone at home is waiting. They'll understand."],
    },
    "orun": {
        "bunk": ["This is someone's bunk. We like it. It smells like a home.", "We have slept in worse. With more of us.", "The pillow has a name on it. We will share."],
        "cabin": ["The door locks. We do not know why you would want that.", "A small cabin. Cosy. Could fit four of us.", "We are fine. Are we nearly there? We are fine."],
        "quarters": ["The lounge is the best room. Everyone is in it.", "Someone in pod two is snoring. We find it comforting.", "The curtains do not meet. Good. We like to see who is there."],
        "stateroom": ["A room for one. We feel lonely. It is very nice.", "The plant is real. We have named it.", "Tell the captain the stateroom is big enough for a family. Ours."],
        "late": ["We were promised arrival by now. We are all disappointed together.", "We have counted the rivets. All of us. We disagree on the number."],
    },
}


def main():
    cp = os.path.join(ROOT, "data", "runtime", "comms.json")
    pp = os.path.join(ROOT, "data", "runtime", "passengers.json")
    comms = json.load(open(cp, encoding="utf-8"))
    comms["species_lines"] = LINES
    json.dump(comms, open(cp, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    open(cp, "a", encoding="utf-8").write("\n")
    # passengers.json is hand-formatted: replace only its aboard_by_species block, at the end
    src = open(pp, encoding="utf-8").read()
    cut = src.find(',\n  "aboard_by_species"')
    src = (src[:cut] if cut >= 0 else src.rstrip()[:-1].rstrip()) + ',\n  "aboard_by_species": ' + \
        json.dumps(ABOARD, indent=2, ensure_ascii=False).replace("\n", "\n  ") + "\n}\n"
    json.loads(src)
    open(pp, "w", encoding="utf-8").write(src)
    n = sum(len(v) for sp in LINES.values() for v in sp.values()) + sum(len(v) for sp in ABOARD.values() for v in sp.values())
    print("%d species lines written into comms.json and passengers.json" % n)


if __name__ == "__main__":
    main()
