"""Coordinator QA of the proposal. No dependency on the drawing builder."""
from pathlib import Path
import json, math, re
from pypdf import PdfReader
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
D=json.loads((HERE/'layout.json').read_text(encoding='utf-8'))
checks=0
def check(value,label):
    global checks
    checks+=1
    if not value:raise AssertionError(label)
def line_distance(p,a,b):
    v=[b[i]-a[i] for i in (0,1)]
    t=max(0,min(1,sum((p[i]-a[i])*v[i] for i in (0,1))/sum(x*x for x in v)))
    return math.dist(p,[a[i]+t*v[i] for i in (0,1)])
def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
def seg_dist(a,b,c,d):
    if cross(a,b,c)*cross(a,b,d)<0 and cross(c,d,a)*cross(c,d,b)<0:return 0
    return min(line_distance(a,c,d),line_distance(b,c,d),line_distance(c,a,b),line_distance(d,a,b))
def inside(p,poly):
    signs=[cross(a,b,p) for a,b in zip(poly,poly[1:]+poly[:1])]
    return all(v>=0 for v in signs) or all(v<=0 for v in signs)
def segment_to_poly(a,b,poly):
    if inside(a,poly) or inside(b,poly):return 0
    return min(seg_dist(a,b,c,d) for c,d in zip(poly,poly[1:]+poly[:1]))
def transform(b,x,y):
    angle=math.radians(b['angle'])
    return [b['x']+math.cos(angle)*x-math.sin(angle)*y,b['y']+math.sin(angle)*x+math.cos(angle)*y]

catalog=(ROOT/'scripts/world/village_building_catalog.gd').read_text(encoding='utf-8')
for ident,m in D['models'].items():
    block=re.search(r'"id": "'+ident+r'"(.*?)\}',catalog,re.S)[1]
    for key,field in [('width','width'),('depth','depth'),('door_width','entry_width')]:
        actual=float(re.search(r'"'+field+r'": ([\d.]+)',block)[1]);check(actual==m[key],ident+' '+key)
    x,_,z=map(float,re.search(r'"entry": Vector3\(([^)]+)\)',block)[1].split(','))
    check(x==m['door_x'] and z==m['depth']/2,ident+' threshold location')
check(len(D['buildings'])==8,'eight proposed buildings')
check([b['model'] for b in D['buildings'] if b['phase']==1]==['H01','W01','B01'],'only three existing models in first slice')
polygons={};clearances={}
for b in D['buildings']:
    m=D['models'][b['model']];w,h=m['width']/2,m['depth']/2
    poly=[transform(b,x,y) for x,y in [(-w,-h),(w,-h),(w,h),(-w,h)]]
    polygons[b['id']]=poly
    yard=b['yard']
    check(all(yard[0]<=x<=yard[0]+yard[2] and yard[1]<=y<=yard[1]+yard[3] for x,y in poly),b['id']+' walls in yard')
    clear=min(segment_to_poly(a,c,poly)-r['width']/2 for r in D['roads'] for a,c in zip(r['points'],r['points'][1:]))
    clearances[b['id']]=round(clear,2)
    check(clear>=0.6,b['id']+' wall/road clearance '+str(clear))
    door=transform(b,m['door_x'],h);out=transform(b,m['door_x'],h+1)
    front=sum((b['gate'][i]-door[i])*(out[i]-door[i]) for i in (0,1))
    check(front>=m['front_clearance'],b['id']+' approach depth')
    nearest=min(line_distance(b['gate'],a,c) for r in D['roads'] for a,c in zip(r['points'],r['points'][1:]))
    check(nearest<0.2,b['id']+' gate connected')
for b in D['buildings']:
    m=D['models'][b['model']];door=transform(b,m['door_x'],m['depth']/2)
    for other,poly in polygons.items():
        if other==b['id']:continue
        check(segment_to_poly(door,b['gate'],poly)>0.6,b['id']+' approach crosses '+other)
    for other,poly in polygons.items():
        if other<=b['id']:continue
        gap=min(segment_to_poly(a,c,poly) for a,c in zip(polygons[b['id']],polygons[b['id']][1:]+polygons[b['id']][:1]))
        check(gap>4,b['id']+' / '+other+' wall gap')
profile=json.loads((HERE/'metrics.json').read_text(encoding='utf-8'))['height_profile']
slopes=[abs(b['height_m']-a['height_m'])/(b['distance_m']-a['distance_m']) for a,b in zip(profile,profile[1:])]
check(max(slopes)<0.06,'proposed street slopes below 6 percent')
reader=PdfReader(HERE/'AshBound-Forest-Yards-B-v1.1.pdf')
check(len(reader.pages)==2,'PDF has two pages')
for i,page in enumerate(reader.pages):
    text=page.extract_text()
    check('НЕ СОГЛАСОВАНО' in text and '\ufffd' not in text,'PDF proposal label and glyphs '+str(i))
report={'version':D['version'],'checks':checks,'failures':[],'wall_to_road_clearance_m':clearances,'maximum_proposed_street_slope_percent':round(max(slopes)*100,2),'review':'Technical diagram checks; 3D sightlines/roof overhang/terrain/camera remain future QA after approval.'}
(HERE/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=True))
