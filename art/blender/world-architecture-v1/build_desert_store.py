"""Desert plots z1/z2/z10/z11: store of imported grain and timber, 8x6 m; canonical GLB source.

One hall. Single door centred on the front (-y) facade; a clear aisle at least
1.2 m wide runs from the door to the rear wall. Grain stores on the left (-x),
timber stacks on the right (+x). Blender axes: z up, facade with door at -y.
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
QA=ROOT/'local/qa/desert-store';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DS stone','stone_wall_02_diff_1k.jpg',2)
LIME=surface('DS lime','plaster_grey_04_diff_1k.jpg',2)
WOOD=surface('DS timber','fine_grained_wood_col_1k.jpg',.65)
CLOTH=C.mat('DS shade',(.36,.30,.20,1),.98)
SACK=C.mat('DS sacking',(.55,.46,.32,1),.98)
IRON=C.mat('DS iron',(.20,.19,.18,1),.5,.5)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('grain sack','pallet','timber stack','trestle','scale table','scale post','scale beam','scale cord','scale pan')):
        o['part_role']='interior_furniture'
    if solid:coll.append((n,p,s))
    return o

def ring_solid(n,x,y,z,rings,m,role=True):
    # a closed solid of octagonal rings [(dz, half_x, half_y), ...] from bottom to top around (x,y,z)
    k=8
    v=[]
    for dz,hx,hy in rings:
        for i in range(k):
            a=math.pi*2*i/k+math.pi/8
            v.append((x+hx*math.cos(a),y+hy*math.sin(a),z+dz))
    f=[tuple(range(k-1,-1,-1))]
    for r in range(len(rings)-1):
        for i in range(k):
            j=(i+1)%k
            f.append((r*k+i,r*k+j,(r+1)*k+j,(r+1)*k+i))
    t=(len(rings)-1)*k
    f.append(tuple(range(t,t+k)))
    o=C.mesh(n,v,f,m)
    if role:o['part_role']='interior_furniture'
    return o

def slab(n,pts,t,m):
    # a thin solid under the quad pts (4 corners, counter-clockwise from above), thickness t downward
    v=[(px,py,pz-t) for px,py,pz in pts]+list(pts)
    f=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    return C.mesh(n,v,f,m)
# Shell: outer walls 8x6 (faces at x +-4, y +-3; inner faces +-3.6 / +-2.6), floor z=0, roof top ~3.6.
box('foundation',(0,0,-.15),(8,6,.3),STONE)
box('entry porch',(0,-3.6,-.12),(3.0,1.2,.24),STONE)
# Outer walls inside the 8x6 envelope: centre lines x +-3.8, y +-2.8, 0.4 thick, wall height 3.2.
# Front wall with 1.8 m door opening centred x=0 (x -0.9..0.9).
for a,b in [(-4,-.9),(.9,4)]:
    box('front wall',((a+b)/2,-2.8,1.6),(b-a,.4,3.2),LIME)
box('door header',(0,-2.8,2.75),(1.8,.4,.9),LIME)
# Rear wall, whole.
box('rear wall',(0,2.8,1.6),(8,.4,3.2),LIME)
# Side walls with one high narrow ventilation louver each (grain air), y -0.4..0.4, z 2.3..2.8.
for x in (-3.8,3.8):
    box('side wall base',(x,0,1.15),(.4,5.2,2.3),LIME)          # y -2.6..2.6, z 0..2.3
    for a,b in [(-2.6,-.4),(.4,2.6)]:
        box('side wall upper',(x,(a+b)/2,2.75),(.4,b-a,.9),LIME) # z 2.3..3.2
    box('louver head',(x,0,3.0),(.4,.8,.4),LIME)                 # z 2.8..3.2 over the louver
# Ceiling and roof (slight slope via mesh).
FACES=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
def roof_piece(name,x0,x1,y0,y1,top,thick,material):
    vertices=[(x,y,top-y*.012+dz) for x in (x0,x1) for y in (y0,y1) for dz in (-thick,0)]
    return C.mesh(name,vertices,FACES,material)
# inset into the walls' thickness (as Codex 477 DA-ROOF-JOINT-01 on the archery pavilion: a ceiling as large
# as the walls' outer faces lay in them - a black band under the roof)
box('ceiling',(0,0,3.12),(7.6,5.6,.16),WOOD)
# the bond course (as the workshop's DW-ROOF-01 and the shop's DS-ROOF-01: walls stopped at 3.20, the roof
# slab's underside at 3.45-0.012y - a 22-28 cm open belt): masonry over every wall line up into the slab
def course(n,x0,x1,y0,y1):
    vs=[(x,y,z) for x in (x0,x1) for y in (y0,y1) for z in (3.19,3.47-y*.012)]
    return C.mesh(n,vs,FACES,LIME)
course('bond course',-4.0,4.0,-3.0,-2.6)
course('bond course',-4.0,4.0,2.6,3.0)
course('bond course',-4.0,-3.6,-2.6,2.6)
course('bond course',3.6,4.0,-2.6,2.6)
roof_piece('flat lime roof',-4.3,4.3,-3.3,3.3,3.6,.15,LIME)
roof_piece('flat roof-colonly',-4.3,4.3,-3.3,3.3,3.6,.15,LIME).hide_render=True
# Parapet (eaves max 0.3 beyond walls).
for x in (-3.9,3.9):box('side parapet',(x,0,3.74),(.2,6.0,.48),LIME)
box('front parapet',(0,-2.9,3.74),(8,.2,.48),LIME)
# the rear parapet open over the single drain (x 0, 0.3 wide)
for a,b in [(-4,-.15),(.15,4)]:
    box('rear parapet',((a+b)/2,2.9,3.74),(b-a,.2,.48),LIME)
# Drainage: one channel through rear parapet with outside outlets.
roof_piece('drain base',-.15,.15,2.6,3.3,3.6,.06,STONE)
for dx in (-.14,.14):roof_piece('drain cheek',dx-.03,dx+.03,2.6,3.3,3.72,.12,STONE)
# Supported timber shade at entry (front, max 1.2 m projection from the -3.0 wall).
for x in (-1.3,1.3):
    box('canopy footing',(x,-4.05,.10),(.24,.24,.2),STONE)
    box('canopy post',(x,-4.05,1.4),(.14,.14,2.4),WOOD)
    C.beam('canopy rafter',(x,-3.0,2.95),(x,-4.12,2.62),.12,.12,WOOD)
slab('entry shade',[(-1.5,-3.0,2.96),(1.5,-3.0,2.96),(1.5,-4.12,2.62),(-1.5,-4.12,2.62)],.03,CLOTH)
# Interior: floor z=0, inner wall faces x +-3.6, y -2.6..2.6; aisle x -0.6..0.6 kept clear.
# Left (-x): two pallets of grain sacks.
for y in (-1.2,1.0):
    box('pallet',(-2.4,y,.08),(1.9,1.6,.16),WOOD)
    for dx in (-.5,.5):
        for dy in (-.4,.4):
            ring_solid('grain sack',-2.4+dx,y+dy,.16,[(0,.36,.28),(.12,.45,.35),(.36,.43,.33),(.5,.26,.2),(.56,.08,.07)],SACK)
            box('grain sack tie',(-2.4+dx,y+dy,.74),(.1,.1,.06),SACK,False)
    for dx in (-.25,.25):
        ring_solid('grain sack',-2.4+dx,y,.62,[(0,.33,.26),(.1,.42,.32),(.32,.4,.3),(.44,.24,.18),(.5,.07,.06)],SACK)
# Right (+x): trestles and timber stacks.
for y in (-0.9,1.3):
    for dx in (-.7,.7):box('trestle',(2.4+dx,y,.35),(.12,1.4,.7),WOOD)
    # a stack on each pair of trestles (the draft laid one stack across both pairs' inner ends)
    for k in range(4):
        for dy in (-.45,-.15,.15,.45):
            box('timber stack',(2.4,y+dy,.77+k*.15),(1.9,.26,.08),WOOD,False)
        for dx in (-.7,.7):
            box('timber stack spacer',(2.4+dx,y,.72+k*.15),(.08,1.2,.04),WOOD,False)
    # the stack keeps one obstacle over its whole volume (Codex 282: the boards came without one)
    coll.append(('timber stack',(2.4,y,(.70+1.26)/2),(1.9,1.2,1.26-.70)))
# Scales by the door, right side.
box('scale table',(1.6,-2.0,.78),(1.0,.6,.12),WOOD)
# its four legs to the floor (Codex 279: the top stood on nothing)
for dx in (-.43,.43):
    for dy in (-.23,.23):box('scale table leg',(1.6+dx,-2.0+dy,.36),(.08,.08,.72),WOOD,False)
box('scale post',(1.6,-2.0,1.25),(.06,.06,.82),WOOD)
box('scale beam',(1.6,-2.0,1.64),(.74,.04,.04),WOOD,False)
for dx in (-.34,.34):
    box('scale cord',(1.6+dx,-2.0,1.45),(.01,.01,.38),WOOD,False)
    ring_solid('scale pan',1.6+dx,-2.0,1.24,[(0,.1,.1),(.03,.15,.15)],IRON)
# Door: EntryPortal, front hinge, open -100 deg.
door_parts=[]
portal=bpy.data.objects.new('EntryPortal',None);C.ASSET.objects.link(portal)
hinge=bpy.data.objects.new('EntryPortal_entry_hinge',None);C.ASSET.objects.link(hinge)
hinge.parent=portal;hinge.location=(-.9,-2.8,0);hinge['open_angle_degrees']=-100
for k in range(5):
    # as DS-DOOR-02 on the shop: 2.36 m planks ran 6 cm into the header (from 2.30); now 0.01..2.27
    part=box('Door plank',(-.7+k*.35,-2.8,1.14),(.35,.08,2.26),WOOD,False)
    part.parent=hinge;part.location-=Vector((-.9,-2.8,0))
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
asset=OUT/'d_store_8x6.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
tints={'DS lime':(.80,.70,.54),'DS stone':(.72,.63,.49),'DS timber':(.33,.24,.16)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_store_8x6.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; Codex export and Godot review pending','walls':[8,6],'maximum_height':4.0,'rooms':['hall'],'triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'entry_hinge':'EntryPortal_entry_hinge at (-0.9,-2.8,0), open -100 deg','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
