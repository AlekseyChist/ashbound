"""Assembly/export/preview runner for forest village kit assets."""
import argparse, json, sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
BUILD_DATA = ROOT / "art/blender/forest-village-v1/build-data.json"
PREVIEW_DIR = ROOT / "art/previews/forest-village-v1"
sys.path.insert(0, str(Path(__file__).resolve().parent))

def parse_args():
    argv = sys.argv
    if "--" in argv:
        idx = argv.index("--")
        argv = argv[idx + 1:]
    else:
        argv = []
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", default="all")
    parser.add_argument("--no-render", action="store_true")
    return parser.parse_args(argv)

def load_specs():
    data = json.loads(BUILD_DATA.read_text())
    specs = data.get("buildings", [])
    if not specs:
        raise ValueError("No buildings found in build-data.json")
    return specs

def ensure_uv(mesh):
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv = mesh.uv_layers.active.data
    for poly in mesh.polygons:
        n = poly.normal
        if abs(n.z) > abs(n.x) and abs(n.z) > abs(n.y):
            u, v = "x", "y"
        elif abs(n.x) > abs(n.y):
            u, v = "z", "y"
        else:
            u, v = "x", "z"
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index
            co = mesh.vertices[vi].co
            uv[li].uv = (getattr(co, u), getattr(co, v))

def merge_by_role(asset):
    groups = {}
    for obj in list(asset.objects):
        if obj.type != "MESH":
            continue
        role = obj.get("part_role", "")
        mat = obj.data.materials[0].name if obj.data.materials else ""
        parent = obj.parent.name if obj.parent else ""
        item = obj.get("item_id", "")
        face = obj.get("face", "")
        key = (role, mat, parent, item, face)
        groups.setdefault(key, []).append(obj)
    for objs in groups.values():
        if len(objs) < 2:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()

def setup_studio():
    scene = bpy.context.scene
    bpy.ops.mesh.primitive_plane_add(size=50, location=(0, 0, -0.04))
    ground = bpy.context.active_object
    ground.name = "StudioGround"
    mat = bpy.data.materials.new("GroundMat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.3, 0.3, 0.3, 1)
    ground.data.materials.append(mat)

    world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.18, 0.18, 0.18, 1)

    bpy.ops.object.light_add(type="AREA", location=(-4, -6, 12))
    key = bpy.context.active_object
    key.name = "KeyLight"
    key.data.energy = 2200
    key.data.size = 10

    bpy.ops.object.light_add(type="AREA", location=(8, -2, 9))
    fill = bpy.context.active_object
    fill.name = "FillLight"
    fill.data.energy = 1300
    fill.data.size = 8

def setup_cameras():
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("ExteriorCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 17
    cam = bpy.data.objects.new("ExteriorCam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = Vector((11, -15, 10))
    target = Vector((0, 0, 2.8))
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()

    cam_data2 = bpy.data.cameras.new("InteriorCam")
    cam_data2.type = "ORTHO"
    cam_data2.ortho_scale = 14
    cam2 = bpy.data.objects.new("InteriorCam", cam_data2)
    scene.collection.objects.link(cam2)
    cam2.location = Vector((11, -14, 14))
    target2 = Vector((0, 0, 1.5))
    cam2.rotation_euler = (target2 - cam2.location).to_track_quat('-Z', 'Y').to_euler()

def render_views(spec_id, blend_path):
    bpy.ops.wm.open_mainfile(filepath=str(blend_path))
    scene = bpy.context.scene
    asset = bpy.data.collections['ASSET']

    scene.camera = bpy.data.objects["ExteriorCam"]
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 900
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.render.filepath = str(PREVIEW_DIR / f"{spec_id.lower()}-exterior.png")
    bpy.ops.render.render(write_still=True)

    hide_roles = {"roof", "ceiling", "gable", "chimney", "canopy"}
    for obj in asset.objects:
        if obj.type != "MESH":
            continue
        role = obj.get("part_role", "")
        face = obj.get("face", "")
        if role in hide_roles or (role in ('shell','door','shutter') and face in ("front", "right")):
            obj.hide_render = True
            obj.hide_viewport = True

    scene.camera = bpy.data.objects["InteriorCam"]
    scene.render.filepath = str(PREVIEW_DIR / f"{spec_id.lower()}-interior.png")
    bpy.ops.render.render(write_still=True)

def main():
    global bpy, C
    import bpy as _bpy
    import buildings_common as _C
    from forest_village_materials import make_materials
    from forest_village_shell import build_shell
    from forest_village_furniture import build_furniture
    bpy = _bpy
    C = _C

    args = parse_args()
    specs = load_specs()
    if args.asset != "all":
        specs = [s for s in specs if s["id"] == args.asset]
        if not specs:
            raise ValueError(f"Invalid asset ID: {args.asset}")

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0

    built_assets = []
    for spec in specs:
        spec_id = spec["id"]
        slug = spec.get("slug", spec_id.lower())
        out_dir = BUILD_DATA.parent
        out_dir.mkdir(parents=True, exist_ok=True)
        tex_dir = out_dir / "textures"
        tex_dir.mkdir(exist_ok=True)

        C.reset()
        asset = C.ASSET
        mats = make_materials(tex_dir)
        build_shell(spec, mats)
        build_furniture(spec, mats)

        for obj in asset.objects:
            if obj.type == "MESH":
                ensure_uv(obj.data)

        merge_by_role(asset)

        bpy.ops.object.select_all(action="DESELECT")
        for obj in asset.objects:
            if obj.type == "MESH" or obj.type == "EMPTY":
                obj.select_set(True)

        setup_studio()
        setup_cameras()
        scene = bpy.context.scene
        scene.render.engine = 'CYCLES'
        scene.cycles.device = 'CPU'
        scene.render.resolution_percentage = 100
        scene.render.image_settings.file_format = 'PNG'
        scene.camera = bpy.data.objects['ExteriorCam']
        # bpy operators select their new studio objects; export only the actual kit.
        bpy.ops.object.select_all(action='DESELECT')
        for obj in asset.objects:
            if obj.type in ('MESH', 'EMPTY'):
                obj.select_set(True)
        bpy.context.view_layer.update()
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.file.make_paths_relative()

        blend_path = out_dir / f"{slug}.blend"
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

        glb_path = out_dir / f"{slug}.glb"
        bpy.ops.export_scene.gltf(
            filepath=str(glb_path),
            use_selection=True,
            export_yup=True,
            export_apply=True,
            export_animations=False,
            export_cameras=False,
            export_lights=False,
            export_extras=True
        )

        mesh_objs = [o for o in asset.objects if o.type == "MESH"]
        total_tris = 0
        total_verts = 0
        materials_used = set()
        min_co = Vector((999, 999, 999))
        max_co = Vector((-999, -999, -999))
        for o in mesh_objs:
            depsgraph = bpy.context.evaluated_depsgraph_get()
            obj_eval = o.evaluated_get(depsgraph)
            mesh_eval = obj_eval.to_mesh()
            mesh_eval.calc_loop_triangles()
            total_tris += len(mesh_eval.loop_triangles)
            total_verts += len(mesh_eval.vertices)
            for m in o.data.materials:
                if m:
                    materials_used.add(m.name)
            for v in o.data.vertices:
                wco = o.matrix_world @ v.co
                min_co = Vector((min(min_co.x, wco.x), min(min_co.y, wco.y), min(min_co.z, wco.z)))
                max_co = Vector((max(max_co.x, wco.x), max(max_co.y, wco.y), max(max_co.z, wco.z)))
            obj_eval.to_mesh_clear()

        dims = max_co - min_co
        stats = {
            "build_id": spec_id,
            "source_contract_file": str(BUILD_DATA.relative_to(ROOT)),
            "mesh_objects": len(mesh_objs),
            "total_triangles": total_tris,
            "total_vertices": total_verts,
            "materials": sorted(materials_used),
            "bbox_min": [min_co.x, min_co.y, min_co.z],
            "bbox_max": [max_co.x, max_co.y, max_co.z],
            "dimensions": [dims.x, dims.y, dims.z]
        }

        print(f"VILLAGE_ASSET_BUILT id={spec_id}")
        built_assets.append((spec_id, slug, blend_path, stats))

    if not args.no_render:
        for spec_id, slug, blend_path, stats in built_assets:
            render_views(spec_id, blend_path)
            stats_path = PREVIEW_DIR / f"{slug}-stats.json"
            stats_path.write_text(json.dumps(stats, indent=2))
            print(f"VILLAGE_PREVIEWS_READY id={spec_id}")
    else:
        for spec_id, slug, blend_path, stats in built_assets:
            stats_path = PREVIEW_DIR / f"{slug}-stats.json"
            stats_path.write_text(json.dumps(stats, indent=2))

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
