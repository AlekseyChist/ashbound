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


def roof_two_pitch(P, x0, x1, y_front, y_back, y_ridge, z_ridge, slope, over_x=0.6, t=0.2, over_x0=None, carve=(True, True)):
    """A gable roof whose ridge runs along x at y_ridge, each pitch reaching its own eave edge (the
    front one further out, over a gallery), carved barge boards and crossed finials on the gables.
    over_x0: the overhang at the x0 end when it differs (0 where the roof runs into a taller wall);
    carve: barge boards and finials at the (x0, x1) gables."""
    ox0 = over_x if over_x0 is None else over_x0
    ends = [e for e, c in ((x0 - ox0 - 0.05, carve[0]), (x1 + over_x + 0.05, carve[1])) if c]
    for ye in (y_front, y_back):
        ze = z_ridge - abs(y_ridge - ye) * slope
        pitch(P, (x0 - ox0, ye, ze), (x1 + over_x, ye, ze), (x0 - ox0, y_ridge, z_ridge), (x1 + over_x, y_ridge, z_ridge), t)
        for xe in ends:
            P.beam((xe, ye, ze + 0.1), (xe, y_ridge, z_ridge + 0.12), 0.08, 0.4, "oak", "frame", up=(1, 0, 0))
    P.beam((x0 - ox0 - 0.1, y_ridge, z_ridge + 0.25), (x1 + over_x + 0.1, y_ridge, z_ridge + 0.25), 0.22, 0.2, "oak", "frame")
    for xe in ends:
        for s in (-1, 1):
            P.beam((xe, y_ridge, z_ridge + 0.1), (xe, y_ridge + s * 0.55, z_ridge + 0.85), 0.08, 0.16, "oak", "frame")


def roof_ridge_y(P, x0, x1, y0, y1, x_ridge, z_ridge, slope, over_y=0.6, t=0.2):
    """A gable roof whose ridge runs along y at x_ridge (the gables face -y and +y), carved barge
    boards and crossed finials on both gables. x0/x1 are the eave lines (overhang included)."""
    for xe in (x0, x1):
        ze = z_ridge - abs(x_ridge - xe) * slope
        pitch(P, (xe, y0 - over_y, ze), (xe, y1 + over_y, ze), (x_ridge, y0 - over_y, z_ridge), (x_ridge, y1 + over_y, z_ridge), t)
        for ye in (y0 - over_y - 0.05, y1 + over_y + 0.05):
            P.beam((xe, ye, ze + 0.1), (x_ridge, ye, z_ridge + 0.12), 0.08, 0.4, "oak", "frame", up=(0, 1, 0))
    P.beam((x_ridge, y0 - over_y - 0.1, z_ridge + 0.25), (x_ridge, y1 + over_y + 0.1, z_ridge + 0.25), 0.22, 0.2, "oak", "frame")
    for ye in (y0 - over_y - 0.05, y1 + over_y + 0.05):
        for sx in (-1, 1):
            P.beam((x_ridge, ye, z_ridge + 0.1), (x_ridge + sx * 0.55, ye, z_ridge + 0.85), 0.08, 0.16, "oak", "frame")


def sill_along_x(P, x0, x1, y_out, y_in, floor, r):
    """Under the first log of a gable wall that runs along x (it starts half a log higher)."""
    first = floor - 0.05 + r + r * 0.93
    P.box((x0, min(y_out, y_in), floor - 0.12), (x1, max(y_out, y_in), first - r * 0.3), "oak", "shell")


def gabled_porch(P, xc, y_wall, floor, z_top, width=3.2, depth=1.6, n_steps=6):
    """A landing at the floor in front of a door on a front wall (y_wall, outside -y), two posts, a
    small gable with a board face, and stairs down to the ground with a rail each side. The stairs
    mesh is `entry_step` (walked on the closed-house wedge)."""
    PY = y_wall - depth
    hw = width * 0.5
    P.box((xc - hw, PY, -0.4), (xc + hw, y_wall - 0.05, floor), "stone", "foundation")
    P.box((xc - hw + 0.05, PY + 0.02, floor - 0.06), (xc + hw - 0.05, y_wall, floor), "oak", "floor", "porch")
    for px in (xc - hw + 0.2, xc + hw - 0.2):
        P.box((px - 0.12, PY + 0.05, floor), (px + 0.12, PY + 0.29, floor + 2.3), "oak", "frame", "porch")
        P.beam((px, PY + 0.17, floor + 2.3), (px, y_wall, floor + 2.3), 0.14, 0.18, "oak", "frame", "porch")
    for sx in (-1, 1):
        pitch(P, (xc + sx * (hw + 0.2), PY - 0.3, floor + 2.3), (xc + sx * (hw + 0.2), y_wall, floor + 2.3), (xc, PY - 0.3, z_top), (xc, y_wall, z_top), 0.12)
        P.beam((xc + sx * (hw + 0.25), PY - 0.33, floor + 2.32), (xc, PY - 0.33, z_top + 0.1), 0.07, 0.3, "oak", "frame", "porch", up=(0, 1, 0))
    P.poly([(xc - hw - 0.15, PY - 0.2, floor + 2.35), (xc + hw + 0.15, PY - 0.2, floor + 2.35), (xc, PY - 0.2, z_top - 0.08),
            (xc - hw - 0.15, PY - 0.12, floor + 2.35), (xc + hw + 0.15, PY - 0.12, floor + 2.35), (xc, PY - 0.12, z_top - 0.08)],
           [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)], "oak", "frame", "porch")
    for i in range(n_steps):
        z = floor * (n_steps - i) / n_steps
        P.box((xc - 1.0, PY - 0.3 * (i + 1), -0.4), (xc + 1.0, PY - 0.3 * i, z), "oak", "floor", "entry_step")
    for sx in (-1, 1):
        P.beam((xc + sx * 1.15, PY - 0.3 * n_steps, 0.9), (xc + sx * 1.15, PY, floor + 0.9), 0.08, 0.08, "oak", "frame", "railing")
        P.box((xc + sx * 1.15 - 0.06, PY - 0.3 * n_steps - 0.06, -0.3), (xc + sx * 1.15 + 0.06, PY - 0.3 * n_steps + 0.06, 0.9), "oak", "frame", "railing")


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
    # Six 0.3 m treads: 1.0 m over 1.8 m, walkable on the entry wedge (four were 49 deg - too steep).
    N = 6
    for i in range(N):
        z = FLOOR * (N - i) / N
        P.box((-1.1, PY - 0.3 * (i + 1), -0.4), (1.1, PY - 0.3 * i, z), "oak", "floor", "entry_step")
    for sx in (-1, 1):
        P.beam((sx * 1.25, PY - 0.3 * N, 0.9), (sx * 1.25, PY, FLOOR + 0.9), 0.08, 0.08, "oak", "frame", "railing")
        P.box((sx * 1.25 - 0.06, PY - 0.3 * N - 0.06, -0.3), (sx * 1.25 + 0.06, PY - 0.3 * N + 0.06, 0.9), "oak", "frame", "railing")

    # The roof: the front pitch reaches out over the gallery.
    roof_two_pitch(P, -HX, HX, GY - 0.4, Y1 + 0.7, YR, RIDGE, SLOPE)
    chimney(P, 2.6, Y1 - 2.0, FLOOR + 0.5, RIDGE + 0.9)

    P.emit(None, f"{bid}_")
    # The closed-house entry walks the stairs on a smooth wedge (closed_house_entry.gd).
    bpy.data.objects[f"{bid}_entry_step"]["item_id"] = "entry_steps"
    door(P, bid, -0.6, 0.6, Y0 + 0.08, FLOOR, FLOOR + 2.15, mats)
    return {"id": bid, "slug": "t1", "floor": FLOOR}


# ------------------------------------------------------------------------------------------- T2
def terem_t2(mats):
    """T2 (14 x 11): an asymmetric tall house - a two-storey block with a lived-in attic under a steep
    roof whose gable faces the street, and a low one-storey wing along its right side under its own
    roof; the entry porch in front of the wing, by the corner. Two chimneys."""
    bid = "T2"
    P = Parts(mats, bid)
    R = 0.16
    FLOOR = 1.0
    # The tall block: x -7..0, y -2.5..5.5; gables on the front (-y) and the back.
    MX0, MX1, MY0, MY1 = -7.0, 0.0, -2.5, 5.5
    UPPER, EAVE, SLOPE = 3.95, 6.7, 1.15
    MXR = (MX0 + MX1) * 0.5
    RIDGE = EAVE + (MX1 - MXR) * SLOPE
    # The wing: x 0..7, y -1..5.5, one storey, its ridge along x.
    WX1, WY0, WY1 = 7.0, -1.0, 5.5
    WEAVE, WSLOPE = 3.9, 0.8
    WYR = (WY0 + WY1) * 0.5
    WRIDGE = WEAVE + (WY1 - WYR) * WSLOPE

    plinth(P, MX0 - 0.2, MX1, MY0 - 0.2, MY1 + 0.2, FLOOR - 0.12)
    plinth(P, MX1, WX1 + 0.2, WY0 - 0.2, WY1 + 0.2, FLOOR - 0.12)
    P.box((MX0, MY0 + 0.2, FLOOR - 0.12), (MX1, MY1 - 0.2, FLOOR), "oak", "floor")
    P.box((MX1, WY0 + 0.2, FLOOR - 0.12), (WX1, WY1 - 0.2, FLOOR), "oak", "floor")

    # The tall block: gable walls front and back (half a log higher, with sills), full side walls.
    gab = (RIDGE - 0.1, EAVE, (MX1 - MX0) * 0.5 + 0.1)
    front = shut_windows(P, "y", MY0, (-5.3, -1.7), FLOOR + 1.1, -1, R)
    front += shut_windows(P, "y", MY0, (-5.3, -1.7), UPPER + 0.9, -1, R)
    front += shut_windows(P, "y", MY0, (MXR,), EAVE + 0.9, -1, R, 0.7, 0.9)
    back = shut_windows(P, "y", MY1, (-5.0, -2.0), FLOOR + 1.1, 1, R)
    back += shut_windows(P, "y", MY1, (-5.0, -2.0), UPPER + 0.9, 1, R)
    back += shut_windows(P, "y", MY1, (MXR,), EAVE + 0.9, 1, R, 0.7, 0.9)
    left = shut_windows(P, "x", MX0, (-0.5, 2.5), FLOOR + 1.1, -1, R)
    left += shut_windows(P, "x", MX0, (-0.5, 2.5), UPPER + 0.9, -1, R)
    right = shut_windows(P, "x", MX1, (-1.8,), UPPER + 0.9, 1, R)
    log_wall(P, "x", MY0 + R, MX0 - 0.35, MX1 + 0.35, FLOOR - 0.05, RIDGE, R, front, R * 0.93, "gable", gab)
    log_wall(P, "x", MY1 - R, MX0 - 0.35, MX1 + 0.35, FLOOR - 0.05, RIDGE, R, back, R * 0.93, "gable", gab)
    sill_along_x(P, MX0, MX1, MY0, MY0 + 2 * R, FLOOR, R)
    sill_along_x(P, MX0, MX1, MY1, MY1 - 2 * R, FLOOR, R)
    log_wall(P, "y", MX0 + R, MY0 - 0.35, MY1 + 0.35, FLOOR - 0.05, EAVE, R, left, 0.0)
    log_wall(P, "y", MX1 - R, MY0 - 0.35, MY1 + 0.35, FLOOR - 0.05, EAVE, R, right, 0.0)
    band(P, MX0, MX1, MY0, MY1, UPPER)
    roof_ridge_y(P, MX0 - 0.6, MX1 + 0.6, MY0, MY1, MXR, RIDGE, SLOPE, 0.6)
    chimney(P, -2.2, 3.4, FLOOR + 0.5, RIDGE + 0.2)

    # The wing: front and back walls along x from the block's wall, a gable at x = 7.
    wfront = shut_windows(P, "y", WY0, (4.2, 6.0), FLOOR + 1.1, -1, R)
    wfront += [(1.0, 2.2, FLOOR, FLOOR + 2.2)]
    wback = shut_windows(P, "y", WY1, (2.2, 5.2), FLOOR + 1.1, 1, R)
    wright = shut_windows(P, "x", WX1, (0.8, 3.7), FLOOR + 1.1, 1, R)
    wright += shut_windows(P, "x", WX1, (WYR,), WEAVE + 0.7, 1, R, 0.6, 0.7)
    log_wall(P, "x", WY0 + R, MX1, WX1 + 0.35, FLOOR - 0.05, WEAVE, R, wfront, 0.0)
    log_wall(P, "x", WY1 - R, MX1, WX1 + 0.35, FLOOR - 0.05, WEAVE, R, wback, 0.0)
    gable_wall(P, WX1, WY0 - 0.35, WY1 + 0.35, FLOOR - 0.05, WRIDGE - 0.1, WEAVE, WYR, R, wright, -1)
    gable_sill(P, WX1, WX1 - 2 * R, WY0, WY1, FLOOR, R)
    roof_two_pitch(P, MX1, WX1, WY0 - 0.6, WY1 + 0.6, WYR, WRIDGE, WSLOPE, 0.6, over_x0=0.0, carve=(False, True))
    chimney(P, 4.8, 3.6, FLOOR + 0.5, WRIDGE + 0.8)

    # The entry: a door in the wing's front by the corner, its frame, a gabled porch and stairs.
    for a in (0.85, 2.2):
        P.box((a, WY0 - 0.12, FLOOR), (a + 0.15, WY0 + 0.1, FLOOR + 2.2), "oak", "frame")
    P.box((0.8, WY0 - 0.14, FLOOR + 2.2), (2.4, WY0 + 0.1, FLOOR + 2.4), "oak", "frame")
    gabled_porch(P, 1.6, WY0, FLOOR, FLOOR + 3.4, width=2.8)

    P.emit(None, f"{bid}_")
    bpy.data.objects[f"{bid}_entry_step"]["item_id"] = "entry_steps"
    door(P, bid, 1.0, 2.2, WY0 + 0.08, FLOOR, FLOOR + 2.15, mats)
    return {"id": bid, "slug": "t2", "floor": FLOOR}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--asset", default="all")
    args = ap.parse_args(argv)
    for bid, build in {"T1": terem_t1, "T2": terem_t2}.items():
        if args.asset not in ("all", bid):
            continue
        C.reset()
        mats = make_materials(Path(__file__).resolve().parent / "forest-city-v1" / "textures")
        info = build(mats)
        bpy.context.view_layer.update()
        export(info)


if __name__ == "__main__":
    main()
