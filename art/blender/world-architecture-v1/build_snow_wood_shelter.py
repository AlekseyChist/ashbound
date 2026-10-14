"""Separate S-S fuel shelter. Place by the approved site plan, outside grain storage."""
import sys,math,json,hashlib,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/snow-store';QA.mkdir(parents=True,exist_ok=True)
def surface(name,filename,metres):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=metres
    im=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/filename),check_existing=True);im.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
WOOD=surface('S shelter weathered boards','fine_grained_wood_col_1k.jpg',.65)
END=C.mat('S split firewood ends',(.45,.34,.22,1),.96)
STONE=surface('S shelter feet','stone_wall_02_diff_1k.jpg',1)
COL=[]
def box(n,p,s,m,solid=False):
    o=C.box(n,p,s,m,.015)
    if solid:COL.append((n,p,s))
    return o
box('raised floor',(0,0,.16),(3,2,.16),WOOD,True)
for x in (-1.3,1.3):
    for y in (-.8,.8):
        box('stone foot',(x,y,.10),(.32,.32,.20),STONE)
        height=2.2 if y<0 else 1.9
        box('post',(x,y,height/2),(.15,.15,height),WOOD,True)
for y in (-.83,.83):box('sill',(0,y,.31),(2.75,.12,.13),WOOD)
for x in (-1.3,1.3):box('side sill',(x,0,.31),(.12,1.66,.13),WOOD)
for k in range(14):
    x=-1.3+k*.20
    box('rear ventilation slat',(x,.85,1.03),(.12,.08,1.42),WOOD)
vs=[(-1.65,-1.15,2.3),(1.65,-1.15,2.3),(1.65,1.15,1.86),(-1.65,1.15,1.86)]
vs += [(x,y,z-.12) for x,y,z in vs]
faces=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
C.mesh('weather roof',vs,faces,WOOD)
# Stacked split billets rest on the raised floor, leaving an open access strip.
for row in range(4):
    for k in range(10):
        x=-1.05+k*.23;z=.345+row*.19
        radius=.105
        verts=[(x+radius*math.cos(a*math.pi/4),y,z+radius*math.sin(a*math.pi/4)) for y in (.05,.70) for a in range(8)]
        f=[tuple(reversed(range(8))),tuple(range(8,16))]+[(a,(a+1)%8,(a+1)%8+8,a+8) for a in range(8)]
        C.mesh('split billet',verts,f,END)
COL.append(('fuel pile',(0,.38,.625),(2.4,.85,.77)))
visual=list(C.ASSET.objects)
for o in visual:
    scale=float(o.data.materials[0].get('uv_metres',0))
    if not scale:continue
    bm=bmesh.new();bm.from_mesh(o.data);uv=bm.loops.layers.uv.verify()
    for face in bm.faces:
        axis=max(range(3),key=lambda i:abs(face.normal[i]))
        for loop in face.loops:
            p=o.matrix_world@loop.vert.co
            u,v=((p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y))
            loop[uv].uv=(u/scale,v/scale)
    bm.to_mesh(o.data);bm.free()
C._join_by_material(visual);visual=list(C.ASSET.objects)
for n,p,s in COL:
    o=box(n+'-colonly',p,s,WOOD);o.hide_render=True
o=C.mesh('shelter roof-colonly',vs,faces,WOOD);o.hide_render=True
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=visual[0]
path=OUT/'s_wood_shelter.glb'
bpy.ops.export_scene.gltf(filepath=str(path),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_cameras=False,export_lights=False)
data=path.read_bytes();size=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+size])
tints={'S shelter weathered boards':(.35,.28,.21),'S shelter feet':(.61,.66,.68)}
for m in doc['materials']:
    if m['name'] in tints:m['pbrMetallicRoughness']['baseColorFactor']=[*tints[m['name']],1]
encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
report={'status':'WIP: native visual and physics QA pending','bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
(QA/'wood-shelter-stats.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
C._studio();bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_wood_shelter.blend'))
print('S_WOOD_SHELTER_BUILT',json.dumps(report))
