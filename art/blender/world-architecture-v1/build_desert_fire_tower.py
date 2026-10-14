"""Desert plot B: the Eternal Fire Tower, 7x7 m footprint (buttresses included);
entry from the south (-y). Four tiers of 5.25 m each; every tier carries two
flights (along the west wall northward, then back south) with a landing at the
north wall; roof platform at z=21 with crenellated parapet and an iron brazier.
The flame is a static model only, no mechanics. Canonical GLB source."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/qa/desert-fire-tower';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DF stone','stone_wall_02_diff_1k.jpg',2)
WOOD=surface('DF timber','fine_grained_wood_col_1k.jpg',.65)
IRON=C.mat('DF iron',(.16,.15,.14,1),.45,.6)
DARK=C.mat('DF window',(.06,.05,.05,1),.9)
CLOTH=C.mat('DF banner',(.45,.10,.08,1),.98)
FIRE=C.mat('DF flame',(1.0,.55,.15,1),.6)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('banner',)):
        o['part_role']='interior_furniture'
    if solid:coll.append((n,p,s))
    return o
def lancet(n,cx,cy,z,axis,sign,w,h,depth,m,lift=0.0):
    # a pointed (Gothic) window shape on a wall face: base width w at height z, straight sides up to z+h,
    # a pointed head 0.5 m over that; a flat solid `depth` thick standing out of the face by `lift`
    pts=[(-w/2,0),(w/2,0),(w/2,h),(w/4,h+.36),(0,h+.5),(-w/4,h+.36),(-w/2,h)]
    def at(u,v,d):
        return (cx+u,cy+sign*d,z+v) if axis=='y' else (cx+sign*d,cy+u,z+v)
    k=len(pts)
    v=[at(u,vv,lift) for u,vv in pts]+[at(u,vv,lift+depth) for u,vv in pts]
    f=[tuple(range(k)),tuple(range(2*k-1,k-1,-1))]
    for i in range(k):
        j=(i+1)%k
        f.append((i,j,k+j,k+i))
    return C.mesh(n,v,f,m)
# Tower shaft: outer faces x +-2.8, y +-2.8; wall thickness 0.6 (inner faces +-2.2), height 0..21.
box('foundation',(0,0,-.2),(7,7,.4),STONE)
box('wall',(-2.5,0,10.5),(.6,5.6,21),STONE)
box('wall',(2.5,0,10.5),(.6,5.6,21),STONE)
box('wall',(0,2.5,10.5),(4.4,.6,21),STONE)
# South wall with door opening x -0.6..0.6, head 2.4.
box('wall',(-1.7,-2.5,10.5),(2.2,.6,21),STONE)
box('wall',(1.7,-2.5,10.5),(2.2,.6,21),STONE)
box('door head',(0,-2.5,11.7),(1.2,.6,18.6),STONE)
box('entry step',(0,-3.1,.08),(1.8,.6,.16),STONE)
# Corner buttresses: two per corner, stepping down in width.
for sx in (-1,1):
    for sy in (-1,1):
        for z0,z1,t in ((0,8,.6),(8,15,.45),(15,20,.3)):
            box('buttress',(sx*(2.8+t/2),sy*2.55,(z0+z1)/2),(t,.7,z1-z0),STONE)
            box('buttress',(sx*2.55,sy*(2.8+t/2),(z0+z1)/2),(.7,t,z1-z0),STONE)
# Tiers: floor levels z = 0, 5.25, 10.5, 15.75 and roof platform 21.0.
# Stair opening in each upper floor: x -2.2..-0.4, y -1.6..2.2.
box('floor',(0,0,.05),(4.4,4.4,.1),STONE)
for z in (5.25,10.5,15.75,21.0):
    box('floor',(.9,0,z-.1),(2.6,4.4,.2),STONE)
    box('floor',(-1.3,-1.9,z-.1),(1.8,.6,.2),STONE)
# Flights on each tier k (floor zk = 5.25*k): 14 risers of 0.1875 m.
for k in range(4):
    zk=5.25*k
    for i in range(14):
        box('stair',(-1.75,-1.6+.207*i+.1035,zk+.1875*(i+1)-.094),(.9,.207,.1875),STONE)
    box('landing',(-1.3,1.75,zk+2.625-.1),(1.8,.9,.2),STONE)
    for i in range(14):
        box('stair',(-.85,1.3-.207*i-.1035,zk+2.625+.1875*(i+1)-.094),(.9,.207,.1875),STONE)
    box('stair wall',(-1.3,-.15,zk+2.6),(.12,2.9,5.2),STONE)
# Windows: dark pointed niches on three tiers of every face.
for z in (6.5,11.8,17.0):
    for axis,sign,cx,cy in (('y',-1,0,-2.8),('y',1,0,2.8),('x',-1,-2.8,0),('x',1,2.8,0)):
        lancet('window reveal',cx,cy,z-.85,axis,sign,.84,1.6,.06,STONE,0.0)
        lancet('window',cx,cy,z-.75,axis,sign,.6,1.45,.04,DARK,.06)
# Parapet with merlons around the roof platform.
box('parapet',(0,-2.65,21.4),(5.6,.3,.8),STONE)
box('parapet',(0,2.65,21.4),(5.6,.3,.8),STONE)
box('parapet',(-2.65,0,21.4),(.3,5.0,.8),STONE)
box('parapet',(2.65,0,21.4),(.3,5.0,.8),STONE)
for k in range(-2,3):
    for x,y in ((k*1.1,-2.65),(k*1.1,2.65)):
        box('merlon',(x,y,22.0),(.45,.3,.4),STONE)
    for x,y in ((-2.65,k*1.1),(2.65,k*1.1)):
        box('merlon',(x,y,22.0),(.3,.45,.4),STONE)
# Brazier: plinth outside the stair opening; four iron posts; bowl and flame.
box('brazier plinth',(1.0,.6,21.4),(1.4,1.4,.8),STONE)
for dx in (-.42,.42):
    for dy in (-.42,.42):
        box('brazier post',(1.0+dx,.6+dy,22.3),(.08,.08,1.0),IRON)
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
ring_solid('brazier bowl',1.0,.6,21.8,[(0,.35,.35),(.25,.6,.6),(.45,.68,.68)],IRON,False)
ring_solid('flame',1.0,.6,22.2,[(0,.45,.45),(.35,.32,.32),(.75,.12,.12),(.95,.02,.02)],FIRE,False)
# Order banners on the south face.
for x in (-1.6,1.6):
    box('banner',(x,-2.86,13.5),(.9,.04,4.0),CLOTH,False)
# Door: EntryPortal, front hinge, open -100 deg.
door_parts=[]
portal=bpy.data.objects.new('EntryPortal',None);C.ASSET.objects.link(portal)
hinge=bpy.data.objects.new('EntryPortal_entry_hinge',None);C.ASSET.objects.link(hinge)
hinge.parent=portal;hinge.location=(-.6,-2.5,0);hinge['open_angle_degrees']=-100
for k in range(4):
    part=box('Door plank',(-.45+k*.3,-2.5,1.18),(.28,.08,2.36),WOOD,False)
    part.parent=hinge;part.location-=Vector((-.6,-2.5,0))
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
asset=OUT/'d_fire_tower.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
tints={'DF stone':(.74,.66,.52),'DF timber':(.33,.24,.16)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_fire_tower.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; Codex export and Godot review pending','walls':[7,7],'maximum_height':23.2,'rooms':['tier 0','tier 1','tier 2','tier 3','roof platform'],'height_note':'measured 23.2 m to the merlons; the concept\'s 25 m was provisional','triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'entry_hinge':'EntryPortal_entry_hinge at (-0.6,-2.5,0), open -100 deg','stairs':'per tier 2x14 risers 0.1875, flights x -2.2..-1.3 north and x -1.3..-0.4 south','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
