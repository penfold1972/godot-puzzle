# Screw Puzzle

A pin-board screw puzzle for **Godot 4.7** (desktop + mobile), played like
peg solitaire with physics. Every level is the silhouette of a real object —
t-shirts, cars, flamingos, robots, skyscrapers — built from overlapping
metal plates screwed to a backboard.

## How it plays

- Tap a screw to unscrew it (blocked screws shake: a plate above is
  covering them). While the screw is in your hand, **physics pause**.
- Tap a highlighted hole to drive the screw back in. It pins **every plate
  whose hole lines up** with that board hole — or just parks in an empty
  spot (the rail at the top always works). Tap the lifted screw again to
  cancel and put it back.
- When physics resume: plates with two or more screws hold still, a plate
  on its **last screw swings** under gravity — it can cover the hole you
  just emptied, or rotate one of its holes over a new spot — and a plate
  with **no screws falls**. Falling plates collide with same-depth
  neighbours and can jam.
- Clear every plate off the board to win. No timers; if the board wedges
  itself into a dead end, restart is always one tap away.

50 levels: 17 object silhouettes, each returning at higher difficulty
(more, smaller plates; brace straps across seams; fewer parking holes).

## Run

Open this folder in Godot 4.7, or `godot --path .` from here. Mouse works
like touch (`emulate_touch_from_mouse`); on mobile it's native touch.

## Project layout

- `src/core/` — `rules.gd` (covering/removal/placement — the game rules),
  `quasi_solver.gd` (solvability), `level_loader.gd` (schema v2 +
  validation), `game_state.gd` (progress + scene flow).
- `src/game.gd` — two-tap state machine, world freeze, joint lifecycle.
- `src/entities/` — `plate_body.gd` (RigidBody2D plates: static / swinging
  on a PinJoint2D / falling), `screw.gd`, `board_hole.gd`.
- `src/ui/` — procedural title, level select, HUD, win overlay.
- `levels/` — 50 committed JSON levels + `index.json` (+ `dev_*.json`
  test fixtures, not in the index).
- `tools/` — Python twins of the rules/validator/solver plus the
  deterministic level generator and the 17 silhouette outlines.
- `tests/` — headless GDScript suites.

## Level format (v2)

```json
{"version": 2, "id": 7, "name": "T-Shirt I", "silhouette": "tshirt",
 "bounds": [720, 1000],
 "board_holes": [[x,y], ...],
 "plates": [{"id":0, "layer":0, "color":"#c25b4e",
             "points":[[x,y],...], "holes":[[x,y],...]}],
 "screws": [{"hole": 3, "plates": [0, 2]}]}
```

Holes no screw references start empty. The validator enforces hole
spacing, screws-through-aligned-holes consistency, same-layer plates
never overlapping (they share a collision layer), and ≥1 empty hole.

## Levels & generator

```sh
python3 tools/generate_levels.py            # regenerate all 50 (deterministic)
python3 tools/generate_levels.py --svg out  # + per-level SVG previews
python3 tools/validate_v2.py                # validate committed levels
python3 tools/quasi_solver.py               # solvability report
python3 tools/test_rules.py                 # rules parity suite (Python side)
```

Every shipped level passes a **quasi-static** solvability check (plates
treated as motionless). Real physics can still wedge a level — that's part
of the game, and the top parking rail plus restart keep it fair.

## Tests (headless, on a machine with Godot)

```sh
./tests/run_all.sh                # test_rules, test_level_data,
                                  # test_quasi_solver, test_scene_v2
GODOT=/path/to/godot ./tests/run_all.sh
```

`test_rules.gd` runs the same fixture file as the Python twin
(`tests/fixtures/rules_cases.json`), so the game and the generator can
never disagree about the rules. `test_scene_v2.gd` drives real touch
events through the viewport: freeze, cancel, swing, fall, win.
