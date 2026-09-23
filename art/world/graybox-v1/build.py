"""Bake terrain constraints from the proposed map. Geometry construction is in Godot/Qwen."""
from pathlib import Path
import hashlib,json,math,shutil
import numpy as np

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
OUT=ROOT/'assets/world/graybox-v1'
SOURCE=ROOT/'docs/design/world-exploration-v1/world-exploration.json'
D=json.loads(SOURCE.read_text(encoding='utf8'))
STEP=5.0; WIDTH=401; HALF=1000.0
z,x=np.mgrid[0:WIDTH,0:WIDTH].astype(float)*STEP

def smooth(t):
    t=np.clip(t,0,1);return t*t*(3-2*t)

def nearest(paths,radius=None):
    best=np.full(x.shape,np.inf);height=np.zeros_like(x)
    for path in paths:
        for a,b in zip(path,path[1:]):
            sl=(slice(None),slice(None)) if radius is None else (slice(max(0,int((min(a[1],b[1])-radius)/STEP)),min(WIDTH,int((max(a[1],b[1])+radius)/STEP)+2)),slice(max(0,int((min(a[0],b[0])-radius)/STEP)),min(WIDTH,int((max(a[0],b[0])+radius)/STEP)+2)))
            xx,zz=x[sl],z[sl]
            dx,dz=b[0]-a[0],b[1]-a[1]
            t=np.clip(((xx-a[0])*dx+(zz-a[1])*dz)/(dx*dx+dz*dz),0,1)
            dist=np.hypot(xx-(a[0]+t*dx),zz-(a[1]+t*dz))
            selected=dist<best[sl]
            height[sl]=np.where(selected,a[2]+t*(b[2]-a[2]),height[sl])
            best[sl]=np.minimum(best[sl],dist)
    return best,height

# Broad shapes are a design proposal, not a DEM inferred from the map's shaded bands.
base=12+55*np.power(1-z/2000,1.3)+24*x/2000
heights=base.copy()
ridge=[[100,260,300],[390,230,430],[480,350,340],[630,470,205],
       [760,330,400],[900,190,510],[1130,285,380],[1290,430,460],
       [1180,650,260],[1230,840,340],[1180,1020,240]]
rd,rh=nearest([ridge])
heights=np.maximum(heights,base+(rh-base)*np.exp(-np.square(rd/230)))
for px,pz,ph in D['peaks']:
    heights=np.maximum(heights,base+(ph-base)*np.exp(-np.square((x-px)/205)-np.square((z-pz)/190)))
for extra in D.get('extra_ridges',[]):
    distance,top=nearest([extra])
    heights=np.maximum(heights,base+(top-base)*np.exp(-np.square(distance/135)))
heights+=7*np.sin(x/95)*np.cos(z/113)+3*np.sin((x+z)/54)

# The city coordinates on the plan are road anchors. Small plazas sit on dry banks.
offsets={'forest':[-35,35],'snow':[0,0],'desert':[45,-35],'lowland':[45,-45]}
roads=[dict(r) for r in D['roads']]
cities=[]
for city in D['cities']:
    px,pz,ph=city['point'];ox,oz=offsets[city['id']];plaza=[px+ox,pz+oz,ph]
    cities.append({**city,'plaza':plaza})
    dist=np.hypot(x-plaza[0],z-plaza[1]);w=1-smooth((dist-48)/38)
    heights=heights*(1-w)+ph*w
    if ox or oz:roads.append({'id':'approach_'+city['id'],'points':[plaza,city['point']],'connector':True})

sites=D['sites']
plazas=[c['plaza'] for c in cities]+[s['point'] for s in sites]
anchors={tuple(r['points'][end]) for r in roads for end in [0,-1]}

def round_path(path):
    # Circular fillets have a known inner radius; quadratic corners can fold a ribbon.
    result=[path[0]]
    for a,b,c in zip(path,path[1:],path[2:]):
        # A branch must meet the main road exactly, rather than a trimmed corner.
        if tuple(b) in anchors:result.append(b);continue
        la=math.dist(a[:2],b[:2]);lc=math.dist(b[:2],c[:2])
        incoming=(np.array(b[:2])-a[:2])/la;outgoing=(np.array(c[:2])-b[:2])/lc
        angle=math.atan2(incoming[0]*outgoing[1]-incoming[1]*outgoing[0],float(incoming@outgoing))
        if abs(angle)<.01:result.append(b);continue
        trim=min(14*math.tan(abs(angle)/2),la*.45,lc*.45)
        radius=trim/math.tan(abs(angle)/2)
        entry=np.array(b)+(np.array(a)-b)*trim/la
        leave=np.array(b)+(np.array(c)-b)*trim/lc
        center=entry[:2]+np.array([-incoming[1],incoming[0]])*math.copysign(radius,angle)
        start=math.atan2(entry[1]-center[1],entry[0]-center[0])
        for t in np.linspace(0,1,max(3,math.ceil(radius*abs(angle)/2)+1)):
            theta=start+t*angle
            result.append([center[0]+radius*math.cos(theta),center[1]+radius*math.sin(theta),entry[2]*(1-t)+leave[2]*t])
    result.append(path[-1]);return result

flat_nodes=[list(p) for p in anchors]+[j['point'] for j in D['junctions']]+plazas
for r in roads:
    curve=round_path(r['points']);sampled=[]
    for a,b in zip(curve,curve[1:]):
        n=max(1,math.ceil(math.dist(a[:2],b[:2])/2))
        for i in range(n):
            p=[a[k]+(b[k]-a[k])*i/n for k in range(3)]
            for nx,nz,nh in flat_nodes:
                influence=1-float(smooth((math.hypot(p[0]-nx,p[1]-nz)-18)/20))
                p[2]=p[2]*(1-influence)+nh*influence
            sampled.append(p)
    sampled.append(curve[-1]);r['geometry_points']=sampled

# Shape the river valleys at their authored elevations, including low terrain.
# Merely carving with min() leaves the water suspended above an unrelated base.
water_distance,water_height=nearest([r['points'] for r in D['rivers']])
_,water_width=nearest([[[p[0],p[1],w] for p,w in zip(r['points'],r['widths_m'])] for r in D['rivers']])
valley_weight=1-smooth((water_distance-16)/95)
heights=heights*(1-valley_weight)+(water_height+2)*valley_weight
dd,dh=nearest([r['geometry_points'] for r in roads],130)
w=1-smooth((dd-12)/80)
heights=heights*(1-w)+(dh-.5)*w
# Small dry city squares join the road through gentle shoulders.
for px,pz,ph in plazas:
    dist=np.hypot(x-px,z-pz);w=1-smooth((dist-24)/14)
    heights=heights*(1-w)+ph*w
# A level lake basin with a continuous shoreline; its outlet joins the river profile.
for lake in D['lakes']:
    px,pz,level=lake['center'];rx,rz=lake['radii_m']
    q=np.hypot((x-px)/rx,(z-pz)/rz)
    bed=level-7*(1-np.minimum(q,1)**2)+10*smooth((q-1)/.35)
    influence=1-smooth((q-1.08)/.45)
    heights=heights*(1-influence)+bed*influence
# Actual channel is below water; road strips cross it as decks.
river_weight=1-smooth((water_distance-(water_width*.5+3))/14)
river_depth=1+1.8*np.clip((water_width-2)/10,0,1)
heights=heights*(1-river_weight)+np.minimum(heights,water_height-river_depth)*river_weight

# Slope bands from neighboring switchbacks can overlap on a 5 m grid.
# Bound every covered cell by ALL nearby decks, not just the nearest path.
for r in roads:
    for a,b in zip(r['geometry_points'],r['geometry_points'][1:]):
        sl=(slice(max(0,int((min(a[1],b[1])-10)/STEP)),min(WIDTH,int((max(a[1],b[1])+10)/STEP)+2)),slice(max(0,int((min(a[0],b[0])-10)/STEP)),min(WIDTH,int((max(a[0],b[0])+10)/STEP)+2)))
        xx,zz=x[sl],z[sl];dx,dz=b[0]-a[0],b[1]-a[1]
        t=np.clip(((xx-a[0])*dx+(zz-a[1])*dz)/(dx*dx+dz*dz),0,1)
        dist=np.hypot(xx-(a[0]+t*dx),zz-(a[1]+t*dz))
        ceiling=a[2]+t*(b[2]-a[2])-.75
        heights[sl]=np.where(dist<10,np.minimum(heights[sl],ceiling),heights[sl])

# Clay color masses only. Roads and water get their own continuous plain-color strips.
colors=np.zeros((WIDTH,WIDTH,4));colors[:,:,:]=[.43,.52,.43,1]
desert=(x>1210)&(z<1570);colors[desert]=[.66,.57,.43,1]
low=z>1390+110*np.sin(x/200);colors[low]=[.37,.52,.49,1]
rock=smooth((heights-165)/155)[:,:,None]
colors[:,:,:3]=colors[:,:,:3]*(1-rock)+np.array([.55,.56,.54])*rock
snow=smooth((heights-280)/110)[:,:,None]
colors[:,:,:3]=colors[:,:,:3]*(1-snow)+np.array([.84,.86,.83])*snow
road_weight=(1-smooth((dd-5)/6))[:,:,None]
road_weight*= (water_distance>water_width*.5+5)[:,:,None]
colors[:,:,:3]=colors[:,:,:3]*(1-road_weight)+np.array([.63,.58,.48])*road_weight
colors[:,:,:3]=np.where(colors[:,:,:3]<=.04045,colors[:,:,:3]/12.92,((colors[:,:,:3]+.055)/1.055)**2.4)

def sample(px,pz):
    gx=np.clip(px/STEP,0,WIDTH-1.000001);gz=np.clip(pz/STEP,0,WIDTH-1.000001)
    ix,iz=int(gx),int(gz);u,v=gx-ix,gz-iz
    a,b,c,d=heights[iz,ix],heights[iz,ix+1],heights[iz+1,ix],heights[iz+1,ix+1]
    # Same diagonal as clockwise Godot mesh triangles [a,b,c], [b,d,c].
    return float(a+(b-a)*u+(c-a)*v if u+v<=1 else d+(c-d)*(1-u)+(b-d)*(1-v))

def dense(path,road=False):
    result=[]
    for a,b in zip(path,path[1:]):
        n=math.ceil(math.dist(a[:2],b[:2])/2)
        for i in range(n):
            t=i/n;p=[a[k]+(b[k]-a[k])*t for k in range(3)]
            if road:p[2]+=.08
            result.append([p[0]-HALF,p[2],p[1]-HALF])
    p=path[-1];result.append([p[0]-HALF,p[2]+.08 if road else p[2],p[1]-HALF])
    return result

OUT.mkdir(parents=True,exist_ok=True)
heights.astype('<f4').tofile(OUT/'heights.bin')
colors.astype('<f4').tofile(OUT/'colors.bin')
def water_record(r):
    points=dense(r['points']);widths=[]
    for a,b,wa,wb in zip(r['points'],r['points'][1:],r['widths_m'],r['widths_m'][1:]):
        n=math.ceil(math.dist(a[:2],b[:2])/2)
        widths.extend(wa+(wb-wa)*i/n for i in range(n))
    widths.append(r['widths_m'][-1])
    assert len(widths)==len(points)
    return {**r,'world_points':points,'world_widths':widths}

layout={'version':'0.21.2-headwaters','width':WIDTH,'spacing':STEP,'extent_m':2000,
        'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'cities':[{**c,'spawn':[c['plaza'][0]-HALF,max(c['plaza'][2],sample(*c['plaza'][:2]))+.12,c['plaza'][1]-HALF]} for c in cities],
        'sites':[{**s,'spawn':[s['point'][0]-HALF,max(s['point'][2],sample(*s['point'][:2]))+.12,s['point'][1]-HALF]} for s in sites],
        'progression':D['progression'],
        'roads':[{**r,'world_points':dense(r['geometry_points'],True)} for r in roads],
        'rivers':[water_record(r) for r in D['rivers']],
        'lakes':D['lakes'],'springs':D['springs'],
        'gates':D['gates'],'peaks':D['peaks'],'source_ridge':ridge,
        'limits':'Graybox hypothesis. No vegetation, swimming, NPC, campaign or streaming.'}
(OUT/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf8',newline='\n')
character=ROOT/'assets/characters/world-graybox-v1';character.mkdir(parents=True,exist_ok=True)
shutil.copyfile(ROOT/'art/characters/walk-consistency-v1/walk-atlas.png',character/'walk.png')
frames=(ROOT/'art/characters/accepted-traveler-v1/traveler_frames.tres').read_text(encoding='utf8').replace('res://art/characters/walk-consistency-v1/walk-atlas.png','res://assets/characters/world-graybox-v1/walk.png')
(character/'traveler_frames.tres').write_text(frames,encoding='utf8',newline='\n')
manifest={'grid':WIDTH,'spacing_m':STEP,'triangles':(WIDTH-1)**2*2,'height_range_m':[float(heights.min()),float(heights.max())],
          'source':str(SOURCE.relative_to(ROOT)).replace('\\','/'),'files':{str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in [*OUT.glob('*'),character/'walk.png',character/'traveler_frames.tres'] if p.suffix in ['.bin','.json','.png','.tres']}}
(HERE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8',newline='\n')
print(f'WORLD_HEIGHTS_OK grid=401 triangles=320000 routes={len(roads)} sites={len(sites)}')
