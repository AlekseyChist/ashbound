"""L-H: lowland town house of the Council (WORLD-PLAN-01, D-118; architecture.md module L-H, plate L).
Plastered stone ground floor (shop allowed), dark timber-framed upper floor with a small jetty,
steep tiled gable roof, stone chimney. Walls 8 x 7 m, ridge ~9.6 m.
Run: blender --background --factory-startup --python-exit-code 1 --python this_file
Blender: XY footprint, Z up, entry on -Y; the GLB export turns it to Godot Y up, entry +Z. Pivot: floor centre.
Photo textures (CC0, already in the project) with world-scale cube UVs; furniture tagged part_role=interior_furniture
so the game can hide it from afar; the entry leaf hangs on L_entry_hinge for village_door.gd. Renders and stats stay in local/ (D-080).
"""
import sys, math, random, json, hashlib
from pathlib import Path
import bpy, bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2].parent if (Path(__file__).resolve().parents[2] / 'project.godot').exists() is False else Path(__file__).resolve().parents[2]
if not (ROOT / 'project.godot').exists():
    ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'art/blender'))
import buildings_common as C
C.reset()
random.seed(119)
OUT = ROOT / 'assets/buildings/world-architecture-v1'
QA = ROOT / 'local/previews/world-architecture-v1/lowland-house'
OUT.mkdir(parents=True, exist_ok=True)
QA.mkdir(parents=True, exist_ok=True)
TEX = ROOT / 'assets/environment/village-house-materials-v1'
COLLISIONS = []
COLLISION_MESHES = []   # (name, verts, faces): closed collision volumes that are not boxes
ROLE = {}          # object name -> part_role

def photo(name, stem, tint=(1, 1, 1), rough=0.92, scale=1.0):
    """Principled material on a CC0 photo texture with the tint baked into its pixels: glTF drops a
    Multiply node (Codex 13 Oct, checked in Godot: albedo came back white) and caps a colour factor at 1."""
    import numpy as np
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    nt = mat.node_tree; bsdf = nt.nodes.get('Principled BSDF')
    src = bpy.data.images.load(str(TEX / f'{stem}_diff_1k.jpg' if (TEX / f'{stem}_diff_1k.jpg').exists() else TEX / f'{stem}_col_1k.jpg'))
    px = np.empty(len(src.pixels), dtype=np.float32); src.pixels.foreach_get(px)
    # 8-bit pixels are sRGB-encoded; the tint was chosen as a linear multiply (the former Mix node)
    px = px.reshape(-1, 4); px[:, :3] = np.clip(px[:, :3] * np.array(tint, dtype=np.float32) ** (1 / 2.2), 0, 1)
    key = name.lower().replace(' ', '_')
    img = bpy.data.images.new(f'{key}_tinted', src.size[0], src.size[1])
    img.pixels.foreach_set(px.ravel())
    img.file_format = 'JPEG'; img.filepath_raw = str(QA / f'{key}_tinted.jpg')
    sc = bpy.context.scene; sc.render.image_settings.quality = 90
    img.save(); img.source = 'FILE'; img.reload(); img.pack()
    bpy.data.images.remove(src)
    tex = nt.nodes.new('ShaderNodeTexImage'); tex.image = img
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = rough
    mat['uv_scale'] = scale
    return mat

PLASTER = photo('L warm plaster', 'plaster_grey_04', (1.18, 1.04, 0.80), 0.95, 0.5)
STONE = photo('L grey stone', 'stone_wall_02', (0.80, 0.80, 0.82), 0.95, 0.6)
TIMBER = photo('L dark timber', 'fine_grained_wood', (0.30, 0.22, 0.17), 0.85, 1.2)
BOARDS = photo('L floor boards', 'fine_grained_wood', (0.62, 0.46, 0.32), 0.9, 1.2)
def tiles(name, base, seed):
    """Barrel clay tiles painted into a small packed image (0.33 m per tile, 0.5 m per course)."""
    rnd = random.Random(seed)
    mat = C.mat(name, (*base, 1), 0.85)
    im = bpy.data.images.new(name + '_paint', width=128, height=128)
    px = []
    for y in range(128):
        v = (y % 64) / 64.0
        for x in range(128):
            u = (x % 32) / 32.0
            k = (x // 32) + 7 * (y // 64)
            jitter = ((k * 2654435761) % 97) / 97.0 * 0.10 - 0.05
            shade = 0.72 + 0.30 * math.sin(math.pi * u) - 0.22 * max(0.0, v - 0.80) / 0.20 + jitter
            px.extend([max(0, min(1, c * shade)) for c in base] + [1])
    im.pixels.foreach_set(px); im.pack()
    tex = mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image = im
    mat.node_tree.links.new(tex.outputs['Color'], mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    mat['uv_scale'] = 1.0 / 1.32      # 128 px = 4 tiles x 0.33 m = 1.32 m
    return mat
TILE = tiles('L clay roof tile', (0.50, 0.24, 0.14), 1)
TILE2 = tiles('L clay roof tile dark', (0.44, 0.21, 0.12), 2)
IRON = C.mat('L forged iron', (0.09, 0.085, 0.08, 1), 0.7)
CLOTH = C.mat('L linen', (0.62, 0.55, 0.44, 1), 0.95)
GLASS = C.mat('L dark window', (0.05, 0.06, 0.07, 1), 0.4)

def box(name, loc, size, mat, solid=False, bevel=0.02, role=None):
    o = C.box(name, loc, size, mat, bevel)
    if solid: COLLISIONS.append((name, tuple(loc), tuple(size)))
    if role: o['part_role'] = role
    return o

W, D = 8.0, 7.0            # walls, X by Y
T = 0.5                    # wall thickness
G = 3.0                    # ground storey height (floor 0 .. 3.0)
WALL_TOP = G + 0.12         # ground walls reach the upper floor's underside (Codex LH04: a 12 cm slot ran round the house
                           # between the wall tops at 3.0 and the floor slab, open in the stair well)
U = 2.7                    # upper storey
JET = 0.30                 # upper floor jetty over the front (-Y)
x0, x1, y0, y1 = -W / 2, W / 2, -D / 2, D / 2

# --- floor, plinth
box('floor', (0, 0, -0.1), (W, D, 0.2), STONE, True, 0)
box('plinth back', (0, D / 2 + 0.04, 0.25), (W + 0.16, 0.12, 0.5), STONE)
for side in (-1, 1):
    box('plinth sides', (side * (W / 2 + 0.04), 0, 0.25), (0.12, D + 0.16, 0.5), STONE)

# --- ground storey: plastered masonry with a door and a shop window on the front
def wall_x(name, y, a, b, z0, z1, mat=PLASTER):
    return box(name, ((a + b) / 2, y, (z0 + z1) / 2), (b - a, T, z1 - z0), mat, True)
def wall_y(name, x, a, b, z0, z1, mat=PLASTER):
    return box(name, (x, (a + b) / 2, (z0 + z1) / 2), (T, b - a, z1 - z0), mat, True)
yf, yb = y0 + T / 2, y1 - T / 2
DOOR = (-1.8, 1.2, 2.3)        # centre x, width, height
SHOP = (1.6, 1.8, 1.0, 2.1)    # centre x, width, sill, top
wall_x('front pier W', yf, x0, DOOR[0] - DOOR[1] / 2, 0, WALL_TOP)
wall_x('front pier mid', yf, DOOR[0] + DOOR[1] / 2, SHOP[0] - SHOP[1] / 2, 0, WALL_TOP)
wall_x('front pier E', yf, SHOP[0] + SHOP[1] / 2, x1, 0, WALL_TOP)
wall_x('door head', yf, DOOR[0] - DOOR[1] / 2, DOOR[0] + DOOR[1] / 2, DOOR[2], WALL_TOP)
wall_x('shop sill wall', yf, SHOP[0] - SHOP[1] / 2, SHOP[0] + SHOP[1] / 2, 0, SHOP[2])
wall_x('shop head', yf, SHOP[0] - SHOP[1] / 2, SHOP[0] + SHOP[1] / 2, SHOP[3], WALL_TOP)
# front plinth on either side of the doorway (it ran across it: a 0.5 m stone band the hero walked
# through), a low threshold stone in the opening
dl, dr = DOOR[0] - DOOR[1] / 2 - 0.2, DOOR[0] + DOOR[1] / 2 + 0.2
box('plinth front', ((x0 - 0.08 + dl) / 2, -(D / 2 + 0.04), 0.25), (dl - x0 + 0.08, 0.12, 0.5), STONE)
box('plinth front', ((dr + x1 + 0.08) / 2, -(D / 2 + 0.04), 0.25), (x1 + 0.08 - dr, 0.12, 0.5), STONE)
box('threshold stone', (DOOR[0], y0 - 0.035, 0.025), (DOOR[1], 0.22, 0.05), STONE, bevel=0.01)   # in front of the shut leaf
box('door frame top', (DOOR[0], y0 - 0.02, DOOR[2] + 0.12), (DOOR[1] + 0.4, 0.14, 0.22), STONE)
for sx in (-1, 1):
    box('door jamb stone', (DOOR[0] + sx * (DOOR[1] / 2 + 0.1), y0 - 0.02, DOOR[2] / 2), (0.2, 0.14, DOOR[2]), STONE)
# The entry leaf, shut in the doorway, hangs on an empty named *_entry_hinge: the game's shared
# village_door.gd swings it (Codex's D-H/S-H contract); its parts stay separate meshes.
hinge = bpy.data.objects.new('L_entry_hinge', None); C.ASSET.objects.link(hinge)
DOOR_Y = y0 + 0.12
hinge.location = (DOOR[0] - DOOR[1] / 2, DOOR_Y, 0); hinge['open_angle_degrees'] = -95.0   # village_door: the leaf swings away from the actor
door_parts = []
for k in range(4):
    door_parts.append(box('Door entry plank', (DOOR[0] - DOOR[1] / 2 + 0.15 + k * 0.29, DOOR_Y, 1.14), (0.285, 0.07, 2.26), TIMBER, bevel=0.01))
for z in (0.45, 1.8):
    door_parts.append(box('Door iron strap', (DOOR[0], DOOR_Y - 0.045, z), (DOOR[1] - 0.08, 0.018, 0.06), IRON, bevel=0))
# shop window: sill board, two shutters folded open, counter inside
box('shop sill board', (SHOP[0], y0 - 0.15, SHOP[2] + 0.04), (SHOP[1] + 0.2, 0.42, 0.08), TIMBER)
for sx in (-1, 1):
    box('shop shutter', (SHOP[0] + sx * (SHOP[1] / 2 + 0.47), y0 - 0.06, (SHOP[2] + SHOP[3]) / 2), (0.9, 0.06, SHOP[3] - SHOP[2]), TIMBER)
box('shop counter', (SHOP[0], y0 + T + 0.35, 0.95), (SHOP[1], 0.6, 0.08), TIMBER, True, role='interior_furniture')
wall_x('rear wall', yb, x0, x1, 0, WALL_TOP)
wall_y('west wall', x0 + T / 2, y0 + T, y1 - T, 0, WALL_TOP)
# east wall with one window
wall_y('east wall S', x1 - T / 2, y0 + T, -0.6, 0, WALL_TOP); wall_y('east wall N', x1 - T / 2, 0.6, y1 - T, 0, WALL_TOP)
wall_y('east sill', x1 - T / 2, -0.6, 0.6, 0, 1.1); wall_y('east head', x1 - T / 2, -0.6, 0.6, 2.0, WALL_TOP)
box('east window', (x1 - 0.05, 0, 1.55), (0.05, 1.2, 0.9), GLASS)
for k in (-1, 1): box('east shutter', (x1 + 0.03, k * 0.9, 1.55), (0.05, 0.6, 0.95), TIMBER)

# --- floor beam between storeys, jetty on the front
box('storey beam front', (0, y0 - JET + 0.15, G + 0.12), (W + 0.3, 0.32, 0.24), TIMBER)
for k in range(9):
    x = x0 + 0.2 + k * (W - 0.4) / 8
    box('joist end', (x, y0 - JET + 0.05, G - 0.08), (0.16, 0.5, 0.16), TIMBER)
# Stair (west wall, rising to the front): 14 equal risers to the upper floor top FLOOR_TOP.
FLOOR_TOP = G + 0.24
RISERS = 14
RISE = FLOOR_TOP / RISERS                  # 0.2314 m
RUN = 0.27
SX0, SX1 = x0 + T, x0 + T + 0.9           # stair width along the west wall
STEP0 = 2.015                             # first tread centre (y); the foot leaves 0.7 m to the rear wall
def tread_y(k): return STEP0 - k * RUN
OPEN_Y0 = tread_y(RISERS - 2) - RUN / 2   # visual floor edge = the last riser
SLOPE = RISE / RUN
RAMP_Y0 = STEP0 + RISE / SLOPE            # ramp through the tread centres: z 0 here ...
RAMP_Y1 = RAMP_Y0 - FLOOR_TOP / SLOPE     # ... and FLOOR_TOP here (just under the landing floor)
OPEN_Y1 = y1 - T - 0.05                   # the opening reaches the rear wall
FY0, FY1 = y0 - JET, y1                   # upper floor extent (y)
def floor_piece(name, xa, xb, ya, yb, z, th, mat, role=None):
    return box(name, ((xa + xb) / 2, (ya + yb) / 2, z), (xb - xa, yb - ya, th), mat, False, 0, role)
OX1 = SX1 + 0.05
floor_piece('upper floor', OX1, x1, FY0, FY1, G + 0.18, 0.12, BOARDS)
floor_piece('upper floor', x0, OX1, FY0, OPEN_Y0, G + 0.18, 0.12, BOARDS)
floor_piece('upper floor', x0, OX1, OPEN_Y1, FY1, G + 0.18, 0.12, BOARDS)
for name, xa, xb, ya, yb in (('upper floor', OX1, x1, FY0, FY1), ('upper floor', x0, OX1, FY0, RAMP_Y1),
                             ('upper floor', x0, OX1, OPEN_Y1, FY1)):
    COLLISIONS.append((name, ((xa + xb) / 2, (ya + yb) / 2, G + 0.18), (xb - xa, yb - ya, 0.12)))

# --- upper storey: timber frame with plaster infill
yu = y0 - JET
WIN = (0.8, G + 0.95, G + 1.85)          # upper window width, sill, head
WIN_X = (-1.0, 1.0)                       # in the two middle bays of the front
def frame_x(name, y, z0, z1, windows=(), out=-1):
    # out: the outside direction (-1 front, +1 rear) - the timbers sit on the outer face
    if not windows:
        box(name + ' infill', (0, y, (z0 + z1) / 2), (W, 0.22, z1 - z0), PLASTER, True)
    else:
        box(name + ' infill low', (0, y, (z0 + WIN[1]) / 2), (W, 0.22, WIN[1] - z0), PLASTER, True)
        box(name + ' infill high', (0, y, (WIN[2] + z1) / 2), (W, 0.22, z1 - WIN[2]), PLASTER, True)
        edges = [x0] + [e for cx in windows for e in (cx - WIN[0] / 2, cx + WIN[0] / 2)] + [x1]
        for a, b in zip(edges[0::2], edges[1::2]):
            box(name + ' infill pier', ((a + b) / 2, y, (WIN[1] + WIN[2]) / 2), (b - a, 0.22, WIN[2] - WIN[1]), PLASTER, True)
    for k in range(5):
        x = x0 + k * W / 4
        box(name + ' post', (x if abs(x) < W / 2 else x * 0.985, y + out * 0.06, (z0 + z1) / 2), (0.2, 0.18, z1 - z0), TIMBER)
    box(name + ' sill', (0, y + out * 0.06, z0 + 0.1), (W, 0.2, 0.2), TIMBER)
    box(name + ' plate', (0, y + out * 0.06, z1 - 0.1), (W, 0.2, 0.2), TIMBER)
    for k in range(4):
        xa = x0 + k * W / 4 + 0.12; xb = xa + W / 4 - 0.24
        if any(xa < cx < xb for cx in windows):
            continue
        if k % 2 == 0:
            C.beam(name + ' brace', (xa, y + out * 0.08, z0 + 0.2), (xb, y + out * 0.08, z1 - 0.2), 0.14, 0.14, TIMBER)
        else:
            C.beam(name + ' brace', (xa, y + out * 0.08, z1 - 0.2), (xb, y + out * 0.08, z0 + 0.2), 0.14, 0.14, TIMBER)
frame_x('upper front', yu + 0.11, G + 0.24, G + U, WIN_X)
frame_x('upper rear', y1 - 0.11, G + 0.24, G + U, out=1)
for sx in (-1, 1):
    x = sx * (W / 2 - 0.11)
    box('upper side infill', (x, -JET / 2, G + 0.24 + (U - 0.24) / 2), (0.22, D + JET, U - 0.24), PLASTER, True)
    for k in range(4):
        y = yu + k * (D + JET) / 3
        box('upper side post', (x + sx * 0.06, y, G + 0.24 + (U - 0.24) / 2), (0.18, 0.2, U - 0.24), TIMBER)
# two upper windows on the front: real openings, a four-bar frame round them, recessed panes
# with a muntin cross, shutters folded open against the wall
wy = yu + 0.11
wz = (WIN[1] + WIN[2]) / 2
wh = WIN[2] - WIN[1]
for cx in WIN_X:
    box('upper window pane', (cx, wy + 0.04, wz), (WIN[0], 0.03, wh), GLASS)
    box('upper window muntin', (cx, wy - 0.01, wz), (0.05, 0.05, wh), TIMBER)
    box('upper window muntin', (cx, wy - 0.01, wz), (WIN[0], 0.05, 0.05), TIMBER)
    for sz in (-1, 1):
        box('upper window frame', (cx, wy - 0.14, wz + sz * (wh / 2 + 0.06)), (WIN[0] + 0.24, 0.1, 0.12), TIMBER)
        box('upper window frame', (cx + sz * (WIN[0] / 2 + 0.06), wy - 0.14, wz), (0.12, 0.1, wh), TIMBER)
        box('upper window shutter', (cx + sz * (WIN[0] / 2 + 0.33), wy - 0.2, wz), (0.4, 0.05, wh), TIMBER)
    box('upper window sill', (cx, wy - 0.2, WIN[1] - 0.04), (WIN[0] + 0.3, 0.22, 0.06), TIMBER)

# --- steep gable roof (ridge along X), clay tile rows, overhang 0.5 m
top = G + U
half = (D + JET) / 2 + 0.5
ridge = top + half * math.tan(math.radians(42))
cy = -JET / 2
for side in (-1, 1):
    rows = 14
    for r in range(rows):
        t0 = r / rows; t1 = (r + 1) / rows + 0.02
        ya, yb2 = cy + side * half * (1 - t0), cy + side * half * (1 - t1)
        za, zb = top + (ridge - top) * t0 - 0.05, top + (ridge - top) * t1 - 0.05
        verts = [(x0 - 0.5, ya, za), (x1 + 0.5, ya, za), (x1 + 0.5, yb2, zb), (x0 - 0.5, yb2, zb),
                 (x0 - 0.5, ya, za + 0.06), (x1 + 0.5, ya, za + 0.06), (x1 + 0.5, yb2, zb + 0.06), (x0 - 0.5, yb2, zb + 0.06)]
        faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        if side < 0: faces = [tuple(reversed(f)) for f in faces]   # outward normals on both slopes
        C.mesh('roof tile row', verts, faces, TILE if r % 2 == 0 else TILE2)
box('ridge tiles', (0, cy, ridge + 0.04), (W + 1.1, 0.34, 0.18), TILE2)
# eaves blocking: the front and rear upper walls reach up under the tiles (Godot frames: a 0.5 m slot
# of sky between the wall plate and the roof), the top following the slope
def roof_under(y):
    return top + (ridge - top) * (half - abs(y - cy)) / half - 0.06
for ya, yb in ((yu, yu + 0.22), (y1 - 0.22, y1)):
    v = [(x0, ya, top), (x1, ya, top), (x1, yb, top), (x0, yb, top),
         (x0, ya, roof_under(ya)), (x1, ya, roof_under(ya)), (x1, yb, roof_under(yb)), (x0, yb, roof_under(yb))]
    C.mesh('eaves blocking', v, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], PLASTER)
# the roof over the living room (Codex 151: bare tile undersides upstairs): board sheathing under
# the tiles between the gables, rafters every metre and a ridge beam - the book's dark timber
ix0, ix1 = x0 + 0.22, x1 - 0.22
for ya in (yu + 0.22, y1 - 0.22):
    za, zr = roof_under(ya) - 0.02, roof_under(cy) - 0.02
    v = [(ix0, ya, za), (ix1, ya, za), (ix1, cy, zr), (ix0, cy, zr)]
    v += [(x, y, z - 0.03) for x, y, z in v]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    if ya > cy: faces = [tuple(reversed(f)) for f in faces]
    C.mesh('roof sheathing', v, faces, BOARDS)
    n = 7
    for k in range(n + 1):
        x = ix0 + 0.1 + k * (ix1 - ix0 - 0.2) / n
        C.beam('rafter', (x, ya, za - 0.12), (x, cy, zr - 0.12), 0.12, 0.16, TIMBER)
C.beam('ridge beam', (ix0, cy, roof_under(cy) - 0.16), (ix1, cy, roof_under(cy) - 0.16), 0.18, 0.22, TIMBER)
# gable triangles in plaster with timber edge boards
for sx in (-1, 1):
    x = sx * (W / 2 - 0.11)
    # up to the underside of the tiles (Godot frames: a 0.2-0.4 m slot of sky along both gables)
    yz = [(yu, top), (y1, top), (y1, roof_under(y1)), (cy, roof_under(cy)), (yu, roof_under(yu))]
    v2 = [(x - 0.11, y, z) for y, z in yz] + [(x + 0.11, y, z) for y, z in yz]
    C.mesh('gable infill', v2, [(4, 3, 2, 1, 0), (5, 6, 7, 8, 9)] + [(i, (i + 1) % 5, (i + 1) % 5 + 5, i + 5) for i in range(5)], PLASTER)
    COLLISIONS.append(('gable', (x, cy, top + (ridge - top) / 3), (0.22, D + JET - 1.0, (ridge - top) * 0.6)))
# the roof's collision is its own volume: a prism from the eaves to the ridge
COLLISION_MESHES.append(('roof', [(x0 - 0.5, cy - half, top), (x1 + 0.5, cy - half, top), (x1 + 0.5, cy + half, top),
                                  (x0 - 0.5, cy + half, top), (x0 - 0.5, cy, ridge), (x1 + 0.5, cy, ridge)],
                         [(0, 1, 2, 3), (0, 4, 5, 1), (3, 2, 5, 4), (0, 3, 4), (1, 5, 2)]))

# --- chimney through the rear slope, from the ground-floor hearth
# the stack rises from the hearth hood (2.7 m) through the upper room and the rear slope
box('chimney', (2.6, 2.3, (ridge + 0.9 + 2.7) / 2), (0.7, 0.7, ridge + 0.9 - 2.7), STONE, True)
box('chimney cap', (2.6, 2.3, ridge + 1.05), (0.9, 0.9, 0.12), STONE)

# --- interior (ground floor): hearth, table, bench, straight stair to the upper floor
box('hearth', (2.6, 2.75, 0.55), (1.4, 0.9, 1.1), STONE, True)
box('hearth hood', (2.6, 2.75, 1.9), (1.2, 0.9, 1.6), STONE)
box('table', (-0.4, 1.0, 0.76), (1.6, 0.8, 0.08), TIMBER, True, role='interior_furniture')
for x in (-1.1, 0.3):
    for y in (0.7, 1.3): box('table leg', (x, y, 0.36), (0.09, 0.09, 0.72), TIMBER, role='interior_furniture')
box('bench', (-0.4, 0.3, 0.42), (1.5, 0.35, 0.07), TIMBER, True, role='interior_furniture')
box('sack', (1.0, 2.7, 0.3), (0.5, 0.4, 0.6), CLOTH, role='interior_furniture')
# stair along the west wall: 13 treads + the upper floor = 14 equal risers; boarded understair.
# The walking surface is a ramp through the tread centres (40.6 deg, under the 45 deg floor limit),
# its top tucked under the landing floor so the step onto the floor is smooth.
scx = (SX0 + SX1) / 2
for k in range(RISERS - 1):
    zt = (k + 1) * RISE
    box('stair tread', (scx, tread_y(k), zt - 0.03), (SX1 - SX0, RUN + 0.03, 0.06), TIMBER, bevel=0.01)
    box('stair riser', (scx, tread_y(k) + RUN / 2 - 0.015, zt - RISE / 2), (SX1 - SX0 - 0.02, 0.03, RISE - 0.06), TIMBER, bevel=0)
side = SX1 + 0.02
C.mesh('understair boards', [(side - 0.02, RAMP_Y0 - 0.25, 0), (side - 0.02, OPEN_Y0, 0), (side - 0.02, OPEN_Y0, FLOOR_TOP - RISE - 0.08),
                             (side + 0.02, RAMP_Y0 - 0.25, 0), (side + 0.02, OPEN_Y0, 0), (side + 0.02, OPEN_Y0, FLOOR_TOP - RISE - 0.08)],
       [(0, 2, 1), (3, 4, 5), (0, 3, 5, 2), (1, 2, 5, 4), (0, 1, 4, 3)], TIMBER)
C.beam('stair rail', (side + 0.03, STEP0 + 0.1, 1.05), (side + 0.03, OPEN_Y0 + 0.05, FLOOR_TOP + 0.9), 0.07, 0.07, TIMBER)
for k in (0, 6, 12):
    C.beam('stair baluster', (side + 0.03, tread_y(k), (k + 1) * RISE), (side + 0.03, tread_y(k), (k + 1) * RISE + 0.95), 0.06, 0.06, TIMBER)
COLLISION_MESHES.append(('stair ramp', [(SX0, RAMP_Y0, 0), (SX1, RAMP_Y0, 0), (SX1, RAMP_Y1, 0), (SX0, RAMP_Y1, 0),
                                        (SX0, RAMP_Y1, FLOOR_TOP), (SX1, RAMP_Y1, FLOOR_TOP)],
                         [(0, 3, 2, 1), (0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5)]))
# ground-floor ceiling with the stair opening
cx0, cx1, cy0, cy1 = x0 + T, x1 - T, y0 + T, y1 - T
floor_piece('ceiling', OX1, cx1, cy0, cy1, G + 0.05, 0.06, TIMBER, 'ceiling')
floor_piece('ceiling', cx0, OX1, cy0, OPEN_Y0, G + 0.05, 0.06, TIMBER, 'ceiling')
# upstairs: a rail round the opening, a bed, a chest and a stool
ux0 = x0 + 0.22
box('landing rail', (OX1 + 0.03, (OPEN_Y0 + 0.6 + OPEN_Y1) / 2, FLOOR_TOP + 0.95), (0.07, OPEN_Y1 - OPEN_Y0 - 0.6, 0.07), TIMBER)
box('landing rail', ((ux0 + OX1) / 2, OPEN_Y1 + 0.03, FLOOR_TOP + 0.95), (OX1 - ux0, 0.07, 0.07), TIMBER)
for y in (OPEN_Y0 + 0.6, (OPEN_Y0 + OPEN_Y1) / 2, OPEN_Y1):
    box('landing post', (OX1 + 0.03, y, FLOOR_TOP + 0.48), (0.08, 0.08, 0.96), TIMBER)
COLLISIONS.append(('landing rail', (OX1 + 0.03, (OPEN_Y0 + 0.6 + OPEN_Y1) / 2, FLOOR_TOP + 0.5), (0.1, OPEN_Y1 - OPEN_Y0 - 0.6, 1.0)))
ex = x1 - 0.22                             # upper east wall inner face
box('bed frame', (ex - 0.5, -1.7, FLOOR_TOP + 0.2), (0.95, 2.0, 0.4), TIMBER, True, role='interior_furniture')
box('bed straw', (ex - 0.5, -1.7, FLOOR_TOP + 0.44), (0.85, 1.9, 0.1), CLOTH, role='interior_furniture')
box('bed head', (ex - 0.5, -2.72, FLOOR_TOP + 0.5), (0.95, 0.06, 1.0), TIMBER, role='interior_furniture')
box('chest', (0.9, y1 - 0.22 - 0.25, FLOOR_TOP + 0.25), (0.9, 0.48, 0.5), TIMBER, True, role='interior_furniture')
box('chest band', (0.9, y1 - 0.22 - 0.25, FLOOR_TOP + 0.4), (0.92, 0.5, 0.05), IRON, role='interior_furniture')
box('stool', (2.0, -2.8, FLOOR_TOP + 0.22), (0.4, 0.4, 0.44), TIMBER, role='interior_furniture')

# --- join, collisions, export
visual = [o for o in C.ASSET.objects if o.type == 'MESH']
# shell by material; the interior furniture by material too (the game hides it from afar);
# the door's parts stay apart, then go under the hinge
C._join_by_material([o for o in visual if not o.get('part_role') and o not in door_parts])
C._join_by_material([o for o in C.ASSET.objects if o.type == 'MESH' and o.get('part_role') == 'interior_furniture'])
for o in door_parts:
    matrix = o.matrix_world.copy(); o.parent = hinge; o.matrix_world = matrix
visual = [o for o in C.ASSET.objects if o.type == 'MESH']
# world-scale cube UVs so the photo textures keep their size on every face
for o in visual:
    m = o.data.materials[0] if o.data.materials else None
    s = float(m.get('uv_scale', 0)) if m else 0
    if not s: continue
    bm = bmesh.new(); bm.from_mesh(o.data)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal; ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            p = o.matrix_world @ l.vert.co
            a, b = [(p.y, p.z), (p.x, p.z), (p.x, p.y)][ax]
            l[uv].uv = (a * s, b * s)
    bm.to_mesh(o.data); bm.free()
for name, loc, size in COLLISIONS:
    o = box(name + '-colonly', loc, size, PLASTER, False, 0)
    o.hide_render = True; o['collision_only'] = True
for name, verts, faces in COLLISION_MESHES:
    o = C.mesh(name + '-colonly', verts, faces, PLASTER)
    o.hide_render = True; o['collision_only'] = True
all_mesh = list(C.ASSET.objects)
bpy.ops.object.select_all(action='DESELECT')
for o in all_mesh: o.select_set(True)
bpy.context.view_layer.objects.active = visual[0]
path = OUT / 'l_town_house.glb'
bpy.ops.export_scene.gltf(filepath=str(path), use_selection=True, export_format='GLB', export_apply=True, export_yup=True,
                          export_materials='EXPORT', export_cameras=False, export_lights=False, export_extras=True)
tris = 0
for o in visual: o.data.calc_loop_triangles(); tris += len(o.data.loop_triangles)
points = [o.matrix_world @ Vector(c) for o in visual for c in o.bound_box]
mn = [min(p[i] for p in points) for i in range(3)]; mx = [max(p[i] for p in points) for i in range(3)]
stats = {'triangles': tris, 'visual_meshes': len(visual), 'collision_boxes': len(COLLISIONS), 'bbox_blender': [mn, mx],
         'full_bbox_m': [round(mx[i] - mn[i], 3) for i in range(3)], 'wall_footprint': [W, D],
         'stair': {'risers': RISERS, 'rise': round(RISE, 4), 'run': RUN, 'ramp_y': [round(RAMP_Y0, 3), round(RAMP_Y1, 3)],
                   'opening_y': [round(OPEN_Y0, 3), round(OPEN_Y1, 3)], 'floor_top': FLOOR_TOP},
         'collision_meshes': len(COLLISION_MESHES), 'door_clear': [DOOR[1], DOOR[2]], 'ridge_m': round(ridge, 2), 'godot_front': [0, 0, 1],
         'pivot': 'floor centre', 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size,
         'approval': 'PDF141 D118; awaiting Codex 3D acceptance'}
(QA / 'stats.json').write_text(json.dumps(stats, indent=2), encoding='utf-8')
C.ASSET.objects.unlink(hinge)   # _studio() measures every ASSET object's vertices; the empty has none
C._studio()
C.ASSET.objects.link(hinge)
sc = bpy.context.scene
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = 24; sc.cycles.use_denoising = True
sc.render.resolution_x = 1280; sc.render.resolution_y = 960
sc.view_settings.view_transform = 'AgX'
cam = sc.camera; cam.rotation_mode = 'XYZ'; cam.data.type = 'PERSP'; cam.data.lens = 40
def view(name, pos, target):
    cam.location = pos; cam.rotation_euler = (Vector(target) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = str(QA / (name + '.png')); bpy.ops.render.render(write_still=True)
view('front', (6, -15, 4.5), (0, 0, 3.5))
view('corner', (13, -11, 7), (0, 0, 3.5))
view('rear', (-10, 13, 6), (0, 0, 3.5))
view('entry', (-1.8, -6, 1.7), (-1.8, 1, 1.4))
# cut-away views of the stair and the upper room (the roof tiles hidden)
for o in C.ASSET.objects:
    if o.type != 'MESH' or o.get('collision_only'): continue
    if o.data.materials and o.data.materials[0].name.startswith('L clay roof tile'): o.hide_render = True
cam.data.lens = 22
view('upper-room', (5.0, -7.0, 9.5), (-0.3, 0.3, FLOOR_TOP))
view('stair', (2.6, -3.6, 7.6), (-3.0, 0.6, 1.4))
bpy.ops.wm.save_as_mainfile(filepath=str(QA / 'l_town_house.blend'))
print('L_H_ASSET_BUILT', json.dumps(stats))
