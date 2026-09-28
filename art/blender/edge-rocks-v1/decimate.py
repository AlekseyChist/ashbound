"""WORLD-EDGES-01: Poly Haven rocks and cliffs (CC0, 1k glTF) reduced for the phone.

Run: blender --background --python art/blender/edge-rocks-v1/decimate.py -- <source dir> <out dir>
Each model is joined into one mesh, decimated to its triangle budget (UVs kept), its origin moved
to the centre of its base, and exported as a .glb with its 1k textures.
"""
import sys
from pathlib import Path

import bpy

BUDGET = {
    "mountainside": 4000,
    "namaqualand_cliff_01": 3000,
    "namaqualand_cliff_02": 3000,
    "namaqualand_boulder_02": 1200,
}

args = sys.argv[sys.argv.index("--") + 1:]
source, out = Path(args[0]), Path(args[1])
out.mkdir(parents=True, exist_ok=True)

for name, budget in BUDGET.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source / name / f"{name}.gltf"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    rock = bpy.context.view_layer.objects.active
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    before = sum(len(p.vertices) - 2 for p in rock.data.polygons)
    after = before
    # Some scans stop short of the ratio in one pass (seams, UV islands): repeat until in budget.
    for _ in range(4):
        if after <= budget * 1.1:
            break
        decimate = rock.modifiers.new("Decimate", "DECIMATE")
        decimate.ratio = min(1.0, budget / max(after, 1))
        decimate.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=decimate.name)
        after = sum(len(p.vertices) - 2 for p in rock.data.polygons)
    # Origin at the centre of the base, so the game can stand it on the ground.
    xs = [v.co.x for v in rock.data.vertices]
    ys = [v.co.y for v in rock.data.vertices]
    zs = [v.co.z for v in rock.data.vertices]
    base = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs))
    for v in rock.data.vertices:
        v.co.x -= base[0]
        v.co.y -= base[1]
        v.co.z -= base[2]
    rock.location = (0, 0, 0)
    rock.name = name
    for o in list(bpy.context.scene.objects):
        if o is not rock:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.export_scene.gltf(filepath=str(out / f"{name}.glb"), export_format="GLB",
                              export_image_format="JPEG", use_selection=False)
    size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    print(f"EDGE_ROCK {name} tris {before} -> {after} size {size[0]:.1f} x {size[1]:.1f} x {size[2]:.1f} m")
