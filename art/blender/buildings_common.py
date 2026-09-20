# AshBound buildings_common.py - reusable Blender 5.2 helpers (background mode).
import json, math, random
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
ASSET = None  # global collection for building meshes


def reset():
    """Clear fresh background scene, metric units, seed, create ASSET collection."""
    global ASSET
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    random.seed(20240501)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for b in list(block):
            if b.users == 0:
                block.remove(b)
    ASSET = bpy.data.collections.new('ASSET')
    scene.collection.children.link(ASSET)


def mat(name, color, roughness=0.9, metallic=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    return m


def _link(obj):
    for c in obj.users_collection:
        c.objects.unlink(obj)
    ASSET.objects.link(obj)


def box(name, location, size, material, bevel=0.02):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        m = o.modifiers.new('bev', 'BEVEL')
        m.width = bevel
        m.segments = 1
        m.limit_method = 'ANGLE'
        bpy.ops.object.modifier_apply(modifier=m.name)
    o.data.materials.clear()
    o.data.materials.append(material)
    _link(o)
    return o


def beam(name, a, b, width, depth, material):
    a, b = Vector(a), Vector(b)
    v = b - a
    length = v.length
    if length < 1e-6:
        return box(name, a, (width, depth, 0.01), material)
    o = box(name, (a + b) / 2, (width, depth, length), material)
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = v.to_track_quat('Z', 'Y')
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return o


def mesh(name, vertices, faces, material):
    me = bpy.data.meshes.new(name)
    me.from_pydata(vertices, [], faces)
    me.validate()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    o.data.materials.append(material)
    _link(o)
    return o


def _join_by_material(objs):
    """Join static ASSET objects sharing a material; keep *Door* objects separate."""
    groups = {}
    for o in objs:
        if 'Door' in o.name:
            continue
        key = o.data.materials[0].name if o.data.materials else ''
        groups.setdefault(key, []).append(o)
    for key, group in groups.items():
        if len(group) < 2:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in group:
            o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        bpy.ops.object.join()


def _center_xy_bottom(objs):
    """Center all ASSET meshes in XY, bottom at z=0 (applied transforms)."""
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in [o.matrix_world @ Vector(v.co) for v in o.data.vertices]:
            mn.x = min(mn.x, c.x); mn.y = min(mn.y, c.y); mn.z = min(mn.z, c.z)
            mx.x = max(mx.x, c.x); mx.y = max(mx.y, c.y); mx.z = max(mx.z, c.z)
    shift = Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
    for o in objs:
        o.location += shift
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)


def _studio():
    """Ground plane, ortho camera front-left, area light, charcoal world."""
    scene = bpy.context.scene
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = 'PreviewGround'
    gm = mat('PreviewGroundMat', (0.35, 0.35, 0.36, 1), 0.95)
    ground.data.materials.append(gm)
    objs = [o for o in ASSET.objects]
    mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in [o.matrix_world @ Vector(v.co) for v in o.data.vertices]:
            mn = Vector(tuple(map(min, mn, c))); mx = Vector(tuple(map(max, mx, c)))
    center = (mn + mx) / 2
    dist = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) * 1.6 + 2.0
    cam_data = bpy.data.cameras.new('PreviewCam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = dist
    cam = bpy.data.objects.new('PreviewCam', cam_data)
    scene.collection.objects.link(cam)
    cam.location = center + Vector((-dist * 0.7, -dist, dist * 0.5))
    d = (center - cam.location).normalized()
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = d.to_track_quat('-Z', 'Y')
    scene.camera = cam
    # Preview-only lights (never exported to GLB): strong neutral key + weak fill.
    key_data = bpy.data.lights.new('KeyLight', 'AREA')
    key_data.energy = 2500
    key_data.size = 16
    key_data.color = (1.0, 0.98, 0.95)
    key = bpy.data.objects.new('KeyLight', key_data)
    scene.collection.objects.link(key)
    key.location = center + Vector((-7, -5, 11))
    kd = (center - key.location).normalized()
    key.rotation_mode = 'QUATERNION'
    key.rotation_quaternion = kd.to_track_quat('-Z', 'Y')
    fill_data = bpy.data.lights.new('FillLight', 'AREA')
    fill_data.energy = 500
    fill_data.size = 14
    fill_data.color = (0.9, 0.95, 1.0)
    fill = bpy.data.objects.new('FillLight', fill_data)
    scene.collection.objects.link(fill)
    fill.location = center + Vector((7, 4, 8))
    fd = (center - fill.location).normalized()
    fill.rotation_mode = 'QUATERNION'
    fill.rotation_quaternion = fd.to_track_quat('-Z', 'Y')
    world = bpy.data.worlds.get('World') or bpy.data.worlds.new('World')
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get('Background')
    bg.inputs[0].default_value = (0.05, 0.05, 0.06, 1)
    bg.inputs[1].default_value = 1.0


def finish(slug):
    out_blend = ROOT / 'art' / 'blender' / 'output' / f'{slug}.blend'
    glb_path = ROOT / 'assets' / 'buildings' / 'ashbound' / f'{slug}.glb'
    png_path = ROOT / 'art' / 'previews' / f'{slug}.png'
    json_path = ROOT / 'art' / 'previews' / f'{slug}-stats.json'
    for p in (out_blend.parent, glb_path.parent, png_path.parent):
        p.mkdir(parents=True, exist_ok=True)

    objs = [o for o in ASSET.objects]
    _join_by_material(objs)
    objs = [o for o in ASSET.objects]
    _center_xy_bottom(objs)

    # Export GLB: only ASSET meshes.
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        use_selection=True,
        export_format='GLB',
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_apply=True,
    )

    # Stats.
    tris = verts = 0
    mats = set()
    mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
        verts += len(o.data.vertices)
        for m in o.data.materials:
            mats.add(m.name)
        for c in [o.matrix_world @ Vector(v.co) for v in o.data.vertices]:
            mn = Vector(tuple(map(min, mn, c))); mx = Vector(tuple(map(max, mx, c)))
    stats = {
        'slug': slug,
        'triangles': tris,
        'vertices': verts,
        'mesh_objects': len(objs),
        'materials': sorted(mats),
        'bbox_min': [round(v, 4) for v in mn],
        'bbox_max': [round(v, 4) for v in mx],
        'dimensions': [round(v, 4) for v in (mx - mn)],
    }
    json_path.write_text(json.dumps(stats, indent=2), encoding='utf-8')

    # Studio setup, render, save blend.
    _studio()
    scene = bpy.context.scene

    # Viewport: material color mode, frame whole asset, select only ASSET objects.
    for m in bpy.data.materials:
        if m.use_nodes:
            m.diffuse_color = m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]
    for area in bpy.context.screen.areas:
        if area.type != 'VIEW_3D':
            continue
        space = area.spaces.active
        space.shading.color_type = 'MATERIAL'
        space.region_3d.view_location = (mn + mx) / 2
        space.region_3d.view_distance = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) * 1.6 + 2.0
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 1000
    scene.render.filepath = str(png_path)
    scene.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out_blend))

    print('ASHBOUND_ASSET_READY')
    print(str(out_blend))
    print(str(glb_path))
    print(str(png_path))
    print(str(json_path))
