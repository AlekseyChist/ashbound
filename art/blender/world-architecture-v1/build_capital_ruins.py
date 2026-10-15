"""Capital ruins (book sheet 15, WORLD-PLAN-01): the burnt royal capital on its 128 m terrace; canonical GLB source.

RUINS-01 step 1: the curtain wall - ragged courses 2..5 m, towers about every 34 m, the west (8 m) and
south (10 m) gates between gate towers, the north and east breaches with rubble spilling out.

Frame: origin = the place's point (layout book_places capital_ruins, the terrace's level 128 m);
Blender x = map east (sheet dx), Blender y = -sheet dz (map south is -y), z up. glTF y-up export turns
this into Godot x = dx, z = dz.
Run: blender -b --python art/blender/world-architecture-v1/build_capital_ruins.py [-- preview]
"""
import sys,json,hashlib,math,struct
from pathlib import Path
import bpy,bmesh
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
ARGS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/qa/capital-ruins';QA.mkdir(parents=True,exist_ok=True)
def surface(name,file,scale):
    m=C.mat(name,(1,1,1,1),.96);m['uv_metres']=scale
    tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);tex.image.pack()
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('CR stone','stone_wall_02_diff_1k.jpg',2)
FLAG=surface('CR flags','stone_wall_02_diff_1k.jpg',3.2)
CHAR=surface('CR charred timber','fine_grained_wood_col_1k.jpg',.65)
EARTH=C.mat('CR earth',(.24,.21,.17,1),.98)
SOOT=C.mat('CR soot',(.09,.085,.08,1),.97)
coll=[]
def hsh(*k):
    # a repeatable 0..1 from integers (no random state: the export must not depend on call order)
    h=0
    for v in k:h=(h*1103515245+int(v)*2654435761+12345)&0x7fffffff
    return (h%10007)/10007.0
def blk(n,c,s,m,yaw=0.0,solid=True,tilt=0.0):
    # an unbevelled block centred at c (x,y,z of its middle), size s, turned yaw degrees about z,
    # tipped `tilt` degrees about its own x (fallen stones)
    hx,hy,hz=s[0]/2,s[1]/2,s[2]/2
    rot=Matrix.Rotation(math.radians(yaw),3,'Z')@Matrix.Rotation(math.radians(tilt),3,'X')
    v=[tuple(Vector(c)+rot@Vector((x,y,z))) for z in (-hz,hz) for y in (-hy,hy) for x in (-hx,hx)]
    v=[v[0],v[1],v[3],v[2],v[4],v[5],v[7],v[6]]
    o=C.mesh(n,v,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],m)
    if solid and yaw==0.0 and tilt==0.0:coll.append((n,c,s))
    return o

# --- the curtain wall -------------------------------------------------------------------------------
RING=[(-64,-50),(64,-50),(64,60),(-64,60)]            # sheet (dx,dz), clockwise on the map
THICK=1.6
# per side (from RING[i] to RING[i+1]): openings as (from,to,kind) metres along the side
OPEN={0:[(40,52,'breach')],1:[(70,78,'breach')],2:[(59,69,'gate')],3:[(66,74,'gate')]}
PIECE=2.2
def at(a,b,t):
    # the sheet point t metres from a towards b, in Blender x,y
    L=math.dist(a,b);x=a[0]+(b[0]-a[0])*t/L;z=a[1]+(b[1]-a[1])*t/L
    return x,-z
def wall_height(side,t,L):
    # the ragged crown: slow swells 2.6..4.8 m, each piece +-0.35, dropping into the breaches
    h=3.7+0.8*math.sin(t*.11+side*1.7)+0.4*math.sin(t*.37+side)
    h+=0.35*math.sin(t*1.3+side*2.1)
    for lo,hi,kind in OPEN[side]:
        if kind=='breach':
            d=max(lo-t,t-hi,0.0)
            if d<5.0:h=min(h,0.5+d*0.7)
    return max(0.5,min(5.0,h))
def towers_on(side,L):
    # about every 34 m; none in a breach, none within 9 m of a gate (its own towers flank it)
    n=math.ceil(L/34.0);step=L/n
    out=[]
    for t in [step*k for k in range(n+1)]:
        if any(lo-3<t<hi+3 for lo,hi,kind in OPEN[side] if kind=='breach'):continue
        if any(lo-9<t<hi+9 for lo,hi,kind in OPEN[side] if kind=='gate'):continue
        out.append(t)
    return out
def wedge(n,a,b,thick,ha,hb,m,base=0.0):
    # a wall piece from a to b (Blender x,y) whose crown slopes from ha to hb: the eroded line runs on
    # across the pieces instead of stepping like stacked boxes
    d=Vector((b[0]-a[0],b[1]-a[1],0));side=Vector((-d.y,d.x,0)).normalized()*thick/2
    A=Vector((a[0],a[1],0));B=Vector((b[0],b[1],0))
    up=Vector((0,0,base))
    v=[A-side+up,B-side+up,B+side+up,A+side+up,A-side+Vector((0,0,ha)),B-side+Vector((0,0,hb)),B+side+Vector((0,0,hb)),A+side+Vector((0,0,ha))]
    o=C.mesh(n,[tuple(p) for p in v],[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],m)
    lo=min(ha,hb);c=((a[0]+b[0])/2,(a[1]+b[1])/2,lo/2)
    s=(abs(b[0]-a[0])+(thick if b[1]!=a[1] else 0),abs(b[1]-a[1])+(thick if b[0]!=a[0] else 0),lo)
    if base==0.0:coll.append((n,c,s))
    return o
def tower(n,x,y,seed,size=4.6):
    # a square tower, its upper storey broken: a full block to h1, two corner stubs up to h2
    h1=4.6+1.6*hsh(seed,1);h2=h1+1.2+1.8*hsh(seed,2)
    blk(n,(x,y,h1/2),(size,size,h1),STONE)
    q=size*.38
    for k,(sx,sy) in enumerate(((1,1),(-1,1),(1,-1),(-1,-1))):
        if hsh(seed,10+k)<.45:continue
        hh=h1+(h2-h1)*(.5+.5*hsh(seed,20+k))
        blk(n+' stub',(x+sx*(size-q)/2,y+sy*(size-q)/2,(h1+hh)/2),(q,q,hh-h1),STONE)
    # a plinth course round the foot
    blk(n+' plinth',(x,y,.3),(size+.5,size+.5,.6),STONE)
def rubble(n,x,y,ax,seed,count=7,spread=2.6):
    # fallen blocks: a heap spilling out of a breach or off a broken crown (no colliders: tipped)
    for k in range(count):
        r=spread*(.25+.75*hsh(seed,k,1));a=math.tau*hsh(seed,k,2)
        sx=.5+.5*hsh(seed,k,3);sz=.35+.3*hsh(seed,k,4)
        blk(n,(x+r*math.cos(a)*ax[0],y+r*math.sin(a)*ax[1],sz/2-.05),(sx*1.3,sx,sz),STONE,
            yaw=360*hsh(seed,k,5),solid=False,tilt=18*(hsh(seed,k,6)-.5))
for side in range(4):
    a,b=RING[side],RING[(side+1)%4];L=math.dist(a,b)
    alongx=abs(b[0]-a[0])>0
    t=0.0;k=0
    while t<L-1e-6:
        t1=min(L,t+PIECE)
        mid=(t+t1)/2
        if any(lo<=mid<=hi for lo,hi,kind in OPEN[side] if kind=='gate'):
            t=t1;continue
        if any(lo+1.5<=mid<=hi-1.5 for lo,hi,kind in OPEN[side] if kind=='breach'):
            t=t1;continue
        ha=wall_height(side,t,L);hb=wall_height(side,t1,L)
        # a bite out of the crown now and then: one end of the piece pulled down
        if hsh(side,k,9)<.18:
            if hsh(side,k,10)<.5:ha*=.62
            else:hb*=.62
        wedge('wall %d-%d'%(side,k),at(a,b,t),at(a,b,t1),THICK,ha,hb,STONE)
        x,y=at(a,b,mid)
        # the batter: a plinth course along both faces at the foot
        ps=(t1-t+.02,THICK+.5,.7) if alongx else (THICK+.5,t1-t+.02,.7)
        blk('wall %d-%d plinth'%(side,k),(x,y,.35),ps,STONE,solid=False)
        t=t1;k+=1
    for lo,hi,kind in OPEN[side]:
        x,y=at(a,b,(lo+hi)/2)
        if kind=='breach':
            out=((0,1),(1,0),(0,-1),(-1,0))[side]       # Blender x,y away from the terrace
            rubble('breach %d'%side,x+out[0]*1.5,y+out[1]*1.5,(1,1),side*31,count=14,spread=4.5)
        else:
            for e,t in enumerate((lo-2.3,hi+2.3)):
                tx,ty=at(a,b,t)
                tower('gate %d tower %d'%(side,e),tx,ty,100+side*7+e,size=4.4)
    for e,t in enumerate(towers_on(side,L)):
        if side>0 and t==0:continue           # the corner tower is the previous side's end
        tx,ty=at(a,b,t)
        tower('tower %d-%d'%(side,e),tx,ty,side*13+e)

# --- RUINS-01 step 2: the four ruined buildings of the sheet --------------------------------------
def S(dx,dz):
    # sheet (dx,dz) to Blender x,y
    return (dx,-dz)
def shell(n,cx,cz,w,d,low,high,door,door_w,thick,seed,bays=0.0):
    # four broken walls round a w x d footprint centred at sheet (cx,cz); door: 'N','E','S','W'.
    # bays > 0: window bays of that width (sill 3 m, piers between) on the long sides
    hw,hd=w/2,d/2
    sides={'N':((cx-hw,cz-hd),(cx+hw,cz-hd)),'E':((cx+hw,cz-hd),(cx+hw,cz+hd)),
           'S':((cx+hw,cz+hd),(cx-hw,cz+hd)),'W':((cx-hw,cz+hd),(cx-hw,cz-hd))}
    for si,(key,(a,b)) in enumerate(sides.items()):
        L=math.dist(a,b);k=0;t=0.0
        gap=(L/2-door_w/2,L/2+door_w/2) if key==door else None
        windows=bays>0 and L>w-1e-6
        def hgt(tt):
            h=(low+high)/2+(high-low)/2*math.sin(tt*.21+seed+si*1.3)+.4*math.sin(tt*.9+seed)
            return max(low*.5,min(high,h))
        def pt(tt):
            return S(a[0]+(b[0]-a[0])*tt/L,a[1]+(b[1]-a[1])*tt/L)
        if windows:
            # window bays: a pier 1.3 m to the crown, then the opening - the wall under its sill (3 m) and,
            # where the crown still stands over the window's head (7.8 m), the wall above it
            nb=max(1,round(L/bays));bl=L/nb
            def part(nm,u0,u1,ha=None,hb=None,base=0.0):
                # a stretch u0..u1 of the side, cut round the door's opening (its head 4.2 m over the floor)
                spans=[(u0,u1)]
                if gap:
                    spans=[(x0,x1) for x0,x1 in ((u0,min(u1,gap[0])),(max(u0,gap[1]),u1)) if x1-x0>.05]
                    if base<4.2 and u1>gap[0] and u0<gap[1] and (ha is None):
                        x0,x1=max(u0,gap[0]),min(u1,gap[1])
                        if x1-x0>.05 and min(hgt(x0),hgt(x1))>5.0:
                            wedge(nm+' over door',pt(x0),pt(x1),thick,hgt(x0),hgt(x1),STONE,base=4.2)
                for x0,x1 in spans:
                    wedge(nm,pt(x0),pt(x1),thick,hgt(x0) if ha is None else ha,hgt(x1) if hb is None else hb,STONE,base=base)
            for j in range(nb):
                t0=j*bl;tp=t0+1.3;t1=t0+bl
                part('%s %s-pier%d'%(n,key,j),t0,tp)
                part('%s %s-sill%d'%(n,key,j),tp,t1,3.0,3.0)
                if min(hgt(tp),hgt(t1))>8.4:
                    wedge('%s %s-head%d'%(n,key,j),pt(tp),pt(t1),thick,hgt(tp),hgt(t1),STONE,base=7.8)
            # the last pier closes the side at its far corner
            part('%s %s-pier%d'%(n,key,nb),L-1.3,L)
        while not windows and t<L-1e-6:
            t1=min(L,t+1.8)
            if gap and gap[0]<(t+t1)/2<gap[1]:t=t1;continue
            wedge('%s %s-%d'%(n,key,k),pt(t),pt(t1),thick,hgt(t),hgt(t1),STONE)
            t=t1;k+=1
        if gap:
            # the door's jambs stand a little prouder and taller than the wall beside them
            for e,tt in enumerate(gap):
                q=(a[0]+(b[0]-a[0])*tt/L,a[1]+(b[1]-a[1])*tt/L)
                hj=min(high,low+1.2+1.5*hsh(seed,si,e))
                blk('%s door jamb'%n,(*S(*q),hj/2),(thick+.4,thick+.4,hj),STONE)
    # the floor: a flagged slab, sooted where the roof burnt down onto it
    blk(n+' floor',(*S(cx,cz),.06),(w-thick,d-thick,.12),FLAG,solid=False)
    for k in range(4):
        r=.25+.5*hsh(seed,k,3)
        blk(n+' soot',(*S(cx+(hsh(seed,k,1)-.5)*w*.6,cz+(hsh(seed,k,2)-.5)*d*.6),.125),(w*r*.5,d*r*.5,.01),SOOT,solid=False)
    # fallen roof timbers, charred, lying across the floor
    for k in range(3):
        x0=cx+(hsh(seed,k,4)-.5)*w*.6;z0=cz+(hsh(seed,k,5)-.5)*d*.6
        blk(n+' beam',(*S(x0,z0),.3),(min(w,d)*.6,.32,.32),CHAR,yaw=180*hsh(seed,k,6),solid=False,tilt=6*(hsh(seed,k,7)-.5))
# the cathedral - the throne hall (Сб): 36 x 20, door to the street on the south
shell('cathedral',22,-22,36,20,5.0,11.0,'S',4.0,1.3,10,bays=4.5)
for k in range(9):
    # buttresses along the long sides, outside, each against a pier (none in front of the south door)
    x=4+.65+k*4.5 if k<8 else 40-.65
    for zz,sg in ((-32,-1),(-12,1)):
        if sg>0 and 20-.8<x<24+.8:continue
        hb=3.5+4.0*hsh(11,k,zz)
        blk('cathedral buttress',(*S(x,zz+sg*1.1),hb/2),(1.2,1.6,hb),STONE)
# the dais at the east end (three steps), the throne's plinth on it, the rod's niche in the east wall
INNER_E=40-1.3/2
for st in range(3):
    dep=6.0-1.6*st
    blk('cathedral dais',(*S(INNER_E-dep/2,-22),.2+.4*st),(dep,9-2*st,.4),FLAG)
blk('cathedral throne plinth',(*S(INNER_E-1.0,-22),1.2+.3),(1.4,1.8,.6),STONE)
blk('cathedral niche',(*S(INNER_E-.02,-25.5),2.6),(.04,1.0,1.8),SOOT,solid=False)
# the collapsed vault over the crown's place: a heap of masonry against the dais
rubble('cathedral collapse',*S(33,-26),(1,1),77,count=18,spread=3.6)
# the rite's circle on the floor: a ring of flat set stones
for k in range(16):
    a=math.tau*k/16
    blk('cathedral rite stone',(*S(16+3.2*math.cos(a),-22+3.2*math.sin(a)),.14),(.7,.45,.06),FLAG,yaw=math.degrees(a)+90,solid=False)
# the archive (Ар): 16 x 10, door north to the street, the scribe's cellar hatch in its floor
shell('archive',-34,20,16,10,2.5,4.5,'N',3.0,1.0,20)
blk('archive hatch frame',(*S(-38,22),.16),(2.2,1.6,.1),CHAR,solid=False)
blk('archive hatch dark',(*S(-38,22),.165),(1.7,1.1,.1),SOOT,solid=False)
portal=bpy.data.objects.new('CellarPortal',None);C.ASSET.objects.link(portal)
portal.location=(*S(-38,22),.2);portal['target']='ruins_archive_cellar'
# the mint (Мд): 14 x 9, door west
shell('mint',40,26,14,9,2.5,4.5,'W',3.0,1.0,30)
for k in range(2):
    blk('mint press base',(*S(42+k*3,26),.45),(1.4,1.4,.9),STONE)
# the royal kennel (Пс): 12 x 8, door south, the pack's lair: earth floor, straw and gnawed bones later
shell('kennel',-40,-32,12,8,2.0,3.5,'S',2.6,.9,40)
blk('kennel earth',(*S(-40,-32),.13),(10.5,6.5,.02),EARTH,solid=False)
# the street from the west gate to the south gate: broken paving, 4 m wide, in patches
ROUTE=[(-64,-10),(-20,-4),(10,10),(0,60)]
for i in range(len(ROUTE)-1):
    a,b=ROUTE[i],ROUTE[i+1];L=math.dist(a,b);n=int(L/2.4)
    yaw=math.degrees(math.atan2(-(b[1]-a[1]),b[0]-a[0]))
    for k in range(n):
        if hsh(i,k,50)<.22:continue                 # a gap: the paving taken or grown over
        t=(k+.5)/n;x=a[0]+(b[0]-a[0])*t;z=a[1]+(b[1]-a[1])*t
        blk('street paving',(*S(x,z),.05),(2.3,3.6+.6*hsh(i,k,51),.1),FLAG,yaw=yaw,solid=False)

# --- export ------------------------------------------------------------------------------------------
visual=[o for o in C.ASSET.objects if o.type=='MESH']
for o in visual:
    scale=o.data.materials[0].get('uv_metres',0)
    if not scale:continue
    bm=bmesh.new();bm.from_mesh(o.data);bm.normal_update()
    uv=bm.loops.layers.uv.get('UVMap') or bm.loops.layers.uv.new('UVMap')
    rot=o.matrix_world.to_3x3()
    for face in bm.faces:
        nrm=rot@face.normal
        axis=max(range(3),key=lambda i:abs(nrm[i]))
        for loop in face.loops:
            p=o.matrix_world@loop.vert.co
            u,v=((p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y))
            loop[uv].uv=(u/scale,v/scale)
    bm.to_mesh(o.data);bm.free()
C._join_by_material(visual)
for n,p,s in coll:C.box(n+'-colonly',p,s,STONE,0).hide_render=True
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=next(o for o in C.ASSET.objects if o.type=='MESH')
asset=OUT/'capital_ruins.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_extras=True,export_yup=True,export_lights=False,export_cameras=False)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];document=json.loads(data[20:20+size])
# burnt capital stone: grey with a cold cast, not the desert's ochre
tints={'CR stone':(.66,.63,.58),'CR flags':(.62,.60,.56),'CR charred timber':(.30,.26,.22)}
for material in document['materials']:
    if material['name'] in tints:material['pbrMetallicRoughness']['baseColorFactor']=[*tints[material['name']],1]
encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
tail=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
triangles=0
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
points=[o.matrix_world@Vector(v) for o in visual for v in o.bound_box]
(QA/'stats.json').write_text(json.dumps({'state':'RUINS-01 steps 1-2 wall, four ruined buildings, street; Codex review pending','triangles':triangles,'colliders':len(coll),
    'bbox':[[round(min(p[i] for p in points),3) for i in range(3)],[round(max(p[i] for p in points),3) for i in range(3)]],
    'sha256':hashlib.sha256(asset.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
if 'preview' in ARGS:
    scene=bpy.context.scene
    for eng in ('BLENDER_EEVEE','BLENDER_EEVEE_NEXT'):
        try:scene.render.engine=eng;break
        except TypeError:pass
    scene.render.resolution_x,scene.render.resolution_y=1600,900
    ground=C.mesh('ground',[(-90,-80,0),(90,-80,0),(90,80,0),(-90,80,0)],[(0,1,2,3)],C.mat('G',(.32,.33,.27,1),.95))
    for o in C.ASSET.objects:
        if '-colonly' in o.name:o.hide_render=True
    sun=bpy.data.objects.new('Sun',bpy.data.lights.new('Sun','SUN'));sun.data.energy=3.5
    sun.rotation_euler=(math.radians(50),0,math.radians(-35));scene.collection.objects.link(sun)
    world=bpy.data.worlds.new('W');scene.world=world;world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.55,.62,.7,1)
    for k,(loc,look) in enumerate((((-95,-110,55),(0,0,0)),((2,8,8),(30,26,3)),((80,70,40),(0,0,0)),((14,-6,3),(24,22,5)))):
        cam=bpy.data.objects.new('Cam%d'%k,bpy.data.cameras.new('Cam%d'%k));cam.data.lens=28
        scene.collection.objects.link(cam);cam.location=loc
        cam.rotation_mode='QUATERNION';cam.rotation_quaternion=(Vector(look)-Vector(loc)).to_track_quat('-Z','Y')
        scene.camera=cam;scene.render.filepath=str(QA/('preview-%d.png'%k))
        bpy.ops.render.render(write_still=True)
print('CAPITAL_RUINS',json.dumps(json.loads((QA/'stats.json').read_text())))
