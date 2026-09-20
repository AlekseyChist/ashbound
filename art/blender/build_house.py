# AshBound build_house.py - dark medieval timber-frame dwelling (Blender 5.2 background).
import sys, math, random
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import buildings_common as C

C.reset()
random.seed(731204)

# ---- palette (<=10 materials) ----
M_STONE   = C.mat('Stone',    (0.42, 0.41, 0.39, 1), 0.95)
M_STONE_D = C.mat('StoneDark',(0.33, 0.32, 0.30, 1), 0.95)
M_PLASTER = C.mat('Plaster',  (0.62, 0.56, 0.45, 1), 0.9)
M_OAK     = C.mat('OakDark',  (0.16, 0.11, 0.07, 1), 0.85)
M_OAK_L   = C.mat('OakLight', (0.24, 0.17, 0.11, 1), 0.85)
M_SHINGLE = C.mat('Shingle',  (0.13, 0.10, 0.08, 1), 0.9)
M_SHINGLE2= C.mat('Shingle2', (0.17, 0.13, 0.10, 1), 0.9)
M_IRON    = C.mat('Iron',     (0.05, 0.05, 0.06, 1), 0.6, 0.8)
M_DOOR    = C.mat('DoorWood', (0.12, 0.08, 0.05, 1), 0.85)

# ---- plan constants (meter scale, z=0 feet, front = -Y) ----
HW, HD = 2.6, 3.0          # half width / half depth of walls
Z_FND, Z_EAVE = 1.1, 3.5   # foundation top / eave (plaster runs continuously to eave)
RIDGE_Z = 6.4
EX, EY = 3.0, 3.35         # roof eave overhang extents

# ---- 1. stone foundation: solid backing box + staggered rows on its four faces ----
C.box('FndCore', (0, 0, Z_FND / 2), (2 * HW, 2 * HD, Z_FND), M_STONE_D, 0)

def stone_row(name, axis, fixed, hlen, zc, n, mat_a, mat_b):
    """One staggered row of beveled stones on a wall face.
    axis 'x': face runs along X at fixed Y (hlen = horizontal length).
    axis 'y': face runs along Y at fixed X (hlen = horizontal length).
    zc = vertical course center height."""
    t = 0.26
    for i in range(n):
        w = hlen / n * random.uniform(0.9, 1.1)
        p = -hlen / 2 + (i + 0.5) * hlen / n
        m = mat_a if i % 2 == 0 else mat_b
        if axis == 'x':
            fy = fixed + (0.02 if fixed > 0 else -0.02)   # slight outward offset vs backing cube
            C.box(name, (p, fy, zc), (w, t, (Z_FND / 2) * 0.92), m, bevel=0.03)
        else:
            fx = fixed + (0.02 if fixed > 0 else -0.02)   # slight outward offset vs backing cube
            C.box(name, (fx, p, zc), (t, w, (Z_FND / 2) * 0.92), m, bevel=0.03)

# two staggered courses per face; front/back length 5.2, sides length 6.0
for k in range(2):
    zc = Z_FND * (k + 0.5) / 2
    stone_row('FndN', 'x',  HD - 0.13, 2 * HW, zc, 9, M_STONE, M_STONE_D)
    stone_row('FndS', 'x', -HD + 0.13, 2 * HW, zc, 9, M_STONE, M_STONE_D)
    stone_row('FndE', 'y',  HW - 0.13, 2 * HD, zc, 11, M_STONE, M_STONE_D)
    stone_row('FndW', 'y', -HW + 0.13, 2 * HD, zc, 11, M_STONE, M_STONE_D)

# ---- 2. plaster upper body: continuous from foundation top to eave (4 faces) ----
PH = Z_EAVE - Z_FND
C.box('PlasterN', (0,  HD, Z_FND + PH / 2), (2 * HW, 0.15, PH), M_PLASTER, 0)
C.box('PlasterS', (0, -HD, Z_FND + PH / 2), (2 * HW, 0.15, PH), M_PLASTER, 0)
C.box('PlasterE', ( HW, 0, Z_FND + PH / 2), (0.15, 2 * HD, PH), M_PLASTER, 0)
C.box('PlasterW', (-HW, 0, Z_FND + PH / 2), (0.15, 2 * HD, PH), M_PLASTER, 0)

# ---- timber frame: corner posts, intermediate posts, rails, braces ----
PW = 0.22
for sx in (-1, 1):
    for sy in (-1, 1):
        C.box('Post', (sx * HW, sy * HD, (Z_FND + Z_EAVE) / 2), (PW, PW, Z_EAVE - Z_FND), M_OAK)
# front/back intermediate posts (skip center x=0 so no post sits over the door)
for sx in (-1, 1):
    for px in (-1.3, 1.3):
        C.box('Post', (px, sx * HD, (Z_FND + Z_EAVE) / 2), (PW, PW, Z_EAVE - Z_FND), M_OAK)
# side intermediate posts
for sy in (-1, 1):
    for py in (-1.5, 1.5):
        C.box('Post', (sy * HW, py, (Z_FND + Z_EAVE) / 2), (PW, PW, Z_EAVE - Z_FND), M_OAK)
# horizontal rails: floor line + eave, all four walls
for z in (Z_FND + 0.05, Z_EAVE - 0.08):
    C.box('Rail', (0,  HD, z), (2 * HW, 0.16, 0.16), M_OAK)
    C.box('Rail', (0, -HD, z), (2 * HW, 0.16, 0.16), M_OAK)
    C.box('Rail', ( HW, 0, z), (0.16, 2 * HD, 0.16), M_OAK)
    C.box('Rail', (-HW, 0, z), (0.16, 2 * HD, 0.16), M_OAK)
# diagonal bracing (front, back, both sides) - placed away from openings
C.beam('Brace', (-2.45, -HD, Z_FND + 0.15), (-0.75, -HD, Z_EAVE - 0.1), 0.14, 0.14, M_OAK_L)
C.beam('Brace', ( 0.75, -HD, Z_FND + 0.15), ( 2.45, -HD, Z_EAVE - 0.1), 0.14, 0.14, M_OAK_L)
C.beam('Brace', (-2.45,  HD, Z_FND + 0.15), (-0.75,  HD, Z_EAVE - 0.1), 0.14, 0.14, M_OAK_L)
C.beam('Brace', ( 0.75,  HD, Z_FND + 0.15), ( 2.45,  HD, Z_EAVE - 0.1), 0.14, 0.14, M_OAK_L)
C.beam('Brace', (-HW, -2.85, Z_FND + 0.15), (-HW, -1.0, Z_EAVE - 0.1), 0.14, 0.14, M_OAK_L)
C.beam('Brace', ( HW,  1.0, Z_FND + 0.15), ( HW,  2.85, Z_EAVE - 0.1), 0.14, 0.14, M_OAK_L)

# ---- 3. gables (closed thickness, outward normals) + roof (two clean slope quads) ----
def gable(name, y):
    t = 0.15
    if y > 0:   # back gable, outward normal +Y
        v = [(-HW, y - t / 2, Z_EAVE), (HW, y - t / 2, Z_EAVE), (0, y - t / 2, RIDGE_Z),
             (-HW, y + t / 2, Z_EAVE), (HW, y + t / 2, Z_EAVE), (0, y + t / 2, RIDGE_Z)]
        f = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
    else:       # front gable, outward normal -Y
        v = [(-HW, y + t / 2, Z_EAVE), (HW, y + t / 2, Z_EAVE), (0, y + t / 2, RIDGE_Z),
             (-HW, y - t / 2, Z_EAVE), (HW, y - t / 2, Z_EAVE), (0, y - t / 2, RIDGE_Z)]
        f = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
    C.mesh(name, v, f, M_PLASTER)

gable('GableN', HD); gable('GableS', -HD)

# roof: exactly two slope quads, eave edge -> ridge, correct winding (outward normal +Z)
def roof_surface(name, side):  # side +1 = +X slope, -1 = -X slope
    s = side
    v = [(-EX, -EY, Z_EAVE), (EX, -EY, Z_EAVE), (0, -EY, RIDGE_Z),
         (-EX,  EY, Z_EAVE), (EX,  EY, Z_EAVE), (0,  EY, RIDGE_Z)]
    if s > 0:
        f = [(1, 2, 5, 4)]
    else:
        f = [(0, 3, 5, 2)]
    C.mesh(name, v, f, M_SHINGLE)

roof_surface('RoofE', 1); roof_surface('RoofW', -1)

# shingle rows aligned to each slope; tilt about Y (ridge lies along Y)
def shingles(side):
    s = side
    dx, dz = EX, RIDGE_Z - Z_EAVE          # slope vector from eave to ridge
    L = math.hypot(dx, dz)
    ux, uz = dx / L, dz / L                # up-slope unit
    nx, nz = s * uz, ux                    # outward normal (positive Z), both slopes offset outward
    rows, cols = 12, 14
    for r in range(rows):
        t = (r + 0.5) / rows * 0.96        # keep inside eave/ridge
        cx = s * EX * (1 - t); cz = Z_EAVE + (RIDGE_Z - Z_EAVE) * t
        off = 0.03 + 0.02 * (r % 2)        # lift above roof plane, slight per-row stagger
        for i in range(cols):
            y = -EY + (i + 0.5) * (2 * EY) / cols
            m = M_SHINGLE if (i + r) % 3 else M_SHINGLE2
            o = C.box('Shingle', (cx + nx * off, y, cz + nz * off),
                      (0.42, 2 * EY / cols * 1.05, 0.05), m, bevel=0.01)
            o.rotation_euler[1] = math.atan2(dz, dx) * s   # tilt about Y: +X slope positive

shingles(1); shingles(-1)

# ridge timber + diagonal bargeboards from each eave corner to the ridge endpoint
C.box('Ridge', (0, 0, RIDGE_Z + 0.05), (0.3, 2 * EY + 0.2, 0.28), M_OAK)
for sy in (-1, 1):
    for sx in (-1, 1):
        C.beam('Barge', (sx * EX, sy * EY, Z_EAVE - 0.05), (0, sy * EY, RIDGE_Z), 0.2, 0.3, M_OAK)

# ---- 4. door, steps, windows ----
# recessed dark doorway + named Door plank (kept separate by common._join_by_material)
C.box('EntryRecess', (0, -HD + 0.05, 1.24), (1.3, 0.2, 2.05), M_OAK)
door = C.box('Door', (0, -HD - 0.15, 1.24), (1.1, 0.08, 2.0), M_DOOR, bevel=0.01)
for i in range(3):  # plank seams (on the door face, past the rail front)
    C.box('EntrySeam', ((-0.35 + i * 0.35), -HD - 0.20, 1.24), (0.04, 0.02, 2.0), M_OAK)
for hz in (0.7, 1.8):  # iron hinge straps
    C.box('Hinge', (-0.5, -HD - 0.21, hz), (0.12, 0.03, 0.3), M_IRON)
    C.box('Hinge', ( 0.5, -HD - 0.21, hz), (0.12, 0.03, 0.3), M_IRON)
# two low stone steps (top step ~0.24 aligns with door bottom)
C.box('Step1', (0, -HD - 0.45, 0.12), (1.6, 0.5, 0.24), M_STONE, bevel=0.03)
C.box('Step2', (0, -HD - 0.95, 0.06), (1.8, 0.5, 0.12), M_STONE, bevel=0.03)

def window(name, axis, fixed, hpos, zc):
    """Shuttered window built with explicit local horizontal + outward directions.
    axis 'x': front/back wall (horizontal = X, outward = +/-Y).
    axis 'y': side wall (horizontal = Y, outward = +/-X)."""
    if axis == 'x':
        out = -1 if fixed < 0 else 1
        base = (hpos, fixed + out * 0.02, zc)
        C.box(name + 'Recess', (hpos, fixed + out * 0.06, zc), (0.9, 0.12, 1.1), M_OAK)
        for s in (-1, 1):
            C.box(name + ('ShutL' if s < 0 else 'ShutR'),
                  (hpos + s * 0.24, fixed + out * 0.16, zc), (0.42, 0.06, 1.0), M_OAK_L)
            C.box(name + ('LatchL' if s < 0 else 'LatchR'),
                  (hpos + s * 0.24, fixed + out * 0.21, zc), (0.06, 0.03, 0.5), M_IRON)
    else:
        out = -1 if fixed < 0 else 1
        C.box(name + 'Recess', (fixed + out * 0.06, hpos, zc), (0.12, 0.9, 1.1), M_OAK)
        for s in (-1, 1):
            C.box(name + ('ShutL' if s < 0 else 'ShutR'),
                  (fixed + out * 0.16, hpos + s * 0.24, zc), (0.06, 0.42, 1.0), M_OAK_L)
            C.box(name + ('LatchL' if s < 0 else 'LatchR'),
                  (fixed + out * 0.21, hpos + s * 0.24, zc), (0.03, 0.06, 0.5), M_IRON)

window('WinF1', 'x', -HD, -1.55, 2.3)
window('WinF2', 'x', -HD,  1.55, 2.3)
window('WinB1', 'x',  HD, -1.55, 2.3)
window('WinB2', 'x',  HD,  1.55, 2.3)
window('WinE1', 'y',  HW, -1.4, 2.3)
window('WinE2', 'y',  HW,  1.4, 2.3)
window('WinW1', 'y', -HW, -1.4, 2.3)
window('WinW2', 'y', -HW,  1.4, 2.3)

# ---- 5. chimney: simple clear stone stack at CX=1.7, Y=0.6 (base pierces roof, top ~7.0) ----
CX = 1.7
C.box('Chimney', (CX, 0.6, 4.9), (0.8, 0.8, 4.2), M_STONE, bevel=0.02)
C.box('ChimCap', (CX, 0.6, 7.15), (1.0, 1.0, 0.2), M_STONE_D, bevel=0.03)
# dark opening: small flat inset rectangle sitting visibly above the cap top (z=7.25)
C.box('ChimOpen', (CX, 0.6, 7.26), (0.5, 0.5, 0.02), M_IRON)

C.finish('house')
