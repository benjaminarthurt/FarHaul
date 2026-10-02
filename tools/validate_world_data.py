#!/usr/bin/env python3
"""Far Haul world-data structural validator. Standard-library only."""
from __future__ import annotations
import json, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
WORLD=ROOT/"data"/"world"
errors=[]; warnings=[]

def load(name):
    p=WORLD/name
    try: return json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:
        errors.append(f"{name}: invalid JSON: {e}"); return {}

def ids(name,key):
    return {str(x.get("id")) for x in load(name).get(key,[]) if x.get("id")}

commodities=ids("commodities.json","commodities")
ship_classes=ids("ship_classes.json","ship_classes")
manufacturers=ids("manufacturers.json","manufacturers")
organizations=ids("organizations.json","organizations")
companies=ids("commercial_companies.json","companies")
expanded={str(x.get("id")) for x in load("commercial_entities_expanded.json").get("entities",[]) if x.get("id")}
known_entities=manufacturers|organizations|companies|expanded

for row in load("baseline_freight_flows.json").get("baseline_flows",[]):
    if row.get("commodity_id") not in commodities:
        errors.append(f"baseline_freight_flows: unknown commodity {row.get('commodity_id')}")
for row in load("commodity_provenance.json").get("flows",[]):
    if row.get("commodity_id") not in commodities:
        errors.append(f"commodity_provenance: unknown commodity {row.get('commodity_id')}")
for row in load("sample_vessel_histories.json").get("vessels",[]):
    if row.get("class_id") not in ship_classes:
        errors.append(f"sample_vessel_histories: unknown class {row.get('class_id')}")
for row in load("ship_classes.json").get("ship_classes",[]):
    if row.get("manufacturer_id") not in manufacturers:
        errors.append(f"ship_classes: unknown manufacturer {row.get('manufacturer_id')}")
for row in load("commercial_relationships_expanded.json").get("relationships",[]):
    for field in ("from","to"):
        value=row.get(field)
        if value not in known_entities:
            warnings.append(f"commercial_relationships_expanded: {field} {value} is outside registered commercial entity sets")
for p in sorted(WORLD.glob("*.json")):
    try: json.loads(p.read_text(encoding="utf-8"))
    except Exception as e: errors.append(f"{p.name}: {e}")

print(f"Far Haul world validation: {len(errors)} errors, {len(warnings)} warnings")
for x in errors: print("ERROR:",x)
for x in warnings: print("WARN:",x)
sys.exit(1 if errors else 0)
