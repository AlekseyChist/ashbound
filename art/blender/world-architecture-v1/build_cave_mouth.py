"""Cave mouth (WORLD-PLAN-01, CAVE-MOUTH): a rock hill with an arch into it.
With `-- mine`: the Crown mine's portal (MINE-01) - the same hill, a squared adit 3.4 x 3.2 m with
timber sets every 1.6 m, a heavy portal frame at the entrance and the haulage rails out onto the
yard; mine_portal.glb. The interior beyond is build_mine.py's portal adit."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector, Matrix, noise
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
MINE='--' in sys.argv and 'mine' in sys.argv[sys.argv.index('--'):]
OUT=ROOT/'assets/caves-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/qa'/('mine-portal' if MINE else 'cave-mouth');QA.mkdir(parents=True,exist_ok=True)
def surface(name,folder,stem,scale,roughness):
    # the cave interiors' natural rock (Codex 305): base colour + normal map, no masonry
    m=C.mat(name,(1,1,1,1),roughness);m['uv_metres']=scale
    nodes=m.node_tree.nodes;links=m.node_tree.links;bsdf=nodes['Principled BSDF']
    tex=nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/folder/(stem+'_diff_1k.jpg')),check_existing=True);tex.image.pack()
    links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    nor=nodes.new('ShaderNodeTexImage')
    nor.image=bpy.data.images.load(str(ROOT/folder/(stem+'_nor_gl_1k.jpg')),check_existing=True);nor.image.pack()
    nor.image.colorspace_settings.name='Non-Color'
    nm=nodes.new('ShaderNodeNormalMap')
    links.new(nor.outputs['Color'],nm.inputs['Color']);links.new(nm.outputs['Normal'],bsdf.inputs['Normal'])
    return m
ROCK=surface('CM rock','assets/environment/cave-rock-v1','rock_face_03',4,.95)
EARTH=surface('CM earth','assets/environment/village-surfaces-v1','forest_ground_04',3,.98)
DARK=C.mat('CM dark',(.02,.02,.02,1),1.0)
TIMBER=C.mat('CM timber',(.36,.26,.17,1),.9)
IRON=C.mat('CM iron',(.16,.15,.14,1),.45,.6)
# Codex MOUTH-02 (in-game: three identical boulders, a flat-cut sole and a faceted ring of an arch
# read as a placed object; the flat plug showed from the portal): one connected body of rock, ridged by
# two octaves of noise, its foot spreading into scree that runs 4 m under the ground (no cut sole on a
# slope), an irregular arch of 40 points, and a way that bends aside so its end is never seen. Three
# variants by seed (-- a / b / c) so no two mouths match.
ARGS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
VARIANT=next((x for x in ARGS if x in ('a','b','c','spring')),'a')
# Codex 403 SPRING-MOUTH-01 (A): the spring cave's one mouth over its stream - the 8 m water out of the
# dark and a dry ledge beside it (clear span >= 10 m), a bigger hill round it
SPRING=VARIANT=='spring' and not MINE
HX,HFRONT,HBACK,HZ,HCY=(17.0,7.0,18.0,9.0,5.0) if SPRING else (11.0,4.5,12.0,5.4,4.0)
ARCH_FRONT=8.5 if SPRING else 4.5
SEED={'a':Vector((0,0,0)),'b':Vector((37.1,-11.3,5.7)),'c':Vector((-21.9,44.2,-8.4)),'spring':Vector((11.0,-29.0,17.0))}[VARIANT] if not MINE else Vector((63.0,7.0,-29.0))
bmr=bmesh.new()
bmesh.ops.create_icosphere(bmr,subdivisions=5,radius=1.0)
for v in bmr.verts:
    d=v.co.normalized()
    # a low wide hill, not an egg (in-game 1d39: a pointed boulder): a steep face round the arch in
    # front, the back sloping long into the ground
    ry=HFRONT if d.y<0 else HBACK
    q=Vector((d.x*HX,d.y*ry+HCY,d.z*HZ+0.8))
    o=q*0.14+SEED
    n=noise.noise(o)*1.8+noise.noise(o*3.1)*0.55+abs(noise.noise(o*1.7))*-0.9+noise.noise(o*7.3)*0.22+abs(noise.noise(o*12.0))*-0.12
    out=Vector((d.x/HX,d.y/ry,d.z/HZ)).normalized()
    q+=out*n
    if q.z<1.6:  # the foot spreads out as scree into the ground
        k=(1.6-q.z)/5.0
        q.x*=1.0+0.45*k;q.y=HCY+(q.y-HCY)*(1.0+0.35*k)
    # Codex 374 MOUTH-02 (flat/sharp mound bases: the ellipsoid's near-vertical side met the grass in one
    # level line): under 1.6 m the foot runs out as an apron (~34 deg, up to ~4.7 m), widest from 0.9 m under the ground, its
    # reach varied by noise so the contact line wanders - not in front of the arch (|x| < 4.5 there), where
    # the way and its floor are
    if q.z<1.6:
        side=Vector((q.x,q.y-HCY,0.0))
        if side.length>1e-6:
            front=1.0 if q.y>=1.0 else min(1.0,max(0.0,(abs(q.x)-ARCH_FRONT)/3.0))
            reach=(1.6-max(q.z,-0.9))*1.5*(0.75+0.5*(noise.noise(o*0.6+Vector((5.0,0,0)))*0.5+0.5))*front
            q+=side.normalized()*reach
        # Codex 395 MOUTH-P-APRON-FLOAT-01: on a falling slope the apron's edge hung up to 4.07 m over the
        # ground (mine P, downhill): under 0.9 m the skirt drops steeply to 10 m, so wherever the ground
        # falls away the rock runs down into it (under level ground it stays hidden)
        if q.z<-0.9:
            q.z=-0.9+(q.z+0.9)*2.5
    q.z=max(q.z,-10.0)
    v.co=q
rock=bpy.data.objects.new('cave mouth rock-col',bpy.data.meshes.new('cave mouth rock'))
bmr.to_mesh(rock.data);bmr.free()
bpy.context.scene.collection.objects.link(rock)
# Tunnel: rings of an irregular arch along +y (flared at the entrance, narrowing inward), each radius
# varied by noise round the ring; past 1 m in it bends aside (cave) so the far end hides behind the
# wall; its far end is closed by the rock itself. The mine's adit stays straight and squared.
K=40;rings=[]
ys=[-9.0+i*1.0 for i in range(28)] if SPRING else [-6.0+i*1.0 for i in range(15)]  # -6 .. 8 (spring -9 .. 18)
ZC=2.8 if SPRING else 1.45
def spring_bend(y):
    return min(4.0,0.03*max(0.0,y-4.0)**2)
bmt=bmesh.new()
for y in ys:
    d=y+3.0  # depth past the rock's front
    flare=1.0+0.45*math.exp(-max(d,0.0)/1.6)
    narrow=1.0-0.15*max(0.0,min(1.0,d/8.0))
    rw,rh=1.9*flare*narrow,1.9*flare*narrow
    if SPRING:  # a wide low vault: 10.4 m clear at the water, 8 m high
        narrow=1.0-0.12*max(0.0,min(1.0,d/14.0))
        rw,rh=7.4*flare*narrow,5.2*flare*narrow
    if MINE:  # a squared adit cut by hand: a superellipse, barely jittered, a little flare
        rw,rh=1.7*(1+0.12*math.exp(-max(d,0.0)/1.2)),1.75
    bend=0.0 if MINE else spring_bend(y) if SPRING else min(2.6,0.08*max(0.0,y-1.0)**2)
    ring=[]
    for i in range(K):
        a=2*math.pi*i/K
        if MINE:
            c,sn=math.cos(a),math.sin(a)
            x,z=rw*math.copysign(abs(c)**0.5,c),1.45+rh*math.copysign(abs(sn)**0.5,sn)
            j=noise.noise(Vector((x*.7,y*.7,z*.7)))*0.08
        else:
            wob=1.0+(0.08 if SPRING else 0.16)*noise.noise(Vector((math.cos(a)*1.3,math.sin(a)*1.3,y*0.35))+SEED)
            x,z=rw*wob*math.cos(a),ZC+rh*wob*math.sin(a)
            j=noise.noise(Vector((x*.9,y*.9,z*.9))+SEED)*(0.15 if SPRING else 0.3)
        r=Vector((x,0,z-ZC)).normalized()
        ring.append(bmt.verts.new((x+r.x*j+bend,y,z+r.z*j)))
    rings.append(ring)
for r0,r1 in zip(rings,rings[1:]):
    for i in range(K):
        bmt.faces.new((r0[i],r0[(i+1)%K],r1[(i+1)%K],r1[i]))
bmt.faces.new(rings[0][::-1]);bmt.faces.new(rings[-1])
bmesh.ops.recalc_face_normals(bmt,faces=bmt.faces[:])
tun=bpy.data.objects.new('tunnel',bpy.data.meshes.new('tunnel'));bmt.to_mesh(tun.data);bmt.free()
bpy.context.scene.collection.objects.link(tun)
mod=rock.modifiers.new('tunnel','BOOLEAN')
mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=tun
bpy.context.view_layer.objects.active=rock
bpy.ops.object.modifier_apply(modifier='tunnel')
bpy.data.objects.remove(tun)
# The floor: wider than the arch (no trench by the walls), as far in as the way runs straight; past
# the bend the rock's own floor (flat under the tunnel's bottom ring) carries on.
if SPRING:
    # no floor over the stream (its 8 m water, |x| < 4, runs out of the dark to the arch): a dry rock
    # ledge on the +x side over it, 1.9 m wide, at the arch's floor (the way in), then past the water's
    # head (9.4 m in) dry ground the width of the way, under its bend
    fl=C.box('spring ledge-col',(4.95,4.0,-.7),(1.9,10.0,1.4),ROCK)
    bm=bmesh.new();bm.from_mesh(fl.data);bmesh.ops.subdivide_edges(bm,edges=bm.edges[:],cuts=6,use_grid_fill=True);bm.to_mesh(fl.data);bm.free()
    fl=C.box('spring floor-col',(1.8,13.5,-.7),(11.0,8.0,1.4),EARTH)
else:
    fl=C.box('mouth floor-col',(0,2.75,-.05),(5.6,7.5,.1),EARTH)  # -1 .. 6.5: inside the arch (Codex 351: its edge showed as a rectangle before forest X)
bm=bmesh.new();bm.from_mesh(fl.data);bmesh.ops.subdivide_edges(bm,edges=bm.edges[:],cuts=8,use_grid_fill=True);bm.to_mesh(fl.data);bm.free()  # vertices for the darkness gradient
if MINE:
    C.box('mouth depth',(0,8.6,1.6),(4.4,.1,4.4),DARK)
if MINE:
    # timber sets every 1.6 m in the adit, the portal frame at its mouth, the rails out onto the yard
    for k in range(9):
        yk=-3.4+k*1.6
        for sx in (-1,1):C.box('portal post',(sx*1.45,yk,1.4),(.22,.22,2.8),TIMBER,0)
        C.box('portal cap',(0,yk,2.9),(3.2,.24,.24),TIMBER,0)
    for sx in (-1,1):C.box('portal frame post',(sx*1.6,-4.6,1.6),(.4,.4,3.2),TIMBER,0)
    C.box('portal frame lintel',(0,-4.6,3.35),(4.2,.45,.45),TIMBER,0)
    # the rails end 1.4 m past the frame (in-game frames: 5.5 m of them hung over the falling yard)
    for k in range(int(15.6/0.75)):
        C.box('rail sleeper',(0,-6.0+k*0.75,.05),(1.3,.22,.1),TIMBER,0)
    for sx in (-1,1):C.box('rail',(sx*.45,1.8,.135),(.06,15.6,.07),IRON,0)
# Transition marker: empty inside the tunnel; local +y points into the cave.
e=bpy.data.objects.new('CavePortal',None)
e.location=(4.95,2.5,0) if SPRING else (0,2.5,0);e.empty_display_size=1.0
C.ASSET.objects.link(e)
# Move the ops-created rock from the scene collection into ASSET and set its material.
for col in list(rock.users_collection):col.objects.unlink(rock)
C.ASSET.objects.link(rock)
rock.data.materials.clear();rock.data.materials.append(ROCK)
# smooth shading: the flat facets of the displaced sphere read as a cut gem (in-game 1d39)
for poly in rock.data.polygons:poly.use_smooth=True
# Darkness into the hill as a vertex colour (the world multiplies the albedo by it): white outside,
# down to 6% at the plug, so the arch reads dark like a cave and the plug is no flat black disc.
for o in [o for o in C.ASSET.objects if o.type=='MESH']:
    attr=o.data.color_attributes.new('Col','BYTE_COLOR','CORNER')
    for loop in o.data.loops:
        c=o.matrix_world@o.data.vertices[loop.vertex_index].co
        if SPRING:
            inside=abs(c.x-spring_bend(c.y))<7.6 and c.z<8.2 and c.y>-5.0
            k=max(0.0,min(1.0,(c.y+3.0)/15.0)) if inside else 0.0
        else:
            inside=abs(c.x-min(2.6,0.08*max(0.0,c.y-1.0)**2))<3.6 and c.z<4.8 and c.y>-3.5
            k=max(0.0,min(1.0,(c.y+2.5)/8.0)) if inside else 0.0
        g=1.0-0.96*k**0.75
        attr.data[loop.index].color=(g,g,g,1.0)
    o.data.color_attributes.active_color=attr
# UVs for the textured rock: projected in metres on each face's dominant axis.
for o in [o for o in C.ASSET.objects if o.type=='MESH']:
    scale=o.data.materials[0].get('uv_metres',0) if o.data.materials else 0
    if not scale:continue
    bm=bmesh.new();bm.from_mesh(o.data);bm.normal_update()
    uv=bm.loops.layers.uv.get('UVMap') or bm.loops.layers.uv.new('UVMap')
    for face in bm.faces:
        axis=max(range(3),key=lambda i:abs(face.normal[i]))
        for loop in face.loops:
            q=o.matrix_world@loop.vert.co
            u,v=((q.y,q.z) if axis==0 else (q.x,q.z) if axis==1 else (q.x,q.y))
            loop[uv].uv=(u/scale,v/scale)
    bm.to_mesh(o.data);bm.free()
# Export GLB.
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=next(o for o in C.ASSET.objects if o.type=='MESH')
asset=OUT/('mine_portal.glb' if MINE else ('cave_mouth.glb' if VARIANT=='a' else 'cave_mouth_%s.glb'%VARIANT))
# no images in the GLB: the world gives the rock and ground their textures (triplanar) from
# assets/environment at runtime (world_cave_mouths.gd), so the file stays small
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False,export_image_format='NONE',export_vertex_color='ACTIVE')
bpy.ops.wm.save_as_mainfile(filepath=str(QA/('cave_mouth_%s.blend'%('mine' if MINE else VARIANT))))
visual=[o for o in C.ASSET.objects if o.type=='MESH']
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/('stats_%s.json'%('mine' if MINE else VARIANT))).write_text(json.dumps({'asset':'mine_portal' if MINE else 'cave_mouth','triangles':triangles,'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'portal':'CavePortal at (0,2.5,0), +y into the cave','sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
