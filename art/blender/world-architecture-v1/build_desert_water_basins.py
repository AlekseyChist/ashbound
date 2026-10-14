"""Book141 desert water branch: cooling7x5 and drinking6x5 basins."""
import sys,json,struct,hashlib,math
from pathlib import Path
import bpy,bmesh
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
OUT=ROOT/'assets/buildings/world-architecture-v1';OUT.mkdir(parents=True,exist_ok=True)
QA=ROOT/'local/previews/world-architecture-v1/desert-water-basins';QA.mkdir(parents=True,exist_ok=True)
def build(name,width,depth):
    C.reset()
    stone=C.mat('DW weathered sandstone',(1,1,1,1),.96);stone['uv_metres']=2
    tex=stone.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1/stone_wall_02_diff_1k.jpg'));tex.image.pack()
    stone.node_tree.links.new(tex.outputs['Color'],stone.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    water=C.mat('DW quiet water',(.12,.28,.25,1),.30)
    im=bpy.data.images.new('DW water paint',width=128,height=128)
    pixels=[]
    for y in range(128):
        for x in range(128):
            v=.012*math.sin(x*.16+y*.025)+.006*math.sin(y*.19-x*.07)
            pixels.extend([max(0,t+v) for t in (.12,.28,.25)]+[1])
    im.pixels.foreach_set(pixels);im.pack()
    wt=water.node_tree.nodes.new('ShaderNodeTexImage');wt.image=im
    water.node_tree.links.new(wt.outputs['Color'],water.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    coll=[]
    def box(n,p,s):
        o=C.box(n,p,s,stone,.015);coll.append((n,p,s));return o
    box('basin foundation',(0,0,-1.12),(width,depth,.24))
    ports=[('Inlet','y',-depth/2+.15,-2.8),('Outlet','x',width/2-.15,0)] if name=='d_cooling_pond' else [('Inlet','x',-width/2+.15,0)]
    def wall(axis,fixed,lo,hi,port):
        bands=[(lo,hi,-1,.22)] if port is None else [(lo,port-.3,-1,.22),(port+.3,hi,-1,.22),(port-.3,port+.3,-1,-.15),(port-.3,port+.3,.15,.22)]
        for a,b,z0,z1 in bands:
            if b<=a:continue
            p=((a+b)/2,fixed,(z0+z1)/2) if axis=='y' else (fixed,(a+b)/2,(z0+z1)/2)
            size=(b-a,.3,z1-z0) if axis=='y' else (.3,b-a,z1-z0)
            box('ported retaining wall',p,size)
    for label,axis,fixed,along in ports:
        marker=bpy.data.objects.new(label,None);C.ASSET.objects.link(marker)
        marker.location=(along,fixed,0) if axis=='y' else (fixed,along,0)
        marker['clear_width']=.6;marker['sill_level']=-.15;marker['head_level']=.15
    # Entire outer extent includes the coping; clear inner chamber is width-.6.
    for side in (-1,1):
        y=side*(depth/2-.15);x=side*(width/2-.15)
        long_port=next((along for _,axis,fixed,along in ports if axis=='y' and abs(fixed-y)<.01),None)
        short_port=next((along for _,axis,fixed,along in ports if axis=='x' and abs(fixed-x)<.01),None)
        wall('y',y,-width/2,width/2,long_port)
        wall('x',x,-depth/2+.3,depth/2-.3,short_port)
        for k in range(int(width)):
            pitch=width/int(width)
            box('long coping block',(-width/2+(k+.5)*pitch,side*(depth/2-.16),.26),(pitch-.014,.32,.14))
        for k in range(int(depth)-1):
            pitch=(depth-.64)/(int(depth)-1)
            box('short coping block',(side*(width/2-.16),-(depth-.64)/2+(k+.5)*pitch,.26),(.32,pitch-.014,.14))
    # Water is a surface only: no invisible platform across the empty bowl.
    vertices=[(-width/2+.30,-depth/2+.30,0),(width/2-.30,-depth/2+.30,0),(width/2-.30,depth/2-.30,0),(-width/2+.30,depth/2-.30,0)]
    plane=C.mesh('WaterSurface',vertices,[(0,1,2,3)],water)
    plane['part_role']='water_surface';plane['water_level']=0.0
    visual=[o for o in C.ASSET.objects if o.type=='MESH']
    for o in visual:
        bm=bmesh.new();bm.from_mesh(o.data);uv=bm.loops.layers.uv.verify()
        for face in bm.faces:
            axis=max(range(3),key=lambda i:abs(face.normal[i]))
            for loop in face.loops:
                p=o.matrix_world@loop.vert.co
                u,v=((p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y))
                loop[uv].uv=(u/2,v/2)
        bm.to_mesh(o.data);bm.free()
    C._join_by_material([o for o in visual if o!=plane])
    for n,p,s in coll:
        o=C.box(n+'-colonly',p,s,stone,0);o.hide_render=True
    visual=[o for o in C.ASSET.objects if o.type=='MESH' and '-colonly' not in o.name]
    bpy.ops.object.select_all(action='DESELECT')
    for o in C.ASSET.objects:o.select_set(True)
    bpy.context.view_layer.objects.active=visual[0]
    target=OUT/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(target),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True)
    data=target.read_bytes();length=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+length])
    for m in doc['materials']:
        if m['name']=='DW weathered sandstone':m['pbrMetallicRoughness']['baseColorFactor']=[.70,.57,.40,1]
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);rest=data[20+length:]
    target.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(rest))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+rest)
    triangles=0
    for o in visual:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
    stats={'state':'WIP basin; pipeline/terrain/inlet/outlet pending','outer_footprint':[width,depth],'water_level':0,'floor':-1,'rim':.33,'triangles':triangles,'meshes':len(visual),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    (QA/(name+'.json')).write_text(json.dumps(stats,indent=2),encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(QA/(name+'.blend')));print('DESERT_BASIN',json.dumps(stats))
build('d_cooling_pond',7,5)
build('d_drinking_cistern',6,5)
