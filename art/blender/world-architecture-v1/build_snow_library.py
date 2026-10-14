"""Book141 library: actual Snow city footprint10x7, lower reading hall."""
import sys, json, hashlib, math, struct
from pathlib import Path
import bpy, bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/snow-library';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('SL stone','stone_wall_02_diff_1k.jpg',2)
WOOD=surface('SL timber','fine_grained_wood_col_1k.jpg',.65)
PLASTER=surface('SL lime','plaster_grey_04_diff_1k.jpg',2)
SLATE=C.mat('SL slate',(.10,.135,.15,1),.95)
im=bpy.data.images.new('SL slate paint',width=256,height=256)
pixels=[]
for y in range(256):
    for x in range(256):
        v=.022*math.sin(x*.039+y*.023)+.012*math.sin(y*.073-x*.013)
        pixels.extend([max(0,min(1,t+v)) for t in (.10,.135,.15)]+[1])
im.pixels.foreach_set(pixels);im.pack()
tex=SLATE.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im;SLATE['uv_metres']=.65
SLATE.node_tree.links.new(tex.outputs['Color'],SLATE.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
BOOK=C.mat('SL bound books',(.20,.16,.11,1),.98)
COVER=C.mat('SL leather binding',(.045,.03,.022,1),.98)
IRON=C.mat('SL iron',(.09,.10,.11,1),.83)
coll=[];furniture=[]
def box(n,p,s,m,solid=True,bevel=.015):
    o=C.box(n,p,s,m,bevel)
    if solid:coll.append((n,p,s))
    return o
def prop(n,p,s,m=WOOD,solid=True,bevel=.015):
    o=box(n,p,s,m,solid,bevel);o['part_role']='interior_furniture';furniture.append(o);return o
box('lower foundation',(0,0,-3.35),(10,7,.3),STONE)
# Ceiling slab stops around both flights and their turning landing.
def flue_slab(n,z,thickness,x0,x1,y0,y1):
    for a,b,c,d in [(x0,.65,y0,y1),(1.55,x1,y0,y1),(.65,1.55,y0,-1.1),(.65,1.55,-.2,y1)]:
        box(n,((a+b)/2,(c+d)/2,z),(b-a,d-c,thickness),WOOD)
flue_slab('upper west slab',-.14,.28,-5,2,-3.5,3.5)
box('upper stair front slab',(3.5,-3.225,-.14),(3,.55,.28),WOOD)
box('upper stair rear slab',(3.5,2.4,-.14),(3,2.2,.28),WOOD)
def wall(n,axis,fixed,a,b,bottom,top,holes=(),material=STONE):
    cuts=sorted(set([a,b]+[v for h in holes for v in h[:2]]))
    for lo,hi in zip(cuts,cuts[1:]):
        opening=next((h for h in holes if lo>=h[0] and hi<=h[1]),None)
        bands=[(bottom,top)] if opening is None else [(bottom,opening[2]),(opening[3],top)]
        for z0,z1 in bands:
            if z1-z0<.001:continue
            p=((lo+hi)/2,fixed,(z0+z1)/2) if axis=='x' else (fixed,(lo+hi)/2,(z0+z1)/2)
            s=(hi-lo,.4,z1-z0) if axis=='x' else (.4,hi-lo,z1-z0)
            box(n,p,s,material,True,0)
for h in (-3.2,0):
    holes=[(-3.9,-2.1,h+1,h+2.4)] if h==0 else []
    front=holes+([(-.8,.8,0,2.5)] if h==0 else [])
    wall('front','x',-3.3,-5,5,h,h+3.2,front)
    wall('back','x',3.3,-5,5,h,h+3.2,holes if h==0 else [(-.8,.8,-3.2,-.7)])
    wall('west','y',-4.8,-3.1,3.1,h,h+3.2,[(-1,1,1,2.4)] if h==0 else [])
    wall('east','y',4.8,-3.1,3.1,h,h+3.2,[(1.6,2.6,1,2.4)] if h==0 else [])
# Supported U-stair: two10-rise flights .16/.28, clear width1.15.
# Upper start is at(2.7,1.05,0); bottom finishes at(4.05,1.05,-3.2).
for k in range(10):
    y=.91-k*.28
    box('upper descending tread',(2.7,y,-(k+1)*.16-.045),(1.15,.28,.09),WOOD,False)
    y=-1.75+.14+k*.28
    box('lower descending tread',(4.05,y,-1.6-(k+1)*.16-.045),(1.15,.28,.09),WOOD,False)
box('turn landing',(3.375,-2.35,-1.68),(2.5,1.2,.16),WOOD)
for x in (2.7,4.05):box('landing support',(x,-2.5,-2.48),(.22,.22,1.28),WOOD)
def ramp(n,x,y0,y1,z0,z1):
    length=math.hypot(y1-y0,z1-z0)
    p=(x,(y0+y1)/2,(z0+z1)/2-.06);s=(1.15,length,.12)
    o=C.box(n+'-colonly',p,s,STONE,0);o.rotation_euler.x=math.atan2(z1-z0,y1-y0);o.hide_render=True
    for side in (-.52,.52):C.beam(n+' stringer',(x+side,y0,z0-.12),(x+side,y1,z1-.12),.1,.18,WOOD)
    C.beam(n+' handrail',(x-.6,y0,z0+.95),(x-.6,y1,z1+.95),.08,.08,WOOD)
    for t in (0,.5,1):
        y=y0+(y1-y0)*t;z=z0+(z1-z0)*t
        box(n+' rail post',(x-.6,y,z+.46),(.08,.08,.92),WOOD,False)
ramp('upper ramp',2.7,-1.75,1.05,-1.6,0)
ramp('lower ramp',4.05,-1.75,1.05,-1.6,-3.2)
# Stairwell guard leaves the upper arrival at y1.05 connected to rear aisle.
box('stair opening rail',(1.98,-.9,.95),(.08,3.9,.08),WOOD)
for y in (-2.8,-.9,1.05):box('stair opening post',(1.98,y,.47),(.08,.08,.94),WOOD)
box('stair opening front rail',(3.3,-2.94,.95),(2.64,.08,.08),WOOD)
for x in (1.98,3.3,4.62):box('stair opening front post',(x,-2.94,.47),(.08,.08,.94),WOOD)
# Only the upper-flight entrance remains open at the rear of the stairwell.
box('stair opening rear rail',(3.99,1.3,.95),(1.26,.08,.08),WOOD)
for x in (3.36,4.62):box('stair opening rear post',(x,1.3,.47),(.08,.08,.94),WOOD)
flue_slab('upper ceiling',3.14,.12,-5,5,-3.5,3.5)
for x in (-4.7,0,4.7):box('cross tie',(x,0,2.97),(.18,6.3,.18),WOOD)
# Steep snow roof, closed gables and generous eaves.
eave=3.9;ridge=6.5;half=4.1
for y in (-3.3,3.3):box('closed attic wall',(0,y,3.74),(10,.4,1.08),PLASTER,True,0)
for side in (-1,1):
    panels=[(-5.6,5.6,0,half)] if side>0 else [(-5.6,.65,-half,0),(1.55,5.6,-half,0),(.65,1.55,-half,-1.1),(.65,1.55,-.2,0)]
    for xa,xb,ya,yb in panels:
        yc=(ya+yb)/2;zc=ridge-abs(yc)*(ridge-eave)/half
        o=box('slate roof',((xa+xb)/2,yc,zc),(xb-xa,(yb-ya)*math.sqrt(1+((ridge-eave)/half)**2),.15),SLATE,False)
        o.rotation_euler.x=-side*math.atan2(ridge-eave,half)
    for x in (-5.52,5.52):C.beam('gable rake',(x,0,ridge+.08),(x,side*half,eave+.08),.12,.14,WOOD)
    box('eave fascia',(0,side*half,eave),(11.2,.12,.18),WOOD,False)
    C.mesh('closed gable',[(side*4.8,-3.5,3.2),(side*4.8,3.5,3.2),(side*4.8,3.5,4.28),(side*4.8,0,6.5),(side*4.8,-3.5,4.28)],[(0,1,2,3,4)],PLASTER)
box('ridge cap',(0,0,ridge+.06),(11.2,.22,.15),SLATE,False)
for floor in (-3.2,0):
    box('stove hearth',(1.1,-.65,floor+.06),(1.3,1.3,.12),STONE)
    box('masonry stove',(1.1,-.65,floor+.84),(1.05,1.05,1.44),STONE)
    box('stove cornice',(1.1,-.65,floor+1.62),(1.15,1.15,.12),STONE)
    box('stove hatch',(.54,-.65,floor+.7),(.06,.42,.40),IRON,False)
box('continuous flue',(1.1,-.65,2.6),(.7,.7,8.2),STONE)
for dx in (-.29,.29):box('open chimney wall',(1.1+dx,-.65,7.08),(.12,.7,.76),STONE)
for dy in (-.29,.29):box('open chimney wall',(1.1,-.65+dy,7.08),(.46,.12,.76),STONE)
for dx in (-.34,.34):box('chimney rim',(1.1+dx,-.65,7.5),(.18,.86,.12),STONE)
for dy in (-.34,.34):box('chimney rim',(1.1,-.65+dy,7.5),(.50,.18,.12),STONE)
for y in (-1.055,-.245):
    z=ridge-abs(y)*(ridge-eave)/half
    box('flashing end',(1.1,y,z+.08),(.9,.09,.16),IRON,False)
for x in (.695,1.505):
    o=box('flashing side',(x,-.65,ridge-.65*(ridge-eave)/half+.08),(.09,.9*math.sqrt(1+((ridge-eave)/half)**2),.12),IRON,False)
    o.rotation_euler.x=math.atan2(ridge-eave,half)
for x in (-4.75,-1.05,1.05,4.75):
    for y in (-3.53,3.53):box('facade post',(x,y,1.64),(.18,.12,3.28),WOOD,False)
for y in (-3.53,3.53):
    for z in (.1,3.18):box('facade belt',(0,y,z),(10,.12,.18),WOOD,False)
for y in (-3.3,3.3):
    for x in (-3.9,-2.1):box('window jamb',(x,y,1.7),(.09,.5,1.5),WOOD,False)
    for z in (1,2.4):box('window lintel',(-3,y,z),(1.98,.5,.1),WOOD,False)
for fixed,mid,width,axis in [(-4.8,0,2,'y'),(4.8,2.1,1,'y')]:
    for edge in (mid-width/2,mid+width/2):box('side window jamb',(fixed,edge,1.7),(.5,.09,1.5),WOOD,False)
    for z in (1,2.4):box('side window lintel',(fixed,mid,z),(.5,width+.18,.1),WOOD,False)
def table(x,y,z):
    prop('reading tabletop',(x,y,z+.79),(1.8,.8,.10))
    for dx in (-.77,.77):
        for dy in (-.28,.28):prop('table leg',(x+dx,y+dy,z+.37),(.09,.09,.74),solid=False)
    prop('reading bench',(x,y+.72,z+.46),(1.7,.3,.08))
    for dx in (-.7,.7):prop('bench leg',(x+dx,y+.72,z+.22),(.09,.25,.44),solid=False)
    for dx in (-.45,.45):prop('open book',(x+dx,y,z+.87),(.32,.4,.05),BOOK,False)
for z in (0,-3.2):
    table(-2.6,-1.7,z);table(-2.6,.6,z)
    for y in (1.9,2.85):
        for h in (.35,.95,1.55,2.15):prop('bookcase shelf',(-2.8,y,z+h),(2.9,.45,.08))
        for x in (-4.25,-1.35):prop('bookcase end',(x,y,z+1.25),(.09,.45,2.5))
        for h in (1,1.6,2.2):
            for k in range(12):
                x=-4.08+k*.23
                prop('shelved pages',(x,y,z+h+.17),(.12,.25,.24),BOOK,False)
                prop('book spine',(x,y-.14,z+h+.17),(.15,.025,.28),COVER,False,0)
                for dx in (-.075,.075):prop('book cover',(x+dx,y,z+h+.17),(.018,.29,.28),COVER,False,0)
door_parts=[]
for name,angle,height in [('EntryPortal',0,0),('LabPortal',math.pi,-3.2)]:
    portal=bpy.data.objects.new(name,None);C.ASSET.objects.link(portal);portal.rotation_euler.z=angle;portal.location.z=height
    hinge=bpy.data.objects.new(name+'_entry_hinge',None);C.ASSET.objects.link(hinge);hinge.parent=portal;hinge.location=(-.76,-3.3,0);hinge['open_angle_degrees']=-100.0
    parts=[box('Door plank',(-.635+k*.254,-3.3,1.22),(.248,.08,2.44),WOOD,False) for k in range(6)]
    parts += [box('Door strap',(0,-3.35,z),(1.5,.02,.055),IRON,False) for z in (.45,1.95)]
    for o in parts:o.parent=hinge;o.location-=Vector((-.76,-3.3,0))
    door_parts.extend(parts)
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
for o in visual:
    scale=float(o.data.materials[0].get('uv_metres',0))
    if not scale:continue
    bm=bmesh.new();bm.from_mesh(o.data);uv=bm.loops.layers.uv.verify()
    for face in bm.faces:
        axis=max(range(3),key=lambda i:abs(face.normal[i]))
        for loop in face.loops:
            p=o.matrix_world@loop.vert.co;u,v=((p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y));loop[uv].uv=(u/scale,v/scale)
    bm.to_mesh(o.data);bm.free()
C._join_by_material([o for o in visual if o not in furniture and o not in door_parts]);C._join_by_material(furniture)
for n,p,s in coll:
    o=C.box(n+'-colonly',p,s,STONE,0);o.hide_render=True
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=visual[0]
asset=OUT/'s_library.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
for material in document['materials']:
    tint={'SL stone':(.61,.66,.68),'SL lime':(.78,.80,.76),'SL timber':(.30,.24,.18),'SL bound books':(.20,.16,.11),'SL leather binding':(.045,.03,.022),'SL iron':(.09,.10,.11)}.get(material['name'])
    if tint:material['pbrMetallicRoughness']['baseColorFactor']=[*tint,1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);remaining=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(remaining))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+remaining)
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
stats={'state':'WIP library; physics and visual QA pending','wall_footprint':[10,7],'lower_floor':-3.2,'ridge':ridge,'triangles':triangles,'meshes':len(visual),'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8');bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_library.blend'));print('S_LIBRARY',json.dumps(stats))
