"""PDF141 bounded repaired Conclave tower; heights are design choices, not book canon.
Blender Z-up -> Godot Y-up. All diagnostic outputs stay in ignored local/.
"""
import sys, math, json, struct, hashlib
from pathlib import Path
import bpy, bmesh
from mathutils import Vector, Matrix
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'art/blender'))
import buildings_common as C
C.reset()
OUT = ROOT/'assets/buildings/world-architecture-v1'; OUT.mkdir(parents=True,exist_ok=True)
QA = ROOT/'local/qa/snow-academy-tower'; QA.mkdir(parents=True,exist_ok=True)

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

def keep(o,solid=False,role=''):
    visual.append(o)
    if role:
        o['part_role']=role; furniture.append(o)
    if solid:
        # Copy actual transformed geometry, not an axis-aligned guess.
        bpy.context.view_layer.update()
        q=o.copy();q.data=o.data.copy();q.name=o.name+'-colonly';C.ASSET.objects.link(q)
        q.hide_render=True; collision.append(q)
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
    return keep(C.beam(n,a,b,w,d,m),solid)
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
def slab(n,h,rect=(-5.5,5.5,-5.5,5.5),cuts=(),m=WOOD):
    for a,b,c,d in panels(rect,cuts):box(n,((a+b)/2,(c+d)/2,h-.12),(b-a,d-c,.24),m,True)
slab('stone foundation',0,m=STONE)
for h in (3.6,7.2,10.8):slab('floor %.1f'%h,h,(-5.1,5.1,-5.1,5.1),cuts=(HOLE,FLUE))
# Lantern cords terminate exactly at the underside of the next floor.
for h in (0,3.6,7.2):box('lamp fixing cleat',(-1,0,h+3.345),(.20,.20,.03),WOOD)
box('Eldren lamp fixing cleat',(-3,0,10.545),(.20,.20,.03),WOOD)

def wall(n,axis,fixed,a,b,bottom,top,holes=(),m=STONE,thickness=.4):
    for lo,hi,z0,z1 in panels((a,b,bottom,top),holes):
        p=((lo+hi)/2,fixed,(z0+z1)/2) if axis=='x' else (fixed,(lo+hi)/2,(z0+z1)/2)
        size=(hi-lo,thickness,z1-z0) if axis=='x' else (thickness,hi-lo,z1-z0)
        box(n,p,size,m,True)
# Deep windows are actual gaps through masonry, never a painted square.
for h in (0,3.6,7.2):
    m=STONE if h<7.2 else PLASTER
    front=[(-3.8,-2.8,h+1.15,h+2.5)]
    if h==0:front.append((-.8,.8,0,2.5))
    rear=[(-1.2,-.2,h+1.15,h+2.5)]
    west=[(-2.7,-1.7,h+1.15,h+2.5)]
    if h==7.2:west.append((-.6,.6,8.2,9.2)) # architectural stash niche, separately backed
    east=[(3.0,4.0,h+1.15,h+2.5)]
    wall('front masonry','x',-5.3,-5.5,5.5,h,h+3.6,front,m)
    wall('rear masonry','x',5.3,-5.5,5.5,h,h+3.6,rear,m)
    wall('west masonry','y',-5.3,-5.1,5.1,h,h+3.6,west,m)
    wall('east masonry','y',5.3,-5.1,5.1,h,h+3.6,east,m)
    for fixed,mid,axis in [(-5.3,-3.3,'x'),(5.3,-.7,'x'),(-5.3,-2.2,'y'),(5.3,3.5,'y')]:
        if axis=='x':
            for u in (mid-.55,mid+.55):box('deep window jamb',(u,fixed,h+1.825),(.10,.52,1.45),WOOD)
            for z in (h+1.10,h+2.55):box('window sill lintel',(mid,fixed,z),(1.2,.58,.12),STONE)
            box('window mullion',(mid,fixed,h+1.825),(.06,.12,1.35),WOOD)
        else:
            for u in (mid-.55,mid+.55):box('deep window jamb',(fixed,u,h+1.825),(.52,.10,1.45),WOOD)
            for z in (h+1.10,h+2.55):box('window sill lintel',(fixed,mid,z),(.58,1.2,.12),STONE)
            box('window mullion',(fixed,mid,h+1.825),(.12,.06,1.35),WOOD)
# The niche is within wall thickness; backing keeps the outside envelope intact.
box('Eldren niche backing',(-5.45,0,8.7),(.10,1.2,1),STONE,True)
for y in (-.63,.63):box('niche stone cheek',(-5.25,y,8.7),(.4,.06,1.12),STONE)
for z in (8.17,9.23):box('niche stone shelf',(-5.25,0,z),(.4,1.32,.06),STONE)
prop('niche folded document',(-5.28,0,8.235),(.16,.35,.06),CLOTH)
def roof_z(y):
    y=abs(y)
    return 14.5-y*.3 if y<=3 else 13.6-(y-3)*(2.8/2.9)
# Maintenance storey has a real east portal and gable supports above it.
for axis,fixed in [('x',-5.3),('x',5.3),('y',-5.3),('y',5.3)]:
    holes=[(-2.9,-1.3,10.8,13.3)] if axis=='y' and fixed>0 else []
    # East doorway rises into the gable-side wall, with continuous jambs.
    wall('maintenance enclosure',axis,fixed,-5.1 if axis=='y' else -5.5,5.1 if axis=='y' else 5.5,10.8,11.04 if axis=='x' else 11.24,holes,PLASTER)
    if axis=='x':
        y0=fixed-.2;y1=fixed+.2
        cap=[(-5.5,y0,11.04),(5.5,y0,11.04),(5.5,y1,11.04),(-5.5,y1,11.04),(-5.5,y0,roof_z(y0)-.14),(5.5,y0,roof_z(y0)-.14),(5.5,y1,roof_z(y1)-.14),(-5.5,y1,roof_z(y1)-.14)]
        mesh('wall cap fitted to slate underside',cap,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],PLASTER,True)
    if holes:wall('maintenance portal header',axis,fixed,-2.9,-1.3,13.3,13.52,m=WOOD)
# Shared .42 stone belt; entrance gap remains clear.
for a,b in [(-5.5,-.8),(.8,5.5)]:box('front .42 stone belt',((a+b)/2,-5.54,.21),(b-a,.12,.42),STONE)
box('rear .42 stone belt',(0,5.54,.21),(11.12,.12,.42),STONE)
for x in (-5.54,5.54):box('side .42 stone belt',(x,0,.21),(.12,11,.42),STONE)
# Old tower: patched corners, restrained framing and exposed repair joinery.
for x in (-5.36,5.36):
    for y in (-5.36,5.36):
        box('stone corner buttress',(x,y,3.5),(.4,.4,7),STONE,True)
        box('supported upper corner post',(x,y,9.10),(.24,.24,4.20),WOOD)
for y in (-5.52,5.52):
    for z in (7.2,10.8,11.0):box('facade timber belt',(0,y,z),(11,.16,.18),WOOD)
    for x in (-4,-1.8,1.8,4):box('upper facade post',(x,y,9),(.18,.16,3.6),WOOD)
    for x in (-4,1.8):beam('upper diagonal brace',(x,y,7.5),(x+1.6,y,10.5),.14,.14)
for x in (-5.52,5.52):
    for z in (7.2,10.8,11.15):box('side timber belt',(x,0,z),(.16,11,.18),WOOD)
for k in range(5):
    box('repaired stone blocks',(-4.7+(k%2)*.3,-5.515,.7+k*.48),(.58,.065,.40),STONE)
slab('dry entrance porch',0,(-1.3,1.3,-7,-5.5),m=STONE)
for x in (-1.15,1.15):box('porch canopy post',(x,-6.8,1.6),(.14,.14,3.2),WOOD,True)
box('porch lintel',(0,-6.8,3.2),(2.5,.18,.18),WOOD)
for x in (-1.15,1.15):beam('porch supported slope',(x,-5.5,3.55),(x,-7,3.2),.12,.18)
porch=box('porch slate canopy',(0,-6.25,3.38),(2.7,1.7,.12),SLATE)
porch.rotation_euler.x=math.atan2(.35,1.5)

# Physical ramp prisms: top endpoints coincide with the walking route.
def ramp(n,x,y0,y1,z0,z1,width=1.35):
    a=x-width/2;b=x+width/2;t=.14
    verts=[(a,y0,z0),(b,y0,z0),(b,y1,z1),(a,y1,z1),(a,y0,z0-t),(b,y0,z0-t),(b,y1,z1-t),(a,y1,z1-t)]
    q=C.mesh(n+'-colonly',verts,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],WOOD);q.hide_render=True;collision.append(q)
    for dx in (-.56,.56):beam(n+' stringer',(x+dx,y0,z0-.2),(x+dx,y1,z1-.2),.12,.22)
    for dx in (-.73,.73):
        beam(n+' handrail',(x+dx,y0,z0+1.05),(x+dx,y1,z1+1.05),.08,.09,WOOD,True)
        beam(n+' lower rail',(x+dx,y0,z0+.45),(x+dx,y1,z1+.45),.07,.08,WOOD,True)
        for t in (0,.25,.5,.75,1):
            y=y0+(y1-y0)*t;z=z0+(z1-z0)*t
            box(n+' baluster',(x+dx,y,z+.525),(.07,.07,1.05),WOOD,True)

def guard(n,a,b,h):
    beam(n+' top',(*a,h+1.05),(*b,h+1.05),.09,.09,WOOD,True)
    beam(n+' mid',(*a,h+.45),(*b,h+.45),.08,.08,WOOD,True)
    length=math.hypot(b[0]-a[0],b[1]-a[1]);count=max(1,math.ceil(length/.65))
    for k in range(count+1):
        t=k/count;box(n+' post',(a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,h+.525),(.08,.08,1.05),WOOD,True)

def stairs(n,x1,x2,h,external=False):
    for k in range(10):
        box(n+' first tread %02d'%k,(x1,-2+(k+.5)*.3,h+(k+1)*.18-.05),(1.35,.30,.10),WOOD)
        box(n+' second tread %02d'%k,(x2,1-(k+.5)*.3,h+1.8+(k+1)*.18-.05),(1.35,.30,.10),WOOD)
    ramp(n+' first ramp',x1,-2,1,h,h+1.8)
    ramp(n+' second ramp',x2,1,-2,h+1.8,h+3.6)
    slab(n+' turn',h+1.8,(x1-.73,x2+.73,1,2.3))
    guard(n+' turn back',(x1-.73,2.3),(x2+.73,2.3),h+1.8)
    for x in (x1-.73,x2+.73):guard(n+' turn cheek',(x,1),(x,2.3),h+1.8)
    if external:
        slab(n+' upper landing',h+3.6,(x1-.73,x2+.73,-3.3,-2))
        guard(n+' front guard',(x1-.73,-3.3),(x2+.73,-3.3),h+3.6)
        guard(n+' outer landing',(x2+.73,-3.3),(x2+.73,-2),h+3.6)
        # Deck load goes to continuous grounded posts and diagonal bracing.
        for x in (x1-.60,x2+.60):
            for y in (-3.15,2.12):
                box(n+' pier',(x,y,h+1.8),(.20,.20,3.6),WOOD,True)
            beam(n+' grounded brace',(x,-3.1,h+.05),(x,2.1,h+3.2),.15,.18)
            beam(n+' landing knee',(x,1.1,h+.5),(x,2.1,h+1.7),.14,.18)
    else:
        for x in (x1-.60,x2+.60):box(n+' landing bearer',(x,2.12,h+.85),(.18,.18,1.7),WOOD,True)
        guard(n+' floor hole west',(1.7,-2),(1.7,2.3),h+3.6)
        guard(n+' floor hole east',(4.85,-2),(4.85,2.3),h+3.6)
        guard(n+' floor hole back',(1.7,2.3),(4.85,2.3),h+3.6)
for h in (0,3.6,7.2):
    stairs('internal %.1f'%h,2.5,4.05,h)
    stairs('external %.1f'%h,6.4,8.0,h,True)
slab('external grounded start',0,(5.67,8.73,-3.3,-2))
# Bridge to the maintenance portal, with continuous support to tower wall.
slab('maintenance bridge',10.8,(5.1,5.67,-3.3,-1.3))
for y in (-3.3,-1.3):guard('maintenance bridge edge',(5.5,y),(5.67,y),10.8)
for y in (-3.15,-2.15):beam('maintenance bridge corbel',(5.5,y,9.2),(6.5,y,10.65),.18,.20)
# First/second flights at each stage use the floor front strip for the U return.
for h in (3.6,7.2):
    guard('external left landing cheek',(5.67,-3.3),(5.67,-2),h)

# Steep lower slate pitches and a short ridge cap form a repaired gambrel roof.
# The shoulder preserves 2.4m headroom along the upper service route.
def gable(n,x):
    outline=[(-5.1,11.24),(5.1,11.24),(5.1,roof_z(5.1)-.14),(3,13.46),(0,14.36),(-3,13.46),(-5.1,roof_z(5.1)-.14)]
    count=len(outline)
    verts=[(x+dx,y,z) for dx in (-.1,.1) for y,z in outline]
    faces=[tuple(reversed(range(count))),tuple(range(count,count*2))]+[(k,(k+1)%count,(k+1)%count+count,k+count) for k in range(count)]
    o=mesh(n,verts,faces,PLASTER,False)
    if x>0:
        cutter=C.box('temporary portal cut',(x,-2.1,12.25),(.8,1.6,2.1),STONE,0)
        mod=o.modifiers.new('real upper portal opening','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter;mod.solver='EXACT'
        bpy.context.view_layer.objects.active=o
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter,do_unlink=True)
    q=o.copy();q.data=o.data.copy();q.name=n+'-colonly';C.ASSET.objects.link(q);q.hide_render=True;collision.append(q)
for x in (-5.3,5.3):gable('closed supported gable',x)
eave=10.8;ridge=14.5;half=5.9
for sign in (-1,1):
    strips=[(0,3),(3,half)] if sign>0 else [(-half,-3),(-3,0)]
    for y0,y1 in strips:
        for a,b,c,d in panels((-5.9,5.9,y0,y1),[FLUE] if sign>0 else []):
            verts=[]
            for dz in (0,-.14):
                verts += [(a,c,roof_z(c)+dz),(b,c,roof_z(c)+dz),(b,d,roof_z(d)+dz),(a,d,roof_z(d)+dz)]
            mesh('slate roof with genuine penetration',verts,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],SLATE,True)
    for x in (-5.7,-1.5,1.5,5.7):
        beam('ridge to shoulder rafter',(x,0,14.32),(x,sign*3,13.42),.14,.19)
        beam('shoulder to wall supported rafter',(x,sign*3,13.42),(x,sign*5.7,roof_z(5.7)-.18),.14,.19)
    for x in (-5.85,5.85):
        beam('gable upper rake',(x,0,14.57),(x,sign*3,13.67),.13,.15)
        beam('gable steep rake',(x,sign*3,13.67),(x,sign*half,10.87),.13,.15)
    box('roof eave fascia',(0,sign*half,10.8),(12,.12,.20),WOOD)
    box('load bearing wall plate',(0,sign*5.3,11.16),(11,.2,.16),WOOD)
    box('roof shoulder purlin',(0,sign*3,13.42),(11,.18,.20),WOOD)
    for x in (-5.3,5.3):
        beam('gable upper diagonal',(x,0,14.32),(x,sign*3,13.42),.18,.18)
        beam('gable lower diagonal',(x,sign*3,13.42),(x,sign*5.3,11.25),.18,.18)
box('structural ridgebeam',(0,0,14.32),(11,.24,.24),WOOD)
box('slate ridge cap',(0,0,14.57),(12,.28,.16),SLATE)
for x in (-5.3,5.3):box('gable supported kingpost',(x,0,12.95),(.18,.18,2.7),WOOD)

# Heated occupied floors; flue has actual slab and roof holes.
for h in (0,3.6,7.2):
    box('stove supported hearth',(-3.8,2.8,h+.06),(1.4,1.4,.12),STONE,True)
    box('stove masonry',(-3.8,2.8,h+.82),(1.1,1.1,1.40),STONE,True)
    box('stove cornice',(-3.8,2.8,h+1.6),(1.2,1.2,.14),STONE)
    box('stove iron hatch',(-3.8,2.22,h+.70),(.42,.05,.40),IRON)
box('continuous solid flue shaft',(-3.8,2.8,7.28),(.72,.72,14.56),STONE,True)
# Above the roof the chimney is hollow; central shaft ends at14.56.
for dx in (-.30,.30):box('hollow chimney cheek',(-3.8+dx,2.8,14.95),(.12,.72,.78),STONE,True)
for dy in (-.30,.30):box('hollow chimney cheek',(-3.8,2.8+dy,14.95),(.48,.12,.78),STONE,True)
for dx in (-.32,.32):box('chimney lip',(-3.8+dx,2.8,15.38),(.16,.84,.12),STONE)
for dy in (-.32,.32):box('chimney lip',(-3.8,2.8+dy,15.38),(.52,.16,.12),STONE)
for y in (2.38,3.22):box('chimney flashing return',(-3.8,y,roof_z(y)+.03),(1.02,.09,.18),IRON)
for x in (-4.22,-3.38):beam('chimney flashing side',(x,2.38,roof_z(2.38)+.03),(x,3.22,roof_z(3.22)+.03),.09,.10,IRON)
# Genuine ridge-mounted supported rods with continuous, clipped downconductor.
for x in (-2.2,2.2):
    box('rod ridge saddle',(x,0,14.62),(.45,.48,.16),IRON)
    beam('supported lightning mast',(x,0,14.62),(x,0,16.0),.055,.055,IRON)
    for y in (-.6,.6):beam('lightning mast bracket',(x,y,roof_z(y)),(x,0,15.1),.045,.045,IRON)
    box('mast crossbar',(x,0,15.75),(.55,.035,.035),IRON)
beam('ridge conductor',(-2.2,0,14.73),(5.6,0,14.73),.025,.025,IRON)
beam('upper roof conductor',(5.6,0,14.73),(5.6,-3,13.68),.025,.025,IRON)
beam('steep roof conductor',(5.6,-3,13.68),(5.6,-5.4,roof_z(-5.4)+.08),.025,.025,IRON)
for y in (-1,-2,-3,-4,-5):beam('roof conductor clip',(5.6,y,roof_z(y)-.06),(5.6,y,roof_z(y)+.08),.045,.045,IRON)
for x in (0,4.2,5.6):beam('ridge conductor clip',(x,0,14.5),(x,0,14.73),.045,.045,IRON)
beam('wall conductor',(5.6,-5.4,roof_z(-5.4)+.08),(5.6,-5.4,.25),.025,.025,IRON)
for z in (.3,1.8,3.3,4.8,6.3,7.8,9.3,10.8,11.25):beam('conductor wall clip',(5.42,-5.4,z),(5.6,-5.4,z),.05,.05,IRON)
box('grounded conductor anchor',(5.56,-5.4,.2),(.22,.22,.4),STONE,True)

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
table('maintenance repair bench',-2.7,-2.8,10.8,1.6,.7)
for k in range(3):prop('replacement iron rods',(-2.7,-2.8+k*.12,11.7),(1.2,.04,.04),IRON)

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
portal('MaintenancePortal',(5.3,-2.1,10.8),math.pi/2,0)
for x in (-.86,.86):box('entry supported jamb',(x,-5.3,1.25),(.12,.5,2.5),WOOD)
box('entry supported lintel',(0,-5.3,2.59),(1.9,.5,.18),WOOD)
for y in (-2.96,-1.24):box('maintenance supported jamb',(5.3,y,12.05),(.5,.12,2.5),WOOD)
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
asset=OUT/'s_academy_tower.glb'
bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True)
data=asset.read_bytes();size=struct.unpack_from('<I',data,12)[0];j=json.loads(data[20:20+size])
for m in j['materials']:
    tint={'ST cool stone':(.61,.66,.68),'ST grey limewash':(.78,.80,.76),'ST dark timber':(.30,.24,.18)}.get(m['name'])
    if tint:m['pbrMetallicRoughness']['baseColorFactor']=[*tint,1]
encoded=json.dumps(j,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);remaining=data[20+size:]
asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(remaining))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+remaining)
stats={'author':'Codex after local worker stalled at zero processed tokens','wall_footprint':[11,11],'design_floor_heights':[0,3.6,7.2,10.8],'design_ridge':14.5,'all_vertex_bounds_godot':[list(lo),list(hi)],'triangles':triangles,'visual_meshes':len(visual),'collision_meshes':sum(1 for o in C.ASSET.objects if o.type=='MESH' and '-colonly' in o.name),'staircases':6,'flights':12,'treads_per_flight':10,'rise':.18,'run':.30,'width':1.35,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest(),'state':'geometry generated; coordinator QA pending'}
(QA/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(QA/'s_academy_tower.blend'))
print('ACADEMY_TOWER_BUILD',json.dumps(stats))
