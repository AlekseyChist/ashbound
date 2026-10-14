"""Snow infirmary: PDF141 eleven-by-six metre shell and four beds. QA pending."""
import sys, json, hashlib, math, struct
from pathlib import Path
import bpy, bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/snow-infirmary';QA.mkdir(parents=True,exist_ok=True)
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
IRON=C.mat('SA iron',(.09,.10,.11,1),.83)
coll=[];furniture=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if solid:coll.append((n,p,s))
    return o
box('foundation',(0,0,-.15),(11,6,.3),STONE)
def wall(n,y,holes):
    cuts=sorted(set([-5.5,5.5]+[v for h in holes for v in h[:2]]))
    for a,b in zip(cuts,cuts[1:]):
        hole=next((h for h in holes if a>=h[0] and b<=h[1]),None)
        for z0,z1 in ([(0,hole[2]),(hole[3],3.2)] if hole else [(0,3.2)]):
            if z1>z0:box(n,((a+b)/2,y,(z0+z1)/2),(b-a,.4,z1-z0),PLASTER)
wall('front',-2.8,[(-.65,.65,0,2.5),(-4,-3,1,2.3),(3,4,1,2.3)])
wall('rear',2.8,[(-4,-3,1,2.3),(3,4,1,2.3)])
for x in (-5.3,5.3):box('side wall',(x,0,1.6),(.4,5.2,3.2),PLASTER)
for y in (-3.025,3.025):
    for x in (-3.5,3.5):
        for dx in (-.54,.54):box('window jamb',(x+dx,y,1.65),(.12,.16,1.42),WOOD,False)
        for z in (.96,2.34):box('window sill lintel',(x,y,z),(1.2,.22,.12),WOOD,False)
for x in (-.73,.73):box('entry jamb',(x,-3.025,1.25),(.14,.18,2.5),WOOD,False)
box('entry lintel',(0,-3.025,2.56),(1.6,.2,.12),WOOD,False)
for a,b,c,d in [(-5.5,3.85,-3,3),(4.75,5.5,-3,3),(3.85,4.75,-3,-.45),(3.85,4.75,.45,3)]:
    box('ceiling',((a+b)/2,(c+d)/2,3.14),(b-a,d-c,.12),WOOD)
for side in (-1,1):
    panels=[(-6,3.85,0,3.5),(4.75,6,0,3.5),(3.85,4.75,.45,3.5)]
    for a,b,c,d in panels:
        yc=side*(c+d)/2
        roof=box('roof',((a+b)/2,yc,6.5-abs(yc)*3.3/3.5),(b-a,(d-c)*math.sqrt(1+(3.3/3.5)**2),.14),SLATE,False)
        roof.rotation_euler.x=-side*math.atan2(3.3,3.5)
    x=side*5.3
    gable_eave=6.5-3*3.3/3.5
    profile=[(-3,3.2),(3,3.2),(3,gable_eave),(0,6.5),(-3,gable_eave)]
    vertices=[(xx,y,z) for xx in (x-.2,x+.2) for y,z in profile]
    faces=[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
    C.mesh('closed masonry gable',vertices,faces,PLASTER)
for a,b in [(-6,3.85),(4.75,6)]:box('ridge cap',((a+b)/2,0,6.56),(b-a,.2,.15),SLATE,False)
for side in (-1,1):
    for row in range(10):
        y=side*(row+.5)*3.5/10
        for column in range(24):
            x=-6+(column+.5)*12/24
            if abs(x-4.3)<.63 and abs(y)<.64:continue
            tile=C.box('slate tile',(x,y,6.5-abs(y)*3.3/3.5+.082),(12/24-.012,3.5/10*math.sqrt(1+(3.3/3.5)**2)-.008,.035),SLATE,0)
            tile.rotation_euler.x=-side*math.atan2(3.3,3.5)
for y in (-.46,.46):
    flashing=box('chimney flashing',(4.3,y,6.5-abs(y)*3.3/3.5+.1),(1.12,.26,.035),IRON,False)
    flashing.rotation_euler.x=-math.copysign(math.atan2(3.3,3.5),y)
for x in (3.84,4.76):
    for side in (-1,1):
        flashing=box('chimney side flashing',(x,side*.225,6.5-.225*3.3/3.5+.1),(.22,.45*math.sqrt(1+(3.3/3.5)**2),.035),IRON,False)
        flashing.rotation_euler.x=-side*math.atan2(3.3,3.5)
box('stove hearth',(4.3,0,.07),(1.5,1.5,.14),STONE)
box('warming stove',(4.3,0,.88),(1.2,1.2,1.48),STONE)
box('stove hatch',(3.655,0,.7),(.09,.48,.42),IRON,False)
box('stove cornice',(4.3,0,1.7),(1.3,1.3,.16),STONE)
box('continuous flue',(4.3,0,4.25),(.7,.7,5.1),STONE)
for dx in (-.29,.29):box('chimney wall',(4.3+dx,0,7.15),(.12,.7,.7),STONE)
for dy in (-.29,.29):box('chimney wall',(4.3,dy,7.15),(.46,.12,.7),STONE)
for dx in (-.34,.34):box('chimney rim',(4.3+dx,0,7.56),(.18,.86,.12),STONE)
for dy in (-.34,.34):box('chimney rim',(4.3,dy,7.56),(.5,.18,.12),STONE)
def prop(n,p,s,m=WOOD):
    o=box(n,p,s,m);o['part_role']='interior_furniture';furniture.append(o)
for x in (-3.2,3.2):
    for y in (-1.5,1.5):
        prop('bed frame',(x,y,.37),(2.1,.95,.14))
        for dx in (-.92,.92):
            for dy in (-.36,.36):prop('bed leg',(x+dx,y+dy,.15),(.1,.1,.30))
        prop('bed linen',(x,y,.5),(1.95,.86,.12),LINEN)
        prop('bed pillow',(x-.72,y,.61),(.35,.72,.10),LINEN)
prop('healer worktop',(-3.6,0,.81),(1.4,.65,.12))
for dx in (-.55,.55):prop('worktop support',(-3.6+dx,0,.375),(.1,.5,.75))
box('wash pedestal',(-.9,2.15,.34),(.56,.46,.68),STONE)
box('wash bowl floor',(-.9,2.15,.74),(1,.7,.12),STONE)
for x in (-1.35,-.45):box('wash bowl side',(x,2.15,.9),(.1,.7,.32),STONE)
for y in (1.85,2.45):box('wash bowl end',(-.9,y,.9),(.8,.1,.32),STONE)
hinge=bpy.data.objects.new('Infirmary_entry_hinge',None);C.ASSET.objects.link(hinge);hinge.location=(-.63,-2.8,0);hinge['open_angle_degrees']=-100.0
door_parts=[box('Door plank',(-.50+k*.25,-2.8,1.22),(.24,.08,2.44),WOOD,False) for k in range(5)]

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
asset=OUT/'s_infirmary.glb'
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
stats={'state':'WIP furnished; canonical runtime and roof QA pending','triangles':triangles,'meshes':len(visual),'wall_footprint':[11,6],'floors':1,'ridge':6.5,'stair_rises':0,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_infirmary.blend'))
print('SNOW_INFIRMARY',json.dumps(stats))
