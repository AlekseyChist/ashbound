"""Snow alchemist shop: PDF141 nine-by-six metre shell and traditional workshop. QA pending."""
import sys, json, hashlib, math, struct
from pathlib import Path
import bpy, bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/snow-alchemist';QA.mkdir(parents=True,exist_ok=True)
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
    o=C.box(n,p,s,m,0 if m==PLASTER else .015)
    if solid:coll.append((n,p,s))
    return o
box('foundation',(0,0,-.15),(9,6,.3),STONE)
def wall(n,y,holes):
    cuts=sorted(set([-4.5,4.5]+[v for h in holes for v in h[:2]]))
    for a,b in zip(cuts,cuts[1:]):
        hole=next((h for h in holes if a>=h[0] and b<=h[1]),None)
        for z0,z1 in ([(0,hole[2]),(hole[3],3.2)] if hole else [(0,3.2)]):
            if z1>z0:box(n,((a+b)/2,y,(z0+z1)/2),(b-a,.4,z1-z0),PLASTER)
wall('front',-2.8,[(-.65,.65,0,2.5),(-3.3,-2.3,1,2.3),(2.3,3.3,1,2.3)])
wall('rear',2.8,[(-3.3,-2.3,1,2.3),(2.3,3.3,1,2.3)])
for x in (-4.3,4.3):box('side wall',(x,0,1.6),(.4,5.2,3.2),PLASTER)
for x in (-2.605,2.605):box('front stone belt',(x,-3.02,.21),(3.91,.12,.42),STONE)
box('rear stone belt',(0,3.02,.21),(9.12,.12,.42),STONE)
for x in (-4.52,4.52):box('side stone belt',(x,0,.21),(.12,6.04,.42),STONE)
for y in (-3.025,3.025):
    for x in (-2.8,2.8):
        for dx in (-.54,.54):box('window jamb',(x+dx,y,1.65),(.12,.16,1.42),WOOD,False)
        for z in (.96,2.34):box('window sill lintel',(x,y,z),(1.2,.22,.12),WOOD,False)
for x in (-.73,.73):box('entry jamb',(x,-3.025,1.25),(.14,.18,2.5),WOOD,False)
box('entry lintel',(0,-3.025,2.56),(1.6,.2,.12),WOOD,False)
for a,b,c,d in [(-4.5,2.85,-3,3),(3.75,4.5,-3,3),(2.85,3.75,-3,-.45),(2.85,3.75,.45,3)]:
    box('ceiling',((a+b)/2,(c+d)/2,3.14),(b-a,d-c,.12),WOOD)
for side in (-1,1):
    panels=[(-5,2.85,0,3.5),(3.75,5,0,3.5),(2.85,3.75,.45,3.5)]
    for a,b,c,d in panels:
        yc=side*(c+d)/2
        roof=box('roof',((a+b)/2,yc,6.5-abs(yc)*3.3/3.5),(b-a,(d-c)*math.sqrt(1+(3.3/3.5)**2),.14),SLATE,False)
        roof.rotation_euler.x=-side*math.atan2(3.3,3.5)
    x=side*4.3
    gable_eave=6.5-3*3.3/3.5
    profile=[(-3,3.2),(3,3.2),(3,gable_eave),(0,6.5),(-3,gable_eave)]
    vertices=[(xx,y,z) for xx in (x-.2,x+.2) for y,z in profile]
    faces=[(4,3,2,1,0),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
    C.mesh('closed masonry gable',vertices,faces,PLASTER)
    at=side*4.53
    for y in (-2.8,2.8):
        C.beam('gable rafter',(at,y,6.5-abs(y)*3.3/3.5),(at,0,6.45),.14,.12,WOOD)
    C.beam('gable lower beam',(at,-2.85,3.24),(at,2.85,3.24),.14,.12,WOOD)
    C.beam('gable centre post',(at,0,3.24),(at,0,6.4),.14,.12,WOOD)
for a,b in [(-5,2.85),(3.75,5)]:box('ridge cap',((a+b)/2,0,6.56),(b-a,.2,.15),SLATE,False)
for side in (-1,1):
    for row in range(10):
        y=side*(row+.5)*3.5/10
        for column in range(24):
            x=-5+(column+.5)*10/24
            if abs(x-3.3)<.63 and abs(y)<.64:continue
            tile=C.box('slate tile',(x,y,6.5-abs(y)*3.3/3.5+.082),(10/24-.012,3.5/10*math.sqrt(1+(3.3/3.5)**2)-.008,.035),SLATE,0)
            tile.rotation_euler.x=-side*math.atan2(3.3,3.5)
for y in (-.46,.46):
    flashing=box('chimney flashing',(3.3,y,6.5-abs(y)*3.3/3.5+.1),(1.12,.26,.035),IRON,False)
    flashing.rotation_euler.x=-math.copysign(math.atan2(3.3,3.5),y)
for x in (2.84,3.76):
    for side in (-1,1):
        flashing=box('chimney side flashing',(x,side*.225,6.5-.225*3.3/3.5+.1),(.22,.45*math.sqrt(1+(3.3/3.5)**2),.035),IRON,False)
        flashing.rotation_euler.x=-side*math.atan2(3.3,3.5)
box('stove hearth',(3.3,0,.07),(1.5,1.5,.14),STONE)
box('warming stove',(3.3,0,.88),(1.2,1.2,1.48),STONE)
box('stove hatch',(2.655,0,.7),(.09,.48,.42),IRON,False)
box('stove cornice',(3.3,0,1.7),(1.3,1.3,.16),STONE)
box('continuous flue',(3.3,0,4.25),(.7,.7,5.1),STONE)
for dx in (-.29,.29):box('chimney wall',(3.3+dx,0,7.15),(.12,.7,.7),STONE)
for dy in (-.29,.29):box('chimney wall',(3.3,dy,7.15),(.46,.12,.7),STONE)
for dx in (-.34,.34):box('chimney rim',(3.3+dx,0,7.56),(.18,.86,.12),STONE)
for dy in (-.34,.34):box('chimney rim',(3.3,dy,7.56),(.5,.18,.12),STONE)
def prop(n,p,s,m=WOOD):
    o=box(n,p,s,m);o['part_role']='interior_furniture';furniture.append(o)
prop('shop counter',(-1.8,-.4,.88),(2.4,.65,.16))
for dx in (-1,1):prop('counter support',(-1.8+dx,-.4,.4),(.14,.52,.8))
prop('ingredient worktop',(-2.6,1.55,.86),(2.2,.75,.14))
for dx in (-.9,.9):prop('worktop support',(-2.6+dx,1.55,.395),(.13,.6,.79))
for y in (1.1,2.4):prop('shelf upright',(3.85,y,1.2),(.38,.12,2.4))
for z in (.48,1.15,1.82):prop('ingredient shelf',(3.85,1.75,z),(.4,1.45,.1))
CLAY=C.mat('AL clay',(.29,.25,.18,1),.96)
def ingredient_jar(x,y,z):
    rings=[(0,.08),(.04,.14),(.28,.14),(.35,.08),(.38,.075)]
    vertices=[(x+r*math.cos(k*math.tau/10),y+r*math.sin(k*math.tau/10),z+h) for h,r in rings for k in range(10)]
    faces=[tuple(range(9,-1,-1)),tuple(range(40,50))]
    for ring in range(4):
        for k in range(10):faces.append((ring*10+k,ring*10+(k+1)%10,(ring+1)*10+(k+1)%10,(ring+1)*10+k))
    jar=C.mesh('closed clay ingredient jar',vertices,faces,CLAY)
    jar['part_role']='interior_furniture';furniture.append(jar)
    lid_vertices=[(x+.085*math.cos(k*math.tau/10),y+.085*math.sin(k*math.tau/10),z+h) for h in (.38,.425) for k in range(10)]
    lid_faces=[tuple(range(9,-1,-1)),tuple(range(10,20))]+[(k,(k+1)%10,(k+1)%10+10,k+10) for k in range(10)]
    lid=C.mesh('wooden jar lid',lid_vertices,lid_faces,WOOD)
    lid['part_role']='interior_furniture';furniture.append(lid)
for row,z in enumerate((.53,1.2,1.87)):
    for y in (1.2,1.6,2.0,2.4):
        ingredient_jar(3.85,y,z)
prop('work tray',(-2.6,1.55,.97),(.55,.35,.08))
box('wash pedestal',(-.9,2.15,.34),(.56,.46,.68),STONE)
box('wash bowl floor',(-.9,2.15,.74),(1,.7,.12),STONE)
for x in (-1.35,-.45):box('wash bowl side',(x,2.15,.9),(.1,.7,.32),STONE)
for y in (1.85,2.45):box('wash bowl end',(-.9,y,.9),(.8,.1,.32),STONE)
hinge=bpy.data.objects.new('Alchemist_entry_hinge',None);C.ASSET.objects.link(hinge);hinge.location=(-.63,-2.8,0);hinge['open_angle_degrees']=-100.0
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
asset=OUT/'s_alchemist.glb'
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
stats={'state':'WIP alchemist workshop; native and physical QA pending','triangles':triangles,'meshes':len(visual),'wall_footprint':[9,6],'floors':1,'ridge':6.5,'stair_rises':0,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_alchemist.blend'))
print('SNOW_ALCHEMIST',json.dumps(stats))
