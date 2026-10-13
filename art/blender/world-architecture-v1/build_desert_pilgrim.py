"""Compact D-P12x7 from accepted desert city plan. Production WIP."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/desert-pilgrim';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DP stone','stone_wall_02_diff_1k.jpg',2)
LIME=surface('DP lime','plaster_grey_04_diff_1k.jpg',2)
WOOD=surface('DP timber','fine_grained_wood_col_1k.jpg',.65)
CLOTH=C.mat('DP shade',(.34,.28,.18,1),.98)
WATER=C.mat('DP basin water',(.075,.18,.20,1),.18)
TILE=C.mat('DP fired roof clay',(.17,.095,.055,1),.98)
IRON=C.mat('DP stove iron',(.09,.10,.11,1),.9)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('bed frame','bed leg','bedding','kitchen worktop','worktop support')):
        o['part_role']='interior_furniture'
    if solid:coll.append((n,p,s))
    return o
box('foundation',(0,0,-.15),(12,7,.3),STONE)
box('entry porch',(0,-4.3,-.12),(3,1.6,.24),STONE)
for y in (-3.3,3.3):
    for x in (-3.35,3.35):box('portal wall',(x,y,1.70),(5.3,.4,3.4),LIME)
    box('portal lintel',(0,y,2.9),(1.4,.4,1),LIME)
for x in (-5.8,5.8):
    for a,b in [(-3.1,-1.9),(-.9,.9),(1.9,3.1)]:box('side pier',(x,(a+b)/2,1.55),(.4,b-a,3.1),LIME)
    for y in (-1.4,1.4):
        box('window sill wall',(x,y,.6),(.4,1,1.2),LIME)
        box('window header',(x,y,2.725),(.4,1,.75),LIME)
        for dy in (-.54,.54):box('window jamb',(x,y+dy,1.775),(.48,.08,1.23),WOOD)
        for z in (1.17,2.38):box('window rail',(x,y,z),(.48,1.15,.08),WOOD)
for x in (-1.1,1.1):
    for a,b in [(-3.1,-1),( .5,3.1)]:box('room partition',(x,(a+b)/2,1.5),(.2,b-a,3),LIME)
    box('room doorway header',(x,-.25,2.7),(.2,1.5,.6),LIME)
def cut_flue(rect):
    x0,x1,y0,y1=rect;a,b=max(x0,4.45),min(x1,5.15);c,d=max(y0,-2.85),min(y1,-2.15)
    if a>=b or c>=d:return [rect]
    return [r for r in [(x0,a,y0,y1),(b,x1,y0,y1),(a,b,y0,c),(a,b,d,y1)] if r[1]-r[0]>.001 and r[3]-r[2]>.001]
FACES=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
def roof_piece(name,rect,top,thickness,material):
    x0,x1,y0,y1=rect
    vertices=[(x,y,top-abs(y)*1.8/4.1+dz) for x in (x0,x1) for y in (y0,y1) for dz in (-thickness,0)]
    return C.mesh(name,vertices,FACES,material)
for x0,x1,y0,y1 in cut_flue((-6,6,-3.5,3.5)):
    box('ceiling',((x0+x1)/2,(y0+y1)/2,3.12),(x1-x0,y1-y0,.16),WOOD)
for side in (-1,1):
    for rect in cut_flue((-6.6,6.6,min(0,side*4.1),max(0,side*4.1))):
        roof_piece('roof',rect,4.92,.14,WOOD)
        roof_piece('roof-colonly',rect,4.92,.14,WOOD).hide_render=True
for x in (-5.8,5.8):
    edge=4.78-3.3*1.8/4.1
    outline=[(-3.3,3.1),(-3.3,edge),(0,4.78),(3.3,edge),(3.3,3.1)]
    vertices=[(x+dx,y,z) for dx in (-.2,.2) for y,z in outline]
    C.mesh('gable',vertices,[tuple(range(5)),tuple(range(5,10))]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)],LIME)
for side in (-1,1):
    for row in range(10):
        low=row*4.1/10;high=min(4.1,(row+1)*4.1/10+.08)
        y0,y1=sorted([side*low,side*high])
        for column in range(27):
            x=-6.35+column*.49
            x0,x1=max(-6.6,x-.24),min(6.6,x+.24)
            if x1<=x0:continue
            for rect in cut_flue((x0,x1,y0,y1)):
                roof_piece('roof clay plate',rect,4.975+row*.004,.04,TILE)
for rect in [(4.3,4.55,-3,-2),(5.05,5.3,-3,-2),(4.55,5.05,-3,-2.75),(4.55,5.05,-2.25,-2)]:
    roof_piece('stove flashing',rect,5.025,.025,IRON)
box('roof ridge',(0,0,4.96),(13.2,.22,.08),TILE,False)
for x in (-1.42,1.42):
    box('canopy footing',(x,-4.98,.10),(.24,.24,.2),STONE)
    box('canopy post',(x,-4.98,1.4),(.14,.14,2.4),WOOD)
    C.beam('canopy rafter',(x,-3.5,2.95),(x,-5.1,2.6),.12,.12,WOOD)
C.mesh('entry shade',[(-1.5,-3.5,2.96),(1.5,-3.5,2.96),(1.5,-5.1,2.61),(-1.5,-5.1,2.61)],[(0,1,2,3)],CLOTH)
# Four whole beds leave the shared aisle clear beside their foot ends.
for y in (-2.25,-.75,.75,2.25):
    box('bed frame',(-4.4,y,.38),(2.1,.9,.14),WOOD)
    for dx in (-.92,.92):
        for dy in (-.33,.33):box('bed leg',(-4.4+dx,y+dy,.155),(.1,.1,.31),WOOD,False)
    box('bedding',(-4.4,y,.50),(1.95,.82,.10),CLOTH,False)
box('kitchen worktop',(5,.1,.9),(.7,2.1,.16),WOOD)
for y in (-.8,1):box('worktop support',(5,y,.41),(.6,.14,.82),WOOD)
box('cook hearth',(4.8,-2.5,.06),(1.3,1.3,.12),STONE)
box('cooking stove',(4.8,-2.5,.66),(1.1,1.1,1.08),STONE)
box('stove hatch',(4.21,-2.5,.66),(.08,.44,.4),IRON,False)
box('stove hood',(4.8,-2.5,1.29),(1.2,1.2,.18),STONE)
box('cook plate',(4.8,-2.5,1.405),(1.1,1.1,.05),IRON,False)
box('flue lower',(4.8,-2.5,2.495),(.5,.5,2.41),STONE)
for dx in (-.2,.2):box('flue upper',(4.8+dx,-2.5,4.23),(.1,.5,1.06),STONE)
for dy in (-.2,.2):box('flue upper',(4.8,-2.5+dy,4.23),(.3,.1,1.06),STONE)
for dx in (-.25,.25):box('flue coping',(4.8+dx,-2.5,4.82),(.2,.7,.12),STONE)
for dy in (-.25,.25):box('flue coping',(4.8,-2.5+dy,4.82),(.3,.2,.12),STONE)
for dx in (-.3,.3):box('ceiling collar',(4.8+dx,-2.5,3.12),(.1,.7,.16),STONE)
for dy in (-.3,.3):box('ceiling collar',(4.8,-2.5+dy,3.12),(.5,.1,.16),STONE)
box('washbasin pedestal',(4.8,2.55,.4),(.6,.6,.8),STONE)
vertices=[];count=16
for radius,z in [(.32,.8),(.43,1.02),(.36,1.02),(.27,.86)]:
    for k in range(count):
        angle=k*math.tau/count
        vertices.append((4.8+radius*math.cos(angle),2.55+radius*math.sin(angle),z))
faces=[]
for k in range(count):
    j=(k+1)%count
    faces.extend([(k,j,j+count,k+count),(k+count,j+count,j+2*count,k+2*count),(k+2*count,j+2*count,j+3*count,k+3*count),(k+3*count,j+3*count,j,k)])
faces.append(tuple(range(3*count,4*count)))
C.mesh('hollow washing bowl',vertices,faces,STONE)
water=[(4.8+.29*math.cos(k*math.tau/count),2.55+.29*math.sin(k*math.tau/count),.90) for k in range(count)]
C.mesh('basin water',water,[tuple(range(count))],WATER)
door_parts=[]
for name,angle in [('EntryPortal',0),('ServicePortal',math.pi)]:
    portal=bpy.data.objects.new(name,None);C.ASSET.objects.link(portal)
    portal.rotation_euler.z=angle
    hinge=bpy.data.objects.new(name+'_entry_hinge',None);C.ASSET.objects.link(hinge)
    hinge.parent=portal;hinge.location=(-.65,-3.3,0);hinge['open_angle_degrees']=-100
    for k in range(5):
        part=box('Door plank',(-.52+k*.26,-3.3,1.18),(.252,.08,2.36),WOOD,False)
        part.parent=hinge;part.location-=Vector((-.65,-3.3,0))
        door_parts.append(part)
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
asset=OUT/'d_pilgrim.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
tints={'DP lime':(.78,.68,.52),'DP stone':(.72,.63,.49),'DP timber':(.32,.23,.15)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_pilgrim.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; peer and campaign/mobile QA pending','walls':[12,7],'ridge':5,'triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
