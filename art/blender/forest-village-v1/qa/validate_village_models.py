"""Coordinator-only independent inspection of actual saved Blender geometry."""
from pathlib import Path
import bpy, json, math
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'art/blender/forest-village-v1'
REPORT=ROOT/'local/previews/forest-village-v1/model-qa.json'
cases={
 'H01':dict(width=6,depth=8,floor=.36,entry_x=-1.25,entry_width=1.15,entry_height=2.2),
 'W01':dict(width=7,depth=9,floor=.36,entry_x=.5,entry_width=2.4,entry_height=2.6),
 'B01':dict(width=8,depth=10,floor=.24,entry_x=0,entry_width=3,entry_height=3),
}
results=[]
specs={s['id']:s for s in json.loads((OUT/'build-data.json').read_text())['buildings']}

def ray_hits(objects,origin,direction,distance):
    origin=Vector(origin);direction=Vector(direction).normalized();hits=[]
    graph=bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        ev=obj.evaluated_get(graph); inv=ev.matrix_world.inverted_safe()
        local_origin=inv@origin;local_dir=(inv.to_3x3()@direction).normalized()
        hit,point,normal,index=ev.ray_cast(local_origin,local_dir)
        if hit:
            world=ev.matrix_world@point
            along=(world-origin).dot(direction)
            if -.001<=along<=distance+.001:hits.append(obj.name)
    return hits

for key,d in cases.items():
    blend=OUT/(key.lower()+'.blend')
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    objects=[o for o in bpy.data.objects if o.get('building_id')==key]
    meshes=[o for o in objects if o.type=='MESH']
    failures=[];notes={}
    def check(ok,name,detail=None):
        if not ok:failures.append(dict(check=name,detail=detail))
    check(all(o.get('building_id')==key for o in bpy.data.collections['ASSET'].objects),'all-asset-parts-tagged')
    check(len(meshes)>15,'nontrivial-building',len(meshes))
    check(bpy.context.scene.unit_settings.scale_length==1,'metres')
    tris=0
    for o in meshes:
        o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
        check(len(o.data.materials)>0,'material',o.name)
        check(len(o.data.uv_layers)>0,'uv',o.name)
        check(len(o.data.polygons)>0,'nonempty-mesh',o.name)
        check(all(math.isfinite(v) for row in o.matrix_world for v in row),'finite-transform',o.name)
    check(tris<60000,'triangle-budget',tris)
    hinges=[o for o in objects if o.get('part_role')=='door_hinge']
    check(bool(hinges),'entry-door-hinges')
    # At normal walking height, the saved closed entrance must actually be closed.
    sample_x=d['entry_x']+min(.22,d['entry_width']/4)
    y=-d['depth']/2
    closed=ray_hits(meshes,(sample_x,y-.45,d['floor']+1.0),(0,1,0),.9)
    check(bool(closed),'closed-door-blocks',closed)
    for o in hinges:
        angle=o.get('open_angle_degrees')
        check(angle is not None,'hinge-has-open-angle',o.name)
        if angle is not None:o.rotation_euler.z=math.radians(float(angle))
    bpy.context.view_layer.update()
    entry_hits=[]
    for x in [d['entry_x']-.3,d['entry_x'],d['entry_x']+.3]:
        for z in [d['floor']+.1,d['floor']+.9,d['floor']+1.8]:
            hits=ray_hits(meshes,(x,y-.32,z),(0,1,0),.7)
            if hits:entry_hits.append(dict(x=x,z=z,objects=hits))
    check(not entry_hits,'open-entrance-clear-at-9-samples',entry_hits)
    for opening in specs[key]['openings']:
        if opening['kind'] not in ('window','vent'):continue
        centre=opening['center'];z=opening['bottom']+opening['height']/2
        face=opening['face']
        origins={'front':(centre,-d['depth']/2-.35,z),'rear':(centre,d['depth']/2+.35,z),'left':(-d['width']/2-.35,centre,z),'right':(d['width']/2+.35,centre,z)}
        directions={'front':(0,1,0),'rear':(0,-1,0),'left':(1,0,0),'right':(-1,0,0)}
        hits=ray_hits(meshes,origins[face],directions[face],.7)
        check(not hits,'window-or-vent-open-'+opening['id'],hits)
    if key=='B01':
        hits=ray_hits(meshes,(-2.2,.75,3.7),(0,1,0),.6)
        check(not hits,'loft-rail-access-gap',hits)
        hits=ray_hits(meshes,(-2.2,-.55,d['floor']+.5),(0,1,0),.12)
        check(not hits,'ladder-approach-no-grain-bin',hits)
    # Opposite control point through opaque rear wall must remain a real barrier.
    rear=ray_hits(meshes,(d['width']/2-.7,d['depth']/2+.45,d['floor']+.65),(0,-1,0),.9)
    check(bool(rear),'rear-wall-solid',rear)
    # Occupied central aisle and entrance to room can be evaluated without a game controller.
    centre=ray_hits(meshes,(0,-d['depth']/2+.8,d['floor']+.8),(0,1,0),d['depth']-1.6)
    # H01 entrance is offset; central route's furnishings are separately reviewed visually.
    if key in ('W01','B01'):check(not centre,'central-aisle-clear',centre)
    images=[im for im in bpy.data.images if im.source=='FILE']
    check(bool(images),'baked-images-present')
    check(all(im.packed_file is not None or Path(bpy.path.abspath(im.filepath)).is_file() for im in images),'images-resolve')
    notes.update(meshes=len(meshes),triangles=tris,door_hinges=len(hinges),baked_images=len(images),closed_entry_hits=closed,central_aisle_hits=centre)
    results.append(dict(asset=key,status='FAIL' if failures else 'PASS',failures=failures,measurements=notes))
REPORT.parent.mkdir(parents=True,exist_ok=True)
REPORT.write_text(json.dumps(dict(results=results),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('VILLAGE_MODEL_QA',json.dumps(results,ensure_ascii=False))
if any(r['failures'] for r in results):raise RuntimeError('Independent model checks failed; see model-qa.json')
