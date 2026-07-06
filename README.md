# Screw Puzzle

A take-apart screw puzzle for **Godot 4.7** (desktop + mobile): tap screws to
unscrew them, but a screw is stuck while a plate on a higher layer covers it.
When a plate loses its last screw it drops off the board with physics. Clear
all plates to win. **50 levels**, no timers, no fail states — the game the
ads promised.

## Run

Open this folder (the one containing `project.godot`) in Godot 4.7, or:

```sh
godot --path . # from this folder
```

Desktop uses the mouse; touch input works natively on mobile
(`emulate_touch_from_mouse` gives both a single input path).

## Project layout

- `scenes/` — title, level select, gameplay scenes (UI is built in code).
- `src/core/` — `game_state.gd` (autoload: progress + scene flow),
  `level_loader.gd` (JSON loading + validation), `solver.gd` (blocking rule +
  solvability simulation; the single source of truth for game rules).
- `src/entities/` — `plate.gd`, `screw.gd`, `falling_plate.gd`.
- `src/ui/` — HUD, overlays, procedural widget styling (`ui_kit.gd`).
- `levels/` — 50 committed JSON levels + `index.json` (ordered list).
- `tools/generate_levels.py` — deterministic offline generator/validator.
- `tests/` — headless test scripts.

## Levels

Levels are plain JSON: plates (polygon `points`, `layer`, `color`) with screw
positions. Rules enforced by `LevelLoader.validate` and the test suite:
every screw is well inside its plate, overlapping plates sit on distinct
layers, every level is solvable.

Most levels are produced by the seeded generator (level N always regenerates
identically); levels 1 (tutorial), 10 (shirt), 30 (star) and 50 (vault) are
designed showcase boards. Regenerate or re-check with:

```sh
python3 tools/generate_levels.py            # regenerate + validate + write
python3 tools/generate_levels.py --validate # validate committed files only
```

The Python geometry/solver code mirrors `solver.gd`/`level_loader.gd`; the
GDScript test suite re-validates every committed level inside the engine.

## Tests (headless)

```sh
./tests/run_all.sh                 # runs all three suites
GODOT=/path/to/godot ./tests/run_all.sh
```

- `test_blocking.gd` — unit tests for the blocking rule and solver.
- `test_level_data.gd` — validates all 50 committed levels, asserts ≥ 48.
- `test_detach.gd` — scene test: tap → unscrew → plate falls → win signal.

## Extracting into its own repository

This folder is fully self-contained (its own `project.godot`; no `res://`
path leaves this directory). Two options:

```sh
# history-preserving (needs git-filter-repo):
git clone <wwjmd-repo> screw-puzzle && cd screw-puzzle
git filter-repo --subdirectory-filter screw_puzzle

# quick copy:
cp -r screw_puzzle/ ../screw-puzzle/ && cd ../screw-puzzle
rm -rf .godot && git init && git add . && git commit -m "Initial import"
```
