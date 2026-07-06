#!/usr/bin/env python3
"""Quasi-static solvability check for v2 pin-board levels.

Mirrors src/core/quasi_solver.gd exactly (same deterministic greedy policy,
same results). Motion is ignored: plates stay at their rest transforms, and
a plate is optimistically deleted the moment it has zero screws ("falls
clear"). Physics can still deadlock a quasi-solvable level at runtime;
restart is the accepted recovery. The generator only ships levels this
solver can clear.

Greedy policy per move (fully deterministic):
  1. Among removable screws, prefer the one whose removal drops the most
     plates; tie-break on lower hole index.
  2. Destination: prefer holes that pin the fewest plates (parking first);
     tie-break on lower hole index. The origin hole is allowed only if the
     removal dropped at least one plate (otherwise it is a no-op).
  3. Repeated states or no legal move => unsolvable.

Usage: python3 tools/quasi_solver.py    # solve all levels in the index
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rules

MOVE_LIMIT = 400

LEVELS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "levels")


def _pins(plate_id, screws):
    return sum(1 for s in screws if plate_id in s["plates"])


def _state_key(plates, screws):
    return (tuple(sorted(p["id"] for p in plates)),
            tuple(sorted((s["hole"], tuple(sorted(s["plates"]))) for s in screws)))


def solve(level):
    """Returns {"solvable": bool, "moves": int}."""
    plates = [dict(p) for p in level["plates"]]
    screws = [{"hole": s["hole"], "plates": sorted(s["plates"])}
              for s in level["screws"]]
    board_holes = level["board_holes"]
    seen = set()
    moves = 0

    while plates and moves < MOVE_LIMIT:
        key = _state_key(plates, screws)
        if key in seen:
            return {"solvable": False, "moves": moves}
        seen.add(key)

        best = None  # (neg_drops, hole, screw_index, dropped_ids, dest, dest_pinned)
        for si in sorted(range(len(screws)), key=lambda i: screws[i]["hole"]):
            screw = screws[si]
            if not rules.can_remove(screw, board_holes, plates):
                continue
            # Simulate removal: plates losing their last pin drop instantly.
            rest = screws[:si] + screws[si + 1:]
            dropped = [pid for pid in screw["plates"] if _pins(pid, rest) == 0]
            after = [p for p in plates if p["id"] not in dropped]
            drops = len(dropped)

            dest = None
            dest_pinned = None
            dest_rank = None
            for hi in range(len(board_holes)):
                if hi == screw["hole"] and drops == 0:
                    continue  # putting it straight back is a no-op
                verdict = rules.can_place(hi, board_holes, after, rest)
                if not verdict["ok"]:
                    continue
                rank = (len(verdict["pinned"]), hi)
                if dest_rank is None or rank < dest_rank:
                    dest_rank = rank
                    dest = hi
                    dest_pinned = sorted(verdict["pinned"])
            if dest is None:
                continue
            rank = (-drops, screw["hole"])
            if best is None or rank < best[0]:
                best = (rank, si, dropped, dest, dest_pinned)

        if best is None:
            return {"solvable": False, "moves": moves}

        _, si, dropped, dest, dest_pinned = best
        screw = screws[si]
        plates = [p for p in plates if p["id"] not in dropped]
        screw["hole"] = dest
        screw["plates"] = dest_pinned
        moves += 1

    return {"solvable": not plates, "moves": moves}


def parse_level_file(path):
    with open(path) as f:
        raw = json.load(f)
    return {
        "board_holes": [tuple(h) for h in raw["board_holes"]],
        "plates": [
            {"id": p["id"], "layer": p["layer"],
             "points": [tuple(pt) for pt in p["points"]],
             "holes": [tuple(h) for h in p.get("holes", [])],
             "xform": rules.IDENTITY}
            for p in raw["plates"]
        ],
        "screws": [{"hole": s["hole"], "plates": list(s["plates"])}
                   for s in raw["screws"]],
    }


def main():
    with open(os.path.join(LEVELS_DIR, "index.json")) as f:
        files = json.load(f)["levels"]
    failures = 0
    for name in files:
        level = parse_level_file(os.path.join(LEVELS_DIR, name))
        result = solve(level)
        status = "ok" if result["solvable"] else "FAIL"
        if not result["solvable"]:
            failures += 1
        print("%s %s: solvable=%s moves=%d"
              % (status, name, result["solvable"], result["moves"]))
    print("%d levels, %d unsolvable" % (len(files), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
