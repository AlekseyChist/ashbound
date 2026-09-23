"""Coordinator checks for requested world layout, connectivity and reproducibility."""
from pathlib import Path
from collections import Counter, defaultdict, deque
import json, math, hashlib, subprocess, sys
R=Path(__file__).resolve().parents[1]
D=json.loads((R/'docs/design/world-exploration-v1/world-exploration.json').read_text(encoding='utf8'))
L=json.loads((R/'assets/world/graybox-v1/layout.json').read_text(encoding='utf8'))
assert Counter(s['kind'] for s in D['sites'])==dict(settlement=4,tavern=2,cave=3,mine=1)
assert all(s['early_access'] for s in D['sites'] if s['kind']=='cave')
assert all(set(s['planned_services'])=={'rest_stop','healing','sleep','drink','quests','save'} for s in D['sites'] if s['kind']=='tavern')
sites={s['id']:s for s in D['sites']}
start=tuple(sites['start_hamlet']['point'])
assert min(math.dist(start[:2],c['point'][:2]) for c in D['cities'])>500
assert D['cities'][2]['point'][1] < 550 and D['cities'][2]['point'][0]>1650
assert not D['progression']['soft_gate']['implemented']
assert D['progression']['mine']['ancient_encounter']=='late_deep_section_not_early_caves'
# Coordinate graph includes actual interior waypoints, not just declared from/to IDs.
graph=defaultdict(set)
for r in D['roads']:
    for a,b in zip(r['points'],r['points'][1:]):
        a,b=tuple(a),tuple(b)
        assert a!=b and math.dist(a[:2],b[:2])>0
        assert abs(a[2]-b[2])/math.dist(a[:2],b[:2])<0.4,(r['id'],a,b)
        graph[a].add(b);graph[b].add(a)
seen={start};todo=deque([start])
while todo:
    for p in graph[todo.popleft()]:
        if p not in seen:seen.add(p);todo.append(p)
assert len(seen)==len(graph),'isolated road network'
assert all(tuple(p['point']) in seen for p in D['sites']+D['cities'])
assert sum(len(v) for v in graph.values())//2-len(graph)+1>=4,'retain main and added exploration loops'
for r in L['rivers']:
    assert len(r['world_widths'])==len(r['world_points'])
    assert r['world_widths'][0]==(2 if r['id']=='east' else 12)
    assert r['world_widths'][-1]==12
    assert all(a[1]>=b[1] for a,b in zip(r['world_points'],r['world_points'][1:])),r['id']
assert len(L['roads'])==21
for lang in ['en','ru']:
    catalog=(R/f'localization/{lang}.po').read_text(encoding='utf8')
    for s in D['sites']:assert f'msgid "{s["key"]}"\nmsgstr "{s["label_"+lang]}"' in catalog
files=[R/'assets/world/graybox-v1'/f for f in ['heights.bin','colors.bin','layout.json']]
before=[hashlib.sha256(p.read_bytes()).hexdigest() for p in files]
subprocess.run([sys.executable,'-X','utf8',str(R/'art/world/graybox-v1/build.py')],check=True,cwd=R)
assert before==[hashlib.sha256(p.read_bytes()).hexdigest() for p in files],'non-deterministic bake'
print('WORLD_EXPLORATION_DATA_OK sites=10 connected_routes=21 loops>=4 repeatable=true')
