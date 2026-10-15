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
# The climb (Codex 298: on the former 0.207 m treads - a 42 deg stair - the adult capsule, radius 0.28,
# had no room to land on the next step and stopped at the second flight): a stair winding up round the
# four walls over an open well - eight steps of 0.325 x 0.1875 (30 deg) along each wall, a 0.9 m landing
# in each corner; 14 sides (1.5 m each) climb the 21 m to the roof, arriving at its north-east corner.
# Each turn passes 6 m over the one below. The well x/y -1.3..1.3 stays open.
box('floor',(0,0,.05),(4.4,4.4,.1),STONE)
SIDES=[('W',(-1.75,-1.3),(-1.75,1.3)),('N',(-1.3,1.75),(1.3,1.75)),('E',(1.75,1.3),(1.75,-1.3)),('S',(1.3,-1.75),(-1.3,-1.75))]
CORNER={'W':(-1.75,1.75),'N':(1.75,1.75),'E':(1.75,-1.75),'S':(-1.75,-1.75)}
z=0.0
for side in range(14):
    name,(x0,y0),(x1,y1)=SIDES[side%4]
    for i in range(8):
        t=(i+.5)/8
        top=z+.1875*(i+1)
        cx,cy=x0+(x1-x0)*t,y0+(y1-y0)*t
        size=(.9,.325,.1875) if name in ('W','E') else (.325,.9,.1875)
        box('stair',(cx,cy,top-.094),size,STONE)
        # the step's stone under it, 1.2 m deep (it stays 3.3 m over the entry passage below the south side)
        box('stair body',(cx,cy,top-.1875-.6),(size[0],size[1],1.2),STONE,False)
    z+=1.5
    lx,ly=CORNER[name]
    box('landing',(lx,ly,z-.1),(.9,.9,.2),STONE)
    box('landing body',(lx,ly,z-.2-.6),(.9,.9,1.2),STONE,False)
# Railings (Codex 303): iron, 0.9 m, on the inner edge of every flight over the open well (rail 0.06 thick
# on the 0.9 m tread leaves 0.84 m clear); posts on every second step, a hand rail and a mid rail. The
# collision is the same rail as a stepped 0.06 panel per step (a visible support, no invisible wall).
# Under the roof slab (underside 20.8) the rail stops where the gap to the slab closes. The landings
# touch the well only at their inner corner, where two flights' rails meet on one post.
GLASS=C.mat('DF lamp glass',(1.0,.72,.38,1),.4)
ROOF_UNDER=20.8
INNER={'W':('x',-1.33),'N':('y',1.33),'E':('x',1.33),'S':('y',-1.33)}
def at_edge(name,u):
    axis,c=INNER[name]
    return (c,u) if axis=='x' else (u,c)
z=0.0
for side in range(14):
    name,(x0,y0),(x1,y1)=SIDES[side%4]
    u0,u1=(y0,y1) if name in ('W','E') else (x0,x1)
    def rail_top(top):
        return min(top+.9,ROOF_UNDER-.05) if side>=12 else top+.9
    for i in range(8):
        t0,t1=i/8,(i+1)/8;top=z+.1875*(i+1)
        h=rail_top(top)-top
        if h<.3:continue
        ua,ub=u0+(u1-u0)*t0,u0+(u1-u0)*t1
        px,py=at_edge(name,(ua+ub)/2)
        size=(.06,abs(ub-ua),h) if name in ('W','E') else (abs(ub-ua),.06,h)
        coll.append(('rail',(px,py,top+h/2),size))
    posts=[]
    for i in range(0,9,2):
        top=z+.1875*min(max(i,1),8)  # the step top under a post (the first stands on step 1)
        h=rail_top(top)-top
        if h<.3:break
        u=u0+(u1-u0)*(i/8)
        posts.append((at_edge(name,u),top,h))
        px,py=at_edge(name,u)
        C.box('rail post',(px,py,top+h/2),(.045,.045,h),IRON,0)
    for (pa,ta,ha),(pb,tb,hb) in zip(posts,posts[1:]):
        C.beam('hand rail',Vector((pa[0],pa[1],ta+ha)),Vector((pb[0],pb[1],tb+hb)),.05,.05,IRON)
        C.beam('mid rail',Vector((pa[0],pa[1],ta+ha*.5)),Vector((pb[0],pb[1],tb+hb*.5)),.035,.035,IRON)
    z+=1.5
# Lamps (Codex 303): TowerLamp_00..13, one over the middle of each flight by the outer wall, 2.0 m over
# the tread there; an iron bracket out of the wall (0.15 m) and a small lantern under it. The empty sits
# at the lantern's centre for the runtime light. Flight 13 rises above the wall top (21): its lamp hangs
# from an iron post standing on the parapet instead.
LAMP={'W':(-2.05,0),'N':(0,2.05),'E':(2.05,0),'S':(0,-2.05)}
WALL={'W':(-2.2,0),'N':(0,2.2),'E':(2.2,0),'S':(0,-2.2)}
for k in range(14):
    name=SIDES[k%4][0];lx,ly=LAMP[name];wx,wy=WALL[name]
    lz=1.5*k+.75+2.0
    C.box('lamp body',(lx,ly,lz),(.16,.16,.26),IRON,0)
    C.box('lamp glass',(lx,ly,lz),(.18,.18,.17),GLASS,0)
    C.box('lamp cap',(lx,ly,lz+.16),(.22,.22,.05),IRON,0)
    if lz+.2<21.0:
        C.beam('lamp bracket',Vector((wx,wy,lz+.2)),Vector((lx,ly,lz+.2)),.05,.05,IRON)
        C.beam('lamp bracket',Vector((wx,wy,lz-.15)),Vector(((wx+lx)/2,(wy+ly)/2,lz+.2)),.035,.035,IRON)
    else:
        # on the parapet (2.5..2.8), in the gap between the merlons at 0 and 1.1 along the wall
        px,py=(wx*1.18+(.55 if name in ('N','S') else 0),wy*1.18+(.55 if name in ('W','E') else 0))
        top=lz+.45
        C.box('lamp post',(px,py,(21.8+top)/2),(.07,.07,top-21.8),IRON,0)
        C.beam('lamp bracket',Vector((px,py,top)),Vector((lx,ly,top)),.05,.05,IRON)
        C.box('lamp chain',(lx,ly,(lz+.18+top)/2),(.02,.02,top-lz-.18),IRON,0)
    e=bpy.data.objects.new('TowerLamp_%02d'%k,None);e.location=(lx,ly,lz);C.ASSET.objects.link(e)
# the roof at 21 m, open over the last two sides (the west and north bands) so the climb keeps its
# headroom under it: x -1.3..2.2, y -2.2..1.3
box('roof floor',(.45,-.45,20.9),(3.5,3.5,.2),STONE)
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
box('brazier plinth',(0,-.6,21.4),(1.4,1.4,.8),STONE)
for dx in (-.42,.42):
    for dy in (-.42,.42):
        box('brazier post',(dx,-.6+dy,22.3),(.08,.08,1.0),IRON)
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
ring_solid('brazier bowl',0,-.6,21.8,[(0,.35,.35),(.25,.6,.6),(.45,.68,.68)],IRON,False)
ring_solid('flame',0,-.6,22.2,[(0,.45,.45),(.35,.32,.32),(.75,.12,.12),(.95,.02,.02)],FIRE,False)
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
(QA/'stats.json').write_text(json.dumps({'state':'built; Codex export and Godot review pending','walls':[7,7],'maximum_height':23.2,'rooms':['stair well','roof platform'],'height_note':'measured 23.2 m to the merlons; the concept\'s 25 m was provisional','triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'entry_hinge':'EntryPortal_entry_hinge at (-0.6,-2.5,0), open -100 deg','stairs':'winding round the four walls over an open well: 14 sides x 8 steps 0.325 x 0.1875, corner landings 0.9, arriving at the roof NE','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
