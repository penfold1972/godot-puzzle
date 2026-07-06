#!/usr/bin/env python3
"""Offline level generator + validator for Screw Puzzle.

Generates the seeded bulk levels, builds the designed showcase levels
(tutorial, shirt, star, vault), validates everything (schema rules mirrored
from src/core/level_loader.gd and solvability mirrored from
src/core/solver.gd), and writes levels/*.json + levels/index.json.

Deterministic: level N always regenerates identically (seed = 1000 + N).

Usage (from the screw_puzzle/ folder):
    python3 tools/generate_levels.py             # generate + validate + write
    python3 tools/generate_levels.py --validate  # only validate existing files
"""

import json
import math
import os
import random
import sys

LEVEL_COUNT = 50
HANDMADE = {1, 10, 30, 50}  # slots built by build_handmade(), not the RNG

BOUNDS = (720, 1000)
MARGIN = 30  # keep plates this far inside the board
MIN_PLATE_AREA = 2000.0  # mirror of LevelLoader.MIN_PLATE_AREA
EDGE_MARGIN = 24.0       # mirror of LevelLoader.EDGE_MARGIN
SCREW_EDGE_MARGIN = 28.0  # generator uses a stricter margin than the loader
MIN_SCREW_SPACING = 55.0
MAX_SCREWS = 4
SAME_LAYER_GAP = 3.0     # required clearance between same-layer plates

LAYER_COLORS = [
    ["#8f9fae", "#98a8b8", "#a2b1bf"],   # layer 0: steel
    ["#7f93a8", "#8a9db1", "#95a7ba"],   # layer 1: darker steel blue
    ["#a8b6c2", "#b1bec9", "#bac6d0"],   # layer 2: light steel
    ["#b8a37f", "#c2ad89", "#ccb793"],   # layer 3: brass
    ["#8ba69b", "#95b0a5", "#9fbaaf"],   # layer 4: patina
    ["#a89f8f", "#b2a999", "#bcb3a3"],   # layer 5: bronze grey
]

LEVELS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "levels")


# ---------------------------------------------------------------- geometry

def signed_area(points):
    total = 0.0
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        total += a[0] * b[1] - b[0] * a[1]
    return total * 0.5


def point_in_polygon(p, points):
    """Ray-casting test (matches Godot's Geometry2D.is_point_in_polygon
    for interior points; screws never sit on edges thanks to margins)."""
    x, y = p
    inside = False
    n = len(points)
    for i in range(n):
        ax, ay = points[i]
        bx, by = points[(i + 1) % n]
        if (ay > y) != (by > y):
            t = (y - ay) / (by - ay)
            if x < ax + t * (bx - ax):
                inside = not inside
    return inside


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
    return min(
        dist_point_segment(p, points[i], points[(i + 1) % len(points)])
        for i in range(len(points))
    )


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
    if o1 == 0 and on_seg(p1, p2, p3):
        return True
    if o2 == 0 and on_seg(p1, p2, p4):
        return True
    if o3 == 0 and on_seg(p3, p4, p1):
        return True
    if o4 == 0 and on_seg(p3, p4, p2):
        return True
    return False


def is_self_intersecting(points):
    n = len(points)
    for i in range(n):
        a1, a2 = points[i], points[(i + 1) % n]
        for j in range(i + 1, n):
            if j == i or (j + 1) % n == i or (i + 1) % n == j:
                continue  # adjacent edges share a vertex
            b1, b2 = points[j], points[(j + 1) % n]
            if segments_intersect(a1, a2, b1, b2):
                return True
    return False


def polygons_overlap(pa, pb):
    """True if two simple polygons overlap (edge crossing or containment)."""
    for i in range(len(pa)):
        for j in range(len(pb)):
            if segments_intersect(pa[i], pa[(i + 1) % len(pa)],
                                  pb[j], pb[(j + 1) % len(pb)]):
                return True
    return point_in_polygon(pa[0], pb) or point_in_polygon(pb[0], pa)


def polygon_clearance(pa, pb):
    """Minimum distance between two non-overlapping polygons' boundaries."""
    best = float("inf")
    for i in range(len(pa)):
        for p in (pa[i],):
            for j in range(len(pb)):
                best = min(best, dist_point_segment(
                    p, pb[j], pb[(j + 1) % len(pb)]))
    for j in range(len(pb)):
        for p in (pb[j],):
            for i in range(len(pa)):
                best = min(best, dist_point_segment(
                    p, pa[i], pa[(i + 1) % len(pa)]))
    return best


def convex_hull(points):
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


# ------------------------------------------------- solver mirror (solver.gd)

def solve_stats(level):
    remaining = [
        {"id": p["id"], "layer": p["layer"], "points": p["points"],
         "screws": list(p["screws"])}
        for p in level["plates"]
    ]
    total_screws = sum(len(p["screws"]) for p in remaining)

    def blocked(plates, plate_id, screw):
        my_layer = next(p["layer"] for p in plates if p["id"] == plate_id)
        return any(
            p["layer"] > my_layer and point_in_polygon(screw, p["points"])
            for p in plates if p["id"] != plate_id
        )

    passes = 0
    while remaining:
        passes += 1
        removed_any = False
        for p in remaining:
            kept = []
            for s in p["screws"]:
                if blocked(remaining, p["id"], s):
                    kept.append(s)
                else:
                    removed_any = True
            p["screws"] = kept
        still = []
        for p in remaining:
            if not p["screws"]:
                removed_any = True
            else:
                still.append(p)
        remaining = still
        if not removed_any:
            return {"solvable": False, "passes": passes,
                    "total_screws": total_screws}
    return {"solvable": True, "passes": passes, "total_screws": total_screws}


# --------------------------------------------- validator mirror (level_loader)

def validate_level(level):
    errors = []
    plates = level.get("plates", [])
    if not plates:
        return ["level has no plates"]
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
            errors.append("%s: area %.0f below minimum" % (label, abs(signed_area(pts))))
        for x, y in pts:
            if not (0 <= x <= BOUNDS[0] and 0 <= y <= BOUNDS[1]):
                errors.append("%s: point (%s,%s) outside bounds" % (label, x, y))
        screws = plate["screws"]
        if not 1 <= len(screws) <= MAX_SCREWS:
            errors.append("%s: %d screws (allowed 1..%d)" % (label, len(screws), MAX_SCREWS))
        for s in screws:
            if not point_in_polygon(s, pts):
                errors.append("%s: screw %s outside plate" % (label, s))
            elif dist_to_edges(s, pts) < EDGE_MARGIN:
                errors.append("%s: screw %s too close to edge (%.1f < %.1f)"
                              % (label, s, dist_to_edges(s, pts), EDGE_MARGIN))
    for i in range(len(plates)):
        for j in range(i + 1, len(plates)):
            a, b = plates[i], plates[j]
            if a["layer"] != b["layer"]:
                continue
            if polygons_overlap(a["points"], b["points"]):
                errors.append("plates %d and %d overlap on layer %d"
                              % (a["id"], b["id"], a["layer"]))
            elif polygon_clearance(a["points"], b["points"]) < SAME_LAYER_GAP:
                errors.append("plates %d and %d too close on layer %d"
                              % (a["id"], b["id"], a["layer"]))
    return errors


# ----------------------------------------------------------------- generator

def make_convex_plate(rng, center, radius):
    """Random convex polygon around center; returns int coordinate list."""
    if rng.random() < 0.3:
        # Rectangle, sometimes slightly rotated.
        w = radius * rng.uniform(0.9, 1.6)
        h = radius * rng.uniform(0.7, 1.2)
        angle = rng.uniform(-0.2, 0.2) if rng.random() < 0.5 else 0.0
        pts = []
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            x = sx * w / 2, sy * h / 2
            rx = x[0] * math.cos(angle) - x[1] * math.sin(angle)
            ry = x[0] * math.sin(angle) + x[1] * math.cos(angle)
            pts.append((center[0] + rx, center[1] + ry))
        hull = pts
    else:
        count = rng.randint(6, 10)
        cloud = []
        for _ in range(count):
            a = rng.uniform(0, 2 * math.pi)
            r = radius * rng.uniform(0.55, 1.0)
            cloud.append((center[0] + r * math.cos(a),
                          center[1] + r * math.sin(a)))
        hull = convex_hull(cloud)
    return [(int(round(x)), int(round(y))) for x, y in hull]


def plate_ok(points, same_layer_plates):
    if len(points) < 3 or is_self_intersecting(points):
        return False
    if abs(signed_area(points)) < MIN_PLATE_AREA * 3:
        return False
    for x, y in points:
        if not (MARGIN <= x <= BOUNDS[0] - MARGIN and MARGIN <= y <= BOUNDS[1] - MARGIN):
            return False
    for other in same_layer_plates:
        if polygons_overlap(points, other["points"]):
            return False
        if polygon_clearance(points, other["points"]) < SAME_LAYER_GAP:
            return False
    return True


def sample_screws(rng, points, count):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    screws = []
    for _ in range(600):
        if len(screws) == count:
            break
        p = (rng.randint(min(xs), max(xs)), rng.randint(min(ys), max(ys)))
        if not point_in_polygon(p, points):
            continue
        if dist_to_edges(p, points) < SCREW_EDGE_MARGIN:
            continue
        if any(math.hypot(p[0] - s[0], p[1] - s[1]) < MIN_SCREW_SPACING for s in screws):
            continue
        screws.append(p)
    return screws


def difficulty(n):
    """Level parameters for generated level n (1-based)."""
    return {
        "plates": min(3 + n // 6, 10),
        "layers": min(2 + n // 10, 6),
        "max_screws": 2 if n < 12 else (3 if n < 30 else 4),
        "min_passes": 1 if n < 8 else (2 if n < 15 else (3 if n < 35 else 4)),
    }


def generate_level(n):
    params = difficulty(n)
    for attempt in range(80):
        rng = random.Random(1000 + n + attempt * 100_000)
        level = try_generate(rng, n, params)
        if level is None:
            continue
        if validate_level(level):
            continue
        stats = solve_stats(level)
        if not stats["solvable"]:
            continue
        if stats["passes"] < params["min_passes"] and attempt < 60:
            continue  # not interlocked enough for this depth yet; retry
        return level
    raise RuntimeError("could not generate level %d" % n)


def try_generate(rng, n, params):
    total_plates = params["plates"]
    layer_count = params["layers"]

    # Distribute plates over layers: every layer gets one, remainder biased low.
    per_layer = [1] * layer_count
    for _ in range(total_plates - layer_count):
        weights = [layer_count - i for i in range(layer_count)]
        per_layer[rng.choices(range(layer_count), weights=weights)[0]] += 1

    plates = []
    pid = 0
    for layer in range(layer_count):
        same_layer = [p for p in plates if p["layer"] == layer]
        for _ in range(per_layer[layer]):
            placed = False
            for _ in range(120):
                radius = rng.uniform(85, 170) * (1.0 - 0.05 * layer)
                if layer == 0:
                    center = (rng.uniform(MARGIN + radius, BOUNDS[0] - MARGIN - radius),
                              rng.uniform(MARGIN + radius + 60, BOUNDS[1] - MARGIN - radius))
                else:
                    # Aim at a screw on a lower layer to create interlock.
                    lower = [p for p in plates if p["layer"] < layer and p["screws"]]
                    if not lower:
                        return None
                    prefer = [p for p in lower if p["layer"] == layer - 1]
                    source = rng.choice(prefer if prefer and rng.random() < 0.7 else lower)
                    target = rng.choice(source["screws"])
                    center = (target[0] + rng.uniform(-40, 40),
                              target[1] + rng.uniform(-40, 40))
                points = make_convex_plate(rng, center, radius)
                if not plate_ok(points, same_layer):
                    continue
                if layer > 0:
                    # The plate must actually cover the target screw, and
                    # cover it comfortably (no boundary ambiguity).
                    if not point_in_polygon(target, points):
                        continue
                    if dist_to_edges(target, points) < 8.0:
                        continue
                screw_count = rng.randint(1, params["max_screws"])
                screws = sample_screws(rng, points, screw_count)
                if not screws:
                    continue
                plate = {"id": pid, "layer": layer, "points": points,
                         "screws": screws,
                         "color": rng.choice(LAYER_COLORS[layer % len(LAYER_COLORS)])}
                plates.append(plate)
                same_layer.append(plate)
                pid += 1
                placed = True
                break
            if not placed:
                return None

    return {
        "id": n,
        "name": "generated",
        "bounds": list(BOUNDS),
        "plates": plates,
    }


# ------------------------------------------------------------ showcase levels

def rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def build_tutorial():
    """Level 1: two plates, three screws, teaches the blocking rule."""
    return {
        "id": 1, "name": "tutorial", "bounds": list(BOUNDS),
        "plates": [
            {"id": 0, "layer": 0, "color": "#98a8b8",
             "points": rect(160, 340, 560, 660),
             "screws": [(240, 500), (480, 500)]},
            {"id": 1, "layer": 1, "color": "#b8a37f",
             "points": rect(380, 400, 620, 600),
             "screws": [(560, 540)]},
        ],
    }


def build_shirt():
    """Level 10: the shirt from the reference ad screenshot."""
    return {
        "id": 10, "name": "shirt", "bounds": list(BOUNDS),
        "plates": [
            # Torso (bottom layer)
            {"id": 0, "layer": 0, "color": "#98a8b8",
             "points": rect(230, 290, 490, 780),
             "screws": [(270, 500), (450, 500), (270, 640), (450, 640)]},
            # Sleeves (2px gap from the torso so same-layer plates never touch)
            {"id": 1, "layer": 0, "color": "#a2b1bf",
             "points": [(110, 300), (226, 282), (226, 420), (130, 450)],
             "screws": [(178, 360)]},
            {"id": 2, "layer": 0, "color": "#a2b1bf",
             "points": [(494, 282), (610, 300), (590, 450), (494, 420)],
             "screws": [(542, 360)]},
            # Chest plate covers the torso's upper screws
            {"id": 3, "layer": 1, "color": "#8f9fae",
             "points": rect(240, 300, 480, 540),
             "screws": [(285, 345), (435, 345)]},
            # Hem/belt covers the torso's lower screws
            {"id": 4, "layer": 1, "color": "#b8a37f",
             "points": rect(240, 600, 480, 800),
             "screws": [(310, 755), (410, 755)]},
            # Collar sits on top of the chest plate
            {"id": 5, "layer": 2, "color": "#c2ad89",
             "points": [(295, 260), (425, 260), (360, 400)],
             "screws": [(360, 305)]},
        ],
    }


def build_star():
    """Level 30: five-pointed star with a pentagon hub and a cap."""
    cx, cy = 360.0, 520.0
    outer_r, inner_r, pent_r = 215.0, 95.0, 118.0
    plates = []

    def polar(radius, deg):
        rad = math.radians(deg)
        return (cx + radius * math.cos(rad), cy + radius * math.sin(rad))

    # Five point triangles on layer 0, shrunk toward their own tip so
    # neighbours never touch.
    for k in range(5):
        tip_angle = -90 + 72 * k
        tip = polar(outer_r, tip_angle)
        left = polar(inner_r, tip_angle - 36)
        right = polar(inner_r, tip_angle + 36)

        def toward_tip(p, f=0.06):
            return (p[0] + (tip[0] - p[0]) * f, p[1] + (tip[1] - p[1]) * f)

        pts = [tip, toward_tip(left), toward_tip(right)]
        pts = [(int(round(x)), int(round(y))) for x, y in pts]
        centroid = (sum(p[0] for p in pts) // 3, sum(p[1] for p in pts) // 3)
        # Nudge the screw toward the tip until it clears the edge margin.
        screw = centroid
        f = 0.0
        while dist_to_edges(screw, pts) < SCREW_EDGE_MARGIN and f < 0.8:
            f += 0.05
            screw = (int(round(centroid[0] + (tip[0] - centroid[0]) * f)),
                     int(round(centroid[1] + (tip[1] - centroid[1]) * f)))
        plates.append({"id": k, "layer": 0, "color": "#b8a37f",
                       "points": pts, "screws": [screw]})

    # Pentagon hub on layer 1 covering the triangles' inner edges.
    pent = [polar(pent_r, -90 + 72 * k) for k in range(5)]
    pent = [(int(round(x)), int(round(y))) for x, y in pent]
    pent_screws = [(int(round(x)), int(round(y)))
                   for x, y in (polar(50, 90), polar(50, 210), polar(50, 330))]
    plates.append({"id": 5, "layer": 1, "color": "#98a8b8",
                   "points": pent, "screws": pent_screws})

    # Diamond cap on layer 2 covering the pentagon's screws.
    cap = [(int(cx), int(cy - 85)), (int(cx + 85), int(cy)),
           (int(cx), int(cy + 85)), (int(cx - 85), int(cy))]
    plates.append({"id": 6, "layer": 2, "color": "#c2ad89",
                   "points": cap, "screws": [(int(cx), int(cy))]})

    return {"id": 30, "name": "star", "bounds": list(BOUNDS), "plates": plates}


def build_vault():
    """Level 50: vault door -- quadrants, corner caps, core, top cap."""
    cx, cy = 360, 520
    plates = []
    # Four quadrant squares (layer 0), 3px gap at the axes.
    offsets = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for i, (sx, sy) in enumerate(offsets):
        x0, y0 = cx + 3 * sx, cy + 3 * sy
        x1, y1 = cx + 250 * sx, cy + 250 * sy
        pts = rect(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))
        outer = (cx + 165 * sx, cy + 165 * sy)   # covered by corner cap
        inner = (cx + 60 * sx, cy + 60 * sy)     # covered by the core
        plates.append({"id": i, "layer": 0, "color": "#8f9fae",
                       "points": pts, "screws": [outer, inner]})
    # Corner caps (layer 1) over the quadrants' outer screws.
    for i, (sx, sy) in enumerate(offsets):
        ccx, ccy = cx + 165 * sx, cy + 165 * sy
        plates.append({"id": 4 + i, "layer": 1, "color": "#b8a37f",
                       "points": rect(ccx - 70, ccy - 70, ccx + 70, ccy + 70),
                       "screws": [(ccx, ccy)]})
    # Core octagon (layer 2) over the quadrants' inner screws.
    core = []
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        core.append((int(round(cx + 150 * math.cos(a))),
                     int(round(cy + 150 * math.sin(a)))))
    plates.append({"id": 8, "layer": 2, "color": "#98a8b8",
                   "points": core, "screws": [(cx - 60, cy), (cx + 60, cy)]})
    # Top diamond (layer 3) over the core's screws.
    cap = [(cx, cy - 92), (cx + 92, cy), (cx, cy + 92), (cx - 92, cy)]
    plates.append({"id": 9, "layer": 3, "color": "#c2ad89",
                   "points": cap, "screws": [(cx, cy)]})
    return {"id": 50, "name": "vault", "bounds": list(BOUNDS), "plates": plates}


def build_handmade():
    return {1: build_tutorial(), 10: build_shirt(), 30: build_star(), 50: build_vault()}


# ------------------------------------------------------------------ file I/O

def level_to_json(level):
    return {
        "id": level["id"],
        "name": level["name"],
        "bounds": [int(b) for b in level["bounds"]],
        "plates": [
            {
                "id": p["id"],
                "layer": p["layer"],
                "color": p["color"],
                "points": [[int(x), int(y)] for x, y in p["points"]],
                "screws": [[int(x), int(y)] for x, y in p["screws"]],
            }
            for p in level["plates"]
        ],
    }


def level_from_json(raw):
    return {
        "id": raw["id"],
        "name": raw.get("name", ""),
        "bounds": raw.get("bounds", list(BOUNDS)),
        "plates": [
            {
                "id": p["id"],
                "layer": p["layer"],
                "color": p.get("color", "#8fa3b8"),
                "points": [tuple(pt) for pt in p["points"]],
                "screws": [tuple(s) for s in p["screws"]],
            }
            for p in raw["plates"]
        ],
    }


def filename(n):
    return "level_%03d.json" % n


def write_levels():
    os.makedirs(LEVELS_DIR, exist_ok=True)
    handmade = build_handmade()
    report = []
    for n in range(1, LEVEL_COUNT + 1):
        level = handmade[n] if n in HANDMADE else generate_level(n)
        errors = validate_level(level)
        stats = solve_stats(level)
        if errors or not stats["solvable"]:
            print("INTERNAL ERROR in level %d:" % n)
            for e in errors:
                print("  -", e)
            if not stats["solvable"]:
                print("  - not solvable")
            return 1
        path = os.path.join(LEVELS_DIR, filename(n))
        with open(path, "w") as f:
            json.dump(level_to_json(level), f, indent=1)
            f.write("\n")
        report.append((n, level["name"], len(level["plates"]),
                       stats["total_screws"], stats["passes"]))
    with open(os.path.join(LEVELS_DIR, "index.json"), "w") as f:
        json.dump({"levels": [filename(n) for n in range(1, LEVEL_COUNT + 1)]},
                  f, indent=1)
        f.write("\n")

    print("  lvl  name        plates  screws  passes")
    for n, name, plates, screws, passes in report:
        print("  %3d  %-10s  %6d  %6d  %6d" % (n, name, plates, screws, passes))
    print("Wrote %d levels to %s" % (LEVEL_COUNT, os.path.normpath(LEVELS_DIR)))
    return 0


def validate_existing():
    index_path = os.path.join(LEVELS_DIR, "index.json")
    with open(index_path) as f:
        files = json.load(f)["levels"]
    failures = 0
    for i, fname in enumerate(files):
        with open(os.path.join(LEVELS_DIR, fname)) as f:
            level = level_from_json(json.load(f))
        errors = validate_level(level)
        stats = solve_stats(level)
        if errors or not stats["solvable"]:
            failures += 1
            print("FAIL %s:" % fname)
            for e in errors:
                print("  -", e)
            if not stats["solvable"]:
                print("  - not solvable")
    if len(files) < 48:
        failures += 1
        print("FAIL: only %d levels, need >= 48" % len(files))
    print("%d levels checked, %d failures" % (len(files), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    if "--validate" in sys.argv:
        sys.exit(validate_existing())
    sys.exit(write_levels())
