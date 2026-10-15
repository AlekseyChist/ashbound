"""Cave mouth (WORLD-PLAN-01, CAVE-MOUTH): a rock hill with an arch into it.
With `-- mine`: the Crown mine's portal (MINE-01) - the same hill, a squared adit 3.4 x 3.2 m with
timber sets every 1.6 m, a heavy portal frame at the entrance and the haulage rails out onto the
yard; mine_portal.glb. The interior beyond is build_mine.py's portal adit."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector, Matrix, noise
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
MINE='--' in sys.argv and 'mine' in sys.argv[sys.argv.index('--'):]
OUT=ROOT/'assets/caves-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/qa'/('mine-portal' if MINE else 'cave-mouth');QA.mkdir(parents=True,exist_ok=True)
def surface(name,folder,stem,scale,roughness):
    # the cave interiors' natural rock (Codex 305): base colour + normal map, no masonry
    m=C.mat(name,(1,1,1,1),roughness);m['uv_metres']=scale
    nodes=m.node_tree.nodes;links=m.node_tree.links;bsdf=nodes['Principled BSDF']
    tex=nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/folder/(stem+'_diff_1k.jpg')),check_existing=True);tex.image.pack()
    links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    nor=nodes.new('ShaderNodeTexImage')
    nor.image=bpy.data.images.load(str(ROOT/folder/(stem+'_nor_gl_1k.jpg')),check_existing=True);nor.image.pack()
    nor.image.colorspace_settings.name='Non-Color'
    nm=nodes.new('ShaderNodeNormalMap')
    links.new(nor.outputs['Color'],nm.inputs['Color']);links.new(nm.outputs['Normal'],bsdf.inputs['Normal'])
    return m
ROCK=surface('CM rock','assets/environment/cave-rock-v1','rock_face_03',4,.95)
EARTH=surface('CM earth','assets/environment/village-surfaces-v1','forest_ground_04',3,.98)
DARK=C.mat('CM dark',(.02,.02,.02,1),1.0)
TIMBER=C.mat('CM timber',(.36,.26,.17,1),.9)
IRON=C.mat('CM iron',(.16,.15,.14,1),.45,.6)
# Boulder: icosphere, displaced for a rough stone look.
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4,radius=1,location=(0,3.5,1.4))
rock=bpy.context.active_object
rock.name='cave mouth rock-col'
rock.scale=(8.0,6.5,5.0)
bpy.ops.object.transform_apply(scale=True)
tex=bpy.data.textures.new('CM noise','CLOUDS')
tex.noise_scale=2.2
mod=rock.modifiers.new('d','DISPLACE')
mod.texture=tex;mod.strength=1.8;mod.mid_level=0.5
bpy.context.view_layer.objects.active=rock
bpy.ops.object.modifier_apply(modifier='d')
# The hill the arch goes into (in-game frames: a lone boulder on a meadow read as a stone with a
# hole): a mass behind and two shoulders, joined to the front rock before the tunnel is cut.
for k,(loc,scl) in enumerate((((0,11.0,1.8),(11.0,8.0,6.8)),((-8.5,5.5,0.4),(5.0,6.0,4.2)),((8.8,6.5,0.6),(5.5,5.5,4.6)))):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3,radius=1,location=loc)
    m=bpy.context.active_object;m.scale=scl;bpy.ops.object.transform_apply(scale=True)
    t=bpy.data.textures.new('CM noise %d'%k,'CLOUDS');t.noise_scale=2.6
    d=m.modifiers.new('d','DISPLACE');d.texture=t;d.strength=1.6;d.mid_level=.5
    bpy.context.view_layer.objects.active=m;bpy.ops.object.modifier_apply(modifier='d')
    u=rock.modifiers.new('u','BOOLEAN');u.operation='UNION';u.solver='EXACT';u.object=m
    bpy.context.view_layer.objects.active=rock;bpy.ops.object.modifier_apply(modifier='u')
    bpy.data.objects.remove(m)
# Cut the bottom flat 2 m under the ground (z=-2): on a slope the rock stays sunk in, no gap under it.
bpy.ops.mesh.primitive_cube_add(size=1,location=(0,3.0,-7.0))
cut=bpy.context.active_object
cut.scale=(30,30,10)
bpy.ops.object.transform_apply(scale=True)
mod=rock.modifiers.new('cut','BOOLEAN')
mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cut
bpy.context.view_layer.objects.active=rock
bpy.ops.object.modifier_apply(modifier='cut')
bpy.data.objects.remove(cut)
# Tunnel (no drilled tube): rings of an irregular arch along +y, flared at the entrance and narrowing
# inward; every vertex jittered by noise. Centre 1.45 m over the floor; the bottom runs under it.
K=20;rings=[]
ys=[-5.0+i*1.0 for i in range(15)]  # -5 .. 9
bmt=bmesh.new()
for y in ys:
    d=y+3.0  # depth past the rock's front
    flare=1.0+0.45*math.exp(-max(d,0.0)/1.6)
    narrow=1.0-0.12*max(0.0,min(1.0,d/8.0))
    rw,rh=1.9*flare*narrow,1.9*flare*narrow
    if MINE:  # a squared adit cut by hand: a superellipse, barely jittered, a little flare
        rw,rh=1.7*(1+0.12*math.exp(-max(d,0.0)/1.2)),1.75
    ring=[]
    for i in range(K):
        a=2*math.pi*i/K
        if MINE:
            c,sn=math.cos(a),math.sin(a)
            x,z=rw*math.copysign(abs(c)**0.5,c),1.45+rh*math.copysign(abs(sn)**0.5,sn)
        else:
            x,z=rw*math.cos(a),1.45+rh*math.sin(a)
        j=noise.noise(Vector((x*.7,y*.7,z*.7)))*(0.08 if MINE else 0.4)
        r=Vector((x,0,z-1.45)).normalized()
        ring.append(bmt.verts.new((x+r.x*j,y,z+r.z*j)))
    rings.append(ring)
for r0,r1 in zip(rings,rings[1:]):
    for i in range(K):
        bmt.faces.new((r0[i],r0[(i+1)%K],r1[(i+1)%K],r1[i]))
bmt.faces.new(rings[0][::-1]);bmt.faces.new(rings[-1])
bmesh.ops.recalc_face_normals(bmt,faces=bmt.faces[:])
tun=bpy.data.objects.new('tunnel',bpy.data.meshes.new('tunnel'));bmt.to_mesh(tun.data);bmt.free()
bpy.context.scene.collection.objects.link(tun)
mod=rock.modifiers.new('tunnel','BOOLEAN')
mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=tun
bpy.context.view_layer.objects.active=rock
bpy.ops.object.modifier_apply(modifier='tunnel')
bpy.data.objects.remove(tun)
# Tunnel floor/threshold.
fl=C.box('mouth floor-col',(0,4.0,-.05),(5.6,11.0,.1),EARTH)
bm=bmesh.new();bm.from_mesh(fl.data);bmesh.ops.subdivide_edges(bm,edges=bm.edges[:],cuts=8,use_grid_fill=True);bm.to_mesh(fl.data);bm.free()  # vertices for the darkness gradient  # wider than the arch at the floor: no trench by the walls
# Dark plug closing the far end of the tunnel (no light leak).
C.box('mouth depth',(0,8.6,1.6),(4.4,.1,4.4),DARK)
if MINE:
    # timber sets every 1.6 m in the adit, the portal frame at its mouth, the rails out onto the yard
    for k in range(9):
        yk=-3.4+k*1.6
        for sx in (-1,1):C.box('portal post',(sx*1.45,yk,1.4),(.22,.22,2.8),TIMBER,0)
        C.box('portal cap',(0,yk,2.9),(3.2,.24,.24),TIMBER,0)
    for sx in (-1,1):C.box('portal frame post',(sx*1.6,-4.6,1.6),(.4,.4,3.2),TIMBER,0)
    C.box('portal frame lintel',(0,-4.6,3.35),(4.2,.45,.45),TIMBER,0)
    for k in range(int(20/0.75)):
        C.box('rail sleeper',(0,-10.5+k*0.75,.05),(1.3,.22,.1),TIMBER,0)
    for sx in (-1,1):C.box('rail',(sx*.45,-0.5,.135),(.06,20.0,.07),IRON,0)
# Transition marker: empty inside the tunnel; local +y points into the cave.
e=bpy.data.objects.new('CavePortal',None)
e.location=(0,2.5,0);e.empty_display_size=1.0
C.ASSET.objects.link(e)
# Move the ops-created rock from the scene collection into ASSET and set its material.
for col in list(rock.users_collection):col.objects.unlink(rock)
C.ASSET.objects.link(rock)
rock.data.materials.clear();rock.data.materials.append(ROCK)
# Darkness into the hill as a vertex colour (the world multiplies the albedo by it): white outside,
# down to 6% at the plug, so the arch reads dark like a cave and the plug is no flat black disc.
for o in [o for o in C.ASSET.objects if o.type=='MESH']:
    attr=o.data.color_attributes.new('Col','BYTE_COLOR','CORNER')
    for loop in o.data.loops:
        c=o.matrix_world@o.data.vertices[loop.vertex_index].co
        inside=abs(c.x)<3.4 and c.z<4.6 and c.y>-3.5
        k=max(0.0,min(1.0,(c.y+2.5)/9.0)) if inside else 0.0
        g=1.0-0.94*k**0.8
        attr.data[loop.index].color=(g,g,g,1.0)
    o.data.color_attributes.active_color=attr
# UVs for the textured rock: projected in metres on each face's dominant axis.
for o in [o for o in C.ASSET.objects if o.type=='MESH']:
    scale=o.data.materials[0].get('uv_metres',0) if o.data.materials else 0
    if not scale:continue
    bm=bmesh.new();bm.from_mesh(o.data);bm.normal_update()
    uv=bm.loops.layers.uv.get('UVMap') or bm.loops.layers.uv.new('UVMap')
    for face in bm.faces:
        axis=max(range(3),key=lambda i:abs(face.normal[i]))
        for loop in face.loops:
            q=o.matrix_world@loop.vert.co
            u,v=((q.y,q.z) if axis==0 else (q.x,q.z) if axis==1 else (q.x,q.y))
            loop[uv].uv=(u/scale,v/scale)
    bm.to_mesh(o.data);bm.free()
# Export GLB.
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=next(o for o in C.ASSET.objects if o.type=='MESH')
asset=OUT/('mine_portal.glb' if MINE else 'cave_mouth.glb')
# no images in the GLB: the world gives the rock and ground their textures (triplanar) from
# assets/environment at runtime (world_cave_mouths.gd), so the file stays small
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False,export_image_format='NONE',export_vertex_color='ACTIVE')
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'cave_mouth.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH']
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'asset':'mine_portal' if MINE else 'cave_mouth','triangles':triangles,'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'portal':'CavePortal at (0,2.5,0), +y into the cave','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
