"""FOREST-CITY-01 step 2: the town hall (R01, 24 x 12) and the militia barracks (K01, 20 x 10) as their
own models after Codex's civic sheet (local/previews/forest-city-art-01/civic-concept-v1.png, owner-
approved): dark log walls on a high rough stone plinth, a steep shingled roof, the hall's gallery on
carved posts with a gabled porch over wide steps, the barracks' shield canopy and door porch.

Same frame and helpers as water_workshops.py: x along the front, the entry faces -y (Godot +z),
z = 0 the ground at the entry, the floor on the plinth.

blender --background --factory-startup --python art/blender/forest_city_halls.py -- --asset all
"""
import argparse, math, sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import buildings_common as C
from forest_village_materials import make_materials
from water_workshops import OUT, Parts, door, export, log_wall

BOX_FACES = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]


def pitch(P, e0, e1, h0, h1, t=0.18, mat="roof", role="roof"):
    """A shingled roof pitch between the eave edge e0-e1 and the high edge h0-h1: a deck and
    overlapping courses whose butts stand proud (the stepped edge reads in silhouette)."""
    e0, e1, h0, h1 = map(Vector, (e0, e1, h0, h1))
    fall = e0 - h0
    up = Vector((0, 0, 1))
    P.poly([e0, h0, h1, e1] + [v + up * t * 0.5 for v in (e0, h0, h1, e1)], BOX_FACES, mat, role, grain=fall)
    rows = max(3, int(fall.length / 0.45))
    for r in range(rows):
        a, b = r / rows, min(1.0, (r + 1) / rows + 0.04)
        la0, la1 = e0 + (h0 - e0) * a, e1 + (h1 - e1) * a
        lb0, lb1 = e0 + (h0 - e0) * b, e1 + (h1 - e1) * b
        lift_a, lift_b = up * (t * 0.5 + 0.04), up * (t * 0.5 + 0.01)
        v = [la0 + lift_a, lb0 + lift_b, lb1 + lift_b, la1 + lift_a]
        v += [x + up * 0.05 for x in v]
        P.poly(v, BOX_FACES, mat, role, grain=fall)


def gable_roof(P, x0, x1, y0, y1, z_eave, z_ridge, over=0.7, t=0.2):
    """A roof with the ridge along x over y0..y1, eaves `over` beyond the walls, carved barge boards."""
    ym = (y0 + y1) * 0.5
    half = (y1 - y0) * 0.5
    slope = (z_ridge - z_eave) / half
    ze = z_eave - over * slope
    for sy, ye in ((-1, y0 - over), (1, y1 + over)):
        pitch(P, (x0 - over, ye, ze), (x1 + over, ye, ze), (x0 - over, ym, z_ridge), (x1 + over, ym, z_ridge), t)
        for xe in (x0 - over - 0.05, x1 + over + 0.05):
            P.beam((xe, ye, ze + 0.1), (xe, ym, z_ridge + 0.12), 0.08, 0.4, "oak", "frame", up=(1, 0, 0))
    P.beam((x0 - over - 0.1, ym, z_ridge + 0.25), (x1 + over + 0.1, ym, z_ridge + 0.25), 0.22, 0.2, "oak", "frame")
    # Crossed finials (the horse-head ends of the barge boards) over both gables.
    for xe in (x0 - over - 0.05, x1 + over + 0.05):
        for s in (-1, 1):
            P.beam((xe, ym, z_ridge + 0.1), (xe, ym + s * 0.55, z_ridge + 0.85), 0.08, 0.16, "oak", "frame")
    return ze


def plinth(P, x0, x1, y0, y1, top, bottom=-1.2):
    """A rough stone plinth with a projecting course of big stones along its foot."""
    P.box((x0, y0, bottom), (x1, y1, top), "stone", "foundation")
    P.box((x0 - 0.12, y0 - 0.12, bottom), (x1 + 0.12, y1 + 0.12, min(top - 0.25, 0.25)), "stone", "foundation")


def steps(P, cx, width, y_top, floor, n, depth=0.34, mat="stone", role="foundation"):
    for i in range(n):
        top = floor * (n - i) / n
        y = y_top - depth * i
        P.box((cx - width * 0.5 - 0.06 * i, y - depth, -0.4), (cx + width * 0.5 + 0.06 * i, y, top), mat, role)


def window(P, face, along, z0, w=0.8, h=0.8, x=None, y=None, out=-1):
    """Frame, sill, lit pane and a pair of open shutters on a wall facing -y/+y (face 'y') or -x/+x."""
    a0, a1 = along - w * 0.5, along + w * 0.5
    if face == "y":
        yy = y + out * 0.18
        P.box((a0 - 0.1, yy - 0.06, z0 - 0.12), (a1 + 0.1, yy + 0.06, z0), "oak", "frame")
        P.box((a0 - 0.12, yy - 0.07, z0 + h), (a1 + 0.12, yy + 0.07, z0 + h + 0.16), "oak", "frame")
        P.box((a0, y - 0.02, z0), (a1, y + 0.02, z0 + h), "cloth", "window")
        for s0, s1 in ((a0 - w * 0.5 - 0.02, a0 - 0.02), (a1 + 0.02, a1 + w * 0.5 + 0.02)):
            P.box((s0, yy - 0.03, z0), (s1, yy + 0.03, z0 + h), "oak", "shutter")
    else:
        xx = x + out * 0.18
        P.box((xx - 0.06, a0 - 0.1, z0 - 0.12), (xx + 0.06, a1 + 0.1, z0), "oak", "frame")
        P.box((xx - 0.07, a0 - 0.12, z0 + h), (xx + 0.07, a1 + 0.12, z0 + h + 0.16), "oak", "frame")
        P.box((x - 0.02, a0, z0), (x + 0.02, a1, z0 + h), "cloth", "window")
        for s0, s1 in ((a0 - w * 0.5 - 0.02, a0 - 0.02), (a1 + 0.02, a1 + w * 0.5 + 0.02)):
            P.box((xx - 0.03, s0, z0), (xx + 0.03, s1, z0 + h), "oak", "shutter")


def lit_windows(P, face, fixed, alongs, z0, out, R, w=0.8, h=0.8):
    """Window dressings and the wall openings (for log_wall) at the given positions."""
    opens = []
    for a in alongs:
        window(P, face, a, z0, w, h, x=fixed if face == "x" else None, y=fixed if face == "y" else None, out=out)
        opens.append((a - w * 0.5, a + w * 0.5, z0, z0 + h))
    return opens


def chimney(P, x, y, z0, z1):
    P.box((x - 0.4, y - 0.4, z0), (x + 0.4, y + 0.4, z1), "stone", "chimney")
    P.box((x - 0.5, y - 0.5, z1), (x + 0.5, y + 0.5, z1 + 0.15), "stone", "chimney")


def vent(P, x, y, z, s=1.2):
    """A little gabled smoke vent (dymnik) on the ridge."""
    P.box((x - s * 0.5, y - s * 0.5, z - 0.3), (x + s * 0.5, y + s * 0.5, z + 0.7), "oak", "frame")
    pitch(P, (x - s * 0.7, y - s * 0.75, z + 0.65), (x + s * 0.7, y - s * 0.75, z + 0.65), (x - s * 0.7, y, z + 1.25), (x + s * 0.7, y, z + 1.25), 0.1)
    pitch(P, (x - s * 0.7, y + s * 0.75, z + 0.65), (x + s * 0.7, y + s * 0.75, z + 0.65), (x - s * 0.7, y, z + 1.25), (x + s * 0.7, y, z + 1.25), 0.1)


def carved_frieze(P, x0, x1, y, z0, h=0.45):
    """A carved board: a plank with a running row of small rosettes proud of it."""
    P.box((x0, y - 0.05, z0), (x1, y + 0.05, z0 + h), "oak", "frame", "carving")
    n = max(2, int((x1 - x0) / 0.35))
    for i in range(n):
        cx = x0 + (i + 0.5) * (x1 - x0) / n
        P.cyl((cx, y - 0.05, z0 + h * 0.5), (cx, y - 0.11, z0 + h * 0.5), h * 0.3, "oak", "frame", "carving", seg=6)


def bench(P, x0, x1, y, h=0.45, d=0.35):
    P.box((x0, y - d * 0.5, h - 0.06), (x1, y + d * 0.5, h), "oak", "furniture", "bench")
    for x in (x0 + 0.15, x1 - 0.15):
        P.box((x - 0.05, y - d * 0.4, 0), (x + 0.05, y + d * 0.4, h - 0.06), "oak", "furniture", "bench")


def table(P, x0, x1, y0, y1, h=0.78):
    P.box((x0, y0, h - 0.07), (x1, y1, h), "oak", "furniture", "table")
    for x in (x0 + 0.2, x1 - 0.2):
        P.box((x - 0.07, y0 + 0.1, 0), (x + 0.07, y1 - 0.1, h - 0.07), "oak", "furniture", "table")


class Lifted:
    """Wraps Parts so that interior furniture is written relative to the floor."""

    def __init__(self, P, dz):
        self.P, self.dz = P, dz

    def box(self, lo, hi, *a, **k):
        self.P.box((lo[0], lo[1], lo[2] + self.dz), (hi[0], hi[1], hi[2] + self.dz), *a, **k)

    def cyl(self, a, b, *r, **k):
        self.P.cyl((a[0], a[1], a[2] + self.dz), (b[0], b[1], b[2] + self.dz), *r, **k)

    def beam(self, a, b, *r, **k):
        self.P.beam((a[0], a[1], a[2] + self.dz), (b[0], b[1], b[2] + self.dz), *r, **k)


# ------------------------------------------------------------------------------------ town hall
def town_hall(mats):
    """R01: a long one-storey hall under a steep roof with two smoke vents; along the front a gallery
    on carved posts, its middle bay a gabled porch over wide stone steps to the door."""
    bid = "R01"
    P = Parts(mats, bid)
    HX = 12.0
    Y0, Y1 = -3.6, 6.0          # the body; the gallery is -6 .. Y0
    GY = -6.0
    FLOOR, EAVE, RIDGE, R = 1.0, 5.0, 9.8, 0.16
    ym = (Y0 + Y1) * 0.5

    plinth(P, -HX - 0.2, HX + 0.2, GY - 0.1, Y1 + 0.2, FLOOR - 0.12)
    P.box((-HX, Y0 + 0.2, FLOOR - 0.12), (HX, Y1 - 0.2, FLOOR), "oak", "floor")
    P.box((-HX - 0.1, GY, FLOOR - 0.12), (HX + 0.1, Y0 + 0.2, FLOOR), "oak", "floor")
    steps(P, 0.0, 3.4, GY - 0.1, FLOOR, 6, 0.3)

    # Walls. Front: the door in the middle, six windows; rear: six; the gables two each and one high.
    front = lit_windows(P, "y", Y0, (-9.5, -6.5, -3.5, 3.5, 6.5, 9.5), FLOOR + 1.3, -1, R)
    front.append((-1.1, 1.1, FLOOR, FLOOR + 2.7))
    rear = lit_windows(P, "y", Y1, (-9.0, -5.0, -1.5, 1.5, 5.0, 9.0), FLOOR + 1.3, 1, R)
    left = lit_windows(P, "x", -HX, (ym - 2.2, ym + 2.2), FLOOR + 1.3, -1, R)
    left += lit_windows(P, "x", -HX, (ym,), EAVE + 1.0, -1, R, 0.7, 0.9)
    right = lit_windows(P, "x", HX, (ym - 2.2, ym + 2.2), FLOOR + 1.3, 1, R)
    right += lit_windows(P, "x", HX, (ym,), EAVE + 1.0, 1, R, 0.7, 0.9)
    log_wall(P, "x", Y0 + R, -HX - 0.35, HX + 0.35, FLOOR - 0.05, EAVE, R, front, 0.0)
    log_wall(P, "x", Y1 - R, -HX - 0.35, HX + 0.35, FLOOR - 0.05, EAVE, R, rear, 0.0)
    gab = (RIDGE - 0.1, EAVE, (Y1 - Y0) * 0.5 + 0.1)
    log_wall(P, "y", -HX + R, Y0 - 0.35, Y1 + 0.35, FLOOR - 0.05, RIDGE, R, left, R * 0.93, "gable", gab)
    log_wall(P, "y", HX - R, Y0 - 0.35, Y1 + 0.35, FLOOR - 0.05, RIDGE, R, right, R * 0.93, "gable", gab)
    # The door frame with a carved lintel board.
    for a in (-1.25, 1.1):
        P.box((a, Y0 - 0.12, FLOOR), (a + 0.15, Y0 + 0.1, FLOOR + 2.7), "oak", "frame")
    carved_frieze(P, -1.5, 1.5, Y0 - 0.14, FLOOR + 2.72, 0.4)

    # The main roof, smoke vents, chimneys.
    gable_roof(P, -HX, HX, Y0, Y1, EAVE, RIDGE, over=0.8)
    for vx in (-5.0, 5.0):
        vent(P, vx, ym, RIDGE)
    chimney(P, -HX + 1.2, Y1 - 1.6, FLOOR, RIDGE - 0.4)

    # The gallery: posts with brackets, a railing, a lean-to roof from the wall.
    # Every 2.34 m along the front, the middle one left out: the porch bay stays open over the steps.
    posts = [x for x in (-11.7 + 2.34 * i for i in range(11)) if abs(x) > 1.5]
    for px in posts:
        P.box((px - 0.15, GY + 0.15, FLOOR), (px + 0.15, GY + 0.45, FLOOR + 3.1), "oak", "frame", "gallery")
        P.cyl((px, GY + 0.3, FLOOR + 1.2), (px, GY + 0.3, FLOOR + 1.7), 0.2, "oak", "frame", "gallery", seg=8)
        for s in (-1, 1):
            if abs(px + s * 0.8) < HX:
                P.beam((px, GY + 0.3, FLOOR + 2.4), (px + s * 0.8, GY + 0.3, FLOOR + 3.05), 0.12, 0.12, "oak", "frame", "gallery")
    P.box((-HX - 0.1, GY + 0.12, FLOOR + 3.05), (HX + 0.1, GY + 0.48, FLOOR + 3.3), "oak", "frame", "gallery")
    for i in range(len(posts) - 1):
        a, b = posts[i] + 0.15, posts[i + 1] - 0.15
        if a < 0 < b:
            continue            # the porch bay stays open to the steps
        for z in (FLOOR + 0.45, FLOOR + 0.95):
            P.box((a, GY + 0.22, z), (b, GY + 0.38, z + 0.1), "oak", "frame", "railing")
        for k in range(1, 5):
            x = a + (b - a) * k / 5
            P.box((x - 0.04, GY + 0.26, FLOOR), (x + 0.04, GY + 0.34, FLOOR + 0.95), "oak", "frame", "railing")
    pitch(P, (-HX - 0.3, GY - 0.35, FLOOR + 3.2), (HX + 0.3, GY - 0.35, FLOOR + 3.2), (-HX - 0.3, Y0, EAVE - 0.45), (HX + 0.3, Y0, EAVE - 0.45), 0.14)

    # The porch gable over the steps: two posts out front, a steep little roof, a carved face.
    PY = GY - 1.9
    for px in (-1.9, 1.9):
        P.box((px - 0.17, PY - 0.17, -0.3), (px + 0.17, PY + 0.17, FLOOR + 3.6), "oak", "frame", "porch")
        P.cyl((px, PY, FLOOR + 1.4), (px, PY, FLOOR + 2.0), 0.24, "oak", "frame", "porch", seg=8)
        P.beam((px, PY - 0.2, FLOOR + 3.65), (px, Y0, FLOOR + 3.65), 0.18, 0.22, "oak", "frame", "porch")
    P.beam((-2.2, PY, FLOOR + 3.65), (2.2, PY, FLOOR + 3.65), 0.2, 0.24, "oak", "frame", "porch")
    top = FLOOR + 5.4
    for sx in (-1, 1):
        pitch(P, (sx * 2.6, PY - 0.5, FLOOR + 3.7), (sx * 2.6, Y0 - 0.2, FLOOR + 3.7), (0, PY - 0.5, top), (0, Y0 - 0.2, top), 0.14)
        P.beam((sx * 2.65, PY - 0.55, FLOOR + 3.75), (0, PY - 0.55, top + 0.12), 0.08, 0.4, "oak", "frame", "porch", up=(0, 1, 0))
    P.poly([(-2.2, PY - 0.3, FLOOR + 3.8), (2.2, PY - 0.3, FLOOR + 3.8), (0, PY - 0.3, top - 0.1),
            (-2.2, PY - 0.2, FLOOR + 3.8), (2.2, PY - 0.2, FLOOR + 3.8), (0, PY - 0.2, top - 0.1)],
           [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)], "oak", "gable", grain=(0, 0, 1))
    carved_frieze(P, -2.0, 2.0, PY - 0.36, FLOOR + 3.85, 0.45)
    P.cyl((0, PY - 0.36, FLOOR + 4.7), (0, PY - 0.45, FLOOR + 4.7), 0.3, "oak", "frame", "carving", seg=8)

    # Inside: the long council table and benches, the elder's seat on a dais, the hearth, chests.
    F = Lifted(P, FLOOR)
    table(F, -6.0, 6.0, 1.5, 2.7)
    bench(F, -6.0, 6.0, 1.0)
    bench(F, -6.0, 6.0, 3.2)
    F.box((8.5, -0.5, 0), (11.6, 4.5, 0.3), "oak", "furniture", "dais")
    F.box((9.8, 1.4, 0.3), (10.8, 2.4, 0.8), "oak", "furniture", "seat")
    F.box((10.6, 1.4, 0.8), (10.8, 2.4, 2.2), "oak", "furniture", "seat")
    for dy in (1.4, 2.3):
        F.box((9.8, dy, 0.8), (10.8, dy + 0.1, 1.2), "oak", "furniture", "seat")
    F.box((-HX + 0.3, Y1 - 2.6, 0), (-HX + 1.8, Y1 - 0.6, 1.3), "stone", "furniture", "hearth")
    F.box((-HX + 0.3, Y1 - 2.4, 1.3), (-HX + 1.2, Y1 - 0.8, 2.6), "stone", "furniture", "hearth")
    for x in (-8.5, 4.0, 7.2):
        F.box((x, Y1 - 0.95, 0), (x + 1.1, Y1 - 0.35, 0.6), "oak", "furniture", "chest")
    for x in (-8.0, -3.0, 3.0, 8.0):
        F.box((x - 0.45, Y1 - 0.34, 1.6), (x + 0.45, Y1 - 0.3, 3.0), "cloth", "furniture", "banner")

    P.emit(None, f"{bid}_")
    door(P, bid, -1.1, 1.1, Y0 + 0.08, FLOOR, FLOOR + 2.6, mats)
    return {"id": bid, "slug": "r01", "floor": FLOOR}


# ------------------------------------------------------------------------------------- barracks
def barracks(mats):
    """K01: a plain long log house on a stone plinth; along the front a lean-to canopy over the shield
    rack and benches, the door right of middle under its own little gable, bunks inside."""
    bid = "K01"
    P = Parts(mats, bid)
    HX, Y0, Y1 = 10.0, -5.0, 5.0
    FLOOR, EAVE, RIDGE, R = 0.8, 4.4, 8.3, 0.155
    DX = 2.5
    ym = 0.0

    plinth(P, -HX - 0.2, HX + 0.2, Y0 - 0.2, Y1 + 0.2, FLOOR - 0.12)
    P.box((-HX, Y0 + 0.2, FLOOR - 0.12), (HX, Y1 - 0.2, FLOOR), "oak", "floor")
    steps(P, DX, 1.9, Y0 - 0.2, FLOOR, 5, 0.3)

    front = lit_windows(P, "y", Y0, (-8.2, -5.8, -3.4, -1.0, 5.2, 8.0), FLOOR + 1.35, -1, R, 0.7, 0.7)
    front.append((DX - 0.8, DX + 0.8, FLOOR, FLOOR + 2.4))
    rear = lit_windows(P, "y", Y1, (-7.5, -4.0, -0.5, 3.0, 6.5), FLOOR + 1.35, 1, R, 0.7, 0.7)
    left = lit_windows(P, "x", -HX, (ym,), EAVE + 0.8, -1, R, 0.7, 0.8)
    right = lit_windows(P, "x", HX, (-2.0, 2.0), FLOOR + 1.35, 1, R, 0.7, 0.7)
    right += lit_windows(P, "x", HX, (ym,), EAVE + 0.8, 1, R, 0.7, 0.8)
    log_wall(P, "x", Y0 + R, -HX - 0.35, HX + 0.35, FLOOR - 0.05, EAVE, R, front, 0.0)
    log_wall(P, "x", Y1 - R, -HX - 0.35, HX + 0.35, FLOOR - 0.05, EAVE, R, rear, 0.0)
    gab = (RIDGE - 0.1, EAVE, (Y1 - Y0) * 0.5 + 0.1)
    log_wall(P, "y", -HX + R, Y0 - 0.35, Y1 + 0.35, FLOOR - 0.05, RIDGE, R, left, R * 0.93, "gable", gab)
    log_wall(P, "y", HX - R, Y0 - 0.35, Y1 + 0.35, FLOOR - 0.05, RIDGE, R, right, R * 0.93, "gable", gab)
    for a in (DX - 0.95, DX + 0.8):
        P.box((a, Y0 - 0.12, FLOOR), (a + 0.15, Y0 + 0.1, FLOOR + 2.4), "oak", "frame")
    P.box((DX - 1.1, Y0 - 0.14, FLOOR + 2.4), (DX + 1.1, Y0 + 0.1, FLOOR + 2.6), "oak", "frame")

    gable_roof(P, -HX, HX, Y0, Y1, EAVE, RIDGE, over=0.7)
    chimney(P, -HX + 1.0, 1.8, FLOOR, RIDGE - 0.2)

    # The shield canopy along the left of the front: posts, a lean-to, the rack of round shields.
    CX0, CX1, CY = -9.4, 0.4, Y0 - 2.0
    for px in (CX0, CX0 + 2.45, CX0 + 4.9, CX0 + 7.35, CX1):
        P.box((px - 0.13, CY - 0.13, -0.3), (px + 0.13, CY + 0.13, FLOOR + 2.55), "oak", "frame", "canopy")
        P.beam((px, CY, FLOOR + 2.0), (px, CY + 0.7, FLOOR + 2.55), 0.1, 0.1, "oak", "frame", "canopy")
    P.box((CX0 - 0.2, CY - 0.15, FLOOR + 2.5), (CX1 + 0.2, CY + 0.15, FLOOR + 2.72), "oak", "frame", "canopy")
    pitch(P, (CX0 - 0.4, CY - 0.4, FLOOR + 2.65), (CX1 + 0.4, CY - 0.4, FLOOR + 2.65), (CX0 - 0.4, Y0, EAVE - 0.5), (CX1 + 0.4, Y0, EAVE - 0.5), 0.14)
    P.box((CX0, CY - 0.1, -0.2), (CX1, Y0 - 0.2, 0.25), "oak", "floor", "canopy_deck")
    P.box((CX0 + 0.3, Y0 - 0.35, FLOOR + 1.45), (CX1 - 0.3, Y0 - 0.25, FLOOR + 1.6), "oak", "frame", "rack")
    for i in range(9):
        x = CX0 + 0.9 + i * 1.05
        P.cyl((x, Y0 - 0.32, FLOOR + 1.15), (x, Y0 - 0.44, FLOOR + 1.15), 0.42, "cloth" if i % 2 else "oak", "furniture", "shield", seg=12)
        P.cyl((x, Y0 - 0.44, FLOOR + 1.15), (x, Y0 - 0.52, FLOOR + 1.15), 0.1, "iron", "furniture", "shield", seg=8)
    bench(Lifted(P, 0.25), CX0 + 0.5, CX0 + 3.2, CY + 0.6)

    # The door porch: two posts, a little gable.
    PY = Y0 - 1.9
    for px in (DX - 1.2, DX + 1.2):
        P.box((px - 0.13, PY - 0.13, -0.3), (px + 0.13, PY + 0.13, FLOOR + 2.6), "oak", "frame", "porch")
        P.beam((px, PY, FLOOR + 2.62), (px, Y0, FLOOR + 2.62), 0.14, 0.18, "oak", "frame", "porch")
    for sx in (-1, 1):
        pitch(P, (DX + sx * 1.6, PY - 0.4, FLOOR + 2.7), (DX + sx * 1.6, Y0 - 0.1, FLOOR + 2.7), (DX, PY - 0.4, FLOOR + 3.8), (DX, Y0 - 0.1, FLOOR + 3.8), 0.12)
    carved_frieze(P, DX - 1.3, DX + 1.3, PY - 0.2, FLOOR + 2.7, 0.3)

    # Inside: two-tier bunks along the rear, a table with benches, a spear rack, chests, the stove.
    F = Lifted(P, FLOOR)
    for bx in (-8.6, -5.4, -2.2, 1.0):
        for lz in (0.35, 1.45):
            F.box((bx, Y1 - 2.2, lz), (bx + 2.0, Y1 - 0.35, lz + 0.12), "oak", "furniture", "bunk")
            F.box((bx + 0.05, Y1 - 2.15, lz + 0.12), (bx + 1.95, Y1 - 0.4, lz + 0.26), "straw", "furniture", "bunk")
        for px in (bx, bx + 1.9):
            F.box((px, Y1 - 2.2, 0), (px + 0.1, Y1 - 2.1, 2.0), "oak", "furniture", "bunk")
    table(F, 3.0, 7.0, -1.2, 0.0)
    bench(F, 3.0, 7.0, -1.65)
    bench(F, 3.0, 7.0, 0.45)
    F.box((HX - 0.6, -4.0, 0.9), (HX - 0.4, -1.0, 1.05), "oak", "furniture", "rack")
    for i in range(7):
        y = -3.8 + i * 0.42
        F.cyl((HX - 0.5, y, 0.0), (HX - 0.5, y, 2.4), 0.03, "oak", "furniture", "spear", seg=5)
        F.cyl((HX - 0.5, y, 2.4), (HX - 0.5, y, 2.65), 0.05, "iron", "furniture", "spear", seg=4, r2=0.0)
    for x in (4.5, 6.2, 7.9):
        F.box((x, Y1 - 0.95, 0), (x + 1.0, Y1 - 0.35, 0.55), "oak", "furniture", "chest")
    F.box((-HX + 0.3, 0.9, 0), (-HX + 1.6, 2.7, 1.2), "stone", "furniture", "stove")

    P.emit(None, f"{bid}_")
    door(P, bid, DX - 0.8, DX + 0.8, Y0 + 0.08, FLOOR, FLOOR + 2.3, mats)
    return {"id": bid, "slug": "k01", "floor": FLOOR}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--asset", default="all")
    args = ap.parse_args(argv)
    for bid, build in {"R01": town_hall, "K01": barracks}.items():
        if args.asset not in ("all", bid):
            continue
        C.reset()
        mats = make_materials(OUT / "textures")
        info = build(mats)
        bpy.context.view_layer.update()
        export(info)


if __name__ == "__main__":
    main()
