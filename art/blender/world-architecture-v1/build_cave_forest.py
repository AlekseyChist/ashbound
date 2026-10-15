"""Forest cave interior (WORLD-PLAN-01, CAVE-01): chambers, links, floors, exits."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector, Matrix, noise
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/caves-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/qa/cave-forest';QA.mkdir(parents=True,exist_ok=True)
def surface(name,folder,stem,scale,roughness):
    # Natural tileable surfaces (Codex 305: no masonry, no flat colour): base colour + normal map.
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
ROCK=surface('CV rock','assets/environment/cave-rock-v1','rock_face_03',4,.95)
EARTH=surface('CV earth','assets/environment/village-surfaces-v1','forest_ground_04',3,.98)
def P(x,zs,h):
    return Vector((x,-zs,h))
CHAMBERS=[('E',0.0,0.0,6.0,5.0,0.0),('A',30.0,0.0,9.0,6.0,0.0),('B',65.0,-15.0,6.0,4.0,0.0),('C',75.0,22.0,13.0,9.0,-1.0),('X',110.0,30.0,5.0,4.0,0.0)]
LINKS=[('E','A',3.0),('A','B',1.2),('A','C',2.5),('C','X',1.6)]
EXITS=[('forest_cave:E','E'),('forest_cave:X','X')]
ch={c[0]:c[1:] for c in CHAMBERS}  # id -> (x, z of the scheme, rx, rz, floor)
volumes=[]
# Chambers: UV spheres, bottom 0.31H below floor, top H above floor.
for cid,x,zs,rx,rz,floor in CHAMBERS:
    H=2.6+0.25*min(rx,rz)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=16,radius=1,location=P(x,zs,floor+H*0.35))
    o=bpy.context.active_object
    o.name='chamber '+cid
    o.scale=(rx,rz,H*0.66)
    bpy.ops.object.transform_apply(scale=True)
    volumes.append(o)
# Links: cylinders between chamber centres, axis Z along the link.
for a,b,w in LINKS:
    xa,zsa,_,_,fa=ch[a];xb,zsb,_,_,fb=ch[b]
    h=max(2.4,w*1.1)
    pa=P(xa,zsa,fa+h*0.42);pb=P(xb,zsb,fb+h*0.42)
    L=(pb-pa).length
    bpy.ops.mesh.primitive_cylinder_add(vertices=20,radius=0.5,depth=1.0)
    o=bpy.context.active_object
    o.name='link '+a+'-'+b
    o.scale=(w,h,L)
    direction=(pb-pa).normalized()
    o.rotation_mode='QUATERNION'
    o.rotation_quaternion=direction.to_track_quat('Z','Y')
    o.location=(pa+pb)/2
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    volumes.append(o)
# Union all volumes into one shell.
base=volumes[0]
for other in volumes[1:]:
    mod=base.modifiers.new('u','BOOLEAN')
    mod.operation='UNION';mod.solver='EXACT';mod.object=other
    bpy.context.view_layer.objects.active=base
    bpy.ops.object.modifier_apply(modifier='u')
    bpy.data.objects.remove(other)
# The walkable top at a point: the highest floor collider over it (chamber discs at .92 of the
# ellipse, link boards w*.95 wide whose top runs fa->fb), else the nearest one's level.
def floor_at(x,y):
    best=None;near=(1e9,0.0)
    for cid,cx,zs,rx,rz,floor in CHAMBERS:
        d=math.hypot((x-cx)/(rx*.92),(y+zs)/(rz*.92))
        if d<=1.0:best=floor if best is None else max(best,floor)
        near=min(near,(d-1.0,floor))
    for a,b,w in LINKS:
        xa,zsa,_,_,fa=ch[a];xb,zsb,_,_,fb=ch[b]
        ax,ay,bx,by=xa,-zsa,xb,-zsb;L2=(bx-ax)**2+(by-ay)**2
        t=max(0.0,min(1.0,((x-ax)*(bx-ax)+(y-ay)*(by-ay))/L2))
        d=math.hypot(x-(ax+t*(bx-ax)),y-(ay+t*(by-ay)))/(w*.95/2)
        h=fa+t*(fb-fa)
        if d<=1.0:best=h if best is None else max(best,h)
        near=min(near,(d-1.0,h))
    return near[1] if best is None else best
# Flip normals so the shell is hollow (inner faces visible); then a finer mesh for the rock.
bm=bmesh.new();bm.from_mesh(base.data)
for f in bm.faces:f.normal_flip()
bmesh.ops.triangulate(bm,faces=bm.faces[:])
bmesh.ops.subdivide_edges(bm,edges=bm.edges[:],cuts=1,use_grid_fill=True)
bmesh.ops.triangulate(bm,faces=bm.faces[:])
bm.normal_update()
# Natural shell: the bowl under the walkable level becomes the floor itself (no disc/strip seam:
# floor and wall are one surface), and the walls bulge OUTWARD only by noise, so the passable volume
# the capsule walked (Codex 305) only grows.
moves=[]
for v in bm.verts:
    q=v.co;f=floor_at(q.x,q.y)
    if q.z<=f+0.02:moves.append((v,Vector((q.x,q.y,f))));continue
    k=min(1.0,(q.z-f)/0.8)
    # Large slow bulges break the drilled-tube look of the links; fine grain on top; never inward.
    n=noise.noise(q*0.16)*0.45+noise.noise(q*0.5)*0.2+noise.noise(q*1.4)*0.07
    moves.append((v,q-v.normal*max(0.05,0.32+n)*k))
for v,co in moves:v.co=co
bm.normal_update()
# Ground where the surface faces up (inward normals), rock elsewhere.
for face in bm.faces:face.material_index=1 if face.normal.z>0.6 else 0
bm.to_mesh(base.data);bm.free()
base.data.materials.clear();base.data.materials.append(ROCK);base.data.materials.append(EARTH)
base.name='cave shell-col'
# bpy.ops puts new objects in the scene's collection; the export takes the ASSET collection's
for o in list(base.users_collection):o.objects.unlink(base)
C.ASSET.objects.link(base)
# Floors: elliptic discs per chamber.
for cid,x,zs,rx,rz,floor in CHAMBERS:
    bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=1,depth=0.3,location=P(x,zs,floor-0.15))
    o=bpy.context.active_object
    o.name='floor '+cid+'-colonly'  # the capsule-tested collider; the visible floor is the shell's
    o.scale=(rx*0.92,rz*0.92,1)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.clear();o.data.materials.append(EARTH)
    C.ASSET.objects.link(o)
# Floors: slanted boards per link.
for a,b,w in LINKS:
    xa,zsa,_,_,fa=ch[a];xb,zsb,_,_,fb=ch[b]
    C.beam('floor link '+a+'-'+b+'-colonly',P(xa,zsa,fa-0.15),P(xb,zsb,fb-0.15),w*0.95,0.3,EARTH)
# Exits: empty markers at chamber edges.
for tag,cid in EXITS:
    x,zs,rx,rz,floor=ch[cid]
    if cid=='E':
        loc=P(-rx+1.0,0,0);rot=(0,0,math.pi)
    else:
        xc,zsc,_,_,_=ch['C']
        d=Vector((x-xc,-(zs-zsc),0)).normalized()
        loc=P(x,zs,floor)+Vector((d.x*(rx-1.0),d.y*(rx-1.0),0))
        rot=(0,0,math.atan2(d.y,d.x))
    e=bpy.data.objects.new('Exit_'+tag,None)
    e.location=loc;e.rotation_euler=rot
    C.ASSET.objects.link(e)
# The floors made by bpy.ops are in the scene's collection too: only ASSET's.
for o in list(C.ASSET.objects):
    for col in list(o.users_collection):
        if col!=C.ASSET:col.objects.unlink(o)
# UVs for the textured rock: projected in metres on each face's dominant axis (as the accepted
# generators do), so the stone keeps its scale on the vaults.
for o in [o for o in C.ASSET.objects if o.type=='MESH']:
    if not any(m.get('uv_metres',0) for m in o.data.materials):continue
    bm=bmesh.new();bm.from_mesh(o.data);bm.normal_update()
    uv=bm.loops.layers.uv.get('UVMap') or bm.loops.layers.uv.new('UVMap')
    for face in bm.faces:
        scale=o.data.materials[face.material_index].get('uv_metres',0) or 3
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
asset=OUT/'forest_cave.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'forest_cave.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and not o.name.endswith('-colonly')]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'cave':'forest_cave','chambers':5,'links':4,'exits':['forest_cave:E','forest_cave:X'],'triangles':triangles,'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
