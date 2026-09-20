# AshBound build_watchtower.py - dark medieval village watchtower (Blender 5.2).
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import buildings_common as C
from mathutils import Vector

C.reset()

STONE = C.mat('stone', (0.34, 0.31, 0.27, 1), 0.95)
STONE_D = C.mat('stone_dark', (0.26, 0.24, 0.21, 1), 0.95)
OAK = C.mat('oak', (0.23, 0.16, 0.10, 1), 0.85)
OAK_D = C.mat('oak_dark', (0.16, 0.11, 0.07, 1), 0.9)
SHINGLE = C.mat('shingle', (0.13, 0.12, 0.11, 1), 0.9)

objs = []
B = 1.4          # base half-extent (full base width 2.8)
H_BASE = 2.5     # stone base top
H_PLAT = 5.5     # deck level
H_RAIL = 6.45    # railing top
H_ROOF0 = 7.0    # roof eave
H_TOP = 8.4      # apex
W_DECK = 3.5     # deck width
W_ROOF = 4.0     # roof overhang width


def stone_course(z, h):
    """One staggered beveled stone course around the full square base perimeter."""
    n = 6
    step = (2 * B) / n
    for side in range(4):
        # fixed axis coordinate: front/back at Y=+-B, left/right at X=+-B
        f = -B if side % 2 == 0 else B
        for i in range(n):
            c = -B + (i + 0.5) * step
            # slight row stagger/variation
            c += ((side + i) % 3 - 1) * 0.02
            mat = STONE if (i + side) % 2 else STONE_D
            if side < 2:  # front/back: run along X at fixed Y
                C.box('stone', (c, f, z + h / 2), (step * 0.92, 0.34, h * 0.9),
                      mat, bevel=0.05)
            else:  # left/right: run along Y at fixed X
                C.box('stone', (f, c, z + h / 2), (0.34, step * 0.92, h * 0.9),
                      mat, bevel=0.05)


# --- stone base z 0..2.5 -------------------------------------------------
# solid backing so no see-through gaps between courses
C.box('base_core', (0, 0, H_BASE / 2), (2 * B, 2 * B, H_BASE), STONE_D, bevel=0.03)
for i in range(8):
    stone_course(i * 0.3125, 0.3125)
# corner quoins
for sx in (-1, 1):
    for sy in (-1, 1):
        C.box('quoin', (sx * B, sy * B, H_BASE / 2), (0.4, 0.4, H_BASE), STONE_D, bevel=0.06)

# door on -Y front, centered
C.box('DoorFrame', (0, -B - 0.22, 1.05), (1.1, 0.12, 2.1), STONE_D, bevel=0.04)
door = C.box('Door', (0, -B - 0.25, 1.0), (0.9, 0.08, 1.9), OAK_D, bevel=0.02)
for i in range(5):
    C.box('doorplank', (0, -B - 0.30, 0.2 + i * 0.38), (0.92, 0.02, 0.3), OAK, bevel=0.01)

# arrow slits: two on front flanks, one each side
for x in (-1.0, 1.0):
    C.box('slit', (x, -B - 0.18, 1.6), (0.1, 0.08, 0.7), STONE_D, bevel=0.02)
for sx in (-1, 1):
    C.box('slit', (sx * (B + 0.18), 0, 1.6), (0.08, 0.1, 0.7), STONE_D, bevel=0.02)

# --- corner timber posts: base -> deck -----------------------------------
for sx in (-1, 1):
    for sy in (-1, 1):
        C.box('post', (sx * B, sy * B, (H_BASE + H_PLAT) / 2),
              (0.3, 0.3, H_PLAT - H_BASE), OAK_D, bevel=0.04)

# --- open timber frame with X braces --------------------------------------
def x_brace(sx, sy):
    """Diagonal X brace on one side between base top and deck."""
    a = (sx * B, sy * B, H_BASE + 0.15)
    b = (sx * B, sy * B, H_PLAT - 0.15)
    # two diagonals in the plane of the wall face
    if sx != 0:  # X/Z faces (normal along X)
        C.beam('brace', (sx * B, -B + 0.2, a[2]), (sx * B, B - 0.2, b[2]), 0.16, 0.16, OAK)
        C.beam('brace', (sx * B, B - 0.2, a[2]), (sx * B, -B + 0.2, b[2]), 0.16, 0.16, OAK)
    else:  # Y faces
        C.beam('brace', (-B + 0.2, sy * B, a[2]), (B - 0.2, sy * B, b[2]), 0.16, 0.16, OAK)
        C.beam('brace', (B - 0.2, sy * B, a[2]), (-B + 0.2, sy * B, b[2]), 0.16, 0.16, OAK)


for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
    x_brace(sx, sy)

# --- observation deck at z=5.5 --------------------------------------------
C.box('deck', (0, 0, H_PLAT - 0.1), (W_DECK, W_DECK, 0.2), OAK_D, bevel=0.03)
# plank floor lines
for i in range(7):
    C.box('plank', (-W_DECK / 2 + 0.25 + i * 0.45, 0, H_PLAT + 0.01),
          (0.38, W_DECK, 0.04), OAK, bevel=0.01)
# knee supports below deck corners
for sx in (-1, 1):
    for sy in (-1, 1):
        C.beam('knee', (sx * B, sy * B, H_BASE + 0.3),
               (sx * W_DECK / 2, sy * W_DECK / 2, H_PLAT - 0.25), 0.14, 0.14, OAK)

# railing at 6.45 with corner posts up to roof
for sx in (-1, 1):
    for sy in (-1, 1):
        C.box('railpost', (sx * W_DECK / 2, sy * W_DECK / 2, (H_PLAT + H_RAIL) / 2),
              (0.12, 0.12, H_RAIL - H_PLAT), OAK_D, bevel=0.02)
        C.box('roofpost', (sx * W_DECK / 2, sy * W_DECK / 2, (H_RAIL + H_ROOF0) / 2),
              (0.14, 0.14, H_ROOF0 - H_RAIL), OAK_D, bevel=0.02)
# rail top beams
for sx in (-1, 1):
    C.box('rail', (sx * W_DECK / 2, 0, H_RAIL), (0.1, W_DECK, 0.1), OAK, bevel=0.02)
    C.box('rail', (0, sx * W_DECK / 2, H_RAIL), (W_DECK, 0.1, 0.1), OAK, bevel=0.02)

# --- four-sided hip roof: eave z=7.0 (width 4.0) to apex z=8.4 -----------
hw = W_ROOF / 2
apex = (0, 0, H_TOP)
eaves = [(-hw, -hw, H_ROOF0), (hw, -hw, H_ROOF0), (hw, hw, H_ROOF0), (-hw, hw, H_ROOF0)]
# four slope faces (outward normals via recalc in mesh helper)
faces = []
verts = [apex] + eaves
for i in range(4):
    a, b = eaves[i], eaves[(i + 1) % 4]
    faces.append((0, 1 + i, 1 + (i + 1) % 4))
C.mesh('roof', verts, faces, SHINGLE)

# shingle rows: narrow horizontal strips on each slope, apex->eave taper
for i in range(4):
    for t in (0.2, 0.38, 0.56, 0.74, 0.92):
        p1 = Vector(apex).lerp(Vector(eaves[i]), t)
        p2 = Vector(apex).lerp(Vector(eaves[(i + 1) % 4]), t)
        C.beam('shingle', (p1.x, p1.y, p1.z + 0.03), (p2.x, p2.y, p2.z + 0.03),
               0.06, 0.06, SHINGLE)

# hip/ridge timber trim along the four hips and eave edges
for i in range(4):
    C.beam('hip', eaves[i], apex, 0.18, 0.18, OAK_D)
    C.beam('eave', eaves[i], eaves[(i + 1) % 4], 0.2, 0.2, OAK_D)

C.finish('watchtower')
