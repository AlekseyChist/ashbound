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
from water_workshops import OUT, Parts, door, empty, export, log_wall

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


def window(P, face, along, z0, w=0.8, h=0.8, x=None, y=None, out=-1, r=0.16):
    """A window in a log wall whose outer face is at x/y (outside towards `out`, the wall 2r thick):
    a plank casing lining the whole cut through the wall - its head and sill blocks fill the courses
    log_wall takes out above and below the opening (up to 1.6 r past it), its jambs cover the cut log
    ends - an open light with a cross bar in the middle of the wall, a surround flush on the outer face
    and a pair of open shutters flat against the logs beside it (owner 29 Sep: no frames hanging in
    the air in ragged holes)."""
    a0, a1 = along - w * 0.5, along + w * 0.5
    face_at = x if face == "x" else y
    t = 2 * r
    lo, hi = z0 - 1.6 * r - 0.02, z0 + h + 1.6 * r + 0.02

    def box(d0, d1, b0, b1, z_0, z_1, mat, role):
        """d: depth outwards from the outer face (negative = into the wall), b: along the wall."""
        p0, p1 = sorted((face_at + out * d0, face_at + out * d1))
        if face == "y":
            P.box((b0, p0, z_0), (b1, p1, z_1), mat, role)
        else:
            P.box((p0, b0, z_0), (p1, b1, z_1), mat, role)

    # The casing through the wall: head, sill, jambs.
    box(-t - 0.01, 0.01, a0 - 0.05, a1 + 0.05, z0 + h, hi, "oak", "frame")
    box(-t - 0.01, 0.01, a0 - 0.05, a1 + 0.05, lo, z0, "oak", "frame")
    for b0, b1 in ((a0 - 0.05, a0), (a1, a1 + 0.05)):
        box(-t - 0.01, 0.01, b0, b1, z0, z0 + h, "oak", "frame")
    # Open, as the village houses' windows: no opaque pane (it read as a shut board), only a thin
    # cross bar in the middle of the wall - the light and the street show through.
    box(-r - 0.02, -r + 0.02, along - 0.025, along + 0.025, z0, z0 + h, "oak", "frame")
    box(-r - 0.02, -r + 0.02, a0, a1, z0 + h * 0.5 - 0.025, z0 + h * 0.5 + 0.025, "oak", "frame")
    # The surround on the outer face: a projecting sill, a head board, side boards.
    box(0.0, 0.08, a0 - 0.14, a1 + 0.14, z0 - 0.1, z0 + 0.02, "oak", "frame")
    box(0.0, 0.06, a0 - 0.16, a1 + 0.16, z0 + h - 0.02, z0 + h + 0.16, "oak", "frame")
    for b0, b1 in ((a0 - 0.12, a0 + 0.02), (a1 - 0.02, a1 + 0.12)):
        box(0.0, 0.04, b0, b1, z0, z0 + h, "oak", "frame")
    # Open shutters against the logs, just clear of the side boards.
    for s0, s1 in ((a0 - 0.13 - w * 0.5, a0 - 0.13), (a1 + 0.13, a1 + 0.13 + w * 0.5)):
        box(0.01, 0.05, s0, s1, z0, z0 + h, "oak", "shutter")


def lit_windows(P, face, fixed, alongs, z0, out, R, w=0.8, h=0.8):
    """Window dressings and the wall openings (for log_wall) at the given positions."""
    opens = []
    for a in alongs:
        window(P, face, a, z0, w, h, x=fixed if face == "x" else None, y=fixed if face == "y" else None, out=out, r=R)
        opens.append((a - w * 0.5, a + w * 0.5, z0, z0 + h))
    return opens


def gable_sill(P, x_out, x_in, y0, y1, floor, r):
    """A gable wall starts half a log higher than the long walls (the corner joint): a sill beam
    under its first log closes the slit that otherwise runs along the floor (owner 29 Sep)."""
    first = floor - 0.05 + r + r * 0.93
    P.box((min(x_out, x_in), y0, floor - 0.12), (max(x_out, x_in), y1, first - r * 0.3), "oak", "shell")


def roof_frame(P, x0, x1, y0, y1, eave, ridge, step=2.4, clear_x0=0.5):
    """The inside of the roof, as in the tavern: board lining under both pitches, trusses every `step`
    (a tie beam over the walls, a king post, two rafters, two struts) and an inner ridge beam - all of
    it under the roof plane, nothing through it."""
    ym = (y0 + y1) * 0.5
    half = (y1 - y0) * 0.5
    slope = (ridge - eave) / half
    for sy in (-1, 1):
        yw = y0 if sy < 0 else y1
        # Lining 4 cm under the deck, from the wall line to the ridge.
        v = [(x0, yw, eave - 0.04), (x0, ym, ridge - 0.04), (x1, ym, ridge - 0.04), (x1, yw, eave - 0.04)]
        v += [(x, y, z - 0.03) for x, y, z in v]
        P.poly(v, BOX_FACES, "oak", "lining", grain=(1, 0, 0))
    P.box((x0, ym - 0.13, ridge - 0.62), (x1, ym + 0.13, ridge - 0.34), "oak", "frame", "roof_frame")
    # clear_x0 keeps the first truss off the hearth's flue at the x0 end.
    n = max(1, int((x1 - x0 - clear_x0 - 0.5) / step))
    xs = []
    for i in range(n + 1):
        x = x0 + clear_x0 + (x1 - x0 - clear_x0 - 0.5) * i / n
        xs.append(x)
        P.box((x - 0.12, y0 + 0.05, eave - 0.3), (x + 0.12, y1 - 0.05, eave - 0.06), "oak", "frame", "roof_frame")
        P.box((x - 0.1, ym - 0.1, eave - 0.06), (x + 0.1, ym + 0.1, ridge - 0.62), "oak", "frame", "roof_frame")
        for sy in (-1, 1):
            yw = y0 if sy < 0 else y1
            # Rafter: its top 6 cm under the plane all along.
            a = (x, yw - sy * 0.15, eave + 0.15 * slope - 0.16)
            b = (x, ym - sy * 0.12, ridge - 0.2)
            P.beam(a, b, 0.14, 0.18, "oak", "frame", "roof_frame", up=(0, 0, 1))
            # Strut from the king post's foot to the rafter's middle.
            mid_y = ym - sy * half * 0.5
            P.beam((x, ym - sy * 0.1, eave + 0.2), (x, mid_y, eave + slope * half * 0.5 - 0.3), 0.1, 0.1, "oak", "frame", "roof_frame")
    return xs


def hearth(P, bid, x_wall, yc, floor, ridge, facing=1):
    """A stone hearth against a gable wall: base slab, cheeks and back round an open firebox, a
    stone lintel with an oak mantel shelf, the breast above narrowing into the flue up through the
    roof. The `<bid>_fire` marker sits on the logs in the firebox."""
    def X(d):
        return x_wall + facing * d
    def box(d0, d1, ya, yb, z0, z1, mat="stone", name="hearth"):
        P.box((min(X(d0), X(d1)), ya, z0), (max(X(d0), X(d1)), yb, z1), mat, "furniture", name)
    f = floor
    # d = 0 is 2 cm inside the wall's logs: the hearth stands against them, no slit behind it.
    box(0.0, 1.9, yc - 1.05, yc + 1.05, f, f + 0.32)
    box(0.0, 1.55, yc - 1.0, yc - 0.68, f + 0.32, f + 1.3)
    box(0.0, 1.55, yc + 0.68, yc + 1.0, f + 0.32, f + 1.3)
    box(0.0, 0.5, yc - 0.68, yc + 0.68, f + 0.32, f + 1.3)
    box(0.0, 1.6, yc - 1.02, yc + 1.02, f + 1.3, f + 1.55)
    box(1.45, 1.75, yc - 1.15, yc + 1.15, f + 1.55, f + 1.65, "oak", "mantel")
    box(0.0, 1.35, yc - 0.85, yc + 0.85, f + 1.55, f + 2.4)
    box(0.25, 1.05, yc - 0.6, yc + 0.6, f + 2.4, ridge + 1.3, "stone", "flue")
    box(0.18, 1.12, yc - 0.67, yc + 0.67, ridge + 1.3, ridge + 1.45, "stone", "flue")
    for k, dy in enumerate((-0.25, 0.0, 0.25)):
        P.cyl((X(0.75), yc + dy - 0.05, f + 0.4 + 0.05 * k), (X(1.25), yc + dy + 0.05, f + 0.4 + 0.05 * k), 0.07, "oak", "furniture", "firewood", seg=6)
    empty(f"{bid}_fire", (X(1.0), yc, f + 0.4), "fire")
    # Firewood stacked beside the hearth.
    for k in range(4):
        P.cyl((X(0.3), yc + 1.2, f + 0.08 + 0.15 * k), (X(1.3), yc + 1.2, f + 0.08 + 0.15 * k), 0.07, "oak", "furniture", "firewood", seg=6)
        P.cyl((X(0.3), yc + 1.37, f + 0.08 + 0.15 * k), (X(1.3), yc + 1.37, f + 0.08 + 0.15 * k), 0.07, "oak", "furniture", "firewood", seg=6)


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


# --- CIVIC-FURNITURE-01 V1 (Codex sheets elder-chair-v1 / hall-furniture-v1, owner-approved 29 Sep):
# planed joinery of separate boards, built from the sheet's table of sizes, not from the picture.

def bench(P, x0, x1, y, h=0.45, d=0.38, module=2.4):
    """Modular benches: each module two seat boards along x on two splayed supports with a foot
    block, joined by a long stretcher."""
    n = max(1, round((x1 - x0) / module))
    m = (x1 - x0) / n
    for i in range(n):
        a = x0 + i * m
        for k in (0, 1):
            y0 = y - d * 0.5 + k * d * 0.5
            P.box((a + 0.005, y0 + 0.004, h - 0.05), (a + m - 0.005, y0 + d * 0.5 - 0.004, h), "oak", "furniture", "bench")
        for x in (a + 0.28, a + m - 0.28):
            P.box((x - 0.04, y - d * 0.42, h - 0.12), (x + 0.04, y + d * 0.42, h - 0.05), "oak", "furniture", "bench")
            for s in (-1, 1):
                P.beam((x, y + s * d * 0.28, h - 0.12), (x, y + s * d * 0.4, 0.06), 0.07, 0.06, "oak", "furniture", "bench")
            P.box((x - 0.045, y - d * 0.46, 0), (x + 0.045, y + d * 0.46, 0.06), "oak", "furniture", "bench")
        P.box((a + 0.24, y - 0.025, 0.16), (a + m - 0.24, y + 0.025, 0.22), "oak", "furniture", "bench")


def trestle_table(P, x0, x1, y0, y1, h=0.78, module=2.4):
    """Modular trestle tables: each module three boards along x (top 0.06), three A-trestles (a
    cross bearer, two splayed legs, a foot) and a long rail between them."""
    n = max(1, round((x1 - x0) / module))
    m = (x1 - x0) / n
    yc, w = (y0 + y1) * 0.5, y1 - y0
    for i in range(n):
        a = x0 + i * m
        for k in range(3):
            b0 = y0 + k * w / 3
            P.box((a + 0.004, b0 + 0.004, h - 0.06), (a + m - 0.004, b0 + w / 3 - 0.004, h), "oak", "furniture", "table")
        for x in (a + 0.3, a + m * 0.5, a + m - 0.3):
            P.box((x - 0.045, y0 + 0.08, h - 0.14), (x + 0.045, y1 - 0.08, h - 0.06), "oak", "furniture", "table")
            for s in (-1, 1):
                P.beam((x, yc + s * 0.22, h - 0.14), (x, yc + s * 0.44, 0.07), 0.08, 0.07, "oak", "furniture", "table")
            P.box((x - 0.05, y0 + 0.06, 0), (x + 0.05, y1 - 0.06, 0.07), "oak", "furniture", "table")
        P.box((a + 0.26, yc - 0.035, 0.26), (a + m - 0.26, yc + 0.035, 0.34), "oak", "furniture", "table")


def elder_chair(P, cx, cy, z, face=-1):
    """The elder's chair (sheet elder-chair-v1): 0.86 wide, 0.85 deep, 1.60 high, seat 0.48; front
    legs rise to the arms, back legs to the top as stiles, three back boards and a top rail, side
    and front rails, a board seat, a thin wool cushion, iron shoes. `face`: the side it looks to in x."""
    W, D, H, S = 0.86, 0.85, 1.60, 0.48
    xf, xb = cx + face * D * 0.5, cx - face * D * 0.5    # front and back edges in x
    def X(t):   # 0 at the front, 1 at the back
        return xf + (xb - xf) * t
    def box(t0, t1, ya, yb, z0, z1, mat="oak", name="chair"):
        P.box((min(X(t0), X(t1)), cy + ya, z + z0), (max(X(t0), X(t1)), cy + yb, z + z1), mat, "furniture", name)
    L = 0.09
    for ys in (-W * 0.5, W * 0.5 - L):
        box(0.0, L / D, ys, ys + L, 0.0, 0.72)                        # front legs up to the arms
        box(1.0 - L / D, 1.0, ys, ys + L, 0.0, H)                     # back legs as stiles
        box(0.0, 1.0, ys + 0.005, ys + L - 0.005, 0.12, 0.18)          # low side rail
        box(0.0, 1.0, ys + 0.01, ys + L - 0.01, S - 0.1, S - 0.04)     # seat side rail
        box(-0.04, 1.0 - L / D, ys - 0.02, ys + L + 0.02, 0.72, 0.77)  # arm
        for t in (0.0, 1.0 - L / D):                                   # iron shoes
            box(t - 0.005 / D, t + (L + 0.005) / D, ys - 0.005, ys + L + 0.005, 0.0, 0.07, "iron", "chair_iron")
    for t0, t1 in ((0.0, L / D), (1.0 - L / D, 1.0)):
        box(t0, t1, -W * 0.5 + L, W * 0.5 - L, S - 0.1, S - 0.04)      # front and back seat rails
    for k in range(4):
        y0 = -W * 0.5 + L + k * (W - 2 * L) / 4
        box(0.02, 1.0 - L / D, y0 + 0.004, y0 + (W - 2 * L) / 4 - 0.004, S - 0.04, S)  # seat boards
    box(0.06, 0.86, -W * 0.5 + L + 0.02, W * 0.5 - L - 0.02, S, S + 0.05, "cloth", "chair_cushion")
    for k in range(3):
        y0 = -W * 0.5 + L + k * (W - 2 * L) / 3
        box(1.0 - (L - 0.02) / D, 1.0 - 0.03 / D, y0 + 0.006, y0 + (W - 2 * L) / 3 - 0.006, S + 0.05, H - 0.2)
    box(1.0 - L / D, 1.0, -W * 0.5 + L, W * 0.5 - L, H - 0.2, H - 0.04)   # top rail
    for k in range(5):                                                    # its shallow notched carving
        y = -W * 0.5 + L + (k + 0.5) * (W - 2 * L) / 5
        box(1.0 - (L + 0.015) / D, 1.0 - L / D, y - 0.04, y + 0.04, H - 0.16, H - 0.08)


def dais(P, x0, x1, y0, y1, h, step=(1.2, 2.8), step_h=0.15, step_d=0.30):
    """The boarded dais (sheet elder-chair-v1): bearers under a deck of 0.18 m boards along y, board
    fascias on the front and ends, a half-height step cut into its front (x0) - nothing outside it."""
    for yb in (y0 + 0.1, (y0 + y1) * 0.5, y1 - 0.1):
        P.box((x0 + 0.05, yb - 0.06, 0), (x1, yb + 0.06, h - 0.04), "oak", "furniture", "dais")
    n = max(1, round((x1 - x0) / 0.18))
    for i in range(n):
        a = x0 + i * (x1 - x0) / n
        b = a + (x1 - x0) / n
        lo = a < x0 + step_d - 0.01
        for ya, yb in (((y0, step[0]), (step[1], y1)) if lo else ((y0, y1),)):
            P.box((a + 0.004, ya, h - 0.04), (b - 0.004, yb, h), "oak", "furniture", "dais")
    # Fascia: the front board broken by the step, the two ends.
    P.box((x0, y0, 0), (x0 + 0.03, step[0], h - 0.04), "oak", "furniture", "dais")
    P.box((x0, step[1], 0), (x0 + 0.03, y1, h - 0.04), "oak", "furniture", "dais")
    for ye in (y0, y1 - 0.03):
        P.box((x0, ye, 0), (x1, ye + 0.03, h - 0.04), "oak", "furniture", "dais")
    # The step: its tread and riser inside the dais, a board face up to the deck behind it.
    P.box((x0, step[0], 0), (x0 + step_d, step[1], step_h), "oak", "furniture", "dais")
    P.box((x0 + step_d - 0.03, step[0], step_h), (x0 + step_d, step[1], h - 0.04), "oak", "furniture", "dais")


def bunk(P, x0, y_wall, floor=0.0, L=2.0, W=0.95, H=2.05):
    """A two-tier militia bunk (sheet hall-furniture-v1) against the rear wall at y_wall: four posts,
    rails, board decks, straw mattresses to 0.48/1.58 m, a green blanket each, a guard rail on top and
    a ladder on the front at the x1 end."""
    y1 = y_wall
    y0 = y_wall - W
    x1 = x0 + L
    P_ = 0.08
    for x in (x0, x1 - P_):
        for y in (y0, y1 - P_):
            P.box((x, y, 0), (x + P_, y + P_, H), "oak", "furniture", "bunk")
    for deck in (0.30, 1.40):
        for y in (y0, y1 - 0.05):
            P.box((x0 + P_, y, deck), (x1 - P_, y + 0.05, deck + 0.1), "oak", "furniture", "bunk")
        for x in (x0 + P_, x1 - P_ - 0.05):
            P.box((x, y0 + P_, deck), (x + 0.05, y1 - P_, deck + 0.1), "oak", "furniture", "bunk")
        P.box((x0 + P_, y0 + 0.05, deck + 0.04), (x1 - P_, y1 - 0.05, deck + 0.06), "oak", "furniture", "bunk")
        P.box((x0 + P_ + 0.02, y0 + 0.07, deck + 0.06), (x1 - P_ - 0.02, y1 - 0.07, deck + 0.18), "straw", "furniture", "bunk")
        P.box((x0 + P_ + 0.5, y0 + 0.06, deck + 0.18), (x1 - P_ - 0.03, y1 - 0.06, deck + 0.2), "cloth", "furniture", "bunk_blanket")
    for y in (y0, y1 - 0.05):                                            # top guard rails
        P.box((x0 + P_, y, 1.85), (x1 - P_ - (0.45 if y == y0 else 0.0), y + 0.05, 1.92), "oak", "furniture", "bunk")
    lx0, lx1 = x1 - 0.46, x1 - 0.1                                        # the ladder
    for x in (lx0, lx1 - 0.05):
        P.box((x, y0 - 0.06, 0), (x + 0.05, y0 - 0.01, 1.95), "oak", "furniture", "bunk")
    for k in range(1, 6):
        P.box((lx0, y0 - 0.055, k * 0.32), (lx1, y0 - 0.015, k * 0.32 + 0.04), "oak", "furniture", "bunk")


def spear_rack(P, x0, y0, x1, y1, n=6, spear=2.6):
    """A spear rack (sheet hall-furniture-v1) 1.80 long in y, 0.45 deep in x, 1.40 high: two A-ends
    with feet, a floor tray, a top bar with the spears in it, spears standing butt-down on the tray."""
    xc = (x0 + x1) * 0.5
    for y in (y0, y1 - 0.08):
        P.box((x0, y, 0), (x1, y + 0.08, 0.06), "oak", "furniture", "rack")
        for s in (-1, 1):
            P.beam((xc + s * 0.18, y + 0.04, 0.04), (xc + s * 0.04, y + 0.04, 1.4), 0.07, 0.07, "oak", "furniture", "rack")
    P.box((x0 + 0.06, y0, 0.06), (x1 - 0.06, y1, 0.12), "oak", "furniture", "rack")
    P.box((xc - 0.06, y0, 1.18), (xc + 0.06, y1, 1.28), "oak", "furniture", "rack")
    for k in range(n):
        y = y0 + 0.25 + k * (y1 - y0 - 0.5) / (n - 1)
        P.cyl((xc, y, 0.12), (xc, y, spear - 0.28), 0.022, "oak", "furniture", "spear", seg=6)
        P.cyl((xc, y, spear - 0.28), (xc, y, spear), 0.045, "iron", "furniture", "spear_iron", seg=4, r2=0.0)


def hanging(P, xc, y_wall, z_top, w=0.9, h=1.4):
    """A cloth hanging on the rear wall (sheet hall-furniture-v1): muted green cloth with an unbleached
    border down both sides and along the foot, on a wooden rod with two iron hooks; no emblem."""
    y = y_wall - 0.36
    P.box((xc - w * 0.5, y - 0.01, z_top - h), (xc + w * 0.5, y + 0.01, z_top - 0.04), "cloth", "furniture", "banner")
    for x in (xc - w * 0.5 + 0.05, xc + w * 0.5 - 0.13):
        P.box((x, y - 0.015, z_top - h + 0.05), (x + 0.08, y - 0.011, z_top - 0.1), "cloth", "furniture", "banner_trim")
    P.box((xc - w * 0.5 + 0.05, y - 0.015, z_top - h + 0.05), (xc + w * 0.5 - 0.05, y - 0.011, z_top - h + 0.13), "cloth", "furniture", "banner_trim")
    P.cyl((xc - w * 0.5 - 0.1, y, z_top), (xc + w * 0.5 + 0.1, y, z_top), 0.025, "oak", "furniture", "banner_rod", seg=6)
    for x in (xc - w * 0.5 + 0.05, xc + w * 0.5 - 0.05):
        P.box((x - 0.015, y - 0.01, z_top - 0.02), (x + 0.015, y_wall - 0.3, z_top + 0.06), "iron", "furniture", "banner_hook")


def chest(P, x0, y0, x1, y1, h):
    """A chest against a wall, its front at y0: body, an overhanging lid, two iron straps over the lid
    and down front and back, a lock plate (owner 29 Sep: chests must not read as the wall's logs)."""
    P.box((x0, y0, 0), (x1, y1, h - 0.1), "oak", "furniture", "chest")
    P.box((x0 - 0.025, y0 - 0.025, h - 0.1), (x1 + 0.025, y1 + 0.025, h), "oak", "furniture", "chest")
    for fx in (0.2, 0.8):
        x = x0 + (x1 - x0) * fx
        P.box((x - 0.035, y0 - 0.04, 0.04), (x + 0.035, y1 + 0.04, h + 0.012), "iron", "furniture", "chest_iron")
    xm = (x0 + x1) * 0.5
    P.box((xm - 0.07, y0 - 0.045, h - 0.24), (xm + 0.07, y0 - 0.02, h - 0.06), "iron", "furniture", "chest_iron")


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
    left = lit_windows(P, "x", -HX, (ym - 2.6, ym - 0.2), FLOOR + 1.3, -1, R)    # the hearth takes the rear end
    left += lit_windows(P, "x", -HX, (ym,), EAVE + 1.0, -1, R, 0.7, 0.9)
    right = lit_windows(P, "x", HX, (ym - 2.2, ym + 2.2), FLOOR + 1.3, 1, R)
    right += lit_windows(P, "x", HX, (ym,), EAVE + 1.0, 1, R, 0.7, 0.9)
    log_wall(P, "x", Y0 + R, -HX - 0.35, HX + 0.35, FLOOR - 0.05, EAVE, R, front, 0.0)
    log_wall(P, "x", Y1 - R, -HX - 0.35, HX + 0.35, FLOOR - 0.05, EAVE, R, rear, 0.0)
    gab = (RIDGE - 0.1, EAVE, (Y1 - Y0) * 0.5 + 0.1)
    log_wall(P, "y", -HX + R, Y0 - 0.35, Y1 + 0.35, FLOOR - 0.05, RIDGE, R, left, R * 0.93, "gable", gab)
    log_wall(P, "y", HX - R, Y0 - 0.35, Y1 + 0.35, FLOOR - 0.05, RIDGE, R, right, R * 0.93, "gable", gab)
    gable_sill(P, -HX, -HX + 2 * R, Y0, Y1, FLOOR, R)
    gable_sill(P, HX, HX - 2 * R, Y0, Y1, FLOOR, R)
    # The door frame with a carved lintel board.
    for a in (-1.25, 1.1):
        P.box((a, Y0 - 0.12, FLOOR), (a + 0.15, Y0 + 0.1, FLOOR + 2.7), "oak", "frame")
    carved_frieze(P, -1.5, 1.5, Y0 - 0.14, FLOOR + 2.72, 0.4)

    # The main roof, smoke vents, chimneys.
    gable_roof(P, -HX, HX, Y0, Y1, EAVE, RIDGE, over=0.8)
    for vx in (-5.0, 5.0):
        vent(P, vx, ym, RIDGE)
    xs = roof_frame(P, -HX + 0.35, HX - 0.35, Y0 + 0.3, Y1 - 0.3, EAVE, RIDGE, clear_x0=1.7)
    hearth(P, bid, -HX + 0.3, Y1 - 2.2, FLOOR, RIDGE)
    # Lanterns hang from two tie beams, one over each half of the council table; the marker is the
    # tie beam's underside.
    for i, lx in enumerate((xs[2], xs[-3])):
        empty(f"{bid}_lamp{i}", (lx, ym - 1.2, EAVE - 0.3), "lamp")

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
    trestle_table(F, -6.0, 6.0, 1.5, 2.7)
    bench(F, -6.0, 6.0, 1.0)
    bench(F, -6.0, 6.0, 3.2)
    dais(F, 8.5, HX - R, -0.5, 4.5, 0.3)
    elder_chair(F, 10.2, 2.0, 0.3, face=-1)
    for x in (-8.5, 4.0, 7.2):
        chest(F, x, Y1 - 0.95, x + 1.1, Y1 - 0.35, 0.6)
    for x in (-8.0, -3.0, 3.0, 8.0):
        hanging(F, x, Y1, 3.0)

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
    gable_sill(P, -HX, -HX + 2 * R, Y0, Y1, FLOOR, R)
    gable_sill(P, HX, HX - 2 * R, Y0, Y1, FLOOR, R)
    for a in (DX - 0.95, DX + 0.8):
        P.box((a, Y0 - 0.12, FLOOR), (a + 0.15, Y0 + 0.1, FLOOR + 2.4), "oak", "frame")
    P.box((DX - 1.1, Y0 - 0.14, FLOOR + 2.4), (DX + 1.1, Y0 + 0.1, FLOOR + 2.6), "oak", "frame")

    gable_roof(P, -HX, HX, Y0, Y1, EAVE, RIDGE, over=0.7)
    xs = roof_frame(P, -HX + 0.35, HX - 0.35, Y0 + 0.3, Y1 - 0.3, EAVE, RIDGE, clear_x0=1.7)
    # The hearth at the middle of the blind gable, clear of the bunks along the rear (Codex 046).
    hearth(P, bid, -HX + 0.3, -1.5, FLOOR, RIDGE)
    for i, lx in enumerate((xs[1], xs[-2])):
        empty(f"{bid}_lamp{i}", (lx, ym - 1.0, EAVE - 0.3), "lamp")

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
    # Bunks: the sheet's 2.00 x 0.95 frames against the rear wall, in the old 2.0 x 1.85 places.
    for bx in (-8.6, -5.4, -2.2, 1.0):
        bunk(F, bx, Y1 - 0.35)
    trestle_table(F, 3.0, 7.0, -1.2, 0.0, module=2.0)
    bench(F, 3.0, 7.0, -1.65, module=2.0)
    bench(F, 3.0, 7.0, 0.45, module=2.0)
    # The spear rack on the right gable, clear of its window (y -2.35 .. -1.65).
    spear_rack(F, HX - 2 * R - 0.5, -4.5, HX - 2 * R - 0.05, -2.7)
    for x in (4.5, 6.2, 7.9):
        chest(F, x, Y1 - 0.95, x + 1.0, Y1 - 0.35, 0.55)

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
