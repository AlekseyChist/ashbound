# Blender 5.2 generator: dark painterly conifer forest kit (3 trees).
import bpy, math, json, random, sys, colorsys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
BLEND_DIR = ROOT / "art/blender/village-forest-v1"
GLB_DIR = ROOT / "assets/environment/village-forest-v1"
PNG_DIR = ROOT / "art/previews/village-forest-v1"
for d in (BLEND_DIR, GLB_DIR, PNG_DIR):
    d.mkdir(parents=True, exist_ok=True)

# sys.argv is a list; use .index('--'), not .find('--')
NO_RENDER = "--no-render" in sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else False

SPECIES = {
    # explicit stable integer seed per species (hash() is salted, do not use)
    "pine_tall": dict(h=10.0, trunk_r=0.34, layers=7, layer_h=1.15, spread=2.6,
                      base_foliage=1.5, hue=0.38, sat=0.32, val=0.16, seed=101),
    "spruce": dict(h=8.0, trunk_r=0.26, layers=9, layer_h=0.75, spread=1.9,
                   base_foliage=1.4, hue=0.42, sat=0.28, val=0.13, seed=202),
    "pine_young": dict(h=4.5, trunk_r=0.14, layers=5, layer_h=0.7, spread=1.2,
                       base_foliage=1.0, hue=0.36, sat=0.35, val=0.2, seed=303),
}

BARK = (0.28, 0.2, 0.14)
MOSS = (0.16, 0.2, 0.12)


def hsl(h, s, v):
    # subtle dark OLIVE/GREEN via HSV (hsl() previously ignored hue -> blue-gray)
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(1.0, s), min(1.0, v))
    return (r, g, b)


def new_obj(name, verts, faces, mat_slots=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def make_mat(name, color, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    return m


def add_trunk(verts, faces, rng, p):
    """Tapered irregular bark trunk; returns (top_z, top_r)."""
    segs, rings = 8, 10
    h, r0 = p["h"], p["trunk_r"]
    ring_idx = []
    for i in range(rings + 1):
        z = h * i / rings
        t = i / rings
        r = r0 * (1 - 0.82 * t)
        row = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            wob = 1 + 0.14 * math.sin(a * 3 + i * 1.7) + rng.uniform(-0.06, 0.06)
            x = r * wob * math.cos(a)
            y = r * wob * math.sin(a)
            row.append(len(verts))
            verts.append((x, y, z))
        ring_idx.append(row)
    for i in range(rings):
        for j in range(segs):
            a, b = ring_idx[i][j], ring_idx[i][(j + 1) % segs]
            c, d = ring_idx[i + 1][(j + 1) % segs], ring_idx[i + 1][j]
            faces.append((a, b, c, d))
    return h, r0 * 0.18


def add_branch(verts, faces, rng, origin, direction, length, radius):
    """Tapered branch as a 6-sided tube; returns tip vertex index."""
    d = direction.normalized()
    quat = d.to_track_quat("Z", "Y")
    segs, rings = 5, 2
    up = quat @ Vector((0, 0, 1))
    side = quat @ Vector((1, 0, 0))
    ring_idx = []
    for i in range(rings + 1):
        t = i / rings
        z = length * t
        r = radius * (1 - 0.85 * t)
        row = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            off = side * math.cos(a) + quat @ Vector((0, 1, 0)) * math.sin(a)
            p = origin + up * z + off * r
            row.append(len(verts))
            verts.append(p)
        ring_idx.append(row)
    for i in range(rings):
        for j in range(segs):
            a, b = ring_idx[i][j], ring_idx[i][(j + 1) % segs]
            c, d = ring_idx[i + 1][(j + 1) % segs], ring_idx[i + 1][j]
            faces.append((a, b, c, d))
    return ring_idx[-1][0]


def build_tree(name, p):
    # Codex handoff: rejected solid pyramid crowns replaced by textured branch cards.
    rng = random.Random(p["seed"])
    verts, faces, fverts, ffaces, uvs = [], [], [], [], []
    add_trunk(verts, faces, rng, p)
    layers = 14 if name == 'spruce' else 13 if name == 'pine_tall' else 9
    for li in range(layers):
        t = li / (layers - 1)
        z = p['base_foliage'] + (p['h'] - p['base_foliage'] - .45) * t
        n = 7 if t < .75 else 5
        phase = rng.uniform(0, math.tau)
        for j in range(n):
            angle = phase + j * math.tau / n + rng.uniform(-.12,.12)
            length = p['spread'] * max(.1, (1-t)**.65) * rng.uniform(.82,1.1)
            start = Vector((.07*math.sin(z),.03*math.cos(z),z))
            outward = Vector((math.cos(angle), math.sin(angle), -.12 + .35*t)).normalized()
            add_branch(verts,faces,rng,start,outward,length,.055*(1-.6*t))
            side = Vector((-math.sin(angle),math.cos(angle),0))
            up = outward.cross(side).normalized()
            # Crossing curved sprays retain silhouette from either camera direction.
            for tilt in [-.8, .65, 1.6]:
                across = side*math.cos(tilt)+up*math.sin(tilt)
                normal = outward.cross(across).normalized()
                base = len(fverts)
                for row in range(4):
                    v = row/3
                    center = start + outward * (v*length*1.14) + normal*math.sin(v*math.pi)*length*.08
                    for col in range(2):
                        u = col
                        fverts.append(center+across*((u-.5)*length*.95))
                        uvs.append((u,v))
                for row in range(3):
                    i = base+row*2
                    ffaces.append((i,i+1,i+3,i+2))
    for co in fverts: co.z = max(.08, co.z)
    bark = new_obj('Bark',verts,faces)
    fol = new_obj('Foliage',fverts,ffaces)
    mb = make_mat(name+'_bark', BARK)
    wood = bpy.data.images.load(str(ROOT/'art/blender/forest-village-v1/textures/oak.png'),check_existing=True)
    wood.pack()
    bn = mb.node_tree.nodes.new('ShaderNodeTexImage'); bn.image=wood
    mb.node_tree.links.new(bn.outputs['Color'],mb.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    bark.data.materials.append(mb)
    uv = bark.data.uv_layers.new(name='UVMap')
    for poly in bark.data.polygons:
        poly.use_smooth=True
        for li in poly.loop_indices:
            co=bark.data.vertices[bark.data.loops[li].vertex_index].co
            uv.data[li].uv=(math.atan2(co.y,co.x)/math.tau+.5,co.z*.5)
    mf=make_mat(name+'_foliage',(1,1,1))
    mf.use_backface_culling=False
    mf.surface_render_method='DITHERED'
    image=bpy.data.images.load(str(GLB_DIR/'textures/pine-spray-v1.png'),check_existing=True);image.pack()
    tex=mf.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
    bsdf=mf.node_tree.nodes['Principled BSDF']
    mf.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    cut=mf.node_tree.nodes.new('ShaderNodeMath');cut.operation='GREATER_THAN';cut.inputs[1].default_value=.4
    mf.node_tree.links.new(tex.outputs['Alpha'],cut.inputs[0]);mf.node_tree.links.new(cut.outputs[0],bsdf.inputs['Alpha'])
    fol.data.materials.append(mf)
    uv=fol.data.uv_layers.new(name='UVMap')
    for poly in fol.data.polygons:
        for li in poly.loop_indices: uv.data[li].uv=uvs[fol.data.loops[li].vertex_index]
    colors=fol.data.color_attributes.new('Col','FLOAT_COLOR','POINT')
    for i,v in enumerate(fverts): colors.data[i].color=(1,1,1,max(0,min(1,v.z/p['h'])))
    bark['part_role']='bark';fol['part_role']='foliage'
    return bark,fol


def export_asset(name, objs):
    # select exactly the returned bark/foliage objects (names are "Bark"/"Foliage",
    # not prefixed by species); preview objects stay unselected and are excluded.
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    glb = GLB_DIR / (name + ".glb")
    # export vertex colors (RGBA wind weights) alongside material Base Color
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB",
                              use_selection=True, export_extras=True,
                              export_vertex_color="ACTIVE")


def render_preview(name):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.film_transparent = False
    # ensure world exists (factory empty scene may have none) and uses nodes
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    if scene.world.node_tree is None:
        scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg is None:
        bg = scene.world.node_tree.nodes.new("ShaderNodeBackground")
    bg.inputs[0].default_value = (0.05, 0.07, 0.06, 1)
    # ground plane (excluded from export by selection-only export)
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    gnd = bpy.context.active_object
    gnd.name = "preview_ground"
    gm = make_mat("preview_ground", (0.06, 0.08, 0.06), 1.0)
    gnd.data.materials.append(gm)
    # camera ortho 3/4
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    h = SPECIES[name]["h"]
    cam_data.ortho_scale = h * 1.25
    cam = bpy.data.objects.new("preview_cam", cam_data)
    bpy.context.collection.objects.link(cam)
    dist = h * 1.6
    cam.location = (dist, -dist, h * 0.75)
    d = Vector((0, 0, h * 0.45)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    # lights
    sun_data = bpy.data.lights.new("key", "SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("key", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), math.radians(20), math.radians(40))
    fill_data = bpy.data.lights.new("fill", "SUN")
    fill_data.energy = 0.35
    fill = bpy.data.objects.new("fill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.rotation_euler = (math.radians(60), math.radians(-30), math.radians(-40))
    scene.render.filepath = str(PNG_DIR / (name + ".png"))
    bpy.ops.render.render(write_still=True)
    # cleanup preview-only objects
    for o in (gnd, cam, sun, fill):
        bpy.data.objects.remove(o, do_unlink=True)


def main():
    stats = {}
    for name, p in SPECIES.items():
        # reset to empty scene PER species so assets don't accumulate and names
        # don't gain .001 suffixes; factory empty world may be None (handled in render)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bark, fol = build_tree(name, p)
        # save individual blend before preview nodes
        bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_DIR / (name + ".blend")))
        export_asset(name, [bark, fol])
        if not NO_RENDER:
            render_preview(name)
        # stats: triangles via polygon vertex count; dims over BOTH meshes per axis
        tris = 0
        for ob in (bark, fol):
            m = ob.data
            tris += sum(len(poly.vertices) - 2 for poly in m.polygons)
        all_co = [v.co for v in bark.data.vertices] + [v.co for v in fol.data.vertices]
        if all_co:
            dims = [max(c[i] for c in all_co) - min(c[i] for c in all_co) for i in range(3)]
        else:
            dims = [0.0, 0.0, 0.0]
        stats[name] = dict(dimensions=[round(x, 2) for x in dims],
                           mesh_count=2,
                           material_count=len(bark.data.materials) + len(fol.data.materials),
                           triangles=tris)
    with open(BLEND_DIR / "stats.json", "w") as f:
        json.dump(stats, f, indent=2)


if __name__ == "__main__":
    main()
