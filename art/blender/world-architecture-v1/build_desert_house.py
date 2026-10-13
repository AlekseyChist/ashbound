"""D-H: playable courtyard house, approved WORLD-PLAN-01 PDF141.
Run Blender --background --factory-startup --python-exit-code 1 --python this_file.
Only its GLB is a game asset; renders, measurements and BLEND remain in local/.
Blender XY footprint; Z up. Export converts to Godot Y up. Pivot: floor centre.
"""
import sys, math, random, json, hashlib, struct
from pathlib import Path
import bpy, bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'art/blender'))
import buildings_common as C
C.reset()
random.seed(118)
OUT = ROOT / 'assets/buildings/world-architecture-v1'
QA = ROOT / 'local/previews/world-architecture-v1/desert-house'
OUT.mkdir(parents=True, exist_ok=True)
QA.mkdir(parents=True, exist_ok=True)
COLLISIONS = []

def painted(name, colour, grain):
    """Small embedded paint texture, deterministic strokes; no procedural GLTF loss."""
    mat = C.mat(name, (*colour, 1), 0.95)
    im = bpy.data.images.new(name + '_paint', width=256, height=256)
    pixels = []
    for y in range(256):
        for x in range(256):
            stroke = math.sin(x*0.031+y*0.012)*0.024 + math.sin(y*0.113)*0.012
            dry = math.sin(x*0.31+y*0.017)*math.sin(y*0.071)*grain
            value = stroke+dry+random.uniform(-0.004,0.004)
            pixels.extend([max(0,min(1,c+value)) for c in colour]+[1])
    im.pixels.foreach_set(pixels)
    im.pack()
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=im
    mat.node_tree.links.new(tex.outputs['Color'], mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    return mat

def surface(name,filename,tint,metres,weather=False):
    """Use the existing licensed surface maps, with restrained material tint, not new copies."""
    m=C.mat(name,(*tint,1),.96)
    m['uv_metres']=metres;m['weather']=weather
    im=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/filename))
    im.pack()
    nt=m.node_tree;tex=nt.nodes.new('ShaderNodeTexImage');tex.image=im
    mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
    mix.inputs[2].default_value=(*tint,1);nt.links.new(tex.outputs['Color'],mix.inputs[1])
    output=mix.outputs['Color']
    if weather:
        colour=nt.nodes.new('ShaderNodeVertexColor');colour.layer_name='Weather'
        damp=nt.nodes.new('ShaderNodeMixRGB');damp.blend_type='MULTIPLY';damp.inputs[0].default_value=1
        nt.links.new(output,damp.inputs[1]);nt.links.new(colour.outputs['Color'],damp.inputs[2]);output=damp.outputs['Color']
    nt.links.new(output,nt.nodes['Principled BSDF'].inputs['Base Color'])
    return m
PLASTER=surface('D warm lime plaster','plaster_grey_04_diff_1k.jpg',(.78,.68,.52),3.0,True)
ROOM=surface('D warm room limewash','plaster_grey_04_diff_1k.jpg',(.93,.81,.62),3.0)
STONE=surface('D cut sandstone','stone_wall_02_diff_1k.jpg',(.72,.63,.49),2.0)
WOOD=surface('D dark oak','fine_grained_wood_col_1k.jpg',(.32,.23,.15),.65)
CLAY=C.mat('D russet pottery',(0.39,0.20,0.12,1))
CLOTH=painted('D faded ochre cloth',(.30,.235,.14),.006)
IRON=C.mat('D forged iron',(0.095,0.09,0.075,1),0.8)
FLOOR=painted('D worn flagstones',(0.46,0.40,0.30),0.014)
LIME=C.mat('D edge limewash',(0.74,0.66,0.51,1))

def box(name, loc, size, mat, solid=False, bevel=0.025):
    o=C.box(name,loc,size,mat,bevel)
    if solid: COLLISIONS.append((name,tuple(loc),tuple(size)))
    return o

def wall_x(name,y,x0,x1,z0,z1,mat=PLASTER):
    return box(name,((x0+x1)/2,y,(z0+z1)/2),(x1-x0,0.4,z1-z0),mat,True)

def wall_y(name,x,y0,y1,z0,z1,mat=PLASTER):
    return box(name,(x,(y0+y1)/2,(z0+z1)/2),(0.4,y1-y0,z1-z0),mat,True)

def door_x(name,y,cx,width=1.3,top=2.35,extent=(-4.3,4.3),height=2.95):
    wall_x(name+' left',y,extent[0],cx-width/2,0,height)
    wall_x(name+' right',y,cx+width/2,extent[1],0,height)
    wall_x(name+' lintel',y,cx-width/2,cx+width/2,top,height)
    for sx in (-1,1):
        box(name+' jamb',(cx+sx*(width/2+0.10),y,1.16),(0.20,0.48,2.32),STONE)
    box(name+' cap',(cx,y,2.48),(width+0.44,0.52,0.26),STONE)

# Exterior boundary exactly 9x9; wall centre ±4.3, thickness 0.4.
box('continuous foundation',(0,0,-0.60),(9.14,9.14,1.20),STONE,True,0)
box('courtyard paving',(0,0,-.02),(9,9,.04),FLOOR,False,0)
door_x('entry',-4.3,0,width=1.5,top=2.5,height=2.8)
wall_y('west wall',-4.3,-4.1,4.1,0,3.1)
wall_y('east wall',4.3,-4.1,4.1,0,3.1)
# Rear wall has two real window openings, not black cards on solid plaster.
for a,b in [(-4.3,-3.05),(-2.15,1.95),(2.85,4.3)]:wall_x('rear pier',4.3,a,b,0,3.1)
for cx in (-2.6,2.4):
    wall_x('rear sill',4.3,cx-.45,cx+.45,0,1.35)
    wall_x('rear header',4.3,cx-.45,cx+.45,2.12,3.1)
    box('window stone sill',(cx,4.3,1.33),(1.12,.52,.12),STONE)
    for j in range(3):box('window bar',(cx-.24+j*.24,4.3,1.72),(.035,.035,.7),IRON)
# Main living room across rear. Door opens onto the courtyard, width 1.3m.
door_x('living room door',1.35,.65,extent=(-4.1,4.1),height=2.95)
# West pantry has an opening in its courtyard wall (Y-direction).
for a,b in [(-4.1,-2.75),(-1.45,1.15)]:wall_y('pantry pier',-1.45,a,b,0,2.95)
wall_y('pantry lintel',-1.45,-2.75,-1.45,2.35,2.95)
# Flat roof over living/pantry rooms, visible beam ends and limewashed parapet.
box('rear roof',(0,2.92,3.0),(8.6,3.35,.28),PLASTER,True)
box('pantry roof',(-2.93,-1.48,2.94),(2.65,5.40,.28),PLASTER,True)
for x in (-3.9,-2.8,-1.7,-.6,.5,1.6,2.7,3.8):
    box('rear joist',(x,2.86,2.82),(.12,3.36,.15),WOOD)
    box('beam end',(x,1.06,2.83),(.15,.27,.16),WOOD)
for y in (-3.9,-2.95,-2,-1.05,-.1):box('pantry joist',(-2.9,y,2.8),(2.9,.13,.17),WOOD)
for x in (-4.25,4.25):box('roof side parapet',(x,2.9,3.37),(.30,3.45,.62),PLASTER,True)
box('rear parapet',(0,4.24,3.38),(8.5,.28,.65),PLASTER,True)
box('rear lime cap',(0,4.24,3.72),(8.58,.34,.10),LIME)
box('pantry parapet',(-4.24,-1.48,3.35),(.30,5.3,.60),PLASTER,True)
# Discrete stone plinth courses, variation concentrated at edges, not random debris.
for a,b in [(-4.5,-.8),(.8,4.5)]:
    box('front stone plinth',((a+b)/2,-4.51,.045),(b-a,.12,.59),STONE)
box('rear stone plinth',(0,4.51,.045),(9,.12,.59),STONE)
for x in (-4.51,4.51):
    box('side stone plinth',(x,0,.045),(.12,9,.59),STONE)
# Roof scupper discharges outside, away from entrance.
box('stone scupper',(4.50,3.75,3.2),(.52,.20,.18),STONE)
# The closed leaf stays separate from static walls and uses the existing door API.
hinge=bpy.data.objects.new('D_entry_hinge',None);C.ASSET.objects.link(hinge)
hinge.location=(-.71,-4.30,0);hinge['open_angle_degrees']=-100.0
door_parts=[]
for k in range(5):door_parts.append(box('Door entry plank',(-.568+k*.284,-4.30,1.22),(.278,.08,2.44),WOOD))
for z in (.43,1.75):door_parts.append(box('Door iron strap',(0,-4.35,z),(1.40,.018,.06),IRON))
# Shaded work alcove on the eastern courtyard side, unobstructed entry axis x=0.
for y in (-2.8,.85):
    box('pergola upright',(2.1,y,1.39),(.16,.16,2.78),WOOD,True)
    box('pergola foot',(2.1,y,.13),(.3,.3,.26),STONE,True)
box('pergola beam',(2.1,-.98,2.83),(.19,3.92,.20),WOOD)
for y in [-2.7+i*.40 for i in range(10)]:box('shade rail',(3.0,y,2.85),(2.1,.12,.13),WOOD)
box('awning woven shade',(3.0,-.98,2.94),(2.05,3.78,.035),CLOTH)
# Living space: bed, low table, hearth with flue to a real chimney.
box('bed frame',(-2.66,2.63,.32),(1.20,2.0,.24),WOOD,True)
box('linen mattress',(-2.66,2.63,.50),(1.13,1.94,.16),CLOTH)
box('bed head',(-2.66,3.59,.67),(1.22,.10,.85),WOOD)
box('blanket',(-2.66,2.25,.60),(1.14,1.1,.035),CLOTH)
for x in (-3.14,-2.18):
    for y in (1.80,3.46):box('bed foot',(x,y,.16),(.12,.12,.32),WOOD)
box('hearth back',(3.70,3.72,.75),(.50,.55,1.5),STONE,True)
box('hearth floor',(3.48,3.62,.07),(1.15,.95,.14),STONE,True)
for x in (3.0,3.96):box('hearth cheek',(x,3.55,.43),(.15,.9,.86),STONE,True)
box('hearth hood',(3.47,3.7,1.42),(1.12,.70,.26),STONE)
box('flue',(3.74,3.83,2.10),(.40,.40,1.38),PLASTER)
box('chimney',(3.74,3.83,3.9),(.56,.56,1.35),PLASTER,True)
for x in (3.46,4.02):box('chimney top',(x,3.83,4.63),(.10,.63,.20),STONE)
box('table',(0,3.18,.73),(1.35,.78,.10),WOOD,True)
for x in (-.49,.49):
    for y in (2.93,3.43):box('table leg',(x,y,.35),(.10,.10,.70),WOOD)
box('stool',(0,2.3,.4),(.45,.4,.12),WOOD,True)
for x in (-.15,.15):
    for y in (2.17,2.43):box('stool leg',(x,y,.19),(.08,.08,.38),WOOD)
# Pantry shelving and bags leave a 1.2m aisle between door and west wall.
for z in (.55,1.17,1.8):box('pantry shelf',(-3.82,-.6,z),(.48,2.25,.10),WOOD)
for y in (-1.65,.45):box('shelf post',(-3.85,y,.96),(.1,.1,1.92),WOOD)
for y in (-.95,-.28,.38):box('grain sack',(-3.7,y,.78),(.33,.43,.40),CLOTH,bevel=.10)
# Low polygon vessels: controlled silhouettes, dry courtyard water storage.
def pot(name,x,y,h,r):
    verts=[];faces=[];n=12
    levels=[(0,.65),(.08,.8),(.35,1),(.70,.86),(.88,.50),(1,.55)]
    for z,s in levels:
        for k in range(n):
            t=k*math.tau/n;verts.append((x+r*s*math.cos(t),y+r*s*math.sin(t),z*h))
    for j in range(len(levels)-1):
        for k in range(n):faces.append((j*n+k,j*n+(k+1)%n,(j+1)*n+(k+1)%n,(j+1)*n+k))
    faces.append(tuple(reversed(range(n))))
    C.mesh(name,verts,faces,CLAY)
pot('water jar',3.8,-2.5,.80,.28)
pot('small pitcher',3.35,-2.48,.38,.14)
box('work bench',(3.7,-.65,.70),(.65,1.45,.13),WOOD,True)
for x in (3.47,3.93):
    for y in (-1.23,-.07):box('workbench leg',(x,y,.34),(.12,.12,.68),WOOD)
# Ground pivot remains zero; do not recenter to asymmetric chimney.
visual=[o for o in C.ASSET.objects if o.type=="MESH"]
for o in visual:
    m=o.data.materials[0]
    scale=float(m.get('uv_metres',0))
    if not scale:continue
    bm=bmesh.new();bm.from_mesh(o.data)
    if m.get('weather'):
        edges=[e for e in bm.edges if e.calc_length()>1]
        bmesh.ops.subdivide_edges(bm,edges=edges,cuts=3,use_grid_fill=True)
        o.data.materials.append(ROOM)
        for face in bm.faces:
            centre=o.matrix_world@face.calc_center_median()
            if abs(centre.x)<4.25 and abs(centre.y)<4.25 and centre.z<3.1:
                face.material_index=1
    uv=bm.loops.layers.uv.verify()
    for face in bm.faces:
        axis=max(range(3),key=lambda i:abs(face.normal[i]))
        for loop in face.loops:
            p=o.matrix_world@loop.vert.co
            u,v=((p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y))
            loop[uv].uv=(u/scale,v/scale)
    bm.to_mesh(o.data);bm.free()
    if m.get('weather'):
        attr=o.data.color_attributes.new(name='Weather',type='FLOAT_COLOR',domain='CORNER')
        for k,loop in enumerate(o.data.loops):
            p=o.matrix_world@o.data.vertices[loop.vertex_index].co
            outside=abs(p.x)>4.2 or abs(p.y)>4.2
            low=.24*max(0,1-p.z/.9) if outside else 0
            drip=.18*math.exp(-((p.y-3.75)/.55)**2)*max(0,1-abs(p.z-1.6)/2) if p.x>4.4 else 0
            shade=max(.58,1-low-drip)
            attr.data[k].color=(shade,shade,shade,1)
        o.data.color_attributes.active_color=attr
C._join_by_material([o for o in visual if o not in door_parts])
for o in door_parts:
    matrix=o.matrix_world.copy();o.parent=hinge;o.matrix_world=matrix
visual=[o for o in C.ASSET.objects if o.type=="MESH"]
for name,loc,size in COLLISIONS:
    o=box(name+'-colonly',loc,size,PLASTER,False,0)
    o.hide_render=True
    o['collision_only']=True
all_mesh=list(C.ASSET.objects)
bpy.ops.object.select_all(action='DESELECT')
for o in all_mesh:o.select_set(True)
bpy.context.view_layer.objects.active=visual[0]
path=OUT/'d_courtyard_house.glb'
bpy.ops.export_scene.gltf(filepath=str(path),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_all_vertex_colors=True,export_extras=True)
# The exporter preserved these photo bytes but omitted MixRGB's constant multiplier
# (verified against source-image means). Write the standard glTF linear colour factor;
# binary image/mesh chunks and buffer-view offsets remain untouched.
data=path.read_bytes();json_size=struct.unpack_from('<I',data,12)[0]
document=json.loads(data[20:20+json_size])
tints={'D warm lime plaster':(.78,.68,.52),'D warm room limewash':(.93,.81,.62),'D cut sandstone':(.72,.63,.49),'D dark oak':(.32,.23,.15)}
for material in document['materials']:
    if material['name'] in tints:
        material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':'),ensure_ascii=False).encode('utf-8')
encoded+=b' '*((-len(encoded))%4)
remaining=data[20+json_size:]
path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(remaining))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+remaining)
tris=0
for o in visual:o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
points=[o.matrix_world@v.co for o in visual for v in o.data.vertices]
mn=[min(p[i] for p in points) for i in range(3)];mx=[max(p[i] for p in points) for i in range(3)]
stats={'triangles':tris,'materials':len({m.name for o in visual for m in o.data.materials}),'visual_meshes':len(visual),'collision_boxes':len(COLLISIONS),'bbox_blender':[mn,mx],'wall_footprint':[9,9],'main_door_clear':[1.5,2.5],'room_door_clear':[1.3,2.35],'godot_front':[0,0,1],'pivot':'floor centre','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'approval':'PDF141 D118','limitations':['asset studio review only; campaign placement and phone performance require later QA']}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
# CPU renders: full exterior, elevated courtyard, pedestrian entry and living room.
C.ASSET.objects.unlink(hinge)
C._studio()
C.ASSET.objects.link(hinge)
bpy.data.objects['PreviewGround'].location.z=-.26
bpy.context.scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.32,.38,.45,1)
bpy.context.scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
sc=bpy.context.scene
sc.render.engine='CYCLES';sc.cycles.device='CPU';sc.cycles.samples=20;sc.cycles.use_denoising=True
sc.render.resolution_x=1280;sc.render.resolution_y=960;sc.render.resolution_percentage=100
sc.render.image_settings.file_format='PNG'
sc.view_settings.view_transform='AgX'
cam=sc.camera;cam.rotation_mode='XYZ';cam.data.type='PERSP';cam.data.lens=40
def view(name,pos,target):
    cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    sc.render.filepath=str(QA/(name+'.png'));bpy.ops.render.render(write_still=True)
view('exterior',(13,-17,10),(0,0,1.4))
view('courtyard',(7,-11,12),(0,0,1.2))
view('entry',(0,-7.7,1.7),(0,1.6,1.45))
view('living-room',(1.1,1.65,1.6),(-1.5,3.25,1.0))
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'d_courtyard_house.blend'))
print('D_H_ASSET_BUILT',json.dumps(stats))
