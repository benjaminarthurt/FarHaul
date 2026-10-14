# Part makers

Who makes the external parts and what that changes. scripts/part_makers.gd (PartMakers), tuning in
data/runtime/part_makers.json, makers' canon in data/world/manufacturers.json.

- The parts the yards always had (engine, radiator, tank, frame, lander legs, braking and manoeuvring
  thrusters, FTL drive) are Northstar Commercial's (`base_maker`): sold everywhere at list price.
- Each entry in `parts` adds a maker's version: module id "<part>__<maker>", a copy of the part
  (`ModuleDef.base` is the part, `maker` the maker, `pitch` their line) with multipliers on its
  numbers: mass, cost (rounded to 50 cr), thrust, heat (made), cooling (shed, for radiators), power,
  fuel, lift, retro, rcs, wear (`ModuleDef.wear_mult`); `drive` is added to the drive's speed
  fraction. Tinted toward the maker's colour (`colours`). Added in ModuleLibrary._init, each straight
  after its part in the palette order, so the number keys still pick the same hull parts.
- Prices (`PartMakers.price`): a maker's version is `home_discount` cheaper at a yard in the maker's
  home system and `import_duty` dearer anywhere else. The builder charges the local price and records
  it on the module as `paid` with `src` "yard"; the ship's value and the refund for removing it use
  what was paid. (Salvage fitted in the yard is `src` "salvage"; a 0.12 save's `paid` without `src` is
  salvage.)
- Wear: `Wear.add` and `Wear.knock` multiply by the part's `wear_mult`, so a Kesh Heavy engine wears at
  40% of the standard rate and a Vector Works engine at 140%.
- Wrecks: the parts in a derelict's hold are sometimes another maker's (`PartMakers.on_a_wreck`, 60% of
  the time when the part has versions).
- The palette lists each maker's version indented under its part, with the local price and a line of
  tags (`PartMakers.tags`): the headline number's change against the standard part (thrust, cooling,
  fuel, lift, braking, push, or jump speed in points), mass if it moves 5% or more, "hot" (heat over
  1.15× the part's), "wears fast" (wear ×1.25 or more) or "tough" (×0.6 or less), "cheap" (list price
  0.8× or less). The tooltip says who makes it and where, their line, list price against here, and how
  fast it wears.
- The comparison card (`PartCompare`, scripts/part_compare.gd; I hides it) sits under the top bar for
  the selected part or salvaged part. For a part with makers' versions (`PartMakers.family`) it is a
  table, one row per make: headline number (`PartMakers.headline`), mass, heat made (not for
  radiators), power (if any differ), wear multiplier, price at this yard and home system, the best in
  each column in green (`PartCompare.best`; ties all green, nothing when all equal). Every part gets a
  "Fit one" line (`PartCompare.effect`) projected from the ship's current ShipStats: T/W (wet), heat
  made against cooling, power used against made (red with "over!" if it tips over), fuel, lift and
  braking at the loaded mass, push, jump speed and hold size. Lines that don't change are left out.
  It assumes engines face aft and braking thrusters face forward.

| Maker | Home | Parts | Trade-off |
|---|---|---|---|
| Ilyan Vector Works | Ilos | engine, braking and manoeuvring thrusters, FTL drive | stronger and lighter, hotter, dear, wears faster |
| Kesh Heavy Systems | Keshar | engine, lander legs, FTL drive | heavy and dear, wears at well under half the rate |
| Gateworks Heavy Orbital | Iron Gate | engine | half again the thrust, twice the mass and heat |
| Deep Junction Machine | Foundry | engine, tank, manoeuvring thrusters | cheap, a bit weak or heavy |
| Orun Thermal Collective | Orun | radiator | sheds 40% more, lasts, a little heavy |
| Aerial Massworks | Ilos | radiator, tank | very light, dear, the radiator wears fast |
| Roosevelt Modular | New Houston | tank, frame | a bigger tank; a cheaper frame |
