# Source: local/qa/world-plan-01/ (the book generator, outside Git by D-080); run there:
#   python export_snow.py <repo>/assets/world/snow-city-v1/plan.json
# Export the accepted book's snow city sheet (plan_snow.build(), PDF141) as plot data for the game:
# buildings (code, centre, footprint, yaw, kind, name, plinth), streets/stairs/bridge lines, the
# terrace polygons and the walls with their gates. Map metres (x east, z south), the sheet's own data.
import json, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import plan_snow

p = plan_snow.build()
out = {
    'id': 'snow_city',
    'source': 'WORLD-PLAN-01 book, plan_snow.py (PDF141, accepted D-118)',
    'frame': 'map metres (x east, z south); the game frame is map - 1000',
    'levels': {'lower': plan_snow.LOW, 'middle': plan_snow.MID, 'academy': plan_snow.ACA},
    'buildings': [{k: it[k] for k in ('code', 'x', 'z', 'w', 'd', 'yaw', 'kind', 'name', 'who', 'enter', 'refs', 'plinth')} for it in p.items],
    'lines': [{'kind': l['kind'], 'width': l['w'], 'pts': [list(map(float, q)) for q in l['pts']]} for l in p.lines],
    'terraces': [[list(map(float, q)) for q in poly[0]] for poly in p.polys],
}
dst = sys.argv[1] if len(sys.argv) > 1 else 'snow_plots.json'
open(dst, 'w', encoding='utf-8', newline='\n').write(json.dumps(out, ensure_ascii=False, indent=1) + '\n')
print('SNOW_PLOTS buildings=%d lines=%d terraces=%d -> %s' % (len(out['buildings']), len(out['lines']), len(out['terraces']), dst))
