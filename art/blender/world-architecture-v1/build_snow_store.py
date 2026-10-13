"""S-S14x8m: independent caravan grain store, approved PDF141. WIP production."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/snow-store';QA.mkdir(parents=True,exist_ok=True)
def surface(name,filename,metres):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=metres
    image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/filename),check_existing=True);image.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('S store stone','stone_wall_02_diff_1k.jpg',2)
WOOD=surface('S store timber','fine_grained_wood_col_1k.jpg',.65)
SLATE=C.mat('S store slate',(.12,.16,.18,1))
GRAIN=C.mat('S store sacks',(.43,.38,.28,1))
collision=[]
def box(n,p,s,m,solid=False):
    o=C.box(n,p,s,m,.015)
    if solid:collision.append((n,p,s))
    return o
box('floor',(0,0,-.15),(14,8,.3),STONE,True)
for x in (-4.2,4.2):box('loading wall pier',(x,-3.8,1.7),(5.6,.4,3.4),STONE,True)
box('loading lintel',(0,-3.8,3.05),(2.8,.4,.7),STONE,True)
for a,b in [(-7,-5.1),(-3.9,3.9),(5.1,7)]:
    box('rear wall pier',((a+b)/2,3.8,1.7),(b-a,.4,3.4),STONE,True)
for x in (-4.5,4.5):
    box('vent sill wall',(x,3.8,1.2),(1.2,.4,2.4),STONE,True)
    box('vent header',(x,3.8,3.225),(1.2,.4,.35),STONE,True)
    for dx in (-.64,.64):box('vent jamb',(x+dx,3.8,2.73),(.08,.48,.74),WOOD)
    for z in (2.42,3.03):box('vent frame',(x,3.8,z),(1.35,.48,.08),WOOD)
    for z in (2.49,2.64,2.79,2.94):
        louvre=box('rain louvre',(x,3.86,z),(1.2,.24,.06),WOOD)
        louvre.rotation_euler.x=math.radians(-20)
for x in (-6.8,6.8):box('side wall',(x,0,1.7),(.4,7.2,3.4),STONE,True)
for y in (-3.8,0,3.8):
    for x in (-6.6,6.6):box('frame post',(x,y,1.7),(.24,.24,3.4),WOOD)
    C.beam('cross tie',(-6.8,y,3.4),(6.8,y,3.4),.25,.25,WOOD)
    for x in (-6.8,6.8):C.beam('rafter',(x,y,3.20),(0,y,5.70),.18,.20,WOOD)
roof_meshes=[]
for side in (-1,1):
    x=side*7.25
    vs=[(x,-4.35,3.35),(x,4.35,3.35),(0,4.35,5.95),(0,-4.35,5.95)]
    vs += [(a,b,c-.12) for a,b,c in vs]
    faces=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
    if side<0:faces=[tuple(reversed(f)) for f in faces]
    roof_meshes.append((vs,faces))
    C.mesh('slate roof',vs,faces,SLATE)
    lining=[(xx,yy,zz-.14) for xx,yy,zz in vs[:4]]
    lining += [(xx,yy,zz-.07) for xx,yy,zz in lining]
    C.mesh('wood roof lining',lining,faces,WOOD)
    for row in range(16):
        a=(row+.02)/16;b=min(1,(row+1.05)/16)
        shift=.30 if row%2 else 0
        for col in range(16):
            ya=max(-4.35,-4.65+col*.60+shift);yb=min(4.35,-4.07+col*.60+shift)
            if yb-ya<.05:continue
            xa,xb=x*a,x*b;za,zb=5.95-2.6*a+.035,5.95-2.6*b+.055
            tile=[(xa,ya,za),(xb,ya,zb),(xb,yb,zb),(xa,yb,za)]
            tile += [(xx,yy,zz-.025) for xx,yy,zz in tile]
            C.mesh('overlapping slate',tile,faces,SLATE)
C.beam('ridge',(0,-4.4,6.0),(0,4.4,6.0),.18,.14,SLATE)
for x in (-7.25,7.25):C.beam('eaves',(x,-4.4,3.35),(x,4.4,3.35),.16,.16,WOOD)
for y in (-3.8,3.8):
    C.mesh('gable', [(-6.9,y-.12,3.4),(6.9,y-.12,3.4),(0,y-.12,5.95),(-6.9,y+.12,3.4),(6.9,y+.12,3.4),(0,y+.12,5.95)],[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],WOOD)
# Storage keeps the central loading aisle clear; goods stand on raised platforms.
for x in (-4.7,4.7):
    for y in (-1.5,1.5):
        box('grain platform',(x,y,.24),(2.5,2.1,.18),WOOD,True)
        for dx in (-.95,.95):
            for dy in (-.75,.75):box('platform leg',(x+dx,y+dy,.12),(.18,.18,.24),WOOD)
        for dx in (-.65,0,.65):
            # Rounded, tied cloth sacks rest on the platform; no placeholder cubes.
            bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,location=(x+dx,y,.57))
            sack=bpy.context.object;sack.name='grain sack'
            sack.scale=(.26,.37,.33)
            bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
            sack.data.materials.append(GRAIN);C._link(sack)
            for vertex in sack.data.vertices:
                if vertex.co.z>.23:
                    vertex.co.x*=.35;vertex.co.y*=.35
            box('sack tie',(x+dx,y,.84),(.14,.14,.035),WOOD)
box('counting desk',(-2.8,2.8,.75),(1.3,.65,.12),WOOD,True)
for x in (-3.25,-2.35):box('desk leg',(x,2.8,.35),(.12,.5,.7),WOOD)
hinges=[]
door_parts=[]
for side in (-1,1):
    hinge=bpy.data.objects.new('S_store_entry_hinge_'+str(side),None)
    C.ASSET.objects.link(hinge);hinge.location=(side*1.36,-3.80,0)
    hinge['open_angle_degrees']=-100.0 if side<0 else 100.0
    hinges.append(hinge)
    for k in range(5):
        part=box('Door plank',(side*(.136+k*.272),-3.80,1.31),(.266,.09,2.62),WOOD)
        door_parts.append((part,hinge))
visual=[o for o in C.ASSET.objects if o.type=='MESH']
for o in visual:
    scale=float(o.data.materials[0].get('uv_metres',0))
    if not scale:continue
    bm=bmesh.new();bm.from_mesh(o.data);uv=bm.loops.layers.uv.verify()
    for face in bm.faces:
        axis=max(range(3),key=lambda i:abs(face.normal[i]))
        for loop in face.loops:
            p=o.matrix_world@loop.vert.co
            u,v=((p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y))
            loop[uv].uv=(u/scale,v/scale)
    bm.to_mesh(o.data);bm.free()
C._join_by_material([o for o in visual if not o.name.startswith('Door')])
for o,hinge in door_parts:
    matrix=o.matrix_world.copy();o.parent=hinge;o.matrix_world=matrix
visual=[o for o in C.ASSET.objects if o.type=='MESH']
for n,p,s in collision:
    o=box(n+'-colonly',p,s,STONE);o.hide_render=True
for i,(vs,faces) in enumerate(roof_meshes):
    o=C.mesh('roof'+str(i)+'-colonly',vs,faces,SLATE);o.hide_render=True
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=visual[0]
path=OUT/'s_caravan_store.glb'
bpy.ops.export_scene.gltf(filepath=str(path),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True)
data=path.read_bytes();size=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+size])
tints={'S store stone':(.61,.66,.68),'S store timber':(.30,.24,.18)}
for m in doc['materials']:
    if m['name'] in tints:m['pbrMetallicRoughness']['baseColorFactor']=[*tints[m['name']],1]
encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
stats={'state':'WIP: textures, roof detail, doors, separate wood shelter, Godot QA pending','wall_footprint':[14,8],'loading_clear':[2.8,2.7],'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
for hinge in hinges:C.ASSET.objects.unlink(hinge)
C._studio()
for hinge in hinges:C.ASSET.objects.link(hinge)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_caravan_store.blend'))
scene=bpy.context.scene;scene.render.resolution_x=1280;scene.render.resolution_y=960;scene.render.resolution_percentage=100
scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True
cam=scene.camera;cam.rotation_mode='XYZ';cam.data.type='PERSP';cam.data.lens=40
cam.location=(19,-17,11);cam.rotation_euler=(Vector((0,0,2.4))-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath=str(QA/'exterior-wip.png');bpy.ops.render.render(write_still=True)
print('S_S_WIP',json.dumps(stats))
