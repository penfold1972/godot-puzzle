#!/usr/bin/env python3
"""Python mirror of LevelLoader.validate (v2 schema) so levels can be
checked without a Godot binary. Shares geometry with rules.py.

Usage: python3 tools/validate_v2.py            # validate all levels in index
       python3 tools/validate_v2.py FILE...    # validate specific files
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rules

MIN_PLATE_AREA = 2000.0
EDGE_MARGIN = 24.0
HOLE_SPACING_MIN = 44.0
REST_ALIGN_TOLERANCE = 2.0

LEVELS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "levels")


def signed_area(points):
    total = 0.0
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        total += a[0] * b[1] - b[0] * a[1]
    return total * 0.5


def dist_point_segment(p, a, b):
    px, py = p
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    length_sq = dx * dx + dy * dy
    if length_sq == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length_sq))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def dist_to_edges(p, points):
    return min(dist_point_segment(p, points[i], points[(i + 1) % len(points)])
               for i in range(len(points)))


def segments_intersect(p1, p2, p3, p4):
    def orient(a, b, c):
        v = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        if abs(v) < 1e-9:
            return 0
        return 1 if v > 0 else -1

    def on_seg(a, b, c):
        return (min(a[0], b[0]) - 1e-9 <= c[0] <= max(a[0], b[0]) + 1e-9
                and min(a[1], b[1]) - 1e-9 <= c[1] <= max(a[1], b[1]) + 1e-9)

    o1, o2 = orient(p1, p2, p3), orient(p1, p2, p4)
    o3, o4 = orient(p3, p4, p1), orient(p3, p4, p2)
    if o1 != o2 and o3 != o4:
        return True
    for (a, b, c, o) in ((p1, p2, p3, o1), (p1, p2, p4, o2),
                         (p3, p4, p1, o3), (p3, p4, p2, o4)):
        if o == 0 and on_seg(a, b, c):
            return True
    return False


def is_self_intersecting(points):
    n = len(points)
    for i in range(n):
        for j in range(i + 1, n):
            if j == i or (j + 1) % n == i or (i + 1) % n == j:
                continue
            if segments_intersect(points[i], points[(i + 1) % n],
                                  points[j], points[(j + 1) % n]):
                return True
    return False


def polygons_overlap(pa, pb):
    for i in range(len(pa)):
        for j in range(len(pb)):
            if segments_intersect(pa[i], pa[(i + 1) % len(pa)],
                                  pb[j], pb[(j + 1) % len(pb)]):
                return True
    return rules.point_in_polygon(pa[0], pb) or rules.point_in_polygon(pb[0], pa)


def parse_level(raw):
    return {
        "id": raw.get("id", 0),
        "name": raw.get("name", ""),
        "silhouette": raw.get("silhouette", ""),
        "board_holes": [tuple(h) for h in raw.get("board_holes", [])],
        "plates": [
            {"id": p["id"], "layer": p["layer"],
             "points": [tuple(pt) for pt in p["points"]],
             "holes": [tuple(h) for h in p.get("holes", [])],
             "xform": rules.IDENTITY}
            for p in raw.get("plates", [])
        ],
        "screws": [{"hole": s["hole"], "plates": list(s["plates"])}
                   for s in raw.get("screws", [])],
    }


def validate(level):
    errors = []
    plates = level["plates"]
    board_holes = level["board_holes"]
    screws = level["screws"]
    if not plates:
        return ["level has no plates"]
    if not board_holes:
        return ["level has no board holes"]

    for i in range(len(board_holes)):
        for j in range(i + 1, len(board_holes)):
            if math.dist(board_holes[i], board_holes[j]) < HOLE_SPACING_MIN:
                errors.append("board holes %d and %d closer than %.0f px"
                              % (i, j, HOLE_SPACING_MIN))

    seen = set()
    for plate in plates:
        pid = plate["id"]
        label = "plate %d" % pid
        if pid in seen:
            errors.append("%s: duplicate id" % label)
        seen.add(pid)
        pts = plate["points"]
        if len(pts) < 3:
            errors.append("%s: fewer than 3 points" % label)
            continue
        if is_self_intersecting(pts):
            errors.append("%s: self-intersecting polygon" % label)
            continue
        if abs(signed_area(pts)) < MIN_PLATE_AREA:
            errors.append("%s: area below minimum" % label)
        holes = plate["holes"]
        if not holes:
            errors.append("%s: has no screw holes" % label)
        for h in holes:
            if not rules.point_in_polygon(h, pts):
                errors.append("%s: hole %s outside plate" % (label, h))
            elif dist_to_edges(h, pts) < EDGE_MARGIN:
                errors.append("%s: hole %s too close to plate edge (%.1f)"
                              % (label, h, dist_to_edges(h, pts)))
        for i in range(len(holes)):
            for j in range(i + 1, len(holes)):
                if math.dist(holes[i], holes[j]) < HOLE_SPACING_MIN:
                    errors.append("%s: holes %d and %d too close" % (label, i, j))

    for i in range(len(plates)):
        for j in range(i + 1, len(plates)):
            a, b = plates[i], plates[j]
            if a["layer"] != b["layer"]:
                continue
            if polygons_overlap(a["points"], b["points"]):
                errors.append("plates %d and %d overlap but share layer %d"
                              % (a["id"], b["id"], a["layer"]))

    used = set()
    pinned_count = {}
    for s in screws:
        hole = s["hole"]
        if hole < 0 or hole >= len(board_holes):
            errors.append("screw hole index %d out of range" % hole)
            continue
        if hole in used:
            errors.append("board hole %d used by more than one screw" % hole)
        used.add(hole)
        point = board_holes[hole]
        covering = sorted(rules.covering_plates(point, plates))
        declared = sorted(s["plates"])
        if covering != declared:
            errors.append("screw at hole %d declares plates %s but covers %s"
                          % (hole, declared, covering))
        for pid in covering:
            plate = next(p for p in plates if p["id"] == pid)
            if not any(math.dist(h, point) <= REST_ALIGN_TOLERANCE
                       for h in plate["holes"]):
                errors.append("screw at hole %d: plate %d has no aligned hole"
                              % (hole, pid))
            pinned_count[pid] = pinned_count.get(pid, 0) + 1

    for plate in plates:
        if pinned_count.get(plate["id"], 0) < 1:
            errors.append("plate %d starts with no screws" % plate["id"])

    if len(screws) >= len(board_holes):
        errors.append("no empty board hole at start")
    return errors


def main(argv):
    if len(argv) > 1:
        files = argv[1:]
    else:
        with open(os.path.join(LEVELS_DIR, "index.json")) as f:
            files = [os.path.join(LEVELS_DIR, name)
                     for name in json.load(f)["levels"]]
    failures = 0
    for path in files:
        with open(path) as f:
            raw = json.load(f)
        if raw.get("version") != 2:
            failures += 1
            print("FAIL %s: not a v2 level" % os.path.basename(path))
            continue
        errors = validate(parse_level(raw))
        if errors:
            failures += 1
            print("FAIL %s:" % os.path.basename(path))
            for e in errors:
                print("  -", e)
    print("%d levels checked, %d failures" % (len(files), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
