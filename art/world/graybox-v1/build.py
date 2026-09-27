"""Bake terrain constraints from the proposed map. Geometry construction is in Godot/Qwen."""
from pathlib import Path
import hashlib,json,math,shutil
import numpy as np

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
# WORLD_OUT: write elsewhere first when Windows folder protection blocks Python in Documents; copy after.
OUT=Path(__import__('os').environ.get('WORLD_OUT',ROOT/'assets/world/graybox-v1'))
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
    # WORLD-TERRAIN-02: the plaza height comes later from the ground (a basin), not from the plan.
    cities.append({**city,'plaza':plaza})
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
# D-099: the sea along the south edge. Shaped before the roads: they follow the beach, and they
# only touch their own narrow band, so they cannot lift the seabed.
# The coast is a function z = c(x); d > 0 is the sea side. West and the fishing cove: a beach
# descends to the water; east of cliffs_from_x the rocky coast keeps its height to the edge.
SEA=D.get('sea')
if SEA:
    coast_x=np.array([p[0] for p in SEA['coast']],float);coast_z=np.array([p[1] for p in SEA['coast']],float)
    d_sea=z-np.interp(x,coast_x,coast_z);level=float(SEA['level'])
    cove_lo,cove_hi=SEA['cove']
    cove=smooth((x-(cove_lo-40))/40)*(1-smooth((x-cove_hi)/40))
    cliff=smooth((x-SEA['cliffs_from_x'])/80)*(1-cove)
    inland=np.maximum(-d_sea,0)
    beach_top=level+1.2+inland*.12
    land_w=(1-cliff)*(1-smooth(inland/SEA['beach_width_m']))*(d_sea<=0)
    heights=np.where(d_sea<=0,heights*(1-land_w)+np.minimum(heights,beach_top)*land_w,heights)
    seaward=np.maximum(d_sea,0)
    seabed=level-1.5-12*smooth(seaward/150)
    # Beaches continue from their water line (level + 1.2) down to the seabed; cliffs drop within 8 m.
    beach_floor=level+1.2+(seabed-level-1.2)*smooth(seaward/20)
    cliff_floor=heights+(seabed-heights)*smooth(seaward/8)
    sea_floor=beach_floor*(1-cliff)+cliff_floor*cliff
    heights=np.where(d_sea>0,np.minimum(heights,sea_floor),heights)
# WORLD-TERRAIN-02 (owner, 27 Sep): no embankments, no trenches, no raised city platforms.
# Cities sit in a gentle basin below the surrounding ground; places sit on their own ground;
# roads take their height from the ground under them, smoothed and grade-limited, and the ground
# only meets them within their own width, with slopes no steeper than 1:3 beyond.
def ease(t):
    t=np.clip(t,0,1);return .5-.5*np.cos(np.pi*t)
def ground_mean(px,pz,radius):
    near=np.hypot(x-px,z-pz)<=radius
    return float(heights[near].mean())
CITY_FLOOR=45.0;CITY_EDGE=150.0;CITY_SINK=2.0
for c in cities:
    px,pz,_=c['plaza'];level_=ground_mean(px,pz,70.0)-CITY_SINK
    # Never below a nearby river: the city stands on its bank, not under its water.
    iz,ix=int(round(pz/STEP)),int(round(px/STEP))
    if water_distance[iz,ix]<CITY_FLOOR+60:level_=max(level_,float(water_height[iz,ix])+1.5)
    c['plaza']=[px,pz,level_]
    dist=np.hypot(x-px,z-pz);w=1-ease((dist-CITY_FLOOR)/CITY_EDGE)
    heights=heights*(1-w)+level_*w
# The start village is pressed in by the game at its own level (world.gd BASE_HEIGHT = 46 m);
# a lake shore sits on its lake's water. Other places sit on their own ground.
START_VILLAGE_LEVEL=46.0
lake_levels={l['site_id']:float(l['center'][2]) for l in D['lakes'] if l.get('site_id')}
for s in sites:
    px,pz,_=s['point'];level_=ground_mean(px,pz,20.0)
    if s['id']=='start_hamlet':level_=START_VILLAGE_LEVEL
    # The game stands the forest inn at the end of the trail from the village (world.gd _inn_frame),
    # i.e. at the start_trail junction; its pad follows that level instead of the hollow beside it.
    if s['id']=='forest_inn':level_=ground_mean(420.0,1210.0,15.0)
    if s['id'] in lake_levels:
        s['point']=[px,pz,lake_levels[s['id']]+3.0]
        continue
    s['point']=[px,pz,level_]
    dist=np.hypot(x-px,z-pz);w=1-ease((dist-18)/40)
    heights=heights*(1-w)+level_*w
# The river banks come back to their water after the basins (a basin must not undercut a river).
bank_weight=valley_weight*((d_sea<-30) if SEA else 1.0)
heights=heights*(1-bank_weight)+np.maximum(heights,water_height+2)*bank_weight
for c in cities:
    # The approach connector starts on the plaza.
    for r in roads:
        if r.get('connector') and r['id']=='approach_'+c['id']:
            r['geometry_points'][0][2]=c['plaza'][2]

def sample_grid(px,pz):
    gx=np.clip(px/STEP,0,WIDTH-1.000001);gz=np.clip(pz/STEP,0,WIDTH-1.000001)
    ix,iz=int(gx),int(gz);u,v=gx-ix,gz-iz
    a,b,c,d=heights[iz,ix],heights[iz,ix+1],heights[iz+1,ix],heights[iz+1,ix+1]
    return float(a*(1-u)*(1-v)+b*u*(1-v)+c*(1-u)*v+d*u*v)
GRADE={6:.18,3:.22}
city_xy=np.array([c['plaza'][:2] for c in cities],float)
def gauss_smooth(h,step,metres):
    sigma=metres/max(float(step.mean()),.5);k=int(3*sigma)+1
    kern=np.exp(-.5*(np.arange(-k,k+1)/sigma)**2);kern/=kern.sum()
    padded=np.pad(h,k,mode='reflect') if len(h)>k+1 else np.pad(h,k,mode='edge')
    return np.convolve(padded,kern,mode='valid')
profiles={}
for r in roads:
    pts=np.array([[p[0],p[1]] for p in r['geometry_points']],float)
    step=np.hypot(*np.diff(pts,axis=0).T);step=np.maximum(step,1e-6)
    ground=gauss_smooth(np.array([sample_grid(px,pz) for px,pz in pts]),step,12.0)
    planned=np.array([p[2] for p in r['geometry_points']],float)
    # Where the plan agrees with the ground (plains, forest) the road follows the ground; where a
    # mountain switchback was designed far from this graybox ground, the planned height stays.
    # Near cities the ground always wins, so roads come down into the city basins.
    to_city=np.min(np.hypot(pts[:,None,0]-city_xy[None,:,0],pts[:,None,1]-city_xy[None,:,1]),axis=1)
    # The plan is kept only where the ground along the road is steeper than a road can climb
    # (mountain switchbacks); on gentle ground the road always lies on it, whatever the plan said.
    grade0=GRADE.get(int(r.get('width_m',6)),.16)
    slope=np.abs(np.gradient(gauss_smooth(ground,step,20.0),np.concatenate([[0],np.cumsum(step)])))
    steep=smooth((gauss_smooth(slope,step,20.0)-grade0)/grade0)
    keep=steep*smooth((np.abs(planned-ground)-4.0)/10.0)*smooth((to_city-150.0)/250.0)
    mixed=ground*(1-keep)+planned*keep
    # A median first removes single-sample spikes of the plan at road corners.
    padded=np.pad(mixed,3,mode='edge')
    mixed=np.median(np.lib.stride_tricks.sliding_window_view(padded,7),axis=1)
    h=gauss_smooth(mixed,step,8.0)
    profiles[r['id']]=[pts,h,step,GRADE.get(int(r.get('width_m',6)),.16),{}]
# Road ends, the plan's junctions and every place two roads meet or cross share one height.
nodes={}
for rid,(pts,h,step,grade,pins) in profiles.items():
    for end in (0,len(pts)-1):nodes.setdefault((round(float(pts[end][0])),round(float(pts[end][1]))),[])
for j in D['junctions']:nodes.setdefault((round(j['point'][0]),round(j['point'][1])),[])
ids=list(profiles)
# Where two roads run together or cross, the lesser one (narrower, then later in the plan) takes
# the main one's final height on every shared sample; no averaging, so no saw-tooth along a shared stretch.
width_of={r['id']:float(r.get('width_m',6)) for r in roads}
# Near a node its level plate decides, so a shared stretch never pins a sample next to a plate.
node_xy=np.array(list(nodes)+[tuple(c['plaza'][:2]) for c in cities]+[tuple(s['point'][:2]) for s in sites],float)
city_plaza_xy=np.array([c['plaza'][:2] for c in cities],float)
def near_node(p):
    return (float(np.min(np.hypot(node_xy[:,0]-p[0],node_xy[:,1]-p[1])))<12.0
            or float(np.min(np.hypot(city_plaza_xy[:,0]-p[0],city_plaza_xy[:,1]-p[1])))<30.0)
shared={}
for a_i,ra in enumerate(ids):
    pa,ha=profiles[ra][0],profiles[ra][1]
    for rb in ids[a_i+1:]:
        pb,hb=profiles[rb][0],profiles[rb][1]
        d=np.hypot(pa[:,None,0]-pb[None,:,0],pa[:,None,1]-pb[None,:,1])
        close=np.argwhere(d<4.0)
        if not len(close):continue
        main,minor=(ra,rb) if width_of[ra]>=width_of[rb] else (rb,ra)
        dm=d if main==ra else d.T
        for iu in {int(ib if main==ra else ia) for ia,ib in close}:
            if near_node(profiles[minor][0][iu]):continue
            # The nearest main sample; its height is copied once the main road is final (below).
            shared.setdefault(minor,{})[iu]=(main,int(dm[:,iu].argmin()))
for key in nodes:
    for rid,(pts,h,step,grade,pins) in profiles.items():
        d=np.hypot(pts[:,0]-key[0],pts[:,1]-key[1]);i=int(d.argmin())
        if d[i]<3.0:nodes[key].append((rid,i))
for key,hits in nodes.items():
    if not hits:continue
    # A branch joins a through road at the through road's level; only road ends meeting each other
    # settle on their average.
    through=[(rid,i) for rid,i in hits if 0<i<len(profiles[rid][0])-1]
    target=float(np.mean([np.median(profiles[rid][1][max(0,i-6):i+7]) for rid,i in (through or hits)]))
    # A place or a city plaza wins: the road arrives on its ground.
    for c in cities:
        if math.dist(key,c['plaza'][:2])<3.0:target=c['plaza'][2]
    for s in sites:
        if math.dist(key,s['point'][:2])<3.0:target=s['point'][2]
    # A level plate: every road around the node at the same height, so decks meet flush. 12 m at a
    # junction (the same reach as the shared-stretch rule above); across a city plaza (~24 m) 30 m.
    plate=30.0 if any(math.dist(key,c['plaza'][:2])<3.0 for c in cities) else 12.0
    for rid,i in hits:
        pts_,h_,step_,grade_,pins_=profiles[rid]
        along=np.concatenate([[0],np.cumsum(step_)])
        for k in np.where(np.abs(along-along[i])<=plate)[0]:pins_[int(k)]=target
# River crossings are bridges: the deck stays at least 0.6 m over the water there.
for rid,(pts,h,step,grade,pins) in profiles.items():
    iz=np.clip(np.round(pts[:,1]/STEP).astype(int),0,WIDTH-1);ix=np.clip(np.round(pts[:,0]/STEP).astype(int),0,WIDTH-1)
    wet=water_distance[iz,ix]<water_width[iz,ix]*.5+4.0
    for k in np.where(wet)[0]:
        k=int(k);pins[k]=max(pins.get(k,h[k]),float(water_height[iz[k],ix[k]])+.6)
# Pins are hard; the grade limit carries each correction along the road (no jumps). Between two
# pins that cannot be joined at the usual grade, only that stretch gets exactly the grade it needs.
def settle(pts,h,step,grade,pins):
    along=np.concatenate([[0],np.cumsum(step)])
    limit=np.full(len(step),grade)
    order=sorted(pins)
    for a_,b_ in zip(order,order[1:]):
        span=along[b_]-along[a_]
        if span>0:
            need=abs(pins[b_]-pins[a_])/span*1.02
            if need>grade:limit[a_:b_]=np.maximum(limit[a_:b_],need)
    for i,v in pins.items():h[i]=v
    for _ in range(8):
        # Pinned points are never moved by the passes; everything else follows them.
        for i in range(1,len(h)):
            if i not in pins:h[i]=np.clip(h[i],h[i-1]-limit[i-1]*step[i-1],h[i-1]+limit[i-1]*step[i-1])
        for i in range(len(h)-2,-1,-1):
            if i not in pins:h[i]=np.clip(h[i],h[i+1]-limit[i]*step[i],h[i+1]+limit[i]*step[i])
for rid,prof in profiles.items():settle(*prof)
# A shared stretch takes the main road's final deck, so both decks coincide; the lesser road is then
# settled again around those pins. Wider (earlier) roads go first, so every main is already final.
rank={rid:(-width_of[rid],n) for n,rid in enumerate(ids)}
for minor in sorted(shared,key=rank.get):
    for iu,(main,im) in shared[minor].items():profiles[minor][4][iu]=float(profiles[main][1][im])
    settle(*profiles[minor])
for r in roads:
    pts,h,step,grade,pins=profiles[r['id']]
    r['geometry_points']=[[float(px),float(pz),float(ph)] for (px,pz),ph in zip(pts,h)]
# The ground meets each road within its width; beyond, a slope of at most 1:3 (narrower where
# the ground is already close to the road), so nothing looks built up or dug out.
dd,dh=nearest([r['geometry_points'] for r in roads],130)
_,dw=nearest([[[p[0],p[1],float(r.get('width_m',6))] for p in r['geometry_points']] for r in roads],130)
core=dw*.5+1.0
fall=np.clip(3.0*np.abs(heights-dh),6.0,90.0)
w=np.where(dd<=core,1.0,1-ease((dd-core)/fall))
heights=heights*(1-w)+(dh-.05)*w
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
# WORLD-TERRAIN-02: soften what the shaping left (cut edges, crossings) everywhere except the road
# decks, then press the river channels and the decks back exactly.
def blur(a,sigma):
    k=int(3*sigma)+1;kern=np.exp(-.5*(np.arange(-k,k+1)/sigma)**2);kern/=kern.sum()
    p=np.pad(a,k,mode='edge')
    p=np.apply_along_axis(lambda v:np.convolve(v,kern,mode='valid'),0,p)
    return np.apply_along_axis(lambda v:np.convolve(v,kern,mode='valid'),1,p)
deck_w=np.where(dd<=core,1.0,1-ease((dd-core)/6.0))
heights=heights*deck_w+blur(heights,1.3)*(1-deck_w)
heights=heights*(1-river_weight)+np.minimum(heights,water_height-river_depth)*river_weight
# No water hanging in the air: right under a river the ground reaches at least its bed.
under=water_distance<=water_width*.5+1.0
heights=np.where(under,np.maximum(heights,water_height-river_depth),heights)

# Slope bands from neighboring switchbacks can overlap on a 5 m grid.
# Bound every covered cell by ALL nearby decks, not just the nearest path.
for r in roads:
    for a,b in zip(r['geometry_points'],r['geometry_points'][1:]):
        sl=(slice(max(0,int((min(a[1],b[1])-10)/STEP)),min(WIDTH,int((max(a[1],b[1])+10)/STEP)+2)),slice(max(0,int((min(a[0],b[0])-10)/STEP)),min(WIDTH,int((max(a[0],b[0])+10)/STEP)+2)))
        xx,zz=x[sl],z[sl];dx,dz=b[0]-a[0],b[1]-a[1]
        t=np.clip(((xx-a[0])*dx+(zz-a[1])*dz)/(dx*dx+dz*dz),0,1)
        dist=np.hypot(xx-(a[0]+t*dx),zz-(a[1]+t*dz))
        # WORLD-TERRAIN-02: only under the road itself, and just below its deck (no trench).
        # Just below the deck at its edge, then free to rise 1:1, so a 5 m terrain triangle cannot
        # bulge over a narrow deck and the bank has no step.
        edge=float(r.get('width_m',6))*.5+.5
        # A steep deck needs more room: grid triangles span half a cell of its climb.
        climb=abs(b[2]-a[2])/max(math.dist(a[:2],b[:2]),1e-6)*STEP*.6
        # The extra room grows towards the deck's edges (where cells bulge); under its axis the
        # ground stays just below the deck, so the deck never floats.
        ceiling=a[2]+t*(b[2]-a[2])-.15-climb*np.minimum(dist/edge,1.0)+np.maximum(dist-edge,0)
        heights[sl]=np.where(dist<edge+STEP*2,np.minimum(heights[sl],ceiling),heights[sl])

# ROADS-UNIFY-01: roads are painted on the ground, so under a road the ground IS the road: every grid
# point within its edge (+1 m) takes the height of the nearest deck point, also between switchback
# legs (a steep bank there instead of a deck in the air). River channels keep their bed; a bridge
# deck carries the road over them.
best=np.full(heights.shape,np.inf);target=heights.copy();lowest=np.full(heights.shape,np.inf)
for r in roads:
    reach=float(r.get('width_m',6))*.5+1.5
    own=np.full(heights.shape,np.inf);own_deck=np.zeros(heights.shape)
    for a,b in zip(r['geometry_points'],r['geometry_points'][1:]):
        sl=(slice(max(0,int((min(a[1],b[1])-reach)/STEP)),min(WIDTH,int((max(a[1],b[1])+reach)/STEP)+2)),slice(max(0,int((min(a[0],b[0])-reach)/STEP)),min(WIDTH,int((max(a[0],b[0])+reach)/STEP)+2)))
        xx,zz=x[sl],z[sl];dx,dz=b[0]-a[0],b[1]-a[1]
        t=np.clip(((xx-a[0])*dx+(zz-a[1])*dz)/max(dx*dx+dz*dz,1e-9),0,1)
        dist=np.hypot(xx-(a[0]+t*dx),zz-(a[1]+t*dz))
        closer=(dist<=reach)&(dist<own[sl])
        own[sl]=np.where(closer,dist,own[sl])
        # On a steep stretch a 5 m triangle cuts across the profile's bends; the ground stays a little
        # under the plan there (0.16 m at 20 %, 0.9 m at 57 %) instead of rising over it.
        sink=.02+min(max(abs(b[2]-a[2])/max(math.dist(a[:2],b[:2]),1e-6)-.12,0)*STEP*.4,1.0)
        own_deck[sl]=np.where(closer,a[2]+t*(b[2]-a[2])-sink,own_deck[sl])
    hit=np.isfinite(own)
    nearer=hit&(own<best)
    best=np.where(nearer,own,best);target=np.where(nearer,own_deck,target)
    lowest=np.where(hit,np.minimum(lowest,own_deck),lowest)
# Where roads meet or share a stretch (their decks within 1 m) the ground takes the lower road, so it
# never rises through a deck; switchback legs further apart in height keep the nearest leg.
target=np.where(target-lowest<1.0,lowest,target)
channel=water_distance<=water_width*.5+3.0
heights=np.where(np.isfinite(best)&~channel,target,heights)

# Clay color masses only. Roads come from the road mask, water from its own strips.
colors=np.zeros((WIDTH,WIDTH,4));colors[:,:,:]=[.43,.52,.43,1]
desert=(x>1210)&(z<1570);colors[desert]=[.66,.57,.43,1]
low=z>1390+110*np.sin(x/200);colors[low]=[.37,.52,.49,1]
rock=smooth((heights-165)/155)[:,:,None]
colors[:,:,:3]=colors[:,:,:3]*(1-rock)+np.array([.55,.56,.54])*rock
snow=smooth((heights-280)/110)[:,:,None]
colors[:,:,:3]=colors[:,:,:3]*(1-snow)+np.array([.84,.86,.83])*snow
# ROADS-UNIFY-01: no road colour here; roads are painted from the 1 m mask (roads.png) at run time.
if SEA:
    # Sand along the water line, grey-green seabed under it, bare rock on the cliff faces.
    sand=((1-smooth((heights-level-2.2)/1.5))*(1-smooth(inland/70)))[:,:,None]
    colors[:,:,:3]=colors[:,:,:3]*(1-sand)+np.array([.74,.68,.52])*sand
    bed=smooth(d_sea/10)[:,:,None]*(d_sea>0)[:,:,None]
    colors[:,:,:3]=colors[:,:,:3]*(1-bed)+np.array([.46,.48,.42])*bed
    face=(cliff*(1-smooth(inland/25)))[:,:,None]
    colors[:,:,:3]=colors[:,:,:3]*(1-face)+np.array([.50,.49,.46])*face
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
(OUT/'heights.bin').write_bytes(heights.astype('<f4').tobytes())
(OUT/'colors.bin').write_bytes(colors.astype('<f4').tobytes())
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
        'sea':({**SEA,'world_coast':[[p[0]-HALF,float(SEA['level']),p[1]-HALF] for p in SEA['coast']]} if SEA else None),
        'gates':D['gates'],'peaks':D['peaks'],'source_ridge':ridge,
        'limits':'Graybox hypothesis. No vegetation, swimming, NPC, campaign or streaming.'}
(OUT/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf8',newline='\n')
# ROADS-UNIFY-01: roads are painted into the ground, as in the village: a 1 m mask over the map
# (alpha as the village's road_info edge) that the ground shader blends to the path material.
# Near the village the game redraws it from the trail heads it builds at run time.
MASK=2000
mask=np.zeros((MASK,MASK),np.float32)
for r in layout['roads']:
    w=float(r.get('width_m',6));inner,outer=w*.42,w*.65+.5
    pts=np.array([[p[0]+HALF,p[2]+HALF] for p in r['world_points']],float)
    for a,b in zip(pts,pts[1:]):
        x0,z0=np.floor(np.minimum(a,b)-outer).astype(int);x1,z1=np.ceil(np.maximum(a,b)+outer).astype(int)
        x0,z0=max(x0,0),max(z0,0);x1,z1=min(x1,MASK-1),min(z1,MASK-1)
        if x1<x0 or z1<z0:continue
        pz,px=np.mgrid[z0:z1+1,x0:x1+1].astype(float)+.5
        ab=b-a;t=np.clip(((px-a[0])*ab[0]+(pz-a[1])*ab[1])/max(ab@ab,1e-9),0,1)
        d=np.hypot(px-a[0]-t*ab[0],pz-a[1]-t*ab[1])
        v=1-smooth((d-inner)/(outer-inner))
        mask[z0:z1+1,x0:x1+1]=np.maximum(mask[z0:z1+1,x0:x1+1],v)
from PIL import Image
Image.fromarray(np.round(mask*255).astype(np.uint8),'L').save(OUT/'roads.png',optimize=True)
character=ROOT/'assets/characters/world-graybox-v1';character.mkdir(parents=True,exist_ok=True)
# First build only: the frames in assets/ were edited later (D-094 guard poses); never overwrite them.
if not (character/'traveler_frames.tres').exists():
    shutil.copyfile(ROOT/'art/characters/walk-consistency-v1/walk-atlas.png',character/'walk.png')
    frames=(ROOT/'art/characters/accepted-traveler-v1/traveler_frames.tres').read_text(encoding='utf8').replace('res://art/characters/walk-consistency-v1/walk-atlas.png','res://assets/characters/world-graybox-v1/walk.png')
    (character/'traveler_frames.tres').write_text(frames,encoding='utf8',newline='\n')
manifest={'grid':WIDTH,'spacing_m':STEP,'triangles':(WIDTH-1)**2*2,'height_range_m':[float(heights.min()),float(heights.max())],
          'source':str(SOURCE.relative_to(ROOT)).replace('\\','/'),'files':{('assets/world/graybox-v1/'+p.name if p.parent==OUT else str(p.relative_to(ROOT)).replace('\\','/')):hashlib.sha256(p.read_bytes()).hexdigest() for p in [*OUT.glob('*'),character/'walk.png',character/'traveler_frames.tres'] if p.suffix in ['.bin','.json','.png','.tres'] and p.name!='manifest.json'}}
(OUT/'manifest.json' if OUT!=ROOT/'assets/world/graybox-v1' else HERE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8',newline='\n')
print(f'WORLD_HEIGHTS_OK grid=401 triangles=320000 routes={len(roads)} sites={len(sites)}')
