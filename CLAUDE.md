# Far Haul: notes for working on this repo

- **Player-facing text uses the game's voice**: the in-game hints, prompts, notices and messages, the
  info site (`site/`), the release notes (`docs/releases/`) and the player-facing README sections. See
  [docs/voice.md](docs/voice.md). Key-reference strips and install steps stay plain. Developer docs
  (`docs/runtime/`) stay plain and technical.
- Tests are headless Godot scripts in `tests/` (`test_*.gd`, `smoke_*.gd`); `capture_*.gd` render
  screenshots under xvfb.
