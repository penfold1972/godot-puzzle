#!/usr/bin/env python3
"""The 17 object silhouettes for Screw Puzzle levels.

Each silhouette is a hand-authored simple polygon (y grows downward, no
self-intersection, no donut holes) in an arbitrary local box, plus a color
palette. `get(name, box)` returns the outline scaled/centered into a target
board rectangle. `--svg DIR` dumps every silhouette for visual review.

Self-checks (run as part of generation): simple polygon, minimum area.
"""

import math
import os
import sys

# name -> (points, palette). Palettes are light->dark plate fills.
RAW = {
    "tshirt": ([
        (35, 0), (65, 0), (70, 5), (100, 15), (95, 35), (75, 30), (75, 90),
        (25, 90), (25, 30), (5, 35), (0, 15), (30, 5)],
        ["#c25b4e", "#d3695b", "#b04d41", "#e07a6c", "#9c4237"]),
    "collared_shirt": ([
        (35, 0), (45, 8), (50, 16), (55, 8), (65, 0), (90, 10), (100, 60),
        (82, 64), (78, 34), (78, 95), (22, 95), (22, 34), (18, 64), (0, 60),
        (10, 10)],
        ["#6d8fb5", "#7d9dc0", "#5d7fa5", "#8eadd0", "#4f7095"]),
    "pants": ([
        (20, 0), (80, 0), (85, 95), (60, 95), (52, 30), (48, 30), (40, 95),
        (15, 95)],
        ["#4a5d79", "#5a6d89", "#3d4f68", "#6a7d99", "#33445a"]),
    "mens_shoe": ([
        (5, 20), (20, 20), (40, 38), (75, 42), (95, 48), (98, 55), (95, 62),
        (5, 62), (2, 40)],
        ["#7a5642", "#8a6650", "#6a4936", "#9a765e", "#5a3d2c"]),
    "womens_heel": ([
        (2, 86), (6, 72), (18, 60), (34, 48), (46, 36), (58, 27), (70, 22),
        (80, 26), (84, 34), (85, 44), (91, 82), (91, 90), (83, 90), (79, 54),
        (74, 46), (56, 56), (38, 68), (18, 80)],
        ["#a34a68", "#b35a78", "#933d58", "#c36a88", "#83324a"]),
    "car": ([
        (0, 52), (3, 36), (18, 32), (28, 16), (62, 16), (75, 32), (96, 38),
        (100, 52)],
        ["#3f7fae", "#4f8fbe", "#33709e", "#5f9fce", "#2a608c"]),
    "truck": ([
        (0, 55), (0, 32), (6, 30), (10, 14), (36, 14), (40, 30), (98, 30),
        (100, 55)],
        ["#b3563d", "#c3664d", "#a34930", "#d3765d", "#8f3d28"]),
    "motorcycle": ([
        (4, 72), (6, 62), (14, 56), (24, 56), (28, 46), (28, 34), (34, 34),
        (36, 44), (50, 44), (60, 36), (64, 24), (62, 14), (68, 12), (70, 22),
        (76, 28), (84, 40), (84, 54), (90, 58), (96, 66), (94, 76), (88, 84),
        (78, 86), (68, 82), (62, 74), (62, 66), (56, 62), (40, 62), (34, 68),
        (34, 76), (28, 84), (16, 86), (6, 80)],
        ["#5a5f66", "#6a6f76", "#4d5258", "#7a7f86", "#404449"]),
    "cup": ([
        (10, 5), (70, 5), (70, 18), (90, 16), (96, 30), (90, 46), (70, 42),
        (66, 72), (14, 72)],
        ["#c9913c", "#d9a14c", "#b9812f", "#e9b15c", "#a97124"]),
    "flamingo": ([
        (14, 2), (22, 4), (24, 10), (17, 11), (22, 24), (30, 36), (42, 40),
        (58, 42), (66, 50), (62, 62), (50, 68), (54, 94), (62, 96), (62, 99),
        (48, 99), (48, 70), (38, 68), (28, 62), (24, 52), (28, 44), (20, 30),
        (12, 14), (6, 10), (6, 4)],
        ["#e08298", "#f092a8", "#d07288", "#ffa2b8", "#c06278"]),
    "dog": ([
        (0, 24), (6, 16), (14, 12), (22, 16), (26, 26), (40, 30), (64, 28),
        (78, 24), (82, 12), (88, 10), (86, 22), (80, 34), (82, 62), (84, 66),
        (76, 66), (74, 38), (60, 40), (58, 66), (50, 66), (48, 40), (36, 42),
        (34, 66), (26, 66), (24, 40), (20, 36), (14, 38), (2, 32)],
        ["#a3773c", "#b3874c", "#93672f", "#c3975c", "#835a24"]),
    "cat": ([
        (30, 10), (36, 2), (42, 10), (58, 10), (64, 2), (70, 10), (74, 20),
        (70, 30), (60, 34), (72, 44), (78, 60), (76, 80), (80, 84), (84, 80),
        (88, 84), (84, 92), (70, 92), (24, 92), (18, 80), (22, 60), (30, 44),
        (40, 34), (28, 28), (26, 18)],
        ["#6e6673", "#7e7683", "#5e5763", "#8e8693", "#4f4854"]),
    "robot": ([
        (46, 0), (54, 0), (54, 6), (64, 6), (64, 24), (56, 24), (56, 28),
        (70, 28), (70, 32), (80, 32), (80, 54), (70, 54), (70, 66), (58, 66),
        (58, 92), (66, 92), (66, 98), (52, 98), (52, 70), (48, 70), (48, 98),
        (34, 98), (34, 92), (42, 92), (42, 66), (30, 66), (30, 54), (20, 54),
        (20, 32), (30, 32), (30, 28), (44, 28), (44, 24), (36, 24), (36, 6),
        (46, 6)],
        ["#8fa6a0", "#9fb6b0", "#7f968f", "#afc6c0", "#6f857f"]),
    "flying_saucer": ([
        (38, 10), (62, 10), (70, 22), (92, 28), (100, 38), (92, 46), (70, 50),
        (30, 50), (8, 46), (0, 38), (8, 28), (30, 22)],
        ["#79a8a2", "#89b8b2", "#699892", "#99c8c2", "#598882"]),
    "house": ([
        (50, 0), (68, 13), (68, 4), (78, 4), (78, 20), (95, 32), (86, 32),
        (86, 90), (14, 90), (14, 32), (5, 32)],
        ["#b08d5f", "#c09d6f", "#a07d52", "#d0ad7f", "#8f6d45"]),
    "sofa": ([
        (0, 28), (10, 22), (18, 26), (18, 14), (82, 14), (82, 26), (90, 22),
        (100, 28), (100, 52), (92, 52), (92, 62), (82, 62), (82, 54), (18, 54),
        (18, 62), (8, 62), (8, 52), (0, 52)],
        ["#7c6aa0", "#8c7ab0", "#6c5a90", "#9c8ac0", "#5c4a7f"]),
    "skyscraper": ([
        (48, 0), (52, 0), (52, 10), (58, 10), (58, 26), (64, 26), (64, 44),
        (72, 44), (72, 96), (28, 96), (28, 44), (36, 44), (36, 26), (42, 26),
        (42, 10), (48, 10)],
        ["#9aa8b6", "#aab8c6", "#8a98a6", "#bac8d6", "#7a8896"]),
}

NAMES = sorted(RAW.keys())

MIN_AREA_FRACTION = 0.15  # silhouette must fill a sane share of its bbox


def _signed_area(points):
    total = 0.0
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        total += a[0] * b[1] - b[0] * a[1]
    return total * 0.5


def _segments_intersect(p1, p2, p3, p4):
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


def is_simple(points):
    n = len(points)
    for i in range(n):
        for j in range(i + 1, n):
            if j == i or (j + 1) % n == i or (i + 1) % n == j:
                continue
            if _segments_intersect(points[i], points[(i + 1) % n],
                                   points[j], points[(j + 1) % n]):
                return False
    return True


def self_check():
    """Returns a list of problems; empty means all silhouettes are sound."""
    problems = []
    for name in NAMES:
        pts, palette = RAW[name]
        if len(pts) < 6:
            problems.append("%s: too few vertices" % name)
        if not is_simple(pts):
            problems.append("%s: self-intersecting outline" % name)
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        bbox_area = (max(xs) - min(xs)) * (max(ys) - min(ys))
        if bbox_area <= 0 or abs(_signed_area(pts)) < MIN_AREA_FRACTION * bbox_area:
            problems.append("%s: degenerate area" % name)
        if len(palette) < 3:
            problems.append("%s: palette too small" % name)
    return problems


def get(name, box):
    """Silhouette scaled and centered into box=(x0, y0, x1, y1).
    Returns (points, palette). Winding normalized counter-clockwise in
    screen coordinates (positive signed area with y down)."""
    pts, palette = RAW[name]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    x0, y0, x1, y1 = box
    scale = min((x1 - x0) / w, (y1 - y0) / h)
    ox = x0 + ((x1 - x0) - w * scale) / 2.0 - min(xs) * scale
    oy = y0 + ((y1 - y0) - h * scale) / 2.0 - min(ys) * scale
    out = [(p[0] * scale + ox, p[1] * scale + oy) for p in pts]
    if _signed_area(out) < 0:
        out.reverse()
    return out, list(palette)


def dump_svg(directory):
    os.makedirs(directory, exist_ok=True)
    for name in NAMES:
        pts, palette = get(name, (20, 20, 340, 460))
        path = " ".join("%s%.1f,%.1f" % ("M" if i == 0 else "L", p[0], p[1])
                        for i, p in enumerate(pts)) + " Z"
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="360" '
               'height="480" viewBox="0 0 360 480">'
               '<rect width="360" height="480" fill="#35506b"/>'
               '<path d="%s" fill="%s" stroke="#1e2c3a" stroke-width="3"/>'
               '</svg>' % (path, palette[0]))
        with open(os.path.join(directory, "silhouette_%s.svg" % name), "w") as f:
            f.write(svg)
    print("wrote %d silhouette SVGs to %s" % (len(NAMES), directory))


if __name__ == "__main__":
    problems = self_check()
    for p in problems:
        print("PROBLEM:", p)
    if "--svg" in sys.argv:
        dump_svg(sys.argv[sys.argv.index("--svg") + 1])
    print("%d silhouettes, %d problems" % (len(NAMES), len(problems)))
    sys.exit(1 if problems else 0)
