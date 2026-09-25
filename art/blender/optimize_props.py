"""Lighten downloaded CC0 props for the phone (TAVERN-03).

For every asset id: import <src>/<id>/<id>_1k.gltf, decimate all meshes together to about
--tris triangles, scale every texture down to at most --tex pixels, export <out>/<id>.glb.
Originals stay where they are (local, not in Git); only the light .glb goes to the game.
"""
import argparse
import sys
from pathlib import Path

import bpy


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--tris", type=int, default=1500)
    parser.add_argument("--tex", type=int, default=512)
    parser.add_argument("ids", nargs="+")
    return parser.parse_args(argv)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def triangle_count(objects):
    total = 0
    for obj in objects:
        if obj.type != "MESH":
            continue
        for poly in obj.data.polygons:
            total += len(poly.vertices) - 2
    return total


def decimate(objects, target):
    meshes = [o for o in objects if o.type == "MESH"]
    before = triangle_count(meshes)
    if before <= target or before == 0:
        return before, before
    ratio = max(0.02, target / before)
    for obj in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new("decimate", "DECIMATE")
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return before, triangle_count(meshes)


def shrink_textures(limit):
    for image in bpy.data.images:
        w, h = image.size[0], image.size[1]
        if w == 0 or h == 0 or max(w, h) <= limit:
            continue
        s = limit / max(w, h)
        image.scale(max(1, int(w * s)), max(1, int(h * s)))
        image.pack()


def main():
    args = parse_args()
    src = Path(args.src)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for asset_id in args.ids:
        reset()
        gltf = src / asset_id / f"{asset_id}_1k.gltf"
        bpy.ops.import_scene.gltf(filepath=str(gltf))
        objects = list(bpy.context.scene.objects)
        before, after = decimate(objects, args.tris)
        shrink_textures(args.tex)
        target = out / f"{asset_id}.glb"
        bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", export_image_format="JPEG", export_jpeg_quality=85)
        print(f"PROP {asset_id} tris {before} -> {after} glb {target.stat().st_size} bytes")


main()
