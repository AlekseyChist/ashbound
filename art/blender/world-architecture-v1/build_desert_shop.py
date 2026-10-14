"""Desert plot lb1: stalls at the cathedral square, 6x5 m; canonical GLB source.
Door front-left (opening x -2.0..-0.4); shop window to the street on the right
(x 0.3..2.3, sill 0.9, head 2.1) with a hinged shutter awning; counter under the
window, goods shelves along the rear wall, a chest; aisle from door along the
facade to the counter."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/qa/desert-shop';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DL stone','stone_wall_02_diff_1k.jpg',2)
LIME=surface('DL lime','plaster_grey_04_diff_1k.jpg',2)
WOOD=surface('DL timber','fine_grained_wood_col_1k.jpg',.65)
CLOTH=C.mat('DL shade',(.36,.30,.20,1),.98)
CLAY=C.mat('DL clay',(.60,.38,.24,1),.9)
CLOTH2=C.mat('DL cloth bolts',(.30,.36,.42,1),.98)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('counter','shelf','jar','bolt','chest')):
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
# Shell: outer walls 6x5 (faces at x +-3, y +-2.5; inner faces +-2.6 / +-2.1), floor z=0, roof top ~3.6.
box('foundation',(0,0,-.15),(6,5,.3),STONE)
box('entry porch',(-1.2,-3.1,-.12),(2.4,1.2,.24),STONE)
# Front wall (y=-2.3) in pieces: door opening x -2.0..-0.4, window x 0.3..2.3 (sill 0.9, head 2.1).
box('front wall',(-2.5,-2.3,1.6),(1.0,.4,3.2),LIME)   # x -3.0..-2.0
box('door header',(-1.2,-2.3,2.75),(1.6,.4,.9),LIME)
box('front wall',(-.05,-2.3,1.6),(.7,.4,3.2),LIME)    # x -0.4..0.3
box('front wall',(1.3,-2.3,.45),(2.0,.4,.9),LIME)     # under window, z 0..0.9
box('front wall',(1.3,-2.3,2.65),(2.0,.4,1.1),LIME)   # over window, z 2.1..3.2
box('front wall',(2.65,-2.3,1.6),(.7,.4,3.2),LIME)    # x 2.3..3.0
box('window sill',(1.3,-2.62,.92),(2.1,.3,.06),WOOD)  # counter board outside under the window
# Hinged shutter awning over the window, folded out to the street on two props.
for x in (0.3,2.3):
    C.beam('shutter prop',(x,-2.5,2.12),(x,-3.2,2.5),.06,.06,WOOD)
slab('shutter board',[(0.25,-2.5,2.14),(2.35,-2.5,2.14),(2.35,-3.2,2.52),(0.25,-3.2,2.52)],.03,WOOD)
# Rear and side walls solid.
box('rear wall',(0,2.3,1.6),(6,.4,3.2),LIME)
for x in (-2.8,2.8):box('side wall',(x,0,1.6),(.4,4.2,3.2),LIME)
# Ceiling and roof (slight slope via mesh).
FACES=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
def roof_piece(name,x0,x1,y0,y1,top,thick,material):
    vertices=[(x,y,top-y*.012+dz) for x in (x0,x1) for y in (y0,y1) for dz in (-thick,0)]
    return C.mesh(name,vertices,FACES,material)
box('ceiling',(0,0,3.12),(6,5,.16),WOOD)
roof_piece('flat lime roof',-3.3,3.3,-2.8,2.8,3.6,.15,LIME)
roof_piece('flat roof-colonly',-3.3,3.3,-2.8,2.8,3.6,.15,LIME).hide_render=True
# Parapet (eaves max 0.3 beyond walls); rear parapet open over the drain at x=0.
for x in (-2.9,2.9):box('side parapet',(x,0,3.74),(.2,5.0,.48),LIME)
box('front parapet',(0,-2.4,3.74),(6,.2,.48),LIME)
for a,b in [(-3,-.15),(.15,3)]:
    box('rear parapet',((a+b)/2,2.4,3.74),(b-a,.2,.48),LIME)
# Drainage: one channel through the rear parapet with an outside outlet.
roof_piece('drain base',-.15,.15,2.1,2.8,3.6,.06,STONE)
for dx in (-.14,.14):roof_piece('drain cheek',dx-.03,dx+.03,2.1,2.8,3.72,.12,STONE)
# Supported timber shade at entry (front-left, over the door).
for x in (-2.2,-.2):
    box('canopy footing',(x,-3.55,.10),(.24,.24,.2),STONE)
    box('canopy post',(x,-3.55,1.4),(.14,.14,2.4),WOOD)
    C.beam('canopy rafter',(x,-2.5,2.95),(x,-3.62,2.62),.12,.12,WOOD)
slab('entry shade',[(-2.4,-2.5,2.96),(0,-2.5,2.96),(0,-3.64,2.62),(-2.4,-3.64,2.62)],.03,CLOTH)
# Interior: counter under the window with jars on top.
box('counter top',(1.3,-1.55,.92),(2.0,.55,.08),WOOD)
box('counter front',(1.3,-1.28,.46),(2.0,.04,.88),WOOD)
for x in (.35,2.25):box('counter leg',(x,-1.75,.44),(.07,.07,.88),WOOD,False)
for x in (.7,1.3,1.9):ring_solid('jar',x,-1.55,(1.09)-0.130,[(0.000,0.068,0.068),(0.078,0.110,0.110),(0.161,0.101,0.101),(0.208,0.055,0.055),(0.239,0.050,0.050),(0.260,0.064,0.064)],CLAY)
# Goods shelves along the rear wall: back panel, sides, four boards; jars and cloth bolts.
box('shelf back',(0,2.05,1.0),(4.4,.06,2.0),WOOD)
for x in (-2.2,2.2):box('shelf side',(x,1.85,1.0),(.08,.4,2.0),WOOD)
for z in (.06,.7,1.34,1.96):box('shelf board',(0,1.85,z),(4.4,.4,.08),WOOD)
for z in (.7,1.34):
    for x in (-1.6,-.8,0,.8,1.6):ring_solid('jar',x,1.85,(z+.17)-0.130,[(0.000,0.074,0.074),(0.078,0.120,0.120),(0.161,0.110,0.110),(0.208,0.060,0.060),(0.239,0.054,0.054),(0.260,0.070,0.070)],CLAY)
for x in (-1.5,-.5,.5,1.5):box('bolt',(x,1.85,1.96+.14),(.7,.25,.2),CLOTH2,False)
# Chest near the door side.
box('chest',(-2.1,.4,.3),(.6,.9,.6),WOOD)
# Door: EntryPortal, front-left hinge, open -100 deg.
door_parts=[]
portal=bpy.data.objects.new('EntryPortal',None);C.ASSET.objects.link(portal)
hinge=bpy.data.objects.new('EntryPortal_entry_hinge',None);C.ASSET.objects.link(hinge)
hinge.parent=portal;hinge.location=(-2.0,-2.3,0);hinge['open_angle_degrees']=-100
for k in range(5):
    part=box('Door plank',(-1.82+k*.31,-2.3,1.18),(.30,.08,2.36),WOOD,False)
    part.parent=hinge;part.location-=Vector((-2.0,-2.3,0))
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
asset=OUT/'d_shop_6x5.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
tints={'DL lime':(.80,.70,.54),'DL stone':(.72,.63,.49),'DL timber':(.33,.24,.16)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_shop_6x5.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; Codex export and Godot review pending','walls':[6,5],'maximum_height':4.0,'rooms':['shop'],'triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'entry_hinge':'EntryPortal_entry_hinge at (-2.0,-2.3,0), open -100 deg','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
