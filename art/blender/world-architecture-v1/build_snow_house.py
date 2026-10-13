"""Independent S-H warm Conclave house; approved PDF141, wall footprint8x7m.
Rebuild with Blender --background --factory-startup --python-exit-code1 --python.
GLB only under assets; measurements/BLEND/render previews remain under local.
"""
import sys,math,json,hashlib,random,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset();random.seed(11801)
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/snow-house';QA.mkdir(parents=True,exist_ok=True)
collision=[];roof_collision=[]
def paint(name,c):
    m=C.mat(name,(*c,1),.95)
    im=bpy.data.images.new(name+'_paint',width=256,height=256)
    px=[]
    for y in range(256):
        for x in range(256):
            v=.022*math.sin(x*.039+y*.023)+.012*math.sin(y*.073-x*.013)+random.uniform(-.004,.004)
            px.extend([max(0,min(1,t+v)) for t in c]+[1])
    im.pixels.foreach_set(px);im.pack()
    node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=im
    m.node_tree.links.new(node.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
def surface(name,filename,tint,metres):
    m=C.mat(name,(*tint,1),.96);m['uv_metres']=metres
    im=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/filename),check_existing=True)
    im.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('S cool stone','stone_wall_02_diff_1k.jpg',(.61,.66,.68),2)
PLASTER=surface('S grey limewash','plaster_grey_04_diff_1k.jpg',(.78,.80,.76),3)
WOOD=surface('S dark timber','fine_grained_wood_col_1k.jpg',(.30,.24,.18),.65)
SLATE=paint('S slate',(.10,.135,.15))
LINEN=C.mat('S warm linen',(.35,.31,.23,1));IRON=C.mat('S iron',(.07,.075,.078,1))
CLAY=C.mat('S stove clay',(.27,.24,.20,1));FLOOR=paint('S floor boards',(.22,.16,.105))
def box(n,p,s,m,solid=False,bevel=.02):
    o=C.box(n,p,s,m,bevel)
    if solid:collision.append((n,p,s))
    return o
def wx(n,y,a,b,z0=0,z1=3.1,m=PLASTER):return box(n,((a+b)/2,y,(z0+z1)/2),(b-a,.36,z1-z0),m,True)
def wy(n,x,a,b,z0=0,z1=3.1,m=PLASTER):return box(n,(x,(a+b)/2,(z0+z1)/2),(.36,b-a,z1-z0),m,True)
def doorway(n,y,lo,hi,width):
    wx(n+' left',y,lo,-width/2);wx(n+' right',y,width/2,hi)
    wx(n+' lintel',y,-width/2,width/2,2.35)
    for x in (-width/2-.06,width/2+.06):box(n+' jamb',(x,y,1.16),(.12,.43,2.32),WOOD)
    box(n+' head',(0,y,2.44),(width+.3,.43,.16),WOOD)
box('floor',(0,0,-.12),(8,7,.24),FLOOR,True,0)
doorway('entry',-3.32,-3.82,3.82,1.3)
wy('west wall',-3.82,-3.14,3.14);wy('east wall',3.82,-3.14,3.14)
# Rear windows pierce the actual wall and illuminate the living/sleeping area.
for a,b in [(-3.82,-2.8),(-1.8,1.8),(2.8,3.82)]:wx('rear wall pier',3.32,a,b)
for x in (-2.3,2.3):
    wx('rear sill',3.32,x-.5,x+.5,0,1.15);wx('rear header',3.32,x-.5,x+.5,2.05)
    box('window ledge',(x,3.32,1.15),(1.12,.48,.12),STONE)
    for dx in (-.53,.53):box('window frame',(x+dx,3.32,1.6),(.09,.4,1.0),WOOD)
    box('window mullion',(x,3.32,1.6),(.07,.13,.95),WOOD)
# Vestibule within the footprint; two clear openings prevent wind through the room.
doorway('vestibule door',-1.95,-1.45,1.45,1.2)
for x in (-1.45,1.45):wy('vestibule cheek',x,-3.14,-2.13,0,2.6,WOOD)
box('vestibule ceiling',(0,-2.60,2.67),(3.0,1.75,.15),WOOD,True)
# Stone base and timber frame are shared in silhouette with the approved Conclave plate.
for y in (-3.52,3.52):
    for k in range(10):
        x=-3.6+k*.8
        if y<0 and abs(x)<.9:continue
        box('stone base',(x,y,.21),(.77,.10,.42),STONE)
for x in (-4.02,4.02):
    for k in range(9):box('side stone base',(x,-3.2+k*.8,.21),(.10,.77,.42),STONE)
for x in (-3.78,3.78):
    for y in (-3.28,3.28):box('corner post',(x,y,1.75),(.23,.23,2.70),WOOD)
for y in (-3.31,3.31):box('wall plate',(0,y,3.0),(7.72,.22,.23),WOOD)
for x in (-3.82,3.82):box('side plate',(x,0,3.0),(.22,6.6,.23),WOOD)
# Closed loft with a real narrow ventilation aperture in each gable.
def gable_band(name,y,outline):
    n=len(outline)
    vs=[(x,y+offset,z) for offset in (-.12,.12) for x,z in outline]
    fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    fs += [(k,(k+1)%n,(k+1)%n+n,k+n) for k in range(n)]
    return C.mesh(name,vs,fs,PLASTER)
for y in (-3.32,3.32):
    low,high=4.77,5.43
    wl=3.95*(7.1-low)/4.02;wh=3.95*(7.1-high)/4.02
    gable_band('gable lower',y,[(-3.95,3.08),(3.95,3.08),(wl,low),(-wl,low)])
    gable_band('gable vent left',y,[(-wl,low),(-.22,low),(-.22,high),(-wh,high)])
    gable_band('gable vent right',y,[(.22,low),(wl,low),(wh,high),(.22,high)])
    gable_band('gable upper',y,[(-wh,high),(wh,high),(0,7.1)])
    C.beam('gable left rake',(-3.98,y-.16,3.07),(0,y-.16,7.13),.18,.18,WOOD)
    C.beam('gable right rake',(3.98,y-.16,3.07),(0,y-.16,7.13),.18,.18,WOOD)
    box('gable king post',(0,y-.16,5.0),(.17,.18,3.85),WOOD)
    box('gable tie',(0,y-.16,4.34),(5.5,.18,.15),WOOD)
    for x in (-1.45,1.45):box('gable upright',(x,y-.16,4.36),(.12,.16,2.25),WOOD)
    for x in (-.25,.25):box('vent surround',(x,y-.18,5.1),(.065,.10,.76),WOOD)
    for z in (4.82,5.03,5.24,5.43):box('vent rain louvre',(0,y-.20,z),(.45,.15,.055),WOOD)
# Slate panels support individually offset overlapping tiles, not metal-like strips.
for side in (-1,1):
    x=side*4.28
    vs=[(0,-3.82,7.22),(x,-3.82,3.12),(x,3.82,3.12),(0,3.82,7.22),(0,-3.82,7.08),(x,-3.82,2.98),(x,3.82,2.98),(0,3.82,7.08)]
    faces=[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
    C.mesh('slate roof',vs,faces,SLATE)
    roof_collision.append((vs,faces))
    for row in range(12):
        a=(row+.03)/12;b=min(1,(row+1.04)/12)
        shift=.30 if row%2 else 0
        for col in range(14):
            y0=max(-3.8,-4.10+col*.60+shift);y1=min(3.8,-3.52+col*.60+shift)
            if y1-y0<.05:continue
            xa,xb=side*4.28*a,side*4.28*b
            za,zb=7.22-4.1*a+.035,7.22-4.1*b+.060
            tile=[(xa,y0,za),(xb,y0,zb),(xb,y1,zb),(xa,y1,za)]
            tile += [(xx,yy,zz-.025) for xx,yy,zz in tile]
            C.mesh('overlapping slate tile',tile,faces,SLATE)
    C.beam('eaves trim',(side*4.28,-3.85,3.08),(side*4.28,3.85,3.08),.17,.17,WOOD)
C.beam('ridge cap',(0,-3.9,7.25),(0,3.9,7.25),.18,.16,SLATE)
# Chimney is connected to a substantial masonry stove, with protected dry storage nearby.
box('stove',(2.85,2.5,.70),(1.18,1.16,1.4),CLAY,True)
box('stove hatch',(2.85,1.91,.52),(.48,.08,.42),IRON)
box('stove hood',(2.85,2.5,1.5),(1.25,1.2,.18),STONE)
box('stove flue',(2.85,2.5,2.2),(.43,.43,1.45),STONE)
box('chimney',(2.85,2.5,4.1),(.60,.60,2.42),STONE,True)
box('chimney cap',(2.85,2.5,5.42),(.78,.78,.15),STONE)
box('bed',(-2.68,2.06,.35),(1.25,2.0,.20),WOOD,True)
box('mattress',(-2.68,2.06,.51),(1.18,1.92,.17),LINEN)
for x in (-3.18,-2.18):
    for y in (1.24,2.88):box('bed leg',(x,y,.18),(.13,.13,.36),WOOD)
box('headboard',(-2.68,2.98,.64),(1.26,.12,.95),WOOD)
box('table',(.05,.7,.74),(1.35,.85,.1),WOOD,True)
for x in (-.47,.57):
    for y in (.38,1.02):box('table leg',(x,y,.35),(.1,.1,.70),WOOD)
box('drying rack rail',(2.65,-.60,1.93),(1.3,.1,.12),WOOD)
for x in (2.05,3.25):box('drying rack post',(x,-.6,.95),(.1,.1,1.9),WOOD)
for x in (2.3,2.8):box('drying cloth',(x,-.6,1.50),(.36,.045,.75),LINEN)
box('storage bench',(-2.95,-1.10,.47),(1.1,.65,.94),WOOD,True)
hinge=bpy.data.objects.new('S_entry_hinge',None);C.ASSET.objects.link(hinge)
hinge.location=(-.60,-3.32,0);hinge['open_angle_degrees']=-100.0
door_parts=[]
for k in range(5):door_parts.append(box('Door plank',(-.48+k*.24,-3.32,1.14),(.234,.08,2.28),WOOD))
for z in (.45,1.72):door_parts.append(box('Door strap',(0,-3.37,z),(1.18,.018,.06),IRON))
visual=[o for o in C.ASSET.objects if o.type=='MESH']
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
C._join_by_material([o for o in visual if o not in door_parts])
for o in door_parts:
    matrix=o.matrix_world.copy();o.parent=hinge;o.matrix_world=matrix
visual=[o for o in C.ASSET.objects if o.type=='MESH']
for n,p,s in collision:
    o=box(n+'-colonly',p,s,STONE,False,0);o.hide_render=True
for k,(vs,fs) in enumerate(roof_collision):
    o=C.mesh('roof panel '+str(k)+'-colonly',vs,fs,SLATE);o.hide_render=True
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=visual[0]
asset=OUT/'s_warm_house.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True)
# Use explicit standard glTF factors so Blender and Godot keep the same tint.
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0]
document=json.loads(data[20:20+size])
tints={'S cool stone':(.61,.66,.68),'S grey limewash':(.78,.80,.76),'S dark timber':(.30,.24,.18)}
for m in document['materials']:
    if m['name'] in tints:m['pbrMetallicRoughness']['baseColorFactor']=[*tints[m['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
remaining=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(remaining))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+remaining)
tri=0
for o in visual:o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
stats={'triangles':tri,'meshes':len(visual),'collision_boxes':len(collision),'roof_collisions':len(roof_collision),'wall_footprint':[8,7],'bbox':[[min(v[i] for v in points) for i in range(3)],[max(v[i] for v in points) for i in range(3)]],'front':'Godot+Z','pivot':'floor0','attic':'ventilated,closed;notplayable','sha256':hashlib.sha256(asset.read_bytes()).hexdigest(),'state':'built;notaccepted;GodotQAandrenderreviewpending'}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
C.ASSET.objects.unlink(hinge)
C._studio();bpy.data.objects['PreviewGround'].location.z=-.26
C.ASSET.objects.link(hinge)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.cycles.use_denoising=True
scene.render.resolution_x=1280;scene.render.resolution_y=960;scene.render.resolution_percentage=100
cam=scene.camera;cam.rotation_mode='XYZ';cam.data.type='PERSP';cam.data.lens=40
for name,pos,target in [('exterior',(13,-16,10),(0,0,2.4)),('entry',(0,-6.4,1.7),(0,-.8,1.5)),('room',(1.1,-1.2,1.6),(-1.8,2.2,1.1))]:
    cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(QA/(name+'.png'));bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_warm_house.blend'))
print('S_H_BUILT',json.dumps(stats))
