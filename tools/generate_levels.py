#!/usr/bin/env python3
"""v2 level generator: silhouette pin-board puzzles.

Pipeline per level (deterministic, seed = 4000 + level + attempt*100000):
  1. Scale the level's silhouette (tools/silhouettes.py) into the board.
  2. Ear-clip triangulate it, then grow N connected regions over the
     triangle adjacency graph (area-balanced BFS) -- the base plates.
     Each region boundary is extracted and shrunk ~3 px toward its centroid
     so same-layer neighbours never touch (they share a collision layer).
  3. Late levels add brace plates (layer 1): the two-triangle quad around a
     seam edge, pinned through shared screws with the pieces beneath.
  4. Punch screws (1-3 per piece by area), a top parking rail of empty
     holes, and a few empty in-piece sockets for re-pinning.
  5. Gate with tools/validate_v2.py rules and tools/quasi_solver.py; retry
     with a new sub-seed until the level passes.

Difficulty ramp over 50 levels: pieces 3->10, braces 0->2, parking rail
6->2 holes, screw caps 2->3. Each of the 17 silhouettes appears ~3 times
(I/II/III) at rising difficulty.

Usage:
  python3 tools/generate_levels.py             # write levels/*.json + index
  python3 tools/generate_levels.py --svg DIR   # also dump per-level SVGs
"""

import heapq
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rules
import silhouettes
import validate_v2
import quasi_solver

LEVEL_COUNT = 50
LEVELS_DIR = validate_v2.LEVELS_DIR
BOUNDS = (720, 1000)
SIL_BOX = (60, 190, 660, 940)
RAIL_Y = 70
MIN_PIECE_AREA = 7000.0
SEAM_GAP = 3.0
SCREW_MARGIN = 28.0
HOLE_SPACING = 46.0  # a hair above the validator's 44 for float safety
ATTEMPTS = 60


# ------------------------------------------------------------- geometry

def area(points):
    return validate_v2.signed_area(points)


def centroid(points):
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    return (cx, cy)


def tri_area(a, b, c):
    return ((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) / 2.0


def ear_clip(points):
    """Triangulate a simple CCW polygon; returns list of index triples."""
    n = len(points)
    idx = list(range(n))
    tris = []
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        ear_found = False
        for k in range(len(idx)):
            i0, i1, i2 = (idx[(k - 1) % len(idx)], idx[k], idx[(k + 1) % len(idx)])
            a, b, c = points[i0], points[i1], points[i2]
            if tri_area(a, b, c) <= 1e-9:
                continue  # reflex or degenerate corner
            ok = True
            for j in idx:
                if j in (i0, i1, i2):
                    continue
                p = points[j]
                if (tri_area(a, b, p) >= -1e-9 and tri_area(b, c, p) >= -1e-9
                        and tri_area(c, a, p) >= -1e-9):
                    ok = False
                    break
            if ok:
                tris.append((i0, i1, i2))
                idx.pop(k)
                ear_found = True
                break
        if not ear_found:
            return None  # numeric trouble; caller retries
    if len(idx) == 3:
        tris.append((idx[0], idx[1], idx[2]))
    return tris


def grow_regions(points, tris, n_regions, rng):
    """Partition triangles into n connected, area-balanced regions."""
    n_regions = min(n_regions, len(tris))
    tri_areas = [abs(tri_area(points[a], points[b], points[c])) for a, b, c in tris]
    tri_centers = [centroid([points[a], points[b], points[c]]) for a, b, c in tris]

    # Adjacency via shared edges.
    edge_owner = {}
    adj = [[] for _ in tris]
    for ti, (a, b, c) in enumerate(tris):
        for e in ((a, b), (b, c), (c, a)):
            key = (min(e), max(e))
            if key in edge_owner:
                other = edge_owner[key]
                adj[ti].append(other)
                adj[other].append(ti)
            else:
                edge_owner[key] = ti

    # Farthest-point seeding.
    seeds = [rng.randrange(len(tris))]
    while len(seeds) < n_regions:
        best, best_d = None, -1.0
        for ti in range(len(tris)):
            if ti in seeds:
                continue
            d = min(math.dist(tri_centers[ti], tri_centers[s]) for s in seeds)
            if d > best_d:
                best, best_d = ti, d
        seeds.append(best)

    assign = [-1] * len(tris)
    heap = []
    for ri, s in enumerate(seeds):
        assign[s] = ri
        heapq.heappush(heap, (tri_areas[s], rng.random(), ri))
    region_area = [tri_areas[s] for s in seeds]
    frontier = [set(adj[s]) for s in seeds]

    remaining = len(tris) - len(seeds)
    guard = 0
    while remaining > 0 and guard < 20000:
        guard += 1
        if not heap:
            break
        _, _, ri = heapq.heappop(heap)
        pick = None
        for cand in sorted(frontier[ri]):
            if assign[cand] == -1:
                pick = cand
                break
        frontier[ri] = {t for t in frontier[ri] if assign[t] == -1}
        if pick is None:
            continue  # region closed off; do not requeue
        assign[pick] = ri
        region_area[ri] += tri_areas[pick]
        frontier[ri].update(t for t in adj[pick] if assign[t] == -1)
        remaining -= 1
        heapq.heappush(heap, (region_area[ri], rng.random(), ri))

    if remaining > 0:
        # Orphans (unreachable from any open region): give them to any
        # assigned neighbour to keep every region connected.
        for _ in range(len(tris)):
            progressed = False
            for ti in range(len(tris)):
                if assign[ti] != -1:
                    continue
                for nb in adj[ti]:
                    if assign[nb] != -1:
                        assign[ti] = assign[nb]
                        progressed = True
                        break
            if all(a != -1 for a in assign):
                break
            if not progressed:
                return None
    return assign


def region_boundary(points, tris, assign, region_id):
    """Boundary polygon of one region; None if it isn't a single loop."""
    edges = set()
    for ti, (a, b, c) in enumerate(tris):
        if assign[ti] != region_id:
            continue
        for e in ((a, b), (b, c), (c, a)):
            if (e[1], e[0]) in edges:
                edges.discard((e[1], e[0]))
            else:
                edges.add(e)
    if not edges:
        return None
    nxt = {}
    for a, b in edges:
        if a in nxt:
            return None  # non-manifold vertex; retry
        nxt[a] = b
    start = next(iter(nxt))
    loop = [start]
    cur = nxt[start]
    guard = 0
    while cur != start and guard < len(nxt) + 2:
        guard += 1
        loop.append(cur)
        if cur not in nxt:
            return None
        cur = nxt[cur]
    if len(loop) != len(nxt):
        return None  # multiple loops (region with hole)
    out = [points[i] for i in loop]
    # Drop collinear runs to keep vertex counts sane.
    cleaned = []
    m = len(out)
    for i in range(m):
        a, b, c = out[(i - 1) % m], out[i], out[(i + 1) % m]
        if abs(tri_area(a, b, c)) > 1e-6:
            cleaned.append(b)
    return cleaned if len(cleaned) >= 3 else None


def shrink(points, gap=SEAM_GAP):
    """Pull every vertex `gap` px toward the centroid (seam separation)."""
    c = centroid(points)
    out = []
    for p in points:
        d = math.dist(p, c)
        if d < gap * 4:
            out.append(p)
        else:
            f = (d - gap) / d
            out.append((c[0] + (p[0] - c[0]) * f, c[1] + (p[1] - c[1]) * f))
    return out


def rnd(points):
    return [(round(x, 1), round(y, 1)) for x, y in points]


# ------------------------------------------------------------ difficulty

DISPLAY = {
    "tshirt": "T-Shirt", "collared_shirt": "Dress Shirt", "pants": "Pants",
    "mens_shoe": "Loafer", "womens_heel": "Stiletto", "car": "Car",
    "truck": "Pickup", "motorcycle": "Motorcycle", "cup": "Mug",
    "flamingo": "Flamingo", "dog": "Dog", "cat": "Cat", "robot": "Robot",
    "flying_saucer": "UFO", "house": "House", "sofa": "Sofa",
    "skyscraper": "Skyscraper",
}
ROMAN = ["I", "II", "III"]


def schedule():
    order = list(silhouettes.NAMES)
    random.Random(7).shuffle(order)
    plan = []
    for n in range(1, LEVEL_COUNT + 1):
        name = order[(n - 1) % len(order)]
        use = (n - 1) // len(order)
        plan.append((name, use))
    return plan


def params(n):
    return {
        "pieces": min(3 + n // 7, 10),
        "braces": 0 if n < 16 else (1 if n < 32 else 2),
        "rail": max(2, 6 - n // 12),
        "sockets": 2 if n < 20 else 1,
        "max_screws": 2 if n < 18 else 3,
    }


# ------------------------------------------------------------- assembly

def _tri_adjacency(tris):
    edge_owner = {}
    adj = [[] for _ in tris]
    for ti, (a, b, c) in enumerate(tris):
        for e in ((a, b), (b, c), (c, a)):
            key = (min(e), max(e))
            if key in edge_owner:
                other = edge_owner[key]
                adj[ti].append(other)
                adj[other].append(ti)
            else:
                edge_owner[key] = ti
    return adj


def _build_pieces(outline, tris, assign):
    """region id -> shrunk piece polygon, or None if any region is broken."""
    out = {}
    for rid in sorted(set(assign)):
        boundary = region_boundary(outline, tris, assign, rid)
        if boundary is None:
            return None
        if area(boundary) < 0:
            boundary.reverse()
        piece = rnd(shrink(boundary))
        if validate_v2.is_self_intersecting(piece):
            return None
        out[rid] = piece
    return out


def sample_point_inside(rng, poly, margin, taken, clear_polys=(), tries=400):
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    for _ in range(tries):
        p = (rng.uniform(min(xs), max(xs)), rng.uniform(min(ys), max(ys)))
        if not rules.point_in_polygon(p, poly):
            continue
        if validate_v2.dist_to_edges(p, poly) < margin:
            continue
        if any(math.dist(p, t) < HOLE_SPACING for t in taken):
            continue
        bad = False
        for cp in clear_polys:
            if rules.point_in_polygon(p, cp) or validate_v2.dist_to_edges(p, cp) < 8:
                bad = True
                break
        if bad:
            continue
        return (round(p[0], 1), round(p[1], 1))
    return None


def try_generate(n, name, use, rng):
    prm = params(n)
    outline, palette = silhouettes.get(name, SIL_BOX)
    tris = ear_clip(outline)
    if tris is None:
        return None
    assign = grow_regions(outline, tris, prm["pieces"], rng)
    if assign is None:
        return None

    # Build pieces; regions too thin or small to hold a screw (a flamingo
    # leg, a spire tip) get merged into an adjacent region and we rebuild.
    adj = _tri_adjacency(tris)
    pieces = None
    for _ in range(6):
        built = _build_pieces(outline, tris, assign)
        if built is None:
            return None
        bad = None
        for rid in sorted(built):
            piece = built[rid]
            if (abs(area(piece)) < MIN_PIECE_AREA
                    or sample_point_inside(rng, piece, SCREW_MARGIN, [],
                                           tries=250) is None):
                bad = rid
                break
        if bad is None:
            pieces = built
            break
        merged = False
        for ti in range(len(tris)):
            if assign[ti] != bad:
                continue
            for nb in adj[ti]:
                if assign[nb] != bad:
                    target = assign[nb]
                    assign = [target if a == bad else a for a in assign]
                    merged = True
                    break
            if merged:
                break
        if not merged:
            return None
    if pieces is None or len(pieces) < 2:
        return None
    # Renumber region ids compactly, keeping deterministic order.
    rid_order = sorted(pieces)
    rid_map = {rid: i for i, rid in enumerate(rid_order)}
    assign = [rid_map[a] for a in assign]
    pieces = [pieces[rid] for rid in rid_order]
    n_regions = len(pieces)

    # --- Braces: two-triangle quads over seams between different regions.
    braces = []
    if prm["braces"] > 0:
        edge_tris = {}
        for ti, (a, b, c) in enumerate(tris):
            for e in ((a, b), (b, c), (c, a)):
                key = (min(e), max(e))
                edge_tris.setdefault(key, []).append(ti)
        seams = []
        for (a, b), owners in edge_tris.items():
            if len(owners) == 2 and assign[owners[0]] != assign[owners[1]]:
                length = math.dist(outline[a], outline[b])
                seams.append((length, a, b, owners[0], owners[1]))
        seams.sort(reverse=True)
        for length, a, b, t1, t2 in seams:
            if len(braces) >= prm["braces"]:
                break
            if length < 100:
                continue
            # A rectangular strap laid along the seam, wide enough on both
            # sides to take a screw with full edge margins.
            pa, pb = outline[a], outline[b]
            mid = ((pa[0] + pb[0]) / 2.0, (pa[1] + pb[1]) / 2.0)
            dx, dy = (pb[0] - pa[0]) / length, (pb[1] - pa[1]) / length
            half_l = min(length * 0.35, 115.0)
            half_w = 65.0
            rect = [
                (mid[0] + dx * half_l + dy * half_w, mid[1] + dy * half_l - dx * half_w),
                (mid[0] + dx * half_l - dy * half_w, mid[1] + dy * half_l + dx * half_w),
                (mid[0] - dx * half_l - dy * half_w, mid[1] - dy * half_l + dx * half_w),
                (mid[0] - dx * half_l + dy * half_w, mid[1] - dy * half_l - dx * half_w),
            ]
            if any(not (30 <= x <= BOUNDS[0] - 30 and 160 <= y <= BOUNDS[1] - 30)
                   for x, y in rect):
                continue
            if area(rect) < 0:
                rect.reverse()
            rect = rnd(rect)
            if any(validate_v2.polygons_overlap(rect, br["points"]) for br in braces):
                continue
            braces.append({
                "points": rect,
                "covers": (assign[t1], assign[t2]),
            })

    # --- Screws, holes, pins.
    board_holes = []
    plate_holes = {i: [] for i in range(n_regions)}
    brace_holes = {i: [] for i in range(len(braces))}
    screws = []  # (hole_index, [plate ids])

    def add_hole(p):
        board_holes.append(p)
        return len(board_holes) - 1

    # Braced pieces first: each needs one screw under the brace (multi-pin).
    piece_screw_counts = {}
    for bi, brace in enumerate(braces):
        for ri in brace["covers"]:
            spot = None
            for _ in range(200):
                p = sample_point_inside(rng, pieces[ri], SCREW_MARGIN, board_holes)
                if p is None:
                    break
                if (rules.point_in_polygon(p, brace["points"])
                        and validate_v2.dist_to_edges(p, brace["points"]) >= SCREW_MARGIN
                        and all(math.dist(p, h) >= HOLE_SPACING for h in brace_holes[bi])):
                    other = [ob["points"] for oi, ob in enumerate(braces) if oi != bi]
                    if any(rules.point_in_polygon(p, op) for op in other):
                        continue
                    spot = p
                    break
            if spot is None:
                return None
            hi = add_hole(spot)
            plate_holes[ri].append(spot)
            brace_holes[bi].append(spot)
            screws.append((hi, [ri, n_regions + bi]))
            piece_screw_counts[ri] = piece_screw_counts.get(ri, 0) + 1

    # Regular screws for every piece (outside all braces).
    brace_polys = [b["points"] for b in braces]
    for ri, piece in enumerate(pieces):
        piece_area = abs(area(piece))
        want = 1 + (1 if piece_area > 30000 else 0) + (1 if piece_area > 90000 else 0)
        want = min(want, prm["max_screws"])
        have = piece_screw_counts.get(ri, 0)
        while have < max(want, 1):
            p = sample_point_inside(rng, piece, SCREW_MARGIN, board_holes,
                                    clear_polys=brace_polys)
            if p is None:
                break
            hi = add_hole(p)
            plate_holes[ri].append(p)
            screws.append((hi, [ri]))
            have += 1
        if have == 0:
            return None

    # Parking rail across the top (uncoverable: everything falls down).
    rail_n = prm["rail"]
    for k in range(rail_n):
        x = 120 + (480 * k / max(1, rail_n - 1)) if rail_n > 1 else 360.0
        board_holes.append((round(x, 1), float(RAIL_Y)))

    # Empty in-piece sockets (single-cover spots only).
    for _ in range(prm["sockets"]):
        ri = rng.randrange(n_regions)
        p = sample_point_inside(rng, pieces[ri], SCREW_MARGIN, board_holes,
                                clear_polys=brace_polys)
        if p is not None:
            board_holes.append(p)
            plate_holes[ri].append(p)

    # --- Assemble level dict (raw JSON-ready format).
    plates = []
    for ri, piece in enumerate(pieces):
        plates.append({
            "id": ri, "layer": 0,
            "color": palette[ri % len(palette)],
            "points": piece,
            "holes": plate_holes[ri],
        })
    for bi, brace in enumerate(braces):
        plates.append({
            "id": n_regions + bi, "layer": 1,
            "color": palette[3 % len(palette)],
            "points": brace["points"],
            "holes": brace_holes[bi],
        })
    return {
        "version": 2,
        "id": n,
        "name": "%s %s" % (DISPLAY[name], ROMAN[min(use, 2)]),
        "silhouette": name,
        "bounds": list(BOUNDS),
        "board_holes": board_holes,
        "plates": plates,
        "screws": [{"hole": hi, "plates": pids} for hi, pids in screws],
    }


def quasi_level(raw):
    return {
        "board_holes": [tuple(h) for h in raw["board_holes"]],
        "plates": [
            {"id": p["id"], "layer": p["layer"],
             "points": [tuple(pt) for pt in p["points"]],
             "holes": [tuple(h) for h in p["holes"]],
             "xform": rules.IDENTITY}
            for p in raw["plates"]
        ],
        "screws": [{"hole": s["hole"], "plates": list(s["plates"])}
                   for s in raw["screws"]],
    }


def generate_level(n, name, use):
    for attempt in range(ATTEMPTS):
        rng = random.Random(4000 + n + attempt * 100_000)
        raw = try_generate(n, name, use, rng)
        if raw is None:
            continue
        if validate_v2.validate(validate_v2.parse_level(raw)):
            continue
        result = quasi_solver.solve(quasi_level(raw))
        if not result["solvable"]:
            continue
        raw["_moves"] = result["moves"]
        return raw
    raise RuntimeError("could not generate level %d (%s)" % (n, name))


# ---------------------------------------------------------------- output

def level_to_json(raw):
    return {
        "version": 2,
        "id": raw["id"],
        "name": raw["name"],
        "silhouette": raw["silhouette"],
        "bounds": raw["bounds"],
        "board_holes": [[h[0], h[1]] for h in raw["board_holes"]],
        "plates": [
            {"id": p["id"], "layer": p["layer"], "color": p["color"],
             "points": [[pt[0], pt[1]] for pt in p["points"]],
             "holes": [[h[0], h[1]] for h in p["holes"]]}
            for p in raw["plates"]
        ],
        "screws": raw["screws"],
    }


def dump_level_svg(raw, directory):
    os.makedirs(directory, exist_ok=True)
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="360" height="500" '
             'viewBox="0 0 720 1000">'
             '<rect width="720" height="1000" fill="#2b415a"/>']
    for h in raw["board_holes"]:
        parts.append('<circle cx="%s" cy="%s" r="14" fill="#141f2a"/>' % tuple(h))
    for p in sorted(raw["plates"], key=lambda q: q["layer"]):
        path = " ".join("%s%s,%s" % ("M" if i == 0 else "L", pt[0], pt[1])
                        for i, pt in enumerate(p["points"])) + " Z"
        parts.append('<path d="%s" fill="%s" stroke="#1e2c3a" stroke-width="3" '
                     'fill-opacity="0.92"/>' % (path, p["color"]))
        for h in p["holes"]:
            parts.append('<circle cx="%s" cy="%s" r="11" fill="#1e2c3a" '
                         'fill-opacity="0.6"/>' % tuple(h))
    for s in raw["screws"]:
        h = raw["board_holes"][s["hole"]]
        parts.append('<g transform="translate(%s,%s)">'
                     '<circle r="20" fill="#ccd5dd" stroke="#6b7885" stroke-width="3"/>'
                     '<path d="M-12,0 H12 M0,-12 V12" stroke="#4a545e" '
                     'stroke-width="5"/></g>' % tuple(h))
    parts.append('</svg>')
    with open(os.path.join(directory, "level_%03d.svg" % raw["id"]), "w") as f:
        f.write("".join(parts))


def main():
    svg_dir = None
    if "--svg" in sys.argv:
        svg_dir = sys.argv[sys.argv.index("--svg") + 1]
    problems = silhouettes.self_check()
    if problems:
        for p in problems:
            print("SILHOUETTE PROBLEM:", p)
        return 1

    plan = schedule()
    os.makedirs(LEVELS_DIR, exist_ok=True)
    print("  lvl  name             plates screws holes  moves")
    files = []
    for n in range(1, LEVEL_COUNT + 1):
        name, use = plan[n - 1]
        raw = generate_level(n, name, use)
        fname = "level_%03d.json" % n
        with open(os.path.join(LEVELS_DIR, fname), "w") as f:
            json.dump(level_to_json(raw), f, indent=1)
            f.write("\n")
        files.append(fname)
        if svg_dir:
            dump_level_svg(raw, svg_dir)
        print("  %3d  %-16s %6d %6d %5d %6d" % (
            n, raw["name"], len(raw["plates"]), len(raw["screws"]),
            len(raw["board_holes"]), raw["_moves"]))
    with open(os.path.join(LEVELS_DIR, "index.json"), "w") as f:
        json.dump({"levels": files}, f, indent=1)
        f.write("\n")
    print("Wrote %d levels to %s" % (LEVEL_COUNT, os.path.normpath(LEVELS_DIR)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
