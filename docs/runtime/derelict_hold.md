# Derelict holds

Every derelict (scripts/flight/traffic.gd) has a cargo hatch as well as its salvage panels. Torch it
open and what the wreck was carrying drifts out to be taken home. scripts/salvage.gd (Salvage) rolls
the contents, stows them and sells them; tuning is `hold` in data/runtime/traffic.json.

## On the wreck

- The hatch is a skin site after the panels' (`ShipDamage.skin_sites`), marked by a yellow frame
  with a bar across. Id "<wreck id>|h". Cutting it takes the torch and `hold.cut_s` seconds; then
  the frame gives way to a dark hole with a scorched rim, the id goes in `profile.salvage_taken`
  (saved at once), and the hold's items come into view and become targets.
- Items (`Salvage.roll(layout, rng, deep)`, seeded with the wreck so the same wreck holds the same):
  - **crate**: `hold.crates` of them (plus `deep_extra_crates` for a wreck out on a route), each
    `crate_t` tonnes of one of `hold.commodities`.
  - **supplies**: `patch_kits` and `spares_kits`, if either rolls above zero.
  - **part**: `hold.parts` of the wreck layout's external parts (not caps), at `part_condition`.
    A wreck out on a route that had a jump drive always gives up the drive, failed
    (`failed_drive_condition`): that's why it's there.
- Items float 2 to 3 m out of the hatch, tumbling slowly: a crate in its goods' colour, a green
  supplies case, a grey cylinder for a part, each with a glowing band. Ids "<wreck id>|h|<k>".

## Taking them

- An item is a space-walk target (`OnFoot.SALVAGE` range, kind "item"): hold E with any tool for
  `hold.grab_s` seconds. One thing in hand at a time (`SpaceWalk.carry`, `carrying` = 1).
- Crates and parts need room in the hold: `Salvage.room_for` checks the saved manifest's free space
  for that commodity (parts ride as `Salvage.HARDWARE`, "Salvaged ship parts", a runtime-only
  commodity that is not in `CommodityLibrary.order`, so it's never posted as freight).
- At the hatch (or reeled in) `Salvage.stow` puts it aboard and saves: crates and parts into the
  manifest and the ledger (`profile.salvage_cargo` commodity -> tonnes, `profile.salvage_parts`
  [{kind, module, tonnes, condition, failed}]), the flight model's `cargo_t` goes up; supplies into
  the patch and spares lockers up to their maximums (the rest is left behind). If it won't go in
  after all, it's let go and stays on the wreck.

## Selling

- `Salvage.cargo_aboard()` and `parts_aboard()` are the ledger, capped by what the hold really has,
  so contract freight of the same goods is never sold as salvage.
- Cargo: at the freight office desk (and the phone's Repairs tab, and the dock menu). The best
  `EconomySim.quote` among the facilities at this port that deal in it, times `buyer_rate`; the
  facility pays and the units go on its shelf (`ledger.receive`). Nobody here deals in it: the scrap
  dealer pays `scrap_rate` of its base value.
- Parts: at the shipyard desk. Module cost x condition x `part_rate`.
- `Salvage.sell("cargo" | "parts")` unloads it, clears the ledger, books the revenue and adds to
  `profile.salvage_sold_cr`.

## Fitting salvaged parts

- In the shipyard, salvaged parts in the hold are listed first in the palette, under FROM YOUR HOLD,
  with their condition and fitting fee (`hold.fit_rate` of the price new, at least `hold.fit_min_cr`;
  `Salvage.fit_fee`). Pick one and place it like any part.
- Fitting takes it out of the hold (the HARDWARE tonnes and the ledger entry), charges the fee and
  starts it at its wear (`Salvage.wear_of`: 1 - condition, or failed). The module records the fee as
  `paid` (saved in the ship's JSON): the ship's value (`ShipData.paid`, `Session.ship_cost`,
  `ShipStats.cost`) counts the fee, not the price, so removing it refunds only the fee.
- Removing a fitted salvaged part (Shift+click) puts it back in the hold at its current condition,
  if there's room for its mass; otherwise it stays on. Undo and redo cover the hold and the ledger.
- A failed part fits but doesn't work until it's fixed. A failed jump drive (common on wrecks
  stranded out on routes) means no jumping until a spares kit or an overhaul brings it back.
