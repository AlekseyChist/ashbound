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
# Chambers: UV spheres, bottom 0.31H below floor, top H above floor.
for cid,x,zs,rx,rz,floor in CHAMBERS:
    H=2.6+0.25*min(rx,rz)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=16,radius=1,location=P(x,zs,floor+H*0.35))
    o=bpy.context.active_object
    o.name='chamber '+cid
    o.scale=(rx,rz,H*0.66)
    bpy.ops.object.transform_apply(scale=True)
    volumes.append(o)
# Links: cylinders between chamber centres, axis Z along the link.
for a,b,w in LINKS:
    xa,zsa,_,_,fa=ch[a];xb,zsb,_,_,fb=ch[b]
    h=max(2.4,w*1.1)
    pa=P(xa,zsa,fa+h*0.42);pb=P(xb,zsb,fb+h*0.42)
    L=(pb-pa).length
    bpy.ops.mesh.primitive_cylinder_add(vertices=20,radius=0.5,depth=1.0)
    o=bpy.context.active_object
    o.name='link '+a+'-'+b
    o.scale=(w,h,L)
    direction=(pb-pa).normalized()
    o.rotation_mode='QUATERNION'
    o.rotation_quaternion=direction.to_track_quat('Z','Y')
    o.location=(pa+pb)/2
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    volumes.append(o)
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
        xa,zsa,_,_,fa=ch[a];xb,zsb,_,_,fb=ch[b]
        ax,ay,bx,by=xa,-zsa,xb,-zsb;L2=(bx-ax)**2+(by-ay)**2
        t=max(0.0,min(1.0,((x-ax)*(bx-ax)+(y-ay)*(by-ay))/L2))
        d=math.hypot(x-(ax+t*(bx-ax)),y-(ay+t*(by-ay)))/(w*.95/2)
        h=fa+t*(fb-fa)
        if d<=1.0:best=h if best is None else max(best,h)
        near=min(near,(d-1.0,h))
    return near[1] if best is None else best
# Flip normals so the shell is hollow (inner faces visible); then a finer mesh for the rock.
bm=bmesh.new();bm.from_mesh(base.data)
for f in bm.faces:f.normal_flip()
bmesh.ops.triangulate(bm,faces=bm.faces[:])
bmesh.ops.subdivide_edges(bm,edges=bm.edges[:],cuts=1,use_grid_fill=True)
bmesh.ops.triangulate(bm,faces=bm.faces[:])
bm.normal_update()
# Natural shell: the bowl under the walkable level becomes the floor itself (no disc/strip seam:
# floor and wall are one surface), and the walls bulge OUTWARD only by noise, so the passable volume
# the capsule walked (Codex 305) only grows.
moves=[]
for v in bm.verts:
    q=v.co;f=floor_at(q.x,q.y)
    if q.z<=f+0.02:moves.append((v,Vector((q.x,q.y,f))));continue
    k=min(1.0,(q.z-f)/0.8)
    # Large slow bulges break the drilled-tube look of the links; fine grain on top; never inward.
    n=noise.noise(q*0.16)*0.45+noise.noise(q*0.5)*0.2+noise.noise(q*1.4)*0.07
    moves.append((v,q-v.normal*max(0.05,0.32+n)*k))
for v,co in moves:v.co=co
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
    xa,zsa,_,_,fa=ch[a];xb,zsb,_,_,fb=ch[b]
    C.beam('floor link '+a+'-'+b+'-colonly',P(xa,zsa,fa-0.15),P(xb,zsb,fb-0.15),w*0.95,0.3,EARTH)
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
    mid=(P(xa,zsa,fa)+P(xb,zsb,fb))/2
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
LINK_LINES=[]
for a,b,w in LINKS:
    xa,zsa,_,_,fa=ch[a];xb,zsb,_,_,fb=ch[b];h=max(2.4,w*1.1)
    LINK_LINES.append((P(xa,zsa,fa+h*0.42),P(xb,zsb,fb+h*0.42),(w+h)/4))
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
                pa,pb,_=L;d=pb-pa;t=max(0.0,min(1.0,(c-pa).dot(d)/d.length_squared))
                return (c-(pa+d*t)).length
            pa,pb,R=min(LINK_LINES,key=seg_d)
            d=(pb-pa).normalized();s=d.cross(Vector((0,0,1)))
            s=s.normalized() if s.length>1e-6 else Vector((1,0,0));up=s.cross(d).normalized()
            if up.z<0:up=-up
            tl=[(q-pa).dot(d) for q in pts]
            ang=_wrap([math.atan2((q-pa-d*t).dot(s),(q-pa-d*t).dot(up)) for q,t in zip(pts,tl)])
            coords=[(t,a*R) for t,a in zip(tl,ang)]
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
(QA/'stats.json').write_text(json.dumps({'cave':CAVE,'chambers':len(CHAMBERS),'links':len(LINKS),'sealed':[a+'-'+b for a,b,_ in SEALED],'exits':[t for t,_ in EXITS],'triangles':triangles,'earth_faces':earth_faces,'bbox':[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]],'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
