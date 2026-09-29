"""FOREST-CITY-01: the forest city's terems (merchants' and elders' town houses) after Codex's sheet
local/previews/forest-city-terems-01/terems-t1-t6-v1.png (PR #147, merged by the owner): two-storey
log houses on a rough stone plinth, shingled roofs, shutters, carved barge boards. Built closed for
now - no interior, shutters shut, the door shut - like the city's other closed houses.

Same frame and helpers as forest_city_halls.py: x along the front, the entry faces -y (Godot +z),
z = 0 the ground at the entry, the floor on the plinth.

blender --background --factory-startup --python art/blender/forest_city_terems.py -- --asset T1
"""
import argparse, sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import buildings_common as C
from forest_village_materials import make_materials
from water_workshops import Parts, door, export, log_wall
from forest_city_halls import chimney, gable_sill, pitch, plinth


def shut_window(P, face, along, z0, fixed, out, r, w=0.8, h=0.9):
    """A shuttered window in a log wall (outer face at `fixed`, outside towards `out`): a plank casing
    through the wall that fills the courses the cut takes out, a surround on the face, and two plank
    leaves shut flush in the opening with a Z brace - a closed house shows no room behind it."""
    a0, a1 = along - w * 0.5, along + w * 0.5
    t = 2 * r
    lo, hi = z0 - 1.6 * r - 0.02, z0 + h + 1.6 * r + 0.02

    def box(d0, d1, b0, b1, z_0, z_1, mat="oak", role="frame"):
        p0, p1 = sorted((fixed + out * d0, fixed + out * d1))
        if face == "y":
            P.box((b0, p0, z_0), (b1, p1, z_1), mat, role)
        else:
            P.box((p0, b0, z_0), (p1, b1, z_1), mat, role)

    box(-t - 0.01, 0.01, a0 - 0.05, a1 + 0.05, z0 + h, hi)
    box(-t - 0.01, 0.01, a0 - 0.05, a1 + 0.05, lo, z0)
    for b0, b1 in ((a0 - 0.05, a0), (a1, a1 + 0.05)):
        box(-t - 0.01, 0.01, b0, b1, z0, z0 + h)
    box(0.0, 0.08, a0 - 0.14, a1 + 0.14, z0 - 0.1, z0 + 0.02)
    box(0.0, 0.06, a0 - 0.16, a1 + 0.16, z0 + h - 0.02, z0 + h + 0.16)
    for b0, b1 in ((a0 - 0.12, a0 + 0.02), (a1 - 0.02, a1 + 0.12)):
        box(0.0, 0.04, b0, b1, z0, z0 + h)
    # The leaves, shut: each half of the opening, 1 cm over the middle seam, a ledge and brace on each.
    mid = (a0 + a1) * 0.5
    for s0, s1 in ((a0, mid + 0.005), (mid - 0.005, a1)):
        box(-0.07, -0.02, s0, s1, z0, z0 + h, "oak", "shutter")
        for zz in (z0 + 0.1, z0 + h - 0.2):
            box(-0.02, 0.0, s0 + 0.03, s1 - 0.03, zz, zz + 0.1, "oak", "shutter")
    return (a0, a1, z0, z0 + h)


def shut_windows(P, face, fixed, alongs, z0, out, r, w=0.8, h=0.9):
    return [shut_window(P, face, a, z0, fixed, out, r, w, h) for a in alongs]


def band(P, x0, x1, y0, y1, z, d=0.14, h=0.22):
    """The storey band: a squared beam proud of the logs all round at the upper floor's level."""
    for yy in (y0, y1):
        P.box((x0 - d, yy - d, z - h * 0.5), (x1 + d, yy + d, z + h * 0.5), "oak", "frame")
    for xx in (x0, x1):
        P.box((xx - d, y0 - d, z - h * 0.5), (xx + d, y1 + d, z + h * 0.5), "oak", "frame")


def roof_two_pitch(P, x0, x1, y_front, y_back, y_ridge, z_ridge, slope, over_x=0.6, t=0.2):
    """A gable roof whose ridge runs along x at y_ridge, each pitch reaching its own eave edge (the
    front one further out, over a gallery), carved barge boards and crossed finials on the gables."""
    for ye in (y_front, y_back):
        ze = z_ridge - abs(y_ridge - ye) * slope
        pitch(P, (x0 - over_x, ye, ze), (x1 + over_x, ye, ze), (x0 - over_x, y_ridge, z_ridge), (x1 + over_x, y_ridge, z_ridge), t)
        for xe in (x0 - over_x - 0.05, x1 + over_x + 0.05):
            P.beam((xe, ye, ze + 0.1), (xe, y_ridge, z_ridge + 0.12), 0.08, 0.4, "oak", "frame", up=(1, 0, 0))
    P.beam((x0 - over_x - 0.1, y_ridge, z_ridge + 0.25), (x1 + over_x + 0.1, y_ridge, z_ridge + 0.25), 0.22, 0.2, "oak", "frame")
    for xe in (x0 - over_x - 0.05, x1 + over_x + 0.05):
        for s in (-1, 1):
            P.beam((xe, y_ridge, z_ridge + 0.1), (xe, y_ridge + s * 0.55, z_ridge + 0.85), 0.08, 0.16, "oak", "frame")


def gable_wall(P, x_face, y0, y1, z0, z_ridge, z_eave, y_ridge, r, openings, inward):
    """A gable wall (along y at x_face) whose peak stands at y_ridge, not necessarily mid-wall: the
    logs above the eave are cut to the two roof lines."""
    pitch_z = 2 * r * 0.93
    z = z0 + r + r * 0.93
    while z < z_ridge:
        a0, a1 = y0, y1
        if z > z_eave:
            k = (z - z_eave) / (z_ridge - z_eave)
            a0 = y0 + (y_ridge - y0) * k
            a1 = y1 - (y1 - y_ridge) * k
            if a1 - a0 < 0.24:
                break
        cuts = sorted((a, b) for a, b, zl, zh in openings if zl < z + r * 0.6 and z - r * 0.6 < zh)
        s = a0
        for a, b in cuts + [(a1, a1)]:
            if min(a, a1) - s > 0.15:
                P.cyl((x_face + inward * r, s, z), (x_face + inward * r, min(a, a1), z), r, "oak", "gable", seg=7)
            s = max(s, b)
        z += pitch_z


# ------------------------------------------------------------------------------------------- T1
def terem_t1(mats):
    """T1 (13 x 11): a wide two-storey log house, a covered porch in the middle of the front with
    stairs up from the ground, an open gallery along the upper floor with a carved balustrade under
    the deepened front eave, a chimney through the back pitch."""
    bid = "T1"
    P = Parts(mats, bid)
    HX = 6.5
    Y0, Y1 = -2.4, 5.4            # the body, 7.8 deep
    GY = -3.8                     # the gallery's front edge
    FLOOR, UPPER, EAVE = 1.0, 3.95, 6.6
    R = 0.16
    YR = (Y0 + Y1) * 0.5          # the ridge over the body's middle
    SLOPE = 0.9
    RIDGE = EAVE + (Y1 - YR) * SLOPE

    plinth(P, -HX - 0.2, HX + 0.2, Y0 - 0.2, Y1 + 0.2, FLOOR - 0.12)
    P.box((-HX, Y0 + 0.2, FLOOR - 0.12), (HX, Y1 - 0.2, FLOOR), "oak", "floor")

    # Front: the door in the middle, two windows either side below; above, the gallery door and four.
    front = shut_windows(P, "y", Y0, (-4.7, -3.0, 3.0, 4.7), FLOOR + 1.1, -1, R)
    front += shut_windows(P, "y", Y0, (-4.2, -2.2, 2.2, 4.2), UPPER + 0.9, -1, R)
    front += [(-0.6, 0.6, FLOOR, FLOOR + 2.2), (-0.5, 0.5, UPPER + 0.05, UPPER + 2.05)]
    rear = shut_windows(P, "y", Y1, (-4.5, -1.5, 1.5, 4.5), FLOOR + 1.1, 1, R)
    rear += shut_windows(P, "y", Y1, (-4.5, -1.5, 1.5, 4.5), UPPER + 0.9, 1, R)
    left = shut_windows(P, "x", -HX, (Y0 + 2.0, Y1 - 2.0), FLOOR + 1.1, -1, R)
    left += shut_windows(P, "x", -HX, (Y0 + 2.0, Y1 - 2.0), UPPER + 0.9, -1, R)
    left += shut_windows(P, "x", -HX, (YR,), EAVE + 0.9, -1, R, 0.7, 0.8)
    right = shut_windows(P, "x", HX, (Y0 + 2.0, Y1 - 2.0), FLOOR + 1.1, 1, R)
    right += shut_windows(P, "x", HX, (Y0 + 2.0, Y1 - 2.0), UPPER + 0.9, 1, R)
    right += shut_windows(P, "x", HX, (YR,), EAVE + 0.9, 1, R, 0.7, 0.8)
    log_wall(P, "x", Y0 + R, -HX - 0.35, HX + 0.35, FLOOR - 0.05, EAVE, R, front, 0.0)
    log_wall(P, "x", Y1 - R, -HX - 0.35, HX + 0.35, FLOOR - 0.05, EAVE, R, rear, 0.0)
    gable_wall(P, -HX, Y0 - 0.35, Y1 + 0.35, FLOOR - 0.05, RIDGE - 0.1, EAVE, YR, R, left, 1)
    gable_wall(P, HX, Y0 - 0.35, Y1 + 0.35, FLOOR - 0.05, RIDGE - 0.1, EAVE, YR, R, right, -1)
    gable_sill(P, -HX, -HX + 2 * R, Y0, Y1, FLOOR, R)
    gable_sill(P, HX, HX - 2 * R, Y0, Y1, FLOOR, R)
    band(P, -HX, HX, Y0, Y1, UPPER)
    # Door frames: the entry below, the gallery door above.
    for a in (-0.75, 0.6):
        P.box((a, Y0 - 0.12, FLOOR), (a + 0.15, Y0 + 0.1, FLOOR + 2.2), "oak", "frame")
        P.box((a + 0.05, Y0 - 0.12, UPPER + 0.05), (a + 0.15, Y0 + 0.1, UPPER + 2.05), "oak", "frame")
    P.box((-0.8, Y0 - 0.14, FLOOR + 2.2), (0.8, Y0 + 0.1, FLOOR + 2.4), "oak", "frame")

    # The gallery: a board floor on the joists out of the wall, posts from the ground to the eave, a
    # carved balustrade (rails, balusters, a sawn board along the top).
    P.box((-HX + 0.4, GY, UPPER - 0.1), (HX - 0.4, Y0, UPPER + 0.05), "oak", "floor", "gallery")
    for k in range(9):
        x = -HX + 0.6 + k * (2 * HX - 1.2) / 8
        P.box((x - 0.07, GY + 0.05, UPPER - 0.3), (x + 0.07, Y0, UPPER - 0.1), "oak", "frame", "gallery")
    z_front = RIDGE - (YR - (GY - 0.4)) * SLOPE
    posts = (-HX + 0.55, -3.1, -1.4, 1.4, 3.1, HX - 0.55)
    for px in posts:
        top = RIDGE - (YR - GY) * SLOPE - 0.18
        P.box((px - 0.13, GY + 0.02, -0.3), (px + 0.13, GY + 0.28, top), "oak", "frame", "gallery")
        P.cyl((px, GY + 0.15, UPPER + 1.2), (px, GY + 0.15, UPPER + 1.5), 0.17, "oak", "frame", "gallery", seg=8)
    P.box((-HX + 0.4, GY + 0.05, UPPER + 0.95), (HX - 0.4, GY + 0.22, UPPER + 1.05), "oak", "frame", "railing")
    P.box((-HX + 0.4, GY + 0.07, UPPER + 0.08), (HX - 0.4, GY + 0.2, UPPER + 0.16), "oak", "frame", "railing")
    n = int((2 * HX - 0.8) / 0.22)
    for k in range(n):
        x = -HX + 0.5 + k * 0.22
        if any(abs(x - px) < 0.2 for px in posts):
            continue
        P.box((x - 0.035, GY + 0.1, UPPER + 0.16), (x + 0.035, GY + 0.17, UPPER + 0.95), "oak", "frame", "railing")
    for k in range(int((2 * HX - 0.8) / 0.5)):
        x = -HX + 0.65 + k * 0.5
        P.cyl((x, GY + 0.04, UPPER + 0.62), (x, GY - 0.01, UPPER + 0.62), 0.09, "oak", "frame", "carving", seg=6)

    # The porch under the gallery and in front of it: a landing at the floor, two posts, a small gable.
    PY = GY - 1.3
    P.box((-1.6, PY, -0.4), (1.6, Y0 - 0.05, FLOOR), "stone", "foundation")
    P.box((-1.55, PY + 0.02, FLOOR - 0.06), (1.55, Y0, FLOOR), "oak", "floor", "porch")
    for px in (-1.4, 1.4):
        P.box((px - 0.12, PY + 0.05, FLOOR), (px + 0.12, PY + 0.29, FLOOR + 2.3), "oak", "frame", "porch")
        P.beam((px, PY + 0.17, FLOOR + 2.3), (px, GY + 0.2, FLOOR + 2.3), 0.14, 0.18, "oak", "frame", "porch")
    top = UPPER - 0.35
    for sx in (-1, 1):
        pitch(P, (sx * 1.8, PY - 0.3, FLOOR + 2.3), (sx * 1.8, GY + 0.05, FLOOR + 2.3), (0, PY - 0.3, top), (0, GY + 0.05, top), 0.12)
        P.beam((sx * 1.85, PY - 0.33, FLOOR + 2.32), (0, PY - 0.33, top + 0.1), 0.07, 0.3, "oak", "frame", "porch", up=(0, 1, 0))
    P.poly([(-1.75, PY - 0.2, FLOOR + 2.35), (1.75, PY - 0.2, FLOOR + 2.35), (0, PY - 0.2, top - 0.08),
            (-1.75, PY - 0.12, FLOOR + 2.35), (1.75, PY - 0.12, FLOOR + 2.35), (0, PY - 0.12, top - 0.08)],
           [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)], "oak", "frame", "porch")
    # Stairs from the ground up to the landing, with a rail each side.
    for i in range(4):
        z = FLOOR * (4 - i) / 4
        P.box((-1.1, PY - 0.3 * (i + 1), -0.4), (1.1, PY - 0.3 * i, z), "oak", "floor", "entry_step")
    for sx in (-1, 1):
        P.beam((sx * 1.25, PY - 1.2, 0.9), (sx * 1.25, PY, FLOOR + 0.9), 0.08, 0.08, "oak", "frame", "railing")
        P.box((sx * 1.25 - 0.06, PY - 1.26, -0.3), (sx * 1.25 + 0.06, PY - 1.14, 0.9), "oak", "frame", "railing")

    # The roof: the front pitch reaches out over the gallery.
    roof_two_pitch(P, -HX, HX, GY - 0.4, Y1 + 0.7, YR, RIDGE, SLOPE)
    chimney(P, 2.6, Y1 - 2.0, FLOOR + 0.5, RIDGE + 0.9)

    P.emit(None, f"{bid}_")
    # The closed-house entry walks the stairs on a smooth wedge (closed_house_entry.gd).
    bpy.data.objects[f"{bid}_entry_step"]["item_id"] = "entry_steps"
    door(P, bid, -0.6, 0.6, Y0 + 0.08, FLOOR, FLOOR + 2.15, mats)
    return {"id": bid, "slug": "t1", "floor": FLOOR}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--asset", default="all")
    args = ap.parse_args(argv)
    for bid, build in {"T1": terem_t1}.items():
        if args.asset not in ("all", bid):
            continue
        C.reset()
        mats = make_materials(Path(__file__).resolve().parent / "forest-city-v1" / "textures")
        info = build(mats)
        bpy.context.view_layer.update()
        export(info)


if __name__ == "__main__":
    main()
