"""B-1.1: reproducible planning sheets, never writes game resources or source art."""
from pathlib import Path
import hashlib, html, importlib.util, json, math, heapq, sys
from reportlab.pdfgen import canvas

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
SOURCE=HERE.parent/'starter-village-concepts-v1/build_concepts.py'
spec=importlib.util.spec_from_file_location('previous_sheets',SOURCE)
sys.dont_write_bytecode=True
old=importlib.util.module_from_spec(spec); spec.loader.exec_module(old)
old.HERE=HERE  # Output destination only; the previous sheets are never rewritten.
Sheet,C,W,H=old.Sheet,old.C,old.W,old.H
D=json.loads((HERE/'layout.json').read_text(encoding='utf-8'))

def pt(b,x,y):
    a=math.radians(b['angle'])
    return [b['x']+x*math.cos(a)-y*math.sin(a),b['y']+x*math.sin(a)+y*math.cos(a)]

def footprint(b,pad=0):
    m=D['models'][b['model']]; w=m['width']/2+pad; h=m['depth']/2+pad
    return [pt(b,x,y) for x,y in [(-w,-h),(w,-h),(w,h),(-w,h)]]

def entry(b):
    m=D['models'][b['model']]
    return pt(b,m['door_x'],m['depth']/2)

def distance(a,b): return math.dist(a,b)

def project(p,a,b):
    v=[b[0]-a[0],b[1]-a[1]]
    t=max(0,min(1,((p[0]-a[0])*v[0]+(p[1]-a[1])*v[1])/(v[0]**2+v[1]**2)))
    q=[a[0]+v[0]*t,a[1]+v[1]*t]
    return t,q,distance(p,q)

def network():
    anchors=[b['gate'] for b in D['buildings']]+[D['well']['gate']]+[x['gate'] for x in D['height_profile']]
    segments=[(a,b) for r in D['roads'] for a,b in zip(r['points'],r['points'][1:])]
    splits={i:[(0,a),(1,b)] for i,(a,b) in enumerate(segments)}
    graph={}
    def key(p):return tuple(round(x,5) for x in p)
    def connect(a,b):
        ka,kb=key(a),key(b);length=distance(a,b)
        graph.setdefault(ka,{})[kb]=length;graph.setdefault(kb,{})[ka]=length
    for p in anchors:
        i,(t,q,d)=min(enumerate(project(p,a,b) for a,b in segments),key=lambda v:v[1][2])
        assert d<0.2,('gate misses road',p,d)
        splits[i].append((t,q));connect(p,q)
    for pts in splits.values():
        pts=sorted(pts,key=lambda v:v[0])
        for (_,a),(_,b) in zip(pts,pts[1:]):connect(a,b)
    def shortest(start,end):
        start,end=key(start),key(end);todo=[(0,start)];known={start:0}
        while todo:
            d,u=heapq.heappop(todo)
            if u==end:return d
            if d>known[u]:continue
            for v,l in graph[u].items():
                if d+l<known.get(v,math.inf):known[v]=d+l;heapq.heappush(todo,(d+l,v))
        raise ValueError('Disconnected route')
    return shortest

shortest=network()
PROFILE=[dict(v,distance_m=round(shortest(D['height_profile'][0]['gate'],v['gate']),2)) for v in D['height_profile']]
LENGTHS={r['id']:round(sum(distance(a,b) for a,b in zip(r['points'],r['points'][1:])),1) for r in D['roads']}
START=D['buildings'][0];WORK=D['buildings'][3];BARN=D['buildings'][-1]
ROUTES={
    'home_to_well_m':round(distance(entry(START),START['gate'])+shortest(START['gate'],D['well']['gate'])+distance(D['well']['gate'],[D['well']['x'],D['well']['y']]),1),
    'home_to_barn_m':round(distance(entry(START),START['gate'])+shortest(START['gate'],BARN['gate'])+distance(BARN['gate'],entry(BARN)),1),
    'home_to_workshop_m':round(distance(entry(START),START['gate'])+shortest(START['gate'],WORK['gate'])+distance(WORK['gate'],entry(WORK)),1)
}

def header(s,number,title,subtitle):
    s.rect(0,0,W,H,C['paper'])
    s.text(48,43,'ASHBOUND / ЛЕСНЫЕ ДВОРЫ',16,C['muted'])
    s.text(1392,43,'24.09.2026 / Б v1.1',16,C['muted'],'right')
    s.text(48,99,title,38)
    s.text(48,138,subtitle,19,C['muted'])
    s.text(48,988,'ПРЕДЛОЖЕНИЕ - НЕ СОГЛАСОВАНО',17,C['gold'])
    s.text(1392,988,f'{number} / 2',17,C['muted'],'right')
    s.text(48,1018,'После согласования - отдельная карточка 3D. Это схема, не новая игровая сборка.',16,C['muted'])

def note(s,y,title,body):
    s.text(982,y,title,22)
    return s.para(982,y+32,body,410,18,27)+28

def scaled(p):return [p[0]*4,p[1]*4]

def map_page(s):
    header(s,1,'Б - деревня складывается из дворов','Реальные габариты моделей / свободные входы / первый участок выделен цветом')
    s.rect(48,174,900,700,C['ground'],C['border'])
    s.begin_map()
    for i,poly in enumerate(D['forest_polygons']):old.woods(s,[scaled(p) for p in poly],12+i,48)
    for b in D['buildings']:
        x,y,w,h=b['yard'];s.rect(x*4,y*4,w*4,h*4,'#D4CEAF' if b['phase']==1 else '#D5D6C5')
    for r in D['roads']:
        pts=[scaled(p) for p in r['points']]
        s.line(pts,C['path'],r['width']*4)
        if r['width']<2:s.line(pts,C['gold'],1.4,[4,6])
    s.line([scaled(p) for p in D['first_street']],'#A7794C',3.2*4)
    # Working connections from every real threshold to the public route.
    for b in D['buildings']:
        m=D['models'][b['model']];e=entry(b)
        s.line([scaled(e),scaled(b['gate'])],'#B79A72',5)
        landing=[pt(b,x,y) for x,y in [(m['door_x']-1.1,m['depth']/2),(m['door_x']+1.1,m['depth']/2),(m['door_x']+1.1,m['depth']/2+m['front_clearance']),(m['door_x']-1.1,m['depth']/2+m['front_clearance'])]]
        s.poly([scaled(p) for p in landing],C['paper'])
        s.poly([scaled(p) for p in footprint(b)],C['roof'] if b['phase']==1 else '#A4A598',C['edge'] if b['phase']==1 else '#7E857B',1.4)
        s.line([scaled(pt(b,-m['width']/2,0)),scaled(pt(b,m['width']/2,0))],C['paper'],1)
        s.line([scaled(pt(b,m['door_x']-m['door_width']/2,m['depth']/2)),scaled(pt(b,m['door_x']+m['door_width']/2,m['depth']/2))],C['paper'],3)
        s.badge(b['x']*4+24,b['y']*4-23,b['id'])
    well=D['well'];x,y=well['x']*4,well['y']*4
    s.line([scaled(well['gate']),[x,y]],C['path'],7)
    s.ellipse(x,y,well['apron_radius']*4,well['apron_radius']*4,'#D9C399')
    s.ellipse(x,y,5,5,C['blue'],C['edge'],1)
    s.label(x+18,y+20,'Колодец',15)
    old.garden(s,65*4,94*4,5*4,10*4)
    s.label(25,44,'К ранней пещере',16)
    s.label(542,44,'К тракту и таверне',16)
    s.label(18,207,'Лесные делянки',15)
    s.label(620,438,'Склон +8 м',16)
    s.label(356,636,'Огороды / конец улицы',16)
    s.label(349,460,'Роща',15)
    old.north(s);old.map_scale(s,100,'25 м')
    s.end_map()
    y=208
    y=note(s,y,'Первый участок','01 - дом H01, 04 - мастерская W01, 08 - амбар B01. Колодец, проходы и тёмный отрезок улицы - первая сборка.')
    y=note(s,y,'Остальные пять мест','Серые дома - резерв жилых дворов. Всего по-прежнему предлагается 8 строений; жители и занятия ещё не назначены.')
    y=note(s,y,'Улица для жизни','Улица 3,2 м; пешая петля 1,8 м. Дворы не сливаются в площадь. Дрова и работа - сбоку, прямой подход к двери свободен.')
    y=note(s,y,'Короткие связи',f"От первого дома: колодец {ROUTES['home_to_well_m']:.0f} м, мастерская {ROUTES['home_to_workshop_m']:.0f} м, амбар {ROUTES['home_to_barn_m']:.0f} м. Это длины схемы, не замер игры.")
    s.text(48,916,'01 / 04 / 08 - существующие модели. Другие номера - предлагаемые места, не новые ассеты.',17)
    s.text(48,946,'Весь лист: 225 × 175 м. Композиция Б из Watabou сохранена; входы и габариты уточнены.',16,C['muted'])

def detail_page(s):
    header(s,2,'Первый двор и плавный рельеф','Вход смотрит на улицу, огород остаётся за домом, угол двора не перекрывает обзор')
    sx,sy,k=70,180,24
    def p(x,y):return [sx+(x-65)*k,sy+(y-88)*k]
    s.rect(sx,sy,21*k,18*k,C['ground'])
    s.rect(*p(65,88),17*k,18*k,'#D4CEAF')
    s.line([p(83.2,88),p(83.2,106)],C['path'],3.2*k)
    s.line([p(*entry(START)),p(*START['gate'])],'#B79A72',1.4*k)
    s.poly([p(*v) for v in footprint(START)],C['roof'],C['edge'],2)
    s.text(*p(73.5,96.8),'H01',24,C['paper'],'center')
    s.text(*p(73.5,98),'6 × 8 м',17,C['paper'],'center')
    old.garden(s,*p(65.5,90),2.6*k,11*k)
    e=entry(START);s.rect(*p(e[0],e[1]-1.1),3*k,2.2*k,C['paper'])
    s.line([p(77.5,97.175),p(77.5,98.325)],C['ink'],2)
    hinge=[77.5,98.325]
    for finish in (0,-180):
        angles=[math.radians(-90+(finish+90)*i/20) for i in range(21)]
        arc=[[hinge[0]+1.15*math.cos(a),hinge[1]+1.15*math.sin(a)] for a in angles]
        s.line([p(*a) for a in arc],C['gold'],2,[4,3])
    s.line([p(77.5,95.7),p(80.5,95.7)],C['ink'],1.5)
    for x in (77.5,80.5):s.line([p(x,95.4),p(x,96)],C['ink'],1.5)
    s.text(*p(79,95.1),'3 м',17,align='center')
    s.label(*p(70.3,90),'Огород за домом',16)
    s.label(*p(79,104),'Колодец выше по улице',15)
    s.text(70,651,'Тёмный контур - стены. Светлое поле - резерв перед входом.',16,C['muted'])
    y=207
    for title,body in [
      ('Сначала удобство','Проём H01 - 1,15 м. Перед входом оставляем 3 м глубины без забора, дерева и поленницы. Обе дуги двери свободны.'),
      ('Быт объясняет детали','Огород получает открытое небо, дрова стоят у сухой стены. У мастерской отдельная рабочая площадка, у амбара - место разгрузки.'),
      ('Вид раскрывается постепенно','Из дома виден свой двор и ближайший поворот. Колодец помогает найти центр, за ним появляется мастерская. Роща скрывает дальние дворы.'),
      ('Перепады без лестничной деревни','В жилом ядре предлагаем плавный подъём: амбар −0,5 м, первый дом 0 м, мастерская +0,4 м. Высокий лесной склон остаётся сбоку.')]:
        s.text(650,y,title,23);y=s.para(650,y+31,body,735,18,27)+22
    s.text(70,718,'Предлагаемый профиль улицы от амбара к верхнему выходу',22)
    ox,oy,pw=90,900,1200;extent=PROFILE[-1]['distance_m']
    points=[[ox+v['distance_m']/extent*pw,oy-v['height_m']*38] for v in PROFILE]
    s.line([(ox,oy),(ox+pw,oy)],C['border'],1.5)
    s.line(points,C['deep'],3)
    for i,(v,pv) in enumerate(zip(PROFILE,points)):
        label={'Первый дом':'Дом','Верхний выход':'Выход к тракту'}.get(v['name'],v['name'])
        align='left' if i==0 else ('right' if i==len(points)-1 else 'center')
        s.ellipse(*pv,4,4,C['deep'])
        s.text(pv[0],pv[1]-29,label,16,align=align)
        s.text(pv[0],pv[1]-8,f"{v['height_m']:+.1f} м",15,C['muted'],align)
        s.text(pv[0],937,f"{v['distance_m']:.0f} м",15,C['muted'],align)
    s.text(70,960,'Расстояние по оси улицы; высота относительно первого дома. Вертикальный масштаб увеличен.',15,C['muted'])

def main():
    pdf=canvas.Canvas(str(HERE/'AshBound-Forest-Yards-B-v1.1.pdf'),pagesize=(W,H),invariant=1,pageCompression=1)
    pdf.setTitle('AshBound - Лесные дворы Б v1.1 / предложение')
    pdf.setAuthor('AshBound / Codex; composition based on saved Watabou study')
    for fn,name in [(map_page,'layout.svg'),(detail_page,'yard-and-relief.svg')]:
        sheet=Sheet(pdf);fn(sheet);sheet.save_svg(name);pdf.showPage()
    pdf.save()
    metrics={'version':D['version'],'road_lengths_m':LENGTHS,'routes':ROUTES,'height_profile':PROFILE,'status':D['status']}
    (HERE/'metrics.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    template=(HERE/'inline-template.html').read_text(encoding='utf-8')
    (HERE/'inline-map.html').write_text(template.replace('LAYOUT_DATA_HERE',json.dumps(D,ensure_ascii=False)),encoding='utf-8')
    source_paths=['docs/design/starter-village-concepts-v1/build_concepts.py','docs/design/starter-village-concepts-v1/concept-b.svg','docs/design/starter-village-concepts-v1/watabou-b.png','docs/design/starter-village-concepts-v1/sources.json','art/concepts/forest-village-v1/street-lived-concept.png','scripts/world/village_building_catalog.gd','assets/ui/fonts/OpenSans-SemiBold.ttf']
    provenance={'version':D['version'],'base_commit':'7dc41c56f6b23dbed6dd66f205b39dd59d937484','status':D['status'],'method':'Refinement of the preserved B composition; new vector diagrams, not fresh Watabou exports or a Godot rendering.','sources':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in source_paths}}
    (HERE/'sources.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(metrics,ensure_ascii=True))

if __name__=='__main__':main()
