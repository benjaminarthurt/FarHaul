# Debug cheats

For testing ships and flight without earning the money first. Code: `scripts/cheats.gd` (`Cheats`),
`scripts/game_menu.gd` (the buttons), `Builder.cheat` and `FlightScene.cheat` (scene-specific parts).
Setting: `cheats` in `GameSettings` (Settings: **Debug cheats (pause menu)**), off by default.
Tests: `tests/test_cheats.gd`.

- With the setting on and a saved game loaded, the pause menu (Esc / F10) shows a CHEATS heading with:
  - **+1,000,000 CR**: paid into the player's carrier from the world (`sim._pay("world", player)`), so the
    economy's cash stays conserved and it isn't counted as freight revenue. In the shipyard it goes on
    the builder's own `earned` instead (the builder works out credits as start funds + earned - ship
    cost, and saves them with the ship).
  - **REPAIR AND RESUPPLY**: hull damage 0, welded patches cleared, all wear cleared, patch and spares
    kit lockers full. In flight (`FlightScene.cheat`) also the flight's own copies: hull, wear, full
    tanks, heat dumped, breach undone.
- Using either sets `profile.cheated`; the pause menu notes "Cheats have been used on this save."
- A scene with `_refill()` (the port) redraws after a cheat.
