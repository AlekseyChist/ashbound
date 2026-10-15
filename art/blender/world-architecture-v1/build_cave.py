"""Any cave's interior from the caves' plan (WORLD-PLAN-01, CAVE-01..04): chambers, links, floors,
exits - the forest cave's recipe (build_cave_forest.py, Codex 305) read from
assets/world/caves-v1/plan.json. Usage: blender -b --python build_cave.py -- <cave id>
A link of kind "завален..." (sealed until a later act) is closed by a rock fall in its middle."""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector, Matrix, noise
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT=ROOT/'assets/caves-v1';OUT.mkdir(parents=True,exist_ok=True)
CAVE=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'forest_cave'
PLAN=next(c for c in json.loads((ROOT/'assets/world/caves-v1/plan.json').read_text(encoding='utf-8'))['caves'] if c['id']==CAVE)
QA=ROOT/'local/qa'/('cave-'+CAVE);QA.mkdir(parents=True,exist_ok=True)
def surface(name,folder,stem,scale,roughness):
    # Natural tileable surfaces (Codex 305: no masonry, no flat colour): base colour + normal map.
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
ROCK=surface('CV rock','assets/environment/cave-rock-v1','rock_face_03',4,.95)
EARTH=surface('CV earth','assets/environment/village-surfaces-v1','forest_ground_04',3,.98)
def P(x,zs,h):
    return Vector((x,-zs,h))
CHAMBERS=[(c['id'],float(c['x']),float(c['z']),float(c['rx']),float(c['rz']),float(c['floor'])) for c in PLAN['chambers']]
LINKS=[(l['a'],l['b'],float(l['width'])) for l in PLAN['links']]
SEALED=[(l['a'],l['b'],float(l['width'])) for l in PLAN['links'] if str(l.get('kind','')).startswith('завален')]
EXITS=[(e['id'],e['chamber']) for e in PLAN['exits']]
ch={c[0]:c[1:] for c in CHAMBERS}  # id -> (x, z of the scheme, rx, rz, floor)
volumes=[]
# Codex ART-CV-04 (in game: the ways read as straight even tubes, the chambers as regular ovals):
# a chamber is its ellipsoid plus two or three lobes off-centre; a way runs along a bent axis (a
# quadratic curve, up to 4 m aside) with a section that only widens by noise - never under its width
# and headroom, so the capsule's passage holds.
import random
RNG=random.Random(sum(map(ord,CAVE)))
def ellipsoid(name,c,r):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=1,location=c)
    o=bpy.context.active_object;o.name=name;o.scale=r
    bpy.ops.object.transform_apply(scale=True);volumes.append(o)
for cid,x,zs,rx,rz,floor in CHAMBERS:
    H=2.6+0.25*min(rx,rz)
    ellipsoid('chamber '+cid,P(x,zs,floor+H*0.35),(rx,rz,H*0.66))
    for k in range(RNG.choice((2,3))):
        a=RNG.uniform(0,2*math.pi);f=RNG.uniform(0.45,0.7)
        c=P(x+math.cos(a)*rx*0.55,zs+math.sin(a)*rz*0.55,floor+H*RNG.uniform(0.25,0.4))
        ellipsoid('chamber %s lobe %d'%(cid,k),c,(rx*f,rz*f*RNG.uniform(0.8,1.2),H*0.66*RNG.uniform(0.75,0.95)))
def link_axis(a,b):
    """The bent axis of a way, map plane points (x, -z) with floor heights, every ~1 m."""
    xa,zsa,_,_,fa=ch[a];xb,zsb,_,_,fb=ch[b]
    A=Vector((xa,-zsa));B=Vector((xb,-zsb));L=(B-A).length;side=Vector((-(B-A).y,(B-A).x)).normalized()
    amp=min(4.0,L*0.12)*RNG.choice((-1,1))*RNG.uniform(0.5,1.0)
    Cc=(A+B)/2+side*amp
    n=max(8,int(L))
    pts=[]
    for i in range(n+1):
        t=i/n;q=A*(1-t)**2+Cc*2*t*(1-t)+B*t*t
        pts.append((q,fa+(fb-fa)*t))
    return pts
AXES={(a,b):link_axis(a,b) for a,b,w in LINKS}
K=16
for a,b,w in LINKS:
    pts=AXES[(a,b)];h=max(2.4,w*1.1)
    bmt=bmesh.new();rings=[]
    for i,(q,fl) in enumerate(pts):
        j=min(i+1,len(pts)-1);k0=max(i-1,0)
        d=(pts[j][0]-pts[k0][0]).normalized();side=Vector((-d.y,d.x))
        o=Vector((q.x*0.21,q.y*0.21,fl*0.21))+Vector((sum(map(ord,a+b)),0,0))
        # wider than high, as a natural passage (never under the plan's width/headroom)
        ww=w*(1.35+0.6*max(0.0,noise.noise(o)))*0.5+0.3;hh=h*(1.0+0.3*max(0.0,noise.noise(o*1.7)))
        ring=[]
        for m in range(K):
            ang=2*math.pi*m/K;cs,sn=math.cos(ang),math.sin(ang)
            lump=1.0+0.28*max(0.0,noise.noise(o*0.9+Vector((cs*1.5,sn*1.5,0)))) # an uneven vault, outward
            # a rounded vault; the lower half lies flat just under the floor (Codex ART-CV-06: an arc
            # below the floor squashed onto it point by point left thin bent triangles at the wall's foot)
            zz=fl+h*0.42+hh*0.58*sn*lump if sn>0 else fl-0.02
            p2=q+side*(ww*cs*lump)
            ring.append(bmt.verts.new((p2.x,p2.y,zz)))
        rings.append(ring)
    for r0,r1 in zip(rings,rings[1:]):
        for m in range(K):bmt.faces.new((r0[m],r0[(m+1)%K],r1[(m+1)%K],r1[m]))
    bmt.faces.new(rings[0][::-1]);bmt.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bmt,faces=bmt.faces[:])
    o=bpy.data.objects.new('link '+a+'-'+b,bpy.data.meshes.new('link'));bmt.to_mesh(o.data);bmt.free()
    bpy.context.scene.collection.objects.link(o);volumes.append(o)
# Union all volumes into one shell.
base=volumes[0]
for other in volumes[1:]:
    mod=base.modifiers.new('u','BOOLEAN')
    mod.operation='UNION';mod.solver='EXACT';mod.object=other
    bpy.context.view_layer.objects.active=base
    bpy.ops.object.modifier_apply(modifier='u')
    bpy.data.objects.remove(other)
# The walkable top at a point: the highest floor collider over it (chamber discs at .92 of the
# ellipse, link boards w*.95 wide whose top runs fa->fb), else the nearest one's level.
def floor_at(x,y):
    best=None;near=(1e9,0.0)
    for cid,cx,zs,rx,rz,floor in CHAMBERS:
        d=math.hypot((x-cx)/(rx*.92),(y+zs)/(rz*.92))
        if d<=1.0:best=floor if best is None else max(best,floor)
        near=min(near,(d-1.0,floor))
    for a,b,w in LINKS:
        pts=AXES[(a,b)];bd=(1e9,0.0)
        for (q0,f0),(q1,f1) in zip(pts,pts[1:]):
            e=q1-q0;L2=e.length_squared or 1e-9;t=max(0.0,min(1.0,((x-q0.x)*e.x+(y-q0.y)*e.y)/L2))
            dd=math.hypot(x-(q0.x+t*e.x),y-(q0.y+t*e.y))
            if dd<bd[0]:bd=(dd,f0+(f1-f0)*t)
        d=bd[0]/(w*.95/2);h=bd[1]
        if d<=1.0:best=h if best is None else max(best,h)
        near=min(near,(d-1.0,h))
    return near[1] if best is None else best
# Flip normals so the shell is hollow (inner faces visible); then a finer mesh for the rock.
bm=bmesh.new();bm.from_mesh(base.data)
for f in bm.faces:f.normal_flip()
bmesh.ops.triangulate(bm,faces=bm.faces[:])
for _ in range(4):  # only the long edges: the rock needs vertices where the faces are big
    long=[e for e in bm.edges if e.calc_length()>1.8]
    if not long:break
    bmesh.ops.subdivide_edges(bm,edges=long,cuts=1)
    bmesh.ops.triangulate(bm,faces=bm.faces[:])
bm.normal_update()
# Natural shell: the bowl under the walkable level becomes the floor itself (no disc/strip seam:
# floor and wall are one surface), and the walls bulge OUTWARD only by noise, so the passable volume
# the capsule walked (Codex 305) only grows.
moves=[]
for v in bm.verts:
    q=v.co;f=floor_at(q.x,q.y)
    if q.z<=f+0.02:moves.append((v,Vector((q.x,q.y,f))));continue
    t=max(0.0,min(1.0,(q.z-f)/1.2));k=t*t*(3-2*t)   # the wall leaves the floor gently
    # Large slow bulges break the drilled-tube look of the links; fine grain on top; never inward.
    n=noise.noise(q*0.16)*0.45+noise.noise(q*0.5)*0.2+noise.noise(q*1.4)*0.07
    moves.append((v,q-v.normal*max(0.05,0.32+n)*k))
for v,co in moves:v.co=co
# Codex ART-CV-06: thin bent triangles at the walls' foot - slivers of the union, the subdivision and the
# floor's flattening; collapse the degenerate ones and flip edges towards the widest angles
bmesh.ops.dissolve_degenerate(bm,dist=0.05,edges=bm.edges[:])
bmesh.ops.triangulate(bm,faces=bm.faces[:])
bmesh.ops.beautify_fill(bm,faces=bm.faces[:],edges=bm.edges[:])
bm.normal_update()
# Ground where the surface faces up (inward normals), rock elsewhere.
# the slots first: materials.clear() resets every face's index to 0 (Codex ART-CV-03: the whole
# shell exported as rock, its floor's earth lost)
base.data.materials.clear();base.data.materials.append(ROCK);base.data.materials.append(EARTH)
for face in bm.faces:face.material_index=1 if face.normal.z>0.6 else 0
bm.to_mesh(base.data);bm.free()
base.name='cave shell-col'
# bpy.ops puts new objects in the scene's collection; the export takes the ASSET collection's
for o in list(base.users_collection):o.objects.unlink(base)
C.ASSET.objects.link(base)
# Floors: elliptic discs per chamber.
for cid,x,zs,rx,rz,floor in CHAMBERS:
    bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=1,depth=0.3,location=P(x,zs,floor-0.15))
    o=bpy.context.active_object
    o.name='floor '+cid+'-colonly'  # the capsule-tested collider; the visible floor is the shell's
    o.scale=(rx*0.92,rz*0.92,1)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.clear();o.data.materials.append(EARTH)
    C.ASSET.objects.link(o)
# Floors: slanted boards per link.
for a,b,w in LINKS:
    pts=AXES[(a,b)]
    for k,((q0,f0),(q1,f1)) in enumerate(zip(pts,pts[1:])):
        e=(q1-q0).normalized()*0.15   # overlap the pieces so the floor has no seams
        C.beam('floor link %s-%s %d-colonly'%(a,b,k),Vector((q0.x-e.x,q0.y-e.y,f0-0.15)),Vector((q1.x+e.x,q1.y+e.y,f1-0.15)),w*0.95,0.3,EARTH)
# Exits: empty markers on the floor at the exit chamber's edge, away from the chamber it links to;
# +x local points out (the forest cave's E: (-rx+1, 0), facing -x).
for tag,cid in EXITS:
    x,zs,rx,rz,floor=ch[cid]
    other=next(b if a==cid else a for a,b,_ in LINKS if cid in (a,b))
    xo,zso,_,_,_=ch[other]
    d=Vector((x-xo,-(zs-zso),0)).normalized()
    reach=(rx if abs(d.x)>=abs(d.y) else rz)-1.0
    e=bpy.data.objects.new('Exit_'+tag,None)
    e.location=P(x,zs,floor)+Vector((d.x*reach,d.y*reach,0));e.rotation_euler=(0,0,math.atan2(d.y,d.x))
    C.ASSET.objects.link(e)
# Sealed links: a rock fall across the middle, visible and solid (-col), the way beyond kept for later.
for a,b,w in SEALED:
    xa,zsa,_,_,fa=ch[a];xb,zsb,_,_,fb=ch[b]
    q,fm=AXES[(a,b)][len(AXES[(a,b)])//2];mid=Vector((q.x,q.y,fm))
    for k,(dx,dy,r) in enumerate(((0,0,1.5),(.9,.6,1.1),(-.8,-.5,1.2),(.3,-.9,.9),(-.4,.8,1.0))):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=r,location=mid+Vector((dx,dy,r*.55)))
        o=bpy.context.active_object;o.name='rock fall %d-col'%k
        bm=bmesh.new();bm.from_mesh(o.data)
        for v in bm.verts:v.co+=v.co.normalized()*noise.noise(v.co*1.7+Vector((k,0,0)))*.25
        bm.to_mesh(o.data);bm.free()
        o.data.materials.append(ROCK);C.ASSET.objects.link(o)
# The floors made by bpy.ops are in the scene's collection too: only ASSET's.
for o in list(C.ASSET.objects):
    for col in list(o.users_collection):
        if col!=C.ASSET:col.objects.unlink(o)
# UVs (Codex ART-CV-02: the dominant-axis projection stretched the tunnels into rings and cut hard
# stripes where the axis switched): metric and continuous along each way. A link's rock is unwrapped
# round its centre line - u metres along it, v the arc from its crown (the wrap at the bottom, under
# the ground); a chamber's walls round its vertical axis (u arc, v height), its vault and every floor
# face planar from above.
# the ways' bent axes as segments, each with its arc length from the way's start (u runs on)
LINK_LINES=[]
for a,b,w in LINKS:
    h=max(2.4,w*1.1);s0=0.0;pts=AXES[(a,b)]
    for (q0,f0),(q1,f1) in zip(pts,pts[1:]):
        pa=Vector((q0.x,q0.y,f0+h*0.42));pb=Vector((q1.x,q1.y,f1+h*0.42))
        LINK_LINES.append((pa,pb,(w+h)/4,s0));s0+=(pb-pa).length
def _wrap(angles):
    out=[angles[0]]
    for x in angles[1:]:
        while x-out[0]>math.pi:x-=2*math.pi
        while x-out[0]<-math.pi:x+=2*math.pi
        out.append(x)
    return out
for o in [o for o in C.ASSET.objects if o.type=='MESH']:
    if not any(m.get('uv_metres',0) for m in o.data.materials):continue
    bm=bmesh.new();bm.from_mesh(o.data);bm.normal_update()
    uv=bm.loops.layers.uv.get('UVMap') or bm.loops.layers.uv.new('UVMap')
    for face in bm.faces:
        scale=o.data.materials[face.material_index].get('uv_metres',0) or 3
        pts=[o.matrix_world@l.vert.co for l in face.loops]
        c=sum(pts,Vector())/len(pts)
        n=(o.matrix_world.to_3x3()@face.normal).normalized()
        best=min(((math.hypot((c.x-cx)/rx,(c.y+zs)/rz),(cx,-zs,rx,rz,fl)) for _,cx,zs,rx,rz,fl in CHAMBERS),key=lambda t:t[0])
        if abs(n.z)>0.75 or o.name.startswith('floor') or face.material_index==1:
            coords=[(q.x,q.y) for q in pts]
        elif best[0]<1.0:
            # round the ellipsoid as built: u the arc round its axis, v the arc up its meridian
            cx,cy,rx,rz,fl=best[1];H=2.6+0.25*min(rx,rz);cz=fl+H*0.35;rv=H*0.66
            R=(rx+rz)/2;Rm=(R+rv)/2
            ang=_wrap([math.atan2((q.y-cy)/rz,(q.x-cx)/rx) for q in pts])
            el=[math.atan2((q.z-cz)/rv,math.hypot((q.x-cx)/rx,(q.y-cy)/rz)) for q in pts]
            coords=[(a*R,e*Rm) for a,e in zip(ang,el)]
        else:
            def seg_d(L):
                pa,pb,_,_=L;d=pb-pa;t=max(0.0,min(1.0,(c-pa).dot(d)/d.length_squared))
                return (c-(pa+d*t)).length
            pa,pb,R,s0=min(LINK_LINES,key=seg_d)
            d=(pb-pa).normalized();s=d.cross(Vector((0,0,1)))
            s=s.normalized() if s.length>1e-6 else Vector((1,0,0));up=s.cross(d).normalized()
            if up.z<0:up=-up
            tl=[(q-pa).dot(d) for q in pts]
            ang=_wrap([math.atan2((q-pa-d*t).dot(s),(q-pa-d*t).dot(up)) for q,t in zip(pts,tl)])
            coords=[(s0+t,a*R) for t,a in zip(tl,ang)]
        for loop,(u,v) in zip(face.loops,coords):
            loop[uv].uv=(u/scale,v/scale)
    bm.to_mesh(o.data);bm.free()
# Export GLB.
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=next(o for o in C.ASSET.objects if o.type=='MESH')
asset=OUT/(CAVE+'.glb')
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
bpy.ops.wm.save_as_mainfile(filepath=str(QA/(CAVE+'.blend')))
visual=[o for o in C.ASSET.objects if o.type=='MESH' and not o.name.endswith('-colonly')]
triangles=0
earth_faces=sum(1 for o in visual for poly in o.data.polygons if o.data.materials and len(o.data.materials)>poly.material_index and o.data.materials[poly.material_index].name.endswith('earth'))
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'cave':CAVE,'chambers':len(CHAMBERS),'links':len(LINKS),'sealed':[a+'-'+b for a,b,_ in SEALED],'exits':[t for t,_ in EXITS],'triangles':triangles,'earth_faces':earth_faces,'axes':{a+'-'+b:[[round(q.x,2),round(q.y,2),round(f,2)] for q,f in AXES[(a,b)]] for a,b,_ in LINKS},'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
