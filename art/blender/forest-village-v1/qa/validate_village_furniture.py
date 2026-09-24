from pathlib import Path
import sys,json,math,bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
import forest_village_materials as M
import forest_village_furniture as F
def bounds(objects):
    points=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
    return [min(v[i] for v in points) for i in range(3)],[max(v[i] for v in points) for i in range(3)]
results=[]
for spec in json.loads((ROOT/'art/blender/forest-village-v1/build-data.json').read_text())['buildings']:
    C.reset();mats=M.make_materials(ROOT/'art/blender/forest-village-v1/textures');F.build_furniture(spec,mats)
    bpy.context.view_layer.update()
    objects=list(C.ASSET.all_objects);meshes=[o for o in objects if o.type=='MESH'];failures=[]
    def check(ok,name):
        if not ok:failures.append(name)
    check(all(o.get('building_id')==spec['id'] for o in objects),'all objects tagged')
    check(len(meshes)>15,'furnished geometry exists')
    if spec['id']=='H01':
        for item,expected in [('table',(1.55,-2.1)),('bed',(1.55,2.25))]:
            parts=[o for o in meshes if o.get('item_id')==item]
            check(bool(parts),item+' exists')
            if parts:
                lo,hi=bounds(parts)
                check(abs((lo[0]+hi[0])/2-expected[0])<.1 and abs((lo[1]+hi[1])/2-expected[1])<.25,item+' world position')
                check(lo[2]>=spec['floor']-.02,item+' above floor')
    if spec['id'] in ('H01','W01'):
        hinges=[o for o in objects if o.get('part_role')=='chest_hinge']
        check(bool(hinges),'chest hinged lid exists')
        for hinge in hinges:
            lids=[o for o in hinge.children_recursive if o.type=='MESH']
            check(bool(lids),'lid is hinge child')
            if lids:
                lo,hi=bounds(lids)
                hinge.rotation_euler.x=math.radians(hinge.get('open_angle_degrees',0));bpy.context.view_layer.update()
                newlo,newhi=bounds(lids)
                check(newhi[2]>hi[2]+.25,'chest opens upward')
                hinge.rotation_euler.x=0
    if spec['id']=='B01':
        bales=[o for o in meshes if 'bale' in o.name.lower()]
        check(bool(bales),'hay bales exist')
        for bale in bales:
            lo,hi=bounds([bale]);check(3.36<=lo[2]<=3.48,'hay rests on loft')
    results.append(dict(asset=spec['id'],status='FAIL' if failures else 'PASS',meshes=len(meshes),failures=failures))
out=ROOT/'art/previews/forest-village-v1/furniture-qa.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
print('FURNITURE_QA',json.dumps(results))
if any(r['failures'] for r in results):raise RuntimeError('Furniture QA failed')
