"""Desert plot A: halberd barracks 'Alebardny dvor', 13x7 m; canonical GLB source.

Arrangement (for Codex inspection): one central circulation lane along the
front wall (y -3.5..-1.0, >=1.0 m clear to the rack line at y=-1.0); sleeping
side x -6.5..-2.0 (two adult beds + bench, all reachable from the lane and
back through the partition door); equipment side x 2.0..6.5 (worktable,
storage chest, supported long-pole rack along the rear wall, clear of the
door swing; four static halberds stand on the rack (props only). One exterior
door only, front centre, no interior moving doors.
"""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/qa/desert-halberd-house';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DH stone','stone_wall_02_diff_1k.jpg',2)
LIME=surface('DH lime','plaster_grey_04_diff_1k.jpg',2)
WOOD=surface('DH timber','fine_grained_wood_col_1k.jpg',.65)
CLOTH=C.mat('DH shade',(.36,.30,.20,1),.98)
LINEN=C.mat('DH bedding',(.27,.24,.18,1),.98)
IRON=C.mat('DH iron',(.16,.16,.17,1),.45,.6)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('bed frame','bed leg','bedding','bench','bench leg','worktable','worktable leg','storage chest','rack post','rack rail','pole rest')):
        o['part_role']='interior_furniture'
    if n.startswith(('halberd shaft','halberd blade','halberd hook','halberd spike')):
        o['part_role']='interior_furniture'
    if solid:coll.append((n,p,s))
    return o
def plate(n,x,y,z,outline,t,m):
    # flat iron piece: outline [(dx,dz),...] counter-clockwise around (x,z), thickness t along y
    v=[(x+a,y-t/2,z+b) for a,b in outline]+[(x+a,y+t/2,z+b) for a,b in outline]
    k=len(outline)
    f=[tuple(range(k-1,-1,-1)),tuple(range(k,2*k))]
    for i in range(k):
        j=(i+1)%k
        f.append((i,j,k+j,k+i))
    o=C.mesh(n,v,f,m)
    o['part_role']='interior_furniture'
    return o
# Shell: outer faces exactly x +-6.5, y +-3.5; wall centre lines x +-6.3, y +-3.3 (0.4 thick).
box('foundation',(0,0,-.15),(13,7,.3),STONE)
box('entry porch',(0,-4.1,-.12),(3.4,1.2,.24),STONE)
# Front wall with 1.8 m door opening centred x=0 (clear width >=1.6).
for a,b in [(-6.5,-.9),(.9,6.5)]:
    box('front wall',((a+b)/2,-3.3,1.75),(b-a,.4,3.5),LIME)
box('door header',(0,-3.3,2.95),(1.8,.4,1.1),LIME)
# Rear wall with two windows (sleeping x=-4.2, equipment x=4.2), 1.0 m wide, sill 1.2, head 2.35.
for a,b in [(-6.5,-4.7),(-3.7,3.7),(4.7,6.5)]:
    box('rear wall',((a+b)/2,3.3,1.75),(b-a,.4,3.5),LIME)
for x in (-4.2,4.2):
    box('window sill wall',(x,3.3,.6),(1.0,.4,1.2),LIME)
    box('window head wall',(x,3.3,2.925),(1.0,.4,1.15),LIME)
    for dx in (-.46,.46):box('window jamb',(x+dx,3.3,1.775),(.08,.48,1.23),WOOD)
    for z in (1.17,2.38):box('window rail',(x,3.3,z),(1.0,.48,.08),WOOD)
# Side walls with one narrow window each (y=-1.4), sill 1.2, head 2.35.
for x in (-6.3,6.3):
    for a,b in [(-3.5,-1.9),(-.9,3.5)]:
        box('side wall',(x,(a+b)/2,1.75),(.4,b-a,3.5),LIME)
    box('window sill wall',(x,-1.4,.6),(.4,1.0,1.2),LIME)
    box('window head wall',(x,-1.4,2.925),(.4,1.0,1.15),LIME)
    for dy in (-.46,.46):box('window jamb',(x,-1.4+dy,1.775),(.48,.08,1.23),WOOD)
    for z in (1.17,2.38):box('window rail',(x,-1.4,z),(.48,1.0,.08),WOOD)
# Partitions: sleeping x -6.5..-2.0; equipment x 2.0..6.5; lane -2.0..2.0.
# Sleeping wall x=-2.0 with door opening y -1.0..0.0 (1.0 m).
box('sleeping wall A',(-2.0,-2.25,1.5),(.2,2.5,3),LIME)   # y -3.5..-1.0
box('sleeping wall B',(-2.0,1.75,1.5),(.2,3.5,3),LIME)    # y 0.0..3.5
box('sleeping door header',(-2.0,-.5,2.7),(.2,1.0,.6),LIME)
# Equipment wall x=2.0 with door opening y -1.0..0.0 (1.0 m).
box('equipment wall A',(2.0,-2.25,1.5),(.2,2.5,3),LIME)   # y -3.5..-1.0
box('equipment wall B',(2.0,1.75,1.5),(.2,3.5,3),LIME)    # y 0.0..3.5
box('equipment door header',(2.0,-.5,2.7),(.2,1.0,.6),LIME)
# Ceiling and roof (slight slope via mesh).
FACES=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
def roof_piece(name,x0,x1,y0,y1,top,thick,material):
    vertices=[(x,y,top-y*.012+dz) for x in (x0,x1) for y in (y0,y1) for dz in (-thick,0)]
    return C.mesh(name,vertices,FACES,material)
box('ceiling',(0,0,3.12),(13,7,.16),WOOD)
roof_piece('flat lime roof',-6.8,6.8,-3.8,3.8,3.6,.15,LIME)
roof_piece('flat roof-colonly',-6.8,6.8,-3.8,3.8,3.6,.15,LIME).hide_render=True
# Parapet (eaves max 0.3 beyond walls); rear open over the two drains.
for x in (-6.7,6.7):box('side parapet',(x,0,3.74),(.2,7.0,.48),LIME)
box('front parapet',(0,-3.4,3.74),(13,.2,.48),LIME)
for a,b in [(-6.5,-3.15),(-2.85,2.85),(3.15,6.5)]:
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
# Sleeping side: two adult beds (2.0x0.9) along the west wall, bench between. The west wall's inner
# face is x=-6.1: the frame stands 0.05 m clear of it, x -6.05..-4.05 (Codex review H01: at x=-5.4 the
# frame, bedding and legs ran 0.30 m into the wall).
BED_X=-5.05
for y in (-2.2,2.2):
    box('bed frame',(BED_X,y,.38),(2.0,.9,.14),WOOD)
    for dx in (-.85,.85):
        for ey in (-.32,.32):box('bed leg',(BED_X+dx,y+ey,.155),(.1,.1,.31),WOOD,False)
    box('bedding',(BED_X,y,.50),(1.85,.82,.10),LINEN,False)
box('bench',(-3.6,0,.42),(1.2,.5,.10),WOOD)
for dx in (-.5,.5):box('bench leg',(-3.6+dx,0,.18),(.08,.08,.36),WOOD,False)
# Equipment side: worktable + chest near the partition; long-pole rack along rear wall.
box('worktable',(4.2,-1.6,.78),(1.6,.7,.14),WOOD)
for dx in (-.7,.7):box('worktable leg',(4.2+dx,-1.6,.36),(.1,.1,.72),WOOD,False)
box('storage chest',(5.6,-2.6,.30),(.6,.55,.6),WOOD)
# Supported pole rack: two posts + two rails, poles rest on the rails (no runtime weapons).
for x in (2.8,5.8):
    box('rack post',(x,2.9,.75),(.12,.12,1.5),WOOD,False)
box('rack rail',(4.3,2.9,1.30),(3.2,.10,.10),WOOD,False)
box('rack rail',(4.3,2.9,.80),(3.2,.10,.10),WOOD,False)
# Four static halberds stand on the rack (props only).
for x in (3.25,3.95,4.65,5.35):
    box('halberd shaft',(x,2.825,1.15),(.05,.05,2.3),WOOD,False)
    plate('halberd blade',x,2.825,2.13,[(.02,-.13),(.11,-.16),(.20,-.12),(.25,-.03),(.26,.03),(.21,.11),(.12,.15),(.02,.12)],.02,IRON)
    plate('halberd hook',x,2.825,2.17,[(-.02,-.03),(-.10,-.05),(-.17,-.01),(-.10,.0),(-.02,.03)],.02,IRON)
    plate('halberd spike',x,2.825,2.30,[(-.022,0),(.022,0),(.012,.18),(0,.26),(-.012,.18)],.03,IRON)
# Door: EntryPortal, front hinge at the opening edge, open -100 deg.
door_parts=[]
portal=bpy.data.objects.new('EntryPortal',None);C.ASSET.objects.link(portal)
hinge=bpy.data.objects.new('EntryPortal_entry_hinge',None);C.ASSET.objects.link(hinge)
hinge.parent=portal;hinge.location=(-.9,-3.3,0);hinge['open_angle_degrees']=-100
# Five planks fill the opening x -0.9..0.9 with a 25 mm working gap at both jambs: x -0.875..0.875
# (Codex review H02: the leaf ran 55 mm into the hinge jamb and left 65 mm at the latch).
for k in range(5):
    part=box('Door plank',(-.7+k*.35,-3.3,1.18),(.35,.08,2.36),WOOD,False)
    part.parent=hinge;part.location-=Vector((-.9,-3.3,0))
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
asset=OUT/'d_halberd_house.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
tints={'DH lime':(.80,.70,.54),'DH stone':(.72,.63,.49),'DH timber':(.33,.24,.16)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_halberd_house.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; Codex export and Godot review pending','walls':[13,7],'maximum_height':4.0,'rooms':['central lane','sleeping side','equipment side'],'triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'entry_hinge':'EntryPortal_entry_hinge at (-0.9,-3.3,0), open -100 deg','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
