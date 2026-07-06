#!/usr/bin/env python3
"""Runs the shared rule-parity fixture suite against tools/rules.py.

The same cases run against src/core/rules.gd via tests/test_rules.gd,
guaranteeing the Python generator and the game agree on the rules.
Usage: python3 tools/test_rules.py
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rules

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "tests", "fixtures", "rules_cases.json")


def build_state(scenario):
    board_holes = [tuple(h) for h in scenario["board_holes"]]
    plates = []
    for p in scenario["plates"]:
        plates.append({
            "id": p["id"],
            "layer": p["layer"],
            "points": [tuple(pt) for pt in p["points"]],
            "holes": [tuple(h) for h in p["holes"]],
            "xform": tuple(p["xform"]) if "xform" in p else rules.IDENTITY,
        })
    screws = [{"hole": s["hole"], "plates": list(s["plates"])}
              for s in scenario["screws"]]
    return board_holes, plates, screws


def main():
    with open(FIXTURES) as f:
        data = json.load(f)
    failures = 0
    checks = 0
    for scenario in data["scenarios"]:
        board_holes, plates, screws = build_state(scenario)
        for check in scenario["checks"]:
            checks += 1
            fn = check["fn"]
            label = "%s / %s" % (scenario["name"], fn)
            ok = False
            if fn == "covering":
                got = rules.covering_plates(tuple(check["point"]), plates)
                ok = sorted(got) == sorted(check["expect"])
                label += " %s -> %s" % (check["point"], got)
            elif fn == "can_remove":
                got = rules.can_remove(screws[check["screw"]], board_holes, plates)
                ok = got == check["expect"]
                label += " screw %d -> %s" % (check["screw"], got)
            elif fn == "can_place":
                got = rules.can_place(check["hole"], board_holes, plates, screws)
                ok = (got["ok"] == check["expect_ok"]
                      and sorted(got["pinned"]) == sorted(check["expect_pinned"]))
                label += " hole %d -> %s" % (check["hole"], got)
            else:
                label += " (unknown check fn)"
            print("[%s] %s" % ("OK" if ok else "FAIL", label))
            if not ok:
                failures += 1
    print("=== RESULT: %s (%d/%d checks passed) ==="
          % ("PASS" if failures == 0 else "FAIL", checks - failures, checks))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
