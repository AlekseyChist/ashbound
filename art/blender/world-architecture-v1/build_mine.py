"""The Crown mine's interior (WORLD-PLAN-01, MINE-01): the working levels from
assets/world/mine-v1/plan.json - the portal adit and station, shaft С1 with its cage, the upper
galleries (-25), the incline Н1, the lower shifts (-60) and the old drainage adit Ш2. Rock-cut
galleries (the caves' natural rock, outward-only bulges, flat floors), timber sets every 2.5 m,
rails in the haulage ways. The rock fall (SQ-MINE-04) and Ш1's masonry (act IV) are solid seals.
Plan frame: x east, z south, y up; Blender (x, -z, y)."""
import sys,json,hashlib,math
from pathlib import Path
import bpy,bmesh
from mathutils import Vector, noise
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/caves-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/qa/mine';QA.mkdir(parents=True,exist_ok=True)
PLAN=json.loads((ROOT/'assets/world/mine-v1/plan.json').read_text(encoding='utf-8'))
def surface(name,folder,stem,scale,roughness,normal=True):
    m=C.mat(name,(1,1,1,1),roughness);m['uv_metres']=scale
    nodes=m.node_tree.nodes;links=m.node_tree.links;bsdf=nodes['Principled BSDF']
    tex=nodes.new('ShaderNodeTexImage')
    suffix='_col_1k.jpg' if stem.startswith('fine_grained') else '_diff_1k.jpg'
    tex.image=bpy.data.images.load(str(ROOT/folder/(stem+suffix)),check_existing=True);tex.image.pack()
    links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    if normal:
        nor=nodes.new('ShaderNodeTexImage')
        nor.image=bpy.data.images.load(str(ROOT/folder/(stem+'_nor_gl_1k.jpg')),check_existing=True);nor.image.pack()
        nor.image.colorspace_settings.name='Non-Color'
        nm=nodes.new('ShaderNodeNormalMap')
        links.new(nor.outputs['Color'],nm.inputs['Color']);links.new(nm.outputs['Normal'],bsdf.inputs['Normal'])
    return m
ROCK=surface('MN rock','assets/environment/cave-rock-v1','rock_face_03',4,.95)
EARTH=surface('MN earth','assets/environment/village-surfaces-v1','forest_ground_04',3,.98)
TIMBER=surface('MN timber','assets/environment/village-house-materials-v1','fine_grained_wood',.8,.9)
MASONRY=surface('MN masonry','assets/environment/village-house-materials-v1','stone_wall_02',2,.95)
IRON=C.mat('MN iron',(.16,.15,.14,1),.45,.6)
def B(x,z,y):
    return Vector((x,-z,y))
LEVEL={l['id']:float(l['y']) for l in PLAN['levels']}
def gallery_h(w):
    return 3.0 if w>=3 else 2.6
volumes=[]
def slab(name,a,b,w,h):
    """A box volume along a->b (Blender points on the floor), w across, h up; the floor may slope."""
    d=Vector((b.x-a.x,b.y-a.y,0));d.normalize();n=Vector((-d.y,d.x,0))*(w/2)
    v=[a-n,a+n,b+n,b-n];v+= [p+Vector((0,0,h)) for p in v]
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
    o=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(o);volumes.append(o);return o
def room(name,x,z,y,w,d,h=3.4):
    a=B(x-w/2,z,y);b=B(x+w/2,z,y);return slab(name,a,b,d,h)
segments=[]  # (a,b,w,h,rail) on the floor, for the timber and the rails
for lv in PLAN['levels']:
    y0=float(lv['y'])
    for g in lv.get('galleries',[]):
        pts=g['pts'];w=float(g['w']);h=gallery_h(w);n=len(pts)-1
        y1=float(g.get('y_end',y0))
        for i in range(n):
            ya=y0+(y1-y0)*i/n;yb=y0+(y1-y0)*(i+1)/n
            a=B(pts[i][0],pts[i][1],ya);b=B(pts[i+1][0],pts[i+1][1],yb)
            # overlap the joints by half a width so the corners stay open
            d=(b-a).normalized();a2=a-d*(w/2 if i>0 else 0);b2=b+d*(w/2 if i<n-1 else 0)
            slab(g['id'],a2,b2,w,h);segments.append((a,b,w,h,g.get('rail',False)))
    for r in lv.get('rooms',[]):
        room(r['id'],r['x'],r['z'],y0+float(r.get('floor',0)),r['w'],r['d'])
# Н1: four flights with landings, from the upper main gallery to the lower gallery
inc=PLAN['incline'];w=float(inc['w']);ytop=LEVEL[inc['from']];ybot=LEVEL[inc['to']]
fl=inc['flights'];drop=(ytop-ybot)/len(fl)
for k,(x,z0,z1) in enumerate(fl):
    ya=ytop-drop*k;yb=ya-drop
    zs=z0-(0.5 if k==0 else 0)  # the first flight starts at the main gallery's edge
    a=B(x,zs,ya);b=B(x,z1,yb)
    slab('Н1 flight %d'%k,a,b,w,2.8);segments.append((a,b,w,2.6,False))
    if k<len(fl)-1:
        xn=fl[k+1][0];zc=z1+(1.25 if z1>z0 else -1.25)
        room('Н1 landing %d'%k,(x+xn)/2,zc,yb,abs(xn-x)+w,2.5+w,2.8)
ex,ez=inc['end'];a=B(fl[-1][0],fl[-1][2],ybot);b=B(ex,ez+1.75,ybot)
slab('Н1 foot',a,b,w,2.8)
# shaft С1: from under the lower station to over the portal station
sh=PLAN['shaft'];sw,sd=float(sh['w']),float(sh['d'])
room('shaft С1',sh['x'],sh['z'],LEVEL['lower']-1.2,sw,sd,LEVEL['portal']-LEVEL['lower']+1.2+5.0)
# Union into one rock shell.
base=volumes[0]
for other in volumes[1:]:
    mod=base.modifiers.new('u','BOOLEAN');mod.operation='UNION';mod.solver='EXACT';mod.object=other
    bpy.context.view_layer.objects.active=base;bpy.ops.object.modifier_apply(modifier='u')
    bpy.data.objects.remove(other)
bm=bmesh.new();bm.from_mesh(base.data)
for f in bm.faces:f.normal_flip()
bmesh.ops.triangulate(bm,faces=bm.faces[:])
for _ in range(7):  # break the long box faces so the rock can bulge
    long=[e for e in bm.edges if e.calc_length()>2.5]
    if not long:break
    bmesh.ops.subdivide_edges(bm,edges=long,cuts=1)
    bmesh.ops.triangulate(bm,faces=bm.faces[:])
bm.normal_update()
# Rock-cut walls: outward-only bulges, smaller than the caves'; a floor stays flat (its vertices
# move only sideways).
moves=[]
for v in bm.verts:
    if not v.link_faces:continue
    q=v.co;nrm=v.normal.copy()
    n=noise.noise(q*0.35)*0.5+noise.noise(q*1.2)*0.2
    amount=max(0.0,0.12+0.14*n)
    if any(f.normal.z>0.7 for f in v.link_faces):
        nrm.z=0.0
        if nrm.length<1e-4:continue
        nrm.normalize()
    moves.append((v,q-nrm*amount))
for v,co in moves:v.co=co
bm.normal_update()
# the slots first: materials.clear() resets every face's index to 0 (Codex ART-CV-03: the whole
# shell exported as rock, its floor's earth lost)
base.data.materials.clear();base.data.materials.append(ROCK);base.data.materials.append(EARTH)
for f in bm.faces:f.material_index=1 if f.normal.z>0.7 else 0
bm.to_mesh(base.data);bm.free()
base.name='mine shell-col'
for col in list(base.users_collection):col.objects.unlink(base)
C.ASSET.objects.link(base)
# Timber sets, rails and sleepers, built straight into one mesh per material.
parts={}
def put(mat,centre,size,yaw=0.0,pitch=0.0):
    bmp=parts.setdefault(mat.name,(bmesh.new(),mat))[0]
    r=bmesh.ops.create_cube(bmp,size=1.0)
    vs=r['verts']
    bmesh.ops.scale(bmp,vec=size,verts=vs)
    from mathutils import Matrix
    rot=Matrix.Rotation(yaw,4,'Z')@Matrix.Rotation(pitch,4,'X')
    bmesh.ops.transform(bmp,matrix=rot,verts=vs)
    bmesh.ops.translate(bmp,vec=centre,verts=vs)
def in_other(q,own):
    # a point in another way's clear width (a junction): no timber set there
    for seg in segments:
        if seg is own:continue
        a,b,w,h,_=seg;d=b-a;L2=d.x*d.x+d.y*d.y
        t=((q.x-a.x)*d.x+(q.y-a.y)*d.y)/L2
        if t<-0.02 or t>1.02:continue
        c=a+d*max(0.0,min(1.0,t))
        if math.hypot(q.x-c.x,q.y-c.y)<w/2+.15 and abs(q.z-c.z)<2.0:return True
    for lv in PLAN['levels']:
        for r in lv.get('rooms',[]):
            if abs(q.x-r['x'])<r['w']/2+.15 and abs(-q.y-r['z'])<r['d']/2+.15 and abs(q.z-float(lv['y']))<2.0:return True
    return False
for seg in segments:
    a,b,w,h,rail=seg
    L=(b-a).length;d=(b-a)/L;side=Vector((-d.y,d.x,0)).normalized();yaw=math.atan2(d.y,d.x)
    for k in range(1,int(L/2.5)+1):
        p=a+d*(k*2.5-1.25)
        if any(in_other(p+side*sg*(w/2-.12),seg) for sg in (-1,1)):continue
        for s in (-1,1):
            put(TIMBER,p+side*s*(w/2-.12)+Vector((0,0,(h-.1)/2)),(.2,.2,h-.1),yaw)
        put(TIMBER,p+Vector((0,0,h-.18)),(.2,w-.04,.2),yaw)
    if rail:
        flat=Vector((d.x,d.y,0)).length
        pitch=math.atan2(d.z,flat)
        for k in range(int(L/0.75)):
            p=a+d*(k*0.75+.375)
            put(TIMBER,p+Vector((0,0,.05)),(.22,1.3,.1),yaw)
        for s in (-1,1):
            put(IRON,(a+b)/2+side*s*.45+Vector((0,0,.135)),(L,.06,.07),yaw,0)
# Shaft guides in the corners, fixed railings on three faces at each stop, the gate, the cage.
gates=sh['gates'];cx,cz=sh['x'],sh['z']
yb0,yt0=LEVEL['lower']-1.2,LEVEL['portal']+3.8
for sx in (-1,1):
    for sz in (-1,1):
        put(TIMBER,B(cx+sx*(sw/2-.15),cz+sz*(sd/2-.15),(yb0+yt0)/2),(.18,.18,yt0-yb0))
FACES={'+x':(1,0),'-x':(-1,0),'+z':(0,1),'-z':(0,-1)}
for lv in sh['stops']:
    y=LEVEL[lv]
    for face,(fx,fz) in FACES.items():
        along=sd if fx else sw
        centre=B(cx+fx*(sw/2+.1),cz+fz*(sd/2+.1),y)
        size=(.12,along,.1) if fx else (along,.12,.1)
        if face==gates[lv]:
            g=bpy.data.objects.new('ShaftGate_'+lv,None);g.location=centre;C.ASSET.objects.link(g)
            for hgt in (.5,1.05):
                bar=C.box('ShaftGate_%s bar'%lv,centre+Vector((0,0,hgt)),size,TIMBER,0);bar.parent=g;bar.location=Vector((0,0,hgt))
            col=C.box('ShaftGate_%s-colonly'%lv,centre+Vector((0,0,.6)),(size[0] if fx else along,size[1] if not fx else along,1.2),TIMBER,0);col.parent=g;col.location=Vector((0,0,.6))
            continue
        for hgt in (.5,1.05):
            put(TIMBER,centre+Vector((0,0,hgt)),size)
        for s in (-1,1):
            post=centre+(Vector((0,s*along/2,0)) if fx else Vector((s*along/2,0,0)))
            put(TIMBER,post+Vector((0,0,.6)),(.14,.14,1.2))
        C.box('shaft rail %s %s-colonly'%(lv,face),centre+Vector((0,0,.6)),(.12,along,1.2) if fx else (along,.12,1.2),TIMBER,0)
    e=bpy.data.objects.new('LiftStop_'+lv,None);e.location=B(cx,cz,y);C.ASSET.objects.link(e)
cage=bpy.data.objects.new('LiftCage',None);cage.location=B(cx,cz,LEVEL['portal']);C.ASSET.objects.link(cage)
cw=min(sw,sd)-.5
for o in [C.box('LiftCage floor',B(cx,cz,LEVEL['portal']-.08),(cw,cw,.16),TIMBER,0),
          C.box('LiftCage roof',B(cx,cz,LEVEL['portal']+2.75),(cw,cw,.12),TIMBER,0)]+[
          C.box('LiftCage post',B(cx+sx*(cw/2-.06),cz+sz*(cw/2-.06),LEVEL['portal']+1.35),(.12,.12,2.7),IRON,0) for sx in (-1,1) for sz in (-1,1)]:
    o.parent=cage;o.location=o.location-cage.location
fc=C.box('LiftCage floor-colonly',B(cx,cz,LEVEL['portal']-.08),(cw,cw,.16),TIMBER,0);fc.parent=cage;fc.location=fc.location-cage.location
# Seals: the rock fall (SQ-MINE-04) and Ш1's masonry (act IV), both solid.
for lv in PLAN['levels']:
    for s in lv.get('seals',[]):
        x,z=s['at'];y=float(lv['y'])
        if s['kind']=='masonry':
            C.box('seal masonry-col',B(x,z,y+1.6),(3.6,.7,3.3),MASONRY,0)
        else:
            for k,(dx,dz,r) in enumerate(((0,0,1.3),(.7,.4,1.0),(-.7,-.3,1.0),(.2,.8,.8),(-.3,-.8,.9))):
                bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=r,location=B(x+dx,z+dz,y+r*.5))
                o=bpy.context.active_object;o.name='seal rock fall %d-col'%k
                bmr=bmesh.new();bmr.from_mesh(o.data)
                for v in bmr.verts:v.co+=v.co.normalized()*noise.noise(v.co*1.7+Vector((k,0,0)))*.22
                bmr.to_mesh(o.data);bmr.free()
                o.data.materials.append(ROCK);C._link(o)
for name,(bmp,mat) in parts.items():
    o=bpy.data.objects.new('mine '+name.split()[-1],bpy.data.meshes.new(name));bmp.to_mesh(o.data);bmp.free()
    o.data.materials.append(mat);C.ASSET.objects.link(o)
# Exits on the floor, +x local pointing out.
for e in PLAN['exits']:
    (x,z),(ox,oz)=e['at'],e['out']
    m=bpy.data.objects.new('Exit_'+e['id'],None);m.location=B(x,z,LEVEL[e['level']]+(-9.0 if 'Ш2' in e['id'] else 0))
    m.rotation_euler=(0,0,math.atan2(-oz,ox));C.ASSET.objects.link(m)
for o in list(C.ASSET.objects):
    for col in list(o.users_collection):
        if col!=C.ASSET:col.objects.unlink(o)
# UVs: metres on each face's dominant axis.
for o in [o for o in C.ASSET.objects if o.type=='MESH']:
    if not any(m.get('uv_metres',0) for m in o.data.materials):continue
    bm=bmesh.new();bm.from_mesh(o.data);bm.normal_update()
    uv=bm.loops.layers.uv.get('UVMap') or bm.loops.layers.uv.new('UVMap')
    for face in bm.faces:
        scale=o.data.materials[face.material_index].get('uv_metres',0) or 3
        axis=max(range(3),key=lambda i:abs(face.normal[i]))
        for loop in face.loops:
            q=o.matrix_world@loop.vert.co
            u,v=((q.y,q.z) if axis==0 else (q.x,q.z) if axis==1 else (q.x,q.y))
            loop[uv].uv=(u/scale,v/scale)
    bm.to_mesh(o.data);bm.free()
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=next(o for o in C.ASSET.objects if o.type=='MESH')
asset=OUT/'crown_mine.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'crown_mine.blend'))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and not o.name.endswith('-colonly')]
triangles=0
earth_faces=sum(1 for o in visual for poly in o.data.polygons if o.data.materials and len(o.data.materials)>poly.material_index and o.data.materials[poly.material_index].name.endswith('earth'))
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'mine':'crown_mine','triangles':triangles,'earth_faces':earth_faces,'meshes':len(visual),'exits':[e['id'] for e in PLAN['exits']],'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
