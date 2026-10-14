"""Desert plot C: ruined cathedral — Order sanctuary, 30x18 m footprint with buttresses; canonical GLB source.

Ancient kingdom masonry adapted by the Order. Three naves running south to north,
north sanctuary with altar and fire basin, pews, closed east library room with a
service hatch to the cisterns. No statues. The north-east roof is lost (open to
the sky) and the east wall is broken in stepped heights 8.5..13 m.

Blender axes: z up; entry on the south (-y); east is +x.
Dimensions: walls 1.0 thick (outer faces x +-14.4, y +-8.4), wall height 13,
ridge 18; buttresses out to x +-15, y +-9; entry opening x -1..1, height 3.
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
QA=ROOT/'local/qa/desert-cathedral';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DC stone','stone_wall_02_diff_1k.jpg',2)
WOOD=surface('DC timber','fine_grained_wood_col_1k.jpg',.65)
ROOF=C.mat('DC roof',(.30,.24,.20,1),.9)
DARK=C.mat('DC window',(.06,.05,.05,1),.9)
CLOTH=C.mat('DC banner',(.45,.10,.08,1),.98)
IRON=C.mat('DC iron',(.16,.15,.14,1),.45,.6)
FIRE=C.mat('DC flame',(1.0,.55,.15,1),.6)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('pew','altar','fire basin','shelf','book','lectern','banner','hatch')):
        o['part_role']='interior_furniture'
    if solid:coll.append((n,p,s))
    return o
def ring_solid(n,x,y,z,rings,m,role=True):
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
def roof_slope(n,xa,xb,y0,y1,za,zb,t,m):
    # a sloped slab from the line x=xa (height za) to x=xb (height zb), y0..y1, thickness t
    v=[(xa,y0,za-t),(xb,y0,zb-t),(xb,y1,zb-t),(xa,y1,za-t),(xa,y0,za),(xb,y0,zb),(xb,y1,zb),(xa,y1,za)]
    f=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    return C.mesh(n,v,f,m)
# Foundation and floor.
box('foundation',(0,0,-.2),(30,18,.4),STONE)
box('floor',(0,0,.05),(28.8,16.8,.1),STONE)
# Walls (thickness 1.0; centre lines x +-13.9, y +-7.9).
box('wall',(0,7.9,6.5),(28.8,1.0,13),STONE)                      # north, intact
box('wall',(-13.9,0,6.5),(1.0,14.8,13),STONE)                    # west, intact
# South wall with portal x -1..1 (height 3).
box('wall',(-7.7,-7.9,6.5),(13.4,1.0,13),STONE)
box('wall',(7.7,-7.9,6.5),(13.4,1.0,13),STONE)
box('portal head',(0,-7.9,8.0),(2.0,1.0,10.0),STONE)
# East wall — ruined, broken in stepped heights (pieces y -7.5..7.5, 3 m each).
for y,h in ((-6,13),(-3,10.5),(0,8.5),(3,10),(6,12)):
    box('wall',(13.9,y,h/2),(1.0,3.0,h),STONE)
# Buttresses outside the long walls, between windows.
for x in (-10,-5,5,10):
    for sy in (-1,1):
        box('buttress',(x,sy*8.7,4.0),(1.0,.6,8.0),STONE)
        box('buttress',(x,sy*8.7,9.0),(.8,.6,2.0),STONE)
for y in (-4,4):
    box('buttress',(-14.7,y,4.0),(.6,1.0,8.0),STONE)
# Windows — dark tall niches on the outer faces.
for x in (-11,-7.5,7.5,11):
    box('window',(x,8.42,7.5),(1.2,.06,4.0),DARK,False)          # north
    box('window',(x,-8.42,7.5),(1.2,.06,4.0),DARK,False)         # south
for y in (-4,0,4):
    box('window',(-14.42,y,7.5),(.06,1.2,4.0),DARK,False)        # west
box('window',(0,-8.42,9.5),(3.0,.06,3.0),DARK,False)             # rose over the portal
# Arcades: piers between naves at x +-5, longitudinal arcade beams on top.
for x in (-5,5):
    for y in (-5,-1.5,2,5.5):
        box('pier',(x,y,5.5),(1.0,1.0,11),STONE)
    box('arcade beam',(x,0,11.3),(1.0,14.8,.6),STONE)
# Roof (only the western part survives to x=4; north-east is open to the sky).
roof_slope('nave roof',-5.6,0,-8.4,4.0,13.0,18.0,.3,ROOF)
roof_slope('nave roof',5.6,0,-8.4,4.0,13.0,18.0,.3,ROOF)
roof_slope('aisle roof',-14.4,-5.4,-8.4,8.4,9.0,11.6,.25,ROOF)   # whole west aisle
roof_slope('aisle roof',14.4,5.4,-8.4,0.0,9.0,11.6,.25,ROOF)     # east aisle, south half only
for x in (-5,5):
    box('clerestory',(x,-2.2,12.3),(1.0,12.4,1.4),STONE)
for x in (-3,0,3):
    C.beam('broken rafter',(x,4.0,15.0),(x,6.5,13.2),.25,.25,WOOD)
# North sanctuary (y 4.5..7.4, central nave).
box('sanctuary dais',(0,6.0,.25),(9.6,2.8,.4),STONE)
box('dais step',(0,4.45,.1),(4.0,.3,.2),STONE)
box('altar',(0,6.6,.95),(2.2,.9,1.0),STONE)
ring_solid('fire basin',2.6,6.3,.45,[(0,.25,.25),(.6,.2,.2),(.7,.5,.5),(.9,.55,.55)],IRON)
ring_solid('fire basin flame',2.6,6.3,1.3,[(0,.38,.38),(.3,.25,.25),(.6,.08,.08),(.75,.02,.02)],FIRE,True)
for x in (-3.5,3.5):
    box('banner',(x,7.36,7.0),(1.2,.04,4.5),CLOTH,False)
# Pews in the central nave: two rows either side of the aisle x -0.9..0.9.
for x in (-2.7,2.7):
    for y in (-5.0,-3.6,-2.2,-.8,.6,2.0):
        box('pew',(x,y,.45),(3.4,.45,.08),WOOD)
        box('pew back',(x,y+.25,.8),(3.4,.06,.7),WOOD,False)
        for dx in (-1.5,1.5):
            box('pew leg',(x+dx,y,.22),(.08,.4,.44),WOOD,False)
# East library room in the east aisle (x 6.0..13.4, y 1.0..7.4).
box('library wall',(7.6,1.0,2.5),(3.2,.3,5.0),STONE)             # south, west of door x 9.2..10.2
box('library wall',(11.8,1.0,2.5),(3.2,.3,5.0),STONE)           # south, east of door
box('library wall',(9.7,1.0,3.7),(1.0,.3,2.6),STONE)            # header over the door z 2.4..5.0
box('library wall',(6.0,4.2,2.5),(.3,6.4,5.0),STONE)            # west partition y 1.0..7.4
box('library door',(9.7,1.0,1.2),(1.0,.1,2.4),WOOD)             # closed, static leaf
for y in (2.0,3.6,5.2):
    box('shelf',(13.1,y,1.3),(.4,1.4,2.6),WOOD)
    for z in (.6,1.2,1.8):
        box('book row',(13.0,y,z),(.25,1.2,.3),CLOTH,False)
box('lectern',(9.7,4.0,1.0),(.6,.5,.12),WOOD)
box('lectern post',(9.7,4.0,.5),(.12,.12,1.0),WOOD,False)
box('hatch',(11.8,6.4,.12),(1.2,1.2,.06),WOOD,False)             # service hatch to the cisterns
box('hatch ring',(11.8,6.0,.17),(.2,.04,.04),IRON,False)
# Banners outside on the south wall flanking the portal.
for x in (-4,4):
    box('banner',(x,-8.46,7.0),(1.4,.04,5.0),CLOTH,False)
# Door: EntryPortal in the main portal, hinge at the west jamb, open -100 deg.
door_parts=[]
portal=bpy.data.objects.new('EntryPortal',None);C.ASSET.objects.link(portal)
hinge=bpy.data.objects.new('EntryPortal_entry_hinge',None);C.ASSET.objects.link(hinge)
hinge.parent=portal;hinge.location=(-1.0,-7.9,0);hinge['open_angle_degrees']=-100
for k in range(6):
    part=box('Door plank',(-.83+k*.333,-7.9,1.48),(.32,.1,2.96),WOOD,False)
    part.parent=hinge;part.location-=Vector((-1.0,-7.9,0))
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
asset=OUT/'d_cathedral.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
tints={'DC stone':(.74,.66,.52),'DC timber':(.33,.24,.16)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_cathedral.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; Codex export and Godot review pending','walls':[30,18],'maximum_height':18.0,'rooms':['nave','aisles','north sanctuary','east library (closed)'],'triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'entry_hinge':'EntryPortal_entry_hinge at (-1.0,-7.9,0), open -100 deg','ruin':'north-east roof lost, east wall broken 8.5..13 m','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
