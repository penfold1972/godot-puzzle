"""Python mirror of src/core/rules.gd (v2 game rules).

Kept in mechanical sync with the GDScript version via the shared fixture
suite tests/fixtures/rules_cases.json (run: python3 tools/test_rules.py).

Transforms use the Godot Transform2D convention as a 6-tuple
(xa_x, xa_y, ya_x, ya_y, o_x, o_y):  world = x_axis*px + y_axis*py + origin.
"""

import math

PLACE_TOLERANCE = 10.0

IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def xform_apply(xf, p):
    xax, xay, yax, yay, ox, oy = xf
    return (xax * p[0] + yax * p[1] + ox, xay * p[0] + yay * p[1] + oy)


def xform_inverse_apply(xf, p):
    """Map a world point into plate-local space (affine inverse)."""
    xax, xay, yax, yay, ox, oy = xf
    det = xax * yay - yax * xay
    px, py = p[0] - ox, p[1] - oy
    return ((yay * px - yax * py) / det, (-xay * px + xax * py) / det)


def point_in_polygon(p, points):
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


def covering_plates(point, plates):
    out = []
    for p in plates:
        local = xform_inverse_apply(p.get("xform", IDENTITY), point)
        if point_in_polygon(local, p["points"]):
            out.append(p["id"])
    return out


def can_remove(screw, board_holes, plates):
    point = board_holes[screw["hole"]]
    pinned = screw["plates"]
    covering = covering_plates(point, plates)
    if not pinned:
        return not covering
    max_pinned_layer = max(
        (p["layer"] for p in plates if p["id"] in pinned), default=-(2 ** 31)
    )
    for cid in covering:
        if cid in pinned:
            continue
        plate = next((p for p in plates if p["id"] == cid), None)
        if plate is not None and plate["layer"] > max_pinned_layer:
            return False
    return True


def can_place(hole_index, board_holes, plates, screws, tolerance=PLACE_TOLERANCE):
    if any(s["hole"] == hole_index for s in screws):
        return {"ok": False, "pinned": []}
    point = board_holes[hole_index]
    covering = covering_plates(point, plates)
    for cid in covering:
        plate = next(p for p in plates if p["id"] == cid)
        xf = plate.get("xform", IDENTITY)
        aligned = any(
            math.dist(xform_apply(xf, h), point) <= tolerance
            for h in plate["holes"]
        )
        if not aligned:
            return {"ok": False, "pinned": []}
    return {"ok": True, "pinned": covering}
