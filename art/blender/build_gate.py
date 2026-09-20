# AshBound build_gate.py - dark medieval freestanding village gate, OPEN PASSAGE.
import random
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import buildings_common as C

C.reset()

STONE = C.mat('GateStone', (0.42, 0.41, 0.39, 1), 0.95)
STONE_DARK = C.mat('GateStoneDark', (0.33, 0.32, 0.30, 1), 0.95)
TIMBER = C.mat('GateTimber', (0.24, 0.17, 0.11, 1), 0.85)
TIMBER_DARK = C.mat('GateTimberDark', (0.16, 0.11, 0.07, 1), 0.9)
IRON = C.mat('GateIron', (0.12, 0.12, 0.13, 1), 0.5, 0.85)

PIER_X = 3.0
PIER_W = 1.35   # X width
PIER_D = 1.45   # Y depth
PIER_H = 2.7    # Z height
COURSE_H = 0.45
N_COURSES = 6


def pier(cx):
    """Solid backing box, then staggered stone courses on all four faces."""
    C.box(f'PierBack_{cx}', (cx, 0, PIER_H / 2), (PIER_W, PIER_D, PIER_H), STONE_DARK, bevel=0.03)
    for i in range(N_COURSES):
        z = i * COURSE_H + COURSE_H / 2
        # Front face (fixed Y = -PIER_D/2), runs along X
        x = cx - PIER_W / 2 + random.uniform(0.15, 0.3)
        while x < cx + PIER_W / 2 - 0.1:
            w = min(random.uniform(0.35, 0.6), cx + PIER_W / 2 - 0.08 - x)
            if w > 0.18:
                C.box(f'StoneF_{cx}_{i}', (x + w / 2, -PIER_D / 2 - 0.03, z),
                      (w, 0.16, COURSE_H * random.uniform(0.85, 0.97)), STONE, bevel=0.02)
            x += w + random.uniform(0.04, 0.08)
        # Back face (fixed Y = +PIER_D/2), runs along X
        x = cx - PIER_W / 2 + random.uniform(0.15, 0.3)
        while x < cx + PIER_W / 2 - 0.1:
            w = min(random.uniform(0.35, 0.6), cx + PIER_W / 2 - 0.08 - x)
            if w > 0.18:
                C.box(f'StoneB_{cx}_{i}', (x + w / 2, PIER_D / 2 + 0.03, z),
                      (w, 0.16, COURSE_H * random.uniform(0.85, 0.97)), STONE, bevel=0.02)
            x += w + random.uniform(0.04, 0.08)
        # Side faces (fixed X), run along Y
        for sx in (-1, 1):
            y = -PIER_D / 2 + random.uniform(0.15, 0.3)
            while y < PIER_D / 2 - 0.1:
                d = min(random.uniform(0.35, 0.6), PIER_D / 2 - 0.08 - y)
                if d > 0.18:
                    C.box(f'StoneS_{cx}_{sx}_{i}', (cx + sx * (PIER_W / 2 + 0.03), y + d / 2, z),
                          (0.16, d, COURSE_H * random.uniform(0.85, 0.97)), STONE, bevel=0.02)
                y += d + random.uniform(0.04, 0.08)
    # Bigger capstones on top
    for sx in (-1, 1):
        C.box(f'Cap_{cx}_{sx}', (cx + sx * PIER_W / 4, 0, PIER_H + 0.1),
              (PIER_W / 2 - 0.05, PIER_D + 0.1, 0.2), STONE, bevel=0.03)


def post(cx):
    """Dark oak upright above pier, with iron hinge strap and pins on inner face."""
    C.box(f'Post_{cx}', (cx, 0, PIER_H + 1.15), (0.42, 0.42, 2.3), TIMBER, bevel=0.02)
    sgn = -1 if cx > 0 else 1  # inner direction toward center
    C.box(f'Strap_{cx}', (cx + sgn * 0.24, 0, PIER_H + 0.9), (0.06, 0.3, 1.5), IRON, bevel=0.01)
    for pz in (PIER_H + 0.5, PIER_H + 1.3):
        C.box(f'Pin_{cx}_{pz}', (cx + sgn * 0.28, 0, pz), (0.05, 0.34, 0.09), IRON, bevel=0.01)


def braces():
    """Chunky diagonal knee braces forming triangles above outer passage corners."""
    for sx in (-1, 1):
        # Outer corner of passage: x = sx*1.7 (inner post face), brace to lintel underside
        C.beam(f'Brace_{sx}', (sx * 3.0, -0.2, 3.0), (sx * 1.75, -0.2, 3.9),
               0.28, 0.22, TIMBER_DARK)
        C.beam(f'BraceB_{sx}', (sx * 3.0, 0.2, 3.0), (sx * 1.75, 0.2, 3.9),
               0.28, 0.22, TIMBER_DARK)


def lintels():
    """Two heavy horizontal lintel timbers at z~4.1 spanning the piers."""
    C.box('LintelF', (0, -0.2, 4.1), (7.6, 0.35, 0.45), TIMBER, bevel=0.02)
    C.box('LintelB', (0, 0.2, 4.1), (7.6, 0.35, 0.45), TIMBER, bevel=0.02)


def upper_rail():
    """Low upper timber rail at z5.0 with short posts."""
    C.box('RailF', (0, -0.2, 5.0), (7.6, 0.18, 0.22), TIMBER_DARK, bevel=0.015)
    C.box('RailB', (0, 0.2, 5.0), (7.6, 0.18, 0.22), TIMBER_DARK, bevel=0.015)
    for px in (-3.0, -1.5, 0, 1.5, 3.0):
        C.box(f'RailPost_{px}', (px, 0, 4.62), (0.16, 0.7, 0.55), TIMBER_DARK, bevel=0.01)


def walkway():
    """Understated narrow plank walkway spanning the piers at z4.25."""
    C.box('Walk', (0, 0, 4.25), (6.3, 1.1, 0.12), TIMBER_DARK, bevel=0.01)
    for px in (-2.4, -1.2, 0, 1.2, 2.4):
        C.box(f'Plank_{px}', (px, 0, 4.33), (1.1, 1.05, 0.04), TIMBER, bevel=0.008)


pier(-PIER_X)
pier(PIER_X)
post(-PIER_X)
post(PIER_X)
braces()
lintels()
upper_rail()
walkway()

C.finish('gate')
