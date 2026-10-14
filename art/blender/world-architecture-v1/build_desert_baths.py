"""Book141 baths12x7 from accepted desert city plan. Production WIP."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/desert-baths';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DB stone','stone_wall_02_diff_1k.jpg',2)
LIME=surface('DB lime','plaster_grey_04_diff_1k.jpg',2)
WOOD=surface('DB timber','fine_grained_wood_col_1k.jpg',.65)
CLOTH=C.mat('DB shade',(.34,.28,.18,1),.98)
WATER=C.mat('DB basin water',(.075,.18,.20,1),.18)
LINEN=C.mat('DB muted bedding',(.25,.22,.16,1),.98)
IRON=C.mat('DB stove iron',(.09,.10,.11,1),.9)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('changing bench','bench support','towel shelf','shelf bracket')):o['part_role']='interior_furniture'
    if solid:coll.append((n,p,s))
    return o
pools=[(-.15,0),(3.35,0)]
# Ground slab is split round two real recessed pools.
xs=[-6,-1.5,1.2,2,4.7,6];ys=[-3.5,-1.8,1.8,3.5]
for a,b in zip(xs,xs[1:]):
    for c,d in zip(ys,ys[1:]):
        if c==-1.8 and a in (-1.5,2):continue
        box('walkable stone floor',((a+b)/2,(c+d)/2,-.12),(b-a,d-c,.24),STONE)
for x,y in pools:
    box('pool foundation',(x,y,-.82),(2.7,3.6,.24),STONE)
    for side in (-1,1):
        port=.8 if x<0 and side<0 else -.8
        for a,b in [(-1.8,port-.24),(port+.24,1.8)]:
            box('pool port pier',(x+side*1.24,(a+b)/2,-.29),(.22,b-a,.82),STONE)
        box('pool port sill',(x+side*1.24,port,-.66),(.22,.48,.08),STONE)
        box('pool port header',(x+side*1.24,port,-.13),(.22,.48,.50),STONE)
        if side<0:box('pool short wall',(x,y+side*1.69,-.29),(2.26,.22,.82),STONE)
        else:
            for dx in (-.815,.815):box('pool entry jamb',(x+dx,1.69,-.29),(.63,.22,.82),STONE)
    C.mesh('WaterSurface',[(x-1.13,-1.58,-.12),(x+1.13,-1.58,-.12),(x+1.13,1.58,-.12),(x-1.13,1.58,-.12)],[(0,1,2,3)],WATER)['part_role']='water_surface'
    # Three shallow supported steps reach the floor instead of a sheer drop.
    for k in range(3):
        top=-.18*(k+1)
        box('pool entry step',(x,1.4-k*.35,(top-.7)/2),(.85,.35,top+.7),STONE,False)
    # Continuous collision follows the shallow stair run, including the lower landing.
    length=math.hypot(1.55,.7)
    ramp=C.box('pool stair ramp-colonly',(x,1.075,-.41),(.85,length,.12),STONE,0)
    ramp.rotation_euler.x=math.atan2(.7,1.55);ramp.hide_render=True
# Covered ducts lie below the dry floor. Their chambers are genuinely hollow.
def duct(axis,fixed,a,b):
    middle=(a+b)/2;length=b-a
    for z in (-.66,-.34):
        p=(middle,fixed,z) if axis=='x' else (fixed,middle,z)
        size=(length,.48,.08) if axis=='x' else (.48,length,.08)
        box('covered duct slab',p,size,STONE)
    for side in (-1,1):
        p=(middle,fixed+side*.20,-.5) if axis=='x' else (fixed+side*.20,middle,-.5)
        size=(length,.08,.24) if axis=='x' else (.08,length,.24)
        box('covered duct cheek',p,size,STONE)
duct('x',.8,-6,-1.28)
duct('x',-.8,1.0,2.22)
duct('x',-.8,4.46,6)
for name,p in [('HotInlet',(-6,.8,-.5)),('WasteOutlet',(6,-.8,-.5))]:
    marker=bpy.data.objects.new(name,None);C.ASSET.objects.link(marker);marker.location=p
    marker['clear_width']=.32;marker['sill_level']=-.62;marker['head_level']=-.38
box('front west pier',(-5.325,-3.3,1.6),(1.35,.4,3.2),LIME)
box('front east pier',(1.325,-3.3,1.6),(9.35,.4,3.2),LIME)
box('entry lintel',(-4,-3.3,2.8),(1.3,.4,.8),LIME)
box('back wall',(0,3.3,1.6),(12,.4,3.2),LIME)
for x in (-5.8,5.8):
    for lo,hi in [(-3.1,-1.2),(1.2,3.1)]:box('side wall',(x,(lo+hi)/2,1.6),(.4,hi-lo,3.2),LIME)
    box('window sill',(x,0,.75),(.4,2.4,1.5),LIME)
    box('window header',(x,0,2.95),(.4,2.4,.5),LIME)
# Changing room passage; no partition through either basin.
for lo,hi in [(-3.1,-3.0),(-1.6,3.1)]:box('changing room wall',(-2,(lo+hi)/2,1.6),(.20,hi-lo,3.2),LIME)
box('changing doorway lintel',(-2,-2.3,2.8),(.2,1.4,.8),LIME)
for y in (-1.8,1.8):
    box('changing bench',(-4.5,y,.46),(2.1,.45,.1),WOOD)
    for x in (-5.3,-3.7):box('bench support',(x,y,.205),(.12,.40,.41),WOOD)
box('towel shelf',(-5.48,0,1.35),(.6,1.8,.1),WOOD)
for y in (-.8,.8):box('shelf bracket',(-5.6,y,1.12),(.35,.10,.36),WOOD)
for y in (-.5,0,.5):box('folded towel',(-5.43,y,1.45),(.42,.35,.10),CLOTH,False)
# Supported wash bowl clear of the rear bench and tested return aisle.
box('wash pedestal',(-5,2.55,.32),(.50,.42,.64),STONE)
box('wash bowl floor',(-5,2.55,.69),(.8,.56,.10),STONE)
for x in (-5.36,-4.64):box('wash bowl side',(x,2.55,.81),(.08,.56,.24),STONE)
for y in (2.31,2.79):box('wash bowl end',(-5,y,.81),(.64,.08,.24),STONE)
box('wash water',(-5,2.55,.79),(.62,.38,.01),WATER,False)
for x in (-5.8,5.8):
    for y in (-1.2,1.2):box('window jamb',(x,y,2.10),(.48,.10,1.3),WOOD,False)
    for z in (1.5,2.7):box('window lintel',(x,0,z),(.48,2.6,.10),WOOD,False)
box('ceiling',(0,0,3.16),(12,7,.12),LIME)
roof=box('flat roof',(0,0,3.4),(13,8,.24),LIME,False)
roof.rotation_euler.x=-math.atan(.015)
roof_collision=C.box('sloped roof-colonly',(0,0,3.4),(13,8,.24),LIME,0)
roof_collision.rotation_euler.x=roof.rotation_euler.x;roof_collision.hide_render=True
for x in (-6.35,6.35):box('roof parapet',(x,0,3.64),(.3,8,.36),LIME)
box('front roof parapet',(0,-3.85,3.64),(12.4,.3,.36),LIME)
for a,b in [(-6.2,-4.8),(-4.4,4.4),(4.8,6.2)]:box('rear roof parapet',((a+b)/2,3.85,3.64),(b-a,.3,.36),LIME)
for x in (-4.6,4.6):
    # Outlet extends to the existing eave edge without increasing the footprint.
    for side in (-1,1):
        cheek=box('roof drain cheek',(x+side*.17,3.72,3.54-.015*3.72),(.06,.56,.12),LIME)
        cheek.rotation_euler.x=-math.atan(.015)
door_parts=[]
hinge=bpy.data.objects.new('DB_entry_hinge',None);C.ASSET.objects.link(hinge);hinge.location=(-4.65,-3.3,0);hinge['open_angle_degrees']=-100
for k in range(5):
    part=box('Door plank',(-4.52+k*.26,-3.3,1.18),(.252,.08,2.36),WOOD,False)
    part.parent=hinge;part.location-=Vector((-4.65,-3.3,0));door_parts.append(part)

visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
for o in visual:
    scale=o.data.materials[0].get('uv_metres',0)
    if not scale:continue
    bm=bmesh.new();bm.from_mesh(o.data);uv=bm.loops.layers.uv.verify()
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
asset=OUT/'d_baths.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
tints={'DB lime':(.78,.68,.52),'DB stone':(.72,.63,.49),'DB timber':(.32,.23,.15),'DB shade':(.34,.28,.18)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_baths.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; peer and campaign/mobile QA pending','walls':[12,7],'maximum_height':3.82,'triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
