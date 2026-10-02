#!/usr/bin/env python3
"""Validate Far Haul world JSON, authority IDs, commodities and core foreign keys."""
from __future__ import annotations
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; W=ROOT/"data"/"world"
E=[]; WN=[]
def load(n):
 p=W/n
 try:return json.loads(p.read_text(encoding="utf-8"))
 except Exception as e:E.append(f"{n}: {e}");return {}
def collect(n,key):
 return {str(x["id"]) for x in load(n).get(key,[]) if isinstance(x,dict) and x.get("id")}
for p in sorted(W.glob("*.json")):
 try:json.loads(p.read_text(encoding="utf-8"))
 except Exception as e:E.append(f"{p.name}: invalid JSON {e}")
commodities=collect("commodities.json","commodities")
ships=collect("ship_classes.json","ship_classes")
manufacturers=collect("manufacturers.json","manufacturers")
settlements=collect("settlements_authority.json","settlements")
sites=collect("sites_authority.json","sites")
orgs=collect("organizations_authority.json","organizations")
for x in load("ship_classes.json").get("ship_classes",[]):
 if x.get("manufacturer_id") not in manufacturers:E.append(f"ship_classes unknown manufacturer {x.get('manufacturer_id')}")
for x in load("sample_vessel_histories.json").get("vessels",[]):
 if x.get("class_id") not in ships:E.append(f"vessel unknown class {x.get('class_id')}")
for fn,key in [("baseline_freight_flows.json","baseline_flows"),("commodity_provenance.json","flows")]:
 for x in load(fn).get(key,[]):
  if x.get("commodity_id") not in commodities:E.append(f"{fn} unknown commodity {x.get('commodity_id')}")
for x in load("sites_authority.json").get("sites",[]):
 if x.get("settlement_id") not in settlements:E.append(f"site {x.get('id')} unknown settlement {x.get('settlement_id')}")
for x in load("component_models.json").get("models",[]):
 if x.get("manufacturer_id") not in manufacturers and x.get("manufacturer_id") not in orgs:E.append(f"component {x.get('id')} unknown manufacturer {x.get('manufacturer_id')}")
for x in load("manufacturing_bom.json").get("recipes",[]):
 for inp in x.get("inputs",[]):
  item=inp[0]
  intermediates={r.get("output",{}).get("item") for r in load("manufacturing_bom.json").get("recipes",[])}
  if item not in commodities and item not in intermediates:WN.append(f"BOM {x.get('id')} unresolved conceptual input {item}")
seeds=[x.get("seed") for x in load("world_generation_seeds.json").get("world_seeds",[])]
if len(seeds)!=len(set(seeds)):E.append("duplicate world generation seed")
print(f"Far Haul validation: {len(E)} errors, {len(WN)} warnings")
for x in E:print("ERROR",x)
for x in WN:print("WARN",x)
sys.exit(1 if E else 0)
