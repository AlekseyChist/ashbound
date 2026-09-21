# AshBound courtyard props generator (Blender background).
import math, sys
from pathlib import Path
import bpy
sys.path.insert(0, str(Path(__file__).resolve().parent))
import buildings_common as C


def cyl(name, location, radius, depth, material, rot=(0, 0, 0), verts=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=location)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    o.data.materials.clear()
    o.data.materials.append(material)
    C._link(o)
    return o


def build_well():
    C.reset()
    stone = C.mat('WellStone', (0.32, 0.31, 0.29, 1), 0.95)
    wood = C.mat('WellWood', (0.16, 0.11, 0.07, 1), 0.9)
    iron = C.mat('WellIron', (0.12, 0.12, 0.13, 1), 0.5, 0.8)
    r = 1.0
    for i in range(16):
        a = i / 16 * math.tau
        x, y = math.cos(a) * r, math.sin(a) * r
        h = 0.55 if i % 2 == 0 else 0.42
        b = C.box(f'WellStone_{i}', (x, y, h / 2), (0.62, 0.5, h), stone, bevel=0.03)
        b.rotation_euler.z = a + math.pi / 2
    for i in range(10):
        a = (i + 0.5) / 10 * math.tau
        x, y = math.cos(a) * r, math.sin(a) * r
        C.box(f'WellStoneTop_{i}', (x, y, 0.62), (0.5, 0.42, 0.18), stone, bevel=0.03)
    for sx in (-1, 1):
        C.box(f'WellPost_{sx}', (sx * 1.15, 0, 1.4), (0.16, 0.16, 2.8), wood)
    C.beam('WellCrossbeam', (-1.15, 0, 2.55), (1.15, 0, 2.55), 0.14, 0.14, wood)
    # Pitched roof: 7 pairs of sloping planks spanning eave to ridge at one X each.
    for i in range(7):
        x = -1.17 + i * 0.39
        C.beam(f'WellRoofPlankL_{i}', (x, -0.95, 2.45), (x, 0, 3.0), 0.38, 0.06, wood)
        C.beam(f'WellRoofPlankR_{i}', (x, 0, 3.0), (x, 0.95, 2.45), 0.38, 0.06, wood)
    C.beam('WellRidge', (-1.17, 0, 3.0), (1.17, 0, 3.0), 0.12, 0.12, wood)
    cyl('WellPulley', (0, 0, 2.55), 0.09, 0.22, iron, rot=(math.pi / 2, 0, 0))
    C.finish('courtyard_well')


def build_dummy():
    C.reset()
    wood = C.mat('DummyWood', (0.18, 0.13, 0.08, 1), 0.9)
    straw = C.mat('DummyStraw', (0.62, 0.52, 0.3, 1), 0.95)
    red = C.mat('DummyRed', (0.45, 0.08, 0.06, 1), 0.85)
    # Crossed ground support beams: one along X, one along Y, centered.
    C.box('DummyBaseL', (0, 0, 0.05), (0.9, 0.12, 0.1), wood)
    C.box('DummyBaseR', (0, 0, 0.05), (0.12, 0.9, 0.1), wood)
    cyl('DummyPole', (0, 0, 0.9), 0.05, 1.8, wood, verts=8)
    C.box('DummyTorso', (0, 0, 1.15), (0.42, 0.26, 0.7), straw)
    cyl('DummyHead', (0, 0, 1.62), 0.16, 0.28, straw, rot=(math.pi / 2, 0, 0), verts=10)
    C.beam('DummyArmL', (-0.2, 0, 1.35), (-0.6, 0, 1.45), 0.1, 0.1, wood)
    C.beam('DummyArmR', (0.2, 0, 1.35), (0.6, 0, 1.45), 0.1, 0.1, wood)
    cyl('DummyBand1', (0, 0, 1.28), 0.235, 0.07, red, rot=(math.pi / 2, 0, 0), verts=14)
    cyl('DummyBand2', (0, 0, 1.05), 0.235, 0.07, red, rot=(math.pi / 2, 0, 0), verts=14)
    # Visible bullseye on forward side: red target disk + smaller straw disk on it.
    cyl('DummyTarget', (0, -0.16, 1.15), 0.18, 0.03, red, rot=(math.pi / 2, 0, 0), verts=14)
    cyl('DummyTargetCore', (0, -0.175, 1.15), 0.09, 0.03, straw, rot=(math.pi / 2, 0, 0), verts=12)
    C.finish('courtyard_dummy')


def build_fence():
    C.reset()
    wood = C.mat('FenceWood', (0.2, 0.15, 0.1, 1), 0.92)
    for x in (-1.5, 1.5):
        C.box(f'FencePost_{x}', (x, 0, 0.55), (0.14, 0.14, 1.1), wood)
    C.beam('FenceRailTop', (-1.5, 0, 0.85), (1.5, 0, 0.85), 0.09, 0.06, wood)
    C.beam('FenceRailBot', (-1.5, 0, 0.35), (1.5, 0, 0.35), 0.09, 0.06, wood)
    C.finish('courtyard_fence')


def build_woodpile():
    C.reset()
    bark = C.mat('WoodBark', (0.22, 0.15, 0.09, 1), 0.95)
    cut = C.mat('WoodCut', (0.55, 0.42, 0.25, 1), 0.9)
    rows = [(0.18, 0.18), (0.36, -0.18), (0.36, 0.18)]
    z = 0.18
    for row in range(3):
        n = 4 if row < 2 else 3
        for i in range(n):
            x = -0.75 + i * 0.5 + (0.25 if row == 2 else 0)
            y = rows[row][1] if row else 0
            cyl(f'Log_{row}_{i}', (x, y, z), 0.18, 0.9, bark, rot=(math.pi / 2, 0, 0), verts=10)
            # Cut ends at y=+/-0.46, same x/z as log, radius 0.16.
            cyl(f'LogEndA_{row}_{i}', (x, y - 0.46, z), 0.16, 0.02, cut, rot=(math.pi / 2, 0, 0), verts=10)
            cyl(f'LogEndB_{row}_{i}', (x, y + 0.46, z), 0.16, 0.02, cut, rot=(math.pi / 2, 0, 0), verts=10)
        z += 0.3
    C.finish('courtyard_woodpile')


def build_crate():
    C.reset()
    wood = C.mat('CrateWood', (0.28, 0.2, 0.12, 1), 0.9)
    s = 0.8
    for i in range(4):
        C.box(f'CrateFront_{i}', (0, s / 2 - 0.03, 0.1 + i * 0.19), (s - 0.08, 0.05, 0.17), wood)
        C.box(f'CrateBack_{i}', (0, -s / 2 + 0.03, 0.1 + i * 0.19), (s - 0.08, 0.05, 0.17), wood)
    for i in range(4):
        C.box(f'CrateSideL_{i}', (-s / 2 + 0.03, 0, 0.1 + i * 0.19), (0.05, s - 0.08, 0.17), wood)
        C.box(f'CrateSideR_{i}', (s / 2 - 0.03, 0, 0.1 + i * 0.19), (0.05, s - 0.08, 0.17), wood)
    # Top planks above the sides (z = 0.78).
    for i in range(4):
        y = -s / 2 + 0.06 + i * 0.19
        C.box(f'CrateTop_{i}', (0, y, 0.78), (s - 0.08, 0.17, 0.05), wood)
    for i in range(4):
        x = -s / 2 + 0.06 + i * 0.19
        C.box(f'CrateBot_{i}', (x, 0, 0.03), (0.17, s - 0.08, 0.05), wood)
    # Diagonal wooden braces across front and back faces (no closed interior planes).
    for sy in (-1, 1):
        C.beam(f'CrateBrace_{sy}A', (-s / 2 + 0.06, sy * (s / 2 - 0.03), 0.08), (s / 2 - 0.06, sy * (s / 2 - 0.03), s - 0.08), 0.05, 0.05, wood)
        C.beam(f'CrateBrace_{sy}B', (s / 2 - 0.06, sy * (s / 2 - 0.03), 0.08), (-s / 2 + 0.06, sy * (s / 2 - 0.03), s - 0.08), 0.05, 0.05, wood)
    C.finish('courtyard_crate')


if __name__ == '__main__':
    build_well()
    build_dummy()
    build_fence()
    build_woodpile()
    build_crate()
    print('ASHBOUND_COURTYARD_PROPS_READY')
