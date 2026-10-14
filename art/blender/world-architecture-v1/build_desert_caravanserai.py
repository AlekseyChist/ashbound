"""Desert plot Ks: caravanserai south of the gates, 14x8 m; canonical GLB source.

Left wing: tethered-animal stalls with an open street arch (x -6.2..-3.8, no door).
Centre: common room with a hearth; people's entry is the centred front door (x -0.9..0.9).
Right: sleeping room behind a partition with a 1.0 m opening. Aisles >= 1.0 m.
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
QA=ROOT/'local/qa/desert-caravanserai';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DK stone','stone_wall_02_diff_1k.jpg',2)
LIME=surface('DK lime','plaster_grey_04_diff_1k.jpg',2)
WOOD=surface('DK timber','fine_grained_wood_col_1k.jpg',.65)
CLOTH=C.mat('DK shade',(.36,.30,.20,1),.98)
HAY=C.mat('DK hay',(.70,.60,.34,1),.98)
RUG=C.mat('DK rug',(.42,.16,.12,1),.98)
CLAY=C.mat('DK clay',(.60,.38,.24,1),.9)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('trough','hitching','hay','hearth','low table','floor cushion','sleeping mat','chest','jar')):
        o['part_role']='interior_furniture'
    if solid:coll.append((n,p,s))
    return o
def slab(n,pts,t,m):
    v=[(px,py,pz-t) for px,py,pz in pts]+list(pts)
    f=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    return C.mesh(n,v,f,m)
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
# Shell: outer walls 14x8 (faces at x +-7, y +-4; inner faces +-6.6 / +-3.6), floor z=0, roof top ~3.8.
box('foundation',(0,0,-.15),(14,8,.3),STONE)
box('entry porch',(0,-4.6,-.12),(3.4,1.2,.24),STONE)
# Front wall y=-3.8 in pieces (z 0..3.4, centre 1.7): stable arch x -6.2..-3.8 open to the street,
# centred door opening x -0.9..0.9.
box('front wall',(-6.6,-3.8,1.7),(.8,.4,3.4),LIME)          # x -7.0..-6.2
box('stable arch head',(-5.0,-3.8,3.0),(2.4,.4,.8),LIME)    # over the arch, opening to z 2.6
box('front wall',(-2.35,-3.8,1.7),(2.9,.4,3.4),LIME)        # x -3.8..-0.9
box('door header',(0,-3.8,2.9),(1.8,.4,1.0),LIME)
box('front wall',(3.95,-3.8,1.7),(6.1,.4,3.4),LIME)         # x 0.9..7.0
# Rear wall whole; side walls.
box('rear wall',(0,3.8,1.7),(14,.4,3.4),LIME)
for x in (-6.8,6.8):
    box('side wall',(x,0,1.7),(.4,7.2,3.4),LIME)
# Stable partition x=-3.0 (0.2 thick, 3.0 high) with opening y -1.0..0.4 (1.4 m).
box('stable partition',(-3.0,-2.3,1.5),(.2,2.6,3.0),LIME)   # y -3.6..-1.0
box('stable partition',(-3.0,2.0,1.5),(.2,3.2,3.0),LIME)    # y 0.4..3.6
box('stable partition head',(-3.0,-.3,2.7),(.2,1.4,.6),LIME)
# Sleeping-room partition x=3.0 with opening y 1.4..2.4 (1.0 m).
box('room partition',(3.0,-1.1,1.5),(.2,5.0,3.0),LIME)      # y -3.6..1.4
box('room partition',(3.0,3.0,1.5),(.2,1.2,3.0),LIME)       # y 2.4..3.6
box('room partition head',(3.0,1.9,2.7),(.2,1.0,.6),LIME)
# Ceiling and roof (slight slope via mesh).
FACES=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
def roof_piece(name,x0,x1,y0,y1,top,thick,material):
    vertices=[(x,y,top-y*.012+dz) for x in (x0,x1) for y in (y0,y1) for dz in (-thick,0)]
    return C.mesh(name,vertices,FACES,material)
box('ceiling',(0,0,3.32),(14,8,.16),WOOD)
roof_piece('flat lime roof',-7.3,7.3,-4.3,4.3,3.8,.15,LIME)
roof_piece('flat roof-colonly',-7.3,7.3,-4.3,4.3,3.8,.15,LIME).hide_render=True
# Parapet (eaves max 0.3 beyond walls), z 3.94, height .48.
for x in (-6.9,6.9):box('side parapet',(x,0,3.94),(.2,8.0,.48),LIME)
box('front parapet',(0,-3.9,3.94),(14,.2,.48),LIME)
# the rear parapet open over the two drains (x +-3, 0.3 wide)
for a,b in [(-7,-3.15),(-2.85,2.85),(3.15,7)]:
    box('rear parapet',((a+b)/2,3.9,3.94),(b-a,.2,.48),LIME)
# Drainage: two channels through rear parapet with outside outlets.
for x in (-3.0,3.0):
    roof_piece('drain base',x-.15,x+.15,3.6,4.3,3.8,.06,STONE)
    for dx in (-.14,.14):roof_piece('drain cheek',x+dx-.03,x+dx+.03,3.6,4.3,3.92,.12,STONE)
# Supported timber shade at entry (front, max 1.2 m projection).
for x in (-1.4,1.4):
    box('canopy footing',(x,-5.05,.10),(.24,.24,.2),STONE)
    box('canopy post',(x,-5.05,1.4),(.14,.14,2.4),WOOD)
    C.beam('canopy rafter',(x,-4.0,2.95),(x,-5.12,2.62),.12,.12,WOOD)
slab('entry shade',[(-1.6,-4.0,2.96),(1.6,-4.0,2.96),(1.6,-5.14,2.62),(-1.6,-5.14,2.62)],.03,CLOTH)
# Stables (x -6.6..-3.1): hitching rail and posts, water troughs, hay.
box('hitching rail',(-4.8,2.6,1.0),(3.0,.1,.1),WOOD)
for x in (-6.2,-3.4):
    box('hitching post',(x,2.6,.55),(.12,.12,1.1),WOOD)
box('trough',(-5.6,3.25,.3),(1.6,.5,.6),STONE)
box('trough',(-3.9,3.25,.3),(1.2,.5,.6),STONE)
box('hay',(-6.2,-.5,.4),(.7,1.4,.8),HAY,False)
box('hay',(-6.2,.9,.3),(.7,1.2,.6),HAY,False)
# Common room (x -2.9..2.9): hearth at the rear wall, low table, floor cushions, jars.
box('hearth',(0,3.2,.25),(1.4,.7,.5),STONE)
box('hearth hood',(0,3.4,2.2),(1.2,.4,1.6),LIME)
box('low table',(0,.6,.3),(1.6,.9,.08),WOOD)
for dx in (-.7,.7):
    for dy in (-.35,.35):
        box('low table leg',(dx,.6+dy,.13),(.08,.08,.26),WOOD,False)
for x,y in ((-1.2,.6),(1.2,.6),(0,-.2),(0,1.4)):
    box('floor cushion',(x,y,.08),(.6,.6,.16),RUG,False)
for y in (2.6,3.1):
    ring_solid('jar',-2.6,y,(.3)-0.300,[(0.000,0.093,0.093),(0.180,0.150,0.150),(0.372,0.138,0.138),(0.480,0.075,0.075),(0.552,0.068,0.068),(0.600,0.087,0.087)],CLAY)
# Sleeping room (x 3.1..6.6): three mats and a chest.
for y in (-2.6,-.9,.8):
    box('sleeping mat',(5.4,y,.06),(2.0,1.2,.12),RUG,False)
box('chest',(6.2,2.8,.3),(.6,.9,.6),WOOD)
# Door: EntryPortal, front hinge, open -100 deg.
door_parts=[]
portal=bpy.data.objects.new('EntryPortal',None);C.ASSET.objects.link(portal)
hinge=bpy.data.objects.new('EntryPortal_entry_hinge',None);C.ASSET.objects.link(hinge)
hinge.parent=portal;hinge.location=(-.9,-3.8,0);hinge['open_angle_degrees']=-100
for k in range(5):
    part=box('Door plank',(-.7+k*.35,-3.8,1.18),(.35,.08,2.36),WOOD,False)
    part.parent=hinge;part.location-=Vector((-.9,-3.8,0))
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
asset=OUT/'d_caravanserai_14x8.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
tints={'DK lime':(.80,.70,.54),'DK stone':(.72,.63,.49),'DK timber':(.33,.24,.16)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_caravanserai_14x8.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; Codex export and Godot review pending','walls':[14,8],'maximum_height':4.2,'rooms':['stable','common room','sleeping room'],'triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'entry_hinge':'EntryPortal_entry_hinge at (-0.9,-3.8,0), open -100 deg','stable_arch':'open, x -6.2..-3.8, height 2.6','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
