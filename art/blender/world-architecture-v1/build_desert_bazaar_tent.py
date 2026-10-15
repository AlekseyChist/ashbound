"""Desert plot Bz1/Bz2: 'Bazaar at the gates' trading tent, 5x4 m; canonical GLB source.

Open on the front (-y): counter with wares, carpet rolls, jars, crates and a
trader stool. No door: the trader enters from the right of the counter through
the open passage x 1.0..2.4. Blender z-up.
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
QA=ROOT/'local/qa/desert-bazaar';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('DB stone','stone_wall_02_diff_1k.jpg',2)
WOOD=surface('DB timber','fine_grained_wood_col_1k.jpg',.65)
CLOTH=C.mat('DB awning',(.62,.52,.36,1),.98)
STRIPE=C.mat('DB stripe',(.52,.17,.11,1),.95)
CLAY=C.mat('DB clay',(.60,.38,.24,1),.9)
WOOL=C.mat('DB carpet',(.40,.14,.12,1),.98)
WOOL_END=C.mat('DB carpet end',(.22,.07,.06,1),.98)   # a roll's end: the darker turns inside
WICKER=C.mat('DB wicker',(.48,.36,.20,1),.95)
PRODUCE=C.mat('DB produce',(.72,.42,.14,1),.8)
coll=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith(('counter','crate','jar','basket','carpet roll','stool')):
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
def vessel(n,x,y,z,rings,m,depth,lip=.82,role=True,k=12):
    # Codex BZR-ART-01b (baskets and jars capped by one flat face): an OPEN vessel - its rings from the
    # foot up, a rim (the top ring to an inner ring lip*its size), the inner wall down `depth` and an
    # inner floor; k sides
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
    faces.append(tuple(range((n_r-1)*k,n_r*k)))   # the inner floor, facing up
    o=C.mesh(n,v,faces,m)
    if role:o['part_role']='interior_furniture'
    return o
def roll(n,x,y,h,r):
    # Codex BZR-ART-01a (square wooden bars): a rolled carpet standing on end - a slightly flattened
    # cylinder, its top end a darker inset spiral of turns, the loose edge of the cloth down one side
    k=14
    v=[];f=[]
    for z in (0.0,h):
        for i in range(k):
            a=math.pi*2*i/k
            v.append((x+r*.92*math.cos(a),y+r*math.sin(a),z))
    for i in range(k):
        j=(i+1)%k;f.append((i,j,k+j,k+i))
    f.append(tuple(range(k-1,-1,-1)))
    o=C.mesh(n,v,f+[tuple(range(k,2*k))],WOOL)
    o['part_role']='interior_furniture'
    # the end: concentric turns, each a thin ring a little lower and darker
    for t,(ra,rb) in enumerate(((r*.9,r*.66),(r*.62,r*.4),(r*.36,r*.14))):
        ve=[];fe=[]
        zt=h+.004-t*.006
        for i in range(k):
            a=math.pi*2*i/k
            ve.append((x+ra*.92*math.cos(a),y+ra*math.sin(a),zt));ve.append((x+rb*.92*math.cos(a),y+rb*math.sin(a),zt))
        for i in range(k):
            j=(i+1)%k;fe.append((2*i,2*j,2*j+1,2*i+1))
        e=C.mesh(n+' end',ve,fe,WOOL_END if t%2==0 else WOOL);e['part_role']='interior_furniture'
    flap=C.box(n+' flap',(x+r*.9,y-r*.25,h*.5),(.012,r*.9,h*.96),WOOL,0);flap['part_role']='interior_furniture'
    return o
# Base slab 5x4.
box('base',(0,0,-.08),(5,4,.16),STONE)
# Posts 0.12x0.12 timber: front row y=-1.9 (h 2.6), rear row y=1.9 (h 2.24).
for x in (-2.4,0,2.4):
    box('post',(x,-1.9,1.3),(.12,.12,2.6),WOOD)
    # up to the awning's underside there (2.24; the task's 2.2 left the cloth 4 cm over the posts)
    box('post',(x,1.9,1.12),(.12,.12,2.24),WOOD)
# Sloped cloth roof prism, explicit heights: y0 z0 down to y1 z1, thickness t.
FACES=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
def sloped(name,x0,x1,y0,z0,y1,z1,t,material):
    vertices=[(x,y,z+dz) for x in (x0,x1) for (y,z) in ((y0,z0),(y1,z1)) for dz in (-t,0)]
    return C.mesh(name,vertices,FACES,material)
sloped('awning',-2.6,2.6,-2.1,2.66,2.1,2.26,.04,CLOTH)
# Front valance and three roof stripes.
box('valance',(0,-2.12,2.52),(5.2,.03,.26),STRIPE,False)
for x in (-1.6,0,1.6):
    sloped('awning stripe',x-.3,x+.3,-2.11,2.68,2.11,2.28,.02,STRIPE)
# Rear drape (z 0.6..2.2) and side drapes to half depth.
box('back drape',(0,1.96,1.4),(4.9,.03,1.6),CLOTH,False)
for x in (-2.46,2.46):
    box('side drape',(x,1.0,1.45),(.03,1.8,1.5),CLOTH,False)
# Counter (x -2.0..1.0, y ~-1.4).
box('counter top',(-.5,-1.4,.92),(3.0,.6,.08),WOOD)
box('counter front',(-.5,-1.68,.46),(3.0,.04,.88),WOOD)
for x in (-1.95,.95):
    box('counter leg',(x,-1.15,.44),(.08,.08,.88),WOOD,False)
# Wares: baskets on the counter, carpet rolls by the rear drape, jars right,
# crates left, trader stool.
for k_,x in enumerate((-1.6,-.9,-.2,.5)):
    # baskets: wicker, low and wide with a woven band, fruit in them (unlike the clay jars)
    vessel('basket',x,-1.4,.96,[(0,.15,.13),(.09,.2,.17),(.1,.212,.182),(.11,.2,.17),(.2,.2,.17)],WICKER,.12)
    for dx,dy in ((-.06,-.03),(.06,.02),(0,.05),(-.02,-.07)):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=.055,location=(x+dx,-1.4+dy,.96+.13))
        fr=bpy.context.active_object;fr.name='basket produce';fr.data.materials.append(PRODUCE);fr['part_role']='interior_furniture'
        for c in list(fr.users_collection):c.objects.unlink(fr)
        C.ASSET.objects.link(fr)
for x in (-1.8,-1.2,-.6):
    roll('carpet roll',x,1.6,1.4,.11)
for x,y in ((1.5,1.2),(1.9,1.4),(1.7,.8)):
    # jars: clay with an open neck and a lip
    vessel('jar',x,y,0.0,[(0.000,0.099,0.099),(0.180,0.160,0.160),(0.372,0.147,0.147),(0.480,0.080,0.080),(0.552,0.072,0.072),(0.600,0.093,0.093)],CLAY,.16,.78)
box('crate',(-1.9,.6,.3),(.6,.6,.6),WOOD)
box('crate',(-1.9,.6,.85),(.5,.5,.5),WOOD)
box('stool',(.5,-.6,.25),(.35,.35,.5),WOOD)
# No door: open front, trader passage x 1.0..2.4 right of the counter.
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
asset=OUT/'d_bazaar_tent_5x4.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
# the timber's tint lifted (Codex BZR-MAT-01: over the dark oak texture .33/.24/.16 read black)
tints={'DB stone':(.72,.63,.49),'DB timber':(.88,.78,.64)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_bazaar_tent_5x4.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'built; Codex export and Godot review pending','walls':[5,4],'maximum_height':2.7,'rooms':['stall'],'triangles':triangles,'meshes':len(visual),'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'entry':'open front; trader passage x 1.0..2.4 right of the counter','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
