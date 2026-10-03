#!/usr/bin/env python3
"""Cross-checks the Far Haul world data (data/world/*.json).

Usage:  python tools/check_world_data.py [--strict]

Reports problems; exits 0 unless --strict is given and problems were found.
Checks: JSON validity, unresolved *_id / *_ids references, duplicate route pairs,
route corridors, route distances vs coordinates, the two route tables
(routes.json vs interstellar_routes.json), port shipyard flags vs yards.json,
and yard hull class vs the port at the same destination.
"""
import collections, glob, json, math, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "world")
problems = []

def warn(msg):
    problems.append(msg)
    print("  PROBLEM", msg)

def load():
    data = {}
    for f in sorted(glob.glob(os.path.join(ROOT, "*.json"))):
        name = os.path.basename(f)[:-5]
        try:
            with open(f, encoding="utf-8") as fh:
                data[name] = json.load(fh)
        except Exception as e:
            warn(f"{name}.json is not valid JSON: {e}")
    return data

def walk(o, fn):
    if isinstance(o, dict):
        fn(o)
        for v in o.values():
            walk(v, fn)
    elif isinstance(o, list):
        for v in o:
            walk(v, fn)

def check_refs(data):
    print("== unresolved id references")
    ids = set()
    walk(data, lambda d: ids.add(d["id"]) if isinstance(d.get("id"), str) else None)
    unresolved = collections.defaultdict(collections.Counter)
    for name, doc in data.items():
        def look(d, name=name):
            for k, v in d.items():
                if k.endswith("_id") and isinstance(v, str) and v not in ids:
                    unresolved[(name, k)][v] += 1
                elif k.endswith("_ids") and isinstance(v, list):
                    for x in v:
                        if isinstance(x, str) and x not in ids:
                            unresolved[(name, k)][x] += 1
        walk(doc, look)
    for (name, k), c in sorted(unresolved.items(), key=lambda kv: -sum(kv[1].values())):
        warn(f"{name}.json {k}: {sum(c.values())} refs to unknown ids, e.g. {list(c)[:4]}")
    if not unresolved:
        print("  ok")

def check_routes(data):
    print("== routes, corridors, coordinates")
    routes = data["routes"]["routes"]
    pairs = collections.Counter(frozenset((r["a"], r["b"])) for r in routes)
    for k, n in pairs.items():
        if n > 1:
            warn(f"routes.json lists {sorted(k)} {n} times")
    corridors = {c["id"] for c in data["corridors"]["corridors"]}
    for r in routes:
        for c in r.get("corridors", []):
            if c not in corridors:
                warn(f"route {r['id']} uses corridor '{c}' which corridors.json does not define")
    coords = {c["id"]: c for c in data["coordinates"]["systems"]}
    for r in routes:
        a, b = coords[r["a"]], coords[r["b"]]
        d = math.dist([a[t] for t in "xyz"], [b[t] for t in "xyz"])
        if abs(d - r["distance_ly"]) > 0.05:
            warn(f"route {r['id']} states {r['distance_ly']} ly but coordinates give {d:.2f}")
    if "interstellar_routes" in data:
        other = {frozenset((l["from"], l["to"])): l["distance_ly"] for l in data["interstellar_routes"]["legs"]}
        mine = {frozenset((r["a"], r["b"])): r["distance_ly"] for r in routes}
        for k in mine:
            if k not in other:
                warn(f"{sorted(k)} is in routes.json but not interstellar_routes.json")
        for k in other:
            if k not in mine:
                warn(f"{sorted(k)} is in interstellar_routes.json but not routes.json")
        diffs = [(sorted(k), mine[k], other[k]) for k in mine if k in other and abs(mine[k] - other[k]) > 0.01]
        if diffs:
            warn(f"{len(diffs)} routes have different distances in routes.json and interstellar_routes.json, e.g. {diffs[:3]}")

def check_ports_yards(data):
    print("== ports and yards")
    order = ["medium_freighter", "large_freighter", "heavy_freighter", "superheavy_freighter"]
    by_dest = collections.defaultdict(list)
    for p in data["ports"]["ports"]:
        by_dest[p["destination_id"]].append(p)
    yards = data["yards"]["yards"]
    yard_dests = {y["destination_id"] for y in yards}
    for dest, plist in by_dest.items():
        flagged = any("shipyard" in p["services"] for p in plist)
        if flagged and dest not in yard_dests:
            warn(f"ports at {dest} advertise a shipyard but yards.json has none there")
        if dest in yard_dests and not flagged:
            warn(f"yards.json has a yard at {dest} but no port there has the 'shipyard' service ({', '.join(p['id'] for p in plist)})")
    for y in yards:
        plist = by_dest.get(y["destination_id"], [])
        if plist:
            biggest = max(order.index(p["max_hull_class"]) for p in plist)
            if biggest < order.index(y["largest_hull_class"]):
                warn(f"yard {y['id']} builds {y['largest_hull_class']} but the largest port at {y['destination_id']} takes {order[biggest]}")

def main():
    data = load()
    check_refs(data)
    if all(k in data for k in ("routes", "corridors", "coordinates")):
        check_routes(data)
    if all(k in data for k in ("ports", "yards")):
        check_ports_yards(data)
    print(f"\n{len(problems)} problem(s) found in {len(data)} files")
    if problems and "--strict" in sys.argv:
        sys.exit(1)

if __name__ == "__main__":
    main()
