#!/usr/bin/env python3
"""Expand tools/voice/voiced.json into tools/voice/lines.json: every spoken line, in every variation,
with who says it. The generator (generate.py) reads lines.json; the game finds a clip by the same id
(scripts/comms/voice_bank.gd).

An id is "<source>:<key>|<index>" plus "|<name>=<value>" for each value filled in from a set, sorted by
name, e.g. "comms:cleared|0|berth=6". The value is the set's first column, as the game knows it.

Also checks that every voiced key still lines up with the game's own lines (comms.json, passengers.json),
so a line added to the game without a spoken version is caught here.

Run from the repo root:  python tools/voice/build_lines.py
"""
import itertools
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "tools", "voice")


def game_lines():
    """The game's lines by '<source>:<key>': comms.json lines and passengers.json aboard."""
    out = {}
    comms = json.load(open(os.path.join(ROOT, "data", "runtime", "comms.json"), encoding="utf-8"))
    for k, v in comms["lines"].items():
        out["comms:" + k] = v
    pax = json.load(open(os.path.join(ROOT, "data", "runtime", "passengers.json"), encoding="utf-8"))
    for k, v in pax["aboard"].items():
        out["aboard:" + k] = v
    return out


def species_game():
    """The species' own lines by '<source>:<key>@<species>'."""
    out = {}
    comms = json.load(open(os.path.join(ROOT, "data", "runtime", "comms.json"), encoding="utf-8"))
    for sp, keys in comms.get("species_lines", {}).items():
        for k, v in keys.items():
            out["comms:%s@%s" % (k, sp)] = v
    pax = json.load(open(os.path.join(ROOT, "data", "runtime", "passengers.json"), encoding="utf-8"))
    for sp, keys in pax.get("aboard_by_species", {}).items():
        for k, v in keys.items():
            out["aboard:%s@%s" % (k, sp)] = v
    return out


def clip_id(key, index, values):
    tail = "".join("|%s=%s" % (n, values[n]) for n in sorted(values))
    return "%s|%d%s" % (key, index, tail)


def file_stem(cid):
    """A filename-safe version of an id: comms_cleared_0_berth-6."""
    s = cid.replace(":", "_").replace("|", "_").replace("=", "-").replace("@", "-")
    return re.sub(r"[^A-Za-z0-9_\-]", "", s)


def main():
    voiced = json.load(open(os.path.join(HERE, "voiced.json"), encoding="utf-8"))
    sets = voiced["sets"]
    game = game_lines()
    problems = []
    lines = []
    for key, spec in voiced["lines"].items():
        if key not in game:
            problems.append("%s: voiced but not in the game's data" % key)
            continue
        if len(spec["say"]) != len(game[key]):
            problems.append("%s: %d voiced, %d in the game" % (key, len(spec["say"]), len(game[key])))
        for i, text in enumerate(spec["say"]):
            if text is None:
                continue
            names = sorted(set(re.findall(r"\{(\w+)\}", text)))
            for n in names:
                if n not in sets:
                    problems.append("%s[%d]: {%s} has no set" % (key, i, n))
            if any(n not in sets for n in names):
                continue
            for combo in itertools.product(*[sets[n] for n in names]):
                values = {n: str(c[0]) for n, c in zip(names, combo)}
                said = text
                for n, c in zip(names, combo):
                    said = said.replace("{%s}" % n, str(c[1]))
                cid = clip_id(key, i, values)
                lines.append({"id": cid, "file": file_stem(cid), "key": key, "index": i, "values": values,
                              "text": said, "role": spec["role"], "radio": bool(spec.get("radio", True))})
    # The aliens' own lines (comms.json species_lines, passengers.json aboard_by_species: written by
    # species_lines.py): "<source>:<key>@<species>", said only by that species, spoken as written ([shown,
    # spoken] when the shown one carries a name).
    for skey, pools in species_game().items():
        key, sp = skey.split("@")
        spec = voiced["lines"].get(key)
        if spec is None:
            problems.append("%s: no base line %s" % (skey, key))
            continue
        for i, entry in enumerate(pools):
            text = entry[1] if isinstance(entry, list) else entry
            names = sorted(set(re.findall(r"\{(\w+)\}", text)))
            bad = [n for n in names if n not in sets or n == "species"]
            if bad:
                problems.append("%s[%d]: {%s} can't be spoken (use [shown, spoken])" % (skey, i, ", ".join(bad)))
                continue
            for combo in itertools.product(*[sets[n] for n in names]):
                values = {n: str(c[0]) for n, c in zip(names, combo)}
                said = text
                for n, c in zip(names, combo):
                    said = said.replace("{%s}" % n, str(c[1]))
                cid = clip_id(skey, i, values)
                lines.append({"id": cid, "file": file_stem(cid), "key": skey, "index": i, "values": values, "text": said,
                              "role": spec["role"], "radio": bool(spec.get("radio", True)), "species": sp})
    # A base line naming a species that has its own wording of it ("Mayday. Kesh registry...") is never
    # played: that caller says its own line. Leave it out.
    own = {(l["key"].split("@")[0], l["species"]) for l in lines if "species" in l}
    lines = [l for l in lines if "species" in l or (l["key"], l["values"].get("species")) not in own]
    for key in game:
        if key not in voiced["lines"] and not key.startswith("comms:you_"):
            problems.append("%s: in the game but has no voiced entry (null it out to leave it as babble)" % key)
    by_role = {}
    for l in lines:
        by_role[l["role"]] = by_role.get(l["role"], 0) + 1
    out = os.path.join(HERE, "lines.json")
    json.dump({"description": "Generated by tools/voice/build_lines.py from voiced.json. Don't edit; edit voiced.json and rerun.",
               "lines": lines}, open(out, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("%d spoken lines -> %s" % (len(lines), os.path.relpath(out, ROOT)))
    for r in sorted(by_role):
        print("  %-10s %4d" % (r, by_role[r]))
    if problems:
        print("\nProblems:")
        for p in problems:
            print("  " + p)
        sys.exit(1)


if __name__ == "__main__":
    main()
