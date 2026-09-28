"""WATER-WORKSHOPS-02 (owner 28 Sep 2026, via Codex BRIEF local/previews/water-workshops-02/BRIEF.md):
the forest city's water mill (M01, 11 x 9) and sawmill (S01, 12 x 8) as their own buildings, each designed
around its wheel - the wheel bay, the axle on a stone pier, the frame over the wheel, a dry entry.

Frame (Blender, exported +Y up): x across the building, the river on +x; y along the river; the entry
faces -y (Godot +z, as every village building). z = 0 is the land-side ground at the entry, the
design water level is WATER. The wheel is an empty `<Name>_wheel_hinge` on the axle turning about its
local x; all its parts are its children.

blender --background --factory-startup --python art/blender/water_workshops.py -- --asset all
"""
import argparse, math, sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import buildings_common as C
from forest_village_materials import make_materials

OUT = HERE / "forest-city-v1"
WATER = -0.5


class Parts:
    """Geometry gathered per (object name, material, role) and emitted as one object each."""

    def __init__(self, mats, bid):
        self.mats = mats
        self.bid = bid
        self.groups = {}

    def _group(self, name, mat, role):
        return self.groups.setdefault((name, mat, role), ([], [], []))

    def poly(self, verts, faces, mat, role, name=None, grain=None):
        """grain: the direction the texture's V (wood grain, shingle courses) runs on these faces."""
        vs, fs, gs = self._group(name or role, mat, role)
        base = len(vs)
        vs.extend(Vector(v) for v in verts)
        fs.extend(tuple(base + i for i in f) for f in faces)
        gs.extend([None if grain is None else Vector(grain).normalized()] * len(faces))

    def box(self, lo, hi, mat, role, name=None):
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
             (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        size = (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
        g = [0, 0, 0]
        g[size.index(max(size))] = 1
        self.poly(v, f, mat, role, name, grain=g)

    def beam(self, a, b, w, d, mat, role, name=None, up=(0, 0, 1)):
        """A w x d beam from a to b (its d side towards `up`)."""
        a, b = Vector(a), Vector(b)
        axis = (b - a).normalized()
        u = Vector(up)
        if abs(axis.dot(u)) > 0.95:
            u = Vector((1, 0, 0))
        side = axis.cross(u).normalized() * (w * 0.5)
        top = side.normalized().cross(axis).normalized() * (d * 0.5)
        v = [a - side - top, a + side - top, a + side + top, a - side + top,
             b - side - top, b + side - top, b + side + top, b - side + top]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        self.poly(v, f, mat, role, name, grain=axis)

    def cyl(self, a, b, r, mat, role, name=None, seg=8, r2=None, caps=True):
        a, b = Vector(a), Vector(b)
        axis = (b - a).normalized()
        u = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
        e1 = axis.cross(u).normalized()
        e2 = axis.cross(e1).normalized()
        r2 = r if r2 is None else r2
        v, f = [], []
        for i in range(seg):
            t = math.tau * (i + 0.5) / seg
            d = e1 * math.cos(t) + e2 * math.sin(t)
            v.append(a + d * r)
            v.append(b + d * r2)
        for i in range(seg):
            j = (i + 1) % seg
            f.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))
        if caps:
            f.append(tuple(2 * i for i in reversed(range(seg))))
            f.append(tuple(2 * i + 1 for i in range(seg)))
        self.poly(v, f, mat, role, name, grain=axis)

    def emit(self, parent=None, prefix=""):
        objs = []
        for (name, mat, role), (vs, fs, gs) in self.groups.items():
            me = bpy.data.meshes.new(prefix + name)
            me.from_pydata([tuple(v) for v in vs], [], fs)
            me.validate()
            import bmesh
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            bm.to_mesh(me)
            bm.free()
            for p in me.polygons:
                p.use_smooth = False
            metric_uv(me, gs)
            ob = bpy.data.objects.new(prefix + name, me)
            ob.data.materials.append(self.mats[mat])
            ob["building_id"] = self.bid
            ob["part_role"] = role
            C.ASSET.objects.link(ob)
            if parent is not None:
                ob.parent = parent
            objs.append(ob)
        self.groups = {}
        return objs


def metric_uv(me, grains):
    """UVs in metres: V along the face's grain (a log's length, a roof's fall line), U across it;
    faces without a grain (or looking along it, like log ends) are projected on their dominant axis."""
    uv = me.uv_layers.new(name="UVMap").data
    for poly in me.polygons:
        n = poly.normal
        g = grains[poly.index] if poly.index < len(grains) else None
        if g is not None and abs(n.dot(g)) < 0.8:
            v_axis = (g - n * n.dot(g)).normalized()
            u_axis = n.cross(v_axis).normalized()
            for li in poly.loop_indices:
                co = me.vertices[me.loops[li].vertex_index].co
                uv[li].uv = (co.dot(u_axis), co.dot(v_axis))
            continue
        if abs(n.z) >= abs(n.x) and abs(n.z) >= abs(n.y):
            a, b = 0, 1
        elif abs(n.x) >= abs(n.y):
            a, b = 1, 2
        else:
            a, b = 0, 2
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = (co[a], co[b])


def empty(name, at, role):
    ob = bpy.data.objects.new(name, None)
    ob.location = at
    ob["part_role"] = role
    C.ASSET.objects.link(ob)
    return ob


def log_wall(P, along, fixed, lo, hi, z0, z1, r, openings, offset, role="shell", gable=None):
    """Horizontal logs along x (along='x', at y=fixed) or y, from lo to hi, courses z0..z1.
    openings: (a, b, zlo, zhi) in the along coordinate. gable: (ridge_z, eave_z, half) narrows the
    course above the eave to the roof line."""
    pitch = 2 * r * 0.93
    z = z0 + r + offset
    while z < z1:
        a0, a1 = lo, hi
        if gable is not None:
            ridge, eave, half = gable
            if z > eave:
                h = half * (ridge - z) / (ridge - eave)
                if h < 0.12:
                    break
                mid = (lo + hi) * 0.5
                a0, a1 = max(lo, mid - h), min(hi, mid + h)
        cuts = sorted((a, b) for a, b, zl, zh in openings if zl < z + r * 0.6 and z - r * 0.6 < zh)
        spans, s = [], a0
        for a, b in cuts:
            if a > s:
                spans.append((s, min(a, a1)))
            s = max(s, b)
        if s < a1:
            spans.append((s, a1))
        for s0, s1 in spans:
            if s1 - s0 < 0.15:
                continue
            if along == "x":
                P.cyl((s0, fixed, z), (s1, fixed, z), r, "oak", role, seg=7)
            else:
                P.cyl((fixed, s0, z), (fixed, s1, z), r, "oak", role, seg=7)
        z += pitch


def roof_slab(P, x_eave, z_eave, z_ridge, y0, y1, t, role="roof", mat="roof", rows=None):
    """One pitch from the eave line x = x_eave to the ridge x = 0: a deck of thickness t and on it
    overlapping courses of shingles whose butts stand proud - the stepped edge reads in silhouette."""
    f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    fall = (x_eave, 0, z_eave - z_ridge)
    v = [(x_eave, y0, z_eave), (0, y0, z_ridge), (0, y1, z_ridge), (x_eave, y1, z_eave)]
    v += [(x, y, z + t * 0.5) for x, y, z in v]
    P.poly(v, f, mat, role, grain=fall)
    length = math.hypot(x_eave, z_ridge - z_eave)
    rows = rows or max(4, int(length / 0.45))
    for r in range(rows):
        t0, t1 = r / rows, min(1.0, (r + 1) / rows + 0.04)
        xa, za = x_eave * (1 - t0), z_eave + (z_ridge - z_eave) * t0
        xb, zb = x_eave * (1 - t1), z_eave + (z_ridge - z_eave) * t1
        lift_a, lift_b = t * 0.5 + 0.09, t * 0.5 + 0.01
        v = [(xa, y0 - 0.04, za + lift_a - 0.05), (xb, y0 - 0.04, zb + lift_b), (xb, y1 + 0.04, zb + lift_b), (xa, y1 + 0.04, za + lift_a - 0.05)]
        v += [(x, y, z + 0.05) for x, y, z in v]
        P.poly(v, f, mat, role, grain=fall)


def door(P, bid, x0, x1, y, z0, z1, mats):
    """A plank door leaf on a hinge at x0 (the village_door contract: *entry_hinge* / *entry_leaf*)."""
    hinge = empty(f"{bid}_entry_hinge0", (x0, y, z0), "door_hinge")
    hinge["open_angle_degrees"] = -90
    P.box((0.03, -0.045, 0.02), (x1 - x0 - 0.03, 0.045, z1 - z0 - 0.02), "oak", "door", "entry_leaf0")
    for zz in (0.35, (z1 - z0) - 0.45):
        P.box((0.08, -0.08, zz), (x1 - x0 - 0.1, -0.045, zz + 0.12), "oak", "door", "entry_leaf0")
    P.box((0.1, -0.1, (z1 - z0) * 0.5), (0.3, -0.045, (z1 - z0) * 0.5 + 0.05), "iron", "door", "entry_leaf0_ring")
    P.emit(hinge, f"{bid}_")
    return hinge


def wheel(P, name, centre, radius, width, spokes, paddles, extra=None):
    """An undershot wheel on a hinge empty at `centre`, turning about local x: two rims, spokes both
    sides into a hub, paddles through both rims. extra(P) adds more parts on the same shaft."""
    hinge = empty(f"{name}_wheel_hinge", centre, "wheel_hinge")
    hw = width * 0.5
    rim_r = radius - 0.1
    n = paddles
    for side in (-hw + 0.06, hw - 0.06):
        for k in range(n):
            a0 = math.tau * k / n
            a1 = math.tau * (k + 1) / n
            p0 = Vector((side, math.cos(a0) * rim_r, math.sin(a0) * rim_r))
            p1 = Vector((side, math.cos(a1) * rim_r, math.sin(a1) * rim_r))
            P.beam(p0 - (p1 - p0) * 0.04, p1 + (p1 - p0) * 0.04, 0.12, 0.2, "oak", "wheel", "wheel", up=(1, 0, 0))
        for k in range(spokes):
            a = math.tau * (k + 0.25) / spokes
            d = Vector((0, math.cos(a), math.sin(a)))
            P.beam(Vector((side, 0, 0)) + d * 0.3, Vector((side, 0, 0)) + d * rim_r, 0.12, 0.14, "oak", "wheel", "wheel")
    for k in range(n):
        a = math.tau * (k + 0.5) / n
        d = Vector((0, math.cos(a), math.sin(a)))
        t = Vector((0, -math.sin(a), math.cos(a)))
        c = d * (radius - 0.3)
        v = []
        for sx in (-hw, hw):
            for sr in (-0.3, 0.32):
                for st in (-0.035, 0.035):
                    v.append(Vector((sx, 0, 0)) + c + d * sr + t * st)
        f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        P.poly(v, f, "oak", "wheel", "wheel")
    P.cyl((-hw - 0.05, 0, 0), (hw + 0.05, 0, 0), 0.34, "oak", "wheel", "wheel", seg=10)
    for sx in (-hw - 0.08, hw + 0.08):
        P.cyl((sx - 0.04, 0, 0), (sx + 0.04, 0, 0), 0.38, "iron", "wheel", "wheel_band", seg=10)
    if extra:
        extra(P)
    P.emit(hinge, f"{name}_")
    return hinge


# ------------------------------------------------------------------------------------------ mill
def water_mill(mats):
    """M01: a compact tall working log house (grain loft), the gable entry on the land end with
    stone steps and a sack hoist over it, the wheel bay on the river side under a lean-to on posts."""
    bid, name = "M01", "WaterMill"
    P = Parts(mats, bid)
    HX, HY = 4.5, 5.5          # the main body 9 x 11
    FLOOR = 1.05
    EAVE = 5.5
    RIDGE = 8.7
    R = 0.155
    WX, WY, WZ = 5.65, 2.3, FLOOR + 0.05   # wheel centre
    WR, WW = 2.0, 1.1

    # Stone base on the whole footprint, down into the river bed on the river side.
    PIT = (3.35, 4.4, WY - 1.05, WY + 1.05)     # the drive pit under the floor slot, down to z 0
    top = FLOOR - 0.15
    P.box((-HX - 0.2, -HY - 0.2, -1.4), (PIT[0], HY + 0.2, top), "stone", "foundation")
    P.box((PIT[0], -HY - 0.2, -1.4), (HX + 0.2, PIT[2], top), "stone", "foundation")
    P.box((PIT[0], PIT[3], -1.4), (HX + 0.2, HY + 0.2, top), "stone", "foundation")
    P.box((PIT[0], PIT[2], -1.4), (PIT[1], PIT[3], 0.0), "stone", "foundation")
    P.box((PIT[1], PIT[2], -1.4), (HX + 0.2, PIT[3], top), "stone", "foundation")
    P.box((HX - 0.1, -HY - 0.2, WATER - 1.3), (HX + 0.35, HY + 0.2, -1.4), "stone", "foundation")
    # A course of large stones along the top edge reads as dressed masonry.
    for k in range(-5, 6):
        P.box((-HX - 0.26, k - 0.44, FLOOR - 0.45), (-HX - 0.14, k + 0.44, FLOOR - 0.17), "stone", "foundation")
    # Stone steps up to the entry (the Hall stair proxy walks them).
    steps = 6
    for i in range(steps):
        top = FLOOR * (steps - i) / steps
        y0 = -HY - 0.2 - 0.3 * i
        P.box((-1.4 - 0.05 * i, y0 - 0.32, -0.4), (1.4 + 0.05 * i, y0, top), "stone", "foundation")

    # A gabled porch on two posts over the steps: the entry reads from afar.
    py = -HY - 1.75
    for sx in (-1, 1):
        P.box((sx * 1.78 - 0.11, py - 0.11, -0.3), (sx * 1.78 + 0.11, py + 0.11, 3.35), "oak", "frame", "porch")
        P.beam((sx * 1.78, py - 0.25, 3.4), (sx * 1.78, -HY + 0.05, 3.4), 0.16, 0.2, "oak", "frame", "porch")
        P.beam((sx * 1.78, py + 0.02, 2.6), (sx * 1.78, py + 0.75, 3.33), 0.1, 0.1, "oak", "frame", "porch")
        roof_slab(P, sx * 2.15, 3.3, 4.35, py - 0.35, -HY + 0.1, 0.12)
        P.beam((sx * 2.15, py - 0.38, 3.32), (0, py - 0.38, 4.37), 0.06, 0.28, "oak", "frame", "porch", up=(0, 1, 0))
    P.beam((-1.9, py, 3.5), (1.9, py, 3.5), 0.18, 0.2, "oak", "frame", "porch")

    # Floor with a slot for the pit wheel by the river wall.
    fl = (FLOOR - 0.15, FLOOR)
    P.box((-HX + 0.2, -HY + 0.2, fl[0]), (PIT[0], HY - 0.2, fl[1]), "oak", "floor")
    P.box((PIT[0], -HY + 0.2, fl[0]), (HX - 0.2, PIT[2], fl[1]), "oak", "floor")
    P.box((PIT[0], PIT[3], fl[0]), (HX - 0.2, HY - 0.2, fl[1]), "oak", "floor")
    # A low guard around the pit.
    P.box((PIT[0] - 0.1, PIT[2] - 0.1, FLOOR), (PIT[0], PIT[3] + 0.1, FLOOR + 0.5), "oak", "furniture")
    P.box((PIT[0], PIT[2] - 0.1, FLOOR), (HX - 0.3, PIT[2], FLOOR + 0.5), "oak", "furniture")
    P.box((PIT[0], PIT[3], FLOOR), (HX - 0.3, PIT[3] + 0.1, FLOOR + 0.5), "oak", "furniture")

    # Log walls. Openings (along, z0, z1).
    front_open = [(-0.95, 0.95, FLOOR, FLOOR + 2.45), (2.1, 2.9, FLOOR + 1.3, FLOOR + 2.1),
                  (-0.65, 0.65, 4.25, 5.55)]
    rear_open = [(-0.4, 0.4, FLOOR + 1.4, FLOOR + 2.1), (-0.5, 0.5, 6.3, 7.2)]
    land_open = [(-2.9, -2.1, FLOOR + 1.3, FLOOR + 2.1), (1.6, 2.4, FLOOR + 1.3, FLOOR + 2.1)]
    river_open = [(-1.9, -0.3, FLOOR + 0.8, FLOOR + 2.0),           # the service window on the drive
                  (WY - 0.3, WY + 0.3, FLOOR - 0.2, FLOOR + 0.35)]  # the axle
    wall_top = EAVE
    log_wall(P, "y", -HX + R, -HY - 0.35, HY + 0.35, FLOOR - 0.05, wall_top, R, land_open, 0.0)
    log_wall(P, "y", HX - R, -HY - 0.35, HY + 0.35, FLOOR - 0.05, wall_top, R, river_open, 0.0)
    gab = (RIDGE - 0.15, EAVE, HX + 0.1)
    log_wall(P, "x", -HY + R, -HX - 0.35, HX + 0.35, FLOOR - 0.05, RIDGE, R, front_open, R * 0.93, "gable", gab)
    log_wall(P, "x", HY - R, -HX - 0.35, HX + 0.35, FLOOR - 0.05, RIDGE, R, rear_open, R * 0.93, "gable", gab)

    # Frames round the openings, window shutters (fixed open), the loft door.
    def frame(face_y, a0, a1, z0, z1, out):
        y = face_y + out * 0.05
        P.box((a0 - 0.12, y - 0.07, z0), (a0, y + 0.07, z1), "oak", "frame")
        P.box((a1, y - 0.07, z0), (a1 + 0.12, y + 0.07, z1), "oak", "frame")
        P.box((a0 - 0.2, y - 0.08, z1), (a1 + 0.2, y + 0.08, z1 + 0.18), "oak", "frame")
    frame(-HY, -0.95, 0.95, FLOOR, FLOOR + 2.45, -1)
    frame(-HY, 2.1, 2.9, FLOOR + 1.3, FLOOR + 2.1, -1)
    frame(-HY, -0.65, 0.65, 4.25, 5.55, -1)
    P.box((-0.6, -HY - 0.02, 4.27), (0.6, -HY + 0.06, 5.5), "oak", "door")   # the loft door, shut
    frame(HY, -0.4, 0.4, FLOOR + 1.4, FLOOR + 2.1, 1)
    for x0, x1 in ((-0.95, 0.95),):
        pass
    for y0, y1 in ((-2.9, -2.1), (1.6, 2.4)):
        P.box((-HX - 0.08, y0 - 0.12, FLOOR + 1.3), (-HX + 0.06, y0, FLOOR + 2.1), "oak", "frame")
        P.box((-HX - 0.08, y1, FLOOR + 1.3), (-HX + 0.06, y1 + 0.12, FLOOR + 2.1), "oak", "frame")
        P.box((-HX - 0.1, y0 - 0.2, FLOOR + 2.1), (-HX + 0.06, y1 + 0.2, FLOOR + 2.28), "oak", "frame")
        # Warm lit panes: a thin inset plane.
        P.box((-HX + 0.18, y0, FLOOR + 1.3), (-HX + 0.22, y1, FLOOR + 2.1), "cloth", "window")
    P.box((2.1, -HY + 0.2, FLOOR + 1.3), (2.9, -HY + 0.24, FLOOR + 2.1), "cloth", "window")
    # The service window over the drive, with its small plank canopy.
    P.box((HX - 0.05, -2.02, FLOOR + 0.7), (HX + 0.1, -0.18, FLOOR + 0.82), "oak", "frame")
    P.box((HX - 0.05, -2.02, FLOOR + 0.8), (HX + 0.1, -1.9, FLOOR + 2.0), "oak", "frame")
    P.box((HX - 0.05, -0.3, FLOOR + 0.8), (HX + 0.1, -0.18, FLOOR + 2.0), "oak", "frame")
    P.poly([(HX, -2.2, FLOOR + 2.25), (HX, 0.0, FLOOR + 2.25), (HX + 0.75, 0.0, FLOOR + 1.95), (HX + 0.75, -2.2, FLOOR + 1.95),
            (HX, -2.2, FLOOR + 2.33), (HX, 0.0, FLOOR + 2.33), (HX + 0.75, 0.0, FLOOR + 2.03), (HX + 0.75, -2.2, FLOOR + 2.03)],
           [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)], "roof", "roof", grain=(1, 0, -0.35))

    # Roof: two pitches with overhangs, ridge beam, carved barge boards on both gables.
    slope = (RIDGE - EAVE) / HX
    over = 0.9
    for sx in (-1, 1):
        roof_slab(P, sx * (HX + over), EAVE - over * slope, RIDGE, -HY - 0.8, HY + 0.8, 0.2)
        for gy in (-HY - 0.8, HY + 0.8):
            P.beam((sx * (HX + over), gy, EAVE - over * slope + 0.02), (0, gy, RIDGE + 0.02), 0.07, 0.34, "oak", "frame",
                   up=(0, 1, 0))
    P.beam((0, -HY - 0.9, RIDGE + 0.2), (0, HY + 0.9, RIDGE + 0.2), 0.24, 0.24, "oak", "frame")
    # Purlins show under the eaves.
    for sx in (-1, 1):
        for t in (0.25, 0.62):
            x = sx * HX * (1 - t)
            P.beam((x, -HY - 0.8, EAVE + t * (RIDGE - EAVE) - 0.1), (x, HY + 0.8, EAVE + t * (RIDGE - EAVE) - 0.1),
                   0.16, 0.16, "oak", "frame")
    # Stone chimney at the rear of the ridge (the miller's stove).
    P.box((-1.6, 3.2, 6.8), (-0.9, 3.9, RIDGE + 1.2), "stone", "chimney")
    P.box((-1.7, 3.1, RIDGE + 1.2), (-0.8, 4.0, RIDGE + 1.35), "stone", "chimney")

    # The sack hoist over the entry: a beam out of the gable apex, rope and a sack.
    P.beam((0, -HY + 0.4, 6.35), (0, -HY - 1.7, 6.35), 0.22, 0.26, "oak", "frame")
    P.beam((0, -HY - 0.2, 6.35), (0, -HY - 0.2, 5.75), 0.14, 0.14, "oak", "frame")
    P.beam((0, -HY - 0.2, 5.85), (0, -HY - 1.0, 6.35), 0.12, 0.12, "oak", "frame")
    P.box((-0.03, -HY - 1.58, 4.35), (0.03, -HY - 1.52, 6.25), "straw", "hoist")
    P.cyl((0, -HY - 1.55, 3.65), (0, -HY - 1.55, 4.4), 0.3, "cloth", "hoist", seg=8, r2=0.18)

    # Wheel bay: the outer stone pier and the bearing block, the axle, a lean-to on posts over the wheel.
    PX = WX + WW * 0.5 + 0.55
    P.box((PX - 0.45, WY - 0.6, WATER - 1.2), (PX + 0.45, WY + 0.6, WZ - 0.3), "stone", "footing", "wheel_support_pier")
    P.box((PX - 0.35, WY - 0.45, WZ - 0.3), (PX + 0.35, WY + 0.45, WZ + 0.1), "oak", "frame", "wheel_support_bearing")
    P.box((PX - 0.2, WY - 0.45, WZ + 0.1), (PX + 0.2, WY - 0.25, WZ + 0.35), "oak", "frame", "wheel_support_bearing")
    P.box((PX - 0.2, WY + 0.25, WZ + 0.1), (PX + 0.2, WY + 0.45, WZ + 0.35), "oak", "frame", "wheel_support_bearing")
    P.cyl((HX - 1.3, WY, WZ), (PX + 0.4, WY, WZ), 0.17, "oak", "frame", "axle", seg=10)
    P.box((HX - 0.05, WY - 0.4, WZ - 0.35), (HX + 0.25, WY + 0.4, WZ - 0.17), "oak", "frame", "wheel_support_bearing")
    LX = PX + 0.3               # the lean-to's outer posts
    LZ = 4.0                    # its eave
    for py in (WY - WR - 0.45, WY + WR + 0.45):
        P.box((LX - 0.4, py - 0.4, WATER - 1.2), (LX + 0.4, py + 0.4, WZ - 0.4), "stone", "footing", "wheel_support_footing")
        P.box((LX - 0.13, py - 0.13, WZ - 0.4), (LX + 0.13, py + 0.13, LZ), "oak", "frame", "wheel_support_post")
        P.beam((LX, py, LZ - 1.0), (HX + 0.05, py, EAVE - 0.8), 0.14, 0.14, "oak", "frame", "wheel_support_post")
        # Ties from the post to the house, over the wheel.
        P.beam((LX, py, LZ - 0.15), (HX, py, LZ - 0.15), 0.16, 0.2, "oak", "frame", "wheel_support_post")
    P.box((LX - 0.15, WY - WR - 0.75, LZ), (LX + 0.15, WY + WR + 0.75, LZ + 0.25), "oak", "frame", "wheel_support_post")
    ly0, ly1 = WY - WR - 0.9, WY + WR + 0.9
    lz_in = EAVE - 0.25
    P.poly([(HX - 0.1, ly0, lz_in), (HX - 0.1, ly1, lz_in), (LX + 0.6, ly1, LZ + 0.1), (LX + 0.6, ly0, LZ + 0.1),
            (HX - 0.1, ly0, lz_in + 0.18), (HX - 0.1, ly1, lz_in + 0.18), (LX + 0.6, ly1, LZ + 0.28), (LX + 0.6, ly0, LZ + 0.28)],
           [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)], "roof", "roof", grain=(1, 0, -0.35))
    # A plank guide wall on the far side of the race keeps the water to the paddles.
    P.box((PX + 0.5, WY - WR - 0.3, WATER - 1.2), (PX + 0.62, WY + WR + 0.3, WATER + 0.2), "oak", "frame", "race")

    # Inside: the millstones on their timber stage, the hopper, the vertical shaft to the pit wheel.
    SX, SY = 2.0, WY - 0.2
    P.box((SX - 0.95, SY - 0.95, FLOOR), (SX + 0.95, SY + 0.95, FLOOR + 0.8), "oak", "furniture")
    for cx in (SX - 0.9, SX + 0.9):
        for cy in (SY - 0.9, SY + 0.9):
            P.box((cx - 0.08, cy - 0.08, FLOOR), (cx + 0.08, cy + 0.08, FLOOR + 0.82), "oak", "furniture")
    P.cyl((SX, SY, FLOOR + 0.8), (SX, SY, FLOOR + 1.02), 0.7, "stone", "furniture", "millstone", seg=14)
    P.cyl((SX, SY, FLOOR + 0.8), (SX, SY, FLOOR + 1.2), 0.78, "oak", "furniture", "casing", seg=12, caps=False)
    P.cyl((SX, SY, FLOOR + 1.02), (SX, SY, FLOOR + 1.24), 0.64, "stone", "furniture", "millstone", seg=14)
    P.cyl((SX, SY, FLOOR + 1.55), (SX, SY, FLOOR + 2.25), 0.22, "oak", "furniture", "hopper", seg=4, r2=0.62)
    for dx, dy in ((-0.5, -0.5), (0.5, -0.5), (-0.5, 0.5), (0.5, 0.5)):
        P.beam((SX + dx, SY + dy, FLOOR + 1.2), (SX + dx * 0.9, SY + dy * 0.9, FLOOR + 2.1), 0.07, 0.07, "oak", "furniture")
    P.box((SX + 0.75, SY - 0.12, FLOOR + 0.5), (SX + 1.2, SY + 0.12, FLOOR + 0.7), "oak", "furniture", "spout")
    P.cyl((PIT[0] - 0.2, WY, FLOOR - 0.1), (PIT[0] - 0.2, WY, FLOOR + 0.95), 0.12, "oak", "furniture", "shaft", seg=8)
    # The wallower (lantern pinion) the pit wheel's cogs drive.
    for k in range(8):
        a = math.tau * k / 8
        P.cyl((PIT[0] - 0.2 + math.cos(a) * 0.3, WY + math.sin(a) * 0.3, FLOOR + 0.05),
              (PIT[0] - 0.2 + math.cos(a) * 0.3, WY + math.sin(a) * 0.3, FLOOR + 0.55), 0.035, "oak", "furniture", "shaft", seg=5)
    P.cyl((PIT[0] - 0.2, WY, FLOOR + 0.02), (PIT[0] - 0.2, WY, FLOOR + 0.07), 0.38, "oak", "furniture", "shaft", seg=10)
    P.cyl((PIT[0] - 0.2, WY, FLOOR + 0.53), (PIT[0] - 0.2, WY, FLOOR + 0.58), 0.38, "oak", "furniture", "shaft", seg=10)
    # Sacks by the door and under the loft, a flour bin, a barrel.
    sacks = [(-3.6, -4.4), (-3.0, -4.6), (-3.3, -3.9), (-3.8, -3.3), (-2.9, -3.4), (3.2, -4.4), (3.7, -4.0)]
    for i, (x, y) in enumerate(sacks):
        h = 0.62 if i % 2 else 0.55
        P.cyl((x, y, FLOOR), (x, y, FLOOR + h), 0.26, "cloth", "furniture", "sack", seg=7, r2=0.2)
    P.cyl((-3.45, -4.1, FLOOR + 0.55), (-3.45, -4.1, FLOOR + 1.05), 0.25, "cloth", "furniture", "sack", seg=7, r2=0.18)
    P.box((-HX + 0.3, 3.0, FLOOR), (-HX + 1.2, 4.8, FLOOR + 0.8), "oak", "furniture", "bin")
    P.cyl((3.8, -2.9, FLOOR), (3.8, -2.9, FLOOR + 0.8), 0.33, "oak", "furniture", "barrel", seg=10)
    # Outside: sacks on the landing by the steps, a cart-side barrel.
    for x, y in ((1.8, -HY - 0.55), (2.3, -HY - 0.6), (2.05, -HY - 1.05)):
        P.cyl((x, y, 0.0), (x, y, 0.58), 0.27, "cloth", "furniture", "sack", seg=7, r2=0.2)

    # The grain loft over the rear half: joists, planks, a ladder up.
    LOFT = FLOOR + 3.0
    for y in (-4.2, -2.4, -0.6, 1.2, 3.0, 4.6):
        P.box((-HX + 0.2, y - 0.1, LOFT - 0.25), (HX - 0.2, y + 0.1, LOFT - 0.05), "oak", "frame")
    # Planks over the whole length; hatches over the hopper (the grain chute) and the ladder.
    hatch = (SX - 0.7, SX + 0.7, SY - 0.9, SY + 0.9)
    lad = (-HX + 0.2, -HX + 1.3, -1.0, 0.35)
    P.box((-HX + 0.2, -HY + 0.2, LOFT - 0.05), (lad[1], lad[2], LOFT + 0.05), "oak", "loft")
    P.box((-HX + 0.2, lad[3], LOFT - 0.05), (lad[1], HY - 0.2, LOFT + 0.05), "oak", "loft")
    P.box((lad[1], -HY + 0.2, LOFT - 0.05), (hatch[0], HY - 0.2, LOFT + 0.05), "oak", "loft")
    P.box((hatch[0], -HY + 0.2, LOFT - 0.05), (hatch[1], hatch[2], LOFT + 0.05), "oak", "loft")
    P.box((hatch[0], hatch[3], LOFT - 0.05), (hatch[1], HY - 0.2, LOFT + 0.05), "oak", "loft")
    P.box((hatch[1], -HY + 0.2, LOFT - 0.05), (HX - 0.2, HY - 0.2, LOFT + 0.05), "oak", "loft")
    P.box((SX - 0.2, SY - 0.2, FLOOR + 2.25), (SX + 0.2, SY + 0.2, LOFT - 0.05), "oak", "furniture", "chute")
    for i, (x, y) in enumerate(((-2.5, 4.6), (-1.9, 4.7), (-2.2, 4.1), (1.5, 4.7))):
        P.cyl((x, y, LOFT + 0.05), (x, y, LOFT + 0.6), 0.26, "cloth", "furniture", "sack", seg=7, r2=0.2)
    lx = -HX + 0.7
    for sy in (-0.25, 0.25):
        P.beam((lx + sy, -0.9, FLOOR), (lx + sy, 0.35, LOFT + 0.6), 0.07, 0.09, "oak", "furniture", "ladder")
    for k in range(1, 11):
        t = k / 11
        P.box((lx - 0.25, -0.9 + 1.25 * t - 0.03, FLOOR + (LOFT + 0.6 - FLOOR) * t - 0.02),
              (lx + 0.25, -0.9 + 1.25 * t + 0.03, FLOOR + (LOFT + 0.6 - FLOOR) * t + 0.02), "oak", "furniture", "ladder")

    P.emit(None, f"{bid}_")
    door(P, bid, -0.95, 0.95, -HY + 0.1, FLOOR, FLOOR + 2.4, mats)

    def pit_wheel(Q):
        # The pit wheel inside the wall on the same shaft: a cogged ring and four arms.
        gx = PIT[0] + 0.45 - WX
        for k in range(16):
            a0, a1 = math.tau * k / 16, math.tau * (k + 1) / 16
            Q.beam((gx, math.cos(a0) * 0.85, math.sin(a0) * 0.85), (gx, math.cos(a1) * 0.85, math.sin(a1) * 0.85),
                   0.16, 0.14, "oak", "wheel", "gear", up=(1, 0, 0))
            Q.box((gx - 0.2, math.cos(a0) * 0.85 - 0.04, math.sin(a0) * 0.85 - 0.04),
                  (gx - 0.08, math.cos(a0) * 0.85 + 0.04, math.sin(a0) * 0.85 + 0.04), "oak", "wheel", "gear")
        for k in range(4):
            a = math.tau * k / 4 + 0.4
            Q.beam((gx, 0, 0), (gx, math.cos(a) * 0.85, math.sin(a) * 0.85), 0.1, 0.1, "oak", "wheel", "gear")
        Q.cyl((gx - 0.2, 0, 0), (gx + 0.2, 0, 0), 0.22, "oak", "wheel", "gear", seg=8)
    wheel(P, name, (WX, WY, WZ), WR, WW, 8, 16, pit_wheel)
    return {"id": bid, "slug": "m01", "wheel_centre": (WX, WY, WZ), "wheel_radius": WR, "water": WATER,
            "floor": FLOOR, "entry": (0.0, -HY, FLOOR)}


# --------------------------------------------------------------------------------------- sawmill
def sawmill(mats):
    """S01: a long low open shed on a heavy post-and-beam frame over a plank deck on stone. Logs come
    in over skids at the front end (-y), ride a carriage on rails to the sash saw in the middle and
    leave as boards at the rear; the wheel on the river side turns a crank that works the saw."""
    bid, name = "S01", "Sawmill"
    P = Parts(mats, bid)
    HX, HY = 4.0, 6.0          # the deck 8 x 12
    FLOOR = 0.6
    EAVE, RIDGE, RX = 3.6, 5.7, -0.6     # an asymmetric gable: the ridge off the middle, landwards
    SAWY = -1.0
    WR, WW = 1.9, 1.0
    WX, WZ = HX + 0.35 + 0.3 + WW * 0.5 + 0.1, WATER + WR - 0.4
    WY = SAWY
    posts_y = (-HY + 0.15, -2.9, 0.0, 2.9, HY - 0.15)
    PX = HX - 0.15

    # Stone: a footing strip under the deck, a retaining wall to the river, blocks under the posts.
    P.box((-HX, -HY, -1.0), (HX - 0.3, HY, FLOOR - 0.35), "stone", "foundation")
    P.box((HX - 0.3, -HY - 0.2, WATER - 1.2), (HX + 0.3, HY + 0.2, FLOOR - 0.35), "stone", "foundation")
    for py in posts_y:
        for px in (-PX, PX):
            P.box((px - 0.3, py - 0.3, -0.9), (px + 0.3, py + 0.3, FLOOR - 0.1), "stone", "footing")
    # Sills and the plank deck.
    for sx in (-PX, -1.3, 1.3, PX):
        P.box((sx - 0.15, -HY, FLOOR - 0.38), (sx + 0.15, HY, FLOOR - 0.1), "oak", "frame")
    P.box((-HX, -HY, FLOOR - 0.1), (HX, HY, FLOOR), "oak", "floor")

    # The frame: posts, plates, tie beams, braces, king posts.
    for py in posts_y:
        for px in (-PX, PX):
            P.box((px - 0.15, py - 0.15, FLOOR), (px + 0.15, py + 0.15, EAVE), "oak", "frame")
            for dy in (-0.9, 0.9):
                if abs(py + dy) < HY:
                    P.beam((px, py, EAVE - 0.95), (px, py + dy, EAVE - 0.1), 0.14, 0.14, "oak", "frame")
            P.beam((px, py, EAVE - 0.9), (px - math.copysign(0.9, px), py, EAVE - 0.1), 0.14, 0.14, "oak", "frame")
        P.beam((-PX - 0.3, py, EAVE + 0.1), (PX + 0.3, py, EAVE + 0.1), 0.24, 0.26, "oak", "frame")
        P.box((RX - 0.12, py - 0.12, EAVE + 0.2), (RX + 0.12, py + 0.12, RIDGE + 0.1), "oak", "frame")
        for px in (-PX, PX):
            k = 0.45
            P.beam((RX, py, RIDGE - 0.6), (RX + (px - RX) * k, py, EAVE + 0.2 + (RIDGE - EAVE) * (1 - k) * 0.8),
                   0.14, 0.14, "oak", "frame")
    for px in (-PX, PX):
        P.box((px - 0.16, -HY - 0.3, EAVE - 0.05), (px + 0.16, HY + 0.3, EAVE + 0.25), "oak", "frame")
    P.box((RX - 0.14, -HY - 0.8, RIDGE + 0.05), (RX + 0.14, HY + 0.8, RIDGE + 0.33), "oak", "frame")
    # Roof: the two pitches meet at the off-centre ridge (roof_slab works about x = 0, shifted to RX).
    over = 0.8
    LIFT = 0.36     # the roof deck rests on the plates and tie beams, not through them
    for sx in (-1, 1):
        edge = sx * (HX + over)
        z_edge = EAVE - over * (RIDGE - EAVE) / abs(sx * HX - RX) + LIFT
        slab = Parts(mats, bid)
        roof_slab(slab, edge - RX, z_edge, RIDGE + LIFT, -HY - over, HY + over, 0.18)
        for key, (vs, fs, gs) in slab.groups.items():
            dst = P._group(*key)
            base = len(dst[0])
            dst[0].extend(Vector((v.x + RX, v.y, v.z)) for v in vs)
            dst[1].extend(tuple(base + i for i in f) for f in fs)
            dst[2].extend(gs)
        for gy in (-HY - over, HY + over):
            P.beam((edge, gy, z_edge + 0.03), (RX, gy, RIDGE + LIFT + 0.03), 0.07, 0.32, "oak", "frame", up=(0, 1, 0))

    # The tool room in the rear land corner: plank walls, a shut door.
    TX0, TX1, TY0 = -PX, -1.6, 3.2
    P.box((TX0, TY0, FLOOR), (TX1, TY0 + 0.08, EAVE), "oak", "door", "toolroom")
    P.box((TX1 - 0.08, TY0, FLOOR), (TX1, HY - 0.15, EAVE), "oak", "door", "toolroom")
    P.box((TX0, HY - 0.23, FLOOR), (TX1, HY - 0.15, EAVE), "oak", "door", "toolroom")
    P.box((TX0, TY0, FLOOR), (TX0 + 0.08, HY - 0.15, EAVE), "oak", "door", "toolroom")
    P.box((TX0 + 0.8, TY0 - 0.06, FLOOR + 0.05), (TX0 + 1.7, TY0, FLOOR + 2.1), "oak", "frame", "toolroom_door")

    # Rails from the front skids to the rear, the carriage, a log on it.
    for rx in (-0.95, 0.35):
        P.box((rx - 0.09, -HY - 0.2, FLOOR), (rx + 0.09, HY - 0.3, FLOOR + 0.16), "oak", "frame", "rails")
        P.beam((rx, -HY - 1.9, 0.0), (rx, -HY - 0.1, FLOOR + 0.1), 0.2, 0.2, "oak", "frame", "skids")
    for ty in range(-5, 6):
        P.box((-1.25, ty - 0.1, FLOOR), (0.65, ty + 0.1, FLOOR + 0.06), "oak", "frame", "rails")
    # The carriage stands back from the entry and rides on the rails: aisles stay free on both sides.
    CY0, CY1 = SAWY - 3.2, SAWY - 0.4
    P.box((-1.0, CY0, FLOOR + 0.16), (0.4, CY1, FLOOR + 0.36), "oak", "furniture", "carriage")
    for cy in (CY0 + 0.3, (CY0 + CY1) * 0.5, CY1 - 0.3):
        P.box((-1.0, cy - 0.12, FLOOR + 0.36), (-0.84, cy + 0.12, FLOOR + 0.8), "oak", "furniture", "carriage")
        P.box((0.24, cy - 0.12, FLOOR + 0.36), (0.4, cy + 0.12, FLOOR + 0.8), "oak", "furniture", "carriage")
    P.cyl((-0.3, CY0 - 0.2, FLOOR + 0.72), (-0.3, SAWY + 0.25, FLOOR + 0.72), 0.36, "oak", "furniture", "log", seg=10)

    # The sash saw: two guide posts, a head beam, the sash with its blade over the log's path.
    for gx in (-1.55, 0.95):
        P.box((gx - 0.14, SAWY - 0.14, FLOOR), (gx + 0.14, SAWY + 0.14, 3.3), "oak", "frame", "saw")
    P.box((-1.75, SAWY - 0.16, 3.0), (1.15, SAWY + 0.16, 3.3), "oak", "frame", "saw")
    P.box((-1.3, SAWY - 0.07, 1.25), (0.7, SAWY + 0.07, 1.4), "oak", "furniture", "sash")
    P.box((-1.3, SAWY - 0.07, 2.55), (0.7, SAWY + 0.07, 2.7), "oak", "furniture", "sash")
    for sx in (-1.3, 0.56):
        P.box((sx, SAWY - 0.07, 1.25), (sx + 0.14, SAWY + 0.07, 2.7), "oak", "furniture", "sash")
    P.box((-0.33, SAWY - 0.01, 1.25), (-0.27, SAWY + 0.01, 2.7), "iron", "furniture", "blade")
    # The drive: the axle through the river wall to a crank disc, the pitman rod up to the sash.
    CX = 2.1
    P.cyl((CX - 0.25, WY, WZ), (WX + WW * 0.5 + 0.75, WY, WZ), 0.16, "oak", "frame", "axle", seg=10)
    P.box((HX - 0.1, WY - 0.35, WZ - 0.4), (HX + 0.35, WY + 0.35, WZ - 0.18), "oak", "frame", "wheel_support_bearing")
    P.box((CX + 0.2, WY - 0.3, FLOOR), (CX + 0.5, WY + 0.3, WZ - 0.16), "oak", "frame", "wheel_support_bearing")
    P.beam((CX - 0.3, WY - 0.35, WZ + 0.05), (0.7, WY, 1.33), 0.12, 0.12, "oak", "furniture", "pitman")

    # Wheel bay: the outer pier and bearing, a lean-to over the wheel on two posts.
    OX = WX + WW * 0.5 + 0.55
    P.box((OX - 0.4, WY - 0.5, WATER - 1.2), (OX + 0.4, WY + 0.5, WZ - 0.3), "stone", "footing", "wheel_support_pier")
    P.box((OX - 0.32, WY - 0.4, WZ - 0.3), (OX + 0.32, WY + 0.4, WZ + 0.08), "oak", "frame", "wheel_support_bearing")
    LX, LZ = OX + 0.25, 3.1
    for py in (WY - WR - 0.4, WY + WR + 0.4):
        P.box((LX - 0.35, py - 0.35, WATER - 1.2), (LX + 0.35, py + 0.35, WZ - 0.45), "stone", "footing", "wheel_support_footing")
        P.box((LX - 0.12, py - 0.12, WZ - 0.45), (LX + 0.12, py + 0.12, LZ), "oak", "frame", "wheel_support_post")
        P.beam((LX, py, LZ - 0.12), (PX, py, LZ - 0.12), 0.14, 0.18, "oak", "frame", "wheel_support_post")
    P.box((LX - 0.14, WY - WR - 0.7, LZ), (LX + 0.14, WY + WR + 0.7, LZ + 0.22), "oak", "frame", "wheel_support_post")
    y0, y1 = WY - WR - 0.85, WY + WR + 0.85
    P.poly([(HX + 0.2, y0, EAVE - 0.35), (HX + 0.2, y1, EAVE - 0.35), (LX + 0.55, y1, LZ + 0.1), (LX + 0.55, y0, LZ + 0.1),
            (HX + 0.2, y0, EAVE - 0.2), (HX + 0.2, y1, EAVE - 0.2), (LX + 0.55, y1, LZ + 0.25), (LX + 0.55, y0, LZ + 0.25)],
           [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)], "roof", "roof", grain=(1, 0, -0.3))
    P.box((OX + 0.45, WY - WR - 0.3, WATER - 1.2), (OX + 0.57, WY + WR + 0.3, WATER + 0.2), "oak", "frame", "race")

    # Boards out at the rear, sawdust, a trestle; logs waiting outside the front on the ground.
    for layer in range(5):
        z = FLOOR + 0.08 + layer * 0.14
        for b in range(5):
            x = 1.2 + b * 0.32
            P.box((x, 2.4 + (layer % 2) * 0.2, z), (x + 0.28, HY - 0.7 + (layer % 2) * 0.2, z + 0.1), "oak", "furniture", "boards")
    P.cyl((-0.3, SAWY + 0.55, FLOOR), (-0.3, SAWY + 0.55, FLOOR + 0.35), 0.75, "straw", "furniture", "sawdust", seg=10, r2=0.1)
    for tx in (-3.45, -2.75):
        P.beam((tx, -3.6, FLOOR), (tx, -3.3, FLOOR + 0.75), 0.1, 0.1, "oak", "furniture", "trestle")
        P.beam((tx, -3.0, FLOOR), (tx, -3.3, FLOOR + 0.75), 0.1, 0.1, "oak", "furniture", "trestle")
    P.box((-3.7, -3.5, FLOOR + 0.75), (-2.5, -3.1, FLOOR + 0.83), "oak", "furniture", "trestle")
    for i, lx in enumerate((-3.4, -2.6, -3.0, 2.4, 3.1)):
        z = 0.32 if i != 2 else 0.9
        P.cyl((lx, -HY - 2.4 - (i % 2) * 0.3, z), (lx, -HY - 6.2 + (i % 2) * 0.4, z), 0.32, "oak", "furniture", f"logpile{i}", seg=9)

    P.emit(None, f"{bid}_")

    def crank(Q):
        Q.cyl((CX - WX - 0.12, 0, 0), (CX - WX + 0.12, 0, 0), 0.5, "oak", "wheel", "crank", seg=12)
        Q.box((CX - WX - 0.2, -0.06, 0.34), (CX - WX - 0.12, 0.06, 0.46), "iron", "wheel", "crank")
    wheel(P, name, (WX, WY, WZ), WR, WW, 8, 14, crank)
    return {"id": bid, "slug": "s01", "wheel_centre": (WX, WY, WZ), "wheel_radius": WR, "water": WATER,
            "floor": FLOOR, "entry": (-0.3, -HY, FLOOR)}


# -------------------------------------------------------------------------------------------- run
def export(info):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in C.ASSET.objects:
        ob.select_set(True)
    OUT.mkdir(parents=True, exist_ok=True)
    blend = OUT / f"{info['slug']}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.export_scene.gltf(filepath=str(OUT / f"{info['slug']}.glb"), use_selection=True, export_yup=True,
                              export_apply=True, export_animations=False, export_cameras=False,
                              export_lights=False, export_extras=True)
    tris = 0
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for ob in C.ASSET.objects:
        if ob.type != "MESH":
            continue
        tris += sum(len(p.vertices) - 2 for p in ob.data.polygons)
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    print(f"WORKSHOP_BUILT id={info['id']} tris={tris} bbox={tuple(round(c, 2) for c in lo)}..{tuple(round(c, 2) for c in hi)} "
          f"wheel={info.get('wheel_centre')} r={info.get('wheel_radius')} water={info.get('water')} floor={info['floor']}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--asset", default="all")
    args = ap.parse_args(argv)
    builders = {"M01": water_mill, "S01": sawmill}
    for bid, build in builders.items():
        if args.asset not in ("all", bid):
            continue
        C.reset()
        mats = make_materials(OUT / "textures")
        info = build(mats)
        bpy.context.view_layer.update()
        export(info)


if __name__ == "__main__":
    main()
