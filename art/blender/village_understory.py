# Blender 5.2 generator: village understory assets (boulder, stump, fern, grass).
import sys, json, math
from pathlib import Path
import bpy
import random
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
BLEND_DIR = ROOT / "art/blender/village-forest-v1"
GLB_DIR = ROOT / "assets/environment/village-forest-v1"
PNG_DIR = ROOT / "art/previews/village-forest-v1"
STATS = BLEND_DIR / "stats-understory.json"
ASSETS = ["boulder", "stump", "fern", "grass"]
rng = random.Random(412)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if bpy.context.scene.world is None:
        w = bpy.data.worlds.new("World")
        bpy.context.scene.world = w
    bpy.context.scene.world.use_nodes = True


def new_mat(name, color, rough=0.9, backface=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    m.use_backface_culling = not backface
    return m


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def deselect_all():
    for o in bpy.context.selected_objects:
        o.select_set(False)


def apply_transforms(objs):
    deselect_all()
    for o in objs:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    deselect_all()


def ground_at_zero(objs):
    zs = [v.co.z for o in objs for v in o.data.vertices]
    if zs:
        dz = -min(zs)
        for o in objs:
            o.location.z += dz
        apply_transforms(objs)


def save_asset(name, objs, role):
    for o in objs:
        o["part_role"] = role
    ground_at_zero(objs)
    apply_transforms(objs)
    deselect_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_DIR / f"{name}.blend"))
    deselect_all()
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=str(GLB_DIR / f"{name}.glb"),
                              export_format="GLB", use_selection=True,
                              export_extras=True)
    deselect_all()
    xs, ys, zs = [], [], []
    for o in objs:
        for v in o.data.vertices:
            xs.append(v.co.x); ys.append(v.co.y); zs.append(v.co.z)
    dims = [max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)] if xs else [0.0, 0.0, 0.0]
    return {"tris": sum(tris(o) for o in objs),
            "dims": [round(max(d, 1e-3), 3) for d in dims],
            "objects": len(objs), "role": role}


def make_boulder():
    mat = new_mat("boulder_stone", (0.42, 0.44, 0.40))
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.7)
    o = bpy.context.active_object
    o.name = "boulder"
    for v in o.data.vertices:
        n = Vector((v.co.x, v.co.y, v.co.z)).normalized()
        f = 1.0 + rng.uniform(-0.18, 0.18)
        v.co = v.co * f
        v.co.z *= 0.72
    o.data.materials.append(mat)
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'art/blender/forest-village-v1/textures/stone.png'));tex.image.pack()
    mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    for face in o.data.polygons: face.use_smooth=True
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return [o]


def make_stump():
    bark = new_mat("stump_bark", (0.30, 0.22, 0.15))
    wood = new_mat("stump_wood", (0.62, 0.48, 0.30))
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.32, depth=0.65)
    o = bpy.context.active_object
    o.name = "stump"
    for v in o.data.vertices:
        if abs(v.co.z - 0.325) < 1e-4:
            v.co.x *= rng.uniform(0.85, 1.15)
            v.co.y *= rng.uniform(0.85, 1.15)
    o.data.materials.append(bark)
    o.data.materials.append(wood)
    o.data.update()
    for p in o.data.polygons:
        p.material_index = 1 if p.normal.z > 0.5 else 0
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return [o]


def make_fern():
    # Codex visual QA: replace conical blades with arching paired-leaf fronds.
    mat=new_mat('fern_leaf',(.14,.25,.08),backface=True)
    verts,faces=[],[]
    for f in range(8):
        angle=math.tau*f/8+rng.uniform(-.1,.1)
        forward=Vector((math.cos(angle),math.sin(angle),0));side=Vector((-math.sin(angle),math.cos(angle),0))
        length=rng.uniform(.55,.78);height=rng.uniform(.52,.72)
        def center(v): return forward*(v*length)+Vector((0,0,.02+height*math.sin(v*math.pi*.8)))
        for s in range(9):
            v=s/9;v1=(s+1)/9;i=len(verts)
            for co in [center(v)-side*.009,center(v)+side*.009,center(v1)+side*.005,center(v1)-side*.005]: verts.append(co)
            faces.append((i,i+1,i+2,i+3))
        for s in range(1,9):
            v=s/10;c=center(v);reach=.16*math.sin(v*math.pi)**.6
            for sign in [-1,1]:
                tip=c+side*(sign*reach)+forward*.075+Vector((0,0,.014))
                mid=c.lerp(tip,.52);i=len(verts)
                verts.extend([c,mid-forward*.024,tip,mid+forward*.024])
                faces.append((i,i+1,i+2,i+3))
    m=bpy.data.meshes.new('fern');m.from_pydata(verts,[],faces);m.update()
    o=bpy.data.objects.new('fern',m);bpy.context.scene.collection.objects.link(o);m.materials.append(mat)
    return [o]


def make_grass():
    mat = new_mat("grass_leaf", (0.30, 0.42, 0.18), backface=True)
    verts, faces = [], []
    for i in range(12):
        ang = rng.uniform(0, 2 * math.pi)
        bend = rng.uniform(0.15, 0.4)
        h = 0.3 * rng.uniform(0.8, 1.0)
        segs = 4
        prev = None
        for s in range(segs + 1):
            t = s / segs
            z = t * h
            r = bend * t * t
            cx = math.cos(ang) * r
            cy = math.sin(ang) * r
            w = 0.02 * (1 - t)
            px, py = -math.sin(ang), math.cos(ang)
            a = len(verts); verts.append((cx + px * w, cy + py * w, z))
            b = len(verts); verts.append((cx - px * w, cy - py * w, z))
            if prev:
                faces += [(prev[0], prev[1], b), (prev[0], b, a)]
            prev = (a, b)
    m = bpy.data.meshes.new("grass")
    m.from_pydata(verts, [], faces)
    o = bpy.data.objects.new("grass", m)
    bpy.context.scene.collection.objects.link(o)
    m.materials.append(mat)
    return [o]


def render_preview(name, dim):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = 512
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.5 * max(dim, 0.5)
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    h = dim * 0.45
    cam.location = Vector((1.8, -1.8, h + 1.6))
    d = Vector((0, 0, h)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun_d = bpy.data.lights.new("Sun", "SUN")
    sun_d.energy = 2.0
    sun = bpy.data.objects.new("Sun", sun_d)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    fill_d = bpy.data.lights.new("Fill", "SUN")
    fill_d.energy = 0.4
    fill = bpy.data.objects.new("Fill", fill_d)
    scene.collection.objects.link(fill)
    fill.rotation_euler = (math.radians(60), 0, math.radians(200))
    floor_m = new_mat("floor", (0.12, 0.12, 0.13))
    bpy.ops.mesh.primitive_plane_add(size=8)
    floor = bpy.context.active_object
    floor.data.materials.append(floor_m)
    scene.render.filepath = str(PNG_DIR / f"{name}.png")
    bpy.ops.render.render(write_still=True)


def main():
    for d in (BLEND_DIR, GLB_DIR, PNG_DIR):
        d.mkdir(parents=True, exist_ok=True)
    do_render = "--no-render" not in sys.argv
    stats = {}
    builders = {"boulder": make_boulder, "stump": make_stump,
                "fern": make_fern, "grass": make_grass}
    for name in ASSETS:
        reset_scene()
        objs = builders[name]()
        info = save_asset(name, objs, {"boulder": "stone", "stump": "bark"}.get(name, "foliage"))
        stats[name] = info
        if do_render:
            render_preview(name, max(info["dims"]))
    STATS.write_text(json.dumps(stats, indent=2))
    print(json.dumps(stats))


if __name__ == "__main__":
    main()
