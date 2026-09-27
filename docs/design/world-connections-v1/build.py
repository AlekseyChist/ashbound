"""Offline cartography and design checks only. No game terrain is generated."""
from pathlib import Path
import base64
import hashlib
import heapq
import html
import json
import math
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
D = json.loads((HERE / 'world-connections.json').read_text(encoding='utf8'))
OLD_PATH = HERE.parent / 'world-relief-v1/world-relief.json'
OLD = json.loads(OLD_PATH.read_text(encoding='utf8'))
assert hashlib.sha256(OLD_PATH.read_bytes()).hexdigest() == D['source_sha256']
assert D['cities'] == OLD['cities'] and D['rivers'] == OLD['rivers']


def metrics(road):
    length = rise = fall = grade = 0.0
    for a, b in zip(road['points'], road['points'][1:]):
        horizontal = math.dist(a[:2], b[:2]); dh = b[2] - a[2]
        assert horizontal > 0
        length += math.hypot(horizontal, dh)
        rise += max(dh, 0); fall += max(-dh, 0)
        grade = max(grade, abs(dh) / horizontal * 100)
    return {'length_m': length, 'ascent_m': rise, 'descent_m': fall,
            'max_grade_percent': grade, 'walk_seconds': length / 4.2, 'run_seconds': length / 6.4}


def crossings(data):
    result = []
    def cross(a, b): return a[0] * b[1] - a[1] * b[0]
    for road in data['roads']:
        for river in data['rivers']:
            for a, b in zip(road['points'], road['points'][1:]):
                for c, d in zip(river['points'], river['points'][1:]):
                    u = [b[i] - a[i] for i in [0, 1]]
                    v = [d[i] - c[i] for i in [0, 1]]
                    w = [c[i] - a[i] for i in [0, 1]]
                    det = cross(u, v)
                    if abs(det) < 1e-8: continue
                    t, s = cross(w, v) / det, cross(w, u) / det
                    if not (-1e-8 <= t <= 1+1e-8 and -1e-8 <= s <= 1+1e-8): continue
                    point = [a[i] + t * (b[i] - a[i]) for i in range(3)]
                    water = c[2] + s * (d[2] - c[2])
                    if any(x['road'] == road['id'] and x['river'] == river['id'] and math.dist(x['point'][:2], point[:2]) < .001 for x in result): continue
                    result.append({'road': road['id'], 'river': river['id'], 'point': point,
                                   'water_h': water, 'clearance_m': point[2] - water})
    return result


CITIES = {c['id']: c for c in D['cities']}
M = {r['id']: metrics(r) for r in D['roads']}
PREVIOUS = {r['id']: metrics(r) for r in OLD['roads']}
CROSSINGS = crossings(D)
BEFORE_CROSSINGS = crossings(OLD)
assert len(CROSSINGS) == 6
assert len([x for x in BEFORE_CROSSINGS if x['clearance_m'] < 0]) == 3
assert min(x['clearance_m'] for x in CROSSINGS) >= 3.0
assert max(m['max_grade_percent'] for m in M.values()) < 25
for r in D['roads']:
    assert r['points'][0] == CITIES[r['from']]['point']
    assert r['points'][-1] == CITIES[r['to']]['point']
    assert all(0 <= p[0] <= 2000 and 0 <= p[1] <= 2000 for p in r['points'])
for g in D['gates']:
    assert g['point'] in next(r for r in D['roads'] if r['id'] == g['road'])['points']
for river in D['rivers']:
    assert all(a[2] >= b[2] for a,b in zip(river['points'],river['points'][1:]))
BRIDGES = []
for label in D['bridge_labels']:
    matches = [x for x in CROSSINGS if math.dist(x['point'][:2],label['near']) < 2]
    assert matches, label
    BRIDGES.append({**label, 'point': matches[0]['point'], 'water_h': matches[0]['water_h'],
                    'clearance_m': min(x['clearance_m'] for x in matches),
                    'roads': sorted({x['road'] for x in matches})})
assert sum(len(b['roads']) for b in BRIDGES) == 6


def node_key(point): return tuple(round(v, 5) for v in point)


# Split road segments at crossings; identical shared approaches become one edge.
# This lets a traveller turn at J1 without first walking to the desert city.
GRAPH = {}
for road in D['roads']:
    extras = [b['point'] for b in BRIDGES if road['id'] in b['roads']]
    for a,b in zip(road['points'],road['points'][1:]):
        points = [(0.0,a),(1.0,b)]; u=[b[i]-a[i] for i in range(3)]
        length2=sum(v*v for v in u)
        for p in extras:
            t=sum((p[i]-a[i])*u[i] for i in range(3))/length2
            if 0<t<1 and math.dist(p,[a[i]+t*u[i] for i in range(3)])<.001:points.append((t,p))
        points.sort(key=lambda item:item[0])
        for (_,x),(_,y) in zip(points,points[1:]):
            kx,ky=node_key(x),node_key(y)
            GRAPH.setdefault(kx,{})[ky]=(math.dist(x,y),road['id'])
            GRAPH.setdefault(ky,{})[kx]=(math.dist(x,y),road['id'])
BLOCKS = {g['id']:{node_key(g['point'])} for g in D['gates']}
BLOCKS.update({b['id']:{node_key(b['point'])} for b in BRIDGES})


def shortest(start, end, removed=()):
    queue = [(0.0, node_key(CITIES[start]['point']), [])]; visited = set()
    end=node_key(CITIES[end]['point'])
    blocked=set().union(*(BLOCKS[k] for k in removed)) if removed else set()
    while queue:
        distance, node, route = heapq.heappop(queue)
        if node in visited or node in blocked: continue
        visited.add(node)
        if node == end: return {'length_m': distance, 'roads': route}
        for other,(length,road_id) in GRAPH[node].items():
            heapq.heappush(queue,(distance+length,other,route+[road_id] if not route or route[-1]!=road_id else route))
    return None


PAIRS = [(a,b) for i,a in enumerate(CITIES) for b in list(CITIES)[i+1:]]
closures = {}
for block_id in BLOCKS:
    cases = [{'from':a,'to':b,**shortest(a,b,[block_id])} for a,b in PAIRS]
    assert len(cases) == 6
    closures[block_id] = {'blocked_node':list(next(iter(BLOCKS[block_id]))),'pairs':cases}
assert shortest('forest','snow',['P1','P2']) is None
REPORT = {'version':D['version'],'roads':M,'previous_roads':PREVIOUS,
          'before_crossings':BEFORE_CROSSINGS,'crossings':CROSSINGS,'bridges':BRIDGES,
          'shortest_pairs':[{'from':a,'to':b,**shortest(a,b)} for a,b in PAIRS],
          'closures':closures,'double_pass_closure':'snow disconnected, expected',
          'scope':'graph/profile checks only; no generated terrain/navigation/collision/streaming proof'}
(HERE/'checks.json').write_text(json.dumps(REPORT,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')

FONT = ROOT/'docs/art/ui/fonts/OpenSans-SemiBold.ttf'
pdfmetrics.registerFont(TTFont('AshBound',str(FONT)))
W,H = 1600,1100
BG,FG,MUTED,GOLD = '#171d23','#f0ecdf','#b6c4c0','#ebc57d'
PDF = canvas.Canvas(str(HERE/'AshBound-World-Connections-v0.3.pdf'),pagesize=(W,H),invariant=1)
PDF.setTitle('AshBound - горы, перевалы и связи четырёх биомов v0.3')
PDF.setAuthor('AshBound / BIOME-01E')
SVG = []


def poly(points,fill=None,stroke=None,width=1,dash=None,closed=False):
    p=PDF.beginPath();p.moveTo(points[0][0],H-points[0][1])
    for x,y in points[1:]:p.lineTo(x,H-y)
    if closed:p.close()
    PDF.setLineWidth(width);PDF.setDash(dash or [])
    if fill:PDF.setFillColor(HexColor(fill))
    if stroke:PDF.setStrokeColor(HexColor(stroke))
    PDF.drawPath(p,fill=bool(fill),stroke=bool(stroke));PDF.setDash([])
    tag='polygon' if closed else 'polyline';pts=' '.join(f'{x:.2f},{y:.2f}' for x,y in points)
    extra=f' stroke-dasharray="{",".join(map(str,dash))}"' if dash else ''
    SVG.append(f'<{tag} points="{pts}" fill="{fill or "none"}" stroke="{stroke or "none"}" stroke-width="{width}" stroke-linejoin="round"{extra}/>')


def rect(x,y,w,h,color,stroke=None):poly([(x,y),(x+w,y),(x+w,y+h),(x,y+h)],color,stroke,closed=True)
def line(points,color,width=1,dash=None):poly(points,stroke=color,width=width,dash=dash)
def circle(x,y,r,fill,stroke=None,width=1):
    PDF.setFillColor(HexColor(fill));PDF.setLineWidth(width)
    if stroke:PDF.setStrokeColor(HexColor(stroke))
    PDF.circle(x,H-y,r,fill=1,stroke=bool(stroke))
    SVG.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke or "none"}" stroke-width="{width}"/>')
def text(x,y,s,size=22,color=FG,align='left'):
    width=pdfmetrics.stringWidth(s,'AshBound',size)
    if align=='center':x-=width/2
    if align=='right':x-=width
    assert x>=0 and x+width<=W and 0<y<H,(s,x,y,width)
    PDF.setFont('AshBound',size);PDF.setFillColor(HexColor(color));PDF.drawString(x,H-y,s)
    SVG.append(f'<text x="{x:.2f}" y="{y}" font-size="{size}" fill="{color}">{html.escape(s)}</text>')
def lines(x,y,rows,size=21,color=MUTED,gap=31):
    for i,row in enumerate(rows):text(x,y+i*gap,row,size,color)
def begin(title,sub,num):
    SVG.clear();rect(0,0,W,H,BG);text(48,66,title,40);text(48,108,sub,21,MUTED)
    text(1552,65,f'BIOME-01E / {num:02}',17,GOLD,'right')
def finish(name,num):
    text(48,1078,'AshBound / 23.09.2026 / v0.3 - проектное предложение, не утверждённая география',17,MUTED)
    text(1552,1078,str(num),17,MUTED,'right')
    font=base64.b64encode(FONT.read_bytes()).decode()
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1100" viewBox="0 0 1600 1100"><title>{name}</title><defs><style>@font-face{{font-family:AshBound;src:url(data:font/ttf;base64,{font})}}text{{font-family:AshBound,sans-serif}}</style></defs>'+''.join(SVG)+'</svg>'
    (HERE/(name+'.svg')).write_text(svg,encoding='utf8',newline='\n');PDF.showPage()
def duration(s):
    sec=round(s);return f'{sec//60}:{sec%60:02}'
def route_label(key):return {'forest_snow':'Лес - снег','snow_desert':'Снег - пустыня','desert_lowland':'Пустыня - низины','lowland_forest':'Низины - лес','forest_desert':'Лес - пустыня'}[key]


begin('Четыре биома / проходы и границы','Горный контур + нижний обход. Города и габарит сохранены из v0.2; переправы уточнены.',1)
MX,MY,S=48,160,.43
def m(p):return MX+p[0]*S,MY+p[1]*S
def zone(points,color):poly([m(p) for p in points],color,closed=True)
rect(MX,MY,860,860,'#536d5a')
zone([(1260,0),(2000,0),(2000,1510),(1750,1630),(1290,1530),(1100,1160),(1240,760)],'#b49469')
zone([(0,1600),(370,1380),(650,1280),(850,1430),(1160,1440),(1400,1550),(1800,1700),(2000,1790),(2000,2000),(0,2000)],'#4e8077')
zone([(0,0),(2000,0),(1920,340),(1490,570),(1390,1030),(1120,1220),(960,960),(700,680),(440,680),(130,530),(0,610)],'#8f9584')
zone([(120,0),(1650,0),(1610,340),(1430,490),(1380,820),(1170,1090),(1040,890),(810,570),(440,600),(200,410),(100,170)],'#adb3a6')
zone([(290,0),(1440,0),(1440,280),(1310,390),(1320,540),(1210,580),(1110,710),(1090,860),(960,720),(930,490),(700,380),(500,400),(270,260)],'#d4dacd')
for ridge in D['ridges']:line([m(p) for p in ridge['points']],'#687168',4,[8,6])
for river in D['rivers']:
    points=[m(p) for p in river['points']];line(points,'#d4e6d9',6);line(points,'#477eaa',3)
    a,b=points[-2:];t=.55;tip=(a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1]));ang=math.atan2(b[1]-a[1],b[0]-a[0])
    poly([tip,(tip[0]-11*math.cos(ang-.5),tip[1]-11*math.sin(ang-.5)),(tip[0]-11*math.cos(ang+.5),tip[1]-11*math.sin(ang+.5))],'#386382',closed=True)
for road in D['roads']:
    pts=[m(p) for p in road['points']];line(pts,'#333b36',7);line(pts,GOLD if not road.get('alternative') else '#fff0bf',3.4,[8,5] if road.get('alternative') else None)
ink='#26352f'
for x,z,h in D['peaks']:
    a,b=m((x,z));poly([(a,b-13),(a-11,b+8),(a+11,b+8)],ink,closed=True);text(a,b+32,'+'+str(h),18,ink,'center')
for c in D['cities']:
    x,y=m(c['point']);circle(x,y,19,BG,FG,2);text(x,y+7,str(c['number']),22,FG,'center')
    if c['id']!='forest':text(x+26,y+6,'+'+str(c['point'][2]),18,ink)
for gate in D['gates']:
    x,y=m(gate['point']);poly([(x,y-11),(x+11,y),(x,y+11),(x-11,y)],'#f9ecb6',ink,2,closed=True)
    text(x-16,y-16,gate['id'],21,ink,'right')
offsets={'B1':(-55,36),'B2':(-125,65),'B3':(90,35),'B4':(-45,-40),'B5':(-52,35)}
for b in BRIDGES:
    x,y=m(b['point']);rect(x-6,y-6,12,12,'#f4f0df',ink);dx,dy=offsets[b['id']]
    line([(x,y),(x+dx*.8,y+dy*.8)],ink,1.5);text(x+dx,y+dy,b['id'],19,ink,'center')
for c in D['cities']:
    x,y=m(c['point']);circle(x,y,19,BG,FG,2);text(x,y+7,str(c['number']),22,FG,'center')
for j in D['junctions']:
    x,y=m(j['point']);circle(x,y,4,ink);line([(x,y),(x-38,y-30)],ink,1);text(x-42,y-34,j['id'],18,ink,'right')
text(*m((100,1120)),'ХВОЙНЫЙ ЛЕС',23,FG)
text(*m((1510,600)),'СУХОЙ РЕГИОН',21,ink)
text(*m((1050,1850)),'НИЗИНЫ: БОЛОТА / ДЖУНГЛИ',20,FG,'center')
text(*m((1880,120)),'С',23,ink,'center');line([m((1880,245)),m((1880,150))],ink,3)
a,b=m((130,1780)),m((630,1780));line([a,b],FG,4);text(a[0],a[1]-15,'500 м',18,FG)
text(478,1044,'2 × 2 км - рабочая сетка; светлые области показывают форму, не точные горизонтали.',16,MUTED,'center')
X=954
text(X,190,'Где меняется маршрут',29)
for i,g in enumerate(D['gates']):
    y=240+i*110;text(X,y,f'{g["id"]}  {g["label"]}  +{g["point"][2]} м',24,GOLD)
    rows={'P1':['Из влажного леса к снежным террасам.','Петли дороги набирают высоту.'],'P2':['Из снежной чаши на сухую сторону.','Отрог ограничивает прямой поперечный путь.'],'D1':['Связь леса и пустыни южнее отрога.','Снежный город можно обойти.']}[g['id']]
    lines(X,y+34,rows,20,gap=28)
text(X,592,'Четыре города',27)
for i,c in enumerate(D['cities']):text(X,630+i*39,f'{c["number"]}  {c["label"]}  +{c["point"][2]} м',22)
text(X,826,'Условные обозначения',25)
lines(X,868,['Пунктир серый: хребет; ромб: проход P/D.',
                  'Золотая дорога: кольцо; светлая: нижний обход.',
                  'Синяя линия/стрелка: русло и направление стока.',
                  'Квадрат B: мост, подробности на странице 3.',
                  'Сезонов нет. Четвёртый биом ещё не выбран.'],19,gap=31)
finish('world-connections-map',1)

begin('Связность / есть ли другой путь','Это граф маршрутов, не географическая проекция. Время - чистое движение без остановок.',2)
pos={'forest':(175,510),'snow':(445,245),'desert':(715,510),'lowland':(445,795)}
junction=(644,430)
for road in D['roads']:
    points=[pos[road['from']],pos[road['to']]]
    if road['id'] in ['forest_desert','snow_desert']:points.insert(1,junction)
    line(points,GOLD if not road.get('alternative') else '#eee1bd',4,[10,7] if road.get('alternative') else None)
circle(*junction,7,FG);text(junction[0]+13,junction[1]-17,'J1',20,GOLD)
for key,(x,y) in pos.items():
    c=CITIES[key];circle(x,y,39,'#2e3b3c',GOLD,2);text(x,y+11,str(c['number']),30,align='center')
    if key=='snow':text(x,y-61,'Снежный город',24,FG,'center')
    elif key=='lowland':text(x,y+81,'Город низин',24,FG,'center')
    else:
        ly=y-62 if key=='forest' else y+74
        rect(x-115,ly-28,230,38,BG)
        text(x,ly,'Лесной город' if key=='forest' else 'Пустынный город',24,FG,'center')
tags={'forest_snow':(184,306,'P1'),'snow_desert':(566,307,'P2'),'desert_lowland':(566,702,'B4'),'lowland_forest':(181,704,'B5'),'forest_desert':(351,557,'D1 / B2 / B3')}
for key,(x,y,label) in tags.items():
    st=M[key];text(x,y,label,23,GOLD);text(x,y+29,f'{st["length_m"]/1000:.2f} км / {duration(st["walk_seconds"])}',19)
lines(48,925,['Два горных прохода ведут к снегу с разных сторон.',
              'Один закрытый проход или мост оставляет все города связными.',
              'Если закрыть оба горных прохода, снежный город изолирован.'],20,gap=32)
X=850
text(X,185,'Чистый переход между соседями',27)
text(X,226,'Маршрут',19,MUTED);text(1290,226,'Шаг',19,MUTED);text(1450,226,'Бег',19,MUTED)
for i,r in enumerate(D['roads']):
    y=271+i*60;st=M[r['id']];line([(X,y+18),(1550,y+18)],'#33433f')
    text(X,y,route_label(r['id']),22);text(1290,y,duration(st['walk_seconds']),22,GOLD);text(1450,y,duration(st['run_seconds']),22)
text(X,615,'Стоимость обхода',27)
for i,(key,a,b,title) in enumerate([('P1','forest','snow','P1 закрыт: лес - снег'),('D1','forest','desert','D1 закрыт: лес - пустыня'),('B3','forest','desert','B3 закрыт: путь через низины')]):
    case=shortest(a,b,[key]);normal=shortest(a,b);y=662+i*107
    text(X,y,title,22,GOLD)
    text(X,y+34,f'{case["length_m"]/1000:.2f} км / {duration(case["length_m"]/4.2)} шагом',21)
    text(X,y+63,f'Вместо {duration(normal["length_m"]/4.2)}; прибавка {duration(round(case["length_m"]/4.2)-round(normal["length_m"]/4.2))}.',19,MUTED)
lines(X,981,['J1 учитывается как развилка, без захода в город.',
              'Закрытие - проверка схемы, не новая механика.'],18,gap=28)
finish('world-connections-network',2)

begin('Переправы / что исправлено','В v0.2 три пересечения имели отметку дороги ниже воды. В v0.3 каждому задан проектный мост.',3)
xs=[48,125,714,934,1150,1350]
for x,s in zip(xs,['ID','Переправа','Настил','Вода','Разница','Дороги']):text(x,181,s,21,MUTED)
for i,b in enumerate(BRIDGES):
    y=239+i*76;line([(48,y+23),(1550,y+23)],'#364742')
    for x,s in zip(xs,[b['id'],b['label'],f'+{b["point"][2]:.1f} м',f'+{b["water_h"]:.1f} м',f'{b["clearance_m"]:.1f} м',str(len(b['roads']))]):text(x,y,s,22,GOLD if x==48 else FG)
lines(48,642,['B3 объединяет два прежних близких пересечения перед пустынным городом.',
              'B4 поднимает локальную переправу низин до +38 м; города и реки не перемещены.',
              f'Всего 5 мест переправ / 6 прохождений дорог. Минимальная разница отметок - {min(b["clearance_m"] for b in BRIDGES):.1f} м.'],21,gap=34)
text(48,791,'Следующие ограниченные шаги мира',29)
for x,title,rows in [(48,'1 / Выбрать форму',['Обсудить хребет, нижний обход','и образ четвёртого биома.']),
                     (565,'2 / Уточнить один район',['Стартовый лес: границы, виды,','река и связь с городом.']),
                     (1082,'3 / Проверить в игре',['Только выбранный короткий участок:','уклон, коллизия, камера, телефон.'])]:
    rect(x,828,469,146,'#24302f');text(x+20,866,title,24,GOLD);lines(x+20,907,rows,20,gap=31)
lines(48,1009,['Отметки условные относительно южного выхода воды. Рисунок не задаёт мостовую конструкцию, русло terrain или зоны загрузки.'],18,gap=26)
finish('world-connections-crossings',3)
PDF.save()
print('WORLD_CONNECTIONS_OK pages=3 roads=5 bridges=5 crossings=6 closure_cases=48 grade_max=%.2f' % max(x['max_grade_percent'] for x in M.values()))
