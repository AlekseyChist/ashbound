"""Desert plot Sh: cells and novice school, 14x7 m; canonical GLB source."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/qa/desert-order-cells';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DO stone','stone_wall_02_diff_1k.jpg',2)
LIME=surface('DO lime','plaster_grey_04_diff_1k.jpg',2)
WOOD=surface('DO timber','fine_grained_wood_col_1k.jpg',.65)
CLOTH=C.mat('DO shade',(.36,.30,.20,1),.98)
LINEN=C.mat('DO bedding',(.27,.24,.18,1),.98)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('desk','bench','shelf','lectern','bed frame','bed leg','bedding','writing desk','storage chest')):
        o['part_role']='interior_furniture'
    if solid:coll.append((n,p,s))
    return o
# Shell: outer walls 14x7 (faces at x +-7, y +-3.5; inner faces +-6.6 / +-3.1), floor z=0, roof top ~3.6.
box('foundation',(0,0,-.15),(14,7,.3),STONE)
box('entry porch',(0,-4.1,-.12),(3.4,1.2,.24),STONE)
# Outer walls inside the 14x7 envelope: centre lines x +-6.8, y +-3.3, 0.4 thick (Codex 2fceb2a:
# centred on +-7/+-3.5 they reached 14.4x7.4).
# Front wall with 1.6 m door opening centred x=0.
for a,b in [(-7,-.8),(.8,7)]:
    box('front wall',((a+b)/2,-3.3,1.75),(b-a,.4,3.5),LIME)
box('door header',(0,-3.3,2.95),(1.6,.4,1.1),LIME)
# Rear wall with two narrow windows (classroom x=-4.8, hall x=0), 1.0 m wide, sill 1.2, head 2.35.
for a,b in [(-7,-5.3),(-4.3,-.5),(.5,7)]:
    box('rear wall',((a+b)/2,3.3,1.75),(b-a,.4,3.5),LIME)
for x in (-4.8,0.0):
    box('window sill wall',(x,3.3,.6),(1.0,.4,1.2),LIME)
    box('window head wall',(x,3.3,2.925),(1.0,.4,1.15),LIME)
    for dx in (-.46,.46):box('window jamb',(x+dx,3.3,1.775),(.08,.48,1.23),WOOD)
    for z in (1.17,2.38):box('window rail',(x,3.3,z),(1.0,.48,.08),WOOD)
# Side walls with one narrow window each (y=-1.4), sill 1.2, head 2.35.
for x in (-6.8,6.8):
    for a,b in [(-3.5,-1.9),(-.9,3.5)]:
        box('side wall',(x,(a+b)/2,1.75),(.4,b-a,3.5),LIME)
    box('window sill wall',(x,-1.4,.6),(.4,1.0,1.2),LIME)
    box('window head wall',(x,-1.4,2.925),(.4,1.0,1.15),LIME)
    for dy in (-.46,.46):box('window jamb',(x,-1.4+dy,1.775),(.48,.08,1.23),WOOD)
    for z in (1.17,2.38):box('window rail',(x,-1.4,z),(.48,1.0,.08),WOOD)
# Partitions: classroom x -7..-2.5; cells x 2.5..7. Hall -2.5..2.5.
# Classroom wall x=-2.5 with door opening y -1.0..0.0 (1.0 m).
box('classroom wall A',(-2.5,-2.25,1.5),(.2,2.5,3),LIME)   # y -3.5..-1.0
box('classroom wall B',(-2.5,1.75,1.5),(.2,3.5,3),LIME)    # y 0.0..3.5
box('classroom door header',(-2.5,-.5,2.7),(.2,1.0,.6),LIME)
# Cell walls x=2.5 with three doors (1.0 m each) at y -2.2,-.7,1.0.
box('cell wall A',(2.5,-3.1,1.5),(.2,.8,3),LIME)    # y -3.5..-2.7
box('cell wall B',(2.5,-1.45,1.5),(.2,.5,3),LIME)   # y -1.7..-1.2
box('cell wall C',(2.5,.15,1.5),(.2,.7,3),LIME)     # y -0.2..0.5
box('cell wall D',(2.5,2.5,1.5),(.2,2.0,3),LIME)    # y 1.5..3.5
for y in (-2.2,-.7,1.0):
    box('cell door header',(2.5,y,2.7),(.2,1.0,.6),LIME)
for y in (-1.45,.2):
    box('cell partition',(4.65,y,1.5),(4.3,.2,3),LIME)
# Ceiling and roof (slight slope via mesh).
FACES=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
def roof_piece(name,x0,x1,y0,y1,top,thick,material):
    vertices=[(x,y,top-y*.012+dz) for x in (x0,x1) for y in (y0,y1) for dz in (-thick,0)]
    return C.mesh(name,vertices,FACES,material)
box('ceiling',(0,0,3.12),(14,7,.16),WOOD)
roof_piece('flat lime roof',-7.3,7.3,-3.8,3.8,3.6,.15,LIME)
roof_piece('flat roof-colonly',-7.3,7.3,-3.8,3.8,3.6,.15,LIME).hide_render=True
# Parapet (eaves max 0.3 beyond walls).
for x in (-6.9,6.9):box('side parapet',(x,0,3.74),(.2,7.0,.48),LIME)
box('front parapet',(0,-3.4,3.74),(14,.2,.48),LIME)
# the rear parapet open over the two drains (x +-3, 0.3 wide; Codex 2fceb2a: it ran on over them)
for a,b in [(-7,-3.15),(-2.85,2.85),(3.15,7)]:
    box('rear parapet',((a+b)/2,3.4,3.74),(b-a,.2,.48),LIME)
# Drainage: two channels through rear parapet with outside outlets.
for x in (-3.0,3.0):
    roof_piece('drain base',x-.15,x+.15,3.1,3.8,3.6,.06,STONE)
    for dx in (-.14,.14):roof_piece('drain cheek',x+dx-.03,x+dx+.03,3.1,3.8,3.72,.12,STONE)
# Supported timber shade at entry (front, max 1.2 m projection).
for x in (-1.4,1.4):
    box('canopy footing',(x,-4.55,.10),(.24,.24,.2),STONE)
    box('canopy post',(x,-4.55,1.4),(.14,.14,2.4),WOOD)
    C.beam('canopy rafter',(x,-3.5,2.95),(x,-4.62,2.62),.12,.12,WOOD)
C.mesh('entry shade',[(-1.6,-3.5,2.96),(1.6,-3.5,2.96),(1.6,-4.64,2.62),(-1.6,-4.64,2.62)],[(0,1,2,3)],CLOTH)
# Classroom furniture: two desk rows + benches, shelf, lectern.
# A 0.75m aisle between the 0.7m desktops admits an adult capsule.
for y in (-2.35,-.9):
    box('desk',(-5.6,y,.78),(1.6,.7,.14),WOOD)
    for dx in (-.7,.7):box('desk leg',(-5.6+dx,y,.36),(.1,.1,.72),WOOD,False)
    box('bench',(-3.9,y,.42),(1.2,.5,.10),WOOD)
    for dx in (-.5,.5):box('bench leg',(-3.9+dx,y,.18),(.08,.08,.36),WOOD,False)
# Preserve the source footprint, but model the shelf as supported boards rather
# than an opaque solid block. Its aisle and wall clearance stay unchanged.
box('shelf back',(-6.52,1.6,1.0),(.06,2.4,2.0),WOOD)
for y in (.45,2.75):box('shelf side',(-6.35,y,1.0),(.4,.1,2.0),WOOD)
for z in (.06,.68,1.30,1.94):box('shelf board',(-6.35,1.6,z),(.4,2.4,.12),WOOD)
box('lectern',(-3.1,1.6,.95),(.5,.5,.14),WOOD)
box('lectern post',(-3.1,1.6,.47),(.12,.12,.94),WOOD,False)
# Cells: bed, writing desk, storage chest each.
for c,dy in ((-2.425,-2.75),(-.625,-.25),(1.8,2.75)):
    box('bed frame',(5.6,c,.38),(2.0,.9,.14),WOOD)
    for dx in (-.85,.85):
        for ey in (-.32,.32):box('bed leg',(5.6+dx,c+ey,.155),(.1,.1,.31),WOOD,False)
    box('bedding',(5.6,c,.50),(1.85,.82,.10),LINEN,False)
    box('writing desk',(3.4,dy,.78),(1.1,.6,.12),WOOD)
    for dx in (-.45,.45):box('desk leg',(3.4+dx,dy,.36),(.08,.08,.72),WOOD,False)
    box('storage chest',(4.3,dy,.30),(.6,.55,.6),WOOD)
# Door: EntryPortal, front hinge, open -100 deg.
door_parts=[]
portal=bpy.data.objects.new('EntryPortal',None);C.ASSET.objects.link(portal)
hinge=bpy.data.objects.new('EntryPortal_entry_hinge',None);C.ASSET.objects.link(hinge)
hinge.parent=portal;hinge.location=(-.8,-3.3,0);hinge['open_angle_degrees']=-100
for k in range(5):
    part=box('Door plank',(-.68+k*.32,-3.3,1.18),(.31,.08,2.36),WOOD,False)
    part.parent=hinge;part.location-=Vector((-.8,-3.3,0))
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
asset=OUT/'d_order_cells.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
tints={'DO lime':(.80,.70,.54),'DO stone':(.72,.63,.49),'DO timber':(.33,.24,.16)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_order_cells.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; Codex export and Godot review pending','walls':[14,7],'maximum_height':4.0,'rooms':['hall','classroom','cell A','cell B','cell C'],'triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'entry_hinge':'EntryPortal_entry_hinge at (-0.8,-3.3,0), open -100 deg','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
