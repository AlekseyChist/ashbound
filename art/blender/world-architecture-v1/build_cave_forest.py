"""Forest cave interior (WORLD-PLAN-01, CAVE-01): chambers, links, floors, exits."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/caves-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/qa/cave-forest';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
ROCK=surface('CV rock','stone_wall_02_diff_1k.jpg',3)
EARTH=C.mat('CV earth',(.32,.27,.21,1),.98)
def P(x,zs,h):
    return Vector((x,-zs,h))
CHAMBERS=[('E',0.0,0.0,6.0,5.0,0.0),('A',30.0,0.0,9.0,6.0,0.0),('B',65.0,-15.0,6.0,4.0,0.0),('C',75.0,22.0,13.0,9.0,-1.0),('X',110.0,30.0,5.0,4.0,0.0)]
LINKS=[('E','A',3.0),('A','B',1.2),('A','C',2.5),('C','X',1.6)]
EXITS=[('forest_cave:E','E'),('forest_cave:X','X')]
ch={c[0]:c for c in CHAMBERS}
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
# Flip normals so the shell is hollow (inner faces visible).
bm=bmesh.new();bm.from_mesh(base.data)
for f in bm.faces:f.normal_flip()
bm.to_mesh(base.data);bm.free()
base.data.materials.clear();base.data.materials.append(ROCK)
base.name='cave shell-col'
# Floors: elliptic discs per chamber.
for cid,x,zs,rx,rz,floor in CHAMBERS:
    bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=1,depth=0.3,location=P(x,zs,floor-0.15))
    o=bpy.context.active_object
    o.name='floor '+cid+'-col'
    o.scale=(rx*0.92,rz*0.92,1)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.clear();o.data.materials.append(EARTH)
    C.ASSET.objects.link(o)
# Floors: slanted boards per link.
for a,b,w in LINKS:
    xa,zsa,_,_,fa=ch[a];xb,zsb,_,_,fb=ch[b]
    C.beam('floor link '+a+'-'+b+'-col',P(xa,zsa,fa-0.15),P(xb,zsb,fb-0.15),w*0.95,0.3,EARTH)
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
# Export GLB.
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=next(o for o in C.ASSET.objects if o.type=='MESH')
asset=OUT/'forest_cave.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'forest_cave.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH']
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'cave':'forest_cave','chambers':5,'links':4,'exits':['forest_cave:E','forest_cave:X'],'triangles':triangles,'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
