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
BALE=C.mat('DA bale straw',(.60,.48,.25,1),.98)          # warmer than the fletchings' straw: it read white
STRAW_DARK=C.mat('DA straw stalks',(.44,.33,.16,1),.98)   # the darker stalks on a bale's faces and ends
TWINE=C.mat('DA twine',(.30,.22,.13,1),.95)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('bow rack','bow','quiver','bench','straw bale')):
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
def vessel(n,x,y,z,rings,m,depth,lip=.8,role=True,k=10):
    # an OPEN vessel (Codex BZR-ART-01b/453 DS-WARES-03: mouths capped by one flat face): its rings from the
    # foot up, a rim (the top ring to an inner ring lip*its size), the inner wall down `depth`, an inner floor
    v=[]
    for dz,hx,hy in rings:
        for i in range(k):
            a=math.pi*2*i/k
            v.append((x+hx*math.cos(a),y+hy*math.sin(a),z+dz))
    tz,thx,thy=rings[-1]
    for dz,f in ((0.0,lip),(-depth,lip*.92)):
        for i in range(k):
            a=math.pi*2*i/k
            v.append((x+thx*f*math.cos(a),y+thy*f*math.sin(a),z+tz+dz))
    n_r=len(rings)+2
    faces=[tuple(range(k-1,-1,-1))]
    for r in range(n_r-1):
        for i in range(k):
            j=(i+1)%k
            faces.append((r*k+i,r*k+j,(r+1)*k+j,(r+1)*k+i))
    faces.append(tuple(range((n_r-1)*k,n_r*k)))
    o=C.mesh(n,v,faces,m)
    if role:o['part_role']='interior_furniture'
    return o
def stave(n,a,b,w,m):
    o=C.beam(n,a,b,w,w,m)
    o['part_role']='interior_furniture'
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
# 7.6 x 4.6 (Codex 477 DA-ROOF-JOINT-01: at 8 x 5 its sides lay in the walls' outer faces - a black band
# under the bond course); now its edges stop inside the walls' thickness
box('ceiling',(0,0,3.12),(7.6,4.6,.16),WOOD)
# the bond course (as the workshop's DW-ROOF-01 and the shop's DS-ROOF-01: walls, front beam and ceiling
# stopped at 3.20, the roof slab's underside at 3.45-0.012y - a 22-28 cm open belt): masonry over every
# wall line and the front beam from 3.20 up into the roof slab, its top following the slab's slope
def course(n,x0,x1,y0,y1):
    vs=[(x,y,z) for x in (x0,x1) for y in (y0,y1) for z in (3.19,3.47-y*.012)]
    return C.mesh(n,vs,FACES,LIME)
course('bond course',-4.0,4.0,-2.5,-2.1)
course('bond course',-4.0,4.0,2.1,2.5)
course('bond course',-4.0,-3.6,-2.1,2.1)
course('bond course',3.6,4.0,-2.1,2.1)
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
    # bows standing against the rack: a stave bent back in three pieces and a string
    for dx in (-.5,-.17,.17,.5):
        bx=x+dx
        pts=[(bx,1.86,.06),(bx,1.74,.55),(bx,1.70,1.0),(bx,1.74,1.45),(bx,1.86,1.94)]
        for p0,p1 in zip(pts,pts[1:]):stave('bow',p0,p1,.035,WOOD)
        stave('bow string',(bx,1.87,.08),(bx,1.87,1.92),.008,LEATHER)
# Quivers with arrows along the middle of the rear wall.
for x in (-.6,-.2,.2,.6):
    # an open leather quiver, the fletchings standing in its mouth
    vessel('quiver',x,1.9,0,[(0,.07,.07),(.06,.09,.09),(.86,.1,.1),(.9,.095,.095)],LEATHER,.3,.82)
    for dx,dy in ((-.04,-.03),(.04,-.03),(0,.04)):
        box('quiver fletching',(x+dx,1.9+dy,.98),(.02,.05,.14),STRAW,False)
# Two benches along the side walls.
for x in (-3.2,3.2):
    box('bench',(x,.2,.24),(.4,2.2,.06),WOOD)
    for y in (-.7,1.1):box('bench leg',(x,y,.1),(.3,.08,.2),WOOD,False)
# Straw bales for spare targets in the right front corner.
def bale(n,c,s,seed):
    # Codex 477 DA-STRAW-ART-01 (two plain light blocks): a straw bale - a softly bevelled body, darker
    # stalks laid along its long faces, two twine bands round it, ragged tufts out of both cut ends;
    # its collider the same box as before
    x,y,z=c;sx,sy,sz=s
    body=C.box(n,c,(sx-.04,sy,sz),BALE,.05);body['part_role']='interior_furniture'
    coll.append((n,c,s))
    def r(i,j):return ((seed*73+i*37+j*11)%17)/17.0
    for i in range(7):   # stalks on the top and the front face
        yy=y-sy/2+sy*(i+.5)/7
        plain_stalk(n+' stalk',(x+(r(i,1)-.5)*.06,yy,z+sz/2+.004),(sx*(.7+.25*r(i,2)),.018,.008))
        zz=z-sz/2+sz*(i+.5)/7
        plain_stalk(n+' stalk',(x+(r(i,3)-.5)*.06,y-sy/2-.004,zz),(sx*(.7+.25*r(i,4)),.008,.018))
    for bx in (-sx*.26,sx*.26):   # the twine bands, a little proud of the straw
        for dy,dz,w,h in ((0,sz/2+.006,.025,sy+.012),(0,-sz/2-.006,.025,sy+.012)):
            plain_stalk(n+' twine',(x+bx,y,z+dz),(w,h,.012),TWINE)
        for dy in (-sy/2-.006,sy/2+.006):
            plain_stalk(n+' twine',(x+bx,y+dy,z),(.025,.012,sz+.012),TWINE)
    for side in (-1,1):  # tufts out of the cut ends
        for i in range(9):
            ty=y-sy*.4+sy*.8*r(i,5);tz=z-sz*.4+sz*.8*r(i,6)
            plain_stalk(n+' tuft',(x+side*(sx/2-.01+.03*r(i,7)),ty,tz),(.06+.05*r(i,8),.03,.03),STRAW_DARK if i%2 else BALE)
def plain_stalk(n,c,s,m=None):
    o=C.box(n,c,s,m or STRAW_DARK,0);o['part_role']='interior_furniture'
    return o
bale('straw bale',(3.1,-1.6,.3),(.8,.6,.6),1)
bale('straw bale',(3.1,-1.6,.9),(.8,.6,.6),2)
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
