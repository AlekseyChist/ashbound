# FOREST-CITY-01 (D-111): the forest city's plan - Middlehill (Watabou MFCG seed 7736) adapted to the
# game's terrain. Draws the schema shown to the owner (local/qa/forest-city-01/schema-plan.png, not in Git; shown as v5)
# and writes the same plan as data for the game (assets/world/forest-city-v1/plan.json).
# Run from the project root with a Python that has numpy and PIL.
import json,math,numpy as np
from PIL import Image,ImageDraw,ImageFont
L=json.load(open('assets/world/graybox-v1/layout.json',encoding='utf8'))
H=np.fromfile('assets/world/graybox-v1/heights.bin','<f4').reshape(401,401)
X0,Z0,SIZE,PX=190.0,780.0,340.0,5
W=int(SIZE*PX)
def P(x,z):return ((x-X0)*PX,(z-Z0)*PX)
F=lambda s:ImageFont.truetype('assets/ui/fonts/OpenSans-SemiBold.ttf',s)
img=Image.new('RGB',(W,W+320),(236,230,214));d=ImageDraw.Draw(img)
# hillshade + contours
hs=np.zeros((W,W));
xs=X0+np.arange(W)/PX;zs=Z0+np.arange(W)/PX
gx,gz=np.meshgrid(xs,zs)
fx,fz=gx/5,gz/5;ix,iz=fx.astype(int),fz.astype(int);u,v=fx-ix,fz-iz
h=H[iz,ix]*(1-u)*(1-v)+H[iz,ix+1]*u*(1-v)+H[iz+1,ix]*(1-u)*v+H[iz+1,ix+1]*u*v
dy,dx=np.gradient(h,1/PX)
shade=np.clip(0.75+0.25*(-dx*0.6-dy*0.8)/np.sqrt(1+dx*dx+dy*dy),0.45,1.0)
base=np.array([214,222,196])
rgb=(base[None,None,:]*shade[:,:,None]).astype(np.uint8)
img.paste(Image.fromarray(rgb),(0,0));d=ImageDraw.Draw(img)
for lev in range(0,400,2):
    m=(h>=lev)
    edge=m^np.roll(m,1,0)|m^np.roll(m,1,1)
    ys,xs_=np.nonzero(edge)
    col=(150,140,110) if lev%10 else (110,100,80)
    for a,b in zip(xs_[::1],ys[::1]):img.putpixel((int(a),int(b)),col)
d=ImageDraw.Draw(img)
# rivers
for r in L['rivers']:
    pts=[P(p[0]+1000,p[2]+1000) for p in r['world_points']]
    for (a,b),w in zip(zip(pts,pts[1:]),r['world_widths']):d.line([a,b],fill=(96,140,170),width=int(w*PX))
# roads
for r in L['roads']:
    pts=[P(p[0]+1000,p[2]+1000) for p in r['world_points']]
    d.line(pts,fill=(150,120,85),width=int(float(r.get('width_m',6))*PX*0.8),joint='curve')
def label(x,z,text,size=26,fill=(40,32,24),anchor='mm'):
    d.text(P(x,z),text,font=F(size),fill=fill,anchor=anchor,stroke_width=3,stroke_fill=(245,240,228))
PLAN=[]
def house(x,z,w,dep,yaw,fill,outline=(40,32,24),num=None,kind=None,enterable=True):
    PLAN.append({'code':str(num),'kind':kind,'map':[round(x,2),round(z,2)],'size':[w,dep],'yaw_deg':yaw,'enterable':bool(enterable)})
    c,s=math.cos(math.radians(yaw)),math.sin(math.radians(yaw))
    pts=[(x+c*a-s*b,z+s*a+c*b) for a,b in ((-w/2,-dep/2),(w/2,-dep/2),(w/2,dep/2),(-w/2,dep/2))]
    d.polygon([P(*p) for p in pts],fill=fill,outline=outline,width=3)
    if num is not None:d.text(P(x,z),str(num),font=F(22),fill=(255,255,255),anchor='mm',stroke_width=2,stroke_fill=(0,0,0))
# palisade
C=(333.0,955.0);R=47.0
ring=[(C[0]+R*math.cos(t),C[1]+R*math.sin(t)) for t in np.linspace(0,2*math.pi,73)]
d.line([P(*p) for p in ring],fill=(70,48,28),width=int(0.9*PX)+4)
gates={'NE':-36,'SE':55,'W':195}
for i in range(10):
    t=math.radians(i*36+18)
    tx,tz=C[0]+R*math.cos(t),C[1]+R*math.sin(t)
    if any(abs(((math.degrees(t)-g+180)%360)-180)<14 for g in gates.values()):continue
    d.rectangle([P(tx-2.5,tz-2.5),P(tx+2.5,tz+2.5)],fill=(70,48,28))
for name,deg in gates.items():
    t=math.radians(deg);gx_,gz_=C[0]+R*math.cos(t),C[1]+R*math.sin(t)
    d.line([P(C[0]+(R-4)*math.cos(t),C[1]+(R-4)*math.sin(t)),P(C[0]+(R+4)*math.cos(t),C[1]+(R+4)*math.sin(t))],fill=(236,230,214),width=int(6*PX))
    for s in (-1,1):
        tt=t+s*math.radians(5.5);d.rectangle([P(C[0]+R*math.cos(tt)-3,C[1]+R*math.sin(tt)-3),P(C[0]+R*math.cos(tt)+3,C[1]+R*math.sin(tt)+3)],fill=(70,48,28))
# inner street to the gates and plaza
d.ellipse([P(C[0]-14,C[1]-12),P(C[0]+14,C[1]+12)],fill=(205,190,160),outline=(120,100,70),width=3)
for deg in gates.values():
    t=math.radians(deg);d.line([P(C[0]+12*math.cos(t),C[1]+12*math.sin(t)),P(C[0]+R*math.cos(t),C[1]+R*math.sin(t))],fill=(205,190,160),width=int(5*PX))
d.line([P(C[0]+R*math.cos(math.radians(-36)),C[1]+R*math.sin(math.radians(-36))),P(385,915)],fill=(205,190,160),width=int(5*PX))
d.line([P(C[0]+R*math.cos(math.radians(55)),C[1]+R*math.sin(math.radians(55))),P(392,1000)],fill=(205,190,160),width=int(4*PX))
d.ellipse([P(C[0]-1.5,C[1]-1.5),P(C[0]+1.5,C[1]+1.5)],fill=(60,90,120))
INNER=(180,120,70);PUBLIC=(150,60,50);OPEN=(200,150,90);CLOSED=(150,150,145)
# public buildings (inside)
house(C[0]-8,C[1]-26,24,12,0,PUBLIC,num='Р',kind='town_hall')        # town hall north of the plaza
house(C[0]+27,C[1]-12,20,10,-36,PUBLIC,num='К',kind='barracks')     # barracks by the NE gate
house(C[0]-31,C[1]-2,11,11,0,PUBLIC,num='Ц',kind='church_tent')        # church west
# big terems inside (enterable)
terems=[(C[0]+28,C[1]+12,13,11,90),(C[0]+6,C[1]+32,14,11,0),(C[0]-12,C[1]+32,13,11,15),(C[0]-30,C[1]-18,12,13,-30),(C[0]+14,C[1]-32,12,10,-15),(C[0]-29,C[1]+20,11,11,0)]
for i,(x,z,w,dp,yw) in enumerate(terems):house(x,z,w,dp,yw,INNER,num='T%d'%(i+1),kind='terem_%d'%(i+1))
# the big watch tower over the crossing
d.rectangle([P(372,868),P(380,876)],fill=(70,48,28));label(376,862,'Сторожевая башня',22)
# outside: ~20 buildings, each with a job - the chains of life (owner 28 Sep)
def wheel(x,z):
    d.ellipse([P(x-2.2,z-2.2),P(x+2.2,z+2.2)],fill=(90,60,35),outline=(30,20,10),width=3)
    for k in range(4):
        t=k*math.pi/4;d.line([P(x+2.2*math.cos(t),z+2.2*math.sin(t)),P(x-2.2*math.cos(t),z-2.2*math.sin(t))],fill=(30,20,10),width=2)
def field(pts):
    poly=[P(*q) for q in pts];d.polygon(poly,fill=(222,196,110),outline=(160,130,60),width=3)
    xs_=[q[0] for q in pts];zs_=[q[1] for q in pts]
    for k in range(int(min(xs_)),int(max(xs_)),4):d.line([P(k,min(zs_)),P(k+6,max(zs_))],fill=(196,168,80),width=2)
# the wheat field on the north bank, by the mill
field([(438,818),(505,806),(525,868),(468,884),(446,872)])
label(485,835,'пшеничное поле',24)
label(432,902,'водяная мельница',20,anchor='lm')
PROD=(120,150,60)
b_=[
 # bread chain: north bank - the water mill (wheel on the river) and its granary, the miller's house
 ('М',(425,890,11,9,-50,1),None),('А',(446,880,9,7,-50,1),None),('',(458,868,7,6,-40,0),None),
 # bridge suburb (south bank, by the bridge): smithy, carter's yard, two houses
 ('Кз',(360,896,8,6,-20,1),None),('',(348,892,7,6,-30,0),None),('',(402,905,7,6,40,0),None),('',(392,925,7,6,30,0),None),
 # the bakery at the south gate (flour comes over the bridge), two houses
 ('П',(396,962,10,8,10,1),'пекарня, хлебная лавка'),('',(403,978,7,6,10,0),None),('',(392,995,7,6,5,0),None),('',(404,1012,7,6,10,0),None),
 # timber chain: south bank downstream - the sawmill (wheel on the river), the log yard, the carpenter, the sawyer
 ('Л',(458,960,12,8,40,1),'лесопилка'),('Ск',(472,982,12,7,40,0),'склад брёвен'),('Пл',(444,982,8,7,40,1),'плотник'),('',(456,1000,7,6,40,0),None),
 # posad outside the west gate: charcoal burners and the tar kiln (atlas: pitch, charcoal), shacks
 ('Уг',(262,952,8,7,0,1),'угольщики'),('См',(270,985,8,7,-10,0),'смолокурня'),('',(283,1002,6,5,30,0),None),('',(262,968,6,5,20,0),None),('',(292,1016,6,5,10,0),None),
]
for i,(code,(x,z,w,dp,yw,op),name) in enumerate(b_):
    col=PROD if code else (OPEN if op else CLOSED)
    if code and not op:col=(150,170,120)
    kinds={'М':'water_mill','А':'granary','П':'bakery','Л':'sawmill','Ск':'log_yard','Пл':'carpenter','Кз':'smithy','Уг':'charcoal_burner','См':'tar_kiln'}
    house(x,z,w,dp,yw,col,num=code or (i+1),kind=kinds.get(code,'house'),enterable=bool(op))
    if name:label(x+(9 if x>300 else -9),z+(9 if name!='водяная мельница' else -9),name,20,anchor='lm' if x>300 else 'rm')
wheel(419,895);wheel(452,952)
# the flour road over the bridge to the bakery
d.line([P(425,890),P(400,880),P(381,873),P(378,885),P(385,915),P(392,945),P(396,962)],fill=(200,80,40),width=4)
label(410,868,'мука через мост',18,fill=(200,80,40))
label(C[0],C[1]+4,'площадь, колодец',20)
label(C[0]-40,C[1]-58,'частокол Ø94 м, 10 башен',24)
label(338,878,'Мостовая слобода',22);label(412,1025,'Южная слобода',22,anchor='lm')
label(252,1030,'посад',24);label(360,870,'мост',22)
label(395,800,'к Снежному городу',24,anchor='lm');label(485,1075,'в пустыню',24);label(440,1105,'к лесному трактиру и деревне',24)
# scale bar and legend
y0=W+20
d.rectangle([20,y0,20+50*PX,y0+10],fill=(0,0,0));d.text((20,y0+16),'50 м',font=F(24),fill=(0,0,0))
lg=[(PUBLIC,'Р ратуша · К казарма · Ц церковь'),(INNER,'T1–T6 терема в 2–3 этажа, все с входом'),(PROD,'ремесло с входом: М мельница · А амбар · П пекарня · Л лесопилка · Пл плотник · Кз кузница'),(PROD,'Уг угольщики · См смолокурня · Ск склад брёвен (светлые — закрытые)'),(CLOSED,'жилой дом закрытый, для телефона')]
for i,(col,t) in enumerate(lg):
    x=330;y=y0+i*42
    d.rectangle([x,y,x+36,y+30],fill=col,outline=(0,0,0),width=2);d.text((x+48,y+2),t,font=F(24),fill=(0,0,0))
d.text((20,y0+225),'Лесной город (Изгнанники), схема v5 · Middlehill (Watabou MFCG seed 7736) на рельефе игры · горизонтали 2 м',font=F(22),fill=(60,60,60))
d.text((20,y0+258),'Цепочки: поле > мельница > амбар > пекарня > рынок  |  лес > лесопилка > склад > плотник  |  лес > угольщики, смолокурня',font=F(22),fill=(60,60,60))
img.save('local/qa/forest-city-01/schema-plan.png')
import os
os.makedirs('assets/world/forest-city-v1',exist_ok=True)
plan={'id':'forest_city','source':'Watabou MFCG Middlehill seed 7736 (https://watabou.github.io/city-generator/?size=12&seed=7736&citadel=0&urban_castle=0&plaza=1&temple=1&walls=1&shantytown=1&coast=0&river=1&greens=0&gates=-1), adapted, D-111',
 'frame':'map metres (x east, z south); the game frame is map - 1000',
 'palisade':{'center':list(C),'radius':R,'towers':10,'gates':[{'id':k,'deg':v} for k,v in gates.items()],'height_m':5.0},
 'plaza':{'center':list(C),'radius':13.0,'well':True},
 'watch_tower':{'map':[376.0,872.0],'size':[8,8]},
 'water_wheels':[[419.0,895.0],[452.0,952.0]],
 'wheat_field':[[438,818],[505,806],[525,868],[468,884],[446,872]],
 'buildings':PLAN}
open('assets/world/forest-city-v1/plan.json','w',encoding='utf8',newline=chr(10)).write(json.dumps(plan,ensure_ascii=False,indent=1)+chr(10))
print('ok',img.size)
