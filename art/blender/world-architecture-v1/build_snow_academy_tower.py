"""PDF141 bounded repaired Conclave tower; heights are design choices, not book canon.
Blender Z-up -> Godot Y-up. All diagnostic outputs stay in ignored local/.
"""
import sys, math, json, struct, hashlib
sys.dont_write_bytecode=True
from pathlib import Path
import bpy, bmesh
from mathutils import Vector, Matrix
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT = ROOT/'assets/buildings/world-architecture-v1'; OUT.mkdir(parents=True,exist_ok=True)
QA = ROOT/'local/qa/snow-academy-tower/r2'; QA.mkdir(parents=True,exist_ok=True)

def surface(name,filename,metres):
    m=C.mat(name,(1,1,1,1),.96); m['uv_metres']=metres
    im=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/filename),check_existing=True); im.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=im
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m
STONE=surface('ST cool stone','stone_wall_02_diff_1k.jpg',2)
PLASTER=surface('ST grey limewash','plaster_grey_04_diff_1k.jpg',3)
WOOD=surface('ST dark timber','fine_grained_wood_col_1k.jpg',.65)
IRON=C.mat('ST iron',(.07,.075,.078,1),.85)
LINEN=C.mat('ST woven teal',(.14,.23,.24,1),.98)
CLOTH=C.mat('ST warm linen',(.35,.31,.23,1),.98)
CLAY=C.mat('ST fired clay',(.27,.24,.20,1),.97)
BOOK=C.mat('ST leather books',(.16,.115,.07,1),.97)
SLATE=C.mat('ST slate',(.10,.135,.15,1),.95); SLATE['uv_metres']=.65
im=bpy.data.images.new('ST slate paint',width=256,height=256)
px=[]
for y in range(256):
    for x in range(256):
        v=.022*math.sin(x*.039+y*.023)+.012*math.sin(y*.073-x*.013)
        px.extend([max(0,min(1,t+v)) for t in (.10,.135,.15)]+[1])
im.pixels.foreach_set(px); im.pack()
tex=SLATE.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
SLATE.node_tree.links.new(tex.outputs['Color'],SLATE.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
visual=[]; furniture=[]; doors=[]; collision=[]

def collider(o):
    q=o.copy();q.data=o.data.copy();q.name=o.name+'-colonly';C.ASSET.objects.link(q)
    q.matrix_world=o.matrix_basis if o.parent is None else o.parent.matrix_world @ o.matrix_basis
    q.hide_render=True;collision.append(q)
def keep(o,solid=False,role=''):
    visual.append(o)
    if role:o['part_role']=role;furniture.append(o)
    if solid:collider(o)
    return o

def box(n,p,s,m=WOOD,solid=False,role='',bevel=0):
    if bevel:
        return keep(C.box(n,p,s,m,bevel),solid,role)
    # Direct cuboid mesh avoids hundreds of context-dependent operators.
    x,y,z=p;a,b,c=[v*.5 for v in s]
    verts=[(dx*a,dy*b,dz*c) for dx,dy,dz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    o=C.mesh(n,verts,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],m)
    o.location=p
    return keep(o,solid,role)
def beam(n,a,b,w=.10,d=.14,m=WOOD,solid=False):
    a,b=Vector(a),Vector(b);v=b-a
    o=box(n,(a+b)/2,(w,d,max(.001,v.length)),m)
    o.rotation_mode='QUATERNION';o.rotation_quaternion=v.to_track_quat('Z','Y')
    if solid:collider(o)
    return o
def mesh(n,v,f,m,solid=False,role=''):
    return keep(C.mesh(n,v,f,m),solid,role)
def prop(n,p,s,m=WOOD,solid=False):
    return box(n,p,s,m,solid,'interior_furniture',.015)
def empty(n,p=(0,0,0),angle=0,parent=None):
    o=bpy.data.objects.new(n,None);C.ASSET.objects.link(o);o.location=p;o.rotation_euler.z=angle;o.parent=parent;return o

def subtract_rect(rect,cut):
    a,b,c,d=rect;e,f,g,h=cut
    if f<=a or e>=b or h<=c or g>=d:return [rect]
    e=max(a,e);f=min(b,f);g=max(c,g);h=min(d,h)
    return [r for r in [(a,e,c,d),(f,b,c,d),(e,f,c,g),(e,f,h,d)] if r[1]-r[0]>.001 and r[3]-r[2]>.001]
def panels(rect,cuts):
    pieces=[rect]
    for cut in cuts:pieces=[part for piece in pieces for part in subtract_rect(piece,cut)]
    return pieces
FLUE=(-4.2,-3.4,2.4,3.2)
HOLE=(1.7,4.85,-2,2.3)
LEVELS=[round(3.6*k,1) for k in range(8)]
SERVICE=25.2
REPAIR=28.8

def slab(n,h,rect=(-5.1,5.1,-5.1,5.1),cuts=(),m=STONE):
    for a,b,c,d in panels(rect,cuts):box(n,((a+b)/2,(c+d)/2,h-.12),(b-a,d-c,.24),m,True)

def wall(n,axis,fixed,a,b,bottom,top,holes=(),m=STONE,thickness=.4):
    for lo,hi,z0,z1 in panels((a,b,bottom,top),holes):
        p=((lo+hi)/2,fixed,(z0+z1)/2) if axis=='x' else (fixed,(lo+hi)/2,(z0+z1)/2)
        size=(hi-lo,thickness,z1-z0) if axis=='x' else (thickness,hi-lo,z1-z0)
        box(n,p,size,m,True)
slab('tower stone foundation',0,(-5.5,5.5,-5.5,5.5))
for h in LEVELS[1:]:slab('occupied floor' if h<10.8 else 'service floor',h,cuts=(HOLE,FLUE),m=WOOD if h<10.8 else STONE)
for h in (0,3.6,7.2):box('lamp fixing cleat',(-1,0,h+3.345),(.20,.20,.03),WOOD)
box('Eldren lamp fixing cleat',(-3,0,10.545),(.20,.20,.03),WOOD)
# All exterior walls are old masonry, not residential half-timber.
for h in LEVELS:
    top=h+3.6 if h<SERVICE else 27.8
    wide=h<10.8
    mids={'south':-3.3 if wide else 0,'north':-.7 if wide else 0,'west':-2.2 if wide else 0,'east':3.5 if wide else 0}
    # A window behind this level's outer flight moves to the flight's low end (Codex 176/2: the
    # stair crossed the north opening at 3.6; the narrow service lights sat behind theirs too).
    side={0:('east',-2.2),1:('north',2.2),2:('west',2.2),3:('south',-2.2)}.get(round(h/3.6)%4)
    if side and abs(mids[side[0]])<=3:mids[side[0]]=side[1]
    half=.5 if wide else .35;lo=h+1.15 if wide else h+1.4;hi=h+2.5 if wide else min(top,h+2.5)
    front=[(mids['south']-half,mids['south']+half,lo,hi)]
    if h==0:front.append((-.8,.8,0,2.5))
    rear=[(mids['north']-half,mids['north']+half,lo,hi)]
    west=[(mids['west']-half,mids['west']+half,lo,hi)]
    if h==7.2:west.append((-.6,.6,8.2,9.2))
    east=[(mids['east']-half,mids['east']+half,lo,hi)]
    if h==SERVICE:east=[(-2.9,-1.3,SERVICE,SERVICE+2.5)]
    for n,axis,fixed,a,b,holes in [('south','x',-5.3,-5.5,5.5,front),('north','x',5.3,-5.5,5.5,rear),('west','y',-5.3,-5.1,5.1,west),('east','y',5.3,-5.1,5.1,east)]:wall(n+' old masonry',axis,fixed,a,b,h,top,holes)
    # Narrow service lights and deep lower windows have masonry frames.
    for fixed,mid,axis in [(-5.3,mids['south'],'x'),(5.3,mids['north'],'x'),(-5.3,mids['west'],'y'),(5.3,mids['east'],'y')]:
        if fixed==5.3 and axis=='y' and h==SERVICE:continue
        w=1.0 if h<10.8 else .7;lo=h+1.15 if h<10.8 else h+1.4;hi=h+2.5
        for u in (mid-w/2-.055,mid+w/2+.055):
            p=(u,fixed,(lo+hi)/2) if axis=='x' else (fixed,u,(lo+hi)/2)
            size=(.11,.54,hi-lo+.22) if axis=='x' else (.54,.11,hi-lo+.22)
            box('carved stone window jamb',p,size,STONE)
        for z in (lo-.06,hi+.06):
            p=(mid,fixed,z) if axis=='x' else (fixed,mid,z)
            size=(w+.32,.60,.12) if axis=='x' else (.60,w+.32,.12)
            box('stone window sill and lintel',p,size,STONE)
        p=(mid,fixed,(lo+hi)/2) if axis=='x' else (fixed,mid,(lo+hi)/2)
        box('iron window divider',p,(.035,.08,hi-lo) if axis=='x' else (.08,.035,hi-lo),IRON)
# Preserve the architectural stash entirely within the west wall.
box('Eldren niche backing',(-5.45,0,8.7),(.10,1.2,1),STONE,True)
for y in (-.63,.63):box('niche carved cheek',(-5.25,y,8.7),(.4,.06,1.12),STONE)
for z in (8.17,9.23):box('niche stone shelf',(-5.25,0,z),(.4,1.32,.06),STONE)
prop('niche folded document',(-5.28,0,8.235),(.16,.35,.06),CLOTH)
# The old recess backing is framed externally and weather-tight.
# The actual open service vent is separately louvred on the north wall.
for y in (-.70,.70):box('vent stone jamb',(-5.56,y,8.70),(.16,.12,1.22),STONE)
for z in (8.12,9.28):box('vent sill lintel',(-5.56,0,z),(.22,1.52,.12),STONE)
for z in (8.27,8.47,8.67,8.87,9.07):
    o=box('repaired backing grille',(-5.63,0,z),(.13,1.25,.08),IRON)
    o.rotation_euler.y=math.radians(22)
for z in (26.72,26.94,27.16,27.38,27.60):
    o=box('open service rain louvre',(0,5.37,z),(.7,.22,.07),IRON)
    o.rotation_euler.x=math.radians(-23)
# One cell beacon, physically in the south window, independent of furniture culling.
GLASS=C.mat('ST cell warm glass',(.18,.11,.04,1),.95)
glass=box('Eldren warm window',(-3.3,-5.37,9.025),(.98,.015,1.32),GLASS)
glass['part_role']='cell_window'
for z in (8.62,9.06,9.50):box('cell window iron grille',(-3.3,-5.59,z),(.99,.035,.025),IRON)
# Stone quoins and sparse string courses give vertical mass, not timber framing.
for x in (-5.35,5.35):
    for y in (-5.35,5.35):
        for k in range(42):
            z=.35+k*.66
            box('alternating masonry quoin',(x,y,z),(.50 if k%2 else .63,.63 if k%2 else .50,.58),STONE)
for h in (0.21,10.8,21.6,27.65):
    for y in (-5.52,5.52):box('masonry string course',(0,y,h),(11.12,.14,.20 if h else .42),STONE)
    for x in (-5.52,5.52):box('masonry side string course',(x,0,h),(.14,11.12,.20),STONE)
# Shared .42m base belt, with the main door kept clear.
for a,b in [(-5.5,-.8),(.8,5.5)]:box('south .42 foundation belt',((a+b)/2,-5.54,.21),(b-a,.12,.42),STONE)
for fixed,axis in [(5.54,'x'),(-5.54,'y'),(5.54,'y')]:
    box('old .42 foundation belt',(0,fixed,.21) if axis=='x' else (fixed,0,.21),(11,.12,.42) if axis=='x' else (.12,11,.42),STONE)
slab('dry stone threshold',0,(-1.3,1.3,-7,-5.5))
# Entry has a masonry hood, no permanent residential wooden porch.
box('entry arch spring left',(-1,-5.65,2.7),(.35,.55,.40),STONE)
box('entry arch spring right',(1,-5.65,2.7),(.35,.55,.40),STONE)
box('entry protective stone hood',(0,-5.9,2.95),(2.5,.95,.22),STONE)

# Closed solid ramp prisms and continuous stone parapets are shared by all stairs.
def prism(n,a,b,h0,h1,width,thickness,m=STONE,solid=True,base=None):
    av,bv=Vector(a),Vector(b);along=(bv-av).normalized();side=Vector((-along.y,along.x))*width/2
    xy=[av-side,av+side,bv+side,bv-side]
    v=[(p.x,p.y,h0 if i<2 else h1) for i,p in enumerate(xy)]
    v += [(p.x,p.y,(h0 if i<2 else h1)-thickness if base is None else base) for i,p in enumerate(xy)]
    return mesh(n,v,[tuple(reversed(f)) for f in [(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]],m,solid)
def stone_guard(n,a,b,h0,h1=None,width=.14):
    if h1 is None:h1=h0
    prism(n,a,b,h0+1.05,h1+1.05,width,1.05,STONE,True)
def repair_guard(n,a,b,h):
    beam(n+' repair handrail',(*a,h+1.05),(*b,h+1.05),.08,.09,WOOD,True)
    beam(n+' repair midrail',(*a,h+.45),(*b,h+.45),.07,.08,WOOD,True)
    length=math.dist(a,b);count=max(1,math.ceil(length/1.4))
    pts=[]
    for k in range(count+1):
        t=k/count;pts.append((a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t))
    for k,(x,y) in enumerate(pts):
        box(n+' repair baluster',(x,y,h+.525),(.07,.07,1.05),WOOD,True)
        box(n+' scaffold pole top',(x,y,h+1.20),(.08,.08,.30),WOOD)
        box(n+' rope lashing',(x,y,h+1.05),(.13,.13,.06),WOOD)
    for k in range(count):
        x0,y0=pts[k];x1,y1=pts[k+1]
        if k%2:beam(n+' repair brace',(x1,y1,h+.10),(x0,y0,h+1.0),.06,.06,WOOD)
        else:beam(n+' repair brace',(x0,y0,h+.10),(x1,y1,h+1.0),.06,.06,WOOD)
def internal_stairs(h):
    for k in range(10):
        box('old internal first step',(2.5,-2+(k+.5)*.3,h+(k+1)*.18-.06),(1.35,.3,.12),STONE)
        box('old internal second step',(4.05,1-(k+.5)*.3,h+1.8+(k+1)*.18-.06),(1.35,.3,.12),STONE)
    prism('first masonry flight',(2.5,-2),(2.5,1),h,h+1.8,1.35,.25)
    prism('second masonry flight',(4.05,1),(4.05,-2),h+1.8,h+3.6,1.35,.25)
    slab('internal turn',h+1.8,(1.77,4.78,1,2.3))
    box('central masonry stair spine',(3.275,-.5,h+1.8),(.16,3,3.6),STONE,True)
    stone_guard('lower flight west',(1.75,-2),(1.75,1),h,h+1.8)
    stone_guard('upper flight east',(4.8,1),(4.8,-2),h+1.8,h+3.6)
    for x in (1.7,4.85):stone_guard('upper hole edge',(x,-2),(x,2.3),h+3.6)
    stone_guard('upper hole rear',(1.7,2.3),(4.85,2.3),h+3.6)
    stone_guard('turn rear',(1.77,2.3),(4.78,2.3),h+1.8)
    for x in (1.77,4.78):stone_guard('turn cheek',(x,1),(x,2.3),h+1.8)
    for x in (2.0,4.6):box('turn masonry support',(x,2.05,h+.85),(.30,.30,1.7),STONE,True)
for h in LEVELS[:-1]:internal_stairs(h)
# Medieval cantilevers: wedges keyed .25m into the wall, never a freestanding cage.
def corbel(n,face,u,h,reach=7.0,solid=True):
    v=[(5.25,u-.18,h-.9),(5.25,u+.18,h-.9),(5.25,u-.18,h-.24),(5.25,u+.18,h-.24),(reach,u-.18,h-.24),(reach,u+.18,h-.24)]
    angle=face*math.pi/2
    verts=[(x*math.cos(angle)-y*math.sin(angle),x*math.sin(angle)+y*math.cos(angle),z) for x,y,z in v]
    mesh(n,verts,[tuple(reversed(f)) for f in [(0,1,3,2),(0,2,4),(1,5,3),(2,3,5,4),(0,4,5,1)]],STONE,solid)
FACES=[((6.25,-3),(6.25,3)),((3,6.25),(-3,6.25)),((-6.25,3),(-6.25,-3)),((-3,-6.25),(3,-6.25))]
CORNERS=[(6.25,6.25),(-6.25,6.25),(-6.25,-6.25),(6.25,-6.25)]
def outer_flight(k):
    a,b=map(Vector,FACES[k%4]);h=round(k*3.6,1);along=(b-a).normalized()
    for step in range(20):
        p=a+along*(step+.5)*.30
        box('cantilever stone tread',(p.x,p.y,h+(step+1)*.18-.065),(1.35,.30,.13) if k%2==0 else (.30,1.35,.13),STONE)
    prism('wall borne exterior flight',a,b,h,h+3.6,1.35,.30,base=h-.24 if k==7 else None)
    # Outward parapet is a single masonry wall following the slope.
    outward=Vector((a.x+b.x,a.y+b.y)).normalized()*.77
    stone_guard('sloping exterior parapet',a+outward,b+outward,h,h+3.6,.18)
    for step in (1,6,11,16,19):
        p=a+along*(step*.30);u=p.y if k%4==0 else -p.x if k%4==1 else -p.y if k%4==2 else p.x
        corbel('flight load corbel',k%4,u,h+step*.18)
    c=Vector(CORNERS[k%4]);nxt=Vector(FACES[(k+1)%4][0]);level=h+3.6
    if level>=SERVICE-.01:return
    # L-shaped corner deck stays outside both masonry faces.
    sx=1 if c.x>0 else -1;sy=1 if c.y>0 else -1
    def rect(xs,ys):return (min(xs),max(xs),min(ys),max(ys))
    slab('wall corner turn',level,rect([sx*5.5,sx*7],[b.y,c.y+sy*.75])) if k%2==0 else slab('wall corner turn',level,rect([b.x,c.x+sx*.75],[sy*5.5,sy*7]))
    slab('corner continuation',level,rect([nxt.x,sx*5.5],[sy*5.5,sy*7])) if k%2==0 else slab('corner continuation',level,rect([sx*5.5,sx*7],[nxt.y,sy*5.5]))
    if k%2==0:
        stone_guard('corner outside eastwest',(sx*7,b.y),(sx*7,sy*7),level)
        stone_guard('corner outside northsouth',(sx*7,sy*7),(nxt.x,sy*7),level)
    else:
        stone_guard('corner outside northsouth',(b.x,sy*7),(sx*7,sy*7),level)
        stone_guard('corner outside eastwest',(sx*7,sy*7),(sx*7,nxt.y),level)
    corbel('corner wall corbel',k%4,4.7,level)
    corbel('corner next face corbel',(k+1)%4,-4.7,level)
for k in range(8):outer_flight(k)
# Horizontal masonry service ring and a temporary upper repair gallery.
def ring(h,repair=False):
    m=WOOD if repair else STONE
    for x in (-6.25,6.25):
        if not repair and x<0:
            for a,b in [(-7,-3),(3,7)]:slab('service stair opening cheek',h,(-7,-5.5,a,b))
            slab('wall borne service bypass',h,(-8,-7.1,-7,7))
            box('bypass longitudinal masonry bearer',(-7.55,0,h-.62),(.9,9,.76),STONE,True)
            for a,b in [(-7,-3),(3,7)]:slab('bypass corner connection',h,(-8,-7,a,b))
            stone_guard('bypass outer parapet',(-8.05,-7),(-8.05,7),h)
            stone_guard('bypass stair well cheek',(-7.08,-3),(-7.08,3),h,width=.12)
            for y in (-7,7):stone_guard('bypass end guard',(-8.05,y),(-7,y),h)
        else:slab('repair deck' if repair else 'wall service gallery',h,(x-.75,x+.75,-7,7),m=m)
    for y in (-6.25,6.25):
        strips=[(-5.5,-3),(3,5.5)] if y<0 else [(-5.5,5.5)]
        for a,b in strips:slab('repair deck' if repair else 'wall service gallery',h,(a,b,y-.75,y+.75),m=m)
    for f in range(4):
        for u in (-4.5,-1.5,1.5,4.5):
            if (f==3 or (f==2 and not repair)) and abs(u)<3:continue # Real eighth-flight opening, no consoles across it.
            corbel('gallery masonry corbel',f,u,h,reach=8.05 if f==2 and not repair else 7.0)
    if not repair:
        # Machicolation rhythm: lighter corbels between the bearing ones (visual only).
        for f in range(4):
            for u in (-3.0,0.0,3.0):
                if (f==3 or f==2) and abs(u)<3:continue
                corbel('gallery machicolation corbel',f,u,h,reach=8.05 if f==2 else 7.0,solid=False)
    for a,b in [((-7,-7),(7,-7)),((7,-7),(7,7)),((7,7),(-7,7)),((-7,7),(-7,-7))]:
        if a[1]==-7 and b[1]==-7:
            if repair:
                repair_guard('repair outer edge',(-7,-7),(-3,-7),h)
                repair_guard('repair outer edge',(3,-7),(7,-7),h)
                repair_guard('stair hole closed west edge',(-3,-7),(-3,-5.5),h)
            else:
                stone_guard('service gallery edge',(-7,-7),(-3,-7),h)
                stone_guard('service gallery edge',(3,-7),(7,-7),h)
        elif not repair and a[0]==-7 and b[0]==-7:
            pass # Stair hole and its separately supported, guarded outer bypass.
        else:repair_guard('upper repair edge',a,b,h) if repair else stone_guard('service gallery edge',a,b,h)
    if repair:
        for a,b in [((-5.6,-5.6),(-3,-5.6)),((3,-5.6),(5.6,-5.6)),((5.6,-5.6),(5.6,5.6)),((5.6,5.6),(-5.6,5.6)),((-5.6,5.6),(-5.6,-5.6))]:repair_guard('broken wall fall guard',a,b,h)
ring(SERVICE)
ring(REPAIR,True)
slab('exterior stair grounded first landing',0,(5.5,7,-4.5,-3))
# Irregular solid masonry crown, deliberately asymmetric and broken.
heights=[30.5,30.8,30.1,29.4,28.5,28.1,29.0,29.4,30.2,31.0,31.4,31.8,31.2,30.0,29.6,28.6,28.0,28.5,29.7,30.6,31.0,30.4]
for face in range(4):
    for k in range(22):
        a=-5.5+k*.5;b=a+.5;top=heights[(k+face*5)%22]
        fixed=-5.3 if face==0 else 5.3 if face==1 else -5.3 if face==2 else 5.3
        axis='x' if face<2 else 'y';wall('fractured old crown',axis,fixed,a,b,27.8,top)
# Heavy surviving north-east masonry anchors the one plain lightning pin.
box('lightning anchor surviving pier',(5.15,5.15,29.65),(.70,.70,3.70),STONE,True)
for z in (29.1,30.0,30.9):beam('mast masonry bracket',(5.35,5.15,z),(5.68,5.15,z),.10,.10,IRON)
beam('single plain lightning pin',(5.68,5.15,29.0),(5.68,5.15,33.2),.055,.055,IRON)
beam('clipped copper downlead',(5.60,5.35,.25),(5.60,5.35,30.8),.025,.025,IRON)
for k in range(21):beam('downlead stone clip',(5.40,5.35,.3+k*1.5),(5.60,5.35,.3+k*1.5),.05,.05,IRON)
beam('pin to conductor link',(5.68,5.15,30.8),(5.60,5.35,30.8),.025,.025,IRON)
box('conductor foundation anchor',(5.52,5.35,.2),(.24,.24,.4),STONE)
# Modest repair scaffold tied to the NORTH masonry, only upper levels.
for x in (-2.1,2.1):
    for y in (5.8,6.75):
        box('repair scaffold upright',(x,y,28.45),(.14,.14,6.5),WOOD)
        beam('scaffold masonry tie',(x,5.32,28.55),(x,y,28.55),.12,.12,WOOD)
    beam('scaffold diagonal',(x,6.8,25.2),(-x,6.8,31.7),.12,.12,WOOD)
for z in (28.7,31.6):box('north scaffold crossbearer',(0,6.25,z),(4.35,.14,.18),WOOD)
beam('scaffold face diagonal',(-2.1,6.75,28.9),(2.1,6.75,31.6),.12,.12,WOOD)
# Temporary low-pitched board lid BELOW the broken crown; roof is not a barn.
def roof_z(y):return 28.35+(y+5.5)*.055
for k in range(23):
    a=-5.5+k*11/23;b=-5.5+(k+1)*11/23
    for xa,xb,ya,yb in panels((a,b,-5.5,5.5),[FLUE]):
        v=[(xa,ya,roof_z(ya)),(xb,ya,roof_z(ya)),(xb,yb,roof_z(yb)),(xa,yb,roof_z(yb))]
        v += [(x,y,z-.12) for x,y,z in v]
        mesh('temporary individual roof boards',v,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],WOOD,True)
for x in (-4.7,0,4.7):beam('repair roof bearer',(x,-5.1,roof_z(-5.1)-.22),(x,5.1,roof_z(5.1)-.22),.16,.22,WOOD)
for y in (-4.8,0,4.8):box('roof bearer masonry pocket',(0,y,roof_z(y)-.32),(10.4,.18,.20),WOOD)
# The flue has real holes in every floor and the board lid, plus an open mouth.
for h in (0,3.6,7.2):
    box('stove supported hearth',(-3.8,2.8,h+.06),(1.4,1.4,.12),STONE,True)
    box('stove masonry',(-3.8,2.8,h+.82),(1.1,1.1,1.4),STONE,True)
    box('stove cornice',(-3.8,2.8,h+1.6),(1.2,1.2,.14),STONE)
    box('stove iron hatch',(-3.8,2.22,h+.70),(.42,.05,.40),IRON)
box('continuous flue',(-3.8,2.8,14.475),(.72,.72,28.95),STONE,True)
for dx in (-.30,.30):box('open chimney cheek',(-3.8+dx,2.8,29.45),(.12,.72,1),STONE,True)
for dy in (-.30,.30):box('open chimney cheek',(-3.8,2.8+dy,29.45),(.48,.12,1),STONE,True)
for dx in (-.32,.32):box('chimney rim',(-3.8+dx,2.8,29.98),(.16,.84,.12),STONE)
for dy in (-.32,.32):box('chimney rim',(-3.8,2.8+dy,29.98),(.52,.16,.12),STONE)
for y in (2.38,3.22):box('flue flashing',(-3.8,y,roof_z(y)+.02),(1.02,.09,.12),IRON)
for x in (-4.22,-3.38):beam('flue flashing side',(x,2.38,roof_z(2.38)+.02),(x,3.22,roof_z(3.22)+.02),.09,.10,IRON)

# Purposeful furnishings with whole joined structures and curved props.
def table(n,x,y,h,w=1.8,d=.8):
    prop(n+' tabletop',(x,y,h+.82),(w,d,.1),solid=True)
    for dx in (-w/2+.12,w/2-.12):
        for dy in (-d/2+.10,d/2-.10):prop(n+' leg',(x+dx,y+dy,h+.36),(.10,.10,.72))
    prop(n+' stretcher',(x,y,h+.22),(w-.15,.09,.10))
def pot(x,y,z):
    rings=[(0,.12),(.06,.20),(.25,.24),(.40,.15),(.45,.14),(.45,.11),(.36,.11)]
    verts=[(x+r*math.cos(k*math.tau/12),y+r*math.sin(k*math.tau/12),z+h) for h,r in rings for k in range(12)]
    faces=[tuple(range(11,-1,-1))]+[(i*12+k,i*12+(k+1)%12,(i+1)*12+(k+1)%12,(i+1)*12+k) for i in range(len(rings)-1) for k in range(12)]
    mesh('whole hollow clay vessel',verts,faces,CLAY,False,'interior_furniture')
def chair(x,y,h):
    prop('chair seat',(x,y,h+.48),(.48,.48,.07))
    for dx in (-.18,.18):
        for dy in (-.18,.18):prop('chair legs',(x+dx,y+dy,h+.22),(.06,.06,.44))
    for dx in (-.18,.18):prop('chair backpost',(x+dx,y+.2,h+.75),(.06,.06,.6))
    prop('chair backboard',(x,y+.2,h+.97),(.42,.06,.20))
def shelf(x,y,h,width=1.6):
    for dx in (-width/2,width/2):prop('shelf supported cheek',(x+dx,y,h+1.05),(.09,.45,2.1),solid=True)
    for z in (.12,.72,1.32,1.92):prop('shelf plank',(x,y,h+z),(width,.45,.08))
    for z in (.76,1.36):
        for k in range(8):
            prop('leather spine',(x-width/2+.14+k*(width-.28)/8,y-.04,h+z+.15),(.11,.25,.28),BOOK)
# Ground: repair bench, toolheads and handles, supported spare materials.
table('repair workbench',-2.8,-2.4,0,2.6,1)
for dx in (-.7,0,.7):
    prop('tool timber handle',(-2.8+dx,-2.4,.94),(.48,.055,.055))
    prop('tool forged head',(-3.02+dx,-2.4,.98),(.12,.19,.09),IRON)
for k in range(6):prop('stacked spare slate',(-3.6,.5,.08+k*.07),(.8,.65,.06),SLATE,solid=k==0)
for x in (-4.6,-2.5):prop('timber repair rack post',(x,4.45,1.1),(.14,.14,2.2),solid=True)
for z in (.3,1.2,2):prop('rack supported bearer',(-3.55,4.45,z),(2.2,.6,.12))
for k in range(4):prop('spare timber',(-3.55,4.45,.45+k*.14),(2,.14,.12))
chair(-2.8,-3.45,0);pot(-4.2,-1.1,0)
# Study: reading desk and instruments, without random jars.
table('study desk',-2.8,-2.3,3.6,2.2,1)
chair(-2.8,-3.35,3.6);shelf(-3.3,4.65,3.6,2.8)
prop('instrument tripod base',(-2.8,-2.3,4.49),(.65,.5,.06),IRON)
for dx,dy in [(-.23,-.16),(.23,-.16),(0,.20)]:
    o=C.beam('instrument tripod',(-2.8+dx,-2.3+dy,4.5),(-2.8,-2.3,4.95),.035,.035,IRON);keep(o,False,'interior_furniture')
prop('instrument sight tube',(-2.8,-2.3,4.97),(.68,.08,.08),IRON)
pot(-4.2,-1.2,3.6)
# Eldren's west cell; actual partition has a wide doorway with no new interaction API.
wall('Eldren cell partition','y',-1.8,-5.1,5.1,7.2,10.56,[(-3.65,-2.05,7.2,9.8)],PLASTER,.16)
table('Eldren writing table',-3.4,-3.9,7.2,1.5,.70);chair(-3.4,-4.75,7.2)
shelf(-4.1,4.65,7.2,1.4)
# Bed assembled from real rails, slats and legs. Mattress is rounded fabric geometry.
for x in (-4.4,-3.35):
    for y in (.9,2.75):prop('bed corner leg',(x,y,7.55),(.12,.12,.70))
for x in (-4.4,-3.35):prop('bed frame rail',(x,1.825,7.70),(.12,1.98,.18))
for y in (.9,2.75):prop('bed end rail',(-3.875,y,7.70),(1.17,.12,.18))
for k in range(8):prop('bed mattress slat',(-3.875,1.0+k*.23,7.78),(1.05,.09,.05))
verts=[]
for z,w,d in [(7.82,.48,.88),(7.91,.52,.94),(8.05,.48,.88)]:
    radius=.13
    for cx,cy,start in [(w-radius,d-radius,0),(-w+radius,d-radius,90),(-w+radius,-d+radius,180),(w-radius,-d+radius,270)]:
        for k in range(4):
            angle=math.radians(start+k*30)
            verts.append((-3.875+cx+radius*math.cos(angle),1.825+cy+radius*math.sin(angle),z))
verts.append((-3.875,1.825,8.08))
faces=[tuple(range(15,-1,-1))]+[(r*16+k,r*16+(k+1)%16,(r+1)*16+(k+1)%16,(r+1)*16+k) for r in range(2) for k in range(16)]+[(32+k,32+(k+1)%16,48) for k in range(16)]
mesh('shaped sewn mattress',verts,faces,CLOTH,True,'interior_furniture')
prop('bed headboard',(-3.875,2.78,8.03),(1.10,.09,.48))
mesh('woven draped cover',[(-4.38,1.35,8.095),(-3.37,1.35,8.095),(-3.37,2.55,8.095),(-4.38,2.55,8.095),(-4.45,1.35,7.75),(-4.45,2.55,7.75)],[(0,1,2,3),(0,3,5,4)],LINEN,False,'interior_furniture')
pot(-4.7,-1.05,7.2)
# Turn the complete bed, including its actual collision, clear of the stove.
bed_transform=Matrix.Translation(Vector((-3.6,1.05,0))) @ Matrix.Rotation(math.pi/2,4,'Z') @ Matrix.Translation(Vector((3.875,-1.825,0)))
bpy.context.view_layer.update()
for o in C.ASSET.objects:
    if o.type=='MESH' and o.name.startswith(('bed ','shaped sewn mattress','woven draped cover')):
        o.matrix_world=bed_transform @ o.matrix_world

# Maintenance repair area keeps the corridor and rod-support view unobstructed.
table('maintenance repair bench',-2.7,-2.8,SERVICE,1.6,.7)
for k in range(3):prop('replacement iron rods',(-2.7,-2.8+k*.12,SERVICE+.9),(1.2,.04,.04),IRON)

# Door parts remain independent and parented in portal local coordinates.
def portal(name,p,angle,door_y):
    root=empty(name,p,angle);hinge=empty(name+'_entry_hinge',(-.76,door_y,0),parent=root);hinge['open_angle_degrees']=-100.0
    for k in range(6):
        o=box(name+' Door plank',(0,0,0),(.248,.08,2.44),WOOD)
        o.parent=hinge;o.location=(.125+k*.254,0,1.22);doors.append(o)
    for z in (.45,1.95):
        o=box(name+' Door strap',(0,0,0),(1.5,.02,.055),IRON)
        o.parent=hinge;o.location=(.76,-.05,z);doors.append(o)
    return root
portal('EntryPortal',(0,0,0),0,-5.3)
portal('MaintenancePortal',(5.3,-2.1,SERVICE),math.pi/2,0)
for x in (-.86,.86):box('entry supported jamb',(x,-5.3,1.25),(.12,.5,2.5),STONE)
box('entry supported lintel',(0,-5.3,2.59),(1.9,.5,.18),STONE)
for y in (-2.96,-1.24):box('maintenance supported jamb',(5.3,y,SERVICE+1.25),(.5,.12,2.5),STONE)
# UV uses metre-scaled world coordinates; wall joins retain continuous pattern.
bpy.context.view_layer.update()
for o in visual:
    metres=float(o.data.materials[0].get('uv_metres',0))
    if not metres:continue
    bm=bmesh.new();bm.from_mesh(o.data);uv=bm.loops.layers.uv.verify()
    for face in bm.faces:
        normal=o.matrix_world.to_3x3()@face.normal;axis=max(range(3),key=lambda i:abs(normal[i]))
        for loop in face.loops:
            p=o.matrix_world@loop.vert.co;u,v=((p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y));loop[uv].uv=(u/metres,v/metres)
    bm.to_mesh(o.data);bm.free()
C._join_by_material([o for o in visual if o not in furniture and o not in doors]);C._join_by_material(furniture)
C._join_by_material(collision)
bpy.context.view_layer.update()
visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
lo=Vector((1e9,1e9,1e9));hi=-lo;triangles=0
for o in [o for o in C.ASSET.objects if o.type=='MESH']:
    for v in o.data.vertices:
        p=o.matrix_world@v.co;g=Vector((p.x,p.z,-p.y));lo=Vector(tuple(min(lo[i],g[i]) for i in range(3)));hi=Vector(tuple(max(hi[i],g[i]) for i in range(3)))
for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
bpy.ops.object.select_all(action='DESELECT')
for o in C.ASSET.objects:o.select_set(True)
bpy.context.view_layer.objects.active=visual[0]
facts=empty('TowerFacts')
facts['architecture_revision']=2;facts['wall_footprint']=[11,11];facts['floor_heights']=LEVELS
facts['service_level']=SERVICE;facts['repair_level']=REPAIR;facts['design_height']=33.2
facts['bounds_min_godot']=list(lo);facts['bounds_max_godot']=list(hi)
facts['internal_treads']=140;facts['external_treads']=160;facts['rise']=.18;facts['run']=.30
facts['outside_path_godot']=[[[a[0],round(k*3.6,1),-a[1]],[b[0],round((k+1)*3.6,1),-b[1]]] for k in range(8) for a,b in [FACES[k%4]]]
facts.select_set(True)
asset=OUT/'s_academy_tower.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];j=json.loads(data[20:20+size])
for m in j['materials']:
    tint={'ST cool stone':(.61,.66,.68),'ST grey limewash':(.78,.80,.76),'ST dark timber':(.30,.24,.18)}.get(m['name'])
    if tint:m['pbrMetallicRoughness']['baseColorFactor']=[*tint,1]
encoded=json.dumps(j,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);remaining=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(remaining))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+remaining)
stats={'author':'Codex direct revision2; no worker launches','wall_footprint':[11,11],'floor_heights':LEVELS,'service_level':SERVICE,'repair_level':REPAIR,'broken_stone_top':31.8,'design_height':33.2,'all_vertex_bounds_godot':[list(lo),list(hi)],'triangles':triangles,'visual_meshes':len(visual),'collision_meshes':sum(1 for o in C.ASSET.objects if o.type=='MESH' and '-colonly' in o.name),'internal_treads':140,'external_treads':160,'rise':.18,'run':.30,'width':1.35,'bytes':asset.stat().st_size,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest(),'state':'revision2 built; QA pending'}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_academy_tower.blend'))
print('ACADEMY_TOWER_BUILD',json.dumps(stats))
