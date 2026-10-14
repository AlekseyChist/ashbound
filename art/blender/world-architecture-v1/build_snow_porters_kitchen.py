"""Porters kitchen: approved8x6m, one floor. QA pending."""
import sys, json, hashlib, math, struct
from pathlib import Path
import bpy, bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/snow-porters-kitchen';QA.mkdir(parents=True,exist_ok=True)
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
coll=[]
furniture=[]
def box(n,p,s,m,solid=True,bevel=.015):
    o=C.box(n,p,s,m,bevel)
    if solid:coll.append((n,p,s))
    return o
box('foundation',(0,0,-.15),(8,6,.3),STONE)
def wall(n,y,a,b,holes=()):
    cuts=sorted(set([a,b]+[v for h in holes for v in h[:2]]))
    for lo,hi in zip(cuts,cuts[1:]):
        opening=next((h for h in holes if lo>=h[0] and hi<=h[1]),None)
        for z0,z1 in ([(0,opening[2]),(opening[3],3.2)] if opening else [(0,3.2)]):
            if z1>z0:box(n,((lo+hi)/2,y,(z0+z1)/2),(hi-lo,.4,z1-z0),PLASTER,True,0)
wall('front',-2.8,-4,4,[(-.65,.65,0,2.5),(-3,-1.8,1,2.3)])
wall('rear',2.8,-4,4,[(-3,-1.8,1,2.3)])
for x in (-3.8,3.8):box('side wall',(x,0,1.6),(.4,5.2,3.2),PLASTER,True,0)
for x in (-3.7,3.7):
    for y in (-2.75,2.75):box('corner post',(x,y,1.6),(.18,.18,3.2),WOOD,False)
for y in (-3.0,3.0):box('stone belt',(0,y,.2),(8,.12,.4),STONE,False)
for y in (-2.8,2.8):
    for x in (-3,-1.8):box('window jamb',(x,y,1.65),(.08,.46,1.4),WOOD,False)
    for z in (1,2.3):box('window lintel',(-2.4,y,z),(1.36,.46,.10),WOOD,False)
    box('window sill',(-2.4,y,.97),(1.4,.55,.12),STONE,False)
for y in (-3.03,3.03):
    box('upper wall plate',(0,y,3.12),(8,.12,.18),WOOD,False)
    for x in (-3.7,-1.4,1.4,3.7):box('facade post',(x,y,1.7),(.14,.10,2.8),WOOD,False)
for x in (-4.03,4.03):
    box('side stone belt',(x,0,.2),(.12,6,.4),STONE,False)
    box('side upper plate',(x,0,3.12),(.12,6,.18),WOOD,False)
# Ceiling excludes the complete continuous flue envelope.
for a,b,c,d in [(-4,2.25,-3,3),(3.15,4,-3,3),(2.25,3.15,-3,1.05),(2.25,3.15,1.95,3)]:
    box('ceiling',((a+b)/2,(c+d)/2,3.14),(b-a,d-c,.12),WOOD)
for side in (-1,1):
    panels=[(-4.5,4.5,-3.5,0)] if side<0 else [(-4.5,2.25,0,3.5),(3.15,4.5,0,3.5),(2.25,3.15,0,1.05),(2.25,3.15,1.95,3.5)]
    for xa,xb,ya,yb in panels:
        yc=(ya+yb)/2
        roof=box('roof',((xa+xb)/2,yc,6.5-abs(yc)*3.3/3.5),(xb-xa,(yb-ya)*math.sqrt(1+(3.3/3.5)**2),.14),SLATE,False)
        roof.rotation_euler.x=-side*math.atan2(3.3,3.5)
    x=side*3.8
    C.mesh('closed gable',[(x,-3,3.2),(x,3,3.2),(x,0,6.5)],[(0,1,2)],PLASTER)
    for row in range(12):
        ya=side*row*3.5/12;yb=side*(row+1)*3.5/12
        for col in range(19):
            xa=max(-4.5,-4.5+col*.5-(.25 if row%2 else 0))
            xb=min(4.5,-4.5+(col+1)*.5-(.25 if row%2 else 0)-.008)
            if xb<=xa:continue
            rectangles=[(xa,xb,min(ya,yb),max(ya,yb))]
            if side>0 and xa<3.15 and xb>2.25 and min(ya,yb)<1.95 and max(ya,yb)>1.05:
                rectangles=[]
                if xa<2.25:rectangles.append((xa,min(xb,2.25),min(ya,yb),max(ya,yb)))
                if xb>3.15:rectangles.append((max(xa,3.15),xb,min(ya,yb),max(ya,yb)))
                if min(ya,yb)<1.05:rectangles.append((max(xa,2.25),min(xb,3.15),min(ya,yb),1.05))
                if max(ya,yb)>1.95:rectangles.append((max(xa,2.25),min(xb,3.15),1.95,max(ya,yb)))
            for a,b,c,d in rectangles:
                if b<=a or d<=c:continue
                vertices=[(a,c,6.5-abs(c)*3.3/3.5+.09+row*.006),(b,c,6.5-abs(c)*3.3/3.5+.09+row*.006),(b,d,6.5-abs(d)*3.3/3.5+.09+row*.006),(a,d,6.5-abs(d)*3.3/3.5+.09+row*.006)]
                vertices += [(xx,yy,zz-.025) for xx,yy,zz in vertices]
                C.mesh('slate course',vertices,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],SLATE)
box('ridge',(0,0,6.57),(9,.18,.14),SLATE,False)
box('hearth',(2.7,1.5,.07),(1.6,1.6,.14),STONE)
box('kitchen stove',(2.7,1.5,.88),(1.3,1.3,1.48),STONE)
box('stove hatch',(1.995,1.5,.7),(.09,.48,.42),IRON,False)
box('stove cornice',(2.7,1.5,1.7),(1.4,1.4,.16),STONE)
box('continuous flue',(2.7,1.5,3.95),(.7,.7,4.5),STONE)
for dx in (-.29,.29):box('chimney wall',(2.7+dx,1.5,6.56),(.12,.7,.72),STONE)
for dy in (-.29,.29):box('chimney wall',(2.7,1.5+dy,6.56),(.46,.12,.72),STONE)
for dx in (-.34,.34):box('chimney rim',(2.7+dx,1.5,6.98),(.18,.86,.12),STONE)
for dy in (-.34,.34):box('chimney rim',(2.7,1.5+dy,6.98),(.5,.18,.12),STONE)
for y in (1.1,1.9):
    box('flashing end',(2.7,y,6.5-y*3.3/3.5+.08),(.9,.10,.18),IRON,False)
for x in (2.3,3.1):
    strip=box('flashing side',(x,1.5,6.5-1.5*3.3/3.5+.08),(.10,.9*math.sqrt(1+(3.3/3.5)**2),.12),IRON,False)
    strip.rotation_euler.x=-math.atan2(3.3,3.5)
def prop(n,p,s,m=WOOD):
    o=box(n,p,s,m);o['part_role']='interior_furniture';furniture.append(o)
for y in (-1.5,1.5):
    prop('common table',(-2.2,y,.78),(2,.75,.1))
    for dx in (-.85,.85):
        for dy in (-.25,.25):prop('table leg',(-2.2+dx,y+dy,.365),(.1,.1,.73))
    by=y+.7 if y<0 else y-.7
    prop('common bench',(-2.2,by,.46),(1.8,.3,.08))
    for dx in (-.7,.7):prop('bench support',(-2.2+dx,by,.22),(.10,.28,.44))
prop('worktop',(2.4,-1.5,.84),(2.2,.7,.12))
for x in (1.5,3.3):prop('worktop support',(x,-1.5,.39),(.12,.6,.78))
box('wash pedestal',(1.0,2.15,.34),(.56,.46,.68),STONE)
box('wash bowl floor',(1.0,2.15,.74),(1.0,.7,.12),STONE)
for x in (.55,1.45):box('wash bowl side',(x,2.15,.9),(.10,.7,.32),STONE)
for y in (1.85,2.45):box('wash bowl end',(1,y,.9),(.8,.10,.32),STONE)
hinge=bpy.data.objects.new('Kitchen_entry_hinge',None);C.ASSET.objects.link(hinge);hinge.location=(-.63,-2.8,0);hinge['open_angle_degrees']=-100.0
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
asset=OUT/'s_porters_kitchen.glb'
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
stats={'state':'WIP furnished; canonical runtime and roof QA pending','triangles':triangles,'meshes':len(visual),'wall_footprint':[8,6],'floors':1,'ridge':6.5,'stair_rises':0,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_porters_kitchen.blend'))
print('S_A_SHELL',json.dumps(stats))
