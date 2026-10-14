"""Snow apprentice dormitory: PDF141 eight-by-four metre shell and three beds. QA pending."""
import sys, json, hashlib, math, struct
from pathlib import Path
import bpy, bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/snow-apprentice-dorm';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('SA stone','stone_wall_02_diff_1k.jpg',2)
WOOD=surface('SA timber','fine_grained_wood_col_1k.jpg',.65)
PLASTER=surface('SA lime','plaster_grey_04_diff_1k.jpg',2)
def slate_paint():
    # Match the accepted S-H recipe: painted surface multiplied by its base tint.
    color=(.10,.135,.15)
    m=C.mat('SA slate',(*color,1),.95);m['uv_metres']=.65
    im=bpy.data.images.new('SA slate paint',width=256,height=256)
    pixels=[]
    for y in range(256):
        for x in range(256):
            variation=.022*math.sin(x*.039+y*.023)+.012*math.sin(y*.073-x*.013)
            pixels.extend([max(0,min(1,t+variation)) for t in color]+[1])
    im.pixels.foreach_set(pixels);im.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
SLATE=slate_paint()
LINEN=C.mat('SA bedding',(.37,.36,.29,1),.98)
BOOK=C.mat('SA book covers',(.20,.16,.11,1),.98)
def dark_metal(name,color):
    m=C.mat(name,(*color,1),.98);m['uv_metres']=.15
    im=bpy.data.images.new(name+' patina',width=64,height=64)
    pixels=[]
    for y in range(64):
        for x in range(64):
            value=.045+.009*math.sin(x*.7+y*.4)
            pixels.extend([value,value,value,1])
    im.pixels.foreach_set(pixels);im.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
IRON=dark_metal('SA black cast iron',(.055,.060,.065))
LEAD=dark_metal('SA weathered lead',(.09,.10,.11))
coll=[];furniture=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,0 if m==PLASTER else .015)
    if solid:coll.append((n,p,s))
    return o

box('foundation',(0,0,-.15),(8,4,.3),STONE)
def wall(n,y,holes):
    cuts=sorted(set([-4,4]+[v for h in holes for v in h[:2]]))
    for a,b in zip(cuts,cuts[1:]):
        hole=next((h for h in holes if a>=h[0] and b<=h[1]),None)
        for z0,z1 in ([(0,hole[2]),(hole[3],3.2)] if hole else [(0,3.2)]):
            if z1>z0:box(n,((a+b)/2,y,(z0+z1)/2),(b-a,.4,z1-z0),PLASTER)
wall('front',-1.8,[(-.65,.65,0,2.5),(-2.3,-1.3,1,2.25),(1.3,2.3,1,2.25)])
wall('rear',1.8,[(-3.3,-2.3,1,2.25),(2.3,3.3,1,2.25)])
for x in (-3.8,3.8):box('side wall',(x,0,1.6),(.4,3.2,3.2),PLASTER)
for a,b in [(-4.06,-.65),(.65,4.06)]:box('front stone belt',((a+b)/2,-2.02,.21),(b-a,.12,.42),STONE)
box('rear stone belt',(0,2.02,.21),(8.12,.12,.42),STONE)
for x in (-4.02,4.02):box('side stone belt',(x,0,.21),(.12,4.04,.42),STONE)
for y in (-2.025,2.025):
    for x in ((-1.8,1.8) if y<0 else (-2.8,2.8)):
        for dx in (-.54,.54):box('window jamb',(x+dx,y,1.625),(.12,.16,1.38),WOOD,False)
        for z in (.96,2.29):box('window sill lintel',(x,y,z),(1.2,.22,.12),WOOD,False)
for x in (-.73,.73):box('entry jamb',(x,-2.025,1.25),(.14,.18,2.5),WOOD,False)
box('entry lintel',(0,-2.025,2.56),(1.6,.2,.12),WOOD,False)
# Continuous flue through actual .9m openings in the ceiling and front roof.
for a,b,c,d in [(-4,-3.45,-2,2),(-2.55,4,-2,2),(-3.45,-2.55,-2,-1.35),(-3.45,-2.55,-.45,2)]:
    box('ceiling',((a+b)/2,(c+d)/2,3.14),(b-a,d-c,.12),WOOD)
SLOPE=2.3/2.5
for side in (-1,1):
    panels=[(-4.5,4.5,0,2.5)] if side>0 else [(-4.5,-3.45,0,2.5),(-2.55,4.5,0,2.5),(-3.45,-2.55,0,.45),(-3.45,-2.55,1.35,2.5)]
    for a,b,c,d in panels:
        yc=side*(c+d)/2
        roof=box('roof',((a+b)/2,yc,5.5-abs(yc)*SLOPE),(b-a,(d-c)*math.sqrt(1+SLOPE*SLOPE),.14),SLATE,False)
        roof.rotation_euler.x=-side*math.atan(SLOPE)
    x=side*3.8;edge=5.5-2*SLOPE
    profile=[(-2,3.2),(2,3.2),(2,edge),(0,5.5),(-2,edge)]
    verts=[(xx,y,z) for xx in (x-.2,x+.2) for y,z in profile]
    faces=[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
    C.mesh('closed masonry gable',verts,faces,PLASTER)
    at=side*4.03
    C.beam('gable lower beam',(at,-1.9,3.24),(at,1.9,3.24),.14,.12,WOOD)
    C.beam('gable centre post',(at,0,3.24),(at,0,5.4),.14,.12,WOOD)
    for y in (-1.9,1.9):C.beam('gable rafter',(at,y,5.5-abs(y)*SLOPE),(at,0,5.45),.14,.12,WOOD)
    for row in range(8):
        y=side*(row+.5)*2.5/8
        for column in range(18):
            x=-4.5+(column+.5)*9/18
            if side<0 and abs(x+3)<.65 and -.1>y>-1.56:continue
            tile=C.box('slate tile',(x,y,5.5-abs(y)*SLOPE+.082),(9/18-.012,2.5/8*math.sqrt(1+SLOPE*SLOPE)-.008,.035),SLATE,0)
            tile.rotation_euler.x=-side*math.atan(SLOPE)
box('ridge cap',(0,0,5.56),(9,.2,.15),SLATE,False)
box('stove hearth',(-3,-.9,.06),(1.05,1.05,.12),STONE)
box('warming stove',(-3,-.9,.75),(.9,.9,1.26),STONE)
box('stove hatch',(-2.5,-.9,.65),(.08,.4,.38),IRON,False)
for y in (-1.12,-.68):box('cast iron hatch jamb',(-2.445,y,.65),(.05,.045,.47),IRON,False)
for z in (.425,.875):box('cast iron hatch rail',(-2.445,-.9,z),(.05,.485,.045),IRON,False)
for z in (.54,.77):box('hatch hinge',(-2.41,-1.10,z),(.055,.065,.045),IRON,False)
box('hatch latch base',(-2.43,-.74,.65),(.08,.055,.06),IRON,False)
box('hatch latch handle',(-2.385,-.74,.69),(.035,.035,.14),IRON,False)
box('stove cornice',(-3,-.9,1.5),(1,1,.16),STONE)
box('continuous flue',(-3,-.9,3.6),(.6,.6,4.2),STONE)
for dx in (-.25,.25):box('chimney wall',(-3+dx,-.9,6.05),(.1,.6,.7),STONE)
for dy in (-.25,.25):box('chimney wall',(-3,-.9+dy,6.05),(.4,.1,.7),STONE)
for dx in (-.30,.30):box('chimney rim',(-3+dx,-.9,6.46),(.16,.76,.12),STONE)
for dy in (-.30,.30):box('chimney rim',(-3,-.9+dy,6.46),(.44,.16,.12),STONE)
for y in (-1.275,-.525):
    flash=box('chimney flashing',(-3,y,5.5-abs(y)*SLOPE+.1),(1.0,.20,.035),LEAD,False);flash.rotation_euler.x=math.atan(SLOPE)
for x in (-3.375,-2.625):
    flash=box('chimney side flashing',(x,-.9,5.5-.9*SLOPE+.1),(.20,.95*math.sqrt(1+SLOPE*SLOPE),.035),LEAD,False);flash.rotation_euler.x=math.atan(SLOPE)
LINEN=C.mat('S warm bedding',(.35,.31,.23,1),.98)
def prop(n,p,s,m=WOOD):
    o=box(n,p,s,m);o['part_role']='interior_furniture';furniture.append(o)
for x in (-2.5,0,2.5):
    prop('bed frame',(x,1.15,.37),(2,.82,.14))
    for dx in (-.87,.87):
        for dy in (-.32,.32):prop('bed leg',(x+dx,1.15+dy,.15),(.1,.1,.30))
    prop('bed linen',(x,1.15,.5),(1.9,.76,.12),LINEN)
    prop('bed pillow',(x-.7,1.15,.61),(.35,.68,.1),LINEN)
prop('common table',(2.9,-1,.82),(1,.6,.12))
for dx in (-.39,.39):prop('table support',(2.9+dx,-1,.38),(.1,.5,.76))
prop('writing tray',(2.9,-1,.915),(.38,.24,.07))
prop('writing stool seat',(2.9,-.25,.43),(.4,.4,.10))
for dx in (-.14,.14):
    for dy in (-.14,.14):prop('writing stool leg',(2.9+dx,-.25+dy,.19),(.07,.07,.38))
hinge=bpy.data.objects.new('Dorm_entry_hinge',None);C.ASSET.objects.link(hinge);hinge.location=(-.63,-1.8,0);hinge['open_angle_degrees']=-100.0
# Five whole timber planks retain the existing door controller's identity.
door_parts=[box('Door plank',(-.50+k*.25,-1.8,1.22),(.24,.08,2.44),WOOD,False) for k in range(5)]
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
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
shell=[o for o in visual if o not in furniture and o not in door_parts]
C._join_by_material(shell)
C._join_by_material(furniture)
for o in door_parts:
    matrix=o.matrix_world.copy();o.parent=hinge;o.matrix_world=matrix
for n,p,s in coll:
    o=C.box(n+'-colonly',p,s,STONE,0);o.hide_render=True
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=visual[0]
asset=OUT/'s_apprentice_dorm.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0]
document=json.loads(data[20:20+size])
tints={'SA stone':(.61,.66,.68),'SA lime':(.78,.80,.76),'SA timber':(.30,.24,.18)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
remaining=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(remaining))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+remaining)
triangles=0
for o in visual:
    o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
stats={'state':'WIP apprentice dormitory; native and physical QA pending','triangles':triangles,'meshes':len(visual),'wall_footprint':[8,4],'floors':1,'ridge':5.5,'stair_rises':0,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_apprentice_dorm.blend'))
print('SNOW_APPRENTICE_DORM',json.dumps(stats))
