"""Document-only schematic and route profiles. No Godot/Blender geometry is produced."""
from pathlib import Path
import base64
import html
import json
import math
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DATA = json.loads((HERE / 'world-relief.json').read_text(encoding='utf-8'))
FONT_PATH = ROOT / 'docs/art/ui/fonts/OpenSans-SemiBold.ttf'
pdfmetrics.registerFont(TTFont('AshBound', str(FONT_PATH)))
W, H = 1600, 1100
BG, FG, MUTED, GOLD = '#171c20', '#ede9dc', '#b4bdb8', '#c5a46a'
PDF = canvas.Canvas(str(HERE / 'AshBound-World-Relief-v0.2.pdf'), pagesize=(W,H), pageCompression=1, invariant=1)
PDF.setTitle('AshBound - Схема рельефа мира v0.2')
PDF.setAuthor('AshBound / BIOME-01D')
SVG = []
TEXTS = []

def polygon(points, fill, stroke=None, width=1, close=True, dash=None):
    p = PDF.beginPath(); p.moveTo(points[0][0], H-points[0][1])
    for x,y in points[1:]: p.lineTo(x,H-y)
    if close: p.close()
    PDF.setLineWidth(width); PDF.setDash(dash or [])
    if fill: PDF.setFillColor(HexColor(fill))
    if stroke: PDF.setStrokeColor(HexColor(stroke))
    PDF.drawPath(p, fill=int(bool(fill)), stroke=int(bool(stroke)))
    pts = ' '.join(f'{x:.2f},{y:.2f}' for x,y in points)
    tag = 'polygon' if close else 'polyline'
    d = f' stroke-dasharray="{",".join(map(str,dash))}"' if dash else ''
    SVG.append(f'<{tag} points="{pts}" fill="{fill or "none"}" stroke="{stroke or "none"}" stroke-width="{width}" stroke-linejoin="round"{d}/>')
    PDF.setDash([])

def line(points, color, width=1, dash=None):
    polygon(points,None,color,width,False,dash)

def rect(x,y,w,h,color,stroke=None):
    polygon([(x,y),(x+w,y),(x+w,y+h),(x,y+h)],color,stroke)

def circle(x,y,r,fill,stroke=None,width=1):
    PDF.setFillColor(HexColor(fill)); PDF.setLineWidth(width)
    if stroke: PDF.setStrokeColor(HexColor(stroke))
    PDF.circle(x,H-y,r,fill=1,stroke=int(bool(stroke)))
    SVG.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke or "none"}" stroke-width="{width}"/>')

def text(x,y,s,size=22,color=FG,align='left'):
    width=pdfmetrics.stringWidth(s,'AshBound',size)
    if align=='center': x-=width/2
    elif align=='right': x-=width
    assert x>=0 and x+width<=W and 0<y<=H, ('Text outside page',s,x,y,width)
    PDF.setFont('AshBound',size);PDF.setFillColor(HexColor(color));PDF.drawString(x,H-y,s)
    SVG.append(f'<text x="{x:.2f}" y="{y}" font-size="{size}" fill="{color}">{html.escape(s)}</text>')
    TEXTS.append(s)

def lines(x,y,rows,size=22,color=MUTED,gap=32):
    for i,row in enumerate(rows):text(x,y+i*gap,row,size,color)

def arrow(a,b,color,width=2,head=9):
    line([a,b],color,width)
    angle=math.atan2(b[1]-a[1],b[0]-a[0])
    wing=[(b[0]-head*math.cos(angle-d),b[1]-head*math.sin(angle-d)) for d in [-0.55,0.55]]
    polygon([b,*wing],color)

def begin(title,subtitle,page):
    SVG.clear();rect(0,0,W,H,BG)
    text(50,65,title,42)
    text(50,106,subtitle,21,MUTED)
    text(1550,63,f'BIOME-01D / {page:02}',18,GOLD,'right')

def finish(name,page):
    text(50,1078,'AshBound  /  23.09.2026  /  v0.2 - предложение для обсуждения',17,MUTED)
    text(1550,1078,str(page),17,MUTED,'right')
    font64=base64.b64encode(FONT_PATH.read_bytes()).decode()
    content=f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><title>{html.escape(name)}</title><defs><style>@font-face{{font-family:AshBound;src:url(data:font/ttf;base64,{font64})}}text{{font-family:AshBound,sans-serif}}</style></defs>'+''.join(SVG)+'</svg>'
    (HERE/(name+'.svg')).write_text(content,encoding='utf-8')
    PDF.showPage()

def stats(road):
    points=road['points'];distance=[0.0];rise=fall=0.0;grade=0.0
    for a,b in zip(points,points[1:]):
        horizontal=math.hypot(b[0]-a[0],b[1]-a[1]);dh=b[2]-a[2]
        assert horizontal>0
        distance.append(distance[-1]+math.hypot(horizontal,dh))
        rise+=max(0,dh);fall+=max(0,-dh);grade=max(grade,abs(dh)/horizontal)
    return {'id':road['id'],'length_m':distance[-1],'cumulative_m':distance,'ascent_m':rise,'descent_m':fall,'max_grade_percent':grade*100,'walk_seconds':distance[-1]/4.2,'run_seconds':distance[-1]/6.4}

STATS = [stats(r) for r in DATA['roads']]
def duration(seconds):
    sec=round(seconds);return f'{sec//60}:{sec%60:02}'

begin('AshBound / Схема рельефа','Четыре биома, один связный регион. Все размеры, высоты и расположение - рабочее предложение.',1)
MX,MY,S=50,155,0.425
def m(point):return MX+point[0]*S,MY+point[1]*S
def zone(points,color):polygon([m(p) for p in points],color)
rect(MX,MY,850,850,'#77866c')
zone([(1260,0),(2000,0),(2000,1510),(1750,1630),(1290,1530),(1100,1160),(1240,760)],'#baa47e')
zone([(0,1600),(370,1380),(650,1280),(850,1430),(1160,1440),(1400,1550),(1800,1700),(2000,1790),(2000,2000),(0,2000)],'#6e948b')
# Schematic contour belts, not an interpolated DEM or climate calculation.
bands=[
 ([(0,0),(2000,0),(1920,340),(1490,570),(1390,1030),(1120,1220),(960,960),(700,680),(440,680),(130,530),(0,610)],'#a5a68d'),
 ([(120,0),(1650,0),(1610,340),(1430,490),(1380,820),(1170,1090),(1040,890),(810,570),(440,600),(200,410),(100,170)],'#b6b7a1'),
 ([(290,0),(1440,0),(1440,280),(1310,390),(1320,540),(1210,580),(1110,710),(1090,860),(960,720),(930,490),(700,380),(500,400),(270,260)],'#cdcfbd'),
 ([(690,80),(910,80),(1080,180),(1040,290),(860,315),(710,240)],'#ececdd'),
 ([(1170,260),(1320,280),(1390,430),(1290,510),(1200,450)],'#e7e8d9')]
for points,col in bands:
    zone(points,col);line([m(p) for p in points+[points[0]]],'#788276',1.2)
ridge=[(260,210),(390,230),(610,195),(900,190),(1130,285),(1290,430),(1260,530),(1180,650),(1230,840),(1180,1020)]
line([m(p) for p in ridge],'#697066',3,[7,5])
for river in DATA['rivers']:
    ps=[m(p) for p in river['points']]
    line(ps,'#dbe9dc',6);line(ps,'#447d8d',3.5)
    a,b=ps[-3],ps[-2];mid=((a[0]+b[0])/2,(a[1]+b[1])/2)
    arrow(a,mid,'#2f6778',2,9)
for road in DATA['roads']:
    ps=[m(p) for p in road['points']]
    line(ps,'#4b4b3d',6)
    line(ps,'#f0c773' if not road.get('alternative') else '#f0e3b7',3.2,[7,4] if road.get('alternative') else None)
ink='#253632'
for x,z,h in DATA['peaks']:
    px,py=m((x,z));polygon([(px,py-13),(px-11,py+8),(px+11,py+8)],ink)
    text(px,py+32,'+'+str(h),18,ink,'center')
for c in DATA['cities']:
    x,y=m(c['point']);circle(x,y,18,BG,FG,2);text(x,y+7,str(c['number']),22,FG,'center')
    text(x+24,y+7,'+'+str(c['point'][2]),20,ink)
px,py=m(DATA['pass']['point']);polygon([(px,py-9),(px+9,py),(px,py+9),(px-9,py)],FG,ink,2)
leader=m((1060,780));line([(px,py),leader],ink,1)
text(*m((1040,845)),'Перевал +260',18,ink,'center')
sx,sy=m(DATA['start']['point']);circle(sx,sy,8,'#efd896',ink,2)
text(sx-18,sy+8,'Старт? +70',19,ink,'right')
text(*m((160,1070)),'Хвойный лес',25,ink)
text(*m((1570,550)),'Сухая сторона',22,ink)
text(*m((710,1880)),'Низины: болота / джунгли?',23,ink)
nx,ny=m((1880,160));arrow((nx,ny+48),(nx,ny),ink,3,12);text(nx,ny-14,'С',22,ink,'center')
a=m((130,1840));b=m((630,1840));line([a,b],ink,4)
for p in [a,b]:line([(p[0],p[1]-6),(p[0],p[1]+6)],ink,2)
text(a[0],a[1]-15,'500 м',19,ink)
line([(MX,MY),(MX+850,MY),(MX+850,MY+850),(MX,MY+850),(MX,MY)],'#596d66',2)
text(MX+425,1038,'Условный габарит 2 × 2 км. Это схема, не готовая игровая карта.',19,MUTED,'center')

X=952
text(X,180,'Сначала форма, затем наполнение',29)
lines(X,222,['Хребет разделяет влажный лес и сухую сторону.',
 'Долина связывает города в обход перевала.',
 'Вода с гор собирается в южных низинах.'],21,gap=31)
for i,c in enumerate(DATA['cities']):
    y=352+i*96;circle(X+17,y-8,16,'#343d3b',GOLD,1.5)
    text(X+17,y-1,str(c['number']),20,FG,'center')
    text(X+48,y,c['label']+'  /  +'+str(c['point'][2])+' м',25)
    notes=[['Высокий берег, дорога и лесные подходы.'],['Террасы ниже вершин; подъём серпантином.'],['Сухой регион с рекой, приходящей из гор.'],['Сухое возвышение над разливами и протоками.']][i]
    text(X+48,y+32,notes[0],20,MUTED)
text(X,772,'Как читать схему',27)
text(X,726,'Светлые пояса - высоты; пунктир - хребет.',20,MUTED)
line([(X,804),(X+55,804)],'#f0c773',4);text(X+72,812,'Основной дорожный контур',21)
line([(X,843),(X+55,843)],'#f0e3b7',4,[7,4]);text(X+72,851,'Поперечный обход через долину',21)
line([(X,882),(X+55,882)],'#5595a4',4);text(X+72,890,'Реки: стрелки показывают направление стока',20)
lines(X,945,['+0 м - условный уровень выхода воды из схемы.',
 'Высоты относительные; это не климатический расчёт.',
 'Фракции, названия и четвёртый биом ещё открыты.'],20,gap=29)
finish('world-relief-map',1)

begin('Дороги / цена высоты','Профили заданы проектными отметками. Геометрию и проходимость ещё предстоит проверить в игре.',2)
for i,(road,st) in enumerate(zip(DATA['roads'],STATS)):
    x=50+(i%2)*775;y=150+(i//2)*282
    rect(x,y,725,257,'#222b2c')
    text(x+24,y+35,road['label'].replace('→','-'),25)
    text(x+24,y+68,f'{st["length_m"]/1000:.2f} км  /  шагом {duration(st["walk_seconds"])}  /  бегом {duration(st["run_seconds"])}',21,GOLD)
    gx,gy,gw,gh=x+58,y+97,640,106
    for height in [0,150,300]:
        py=gy+gh-height/340*gh
        line([(gx,py),(gx+gw,py)],'#42504c',1)
        text(gx-12,py+5,str(height),15,MUTED,'right')
    ps=[(gx+d/st['length_m']*gw,gy+gh-p[2]/340*gh) for d,p in zip(st['cumulative_m'],road['points'])]
    polygon([(gx,gy+gh),*ps,(gx+gw,gy+gh)],'#4b5e52')
    line(ps,GOLD,3)
    for p in [ps[0],ps[-1]]:circle(*p,4,FG)
    text(gx-25,gy-5,'м',15,MUTED)
    text(gx,gy+gh+22,'0',16,MUTED)
    text(gx+gw,gy+gh+22,f'{st["length_m"]/1000:.2f} км',16,MUTED,'right')
    text(x+24,y+244,f'Подъём {st["ascent_m"]:.0f} м; спуск {st["descent_m"]:.0f} м; макс. уклон сегмента {st["max_grade_percent"]:.1f}%',18,MUTED)
ring=sum(s['length_m'] for s in STATS[:4])
x,y=825,714
text(x+10,y+38,'Что это даёт игроку',28)
lines(x+10,y+82,['Подъём к снегу длиннее прямой линии:',
 'серпантины дают высоту без отвесной дороги.',
 'Поперечная долина позволяет менять маршрут',
 'и не пересекать снежный город каждый раз.',
 f'Полное кольцо: {ring/1000:.2f} км, шагом {duration(ring/4.2)}.',
 'Это бюджет переходов, а не длительность игры.'],21,gap=31)
lines(50,1020,['Время = длина / 4.2 или 6.4 м/с. Без остановок, боёв и изменения скорости на склонах.',
 'Максимальный уклон дан между опорными точками. Он не доказывает отсутствие обрывов в будущем terrain.'],19,gap=29)
finish('world-relief-profiles',2)
PDF.save()

# Validate document constraints rather than claim a walkable game map.
city={c['id']:c['point'] for c in DATA['cities']}
assert len(city)==4 and city['snow'][2]>max(p[2] for k,p in city.items() if k!='snow')
graph={k:set() for k in city}
for road,st in zip(DATA['roads'],STATS):
    assert road['points'][0]==city[road['from']] and road['points'][-1]==city[road['to']]
    assert st['max_grade_percent']<25
    graph[road['from']].add(road['to']);graph[road['to']].add(road['from'])
    assert all(0<=p[0]<=2000 and 0<=p[1]<=2000 for p in road['points'])
seen=set();stack=['forest']
while stack:
    k=stack.pop()
    if k in seen:continue
    seen.add(k);stack+=list(graph[k]-seen)
assert len(seen)==4
main_points=DATA['rivers'][0]['points']
for river in DATA['rivers']:
    assert all(b[2]<a[2] for a,b in zip(river['points'],river['points'][1:]))
    if river.get('joins'):assert river['points'][-1] in main_points
assert 'desert' in graph['forest'] and 'jungle_or_swamp' in DATA['open_decisions']
(HERE/'route-metrics.json').write_text(json.dumps({'roads':STATS,'ring_length_m':ring,'assumptions':DATA['notes']},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(HERE/'text-qa.json').write_text(json.dumps(TEXTS,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PASS 4 cities, connected ring+valley, downhill river junctions, bounded roads, proposed grades <25%, text page bounds')
for st in STATS:print(st['id'],round(st['length_m']),duration(st['walk_seconds']),round(st['max_grade_percent'],1))
