"""Desert plot g1: workshops (potters, weavers), 6x5 m; canonical GLB source.

One workshop room. Door centred on the front (-y) wall. Left side: potter's
wheel with a shelf of pots against the left wall. Right side: loom in the
depth and a yarn work table near the door. Aisles x -0.5..0.5 stay clear from
the door to the rear wall.
"""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/qa/desert-workshop';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DW stone','stone_wall_02_diff_1k.jpg',2)
LIME=surface('DW lime','plaster_grey_04_diff_1k.jpg',2)
WOOD=surface('DW timber','fine_grained_wood_col_1k.jpg',.65)
CLOTH=C.mat('DW shade',(.36,.30,.20,1),.98)
CLAY=C.mat('DW clay',(.60,.38,.24,1),.9)
YARN=C.mat('DW yarn',(.48,.22,.16,1),.98)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('wheel','potter seat','shelf','pot','loom','weaver bench','yarn','work table','table leg')):
        o['part_role']='interior_furniture'
    if solid:coll.append((n,p,s))
    return o
# Shell: outer walls 6x5 (faces at x +-3, y +-2.5; inner faces +-2.6 / +-2.1), floor z=0, roof top ~3.6.
box('foundation',(0,0,-.15),(6,5,.3),STONE)
box('entry porch',(0,-3.1,-.12),(2.6,1.2,.24),STONE)
# Outer walls inside the 6x5 envelope: centre lines x +-2.8, y +-2.3, 0.4 thick.
# Front wall with 1.6 m door opening centred x=0 (x -0.8..0.8).
for a,b in [(-3,-.8),(.8,3)]:
    box('front wall',((a+b)/2,-2.3,1.6),(b-a,.4,3.2),LIME)
box('door header',(0,-2.3,2.75),(1.6,.4,.9),LIME)
# Rear wall, solid.
box('rear wall',(0,2.3,1.6),(6,.4,3.2),LIME)
# Left wall x=-2.8 with one window (y -0.5..0.5, sill 1.0, head 2.0).
box('side wall',(-2.8,0,.5),(.4,4.2,1.0),LIME)
for a,b in [(-2.1,-.5),(.5,2.1)]:
    box('side wall',(-2.8,(a+b)/2,2.1),(.4,b-a,2.2),LIME)
box('window head wall',(-2.8,0,2.6),(.4,1.0,1.2),LIME)
# Right wall x=2.8, solid.
box('side wall',(2.8,0,1.6),(.4,4.2,3.2),LIME)
# Ceiling and roof (slight slope via mesh).
FACES=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
def roof_piece(name,x0,x1,y0,y1,top,thick,material):
    vertices=[(x,y,top-y*.012+dz) for x in (x0,x1) for y in (y0,y1) for dz in (-thick,0)]
    return C.mesh(name,vertices,FACES,material)
box('ceiling',(0,0,3.12),(6,5,.16),WOOD)
roof_piece('flat lime roof',-3.3,3.3,-2.8,2.8,3.6,.15,LIME)
roof_piece('flat roof-colonly',-3.3,3.3,-2.8,2.8,3.6,.15,LIME).hide_render=True
# Parapet (eaves max 0.3 beyond walls).
for x in (-2.9,2.9):box('side parapet',(x,0,3.74),(.2,5.0,.48),LIME)
box('front parapet',(0,-2.4,3.74),(6,.2,.48),LIME)
# The rear parapet is open over the drain (x=0, 0.3 wide).
for a,b in [(-3,-.15),(.15,3)]:
    box('rear parapet',((a+b)/2,2.4,3.74),(b-a,.2,.48),LIME)
# Drainage: one channel through the rear parapet with an outside outlet.
roof_piece('drain base',-.15,.15,2.1,2.8,3.6,.06,STONE)
for dx in (-.14,.14):roof_piece('drain cheek',dx-.03,dx+.03,2.1,2.8,3.72,.12,STONE)
# Supported timber shade at entry (front, max 1.2 m projection).
for x in (-1.1,1.1):
    box('canopy footing',(x,-3.55,.10),(.24,.24,.2),STONE)
    box('canopy post',(x,-3.55,1.4),(.14,.14,2.4),WOOD)
    C.beam('canopy rafter',(x,-2.5,2.95),(x,-3.62,2.62),.12,.12,WOOD)
C.mesh('entry shade',[(-1.3,-2.5,2.96),(1.3,-2.5,2.96),(1.3,-3.64,2.62),(-1.3,-3.64,2.62)],[(0,1,2,3)],CLOTH)
# Potter's wheel on the left, with a seat.
box('wheel base',(-1.8,-.8,.225),(.5,.5,.45),WOOD)
box('wheel',(-1.8,-.8,.5),(.6,.6,.06),CLAY,False)
box('potter seat',(-1.8,-1.45,.22),(.4,.35,.44),WOOD)
# Shelf of pots against the left wall in the depth.
box('shelf back',(-2.55,1.2,1.0),(.06,1.6,2.0),WOOD)
for y in (.4,2.0):box('shelf side',(-2.35,y,1.0),(.4,.08,2.0),WOOD)
for z in (.06,.7,1.34,1.96):box('shelf board',(-2.35,1.2,z),(.4,1.6,.08),WOOD)
for z in (.7,1.34,1.96):
    for y in (.7,1.2,1.7):box('pot',(-2.35,y,z+.17),(.24,.24,.26),CLAY,False)
# Loom on the right in the depth, with a weaver bench.
for x in (1.1,2.3):box('loom upright',(x,1.4,.9),(.1,.1,1.8),WOOD)
box('loom beam',(1.7,1.4,1.75),(1.3,.1,.1),WOOD,False)
box('loom beam',(1.7,1.4,.35),(1.3,.1,.1),WOOD,False)
box('loom cloth',(1.7,1.4,1.05),(1.1,.02,1.3),YARN,False)
box('weaver bench',(1.7,.75,.22),(1.0,.35,.44),WOOD)
# Yarn work table on the right near the door.
box('work table',(1.7,-1.2,.78),(1.2,.6,.08),WOOD)
for dx in (-.5,.5):
    for dy in (-.22,.22):box('table leg',(1.7+dx,-1.2+dy,.37),(.07,.07,.74),WOOD,False)
for x in (1.35,1.75,2.1):box('yarn',(x,-1.2,.9),(.25,.25,.16),YARN,False)
# Door: EntryPortal, front hinge, open -100 deg.
door_parts=[]
portal=bpy.data.objects.new('EntryPortal',None);C.ASSET.objects.link(portal)
hinge=bpy.data.objects.new('EntryPortal_entry_hinge',None);C.ASSET.objects.link(hinge)
hinge.parent=portal;hinge.location=(-.8,-2.3,0);hinge['open_angle_degrees']=-100
for k in range(5):
    part=box('Door plank',(-.62+k*.31,-2.3,1.18),(.30,.08,2.36),WOOD,False)
    part.parent=hinge;part.location-=Vector((-.8,-2.3,0))
    door_parts.append(part)
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
for o in visual:
    scale=o.data.materials[0].get('uv_metres',0)
    if not scale:continue
    bm=bmesh.new();bm.from_mesh(o.data);bm.normal_update()
    # New from_pydata meshes default to Float2 in Blender 5.2; joining to boxes
    # would retain a separate empty UVMap, which glTF then exports as TEXCOORD_0.
    uv=bm.loops.layers.uv.get('UVMap') or bm.loops.layers.uv.new('UVMap')
    for face in bm.faces:
        axis=max(range(3),key=lambda i:abs(face.normal[i]))
        for loop in face.loops:
            p=o.matrix_world@loop.vert.co
            u,v=((p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y))
            loop[uv].uv=(u/scale,v/scale)
    bm.to_mesh(o.data);bm.free()
inside=[o for o in visual if o.get('part_role')=='interior_furniture']
shell=[o for o in visual if o not in door_parts and o.get('part_role')!='interior_furniture']
C._join_by_material(shell)
C._join_by_material(inside)
for n,p,s in coll:C.box(n+'-colonly',p,s,STONE,0).hide_render=True
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=next(o for o in C.ASSET.objects if o.type=='MESH')
asset=OUT/'d_workshop_6x5.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
tints={'DW lime':(.80,.70,.54),'DW stone':(.72,.63,.49),'DW timber':(.33,.24,.16)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_workshop_6x5.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; Codex export and Godot review pending','walls':[6,5],'maximum_height':4.0,'rooms':['workshop'],'triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'entry_hinge':'EntryPortal_entry_hinge at (-0.8,-2.3,0), open -100 deg','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
