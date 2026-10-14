"""Snow stables12x7m, approved PDF141. WIP production."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/snow-stables';QA.mkdir(parents=True,exist_ok=True)
def surface(name,filename,metres):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=metres
    image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/filename),check_existing=True);image.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('S stable stone','stone_wall_02_diff_1k.jpg',2)
WOOD=surface('S stable timber','fine_grained_wood_col_1k.jpg',.65)
def paint(name,color,metres,woven=False):
    m=C.mat(name,(*color,1),.98);m['uv_metres']=metres
    im=bpy.data.images.new(name+' paint',width=256,height=256)
    pixels=[]
    for y in range(256):
        for x in range(256):
            variation=(.018 if woven else .022)*math.sin(x*(1.57 if woven else .039)+y*.023)
            variation+=.012*math.sin(y*(1.57 if woven else .073)-x*.013)
            pixels.extend([max(0,min(1,t+variation)) for t in color]+[1])
    im.pixels.foreach_set(pixels);im.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
SLATE=paint('S stable slate',(.10,.135,.15),.65)
GRAIN=paint('S stable sacks',(.43,.38,.28),.4,True)
collision=[];roof_meshes=[];door_parts=[];hinges=[]
def box(n,p,s,m,solid=True):
    o=C.box(n,p,s,m,.015)
    if n.startswith('manger'):o['part_role']='interior_furniture'
    if solid:collision.append((n,p,s))
    return o
box('stable floor',(0,0,-.15),(12,7,.3),STONE)
for y in (-3.3,3.3):
    if y<0:
        for x in (-3.65,3.65):
            box('front masonry',(x,y,.45),(4.7,.4,.9),STONE)
            box('front timber',(x,y,1.95),(4.7,.4,2.1),WOOD)
        box('entry lintel',(0,y,2.9),(2.6,.4,.2),WOOD)
    else:
        box('rear masonry',(0,y,.45),(12,.4,.9),STONE)
        cuts=[-6,-4.4,-3.6,3.6,4.4,6]
        for a,b in zip(cuts,cuts[1:]):
            bands=[(.9,2.1),(2.7,3)] if a in (-4.4,3.6) else [(.9,3)]
            for lo,hi in bands:box('rear timber',((a+b)/2,y,(lo+hi)/2),(b-a,.4,hi-lo),WOOD)
        for x in (-4,4):
            for dx in (-.4,.4):box('vent frame',(x+dx,y,2.4),(.08,.46,.68),WOOD,False)
            for z in (2.1,2.7):box('vent frame',(x,y,z),(.96,.46,.08),WOOD,False)
for x in (-5.8,5.8):
    box('side masonry',(x,0,.45),(.4,6.2,.9),STONE)
    box('side timber',(x,0,1.95),(.4,6.2,2.1),WOOD)
# Four stalls; a central2.8m passage remains clear.
for side in (-1,1):
    for z in (.45,1.0):box('stall dividing rail',(side*3.7,0,z),(4.2,.10,.1),WOOD)
    for x in (side*1.65,side*3.7,side*5.6):box('stall dividing post',(x,0,.6),(.12,.12,1.2),WOOD)
    for y in (-1.65,1.65):
        x=side*5.08
        box('manger floor',(x,y,.55),(.65,1.1,.08),WOOD)
        for dx in (-.29,.29):box('manger side',(x+dx,y,.68),(.07,1.1,.26),WOOD)
        for dy in (-.515,.515):box('manger end',(x,y+dy,.68),(.51,.07,.26),WOOD)
        for dy in (-.42,.42):box('manger foot',(x,y+dy,.25),(.50,.12,.50),WOOD)
box('ceiling',(0,0,3.05),(12,7,.16),WOOD)
for y in (-3.53,3.53):
    for x in (-5.75,-1.45,1.45,5.75):box('front frame post',(x,y,1.95),(.16,.10,2.1),WOOD,False)
    box('upper frame belt',(0,y,2.96),(12,.10,.16),WOOD,False)
    for a,b in [(-6,-1.3),(1.3,6)] if y<0 else [(-6,6)]:
        box('lower frame belt',((a+b)/2,y,.92),(b-a,.10,.16),WOOD,False)
for x in (-6.03,6.03):
    for y in (-3.05,0,3.05):box('side frame post',(x,y,1.95),(.10,.16,2.1),WOOD,False)
    for z in (.92,2.96):box('side frame belt',(x,0,z),(.10,6.2,.16),WOOD,False)
for side in (-1,1):
    roof=box('slate roof',(0,side*1.95,4.65),(13.2,math.hypot(3.9,2.9),.14),SLATE,False)
    roof.rotation_euler.x=-side*math.atan2(2.9,3.9)
    for row in range(12):
        ya=side*row*3.9/12;yb=side*(row+1)*3.9/12
        for col in range(25):
            xa=max(-6.6,-6.6+col*.55-(.275 if row%2 else 0))
            xb=min(6.6,-6.6+(col+1)*.55-(.275 if row%2 else 0)-.008)
            if xb<=xa:continue
            za=6.1-abs(ya)*2.9/3.9+.08+row*.006
            zb=6.1-abs(yb)*2.9/3.9+.08+row*.006
            vertices=[(xa,ya,za),(xb,ya,za),(xb,yb,zb),(xa,yb,zb)]
            vertices += [(x,y,z-.025) for x,y,z in vertices]
            C.mesh('slate course',vertices,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],SLATE)
    box('eave fascia',(0,side*3.9,3.2),(13.2,.12,.18),WOOD,False)
    x=side*5.8
    C.mesh('timber gable',[(x,-3.5,3),(x,3.5,3),(x,3.5,3.50),(x,0,6.1),(x,-3.5,3.50)],[(0,1,2,3,4)],WOOD)
    for k in range(35):
        a=-3.5+k*.2+.006;b=min(3.5,a+.188)
        za=3.5+2.6*(1-abs(a)/3.5);zb=3.5+2.6*(1-abs(b)/3.5)
        vertices=[(xx,yy,zz) for xx in (x+side*.035,x+side*.075) for yy,zz in [(a,3.02),(b,3.02),(b,zb),(a,za)]]
        C.mesh('gable boarding',vertices,[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],WOOD)
    for sx in (-6.5,6.5):C.beam('gable rake',(sx,0,6.18),(sx,side*3.9,3.28),.12,.12,WOOD)
box('ridge cap',(0,0,6.16),(13.2,.20,.16),SLATE,False)
for side in (-1,1):
    hinge=bpy.data.objects.new('Stable'+str(side)+'_entry_hinge',None);C.ASSET.objects.link(hinge)
    hinge.location=(side*1.3,-3.3,0);hinge['open_angle_degrees']=side*100;hinges.append(hinge)
    for k in range(5):
        part=box('Door plank',(side*(.13+k*.26),-3.3,1.34),(.25,.08,2.68),WOOD,False);door_parts.append((part,hinge))

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
static=[o for o in visual if not o.name.startswith('Door')]
inside=[o for o in static if o.get('part_role')=='interior_furniture']
shell=[o for o in static if o.get('part_role')!='interior_furniture']
C._join_by_material(shell)
C._join_by_material(inside)
for o,hinge in door_parts:
    matrix=o.matrix_world.copy();o.parent=hinge;o.matrix_world=matrix
visual=[o for o in C.ASSET.objects if o.type=='MESH']
for n,p,s in collision:
    o=box(n+'-colonly',p,s,STONE,False);o.hide_render=True
for i,(vs,faces) in enumerate(roof_meshes):
    o=C.mesh('roof'+str(i)+'-colonly',vs,faces,SLATE);o.hide_render=True
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=visual[0]
path=OUT/'s_stables.glb'
bpy.ops.export_scene.gltf(filepath=str(path),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True)
data=path.read_bytes();size=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+size])
tints={'S stable stone':(.61,.66,.68),'S stable timber':(.30,.24,.18)}
for m in doc['materials']:
    if m['name'] in tints:m['pbrMetallicRoughness']['baseColorFactor']=[*tints[m['name']],1]
encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
points=[o.matrix_world@v.co for o in visual for v in o.data.vertices]
stats={'state':'WIP stables; runtime/physics/art/campaign/mobile QA pending','wall_footprint':[12,7],'entry_opening':[2.6,2.8],'geometry_bounds':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')

bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_stables.blend'))
print('S_STABLES_WIP',json.dumps(stats))
