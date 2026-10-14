"""Seven native-size Snow service buildings. Blender5.2 --background --python-exit-code 1.
Source dimensions are metres; Blender (x,y,z) -> Godot (x,z,-y).
No geometry is derived by scaling a GLB. Runtime and previews are separate.
"""
import sys, math, json, hashlib, struct, random
from pathlib import Path
import bpy, bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
OUT=ROOT/'assets/buildings/world-architecture-v1'
QA=ROOT/'local/qa/snow-service-family'
OUT.mkdir(parents=True,exist_ok=True);QA.mkdir(parents=True,exist_ok=True)
FAMILY=[('s_porters_barracks_11x5',11,5,'barracks'),('s_porters_barracks_10x5',10,5,'barracks'),('s_shoemaker',7,5,'shoemaker'),('s_saddler',7,5,'saddler'),('s_candlemaker',7,5,'candlemaker'),('s_caravan_inn',12,7,'inn'),('s_wood_store',6,4,'wood_store')]
FACES=[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
def surface(name,file,tint,metres):
    m=C.mat(name,(*tint,1),.96);m['uv_metres']=metres
    im=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);im.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m

def paint(name,color):
    m=C.mat(name,(*color,1),.95)
    im=bpy.data.images.new(name+'_paint',width=256,height=256);pixels=[]
    for y in range(256):
        for x in range(256):
            variation=.022*math.sin(x*.039+y*.023)+.012*math.sin(y*.073-x*.013)+random.uniform(-.004,.004)
            pixels.extend([max(0,min(1,t+variation)) for t in color]+[1])
    im.pixels.foreach_set(pixels);im.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m

def dark_metal(name,color):
    # Accepted apprentice dorm recipe (674ce76): packed dark patina, no grey default.
    m=C.mat(name,(*color,1),.98);m['uv_metres']=.15
    im=bpy.data.images.new(name+' patina',width=64,height=64);pixels=[]
    for y in range(64):
        for x in range(64):
            value=.045+.009*math.sin(x*.7+y*.4)
            pixels.extend([value,value,value,1])
    im.pixels.foreach_set(pixels);im.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m

def build(slug,w,d,kind):
    C.reset();random.seed(11801)
    poor=kind=='barracks';shed=kind=='wood_store';warm=kind=='inn'
    stone=surface('S cool stone','stone_wall_02_diff_1k.jpg',(.61,.66,.68),2)
    plaster=surface('S grey limewash','plaster_grey_04_diff_1k.jpg',(.78,.80,.76),3)
    wood=surface('S dark timber','fine_grained_wood_col_1k.jpg',(.30,.24,.18),.65)
    slate=paint('S slate',(.10,.135,.15));linen=C.mat('S warm linen',(.35,.31,.23,1),.98)
    iron=dark_metal('S black cast iron',(.055,.060,.065));lead=dark_metal('S weathered lead',(.09,.10,.11))
    clay=paint('S worn fired stove plaster',(.25,.235,.205))
    bedding=paint('S muted flax pad',(.31,.29,.235));wool=paint('S dark wool',(.105,.095,.070))
    leather=paint('S worn leather',(.16,.095,.055))
    wax=paint('S muted ivory beeswax',(.49,.43,.32))
    endgrain=C.mat('S split wood ends',(.32,.23,.14,1),.97)
    collision=[];roof_collision=[];furniture=[];beds=[];parts=[];chimney_top=0
    h=2.6 if poor else 2.7 if shed else 3.1
    rise=2.2 if poor else 1.35 if shed else 3.55 if warm else w*.5
    ridge=h+rise;ex=w/2+.28;ey=d/2+.32;xf=w/2-.18;yf=d/2-.18
    cx=w/2-.95;cy=-2.0 if warm else d/2-1.0;heated=not poor and not shed
    def tag(o,semantic):
        o['part_role']='interior_furniture';o['semantic']=semantic;furniture.append(o);return o
    def box(n,p,s,m,solid=False,inside=False,semantic='furniture'):
        o=C.box(n,p,s,m,0 if m==plaster or n=='floor' else .012)
        if inside:tag(o,semantic)
        if solid:collision.append((n,p,s))
        return o
    def wx(n,y,a,b,lo=0,hi=h,m=None):return box(n,((a+b)/2,y,(lo+hi)/2),(b-a,.36,hi-lo),m or (wood if poor else plaster),True)
    def wy(n,x,a,b,lo=0,hi=h,m=None):return box(n,(x,(a+b)/2,(lo+hi)/2),(.36,b-a,hi-lo),m or (wood if poor else plaster),True)
    def prism(n,outline,y0,y1,m,semantic=None):
        vs=[(x,y,z) for y in (y0,y1) for x,z in outline];k=len(outline)
        faces=[tuple(reversed(range(k))),tuple(range(k,2*k))]+[(i,(i+1)%k,(i+1)%k+k,i+k) for i in range(k)]
        o=C.mesh(n,vs,faces,m)
        return tag(o,semantic) if semantic else o
    def lathe(n,p,profile,m,semantic='ware',sides=12,closed=True):
        x,y,z=p;vs=[(x+r*math.cos(i*math.tau/sides),y+r*math.sin(i*math.tau/sides),z+height) for r,height in profile for i in range(sides)]
        faces=[(j*sides+i,j*sides+(i+1)%sides,(j+1)*sides+(i+1)%sides,(j+1)*sides+i) for j in range(len(profile)-1) for i in range(sides)]
        if closed:faces+=[tuple(reversed(range(sides))),tuple(range((len(profile)-1)*sides,len(profile)*sides))]
        return tag(C.mesh(n,vs,faces,m),semantic)
    def table(n,x,y,width,depth,height=.8):
        box(n,(x,y,height-.05),(width,depth,.10),wood,True,True)
        for dx in (-width/2+.15,width/2-.15):
            for dy in (-depth/2+.12,depth/2-.12):box(n+' leg',(x+dx,y+dy,(height-.10)/2),(.12,.12,height-.10),wood,False,True)
    def bench(n,x,y,width):
        box(n,(x,y,.43),(width,.46,.10),wood,True,True)
        for dx in (-width/2+.20,width/2-.20):box(n+' trestle',(x+dx,y,.19),(.18,.42,.38),wood,False,True)
    box('floor',(0,0,-.12),(w,d,.24),wood,True)
    if not shed:
        if kind in ('shoemaker','saddler','candlemaker'):
            # Real street display apertures face the counter without changing plot walls.
            ww={'shoemaker':1.4,'saddler':1.7,'candlemaker':1.2}[kind]
            low=1.02 if kind=='saddler' else .94;high=2.15 if kind=='candlemaker' else 2.08
            a=-1.8-ww/2;b=-1.8+ww/2
            wx('entry left pier',-yf,-w/2,a);wx('entry display door pier',-yf,b,-.65)
            wx('display sill wall',-yf,a,b,0,low);wx('display header',-yf,a,b,high)
            for x in (a-.04,b+.04):box('display jamb',(x,-yf,(low+high)/2),(.08,.42,high-low+.16),wood)
            for z in (low,high):box('display rail',(-1.8,-yf,z),(ww+.16,.42,.08),wood)
            box('display ledge',(-1.8,-yf-.04,low-.06),(ww+.20,.50,.10),stone)
            if kind=='candlemaker':box('display crossbar',(-1.8,-yf,1.65),(ww,.13,.06),wood)
            else:box('display mullion',(-1.8,-yf,(low+high)/2),(.06,.13,high-low),wood)
        else:wx('entry left',-yf,-w/2,-.65)
        wx('entry right',-yf,.65,w/2);wx('entry lintel',-yf,-.65,.65,2.35)
        wy('west wall',-xf,-yf+.18,yf-.18);wy('east wall',xf,-yf+.18,yf-.18)
        windows=[-w/2+1.15,w/2-2.1] if heated else [-w/2+1.15,-.50,w/2-1.15]
        edge=-w/2
        for x in windows:
            wx('rear pier',yf,edge,x-.42);wx('window sill wall',yf,x-.42,x+.42,0,1.45);wx('window header',yf,x-.42,x+.42,2.25)
            for dx in (-.47,.47):box('window jamb',(x+dx,yf,1.85),(.08,.40,.86),wood)
            for z in (1.45,2.25):box('window rail',(x,yf,z),(.98,.40,.08),wood)
            box('window mullion',(x,yf,1.85),(.06,.12,.8),wood)
            box('window ledge',(x,yf,1.39),(1.03,.46,.1),stone)
            edge=x+.42
        wx('rear pier',yf,edge,w/2)
        if not poor:
            for a,b in [(-w/2,-.65),(.65,w/2)]:box('front stone belt',((a+b)/2,-d/2-.03,.21),(b-a,.12,.42),stone)
            box('rear stone belt',(0,d/2+.03,.21),(w+.10,.12,.42),stone)
            for x in (-w/2-.03,w/2+.03):box('side stone belt',(x,0,.21),(.12,d,.42),stone)
        else:
            for z in (.35,.85,1.35,1.85,2.35):
                for x in (-xf-.20,xf+.20):box('weathered board seams',(x,0,z),(.035,d-.4,.045),wood)
            for x in (-xf,xf):box('timber sill',(x,0,.1),(.42,d,.2),stone)
        for x in (-.72,.72):box('entry jamb',(x,-yf,1.17),(.12,.43,2.34),wood)
        box('entry head',(0,-yf,2.42),(1.56,.43,.14),wood)
        if heated:
            for a,b in [(-xf,cx-.30),(cx+.30,xf)]:box('loft ceiling',((a+b)/2,0,h),(b-a,d-.36,.14),wood,True)
            for a,b in [(-yf+.18,cy-.30),(cy+.30,yf-.18)]:
                if b>a:box('loft ceiling',(cx,(a+b)/2,h),(.60,b-a,.14),wood,True)
        else:box('low boarded ceiling',(0,0,h),(w-.36,d-.36,.14),wood,True)
    else:
        # Full 6x4 store footprint with a completely open front and ventilated back.
        for x in (-xf,xf):
            for y in (-yf,yf):box('load bearing shelter post',(x,y,h/2),(.22,.22,h),wood,True)
        for y in (-yf,yf):box('shelter tie',(0,y,h-.10),(w,.22,.20),wood)
        for x in (-xf,xf):box('shelter side plate',(x,0,h-.10),(.22,d,.20),wood)
        for x in [-xf+i*.34 for i in range(int(2*xf/.34)+1)]:box('rear ventilation board',(x,yf,1.4),(.23,.10,2.5),wood)
        collision.append(('rear ventilated barrier',(0,yf,1.35),(w,.10,2.7)))
        for x in (-2.0,2.0):
            box('wood rack base',(x,.55,.30),(1.40,2.0,.16),wood,True,True)
            for dx in (-.6,.6):
                for dy in (-.85,.85):box('rack foot',(x+dx,.55+dy,.11),(.18,.18,.22),wood,False,True)
            for dx in (-.63,.63):
                for dy in (-.85,.85):box('rack upright',(x+dx,.55+dy,.98),(.1,.1,1.52),wood,False,True)
            for row in range(5):
                for col in range(5):
                    px=x-.52+col*.26;pz=.50+row*.24
                    # Real octagonal split billets; end caps expose the same whole wood.
                    vs=[(px+.12*math.cos(i*math.tau/8),yy,pz+.12*math.sin(i*math.tau/8)) for yy in (-.25,1.35) for i in range(8)]
                    fs=[tuple(reversed(range(8))),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
                    billet=tag(C.mesh('stacked split billet',vs,fs,wood),'firewood')
                    billet.data.materials.append(endgrain)
                    for face in billet.data.polygons:face.material_index=1 if len(face.vertices)==8 else 0
            collision.append(('stacked dry wood',(x,.55,.98),(1.4,1.6,1.22)))
    for x in (-xf,xf):
        for y in (-yf,yf):box('corner post',(x,y,h/2),(.22,.22,h),wood)
    for y in (-yf,yf):box('wall plate',(0,y,h-.1),(w,.22,.2),wood)
    for x in (-xf,xf):box('side plate',(x,0,h-.1),(.22,d-.36,.2),wood)
    for y in (-yf,yf):
        prism('closed gable',[(-w/2,h),(w/2,h),(0,ridge)],y-.12,y+.12,wood if poor or shed else plaster)
        for side in (-1,1):C.beam('gable rake',(side*w/2,y-.15,h),(0,y-.15,ridge),.16,.18,wood)
        box('gable king post',(0,y-.16,h+rise/2),(.16,.18,rise),wood)
        box('gable tie',(0,y-.16,h+.75),(w*(1-.75/rise),.18,.15),wood)
        if not poor and not shed:
            for x in (-w*.18,w*.18):box('gable upright',(x,y-.16,h+rise*.32),(.12,.17,rise*.64),wood)
    # Gables/eave plates and actual internal rafters support the complete pitched roof.
    for y in (-d/4,0,d/4):
        for side in (-1,1):C.beam('structural rafter',(side*w/2,y,h-.05),(0,y,ridge-.05),.12,.14,wood)
    def zroof(x):return ridge+.10-(rise+.10)*abs(x)/ex
    def roofpatch(n,x0,x1,y0,y1,lift=0,thick=.12,solid=False):
        top=[(x0,y0,zroof(x0)+lift),(x1,y0,zroof(x1)+lift),(x1,y1,zroof(x1)+lift),(x0,y1,zroof(x0)+lift)]
        vs=top+[(x,y,z-thick) for x,y,z in top];C.mesh(n,vs,FACES,wood if poor or shed else slate)
        if solid:roof_collision.append((vs,FACES))
    for side in (-1,1):
        xs=[-ex,0] if side<0 else [0,cx-.32,cx+.32,ex] if heated else [0,ex]
        ys=[-ey,cy-.32,cy+.32,ey] if heated else [-ey,ey]
        for a,b in zip(xs,xs[1:]):
            for c,e in zip(ys,ys[1:]):
                if heated and side>0 and a>=cx-.321 and b<=cx+.321 and c>=cy-.321 and e<=cy+.321:continue
                roofpatch('roof panel',a,b,c,e,solid=True)
        for row in range(10):
            lo,hi=sorted((side*ex*(row+.01)/10,side*ex*min(1,(row+1.04)/10)))
            for col in range(math.ceil(2*ey/.58)+1):
                ya=max(-ey,-ey-.29+col*.58+(.29 if row%2 else 0));yb=min(ey,ya+.56)
                if yb<=ya:continue
                rects=[(lo,hi,ya,yb)]
                if heated and side>0 and hi>cx-.32 and lo<cx+.32 and yb>cy-.32 and ya<cy+.32:
                    rects=[]
                    if lo<cx-.32:rects.append((lo,cx-.32,ya,yb))
                    if hi>cx+.32:rects.append((cx+.32,hi,ya,yb))
                    l=max(lo,cx-.32);r=min(hi,cx+.32)
                    if ya<cy-.32:rects.append((l,r,ya,cy-.32))
                    if yb>cy+.32:rects.append((l,r,cy+.32,yb))
                for a,b,c,e in rects:roofpatch('overlapping shingles' if poor or shed else 'overlapping slate tile',a,b,c,e,.04,.025)
        C.beam('eaves trim',(side*ex,-ey,h),(side*ex,ey,h),.14,.14,wood)
    C.beam('ridge cap',(0,-ey-.08,ridge+.12),(0,ey+.08,ridge+.12),.18,.16,wood if poor or shed else slate)
    if heated:
        chimney_top=zroof(cx-.32)+.65
        # Textured limewash body plus a stone brick plinth at the stove base.
        stove_lime=surface('S stove limewash','plaster_grey_04_diff_1k.jpg',(.60,.54,.45),.9)
        box('stove',(cx,cy,.68),(1.05,1.05,1.36),stove_lime,True)
        box('stove brick plinth',(cx,cy,.09),(1.11,1.11,.18),stone)
        hatch_side=1 if warm else -1
        hatch_y=cy+hatch_side*.55
        box('stove hatch',(cx,hatch_y,.53),(.46,.06,.40),iron)
        for dx in (-.25,.25):box('cast iron hatch jamb',(cx+dx,hatch_y+hatch_side*.025,.53),(.045,.055,.47),iron)
        for z in (.30,.76):box('cast iron hatch rail',(cx,hatch_y+hatch_side*.025,z),(.545,.055,.045),iron)
        for z in (.40,.65):box('hatch hinge',(cx-.235,hatch_y+hatch_side*.06,z),(.075,.07,.05),iron)
        box('hatch latch base',(cx+.19,hatch_y+hatch_side*.055,.53),(.065,.06,.06),iron)
        box('hatch latch handle',(cx+.19,hatch_y+hatch_side*.095,.58),(.035,.035,.14),iron)
        # Four overlapping lead aprons seal the original .64m roof opening to the .60m stack.
        for x0,x1,y0,y1 in [(cx-.52,cx-.30,cy-.52,cy+.52),(cx+.30,cx+.52,cy-.52,cy+.52),(cx-.30,cx+.30,cy-.52,cy-.30),(cx-.30,cx+.30,cy+.30,cy+.52)]:
            top=[(x0,y0,zroof(x0)+.065),(x1,y0,zroof(x1)+.065),(x1,y1,zroof(x1)+.065),(x0,y1,zroof(x0)+.065)]
            C.mesh('dark lead chimney flashing',top+[(x,y,z-.030) for x,y,z in top],FACES,lead)
        box('stove hood',(cx,cy,1.43),(1.14,1.14,.14),stone)
        box('continuous stove flue',(cx,cy,(1.50+chimney_top)/2),(.60,.60,chimney_top-1.5),stone,True)
        for dx in (-.25,.25):
            for dy in (-.25,.25):box('chimney cap support',(cx+dx,cy+dy,chimney_top+.14),(.1,.1,.28),stone)
        box('chimney rain cap',(cx,cy,chimney_top+.31),(.78,.78,.10),stone)
    if poor or warm:
        bedy=d/2-1.50
        positions=[-w/2+1.10+i*2.25 for i in range(4)]
        for bx in positions:
            bw=1.12
            box('bed frame',(bx,bedy,.35),(bw,2.16,.18),wood,True,True)
            # Existing bed-frame collider is untouched; side boards retain its exact plan extents.
            for dx in (-bw/2+.03,bw/2-.03):box('bed box sideboard',(bx+dx,bedy,.46),(.06,2.16,.12),wood,False,True)
            box('bed box footboard',(bx,bedy-1.03,.46),(bw,.06,.12),wood,False,True)
            box('adult mattress',(bx,bedy,.47),(bw-.08,2.04,.06),bedding,False,True,'adult_mattress')
            box('dark wool blanket',(bx,bedy-.27,.513),(bw-.14,1.45,.024),wool,False,True)
            box('dark wool pillow',(bx,bedy+.76,.5325),(bw-.24,.34,.055),wool,False,True)
            for dx in (-bw/2+.12,bw/2-.12):
                for dy in (-.91,.91):box('bed leg',(bx+dx,bedy+dy,.18),(.12,.12,.36),wood,False,True)
            box('headboard',(bx,bedy+1.03,.65),(bw,.10,1.05),wood,False,True)
            beds.append({'center':[bx,.47,-bedy],'length':2.04,'width':bw-.08})
        if warm:
            # Real partition with two broad passages; sleeping space is not the hall.
            for a,b in [(-w/2+.36,-1.45),(-.05,.5),(1.9,w/2-.36)]:wx('guest room partition',-.55,a,b,0,2.6,wood)
            for a,b in [(-1.45,-.05),(.5,1.9)]:wx('guest passage header',-.55,a,b,2.35,2.6,wood)
            # Furniture stays west of the straight entry aisle and outside the door arc.
            table('common room table',-3.0,-2.0,2.6,.86)
            bench('hall bench',-3.0,-2.85,2.5);bench('hall bench',-3.0,-1.05,2.5)
            box('hall cupboard',(-5.0,-2.0,.65),(1.2,.65,1.3),wood,True,True)
        else:bench('porters common bench',-w/2+2.1,-1.65,3.0)
    if not shed:
        dx=2.0 if warm else w/2-.90;dy=-2.75 if warm else -d/2+.8
        for x in (dx-.45,dx+.45):box('drying rack post',(x,dy,.92),(.09,.09,1.84),wood,False,True)
        box('drying rail',(dx,dy,1.85),(1.04,.10,.10),wood,False,True)
        # Three garments draped over the rail; each hangs on both sides of it.
        for name,m,x,width,length in [('drying shirt',linen,dx-.28,.34,.62),('drying wool cloak',wool,dx+.05,.40,.80),('drying leggings',leather,dx+.34,.16,.55)]:
            for side in (-.06,.06):box(name,(x,dy+side,1.80-length/2),(width,.03,length),m,False,True)
        box('lamp support',(-2.0 if warm else 0,-1.8 if warm else 0,h-.10),(.22,.22,.06),wood)
        hinge=bpy.data.objects.new('S_entry_hinge',None);C.ASSET.objects.link(hinge)
        hinge.location=(-.60,-yf,0);hinge['open_angle_degrees']=-100.0
        for k in range(5):parts.append(box('Door plank',(-.48+k*.24,-yf,1.14),(.234,.08,2.28),wood))
        for z in (.45,1.72):parts.append(box('Door strap',(0,-yf-.05,z),(1.18,.018,.06),iron))
    else:hinge=None
    if kind in ('shoemaker','saddler','candlemaker'):
        table('shop counter',-1.80,-1.30,1.65,.75,.90)
        table('craft workbench',-1.70,1.15,1.90,.85,.85)
        bench('craft stool',-.65,1.15,.40)
        # A hanging trade sign on an iron bracket, right of the door, readable along the street.
        box('sign bracket arm',(1.4,-d/2-.33,2.55),(.04,.66,.04),iron)
        C.beam('sign bracket brace',(1.4,-d/2,2.15),(1.4,-d/2-.45,2.53),.03,.03,iron)
        for y in (-d/2-.25,-d/2-.61):box('sign chain',(1.4,y,2.43),(.02,.02,.22),iron)
        box('trade sign board',(1.4,-d/2-.43,2.10),(.05,.52,.44),wood)
        for xs in (1.4-.035,1.4+.035):
            if kind=='shoemaker':
                box('sign boot shaft',(xs,-d/2-.40,2.17),(.02,.11,.22),leather)
                box('sign boot foot',(xs,-d/2-.46,2.03),(.02,.26,.08),leather)
            elif kind=='saddler':
                box('sign saddle seat',(xs,-d/2-.43,2.06),(.02,.30,.06),leather)
                for dy in (-.15,.15):box('sign saddle horn',(xs,-d/2-.43+dy,2.14),(.02,.06,.14),leather)
            else:
                for k in (-1,0,1):
                    box('sign candle',(xs,-d/2-.43+k*.13,2.06),(.02,.06,.20+.04*(k+1)),wax)
                    box('sign wick',(xs,-d/2-.43+k*.13,2.06+(.20+.04*(k+1))/2+.02),(.02,.015,.04),iron)
        # Wall stock on the west wall: what this shop makes.
        for z in (1.55,1.95):
            box('stock shelf',(-2.98,0,z),(.30,1.40,.05),wood,False,True)
            for dy in (-.55,.55):box('stock shelf bracket',(-3.06,dy,z-.09),(.14,.05,.14),wood,False,True)
        # Whole goods are built to adult-world dimensions and stand on their surfaces.
        def foot(n,x,y,z,m,boot):
            # Adult whole last/boot foot: curved heel, instep, ball and tapered toe.
            stations=[(-.16,.045,.085),(-.11,.080,.145),(-.035,.095,.165),(.065,.112,.110),(.135,.098,.075),(.195,.047,.045),(.21,.015,.026)]
            sides=12
            vs=[(x+width*math.cos(i*math.tau/sides),y+along,z+height*(.5+.5*math.sin(i*math.tau/sides))) for along,width,height in stations for i in range(sides)]
            fs=[tuple(reversed(range(sides))),tuple(range((len(stations)-1)*sides,len(stations)*sides))]
            fs += [(j*sides+i,j*sides+(i+1)%sides,(j+1)*sides+(i+1)%sides,(j+1)*sides+i) for j in range(len(stations)-1) for i in range(sides)]
            o=tag(C.mesh(n+' whole foot',vs,fs,m),'boot' if boot else 'last')
            for face in o.data.polygons:face.use_smooth=len(face.vertices)==4
            if boot:
                lathe('boot shaft',(x,y-.08,z+.10),[(.085,0),(.075,.25),(.090,.37),(.065,.37),(.06,.13)],m,'boot',12,False)
                lathe('boot cuff',(x,y-.08,z+.43),[(.092,0),(.092,.045),(.071,.045),(.071,0)],m,'boot',12,False)
        if kind=='shoemaker':
            for x in (-2.2,-1.80):foot('finished boot',x,-1.30,.90,leather,True)
            for x in (-2.20,-1.60):
                foot('wooden shoe last',x,1.15,.85,endgrain,False)
            box('leather cutting sheet',(-1.2,1.15,.858),(.45,.45,.016),leather,False,True)
        elif kind=='saddler':
            # Saddle panels follow a curved cantle/pommel silhouette, resting on a trestle.
            box('saddle stand',(-1.65,1.15,1.015),(.16,.60,.33),wood,False,True)
            outline=[(-.37,1.04),(-.33,1.32),(-.20,1.42),(0,1.30),(.20,1.42),(.33,1.32),(.37,1.04),(.25,1.07),(.16,1.26),(0,1.18),(-.16,1.26),(-.25,1.07)]
            prism('curved leather saddle',[(x-1.65,z) for x,z in outline],.83,1.47,leather,'saddle')
            for y in (.81,1.47):prism('raised saddle end',[(-2.0,1.3),(-1.85,1.53),(-1.65,1.48),(-1.45,1.53),(-1.30,1.3)],y,y+.055,leather,'saddle')
            # Harness loop ribbons hang from a braced rack, not from empty air.
            for x in (1.25,2.25):box('harness rack leg',(x,-.55,1.05),(.10,.10,2.10),wood,False,True)
            box('harness rail',(1.75,-.55,2.10),(1.18,.12,.10),wood,False,True)
            for x in (1.5,1.95):
                points=[(x+.19*math.cos(i*math.tau/16),-.62,1.51+.55*math.sin(i*math.tau/16)) for i in range(16)]
                for i in range(16):tag(C.beam('whole harness strap',points[i],points[(i+1)%16],.035,.018,leather),'harness')
                box('harness hook',(x,-.60,2.075),(.045,.18,.045),iron,False,True)
        else:
            lathe('closed wax pot',(-1.85,1.15,.85),[(.19,0),(.25,.09),(.26,.33),(.21,.40),(.20,.42)],iron,'closed_pot',16)
            lathe('closed pot lid',(-1.85,1.15,1.27),[(.23,0),(.20,.045),(.07,.065),(.045,.10)],iron,'closed_pot',16)
            # Six metal mould tubes capped below; visible rims have actual hollow mouths.
            for i in range(6):lathe('candle mould',(-1.10+(i%3)*.11,.97+(i//3)*.20,.85),[(.04,0),(.04,.34),(.027,.34),(.027,.03),(0,.03)],iron,'mould',10)
            for i in range(7):
                x=-2.35+i*.18
                lathe('tapered candle',(x,-1.30,.90),[(.042,0),(.027,.32+(i%3)*.07),(.010,.35+(i%3)*.07)],wax,'candle',10)
                box('candle wick',(x,-1.30,1.262+(i%3)*.07),(.012,.012,.025),iron,False,True,'candle')
        # Wall stock on the west wall: what this shop makes.
        if kind=='shoemaker':
            for y in (-.35,.35):foot('stock boot',-2.98,y,1.975,leather,True)
            for y in (-.45,0,.45):foot('stock last',-2.98,y,1.575,endgrain,False)
        elif kind=='saddler':
            for y in (-.45,0,.45):
                points=[(-2.98,y+.13*math.cos(i*math.tau/12),1.72+.13*math.sin(i*math.tau/12)) for i in range(12)]
                for i in range(12):tag(C.beam('stock strap ring',points[i],points[(i+1)%12],.03,.02,leather),'harness')
            for dy in (-.3,.3):box('stock stirrup',(-2.98,dy,2.08),(.04,.14,.16),iron,False,True)
        else:
            box('candle drying rod',(-2.95,0,2.60),(.04,1.30,.04),iron,False,True)
            for y in (-.48,-.16,.16,.48):
                for i in range(5):box('hanging candle',(-2.95+(i-2)*.035,y+((i%2)-.5)*.03,2.40),(.03,.03,.34),wax,False,True)
            for i in range(8):lathe('stock candle',(-2.98,-.56+i*.16,1.575),[(.03,0),(.022,.26),(.008,.28)],wax,'candle',8)

    visual=[o for o in C.ASSET.objects if o.type=='MESH']
    # Continuous world-space UV on zero-bevel limewash, including split wall piers.
    for o in visual:
        scale=float(o.data.materials[0].get('uv_metres',0))
        if not scale:continue
        bm=bmesh.new();bm.from_mesh(o.data);uv=bm.loops.layers.uv.verify()
        for face in bm.faces:
            normal=o.matrix_world.to_3x3()@face.normal;axis=max(range(3),key=lambda i:abs(normal[i]))
            for loop in face.loops:
                p=o.matrix_world@loop.vert.co
                u,v=(p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y)
                loop[uv].uv=(u/scale,v/scale)
        bm.to_mesh(o.data);bm.free()
    C._join_by_material([o for o in visual if o not in parts and o not in furniture])
    groups={}
    for o in furniture:groups.setdefault(o.get('semantic','furniture'),[]).append(o)
    for group,members in groups.items():
        if group!='adult_mattress':C._join_by_material(members)
    for o in parts:
        matrix=o.matrix_world.copy();o.parent=hinge;o.matrix_world=matrix
    bpy.context.view_layer.update()
    visual=[o for o in C.ASSET.objects if o.type=='MESH']
    tri=0;pts=[]
    for o in visual:
        o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles)
        pts += [o.matrix_world@v.co for v in o.data.vertices]
    mn=[min(p[i] for p in pts) for i in range(3)];mx=[max(p[i] for p in pts) for i in range(3)]
    bounds=[[mn[0],mn[2],-mx[1]],[mx[0],mx[2],-mn[1]]]
    for n,p,s in collision:
        o=box(n+'-colonly',p,s,stone);o.hide_render=True
    for k,(vs,fs) in enumerate(roof_collision):
        o=C.mesh('roof panel '+str(k)+'-colonly',vs,fs,slate);o.hide_render=True
    anchor=bpy.data.objects.new('EntryAnchor',None);C.ASSET.objects.link(anchor);anchor.location=(0,-yf,0)
    anchor['wall_width']=w;anchor['wall_depth']=d;anchor['ceiling_height']=h;anchor['enter']=not shed;anchor['kind']=kind;anchor['lamp_z']=1.8 if warm else 0;anchor['lamp_x']=-2.0 if warm else 0
    for o in C.ASSET.objects:o.select_set(True)
    bpy.context.view_layer.objects.active=visual[0]
    asset=OUT/(slug+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_extras=True,export_cameras=False,export_lights=False)
    raw=asset.read_bytes();sz=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+sz])
    tints={'S cool stone':(.61,.66,.68),'S grey limewash':(.78,.80,.76),'S dark timber':(.30,.24,.18)}
    for m in doc['materials']:
        if m['name'] in tints:m['pbrMetallicRoughness']['baseColorFactor']=[*tints[m['name']],1]
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);tail=raw[20+sz:]
    asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
    stats={'slug':slug,'wall_footprint':[w,d],'entry':[0,0,yf],'ceiling':h,'ridge':ridge,'whole_bounds_godot':bounds,'triangles':tri,'visual_meshes':len(visual),'material_count':len(doc['materials']),'collision_boxes':len(collision),'roof_patches':len(roof_collision),'beds':beds,'kind':kind,'enter':not shed,'bytes':asset.stat().st_size,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest(),'chimney_mouth_y':chimney_top,'stove':[cx,cy]}
    (QA/(slug+'.json')).write_text(json.dumps(stats,indent=2),encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(QA/(slug+'.blend')))
    print('FAMILY_BUILT',json.dumps(stats),flush=True)

for variant in FAMILY:build(*variant)
