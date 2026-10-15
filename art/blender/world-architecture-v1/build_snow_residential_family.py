"""Six native-size Snow residences. Blender5.2 --background --python-exit-code 1.
Source dimensions are metres; Blender (x,y,z) -> Godot (x,z,-y).
No geometry is derived by scaling a GLB. Runtime and previews are separate.
"""
import sys, math, json, hashlib, struct, random
from pathlib import Path
import bpy, bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/blender'))
import buildings_common as C
OUT=ROOT/'assets/buildings/world-architecture-v1'
QA=ROOT/'local/qa/snow-residential-family'
OUT.mkdir(parents=True,exist_ok=True);QA.mkdir(parents=True,exist_ok=True)
FAMILY=[('s_home_8x6',8,6,False),('s_home_9x6',9,6,False),('s_home_8x5',8,5,False),('s_home_7x5',7,5,False),('s_home_6x5',6,5,False),('s_cottage_6x5',6,5,True)]
FACES=[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
def surface(name,file,tint,metres):
    m=C.mat(name,(*tint,1),.96);m['uv_metres']=metres
    im=bpy.data.images.load(str(ROOT/'assets/environment/village-house-materials-v1'/file),check_existing=True);im.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m

def paint(name,color):
    m=C.mat(name,(*color,1),.95)
    im=bpy.data.images.new(name+'_paint',width=256,height=256);pixels=[]
    for y in range(256):
        for x in range(256):
            variation=.022*math.sin(x*.039+y*.023)+.012*math.sin(y*.073-x*.013)+random.uniform(-.004,.004)
            pixels.extend([max(0,min(1,t+variation)) for t in color]+[1])
    im.pixels.foreach_set(pixels);im.pack()
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im
    m.node_tree.links.new(tex.outputs['Color'],m.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    return m

def build(slug,w,d,poor):
    C.reset();random.seed(11801)
    stone=surface('S cool stone','stone_wall_02_diff_1k.jpg',(.61,.66,.68),2)
    plaster=surface('S grey limewash','plaster_grey_04_diff_1k.jpg',(.78,.80,.76),3)
    wood=surface('S dark timber','fine_grained_wood_col_1k.jpg',(.30,.24,.18),.65)
    slate=paint('S slate',(.10,.135,.15))
    linen=C.mat('S warm linen',(.35,.31,.23,1),.98)
    iron=C.mat('S iron',(.07,.075,.078,1),.9)
    clay=C.mat('S stove clay',(.27,.24,.20,1),.97)
    collision=[];roof_collision=[];furniture=[];beds=[]
    h=2.6 if poor else 3.1;rise=1.85 if poor else w*.5
    ridge=h+rise;ex=w/2+.28;ey=d/2+.32
    xf=w/2-.18;yf=d/2-.18;cx=w/2-.95;cy=d/2-1.00
    def box(n,p,s,m,solid=False,inside=False):
        o=C.box(n,p,s,m,0 if m==plaster or n=='floor' else .012)
        if inside:o['part_role']='interior_furniture';furniture.append(o)
        if solid:collision.append((n,p,s))
        return o
    def wx(n,y,a,b,lo=0,hi=h,m=None):
        return box(n,((a+b)/2,y,(lo+hi)/2),(b-a,.36,hi-lo),m or (wood if poor else plaster),True)
    def wy(n,x,a,b,lo=0,hi=h,m=None):
        return box(n,(x,(a+b)/2,(lo+hi)/2),(.36,b-a,hi-lo),m or (wood if poor else plaster),True)
    box('floor',(0,0,-.12),(w,d,.24),wood,True)
    wx('entry left',-yf,-w/2,-.65);wx('entry right',-yf,.65,w/2)
    wx('entry lintel',-yf,-.65,.65,2.35)
    wy('west wall',-xf,-yf+.18,yf-.18);wy('east wall',xf,-yf+.18,yf-.18)
    # Two real rear apertures; all fittings stay below their sill or outside jambs.
    windows=[-w/2+1.15,w/2-2.1] if not poor else [-w/2+1.15]
    edge=-w/2
    for x in windows:
        wx('rear pier',yf,edge,x-.45);wx('rear sill',yf,x-.45,x+.45,0,1.45)
        wx('rear header',yf,x-.45,x+.45,2.25)
        for dx in (-.50,.50):box('window jamb',(x+dx,yf,1.85),(.08,.40,.86),wood)
        for z in (1.45,2.25):box('window rail',(x,yf,z),(1.08,.40,.08),wood)
        box('window mullion',(x,yf,1.85),(.06,.12,.80),wood)
        box('window ledge',(x,yf,1.39),(1.12,.46,.10),stone)
        edge=x+.45
    wx('rear pier',yf,edge,w/2)
    if not poor:
        for a,b in [(-w/2,-.65),(.65,w/2)]:box('front stone belt',((a+b)/2,-d/2-.03,.21),(b-a,.12,.42),stone)
        box('rear stone belt',(0,d/2+.03,.21),(w+.10,.12,.42),stone)
        for x in (-w/2-.03,w/2+.03):box('side stone belt',(x,0,.21),(.12,d,.42),stone)
    else:
        # Low timber cottage: boarded skin with horizontal seam battens, stone sill.
        for z in (.35,.85,1.35,1.85,2.35):
            for x in (-xf-.20,xf+.20):box('weathered board seam',(x,0,z),(.035,d-.4,.045),wood)
        for x in (-xf,xf):box('cottage sill',(x,0,.10),(.42,d,.20),stone)
    for x in (-xf,xf):
        for y in (-yf,yf):box('corner post',(x,y,h/2),(.22,.22,h),wood)
    for y in (-yf,yf):box('wall plate',(0,y,h-.10),(w,.22,.20),wood)
    for x in (-xf,xf):box('side plate',(x,0,h-.10),(.22,d-.36,.20),wood)
    for x in (-.72,.72):box('entry jamb',(x,-yf,1.17),(.12,.43,2.34),wood)
    box('entry head',(0,-yf,2.42),(1.56,.43,.14),wood)
    # Real ceiling aperture: the masonry stack fills it continuously.
    for a,b in [(-xf,cx-.30),(cx+.30,xf)]:box('loft ceiling',((a+b)/2,0,h),(b-a,d-.36,.14),wood,True)
    for a,b in [(-yf+.18,cy-.30),(cy+.30,yf-.18)]:
        if b>a:box('loft ceiling', (cx,(a+b)/2,h),(.60,b-a,.14),wood,True)
    for y in (-yf,yf):
        vs=[(-w/2,y-.12,h),(w/2,y-.12,h),(0,y-.12,ridge),(-w/2,y+.12,h),(w/2,y+.12,h),(0,y+.12,ridge)]
        gable_faces=[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)]
        C.mesh('closed gable',vs,gable_faces,wood if poor else plaster)
        # its own triangular prism as a collider (Codex 338 CAM-VS3-01: the camera's spring arm passed
        # through the uncollided gable of vs4 and the hero was hidden behind it)
        roof_collision.append((vs,gable_faces))
        for side in (-1,1):C.beam('gable rake',(side*w/2,y-.15,h),(0,y-.15,ridge),.16,.18,wood)
        box('gable king post',(0,y-.16,h+rise/2),(.16,.18,rise),wood)
        box('gable tie',(0,y-.16,h+.75),(w*(1-.75/rise),.18,.15),wood)
        if not poor:
            for x in (-w*.18,w*.18):box('gable upright',(x,y-.16,h+rise*.32),(.12,.17,rise*.64),wood)
    def zroof(x):return ridge+.10-(rise+.10)*abs(x)/ex
    def roofpatch(n,x0,x1,y0,y1,lift=.0,thick=.12,solid=False):
        top=[(x0,y0,zroof(x0)+lift),(x1,y0,zroof(x1)+lift),(x1,y1,zroof(x1)+lift),(x0,y1,zroof(x0)+lift)]
        vs=top+[(x,y,z-thick) for x,y,z in top]
        C.mesh(n,vs,FACES,wood if poor else slate)
        if solid:roof_collision.append((vs,FACES))
    # Partition slabs at stack boundaries instead of covering a flue with roof faces.
    for side in (-1,1):
        xs=[-ex,0] if side<0 else [0,cx-.32,cx+.32,ex]
        ys=[-ey,cy-.32,cy+.32,ey]
        for a,b in zip(xs,xs[1:]):
            for c,e in zip(ys,ys[1:]):
                if side>0 and a>=cx-.321 and b<=cx+.321 and c>=cy-.321 and e<=cy+.321:continue
                roofpatch('roof panel',a,b,c,e,solid=True)
        # Tile overlaps are clipped against the same aperture.
        for row in range(10):
            xa=side*ex*(row+.01)/10;xb=side*ex*min(1,(row+1.04)/10)
            lo,hi=sorted((xa,xb))
            for col in range(math.ceil(2*ey/.58)+1):
                ya=max(-ey,-ey-.29+col*.58+(.29 if row%2 else 0));yb=min(ey,ya+.56)
                if yb<=ya:continue
                rects=[(lo,hi,ya,yb)]
                if side>0 and hi>cx-.32 and lo<cx+.32 and yb>cy-.32 and ya<cy+.32:
                    rects=[]
                    if lo<cx-.32:rects.append((lo,cx-.32,ya,yb))
                    if hi>cx+.32:rects.append((cx+.32,hi,ya,yb))
                    l=max(lo,cx-.32);r=min(hi,cx+.32)
                    if ya<cy-.32:rects.append((l,r,ya,cy-.32))
                    if yb>cy+.32:rects.append((l,r,cy+.32,yb))
                for a,b,c,e in rects:roofpatch('wood shingles' if poor else 'overlapping slate tile',a,b,c,e,.04,.025)
        C.beam('eaves trim',(side*ex,-ey,h),(side*ex,ey,h),.14,.14,wood)
    C.beam('ridge cap',(0,-ey-.08,ridge+.12),(0,ey+.08,ridge+.12),.18,.16,wood if poor else slate)
    # Stack and hatch are centred on the stove; top rises above uphill roof edge.
    chimney_top=zroof(cx-.32)+.65
    box('stove',(cx,cy,.68),(1.05,1.05,1.36),clay,True)
    box('stove hatch',(cx,cy-.54,.53),(.46,.06,.40),iron)
    box('stove hood',(cx,cy,1.43),(1.14,1.14,.14),stone)
    box('continuous stove flue',(cx,cy,(1.50+chimney_top)/2),(.60,.60,chimney_top-1.50),stone,True)
    # Four cap legs and cap slab leave a real smoke mouth on all four sides.
    for dx in (-.25,.25):
        for dy in (-.25,.25):box('chimney cap support',(cx+dx,cy+dy,chimney_top+.14),(.1,.1,.28),stone)
    box('chimney rain cap',(cx,cy,chimney_top+.31),(.78,.78,.10),stone)
    bedx=-w/2+1.12;bedy=d/2-1.50
    count=2 if w>=8 else 1
    for j in range(count):
        bx=bedx+j*1.55; bw=1.15 if count==2 else 1.45
        box('bed frame',(bx,bedy,.35),(bw,2.16,.18),wood,True,True)
        box('adult mattress',(bx,bedy,.51),(bw-.08,2.04,.16),linen,False,True)
        box('pillow',(bx,bedy+.70,.63),(bw-.18,.40,.09),linen,False,True)
        for dx in (-bw/2+.12,bw/2-.12):
            for dy in (-.91,.91):box('bed leg',(bx+dx,bedy+dy,.18),(.12,.12,.36),wood,False,True)
        box('headboard',(bx,bedy+1.03,.65),(bw,.10,1.05),wood,False,True)
        beds.append({'center':[bx,.51,-bedy],'length':2.04,'width':bw-.08})
    tx=-w/2+1.15;ty=-d/2+1.15
    box('table',(tx,ty,.76),(1.18,.76,.10),wood,True,True)
    for dx in (-.46,.46):
        for dy in (-.25,.25):box('table leg',(tx+dx,ty+dy,.35),(.10,.10,.70),wood,False,True)
    box('stool seat',(tx+.95,ty,.45),(.40,.40,.10),wood,True,True)
    for dx in (-.13,.13):
        for dy in (-.13,.13):box('stool leg',(tx+.95+dx,ty+dy,.20),(.07,.07,.40),wood,False,True)
    wxash=w/2-.80;wyash=-.05
    box('wash stand',(wxash,wyash,.42),(.75,.65,.84),wood,True,True)
    # Open wash bowl assembled from bottom and four rims, not a filled cube.
    box('wash basin bottom',(wxash,wyash,.88),(.57,.46,.04),clay,False,True)
    for dx in (-.27,.27):box('wash basin rim',(wxash+dx,wyash,.96),(.04,.46,.16),clay,False,True)
    for dy in (-.21,.21):box('wash basin rim',(wxash,wyash+dy,.96),(.57,.04,.16),clay,False,True)
    dy=-d/2+.80;dx=w/2-.80
    for x in (dx-.45,dx+.45):box('drying rack post',(x,dy,.92),(.09,.09,1.84),wood,False,True)
    box('drying rail',(dx,dy,1.85),(1.04,.10,.10),wood,False,True)
    box('drying cloth',(dx,dy,1.46),(.55,.04,.75),linen,False,True)
    # A fixed support at the actual lamp position meets the runtime cord.
    box('lamp support',(0,0,h-.10),(.22,.22,.06),wood)
    hinge=bpy.data.objects.new('S_entry_hinge',None);C.ASSET.objects.link(hinge)
    hinge.location=(-.60,-yf,0);hinge['open_angle_degrees']=-100.0
    parts=[]
    for k in range(5):parts.append(box('Door plank',(-.48+k*.24,-yf,1.14),(.234,.08,2.28),wood))
    for z in (.45,1.72):parts.append(box('Door strap',(0,-yf-.05,z),(1.18,.018,.06),iron))
    visual=[o for o in C.ASSET.objects if o.type=='MESH']
    # Continuous world-space UV on zero-bevel limewash, including split wall piers.
    for o in visual:
        scale=float(o.data.materials[0].get('uv_metres',0))
        if not scale:continue
        bm=bmesh.new();bm.from_mesh(o.data);uv=bm.loops.layers.uv.verify()
        for face in bm.faces:
            normal=o.matrix_world.to_3x3()@face.normal;axis=max(range(3),key=lambda i:abs(normal[i]))
            for loop in face.loops:
                p=o.matrix_world@loop.vert.co
                u,v=(p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y)
                loop[uv].uv=(u/scale,v/scale)
        bm.to_mesh(o.data);bm.free()
    C._join_by_material([o for o in visual if o not in parts and o not in furniture]);C._join_by_material(furniture)
    for o in parts:
        matrix=o.matrix_world.copy();o.parent=hinge;o.matrix_world=matrix
    bpy.context.view_layer.update()
    visual=[o for o in C.ASSET.objects if o.type=='MESH']
    tri=0;pts=[]
    for o in visual:
        o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles)
        pts += [o.matrix_world@v.co for v in o.data.vertices]
    mn=[min(p[i] for p in pts) for i in range(3)];mx=[max(p[i] for p in pts) for i in range(3)]
    bounds=[[mn[0],mn[2],-mx[1]],[mx[0],mx[2],-mn[1]]]
    for n,p,s in collision:
        o=box(n+'-colonly',p,s,stone);o.hide_render=True
    for k,(vs,fs) in enumerate(roof_collision):
        o=C.mesh('roof panel '+str(k)+'-colonly',vs,fs,slate);o.hide_render=True
    anchor=bpy.data.objects.new('EntryAnchor',None);C.ASSET.objects.link(anchor);anchor.location=(0,-yf,0)
    anchor['wall_width']=w;anchor['wall_depth']=d;anchor['ceiling_height']=h;anchor['poor_timber_cottage']=poor
    for o in C.ASSET.objects:o.select_set(True)
    bpy.context.view_layer.objects.active=visual[0]
    asset=OUT/(slug+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(asset),use_selection=True,export_format='GLB',export_apply=True,export_yup=True,export_extras=True,export_cameras=False,export_lights=False)
    raw=asset.read_bytes();sz=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+sz])
    tints={'S cool stone':(.61,.66,.68),'S grey limewash':(.78,.80,.76),'S dark timber':(.30,.24,.18)}
    for m in doc['materials']:
        if m['name'] in tints:m['pbrMetallicRoughness']['baseColorFactor']=[*tints[m['name']],1]
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);tail=raw[20+sz:]
    asset.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
    stats={'slug':slug,'wall_footprint':[w,d],'entry':[0,0,yf],'ceiling':h,'ridge':ridge,'whole_bounds_godot':bounds,'triangles':tri,'visual_meshes':len(visual),'material_count':len(doc['materials']),'collision_boxes':len(collision),'roof_patches':len(roof_collision),'beds':beds,'bytes':asset.stat().st_size,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest(),'chimney_mouth_y':chimney_top,'stove':[cx,cy]}
    (QA/(slug+'.json')).write_text(json.dumps(stats,indent=2),encoding='utf-8')
    bpy.ops.wm.save_as_mainfile(filepath=str(QA/(slug+'.blend')))
    print('FAMILY_BUILT',json.dumps(stats),flush=True)

for variant in FAMILY:build(*variant)
