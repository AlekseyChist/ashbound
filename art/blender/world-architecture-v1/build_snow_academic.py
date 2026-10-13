"""S-A production shell: approved 18x12m, two floors, ridge11m. QA pending."""
import sys, json, hashlib, math, struct
from pathlib import Path
import bpy, bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/snow-academic';QA.mkdir(parents=True,exist_ok=True)
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
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if solid:coll.append((n,p,s))
    return o
box('foundation',(0,0,-.18),(18,12,.36),STONE)
# Upper slab excludes the full stair envelope, including the upper landing.
box('upper west slab',(-2.125,0,3.48),(13.75,12,.24),WOOD)
box('upper front slab',(6.875,-3.25,3.48),(4.25,5.5,.24),WOOD)
box('upper back slab',(6.875,5.5,3.48),(4.25,1,.24),WOOD)
box('upper stair landing',(7.3,-.35,3.48),(1.6,.7,.24),WOOD)
def wall(n,axis,fixed,a,b,z0,z1,holes=()):
    # Apertures are actual missing wall volumes, not painted rectangles.
    cuts=[a,b]+[v for h in holes for v in h[:2]]
    cuts=sorted(set(cuts))
    for lo,hi in zip(cuts,cuts[1:]):
        opening=next((h for h in holes if lo>=h[0] and hi<=h[1]),None)
        bands=[(z0,z1)] if opening is None else [(z0,opening[2]),(opening[3],z1)]
        for bottom,top in bands:
            if top-bottom<.001:continue
            p=((lo+hi)/2,fixed,(bottom+top)/2) if axis=='x' else (fixed,(lo+hi)/2,(bottom+top)/2)
            s=(hi-lo,.4,top-bottom) if axis=='x' else (.4,hi-lo,top-bottom)
            box(n,p,s,STONE if z0==0 else PLASTER)
for level in (0,3.6):
    openings=[(-7,-5.6,level+1.15,level+2.45),(5.6,7,level+1.15,level+2.45)]
    front=list(openings)
    if level==0:front.append((-.8,.8,0,2.5))
    wall('front','x',-5.8,-9,9,level,3.6 if level==0 else 7.33,front)
    wall('rear','x',5.8,-9,9,level,3.6 if level==0 else 7.33,openings)
    for x in (-8.8,8.8):
        wall('side','y',x,-5.6,5.6,level,level+3.6,[(-3.6,-2.2,level+1.15,level+2.45),(1.5,2.9,level+1.15,level+2.45)])
    # Continuous corridor walls with door gaps, clear1.8m between faces.
    for x in (-1.1,1.1):
        wall('corridor','y',x,-5.6,5.6,level,level+3.48,[(-2.4,-1,level,level+2.4),(1.1,2.5,level,level+2.4),(4.2,5.5,level,level+2.4)])
# East back passage connects the corridor to the stair foot.
box('class rear partition',(5,-1.2,1.68),(7.4,.18,3.36),PLASTER)
for y in (-.5,3.2):
    box('upper west cell partition',(-5,y,5.28),(7.4,.18,3.36),PLASTER)
wall('upper east cell partition','x',-1.2,1.3,8.7,3.6,6.96,[(3.8,5.2,3.6,6)])
# Two twelve-rise flights: 0.15m rise /0.28m tread,1.4m wide.
for k in range(12):
    box('first tread',(5.6,.14+k*.28,(k+1)*.15-.045),(1.4,.28,.09),WOOD,False)
    box('second tread',(7.3,3.22-k*.28,1.8+(k+1)*.15-.045),(1.4,.28,.09),WOOD,False)
box('mid landing',(6.45,4.06,1.71),(3.1,1.4,.18),WOOD)
for x in (5.05,7.85):
    for y in (3.55,4.55):box('landing support',(x,y,.81),(.18,.18,1.62),WOOD)
for x,y0,y1,z0,z1 in [(5.6,0,3.36,0,1.8),(7.3,3.36,0,1.8,3.6)]:
    for offset in (-.62,.62):
        C.beam('stair stringer',(x+offset,y0,z0-.08),(x+offset,y1,z1-.08),.16,.22,WOOD)
        C.beam('stair handrail',(x+offset,y0,z0+1),(x+offset,y1,z1+1),.08,.08,WOOD)
        for t in (0,.5,1):
            y=y0+(y1-y0)*t;z=z0+(z1-z0)*t
            box('rail post',(x+offset,y,z+.5),(.08,.08,1),WOOD)
for x in (4.9,6.45,8):box('landing rail post',(x,4.72,2.3),(.08,.08,1),WOOD)
C.beam('landing rear rail',(4.9,4.72,2.8),(8,4.72,2.8),.08,.08,WOOD)
def ramp(n,x,y0,y1,bottom,top):
    vertices=[(x+dx,y,z) for dx in (-.7,.7) for y,z in ((y0,bottom),(y1,bottom),(y1,top))]
    faces=[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)]
    o=C.mesh(n+'-colonly',vertices,faces,WOOD);o.hide_render=True
ramp('first stair',5.6,0,3.36,0,1.8)
ramp('second stair',7.3,3.36,0,1.8,3.6)
# Ceiling closes nonplayable roof; the top ridge remains exactly11m.
box('upper ceiling',(0,0,7.14),(18,12,.12),WOOD)
for side in (-1,1):
    points=[(x,y,z) for x in (-9.4,9.4) for y,z in ((0,10.88),(side*6.4,7.13),(side*6.4,6.98),(0,10.73))]
    o=C.mesh('roof panel',points,[(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5),(0,3,2,1),(4,5,6,7)],SLATE)
    roof_col=C.mesh('roof panel-colonly',points,[(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5),(0,3,2,1),(4,5,6,7)],SLATE)
    roof_col.hide_render=True
for x in (-8.8,8.8):
    outline=[(-5.8,7.2),(-5.8,7.33),(0,10.73),(5.8,7.33),(5.8,7.2)]
    vertices=[(x+dx,y,z) for dx in (-.2,.2) for y,z in outline]
    faces=[tuple(range(5)),tuple(range(5,10))]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)]
    C.mesh('gable',vertices,faces,PLASTER)
for side in (-1,1):
    for row in range(12):
        y=side*(row+.5)*6.4/12
        for column in range(38):
            x=-9.25+column*.5
            vertices=[(dx,dy,dz) for dx in (-.255,.255) for dy in (-.335,.335) for dz in (-.025,.025)]
            tile=C.mesh('slate plate',vertices,[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)],SLATE)
            tile.location=(x,y,10.94-abs(y)*3.75/6.4)
            tile.rotation_euler.x=-side*math.atan(3.75/6.4)
box('ridge cap',(0,0,10.94),(19,.24,.12),SLATE,False)
# Window joinery follows the actual aperture dimensions on both floors.
for level in (0,3.6):
    for y in (-5.8,5.8):
        for x in (-6.3,6.3):
            for dx in (-.73,.73):box('window jamb',(x+dx,y,level+1.8),(.09,.48,1.4),WOOD)
            for z in (1.12,2.48):box('window rail',(x,y,level+z),(1.55,.48,.09),WOOD)
            box('window mullion',(x,y,level+1.8),(.055,.08,1.3),WOOD)
            box('window sill',(x,y,level+1.08),(1.65,.68,.10),WOOD)
    for x in (-8.8,8.8):
        for y in (-2.9,2.2):
            for dy in (-.73,.73):box('side window jamb',(x,y+dy,level+1.8),(.48,.09,1.4),WOOD)
            for z in (1.12,2.48):box('side window rail',(x,y,level+z),(.48,1.55,.09),WOOD)
            box('side window mullion',(x,y,level+1.8),(.08,.055,1.3),WOOD)
            box('side window sill',(x,y,level+1.08),(.68,1.65,.1),WOOD)
for x in (-8.8,-3,3,8.8):
    for y in (-5.82,5.82):box('facade upright',(x,y,3.6),(.16,.46,7.2),WOOD)
for z in (3.6,7.18):
    for y in (-5.82,5.82):box('facade belt',(0,y,z),(18,.48,.16),WOOD)
def prop(n,p,s,m=WOOD,solid=True):
    o=box(n,p,s,m,solid);o['part_role']='interior_furniture';furniture.append(o)
    return o
def table(n,x,y,z,width=2):
    prop(n+' top',(x,y,z+.76),(width,.8,.12))
    for dx in (-width/2+.12,width/2-.12):
        for dy in (-.28,.28):prop(n+' leg',(x+dx,y+dy,z+.35),(.1,.1,.7),solid=False)
def bench(n,x,y,z,width=1.8):
    prop(n+' seat',(x,y,z+.46),(width,.35,.1))
    for dx in (-width/2+.15,width/2-.15):prop(n+' leg',(x+dx,y,z+.205),(.12,.32,.41),solid=False)
for y in (-3.8,.1,3.8):
    table('reading table',-6.2,y,0,2.4)
    bench('reading bench',-6.2,y+.85,0,2.2)
    for dx in (-.65,.65):prop('reading book',(-6.2+dx,y,.85),(.3,.4,.055),BOOK,False)
for x in (3.3,6.5):
    table('class desk',x,-4,0,1.8);bench('class bench',x,-3.2,0,1.6)
prop('teaching board',(3.1,-5.49,1.8),(2.6,.08,1.1),BOOK,False)
for z in (.35,.95,1.55):prop('reading shelf',(-8.08,.1,z),(.6,2.8,.09))
for y in (-1.25,1.45):prop('shelf end',(-8.08,y,.95),(.6,.09,1.4))
for k in range(12):prop('shelved book',(-8.08,-1.08+k*.19,1.13),(.3,.09,.28),BOOK,False)
for x,y in [(-6.1,-4.6),(-6.1,1),(-6.1,4.5),(6.5,-4.6),(2.9,3.3)]:
    z=3.6
    prop('cell bed frame',(x,y,z+.36),(2.1,.95,.14))
    for dx in (-.92,.92):
        for dy in (-.36,.36):prop('bed leg',(x+dx,y+dy,z+.145),(.1,.1,.29),solid=False)
    prop('cell bedding',(x,y,z+.49),(1.95,.86,.12),LINEN)
    prop('cell pillow',(x-.72,y,z+.60),(.35,.72,.1),LINEN,False)
    # Small tables occupy the outside wall, leaving the door approach clear.
    desk_y=.9 if y==3.3 else 3.8 if y==4.5 else y
    table('cell desk',-3.1 if x<0 else 3.1,desk_y,z,.8)
# Entry leaf uses the existing door contract; no extra static blocker.
hinge=bpy.data.objects.new('SA_entry_hinge',None);C.ASSET.objects.link(hinge)
hinge.location=(-.76,-5.8,0);hinge['open_angle_degrees']=-100.0
door_parts=[]
for k in range(6):door_parts.append(box('Door plank',(-.635+k*.254,-5.8,1.22),(.248,.08,2.44),WOOD,False))
for z in (.45,1.95):door_parts.append(box('Door strap',(0,-5.85,z),(1.5,.02,.055),IRON,False))
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
asset=OUT/'s_academic.glb'
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
stats={'state':'WIP furnished; canonical runtime and roof QA pending','triangles':triangles,'meshes':len(visual),'wall_footprint':[18,12],'floors':2,'ridge':11,'stair_rises':24,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_academic.blend'))
print('S_A_SHELL',json.dumps(stats))
