# Door caps

Two cheap modules that close a doorway nobody uses, so the hull counts as sealed without joining a
room to it. Code: `scripts/module_library.gd` (`door_cap`, `porthole_cap`), `scripts/module_def.gd`
(`seal`, `_build_cap`, `PORTHOLE`), `scripts/ship_data.gd` (`open_doors`, `_faces`),
`scripts/ship_skin.gd` (`_holes`, `mount_offset`), `scripts/flight/space_walk.gd` (`ship_boxes`).
Tests: `tests/test_door_caps.gd`. Render: `tests/capture_caps.gd`.

- **Door cap** (250 cr, 0.1 t) and **Door cap, porthole** (600 cr, 0.15 t), in the builder's palette
  under DOOR CAPS. Not pressurised, `seal = true`.
- Each is a fitting placed from the cell outside the doorway, with a single door socket on its -Z face.
  Placement is the normal rule: a door socket has to mate with a door facing it, so a cap only fits
  facing a doorway (turn it with the usual rotate key). One cap to a doorway.
- **A cap fills no cell** (`ShipData.world_cells` is empty for `seal` modules), so an engine, tank or
  radiator can still go in that cell, and a MOUNT socket can bolt onto a capped door face
  (`ShipData._mate_of` treats a capped doorway as bare hull; `ShipData.capped` finds the cap).
  Shift-click (`remove_at`, `module_at`) takes whatever fills the cell first, then the cap.
- **Hatch caps** (`hatch_cap_top`, `hatch_cap_bottom`, 250 cr): the same for a ladder shaft's deck
  hatch, placed from the cell above or below, a square plate on that cell's floor or ceiling.
- ShipStats counts a cap's mass at its cell but leaves it out of the ship's size.
- `ShipData.open_doors()`: a doorway whose neighbour is a sealing module with a door socket facing back
  is closed. Contracts' "Hull sealed" row and the builder's warning follow.
- Looks: just a plate on the doorway's face of the cell (just outside the room's wall), bolted round
  its rim, a hazard strip along the top; the porthole cap has a 0.9 m square window at eye height in
  a heavy frame. The rest of the cell is empty.
- Under the outer hull in flight the cap stays on the pressure wall (`mount_offset` is zero for
  sealing modules). The hull plates over a plain cap as it does over any unused doorway; for a
  porthole cap `ShipSkin._holes` cuts the window's opening in the hull, lined out to the skin like the
  cockpit's windows.
- A space walker isn't walled out of a cap's cell (`ship_boxes` skips sealing modules).
