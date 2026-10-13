"""L-H: lowland town house of the Council (WORLD-PLAN-01, D-118; architecture.md module L-H, plate L).
Plastered stone ground floor (shop allowed), dark timber-framed upper floor with a small jetty,
steep tiled gable roof, stone chimney. Walls 8 x 7 m, ridge ~9.6 m.
Run: blender --background --factory-startup --python-exit-code 1 --python this_file
Blender: XY footprint, Z up, entry on -Y; the GLB export turns it to Godot Y up, entry +Z. Pivot: floor centre.
Photo textures (CC0, already in the project) with world-scale cube UVs; furniture tagged part_role=furniture
so the game's closed variant can drop it. Renders and stats stay in local/ (D-080).
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
ROLE = {}          # object name -> part_role

def photo(name, stem, tint=(1, 1, 1), rough=0.92, scale=1.0):
    """Principled material on a CC0 photo texture; colour multiplied by tint."""
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    nt = mat.node_tree; bsdf = nt.nodes.get('Principled BSDF')
    tex = nt.nodes.new('ShaderNodeTexImage'); tex.image = bpy.data.images.load(str(TEX / f'{stem}_diff_1k.jpg' if (TEX / f'{stem}_diff_1k.jpg').exists() else TEX / f'{stem}_col_1k.jpg'))
    mix = nt.nodes.new('ShaderNodeMixRGB'); mix.blend_type = 'MULTIPLY'; mix.inputs[0].default_value = 1.0
    mix.inputs[2].default_value = (*tint, 1)
    nt.links.new(tex.outputs['Color'], mix.inputs[1]); nt.links.new(mix.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = rough
    mat['uv_scale'] = scale
    return mat

PLASTER = photo('L warm plaster', 'plaster_grey_04', (1.18, 1.04, 0.80), 0.95, 0.5)
STONE = photo('L grey stone', 'stone_wall_02', (0.80, 0.80, 0.82), 0.95, 0.6)
TIMBER = photo('L dark timber', 'fine_grained_wood', (0.30, 0.22, 0.17), 0.85, 1.2)
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
U = 2.7                    # upper storey
JET = 0.30                 # upper floor jetty over the front (-Y)
x0, x1, y0, y1 = -W / 2, W / 2, -D / 2, D / 2

# --- floor, plinth
box('floor', (0, 0, -0.1), (W, D, 0.2), STONE, True, 0)
for side in (-1, 1):
    box('plinth front back', (0, side * (D / 2 + 0.04), 0.25), (W + 0.16, 0.12, 0.5), STONE)
    box('plinth sides', (side * (W / 2 + 0.04), 0, 0.25), (0.12, D + 0.16, 0.5), STONE)

# --- ground storey: plastered masonry with a door and a shop window on the front
def wall_x(name, y, a, b, z0, z1, mat=PLASTER):
    return box(name, ((a + b) / 2, y, (z0 + z1) / 2), (b - a, T, z1 - z0), mat, True)
def wall_y(name, x, a, b, z0, z1, mat=PLASTER):
    return box(name, (x, (a + b) / 2, (z0 + z1) / 2), (T, b - a, z1 - z0), mat, True)
yf, yb = y0 + T / 2, y1 - T / 2
DOOR = (-1.8, 1.2, 2.3)        # centre x, width, height
SHOP = (1.6, 1.8, 1.0, 2.1)    # centre x, width, sill, top
wall_x('front pier W', yf, x0, DOOR[0] - DOOR[1] / 2, 0, G)
wall_x('front pier mid', yf, DOOR[0] + DOOR[1] / 2, SHOP[0] - SHOP[1] / 2, 0, G)
wall_x('front pier E', yf, SHOP[0] + SHOP[1] / 2, x1, 0, G)
wall_x('door head', yf, DOOR[0] - DOOR[1] / 2, DOOR[0] + DOOR[1] / 2, DOOR[2], G)
wall_x('shop sill wall', yf, SHOP[0] - SHOP[1] / 2, SHOP[0] + SHOP[1] / 2, 0, SHOP[2])
wall_x('shop head', yf, SHOP[0] - SHOP[1] / 2, SHOP[0] + SHOP[1] / 2, SHOP[3], G)
box('door frame top', (DOOR[0], y0 - 0.02, DOOR[2] + 0.12), (DOOR[1] + 0.4, 0.14, 0.22), STONE)
for sx in (-1, 1):
    box('door jamb stone', (DOOR[0] + sx * (DOOR[1] / 2 + 0.1), y0 - 0.02, DOOR[2] / 2), (0.2, 0.14, DOOR[2]), STONE)
# open door leaf against the inner wall (the doorway stays 1.2 m clear)
for k in range(4):
    box('door plank', (DOOR[0] - DOOR[1] / 2 - 0.04 - k * 0.0, y0 + T + 0.05 + k * 0.3, 1.15), (0.06, 0.29, 2.25), TIMBER, role=None)
box('door strap', (DOOR[0] - DOOR[1] / 2 + 0.0, y0 + T + 0.5, 0.5), (0.02, 1.1, 0.06), IRON)
# shop window: sill board, two shutters folded open, counter inside
box('shop sill board', (SHOP[0], y0 - 0.15, SHOP[2] + 0.04), (SHOP[1] + 0.2, 0.42, 0.08), TIMBER)
for sx in (-1, 1):
    box('shop shutter', (SHOP[0] + sx * (SHOP[1] / 2 + 0.47), y0 - 0.06, (SHOP[2] + SHOP[3]) / 2), (0.9, 0.06, SHOP[3] - SHOP[2]), TIMBER)
box('shop counter', (SHOP[0], y0 + T + 0.35, 0.95), (SHOP[1], 0.6, 0.08), TIMBER, True, role='furniture')
wall_x('rear wall', yb, x0, x1, 0, G)
wall_y('west wall', x0 + T / 2, y0 + T, y1 - T, 0, G)
# east wall with one window
wall_y('east wall S', x1 - T / 2, y0 + T, -0.6, 0, G); wall_y('east wall N', x1 - T / 2, 0.6, y1 - T, 0, G)
wall_y('east sill', x1 - T / 2, -0.6, 0.6, 0, 1.1); wall_y('east head', x1 - T / 2, -0.6, 0.6, 2.0, G)
box('east window', (x1 - 0.05, 0, 1.55), (0.05, 1.2, 0.9), GLASS)
for k in (-1, 1): box('east shutter', (x1 + 0.03, k * 0.9, 1.55), (0.05, 0.6, 0.95), TIMBER)

# --- floor beam between storeys, jetty on the front
box('storey beam front', (0, y0 - JET + 0.15, G + 0.12), (W + 0.3, 0.32, 0.24), TIMBER)
for k in range(9):
    x = x0 + 0.2 + k * (W - 0.4) / 8
    box('joist end', (x, y0 - JET + 0.05, G - 0.08), (0.16, 0.5, 0.16), TIMBER)
box('upper floor', (0, -JET / 2, G + 0.18), (W, D + JET, 0.12), TIMBER, True, 0)

# --- upper storey: timber frame with plaster infill
yu = y0 - JET
def frame_x(name, y, z0, z1):
    box(name + ' infill', (0, y, (z0 + z1) / 2), (W, 0.22, z1 - z0), PLASTER, True)
    for k in range(5):
        x = x0 + k * W / 4
        box(name + ' post', (x if abs(x) < W / 2 else x * 0.985, y - 0.06, (z0 + z1) / 2), (0.2, 0.18, z1 - z0), TIMBER)
    box(name + ' sill', (0, y - 0.06, z0 + 0.1), (W, 0.2, 0.2), TIMBER)
    box(name + ' plate', (0, y - 0.06, z1 - 0.1), (W, 0.2, 0.2), TIMBER)
    for k in range(4):
        xa = x0 + k * W / 4 + 0.12; xb = xa + W / 4 - 0.24
        C.beam(name + ' brace', (xa, y - 0.08, z0 + 0.2), (xb, y - 0.08, z1 - 0.2) if k % 2 == 0 else (xb, y - 0.08, z0 + 0.2), 0.14, 0.14, TIMBER) if False else None
        if k % 2 == 0:
            C.beam(name + ' brace', (xa, y - 0.08, z0 + 0.2), (xb, y - 0.08, z1 - 0.2), 0.14, 0.14, TIMBER)
        else:
            C.beam(name + ' brace', (xa, y - 0.08, z1 - 0.2), (xb, y - 0.08, z0 + 0.2), 0.14, 0.14, TIMBER)
frame_x('upper front', yu + 0.11, G + 0.24, G + U)
frame_x('upper rear', y1 - 0.11, G + 0.24, G + U)
for sx in (-1, 1):
    x = sx * (W / 2 - 0.11)
    box('upper side infill', (x, -JET / 2, G + 0.24 + (U - 0.24) / 2), (0.22, D + JET, U - 0.24), PLASTER, True)
    for k in range(4):
        y = yu + k * (D + JET) / 3
        box('upper side post', (x + sx * 0.06, y, G + 0.24 + (U - 0.24) / 2), (0.18, 0.2, U - 0.24), TIMBER)
# two upper windows on the front
for cx in (-2.0, 2.0):
    box('upper window', (cx, yu - 0.01, G + 1.4), (0.8, 0.05, 0.9), GLASS)
    box('upper window frame', (cx, yu - 0.04, G + 1.4), (1.0, 0.06, 1.1), TIMBER)

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
# gable triangles in plaster with timber edge boards
for sx in (-1, 1):
    x = sx * (W / 2 - 0.11)
    verts = [(x, cy - half + 0.5, top), (x, cy + half - 0.5, top), (x, cy, ridge - 0.25)]
    v2 = [(x - 0.11, *p[1:]) for p in verts] + [(x + 0.11, *p[1:]) for p in verts]
    C.mesh('gable infill', v2, [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)], PLASTER)
    COLLISIONS.append(('gable', (x, cy, top + (ridge - top) / 3), (0.22, D + JET - 1.0, (ridge - top) * 0.6)))
# a roof collision slab per side (the roof is not walked on, it only blocks)
COLLISIONS.append(('roof', (0, cy, (top + ridge) / 2), (W + 1.0, D + JET + 1.0, 0.4)))

# --- chimney through the rear slope, from the ground-floor hearth
box('chimney', (2.6, 2.3, (ridge + 0.9 + G) / 2 + 0.6), (0.7, 0.7, ridge + 0.9 - G - 1.2), STONE, True)
box('chimney cap', (2.6, 2.3, ridge + 1.05), (0.9, 0.9, 0.12), STONE)

# --- interior (ground floor): hearth, table, bench, straight stair to the upper floor
box('hearth', (2.6, 2.75, 0.55), (1.4, 0.9, 1.1), STONE, True, role='furniture')
box('hearth hood', (2.6, 2.75, 1.9), (1.2, 0.9, 1.6), STONE, role='furniture')
box('table', (-0.4, 1.0, 0.76), (1.6, 0.8, 0.08), TIMBER, True, role='furniture')
for x in (-1.1, 0.3):
    for y in (0.7, 1.3): box('table leg', (x, y, 0.36), (0.09, 0.09, 0.72), TIMBER, role='furniture')
box('bench', (-0.4, 0.3, 0.42), (1.5, 0.35, 0.07), TIMBER, True, role='furniture')
box('sack', (-3.2, 2.6, 0.3), (0.5, 0.4, 0.6), CLOTH, role='furniture')
# stair along the west wall, 13 risers of 0.23 m to the upper floor
for k in range(13):
    box('stair step', (x0 + T + 0.45, y1 - T - 0.4 - k * 0.27, 0.115 + k * 0.23), (0.9, 0.3, 0.06), TIMBER, role='furniture')
COLLISIONS.append(('stair', (x0 + T + 0.45, y1 - T - 2.0, 1.5), (0.9, 3.6, 0.2)))
box('ceiling', (0, 0, G + 0.05), (W - 2 * T, D - 2 * T, 0.06), TIMBER, role='ceiling')

# --- join, collisions, export
visual = list(C.ASSET.objects)
roles = {o.name: o.get('part_role') for o in visual}
C._join_by_material([o for o in visual if not o.get('part_role')])
visual = list(C.ASSET.objects)
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
         'wall_footprint': [W, D], 'door_clear': [DOOR[1], DOOR[2]], 'ridge_m': round(ridge, 2), 'godot_front': [0, 0, 1],
         'pivot': 'floor centre', 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size,
         'approval': 'PDF141 D118; awaiting Codex 3D acceptance'}
(QA / 'stats.json').write_text(json.dumps(stats, indent=2), encoding='utf-8')
C._studio()
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
bpy.ops.wm.save_as_mainfile(filepath=str(QA / 'l_town_house.blend'))
print('L_H_ASSET_BUILT', json.dumps(stats))
