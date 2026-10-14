"""PDF141 native residential footprints. Blender5.2, no wp or historical QA inputs.
blender --background --factory-startup --python-exit-code 1 --python THIS_FILE
XY footprint, Z up; exported Godot +Z front, Y=0 walking floor, unit scale.
Only four GLBs are written outside ignored local/qa/desert-residential-family.
"""
import sys, math, json, struct, hashlib
from pathlib import Path
import bpy, bmesh

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'art/blender'))
import buildings_common as C
OUT = ROOT / 'assets/buildings/world-architecture-v1'
QA = ROOT / 'local/qa/desert-residential-family'
VARIANTS = [('d_home_6x5', 6, 5, False), ('d_home_7x6', 7, 6, False),
            ('d_home_6x6', 6, 6, False), ('d_poor_home_6x5', 6, 5, True)]
OUT.mkdir(parents=True, exist_ok=True)
QA.mkdir(parents=True, exist_ok=True)


def build(identity, w, d, poor):
    C.reset()
    collisions = []
    textures = ROOT / 'assets/environment/village-house-materials-v1'

    def surface(name, filename, tint, metres):
        m = C.mat(name, (*tint, 1), .96)
        m['uv_metres'] = metres
        m['tint'] = list(tint)
        tex = m.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(str(textures / filename), check_existing=True)
        tex.image.pack()
        m.node_tree.links.new(tex.outputs['Color'], m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
        return m

    plaster = surface('DR rough ochre adobe' if poor else 'DR warm lime plaster',
                      'plaster_grey_04_diff_1k.jpg', (.66, .49, .32) if poor else (.78, .68, .52), 2.5)
    stone = surface('DR sandstone', 'stone_wall_02_diff_1k.jpg', (.72, .63, .49), 2)
    wood = surface('DR dark oak', 'fine_grained_wood_col_1k.jpg', (.32, .23, .15), .65)
    clay = C.mat('DR fired clay', (.39, .20, .12, 1), .96)
    cloth = C.mat('DR worn dark wool' if poor else 'DR dark ochre wool',
                  (.08,.07,.05,1) if poor else (.12,.10,.075,1),.99)
    cloth['uv_metres']=.25
    wool_image=bpy.data.images.new(identity+' wool weave',width=64,height=64)
    wool_pixels=[]
    for iy in range(64):
        for ix in range(64):
            value=.22+.018*math.sin(ix*.7)+.015*math.sin(iy*.65)
            wool_pixels.extend([value,value*.93,value*.84,1])
    wool_image.pixels.foreach_set(wool_pixels);wool_image.pack()
    wool_tex=cloth.node_tree.nodes.new('ShaderNodeTexImage');wool_tex.image=wool_image
    cloth.node_tree.links.new(wool_tex.outputs['Color'],cloth.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    straw = C.mat('DR thin straw tick', (.36, .29, .18, 1), .99)
    iron = C.mat('DR forged iron', (.095, .09, .075, 1), .82)

    def box(name, p, s, mat, solid=False, interior=False, bevel=.015):
        ob = C.box(name, p, s, mat, bevel)
        if interior:
            ob['part_role'] = 'interior_furniture'
        if solid:
            collisions.append((name, p, s, interior))
        return ob

    # Every surface and shade support stays within the book plot. No stretched models.
    box('model floor', (0, 0, -.12), (w, d, .24), stone, True, bevel=0)
    front, back = -d / 2 + .2, d / 2 - .2
    height = 2.82
    for a, b in [(-w / 2, -.87), (.87, w / 2)]:
        box('front adobe pier', ((a + b) / 2, front, height / 2), (b-a, .4, height), plaster, True, bevel=0)
    box('structural timber lintel',(0,front,2.45),(1.74,.4,.20),wood,True,bevel=0)
    box('adobe above entry',(0,front,(2.55+height)/2),(1.74,.4,height-2.55),plaster,True,bevel=0)
    for x in (-w / 2 + .2, w / 2 - .2):
        box('side adobe wall', (x, 0, height / 2), (.4, d-.8, height), plaster, True, bevel=0)
    # Rear window is a true cut through all plaster and collision, with inset wooden shutter.
    window = .62 if poor else .9
    for a, b in [(-w/2, -.5-window/2), (-.5+window/2, w/2)]:
        box('rear adobe pier', ((a+b)/2, back, height/2), (b-a, .4, height), plaster, True, bevel=0)
    for z0, z1 in [(0, 1.4), (2.15, height)]:
        box('window sill wall' if z0 == 0 else 'window header', (-.5, back, (z0+z1)/2),
            (window, .4, z1-z0), plaster, True, bevel=0)
    for dx in (-window/2+.035, window/2-.035):
        box('window jamb', (-.5+dx, back, 1.775), (.07, .4, .75), wood)
    for z in (1.435, 2.115):
        box('window rail', (-.5, back, z), (window-.14, .4, .07), wood)
    # Half shutters leave an open central slit; shelter is readable from outside and inside.
    for dx in (-window*.34, window*.34):
        box('window shutter', (-.5+dx, back+.13, 1.775), (window*.27, .04, .67), wood)
    # Flat timber-supported adobe roof, no hidden substitute roof collider.
    box('flat adobe roof', (0, 0, 2.96), (w, d, .28), plaster, True, bevel=0)
    for x in [(-w/2+.55)+i*(w-1.1)/5 for i in range(6)]:
        box('roof joist', (x, 0, 2.75), (.14, d-.7, .14), wood)
    for x in (-w/2+.16, w/2-.16):
        box('side parapet', (x, 0, 3.31), (.32, d, .42), plaster, True, bevel=0)
    for y in (-d/2+.16, d/2-.16):
        box('end parapet', (0, y, 3.31), (w-.64, .32, .42), plaster, True, bevel=0)
    if not poor:
        for x in (-w/2+.17, w/2-.17):
            box('lime coping', (x, 0, 3.535), (.34, d, .03), stone, bevel=0)
        for y in (-d/2+.17, d/2-.17):
            box('lime coping', (0, y, 3.535), (w-.68, .34, .03), stone, bevel=0)
    else:
        # Plaster has flaked off in patches, exposing the raw mud brick underneath.
        mudbrick = surface('DR exposed mud brick', 'stone_wall_02_diff_1k.jpg', (.55, .38, .24), 1.2)
        for x, z, width, height in [(-2.2, .55, .7, .5), (1.75, 1.6, .55, .4), (-1.5, 2.2, .45, .3)]:
            box('mudbrick patch', (x, -d/2-.006, z), (width, .012, height), mudbrick, bevel=.01)
        for y, z, width, height in [(-.8, .9, .8, .6), (1.2, 2.0, .5, .35)]:
            box('mudbrick patch', (-w/2-.006, y, z), (.012, width, height), mudbrick, bevel=.01)
        box('mudbrick patch', (1.6, d/2+.006, .75), (.7, .012, .45), mudbrick, bevel=.01)
        # Reed shade mat over the roof instead of an empty terrace.
        for x in (-w/2+.6, -.2):
            for y in (-d/2+.8, d/2-.8):
                box('roof shade pole', (x, y, 3.75), (.08, .08, 1.3), wood)
        box('reed roof mat', (-w/4+.2, 0, 4.42), (w/2+.1, d-1.4, .05), straw)
        for y in (-d/2+.8, 0, d/2-.8):
            box('reed mat batten', (-w/4+.2, y, 4.38), (w/2+.2, .06, .06), wood)
    # Deep entrance reveal and supported reed shade inside the plot boundary.
    for x in (-.79, .79):
        box('entry reveal', (x, front+.25, 1.175), (.16, .9, 2.35), stone if not poor else plaster, True, bevel=0)
    box('shade lintel beam', (0, front+.3, 2.49), (1.85, .15, .16), wood)
    for x in (-.81, .81):
        box('shade bracket', (x, front+.47, 2.38), (.12, .38, .12), wood)
    for i in range(10):
        box('reed shade slat', (-.85+i*.19, front+.47, 2.51), (.13, .55, .055), wood)
    # Desert exterior: joist ends through the walls, roof spouts, a roof ladder, a stone foot band.
    for x in [(-w/2+.55)+i*(w-1.1)/5 for i in range(6)]:
        box('joist end', (x, d/2+.07, 2.75), (.14, .14, .14), wood)
        if abs(x) >= .95:
            box('joist end', (x, -d/2-.07, 2.75), (.14, .14, .14), wood)
    for x in (-w/2+1.0, w/2-1.0):
        box('roof spout', (x, d/2+.16, 3.18), (.12, .32, .10), clay)
    for dy in (-.22, .22):
        box('roof ladder rail', (w/2+.09, d/2-1.0+dy, 1.85), (.06, .06, 3.7), wood)
    z = .35
    while z <= 3.35:
        box('roof ladder rung', (w/2+.09, d/2-1.0, z), (.05, .5, .05), wood)
        z += .3
    if not poor:
        box('stone foot band', (-w/2-.015, 0, .2), (.03, d, .4), stone)
        box('stone foot band', (w/2+.015, 0, .2), (.03, d, .4), stone)
        box('stone foot band', (0, d/2+.015, .2), (w+.06, .03, .4), stone)
        for a, b in [(-w/2, -.87), (.87, w/2)]:
            box('stone foot band', ((a+b)/2, -d/2-.015, .2), (b-a, .03, .4), stone)

    hinge = bpy.data.objects.new('DR_entry_hinge', None)
    C.ASSET.objects.link(hinge)
    door_plane = front+.45
    hinge.location = (-.66, door_plane, 0)
    hinge['open_angle_degrees'] = -100.0
    door_parts = []
    for i in range(5):
        door_parts.append(box('Door entry plank', (-.528+i*.264, door_plane, 1.145), (.258, .085, 2.29), wood, bevel=.008))
    for z in (.45, 1.75):
        door_parts.append(box('Door strap', (0, door_plane-.055, z), (1.30, .022, .07), iron, bevel=.005))
    for ob in door_parts:
        matrix = ob.matrix_world.copy()
        ob.parent = hinge
        ob.matrix_world = matrix

    # Adult wooden box bed and thin tick; poor houses sleep on a reed mat. Aisle stays >1.3m.
    bx, by = -w/2+1.02, d/2-1.57
    if not poor:
        box('bed wooden box', (bx, by, .28), (1.12, 2.10, .22), wood, True, True)
        for dx in (-.45, .45):
            for dy in (-.91, .91):
                box('bed feet', (bx+dx, by+dy, .085), (.12, .12, .17), wood, interior=True)
        box('bed headboard', (bx, by+.995, .56), (1.12, .11, .65), wood, True, True)
    else:
        box('sleeping reed mat', (bx, by, .02), (1.05, 2.05, .04), straw, interior=True, bevel=.01)
    tick_z = .425 if not poor else .06
    box('thin straw tick', (bx, by, tick_z), (1.04, 2.0, .07), straw, interior=True, bevel=.025)
    box('wool blanket', (bx, by-.27, .468 if not poor else .095), (1.05, 1.33, .016), cloth, interior=True, bevel=.007)
    box('folded wool bolster', (bx, by+.76, .48 if not poor else .10), (.82, .22, .08), cloth, interior=True, bevel=.025)
    tx, ty = w/2-1.04, .45
    box('table top', (tx, ty, .78), (.85, 1.05, .09), wood, True, True)
    for dx in (-.32, .32):
        for dy in (-.42, .42):
            box('table leg', (tx+dx, ty+dy, .368), (.09, .09, .736), wood, True, True)
    sx, sy = tx, -.48
    box('stool seat', (sx, sy, .45), (.4, .4, .08), wood, True, True)
    for dx in (-.13, .13):
        for dy in (-.13, .13):
            box('stool leg', (sx+dx, sy+dy, .205), (.08, .08, .41), wood, True, True)
    # Plain storage box in poor houses; fitted lid/iron binding in ordinary ones.
    cx, cy = -w/2+1, -d/2+1.05
    box('storage chest', (cx, cy, .29), (1, .55, .58), wood, True, True)
    box('chest lid', (cx, cy, .61), (1.03, .58, .06), wood, interior=True)
    if not poor:
        for dx in (-.36, .36):
            box('chest binding', (cx+dx, cy, .648), (.045, .59, .018), iron, interior=True)
    px, py = w/2-.625, d/2-.76
    for z in ((.85, 1.45) if not poor else (1.2,)):
        box('wall shelf', (px, py, z), (.45, 1, .07), wood, interior=True)
        for dy in (-.36, .36):
            box('shelf bracket', (px+.08, py+dy, z-.13), (.30, .08, .20), wood, interior=True)

    def pot(name, x, y, bottom, h, r):
        verts, faces, n = [], [], 12
        rings = [(0,.65), (.08,.78), (.35,1), (.72,.80), (.9,.5), (1,.52), (.99,.39), (.89,.39)]
        for z, scale in rings:
            for k in range(n):
                t = k*math.tau/n
                verts.append((x+r*scale*math.cos(t), y+r*scale*math.sin(t), bottom+z*h))
        for j in range(len(rings)-1):
            for k in range(n):
                faces.append((j*n+k,j*n+(k+1)%n,(j+1)*n+(k+1)%n,(j+1)*n+k))
        faces.append(tuple(reversed(range(n))))
        ob = C.mesh(name, verts, faces, clay)
        ob['part_role'] = 'interior_furniture'
    pot('table pitcher', tx, ty+.15, .825, .30, .115)
    pot('water jar', w/2-.82, -d/2+1.1, 0, .65, .25)
    # Small permanent wall niche with an ochre backing, visually distinct in the larger square.
    if d == 6:
        box('rear storage ledge', (.5, back-.27, .93), (.85, .35, .08), wood, interior=True)
        pot('storage bowl', .5, back-.27, .97, .13, .18)

    def marker(name, loc):
        ob = bpy.data.objects.new(name, None)
        C.ASSET.objects.link(ob)
        ob.location = loc
        return ob
    spec = marker('ResidenceContract', (0,0,0))
    spec['variant'] = identity
    spec['wall_footprint'] = [w,d]
    spec['bed_length'] = 2.1
    spec['clear_door'] = [1.4,2.35]
    spec['poor_adobe'] = poor
    spec['godot_entry_z'] = d/2-.65
    marker('LampAnchor', (.35,.1,2.08))
    marker('LampCeiling', (.35,.1,2.82))
    # UVs in metres, continuous plaster weathering confined to the foot of the wall.
    visual = [o for o in C.ASSET.objects if o.type == 'MESH']
    for ob in visual:
        material = ob.data.materials[0]
        scale = material.get('uv_metres', 0)
        if not scale:
            continue
        bm = bmesh.new(); bm.from_mesh(ob.data)
        if material == plaster:
            edges = [e for e in bm.edges if e.calc_length()>1]
            bmesh.ops.subdivide_edges(bm, edges=edges, cuts=2, use_grid_fill=True)
        uv = bm.loops.layers.uv.verify()
        for face in bm.faces:
            axis = max(range(3),key=lambda i:abs(face.normal[i]))
            for loop in face.loops:
                p = ob.matrix_world @ loop.vert.co
                u,v = (p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y)
                loop[uv].uv=(u/scale,v/scale)
        bm.to_mesh(ob.data); bm.free()
        if material == plaster:
            attr=ob.data.color_attributes.new(name='Weather',type='FLOAT_COLOR',domain='CORNER')
            for k,loop in enumerate(ob.data.loops):
                p=ob.matrix_world @ ob.data.vertices[loop.vertex_index].co
                dirt=(.25 if poor else .15)*max(0,1-p.z/.85)
                shade=1-dirt-.035*(.5+.5*math.sin(p.x*5.2+p.y*2.3))
                attr.data[k].color=(shade,shade,shade,1)
            ob.data.color_attributes.active_color=attr
    static = [o for o in visual if o not in door_parts]
    groups = [[o for o in static if (o.get('part_role')=='interior_furniture') == interior
               and o.name != 'bed wooden box'] for interior in (False, True)]
    for group in groups:
        C._join_by_material(group)
    for name,p,s,interior in collisions:
        ob = box(name+'-colonly', p, s, plaster, bevel=0)
        ob.hide_render = True
        ob['collision_only'] = True
        # Static obstacle layer8 is applied at runtime, never the floor/walls.
        ob['furniture_obstacle'] = interior
    bpy.ops.object.select_all(action='DESELECT')
    for ob in C.ASSET.objects:
        ob.select_set(True)
    path = OUT/(identity+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),use_selection=True,export_format='GLB',
        export_apply=True,export_yup=True,export_extras=True,export_all_vertex_colors=True,
        export_materials='EXPORT',export_cameras=False,export_lights=False)
    data=path.read_bytes(); length=struct.unpack_from('<I',data,12)[0]
    document=json.loads(data[20:20+length])
    tints={m.name:list(m['tint']) for m in bpy.data.materials if 'tint' in m}
    for m in document['materials']:
        if m['name'] in tints:
            m['pbrMetallicRoughness']['baseColorFactor']=[*tints[m['name']],1]
    encoded=json.dumps(document,separators=(',',':'),ensure_ascii=False).encode()
    encoded+=b' '*((-len(encoded))%4)
    remaining=data[20+length:]
    path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(remaining))+
                     struct.pack('<II',len(encoded),0x4e4f534a)+encoded+remaining)
    visual=[o for o in C.ASSET.objects if o.type=='MESH' and not o.get('collision_only')]
    points=[o.matrix_world@v.co for o in visual for v in o.data.vertices]
    tris=0
    for o in visual:
        o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
    stats={'id':identity,'wall_footprint':[w,d],'triangles':tris,'visual_meshes':len(visual),
           'collision_boxes':len(collisions),'bbox_blender':[[min(p[i] for p in points) for i in range(3)],
                                                        [max(p[i] for p in points) for i in range(3)]],
           'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    (QA/(identity+'-build.json')).write_text(json.dumps(stats,indent=2),encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(QA/(identity+'.blend')))
    print('RESIDENCE_BUILT',json.dumps(stats),flush=True)


for variant in VARIANTS:
    build(*variant)
