#!/usr/bin/env python3
"""Build data/runtime/sim_scenario_known_space.json: the Hopewell scenario plus a maker and a user for every
freight good, and the carriers to move them. Reads data/world (markets, commodities, routes, systems) and
data/runtime/goods_roles.json. Everything it adds is an ASSUMPTION; rerun after changing roles or fleet.

    python3 tools/gen_known_space.py            # writes the scenario
    python3 tools/gen_known_space.py --report   # prints flows and fleet sizing only
"""
import json, math, heapq, sys, collections, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
J = lambda p: json.load(open(os.path.join(ROOT, p)))
base = J("data/runtime/sim_scenario_hopewell.json")
roles = J("data/runtime/goods_roles.json")
coms = {c["id"]: c for c in J("data/world/commodities.json")["commodities"]}
markets = J("data/world/markets.json")["markets"]
pop = {s["id"]: float(s.get("population", 1)) for s in J("data/world/systems.json")["systems"]}
ports = {}
for p in J("data/world/ports.json")["ports"]:
    ports.setdefault(p["system_id"], p["id"])
adj = collections.defaultdict(dict)
for r in J("data/world/routes.json")["routes"]:
    adj[r["a"]][r["b"]] = adj[r["b"]][r["a"]] = float(r["distance_ly"])
P = base["params"]
HUBS = set(P["hub_systems"])
FRONTIER = set(P["frontier_systems"])
CFG = J("data/runtime/known_space_fleet.json")


def path(a, b):
    dist, prev, pq = {a: 0.0}, {}, [(0.0, a)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == b:
            break
        if d > dist[u]:
            continue
        for v, w in adj[u].items():
            if d + w < dist.get(v, 1e18):
                dist[v], prev[v] = d + w, u
                heapq.heappush(pq, (d + w, v))
    out = [b]
    while out[-1] != a:
        out.append(prev[out[-1]])
    return out[::-1]


def ly(p): return sum(adj[p[i]][p[i + 1]] for i in range(len(p) - 1))


def segments(p):
    cuts = [0] + [i for i in range(1, len(p) - 1) if p[i] in HUBS] + [len(p) - 1]
    return [p[cuts[k]:cuts[k + 1] + 1] for k in range(len(cuts) - 1)]


def popf(s): return min(1.6, max(0.4, (pop[s] / 640e6) ** 0.2))


mk = {}
for m in markets:
    for e in m["commodities"]:
        mk[(m["system_id"], e["commodity_id"])] = e

hand_goods = set(roles["hand_built"]) | set(roles["skip"])
facs = {}      # (system, kind) -> facility
flows = []     # (good, maker, user, scu_per_day)
makers_listing = {}


def fac(system, kind):
    k = (system, kind)
    if k not in facs:
        nm = system.replace("_", " ").title()
        facs[k] = {"id": f"{system}_{'works' if kind == 'supplier' else 'exchange'}",
                   "name": f"{nm} {'Industrial Works' if kind == 'supplier' else 'Commercial Exchange'} (assumed)",
                   "kind": kind, "system_id": system, "port_id": ports[system], "cash": 0.0, "income_cr_per_day": 0.0,
                   "reliability": 0.96 if kind == "supplier" else 1.0, "items": {}}
    return facs[k]


for g, c in sorted(coms.items()):
    if g in hand_goods:
        continue
    cat = roles["category_defaults"][c["category"]]
    ov = roles["goods"].get(g, {})
    makers = list(ov.get("makers", cat["makers"]))
    for (s, gg), e in mk.items():
        if gg == g and e["stock"] >= 4 and s not in makers and s in adj:
            makers.append(s)
    makers = makers[:3]
    cand = []
    for (s, gg), e in mk.items():
        if gg == g and s not in makers and s in adj and (e["demand"] >= 4 or e["demand"] >= e["stock"] + 2):
            cand.append((-(e["demand"] * popf(s)), s))
    users = [s for _, s in sorted(cand)]
    for s in ov.get("users", cat["users"]):
        if s not in users and s not in makers:
            users.append(s)
    users = users[:CFG["max_users_per_good"]]
    makers_listing[g] = makers
    vol = CFG["base_scu_per_day"] * cat.get("volume", 1.0) * ov.get("volume", 1.0)
    for u in users:
        d = mk.get((u, g), {"demand": 3})["demand"]
        scu = vol * popf(u) * (0.7 + 0.15 * d)
        near = min(makers, key=lambda m: ly(path(m, u)))
        flows.append((g, near, u, scu))

# ---- facilities
need = collections.defaultdict(float)     # (maker, good) -> units/day its own users take
total_need = collections.defaultdict(float)   # good -> units/day everyone takes
makers_of = collections.defaultdict(set)
for g, m, u, scu in flows:
    c = coms[g]
    units = max(0.15, scu / max(float(c["scu_per_unit"]), 1.0))
    mult_u = mk.get((u, g), {}).get("price_multiplier", 1.0)
    price = float(c["base_value"]) * mult_u
    fu = fac(u, "consumer")
    batch = CFG["min_batch_scu"] / max(float(c["scu_per_unit"]), 1.0)          # small buyers order by the container, not by the day
    segs = segments(path(m, u))
    lead = sum(1.5 + ly(sg) / P["ly_per_day"] for sg in segs) + 3.0      # dispatch, load, fly, unload, and a few days waiting for a ship
    reorder = units * (lead + 9)
    target = reorder + max(units * 14, batch)
    fu["items"][g] = {"on_hand": round(target * 0.9, 1), "reorder_point": round(reorder, 1), "target_stock": round(target, 1),
                      "safety_stock": round(units * 1.5, 1), "daily_demand": round(units, 2)}
    spend = units * price * 1.25
    fu["income_cr_per_day"] += spend * CFG["income_factor"]
    fu["cash"] += spend * 90
    need[(m, g)] += units
    total_need[g] += units
    makers_of[g].add(m)
for g, ms in makers_of.items():
    pass
# Buyers pick the cheapest landed supplier, so every maker must be able to cover most of the demand
# alone; stocks and prices then shift buyers between makers instead of starving anyone.
all_makers = collections.defaultdict(set)
for g, c in coms.items():
    pass
for (m, g), units in list(need.items()):
    for m2 in makers_listing.get(g, []):
        need.setdefault((m2, g), 0.0)
for (m, g), units in need.items():
    c = coms[g]
    fm = fac(m, "supplier")
    prod = total_need[g] * max(1.25 / max(1, len(makers_listing[g])), 0.7)
    mult_m = mk.get((m, g), {}).get("price_multiplier", 1.0)
    cost = float(c["base_value"]) * mult_m * CFG["unit_cost_fraction"]
    fm["items"][g] = {"on_hand": round(prod * 12, 1), "reorder_point": 0, "target_stock": 0, "safety_stock": 0, "daily_demand": 0,
                      "produce_per_day": round(prod, 2), "max_stock": round(prod * 40, 1), "unit_cost": round(cost, 1), "price_mult": 0.9}
    fm["cash"] += prod * cost * 30
for f in facs.values():
    f["cash"] = round(max(f["cash"], 300000.0))
    f["income_cr_per_day"] = round(f["income_cr_per_day"])

# ---- fleet sizing: scu-ly/day originating at each system, hauled by ships homed there
homes = CFG["homes"]
load = collections.defaultdict(float)
for g, m, u, scu in flows:
    for seg in segments(path(m, u)):
        o = seg[0]
        if o in homes and all(x in homes[o]["network"] for x in seg):
            load[o] += scu * ly(seg)
        else:
            print("NO HOME FLEET for", g, seg, file=sys.stderr)
carriers = []
existing = collections.Counter(c["home_system_id"] for c in base["carriers"])
for o, hm in homes.items():
    kind = "big" if load[o] >= CFG["big_ship_above_scu_ly_per_day"] else "small"
    sh = CFG["ships"][kind]
    per_ship = CFG["effective_utilisation"] * sh["capacity_scu"] * P["ly_per_day"]
    n_new = math.ceil(load[o] / per_ship) if load[o] > 0 else 0
    for i in range(n_new):
        carriers.append({"id": f"{o}_haulers_{chr(97 + i) if i < 26 else i}", "company": f"{o}_haulers", "home_system_id": o,
                         "capacity_scu": sh["capacity_scu"], "dry_mass_t": sh["dry_mass_t"], "crew": sh["crew"],
                         "wage_cr_per_day": sh["wage"], "fixed_cr_per_day": sh["fixed"], "cash": sh["cash"],
                         "min_margin": sh["min_margin"], "network": hm["network"]})
    print(f"home {o:14s} load {load[o]:6.0f} scu-ly/day -> +{n_new} {kind} ships", file=sys.stderr)

total = sum(f[3] for f in flows)
print(f"{len(flows)} flows, {total:.0f} scu/day, {len(facs)} facilities, {sum(len(f['items']) for f in facs.values())} items, {len(carriers)} new carriers", file=sys.stderr)
if "--report" in sys.argv:
    sys.exit(0)

out = dict(base)
out["id"] = "known_space"
out["note"] = base["note"] + " KNOWN SPACE: tools/gen_known_space.py adds a maker and users for every freight good (data/runtime/goods_roles.json) and the carriers to move them. Do not hand-edit the generated entries (ids ending _works, _exchange and the pool carriers); change the roles or the fleet file and regenerate."
out["facilities"] = base["facilities"] + sorted(facs.values(), key=lambda f: f["id"])
out["carriers"] = base["carriers"] + carriers
json.dump(out, open(os.path.join(ROOT, "data/runtime/sim_scenario_known_space.json"), "w"), indent=1)
print("wrote data/runtime/sim_scenario_known_space.json", file=sys.stderr)
