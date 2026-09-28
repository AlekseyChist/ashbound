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
# RIVER-GRID-01 (owner 28 Sep: at the crossroads inn the water lies under the ground in pieces): a
# 2-3 m stream falls between the 5 m grid points, so the ground covers it in patches. Water and
# channel are at least 8 m wide: every grid row within 2.5 m of the axis then lies on the bed.
# The depth still follows the planned width: a stream stays wadeable (1-1.2 m, the hero stops at 1.2).
MIN_RIVER_WIDTH=8.0
for _rv in D['rivers']:
    _rv['depth_widths_m']=[float(w) for w in _rv['widths_m']]
    _rv['widths_m']=[max(float(w),MIN_RIVER_WIDTH) for w in _rv['widths_m']]
# RIVERS-SHALLOW-01 (owner 28 Sep: "make the rivers shallow so one can run across them"): knee-deep,
# 0.6 m for a stream to 0.8 m for the widest river (was 1.0-2.8 m).
def river_depth_for(w):
    return 0.6+0.2*np.clip((np.asarray(w,float)-2)/10,0,1)

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

# RIVER-NATURAL-01 (owner 28 Sep: "if I were the river I'd flow into that valley below ... it must look
# natural, not a wild fantasy"): the plan's water stood up to 70-100 m over the land around it, and the
# valley shaping below raised a wide embankment to carry it. The water now takes its height from this
# natural ground along its own course: the lowest ground across its bed (within 15 m), 1.5 m into it,
# never rising downstream, a drop spread upstream at most 45 % (cascades, no walls). A lake fills to its outlet;
# a tributary meets the river it flows into at that river's water. The courses themselves are the plan's.
def natural_floor(px,pz,reach=15.0):
    i0,i1=max(0,int((pz-reach)/STEP)),min(WIDTH,int((pz+reach)/STEP)+2)
    j0,j1=max(0,int((px-reach)/STEP)),min(WIDTH,int((px+reach)/STEP)+2)
    win=heights[i0:i1,j0:j1];near=np.hypot(x[i0:i1,j0:j1]-px,z[i0:i1,j0:j1]-pz)<=reach
    return float(win[near].min())
RIVER_INTO_GROUND=1.5;RAPIDS=0.45;RIVER_STEP=8.0
for lake in D['lakes']:
    ox,oz=lake['outlet'][:2]
    lake['center'][2]=round(min(float(lake['center'][2]),natural_floor(ox,oz)-1.0),2)
    lake['outlet'][2]=lake['center'][2]
lake_of={l['river_id']:l for l in D['lakes'] if l.get('river_id')}
settled_courses={}
def natural_course(rv):
    pts=rv['points'];cols=[rv['widths_m'],rv['depth_widths_m']];out=[];ws=[[],[]]
    for a,b,*w in zip(pts,pts[1:],*[c for c in cols],*[c[1:] for c in cols]):
        n=max(1,math.ceil(math.dist(a[:2],b[:2])/RIVER_STEP))
        for i in range(n):
            t=i/n;out.append([a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t])
            ws[0].append(w[0]+(w[2]-w[0])*t);ws[1].append(w[1]+(w[3]-w[1])*t)
    out.append(list(pts[-1]));ws[0].append(cols[0][-1]);ws[1].append(cols[1][-1])
    level=[min(p[2],natural_floor(p[0],p[1])-RIVER_INTO_GROUND) for p in out]
    if rv['id'] in lake_of:level[0]=float(lake_of[rv['id']]['center'][2])
    for i in range(1,len(level)):level[i]=min(level[i],level[i-1])
    # A tributary ends in its river's water (that river is settled first).
    end=out[-1]
    for other,(opts,olevel) in settled_courses.items():
        d=[math.dist(end[:2],q[:2]) for q in opts];k=int(np.argmin(d))
        if d[k]<20.0:level[-1]=min(level[-1],olevel[k])
    for i in range(len(level)-2,-1,-1):
        level[i]=min(level[i],level[i+1]+RAPIDS*math.dist(out[i][:2],out[i+1][:2]))
    for p,h in zip(out,level):p[2]=round(h,2)
    rv['points']=out;rv['widths_m']=ws[0];rv['depth_widths_m']=ws[1]
    settled_courses[rv['id']]=(out,level)
# Rivers others flow into come first (main before its tributaries).
for rv in sorted(D['rivers'],key=lambda r:0 if r['id']=='main' else 1):natural_course(rv)

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

# RIVERSIDE-ROADS-01 (owner 27 Sep: bridges along rivers, roads in the water): where a road runs along
# a river (not across it) inside its channel, the road moves onto the bank - clear of the water's
# edge by 4 m past its own half width. Real crossings (over 45 deg to the river) stay; the shift
# is smoothed along the road and fades out at road ends, junctions and plazas.
river_segs=[]
for rv in D['rivers']:
    pts=rv['points'];ws=rv['widths_m']
    for (a,b,wa,wb) in zip(pts,pts[1:],ws,ws[1:]):river_segs.append((np.array(a[:2],float),np.array(b[:2],float),float(wa),float(wb)))
def river_near(p):
    best=(1e9,None,None,0.0)
    for a,b,wa,wb in river_segs:
        ab=b-a;L2=float(ab@ab) or 1e-9;t=min(max(float((p-a)@ab)/L2,0.0),1.0)
        q=a+ab*t;d=float(np.hypot(*(p-q)))
        if d<best[0]:best=(d,q,ab/np.sqrt(L2),wa+(wb-wa)*t)
    return best
node_pts=np.array([n[:2] for n in flat_nodes],float)
moved_roads=0
for r in roads:
    g=r['geometry_points'];n=len(g)
    if n<5:continue
    P=np.array([p[:2] for p in g],float)
    shift=np.zeros_like(P)
    half_road=float(r.get('width_m',6))*.5
    for i in range(n):
        d,q,rt,w=river_near(P[i])
        clear=w*.5+half_road+4.0
        if q is None or d>=clear:continue
        a=P[max(i-2,0)];b=P[min(i+2,n-1)];tt=b-a;tl=float(np.hypot(*tt)) or 1.0
        if abs(float(tt@rt))/tl<.7:continue                   # a crossing: keep it
        side=P[i]-q;sl=float(np.hypot(*side))
        normal=side/sl if sl>1e-3 else np.array([-rt[1],rt[0]])
        shift[i]=normal*(clear-d)
    if not shift.any():continue
    # Smooth the shift along the road (~16 m), then fade it at the ends and near nodes.
    k=np.exp(-.5*(np.arange(-8,9)/3.0)**2);k/=k.sum()
    sm=np.stack([np.convolve(np.pad(shift[:,c],8,mode='edge'),k,mode='valid') for c in (0,1)],axis=1)
    sm=np.where(np.abs(sm)>np.abs(shift),sm,shift)
    for i in range(n):
        dn=float(np.min(np.hypot(*(node_pts-P[i]).T))) if len(node_pts) else 1e9
        de=min(i,n-1-i)*2.0
        fade=float(smooth((min(dn,de)-8.0)/16.0))
        g[i][0]+=float(sm[i,0])*fade;g[i][1]+=float(sm[i,1])*fade
    # BRIDGES-02: where the road crosses the river at a shallow angle, the samples before the crossing
    # went to one bank and those after it to the other - one 20-30 m segment spanned the water with no
    # sample on it, so no bridge pin (the deck stayed at bank height, 7 m over the water). Resample.
    dense_g=[g[0]]
    for a,b in zip(g,g[1:]):
        n=max(1,math.ceil(math.dist(a[:2],b[:2])/2.0))
        dense_g.extend([a[k]+(b[k]-a[k])*j/n for k in range(3)] for j in range(1,n+1))
    # The jump between the banks left an 80 deg zigzag at each bridge end: the road strip folded into
    # a wall there and the bridge rails ran across the road. Round it (~6 m), ends and nodes stay put.
    Q=np.array(dense_g,float);m=len(Q)
    kz=np.exp(-.5*(np.arange(-9,10)/3.0)**2);kz/=kz.sum()
    sq=np.stack([np.convolve(np.pad(Q[:,c],9,mode='edge'),kz,mode='valid') for c in (0,1)],axis=1)
    for i in range(m):
        dn=float(np.min(np.hypot(*(node_pts-Q[i,:2]).T))) if len(node_pts) else 1e9
        fade=float(smooth((min(dn,min(i,m-1-i)*2.0)-8.0)/16.0))
        dense_g[i][0]=float(Q[i,0]+(sq[i,0]-Q[i,0])*fade);dense_g[i][1]=float(Q[i,1]+(sq[i,1]-Q[i,1])*fade)
    r['geometry_points']=dense_g
    moved_roads+=1
print('RIVERSIDE_ROADS moved',moved_roads)

# Shape the river valleys at their authored elevations, including low terrain.
# Merely carving with min() leaves the water suspended above an unrelated base.
water_distance,water_height=nearest([r['points'] for r in D['rivers']])
_,water_width=nearest([[[p[0],p[1],w] for p,w in zip(r['points'],r['widths_m'])] for r in D['rivers']])
_,depth_width=nearest([[[p[0],p[1],w] for p,w in zip(r['points'],r['depth_widths_m'])] for r in D['rivers']])
valley_weight=1-smooth((water_distance-16)/95)
# RIVER-NATURAL-01: the valley is cut down to the water, never built up to it (that was the embankment),
# and only as a valley. Low down a broad floodplain (40 m each side 2 m over the water, then 1:3) where
# the roads, junctions and towns by the river lie - people keep to the rivers (owner 28 Sep); in the
# mountains a narrow one (16 m, then 1:1.7), not a trench sawn under the pass roads.
_mountain=smooth((water_height-100.0)/80.0)
_floor=40.0+(16.0-40.0)*_mountain;_side=0.33+(0.6-0.33)*_mountain
heights=np.minimum(heights,water_height+2+np.maximum(water_distance-_floor,0)*_side)
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
# RIVER-NATURAL-01: only the banks themselves (a few metres past the water), 0.5 m over it.
bank_weight=(1-smooth((water_distance-np.maximum(water_width*.5,3.0)-2.0)/6.0))*((d_sea<-30) if SEA else 1.0)
heights=heights*(1-bank_weight)+np.maximum(heights,water_height+.5)*bank_weight
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
    # RIVER-NATURAL-01: by a river the road keeps to the valley floor, whatever the old plan said.
    iz_=np.clip(np.round(pts[:,1]/STEP).astype(int),0,WIDTH-1);ix_=np.clip(np.round(pts[:,0]/STEP).astype(int),0,WIDTH-1)
    to_river=water_distance[iz_,ix_]
    keep=steep*smooth((np.abs(planned-ground)-4.0)/10.0)*smooth((to_city-150.0)/250.0)*smooth((to_river-120.0)/120.0)
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
        # 5 m: a rounded corner passes a junction up to ~3.5 m off (snow_desert at J1 missed its plate).
        if d[i]<5.0:nodes[key].append((rid,i))
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
# Actual channel is below water; road strips cross it as decks.
# RIVER-BANKS-01 (owner 27 Sep: "the river hangs in the air"): the water lies *inside* its channel.
# The bed is under the water; the bank starts 1.5 m inside the water's edge (so the water ribbon
# tucks into it) and half a metre past the edge stands 0.5 m over the water, then 1:1 up to the land. Where the land by a river is lower than that (after
# the basins, sea and roads), a low bank rises to it - never into the sea. The old channel was a
# flat trench 3+14 m wider than the water, so the water ribbon hung over its own bed.
river_depth=river_depth_for(depth_width)
river_half=np.maximum(water_width*.5,3.0)
river_bed=water_height-river_depth
river_bank=water_height+.5
def channel_profile():
    t=np.clip((water_distance-(river_half-1.5))/2.0,0,1)
    return river_bed+(river_bank-river_bed)*t*t*(3-2*t)+np.maximum(water_distance-(river_half+1.5),0)
def carve(h):
    h=np.minimum(h,channel_profile())
    inland=(d_sea<-30) if SEA else np.ones_like(h,bool)
    # A low bank on the downhill side: 0.5 m over the water to 4 m past the edge, then 1:1 down
    # to the land, so a grid triangle by the water never dips under it on a slope.
    ring=(water_distance>=river_half+.5)&(water_distance<=river_half+12.0)&inland
    levee=river_bank-np.maximum(water_distance-(river_half+4.0),0)
    return np.where(ring,np.maximum(h,levee),h)

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

# RIVER-BANKS-01: where the planned water would stand over its own banks (steep headwaters, the lake
# outlet, a confluence) the water comes down to them: at every point it stays 0.15 m under the lower
# bank just past the (widened) ribbon's edge and never rises downstream; the bed is cut under it again.
def river_widths(r,key='widths_m'):
    widths=[]
    for a,b,wa,wb in zip(r['points'],r['points'][1:],r[key],r[key][1:]):
        n=math.ceil(math.dist(a[:2],b[:2])/2)
        widths.extend(wa+(wb-wa)*i/n for i in range(n))
    widths.append(r[key][-1])
    return widths
def settle_river(r):
    pts=dense(r['points']);widths=river_widths(r)
    assert len(widths)==len(pts)
    planned=[p[1] for p in pts]
    for i,(p,w) in enumerate(zip(pts,widths)):
        a=pts[max(i-1,0)];b=pts[min(i+1,len(pts)-1)]
        tx,tz=b[0]-a[0],b[2]-a[2];n=math.hypot(tx,tz) or 1.0
        reach=max(w*.5,3.0)+3.0
        banks=[sample(p[0]+HALF-tz/n*s*reach,p[2]+HALF+tx/n*s*reach) for s in (-1,1)]
        if p[1]>1.0:p[1]=min(p[1],min(banks)-.15)
        if i:p[1]=min(p[1],pts[i-1][1])
    # No steps in the water: a drop spreads upstream at no more than 15 % (rapids, not a wall) -
    # or the plan's own fall where the river is planned steeper (RIVER-GRID-01: mountain rivers fall
    # up to ~55 %; at 15 % the water was dragged 50 m under its valley and recut() sawed a slot
    # canyon down to it, under the foothill cave bridge and below the spring cave).
    for i in range(len(pts)-2,-1,-1):
        run=math.dist((pts[i][0],pts[i][2]),(pts[i+1][0],pts[i+1][2]))
        fall=max(.15*run,(planned[i]-planned[i+1])*1.05)
        pts[i][1]=min(pts[i][1],pts[i+1][1]+fall)
    return pts,widths
# RIVER-GRID-01 (owner 28 Sep: the spring cave canyon is "cut up by textures along it"): where the
# settled water lies under the planned channel, the bed used to be sawn straight down inside the
# ribbon - a slot with vertical 5 m-grid walls that covered the water and stretched the texture.
# Now the banks come down to the water at 1:1 up to WALL_REACH from the edge; the ground under a
# road (road_cells, once the roads are laid) keeps its deck, so no road is undercut.
WALL_REACH=30.0
road_cells=None
def recut(settled):
    for rid,(pts,widths) in settled.items():
        planned=river_widths(next(r for r in D['rivers'] if r['id']==rid),'depth_widths_m')
        for a,b,w,pw in zip(pts,pts[1:],widths,planned):
            depth=float(river_depth_for(pw));half=max(w*.5,3.0)-.5;reach=half+WALL_REACH
            ax,az,bx,bz=a[0]+HALF,a[2]+HALF,b[0]+HALF,b[2]+HALF
            sl=(slice(max(0,int((min(az,bz)-reach)/STEP)),min(WIDTH,int((max(az,bz)+reach)/STEP)+2)),slice(max(0,int((min(ax,bx)-reach)/STEP)),min(WIDTH,int((max(ax,bx)+reach)/STEP)+2)))
            xx,zz=x[sl],z[sl];dx,dz=bx-ax,bz-az
            t=np.clip(((xx-ax)*dx+(zz-az)*dz)/max(dx*dx+dz*dz,1e-9),0,1)
            dist=np.hypot(xx-(ax+t*dx),zz-(az+t*dz))
            water=a[1]+t*(b[1]-a[1])
            profile=np.where(dist<=half,water-depth,water+.5+np.maximum(dist-(half+1.0),0))
            free=dist<=reach
            if road_cells is not None:free&=~(road_cells[sl]&(dist>half))
            heights[sl]=np.where(free,np.minimum(heights[sl],profile),heights[sl])

# River crossings are bridges. BRIDGES-02 (owner 28 Sep: "fix all the bridges" - a deck 50 m over the
# foothill gorge, 12 m over the lowland river, climbing across the water): the whole crossing is one
# level deck BRIDGE_CLEAR over the water - the road comes down its banks to it at its own grade -
# unless a junction or place plate pins the road higher there.
BRIDGE_CLEAR=1.0
# The water the bridge stands over is the settled one (it sinks under the plan where the banks are
# lower, up to 4 m by the lowland loop): settle it once on the carved ground as it is now, before
# the roads, and read the deck from that.
_ground=heights;heights=carve(_ground.copy())
for _ in range(2):
    _settled={r['id']:settle_river(r) for r in D['rivers']}
    recut(_settled)
heights=_ground
_water=np.array([[p[0]+HALF,p[2]+HALF,p[1]] for pts_,_w in _settled.values() for p in pts_])
def settled_water(px,pz):
    return float(_water[int(np.argmin(np.hypot(_water[:,0]-px,_water[:,1]-pz))),2])
for rid,(pts,h,step,grade,pins) in profiles.items():
    iz=np.clip(np.round(pts[:,1]/STEP).astype(int),0,WIDTH-1);ix=np.clip(np.round(pts[:,0]/STEP).astype(int),0,WIDTH-1)
    wet=water_distance[iz,ix]<water_width[iz,ix]*.5+4.0
    k=0
    while k<len(pts):
        if not wet[k]:k+=1;continue
        e=k
        while e<len(pts) and wet[e]:e+=1
        levels=[settled_water(*pts[j])+BRIDGE_CLEAR for j in range(k,e)]
        # A crossing is level; a long wet stretch (a road along the water) follows the water down.
        if float(step[k:e-1].sum())<=40.0:
            deck=max(levels)
            # RIVER-NATURAL-01: a junction or a place plate close above a valley cannot be left at the
            # road's grade down to the water - the bridge then stands that much higher over a ravine
            # (it was a 76 % drop to the desert crossroads bridge).
            along=np.concatenate([[0],np.cumsum(step)])
            for j,v in pins.items():
                if k<=j<e:continue
                gap=min(abs(along[j]-along[k]),abs(along[j]-along[e-1]))
                if gap<=60.0:deck=max(deck,v-grade*gap)
            levels=[deck]*len(levels)
        for j,deck in zip(range(k,e),levels):pins[j]=max(pins[j],deck) if j in pins else deck
        k=e
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
river_weight=(water_distance<=river_half+1.0).astype(float)
heights=carve(heights)
# WORLD-TERRAIN-02: soften what the shaping left (cut edges, crossings) everywhere except the road
# decks, then press the river channels and the decks back exactly.
def blur(a,sigma):
    k=int(3*sigma)+1;kern=np.exp(-.5*(np.arange(-k,k+1)/sigma)**2);kern/=kern.sum()
    p=np.pad(a,k,mode='edge')
    p=np.apply_along_axis(lambda v:np.convolve(v,kern,mode='valid'),0,p)
    return np.apply_along_axis(lambda v:np.convolve(v,kern,mode='valid'),1,p)
deck_w=np.where(dd<=core,1.0,1-ease((dd-core)/6.0))
heights=heights*deck_w+blur(heights,1.3)*(1-deck_w)
heights=carve(heights)
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
channel=water_distance<=river_half+.5
heights=np.where(np.isfinite(best)&~channel,target,heights)
road_cells=np.isfinite(best)

# WORLD-EDGES-01 (owner 27 Sep): the world ends in mountains - along the north, west and east edges
# the land rises 45-95 m within ~30 m (steeper than 60 deg, the hero climbs 45 at most), a ridge that
# varies along the edge; rock models dress its face in the game. The south is the sea.
edge_e=np.minimum(np.minimum(x,2000.0-x),z)
along=np.where(edge_e==z,x,z)
# Ridged: |sin| of incommensurable periods adds up to sharp crests and notches, not even waves.
ridge_h=40+sum(a*np.abs(np.sin(along/p+ph)) for a,p,ph in ((22,397.,.3),(16,173.,1.7),(10,89.,2.9),(6,37.,.8)))
# The crest stands over the highest land within 300 m of the edge (owner 27 Sep: from the high
# mine one could jump over the old ridge, which only rose over the land right at the edge).
band=60
top_n=np.maximum.accumulate(heights[band::-1,:],axis=0)[-1][None,:]      # north: rows 0..band
top_w=np.maximum.accumulate(heights[:,band::-1],axis=1)[:,-1][:,None]     # west: columns 0..band
top_e=np.maximum.accumulate(heights[:,-band-1:],axis=1)[:,-1][:,None]     # east: last columns
near_top=np.where(edge_e==z,np.broadcast_to(top_n,heights.shape),np.where(x<1000,np.broadcast_to(top_w,heights.shape),np.broadcast_to(top_e,heights.shape)))
crest=np.maximum(heights+ridge_h,near_top+20+ridge_h)
wall=1-smooth((edge_e-12.0)/30.0)
heights=heights*(1-wall)+crest*wall

# Twice: the cut bed moves the ground by the water's edge, the water settles to it once more.
# Before the colours (RIVER-GRID-01): the cut banks are 1:1 and turn bare rock like any steep slope.
for _ in range(2):
    settled={r['id']:settle_river(r) for r in D['rivers']}
    recut(settled)

# Clay color masses only. Roads come from the road mask, water from its own strips.
colors=np.zeros((WIDTH,WIDTH,4));colors[:,:,:]=[.43,.52,.43,1]
desert=(x>1210)&(z<1570);colors[desert]=[.66,.57,.43,1]
low=z>1390+110*np.sin(x/200);colors[low]=[.37,.52,.49,1]
rock=smooth((heights-165)/155)[:,:,None]
# LAKE-SHORE-01 (owner 28 Sep: no grass and no trees by the mountain lake): a meadow ring round each
# lake, below the treeline, keeps the forest colour instead of the altitude's bare rock, so grass and
# the far forest (bake.py reads the forest green) grow on its shore. Steep slopes stay rock.
for lake in D['lakes']:
    lx,lz,_lv=lake['center'];lrx,lrz=lake['radii_m']
    lq=np.hypot((x-lx)/lrx,(z-lz)/lrz)
    meadow=(1-smooth((lq-1.7)/.6))*(1-smooth((heights-300)/30))
    rock=rock*(1-meadow[:,:,None])
colors[:,:,:3]=colors[:,:,:3]*(1-rock)+np.array([.55,.56,.54])*rock
# WORLD-EDGES-01: bare rock on every slope steeper than ~35 deg (the edge ridge, gorges, cliffs), so
# no meadow colour - and no grass - climbs a cliff.
_gz,_gx=np.gradient(heights,STEP)
steep_rock=smooth((np.degrees(np.arctan(np.hypot(_gx,_gz)))-30.0)/12.0)[:,:,None]
colors[:,:,:3]=colors[:,:,:3]*(1-steep_rock)+np.array([.55,.56,.54])*steep_rock
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

OUT.mkdir(parents=True,exist_ok=True)
(OUT/'heights.bin').write_bytes(heights.astype('<f4').tobytes())
(OUT/'colors.bin').write_bytes(colors.astype('<f4').tobytes())
def water_record(r):
    points,widths=settled[r['id']]
    # SHORE-MESH-01: the game rebuilds the banks at 1.25 m along the water from these.
    depths=[round(float(river_depth_for(w)),3) for w in river_widths(r,'depth_widths_m')]
    return {**r,'world_points':points,'world_widths':widths,'world_depths':depths}

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
