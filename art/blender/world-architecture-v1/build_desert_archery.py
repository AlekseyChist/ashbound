"""Desert plot Lk: longbow archery range, 8x5 m; canonical GLB source.

Open-front shooting pavilion (front facade -y opens onto the target field;
targets and the field itself are placed by the city, not part of this model).
Three stone piers carry a front beam over the open side; the shooting line is
the floor edge at y=-2.3. Inside: bow racks with standing bows and quivers
against the rear wall, benches along the side walls, straw bales for spare
targets in the right front corner. No door, no EntryPortal.
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
QA=ROOT/'local/qa/desert-archery';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DA stone','stone_wall_02_diff_1k.jpg',2)
LIME=surface('DA lime','plaster_grey_04_diff_1k.jpg',2)
WOOD=surface('DA timber','fine_grained_wood_col_1k.jpg',.65)
STRAW=C.mat('DA straw',(.72,.62,.38,1),.98)
LEATHER=C.mat('DA leather',(.36,.22,.14,1),.9)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('bow rack','bow','quiver','bench','straw bale')):
        o['part_role']='interior_furniture'
    if solid:coll.append((n,p,s))
    return o
# Shell: outer walls 8x5 (faces at x +-4, y +-2.5; inner faces +-3.6 / +-2.1), floor z=0, roof top ~3.6.
box('foundation',(0,0,-.15),(8,5,.3),STONE)
# Shooting line: stone threshold across the open front side at y=-2.38.
box('shooting line',(0,-2.38,.03),(7.2,.24,.06),STONE)
# Rear wall (y=+2.5 face, centred 2.3).
box('rear wall',(0,2.3,1.6),(8,.4,3.2),LIME)
# Side walls (x=+-4 faces, centred +-3.8).
for x in (-3.8,3.8):
    box('side wall',(x,0,1.6),(.4,4.2,3.2),LIME)
# Open front side: three stone piers (0.3x0.3) at y=-2.3 under a lintel beam.
for x in (-2.0,0.0,2.0):
    box('front pier',(x,-2.3,1.6),(.3,.3,3.2),STONE)
box('front beam',(0,-2.3,3.0),(8,.4,.4),LIME)
# Ceiling and roof (slight slope via mesh).
FACES=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
def roof_piece(name,x0,x1,y0,y1,top,thick,material):
    vertices=[(x,y,top-y*.012+dz) for x in (x0,x1) for y in (y0,y1) for dz in (-thick,0)]
    return C.mesh(name,vertices,FACES,material)
box('ceiling',(0,0,3.12),(8,5,.16),WOOD)
roof_piece('flat lime roof',-4.3,4.3,-2.8,2.8,3.6,.15,LIME)
roof_piece('flat roof-colonly',-4.3,4.3,-2.8,2.8,3.6,.15,LIME).hide_render=True
# Parapet (eaves max 0.3 beyond walls).
for x in (-3.9,3.9):box('side parapet',(x,0,3.74),(.2,5.0,.48),LIME)
box('front parapet',(0,-2.4,3.74),(8,.2,.48),LIME)
# Rear parapet open over the drain at x=0 (0.3 wide; Codex 2fceb2a: it ran on over them).
for a,b in [(-4,-.15),(.15,4)]:
    box('rear parapet',((a+b)/2,2.4,3.74),(b-a,.2,.48),LIME)
# Drainage: one channel through the rear parapet with an outside outlet.
roof_piece('drain base',-.15,.15,2.1,2.8,3.6,.06,STONE)
for dx in (-.14,.14):roof_piece('drain cheek',dx-.03,dx+.03,2.1,2.8,3.72,.12,STONE)
# Interior (floor z=0; inner faces x +-3.6, y to 2.1).
# Two bow racks against the rear wall with standing bows.
for x in (-2.4,2.4):
    box('bow rack',(x,1.95,1.1),(1.6,.1,.08),WOOD)
    box('bow rack',(x,1.95,1.6),(1.6,.1,.08),WOOD)
    for dx in (-.75,.75):box('bow rack post',(x+dx,1.95,.9),(.08,.08,1.8),WOOD)
    for dx in (-.5,-.17,.17,.5):box('bow',(x+dx,1.85,1.0),(.04,.04,1.9),WOOD,False)
# Quivers with arrows along the middle of the rear wall.
for x in (-.6,-.2,.2,.6):
    box('quiver',(x,1.9,.45),(.18,.18,.9),LEATHER,False)
# Two benches along the side walls.
for x in (-3.2,3.2):
    box('bench',(x,.2,.24),(.4,2.2,.06),WOOD)
    for y in (-.7,1.1):box('bench leg',(x,y,.1),(.3,.08,.2),WOOD,False)
# Straw bales for spare targets in the right front corner.
box('straw bale',(3.1,-1.6,.3),(.8,.6,.6),STRAW)
box('straw bale',(3.1,-1.6,.9),(.8,.6,.6),STRAW)
# No door: open front between the three piers.
door_parts=[]
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
asset=OUT/'d_archery_8x5.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
tints={'DA lime':(.80,.70,.54),'DA stone':(.72,.63,.49),'DA timber':(.33,.24,.16)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_archery_8x5.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; Codex export and Godot review pending','walls':[8,5],'maximum_height':4.0,'rooms':['range pavilion'],'triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'entry':'open front -y between three piers; shooting line at y -2.38; targets placed by the city','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
