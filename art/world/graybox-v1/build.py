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
# WORLD-BUILD-01B (D-118, the book's W1 project, sheet wfW1, PDF141 pp 86-87): the mountain lake's
# water hung 60 m over its southern slope (mirror 228, ground 221-162). Its mirror goes down to 220 m
# and the 85 x 60 m ellipse is cut by the stone sill at z 355 (cut_z): south of it is land. The
# west river starts at the sill and falls by the book's nodes, a cascade of 57 m on the ground to the
# pool at 163 m; those nodes are pinned (no rapids limit, no smoothing) - the rest of the river is
# settled as before.
W1_NODES=[(330,355,220.0),(330,371,206.0),(330,385,192.0),(330,399,178.0),(330,415,163.0)]
# The sheet's ledges: from the sill a fall to each node, a 4 m plunge pool level at the node
# (the sheet's 10 x 4 m basins under ledges 1-3), then the next fall; the river's own pool at 163 m.
W1_PROFILE=[(330,355,220.0)]
for (_x,_z,_h),(_x2,_z2,_h2) in zip(W1_NODES,W1_NODES[1:]):
    W1_PROFILE+= [(330,_z2,_h2),(330,_z2+4,_h2)]
for lake in D['lakes']:
    if lake['id']=='mountain_lake':
        lake['center']=[330,360,220.0];lake['radii_m']=[85,60];lake['outlet']=[330,355,220.0];lake['cut_z']=355.0
for rv in D['rivers']:
    if rv['id']=='west':
        tail=[(p,w,dw) for p,w,dw in zip(rv['points'],rv['widths_m'],rv['depth_widths_m']) if p[1]>420]
        rv['points']=[list(n) for n in W1_PROFILE]+[t[0] for t in tail]
        rv['widths_m']=[12.0]*len(W1_PROFILE)+[t[1] for t in tail]
        rv['depth_widths_m']=[12.0]*len(W1_PROFILE)+[t[2] for t in tail]
        rv['pinned_head']=len(W1_PROFILE)
lake_of={l['river_id']:l for l in D['lakes'] if l.get('river_id')}
settled_courses={}
def natural_course(rv):
    pts=rv['points'];cols=[rv['widths_m'],rv['depth_widths_m']];out=[];ws=[[],[]];pinned_upto=-1
    for k,(a,b,*w) in enumerate(zip(pts,pts[1:],*[c for c in cols],*[c[1:] for c in cols])):
        if k==rv.get('pinned_head',0)-1:pinned_upto=len(out)
        n=max(1,math.ceil(math.dist(a[:2],b[:2])/RIVER_STEP))
        for i in range(n):
            t=i/n;out.append([a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t])
            ws[0].append(w[0]+(w[2]-w[0])*t);ws[1].append(w[1]+(w[3]-w[1])*t)
    out.append(list(pts[-1]));ws[0].append(cols[0][-1]);ws[1].append(cols[1][-1])
    level=[min(p[2],natural_floor(p[0],p[1])-RIVER_INTO_GROUND) for p in out]
    if rv['id'] in lake_of:level[0]=float(lake_of[rv['id']]['center'][2])
    # WORLD-BUILD-01B: a pinned head (the W1 cascade) keeps the book's levels between its nodes.
    for i in range(pinned_upto+1):level[i]=out[i][2]
    for i in range(1,len(level)):level[i]=min(level[i],level[i-1])
    # A tributary ends in its river's water (that river is settled first).
    end=out[-1]
    for other,(opts,olevel) in settled_courses.items():
        d=[math.dist(end[:2],q[:2]) for q in opts];k=int(np.argmin(d))
        if d[k]<20.0:level[-1]=min(level[-1],olevel[k])
    for i in range(len(level)-2,pinned_upto,-1):
        level[i]=min(level[i],level[i+1]+RAPIDS*math.dist(out[i][:2],out[i+1][:2]))
    for p,h in zip(out,level):p[2]=round(h,2)
    rv['points']=out;rv['widths_m']=ws[0];rv['depth_widths_m']=ws[1]
    if pinned_upto>=0:rv['pinned_head_z']=out[pinned_upto][1]
    settled_courses[rv['id']]=(out,level)
# Rivers others flow into come first (main before its tributaries).
for rv in sorted(D['rivers'],key=lambda r:0 if r['id']=='main' else 1):natural_course(rv)

# The city coordinates on the plan are road anchors. Small plazas sit on dry banks.
# WORLD-BUILD-01F (D-118: the lowland citadel on the spur, the road moved and a new bridge): the
# plan's lowland point (1030/1640) - where the desert, forest and fishing-village roads met - is the
# spur the citadel now takes. The city's point is its market inside the walls; the roads end at its
# gates (the book's links): the desert road at the east gate, the forest road at the west gate, and
# the fishing-village loop leaves by the south gate over the new bridge below the wall, rejoining
# its old line south-east (sheet 23, plan_lowland.py).
for _c in D['cities']:
    if _c['id']=='lowland':_c['point']=[1075,1592,18]
for _r in D['roads']:
    if _r['id']=='desert_lowland':
        _r['points']=[q for q in _r['points'] if q[0]>1200]+[[1128,1556,19]]
    elif _r['id']=='lowland_forest':
        _r['points']=[[992,1578,19]]+[q for q in _r['points'] if q[0]<1000]
    elif _r['id']=='lowland_loop':
        _r['points']=[q for q in _r['points'] if q[0]>1200]+[[1168,1760,6],[1150,1745,8],[1118,1700,13],[1108,1672,16],[1102,1656,18],[1074,1638,18.5],[1050,1634,18.6]]
offsets={'forest':[-35,35],'snow':[0,0],'desert':[45,-35],'lowland':[0,0]}
roads=[dict(r) for r in D['roads']]
cities=[]
for city in D['cities']:
    px,pz,ph=city['point'];ox,oz=offsets[city['id']];plaza=[px+ox,pz+oz,ph]
    # WORLD-TERRAIN-02: the plaza height comes later from the ground (a basin), not from the plan.
    cities.append({**city,'plaza':plaza})
    if ox or oz:roads.append({'id':'approach_'+city['id'],'points':[plaza,city['point']],'connector':True})
# WORLD-BUILD-01B (sheet wfW1): the footbridge below the W1 pool (z 440) - a trail across the west
# river; the game's bridges stand on every crossing (BRIDGES-01). The west bank is a plain 6 m under
# the deck: the trail runs on to x 250 so its ramp down stays as gentle as the bridge's own (Codex
# 14 Oct: at 286 the end pinned it to the plain, a 40 % drop the bridge ramp could not follow and the
# hero was stopped by its toe).
roads.append({'id':'w1_footbridge','points':[[352,440,160],[250,440,150]],'width_m':3,'label':'W1 footbridge'})
# WORLD-BUILD-01G (book PDF141 p.59/p.27, Codex 331/333: foothill cave X stood on a 45-50 deg mountain
# side, no way to it): the smugglers' trail from the cave's exit X (~600/438) up the north slope past
# the snow city to the old drainage adit Sh2 (~1005/244), round the council's outpost (25 m) and the
# snow city's ring, 7-9 m outside its walls (tests57: a line along the west wall made the wall leave a gap
# for it and the Sh2 stair hit the north-west corner) - the plan's grade-limited path (<= 30 %). Its gentle legs are trails here;
# its three steep climbs are stone switchback stairs (SMUGGLER_STAIRS below).
SMUGGLER_LEGS=[
    [[625.0,445.0,188.2],[660.0,445.0,189.8],[730.0,480.0,189.9],[765.0,465.0,198.0],[800.0,470.0,205.9],[820.0,440.0,215.7],[815.0,430.0,218.2],[815.0,385.0,224.3],[825.0,365.0,227.7],[840.0,355.0,231.6]],
    [[860.0,320.0,261.8],[903.0,320.0,270.5],[892.0,306.0,274.5],[890.0,300.0,278.3],[900.0,288.0,281.5]],
    [[900.0,249.0,303.0],[920.0,240.0,307.2],[995.0,240.0,308.3],[999.0,242.0,308.0]],
]
for _k,_pts in enumerate(SMUGGLER_LEGS):
    roads.append({'id':'smugglers_trail_%d'%(_k+1),'points':_pts,'width_m':3,'label':'smugglers trail','planned':True})

sites=D['sites']
plazas=[c['plaza'] for c in cities]+[s['point'] for s in sites]
# the smugglers' trail ('planned') is no anchor: its ends lie on the mountain side, not at a junction
anchors={tuple(r['points'][end]) for r in roads for end in [0,-1] if not r.get('planned')}

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
            for nx,nz,nh in ([] if r.get('planned') else flat_nodes):
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
    # the smugglers' trail's heights come from the finished ground (the plan's path finder): kept
    if r.get('planned'):keep=np.ones_like(keep)
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
# the smugglers' trail keeps its planned profile: no plate or shared stretch pins it (a plan junction
# by the snow city pinned its third leg 12.6 m under its own start)
_planned_ids={r['id'] for r in roads if r.get('planned')}
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
        if ra in _planned_ids or rb in _planned_ids:continue
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
    hits[:]=[(rid,i) for rid,i in hits if rid not in _planned_ids]
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
    head_z=r.get('pinned_head_z')   # WORLD-BUILD-01B: the W1 cascade keeps the book's levels
    for i,(p,w) in enumerate(zip(pts,widths)):
        if head_z is not None and p[2]+HALF<=head_z+0.5:
            if i:p[1]=min(p[1],pts[i-1][1])
            continue
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
    for rid,val in settled.items():
        # (points, widths) of a whole river, or of a stretch from its point `start` on (WORLD-BUILD-01D)
        pts,widths=val[0],val[1];start=val[2] if len(val)>2 else 0
        planned=river_widths(next(r for r in D['rivers'] if r['id']==rid),'depth_widths_m')[start:]
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
_main=[r for r in roads if not r.get('planned')]
_trail=[r for r in roads if r.get('planned')]
dd,dh=nearest([r['geometry_points'] for r in _main],130)
_,dw=nearest([[[p[0],p[1],float(r.get('width_m',6))] for p in r['geometry_points']] for r in _main],130)
core=dw*.5+1.0
fall=np.clip(3.0*np.abs(heights-dh),6.0,90.0)
w=np.where(dd<=core,1.0,1-ease((dd-core)/fall))
heights=heights*(1-w)+(dh-.05)*w
# WORLD-BUILD-01G: the smugglers' trail on a 45 deg mountain side - a 1:3 fade cut or filled up to 90 m
# of the slope round it (first bake: -37/+19 m); a mountain path meets its slope 1:1 within 15 m.
if _trail:
    td,th=nearest([r['geometry_points'] for r in _trail],40)
    tcore=float(_trail[0].get('width_m',3))*.5+1.0
    tfall=np.clip(np.abs(heights-th),3.0,15.0)
    tw=np.where(td<=tcore,1.0,1-ease((td-tcore)/tfall))
    heights=heights*(1-tw)+(th-.05)*tw
    dd=np.minimum(dd,td)
# A level lake basin with a continuous shoreline; its outlet joins the river profile.
for lake in D['lakes']:
    px,pz,level=lake['center'];rx,rz=lake['radii_m']
    q=np.hypot((x-px)/rx,(z-pz)/rz)
    # a cut lake (W1 sill): past the cut the ground is shore, rising as outside the ellipse
    if 'cut_z' in lake:q=np.where(z>lake['cut_z'],np.maximum(q,1.0+(z-lake['cut_z'])/rz),q)
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

# WORLD-BUILD-01A (D-118, the accepted world book WORLD-PLAN-01): the book's level pads, map metres.
# Inside the polygon the ground takes the level; over `margin` metres outside it eases back to the
# land. Road decks and river channels keep their ground (they were laid before). The snow city's
# middle terrace and the Academy shelf are cuts into the slope with a short margin: their steep
# edges are where the book puts retaining walls and the rock face; the capital ruins' terrace is a
# plateau over the lower valley with a long soft slope.
BOOK_PADS=[
    # The book's sheet put the terrace's north edge at z 1135: the lower valley road (forest_desert)
    # runs along z 1140-1149 there. The whole ruins moved 22 m south (centre 1200/1212), a 12 m
    # slope keeps clear of the road's cells; deviation recorded in WORLD_BUILD_01_TASK.md.
    {'id':'capital_ruins','level':128.0,'margin':12.0,'poly':[(1130,1162),(1270,1162),(1270,1277),(1130,1277)]},
    {'id':'snow_middle_terrace','level':288.0,'margin':4.0,'poly':[(930,258),(1016,258),(1020,284),(928,286)]},
    {'id':'snow_academy_shelf','level':298.0,'margin':4.0,'poly':[(1046,278),(1088,274),(1090,306),(1050,310)]},
    # sheet wfW1: the viewing platform beside ledge 2, east of the falls (6 x 4 m on the sheet) - a
    # 10 x 10 m terrace on the 5 m grid (a 4 m pad falls between grid points), its own ground;
    # laid late, after the rivers' final cut (see the W1 block)
    {'id':'w1_viewpoint','level':None,'margin':3.0,'late':True,'poly':[(350,380),(360,380),(360,390),(350,390)]},
]
def poly_distance(poly):
    """Distance of every grid point to the polygon (0 inside)."""
    inside=np.zeros(x.shape,bool);dist=np.full(x.shape,np.inf)
    for (ax,az),(bx,bz) in zip(poly,poly[1:]+poly[:1]):
        cross=((az>z)!=(bz>z))&(x<(bx-ax)*(z-az)/((bz-az) if bz!=az else 1e-9)+ax)
        inside^=cross
        dx,dz=bx-ax,bz-az
        t=np.clip(((x-ax)*dx+(z-az)*dz)/(dx*dx+dz*dz),0,1)
        dist=np.minimum(dist,np.hypot(x-ax-t*dx,z-az-t*dz))
    return np.where(inside,0.0,dist)
def lay_pad(pad):
    global heights
    if pad['level'] is None:
        cx=sum(p[0] for p in pad['poly'])/len(pad['poly']);cz=sum(p[1] for p in pad['poly'])/len(pad['poly'])
        pad['level']=round(float(heights[int(round(cz/STEP)),int(round(cx/STEP))]),2)
    d=poly_distance(pad['poly'])
    w=1-smooth(d/pad['margin'])
    keep=road_cells|channel
    heights=np.where(keep,heights,heights*(1-w)+pad['level']*w)
for pad in BOOK_PADS:
    if not pad.get('late'):lay_pad(pad)

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
# WATER-02 (owner 28 Sep: "on the drops and joints the water looks untidy"): the settled water kept
# small steps (0.5-1 m within 2 m) where a bank pulled it down; each is spread into a ramp: the
# water sinks to the mean of +-10 m, twice, and is never raised (it stays inside its banks).
# WORLD-BUILD-01B: the W1 cascade (a pinned head) keeps its falls - no ramps spread over them.
for rid,(pts,widths) in settled.items():
    head_z=next((r.get('pinned_head_z') for r in D['rivers'] if r['id']==rid),None)
    for _ in range(2):
        ys=[p[1] for p in pts]
        for i in range(len(pts)):
            if head_z is not None and pts[i][2]+HALF<=head_z+2.0:continue
            lo,hi=max(0,i-5),min(len(pts),i+6)
            pts[i][1]=min(ys[i],sum(ys[lo:hi])/(hi-lo))

# WORLD-BUILD-01D (D-118, the book's waterfalls W2-W5, PDF141 list of falls): each is a span of its
# river's steepest stretch (about 30 m) that now falls in ledges - a drop, then a level pool to the
# next - instead of the even 45 % chute the settling left. The ledges only cut down from the chute
# (never raise the water over its banks); the ground under the span is cut to the new water, so each
# pool has its basin. The total drop and the river outside the span are unchanged.
FALLS=[('W2','west',263,561,30.0,3),('W3','main',858,513,30.0,3),('W4','east',1558,861,30.0,3),('W5','east',1412,640,30.0,3)]
FALL_LIP=0.22   # the share of each ledge's length its drop takes
falls_spans={}
for fid,rid,fx,fz,span,steps in FALLS:
    pts,widths=settled[rid]
    d=[math.hypot(p[0]+HALF-fx,p[2]+HALF-fz) for p in pts];k=int(np.argmin(d))
    along=[0.0]
    for a,b in zip(pts,pts[1:]):along.append(along[-1]+math.hypot(b[0]-a[0],b[2]-a[2]))
    i0=k
    while i0>0 and along[k]-along[i0]<span*.5:i0-=1
    i1=k
    while i1<len(pts)-1 and along[i1]-along[k]<span*.5:i1+=1
    top,bottom=pts[i0][1],pts[i1][1];drop=top-bottom;length=along[i1]-along[i0]
    ledge=length/steps
    for i in range(i0,i1+1):
        s_=along[i]-along[i0];j=min(int(s_/ledge),steps-1);u=s_-j*ledge
        t=min(max(u/(ledge*FALL_LIP),0.0),1.0);t=t*t*(3-2*t)
        pts[i][1]=min(pts[i][1],top-drop*(j+t)/steps)
    falls_spans[fid]=(rid,i0,i1)
    print('FALL',fid,rid,'points',i0,i1,'drop %.1f m over %.0f m in %d ledges'%(drop,length,steps))
# the ground under the falls' spans cut to their new water (recut for those segments only)
for fid,(rid,i0,i1) in falls_spans.items():
    pts,widths=settled[rid]
    recut({rid:(pts[i0:i1+1],widths[i0:i1+1],i0)})

# WORLD-BUILD-01B: under the W1 cascade the ground follows its water at the stream's depth (the
# valley shaping had cut a 4-5 m trough under the pinned falls): a shallow cascade on its ledges.
for r in D['rivers']:
    head_z=r.get('pinned_head_z')
    if head_z is None:continue
    pts,widths=settled[r['id']]
    # Each cell takes the bed of its nearest stretch (on a 1:1 fall a neighbour's end lies within
    # the half width and would lift the cell to the water upstream).
    best=np.full(heights.shape,np.inf);beds=np.zeros(heights.shape);waters=np.zeros(heights.shape);halves=np.zeros(heights.shape)
    for a,b,w in zip(pts,pts[1:],widths):
        if b[2]+HALF>head_z+0.5:break
        half=max(w*.5,3.0)+1.0;reach=half+12.0
        ax,az,bx,bz=a[0]+HALF,a[2]+HALF,b[0]+HALF,b[2]+HALF
        sl=(slice(max(0,int((min(az,bz)-reach)/STEP)),min(WIDTH,int((max(az,bz)+reach)/STEP)+2)),slice(max(0,int((min(ax,bx)-reach)/STEP)),min(WIDTH,int((max(ax,bx)+reach)/STEP)+2)))
        xx,zz=x[sl],z[sl];dx,dz=bx-ax,bz-az
        t=np.clip(((xx-ax)*dx+(zz-az)*dz)/max(dx*dx+dz*dz,1e-9),0,1)
        dist=np.hypot(xx-(ax+t*dx),zz-(az+t*dz))
        water=a[1]+t*(b[1]-a[1]);bed=water-float(river_depth_for(w))
        nearer=(dist<=reach)&(dist<best[sl])
        best[sl]=np.where(nearer,dist,best[sl]);beds[sl]=np.where(nearer,bed,beds[sl])
        waters[sl]=np.where(nearer,water,waters[sl]);halves[sl]=np.where(nearer,half,halves[sl])
    # under the water its bed; beside it a low bank 0.5 m over the water to 3 m past the edge, then
    # 1:1 down to the land (the cascade had run on a crest, its edges over lower ground)
    levee=waters+.5-np.maximum(best-(halves+3.0),0)
    # only south of the lake's cut: inside the lake its own basin holds (no bank islands by the outflow)
    south=np.ones(heights.shape,bool)
    for lake in D['lakes']:
        if lake.get('river_id')==r['id'] and lake.get('cut_z') is not None:south=z>=lake['cut_z']-0.5
    inside=np.isfinite(best)&(best<=halves)&south
    beside=np.isfinite(best)&(best>halves)&south
    heights=np.where(inside,np.maximum(heights,beds),np.where(beside,np.maximum(heights,levee),heights))
for pad in BOOK_PADS:
    if pad.get('late'):lay_pad(pad)
# The W1 footbridge's ramps (Codex 14 Oct: a triangle of ground cut through the boards in the west
# approach - on the 5 m grid the ground bulges at the ramp's knee): within 28 m of the crossing the
# ground stays 0.3 m under the deck, across the trail's width.
for r in roads:
    if r['id']!='w1_footbridge':continue
    gp=r['geometry_points']
    for a,b in zip(gp,gp[1:]):
        if min(abs(a[0]-322),abs(b[0]-322))>28.0:continue   # the ramps reach ~22 m from the crossing
        # 6 m: the trail runs along a grid row; the rows 5 m to either side must come down too or their
        # triangles rise over the boards' edges (Codex 5b143f4 frame 012)
        reach=6.0
        sl=(slice(max(0,int((min(a[1],b[1])-reach)/STEP)),min(WIDTH,int((max(a[1],b[1])+reach)/STEP)+2)),slice(max(0,int((min(a[0],b[0])-reach)/STEP)),min(WIDTH,int((max(a[0],b[0])+reach)/STEP)+2)))
        xx,zz=x[sl],z[sl];dx,dz=b[0]-a[0],b[1]-a[1]
        t=np.clip(((xx-a[0])*dx+(zz-a[1])*dz)/max(dx*dx+dz*dz,1e-9),0,1)
        dist=np.hypot(xx-(a[0]+t*dx),zz-(a[1]+t*dz))
        deck=a[2]+t*(b[2]-a[2])
        heights[sl]=np.where(dist<=reach,np.minimum(heights[sl],deck-.3),heights[sl])
# WORLD-BUILD-01B (sheet wfW1, Codex ACK160 and ACK162 variant b): the east stair flights from the lake
# shore at 360/360 down to the viewpoint's terrace and on to the footbridge at 350/436. Stone flights
# 2 m wide, risers ~0.18 m, treads ~0.28 m; landings only where the flights turn. Under each tread
# the ground is cut below it; where a tread stands over lower ground the game builds its stone body
# down to the ground.
STAIR_RISE,STAIR_RUN,STAIR_WIDTH=.18,.28,2.0
# Records: [x, z, top, yaw_deg, depth, width, rail] in map metres; depth along yaw, width across;
# rail: 0 none, -1/+1 a rail on that side (local x), 2 a rail across the far end (local +z).
def _rec(x_,z_,top,yaw,depth,width=STAIR_WIDTH,rail=0):
    return [round(x_,3),round(z_,3),round(top,3),round(yaw,2),round(depth,3),round(width,3),rail]
def stair_switchback(top_xz,h0,h1,z_end,xc,flights):
    """Variant (b), Codex 14 Oct: flights across the slope, side by side 2 m apart down the slope
    (one solid stepped body, no gap to fall in), turn landings at the ends, a rail on each flight's
    downhill side and round each landing's outer end."""
    n=max(1,int(round((h0-h1)/STAIR_RISE)));rise=(h0-h1)/n
    per=[n//flights+(1 if k<n%flights else 0) for k in range(flights)]
    z0=top_xz[1]+1.0
    out=[];h=h0
    for k,r in enumerate(per):
        zc=z0+k*STAIR_WIDTH;L=r*STAIR_RUN;d=-1.0 if k%2==0 else 1.0
        xs=xc-d*L*.5
        yaw=-90.0 if d<0 else 90.0
        if k==0:out.append(_rec(xs-d*1.0,zc-.5,h,yaw,2.0,3.0,0))   # the head landing by the shore
        for i in range(r):
            out.append(_rec(xs+d*STAIR_RUN*(i+.5),zc,h-rise*(i+1),yaw,STAIR_RUN+.02,STAIR_WIDTH,-1 if d<0 else 1))
        h-=rise*r
        xe=xs+d*L
        if k<flights-1:
            out.append(_rec(xe+d*1.0,zc+STAIR_WIDTH*.5,h,yaw,2.0,2*STAIR_WIDTH,2))
        else:
            # the last landing reaches south onto the viewpoint's terrace
            zz=(zc-STAIR_WIDTH*.5+z_end)*.5
            out.append(_rec(xe+d*1.0,zz,h,0.0,z_end-(zc-STAIR_WIDTH*.5),2.0,0))
    return out
def stair_straight(a_xz,b_xz,h0,h1):
    n=max(1,int(round((h0-h1)/STAIR_RISE)));rise=(h0-h1)/n
    dx,dz=b_xz[0]-a_xz[0],b_xz[1]-a_xz[1];L=math.hypot(dx,dz);ux,uz=dx/L,dz/L;run=L/n
    yaw=math.degrees(math.atan2(ux,uz))
    # a stone landing from the terrace's edge to the first tread, at the terrace's level
    out=[_rec(a_xz[0]-ux*1.3,a_xz[1]-uz*1.3,h0,yaw,2.6,STAIR_WIDTH,0)]
    for i in range(n):
        c=run*(i+.5)
        out.append(_rec(a_xz[0]+ux*c,a_xz[1]+uz*c,h0-rise*(i+1),yaw,run+.02,STAIR_WIDTH,3))   # 3: rails both sides
    return out
BOOK_STAIRS=[]
W1_STAIRS=True
_vp=next((p_ for p_ in BOOK_PADS if p_['id']=='w1_viewpoint'),None)
if W1_STAIRS and _vp is not None:
    _top=(360.0,360.0);_foot=(350.0,436.0)
    _h_top=float(heights[int(round(_top[1]/STEP)),int(round(_top[0]/STEP))])
    _h_foot=float(heights[int(round(_foot[1]/STEP)),int(round(_foot[0]/STEP))])
    _lvl=float(_vp['level'])
    _steps=stair_switchback(_top,_h_top,_lvl,381.5,358.0,10)+stair_straight((358.5,392.0),_foot,_lvl,_h_foot)
    BOOK_STAIRS.append({'id':'w1_stairs','steps':_steps})
    # the cut under every tread and landing: the grid points near it below its top; the viewpoint's
    # terrace keeps its level (the flights land on it and leave it)
    for sx,sz,top,_yaw,dep,wid,_r in _steps:
        reach=max(dep,wid)*.5+4.0+(1.0 if dep>1.0 else 0.0)
        i0,i1=max(0,int((sz-reach)/STEP)),min(WIDTH-1,int((sz+reach)/STEP)+1)
        j0,j1=max(0,int((sx-reach)/STEP)),min(WIDTH-1,int((sx+reach)/STEP)+1)
        win=heights[i0:i1+1,j0:j1+1];_vx,_vz=x[i0:i1+1,j0:j1+1],z[i0:i1+1,j0:j1+1]
        near=np.hypot(_vx-sx,_vz-sz)<=reach
        near&=~((_vx>=349.9)&(_vx<=360.1)&(_vz>=380.1)&(_vz<=390.1))
        heights[i0:i1+1,j0:j1+1]=np.where(near,np.minimum(win,top-.12),win)
# WORLD-BUILD-01C (D-118, the book's snow city sheet and its profiles 16-snow-profile-A/B/C): the stair
# routes between the terraces at the book's node levels. A: lower 274 -> landing 281 -> middle 288.
# B: middle 288 -> 291 -> abutment 294 -> rope bridge over the meltwater channel -> abutment 295 ->
# Academy 298. C: the porters' flights from the east gate 276 -> 283 -> 291 -> Academy 298. Rises
# ~0.18 m, treads 0.28 m (0.25 at the least on a short leg), the rest of a leg a level landing.
def stair_route(nodes,width=2.5,bridge_legs=()):
    out=[]
    for k,((ax,az,ah),(bx,bz,bh)) in enumerate(zip(nodes,nodes[1:])):
        L=math.hypot(bx-ax,bz-az);ux,uz=(bx-ax)/L,(bz-az)/L;yaw=math.degrees(math.atan2(ux,uz))
        if k in bridge_legs:
            n=max(2,int(round(L/2.0)))
            for i in range(n):
                c=L*(i+.5)/n
                out.append(_rec(ax+ux*c,az+uz*c,ah+(bh-ah)*(i+.5)/n,yaw,L/n+.02,width,4))   # 4: bridge deck
            continue
        rise=bh-ah;n=int(round(abs(rise)/STAIR_RISE))
        if n==0:
            out.append(_rec((ax+bx)*.5,(az+bz)*.5,ah,yaw,L+.02,width,3));continue
        run=min(STAIR_RUN,max(.25,(L-1.0)/n));flight=n*run;flat=max(L-flight,0.0)
        # the walking slab of a tread falls along its yaw (as on W1): a climbing leg faces back down it
        tyaw=yaw+180.0 if rise>0 else yaw
        # the flight in the middle of the leg, level landings before and after it
        a0=flat*.5;h=ah;dr=rise/n
        if a0>.05:out.append(_rec(ax+ux*a0*.5,az+uz*a0*.5,ah,yaw,a0+.02,width,3))
        for i in range(n):
            c=a0+run*(i+.5)
            out.append(_rec(ax+ux*c,az+uz*c,ah+dr*(i+1),tyaw,run+.02,width,3))
        a1=L-a0-flight
        if a1>.05:out.append(_rec(bx-ux*a1*.5,bz-uz*a1*.5,bh,yaw,a1+.02,width,3))
    return out
SNOW_ROUTES=[
    ('snow_stairs_A',[(976,304,274.0),(970,296,281.0),(970,288,281.0),(976,273,288.0)],3.0,()),
    ('snow_stairs_B',[(1012,272,288.0),(1024,275,291.0),(1030,279,294.0),(1046,287,295.0),(1052,292,298.0)],2.5,(2,)),
    ('snow_stairs_C',[(1034,336,276.0),(1044,326,283.0),(1050,316,291.0),(1056,307,298.0)],2.5,()),
]
_snow_pad_mask=np.zeros(heights.shape,bool)
for pad in BOOK_PADS:
    if pad['id'].startswith('snow'):_snow_pad_mask|=poly_distance(pad['poly'])<=0.0
for _sid,_nodes,_w,_bl in SNOW_ROUTES:
    # a route starts at the book's level of its street; where the ground stands higher there, the
    # flight's cut below lowers it (Codex 6ef4e04: started on the bank at 280.36, stair C's foot
    # stood 4-6 m over the lower street at 274-276)
    _st=stair_route(_nodes,_w,_bl)
    BOOK_STAIRS.append({'id':_sid,'steps':_st})
    for sx,sz,top,_yaw,dep,wid,_r in _st:
        if _r==4:continue    # the bridge spans the channel: no cut under it
        reach=max(dep,wid)*.5+4.5   # past the next grid node, or its triangle lifts between them
        i0,i1=max(0,int((sz-reach)/STEP)),min(WIDTH-1,int((sz+reach)/STEP)+1)
        j0,j1=max(0,int((sx-reach)/STEP)),min(WIDTH-1,int((sx+reach)/STEP)+1)
        win=heights[i0:i1+1,j0:j1+1];near=np.hypot(x[i0:i1+1,j0:j1+1]-sx,z[i0:i1+1,j0:j1+1]-sz)<=reach
        # inside a terrace only the flight's own well (the book ends route A 13 m into the middle
        # terrace, behind its retaining wall); the rest of the terrace keeps its level
        well=np.hypot(x[i0:i1+1,j0:j1+1]-sx,z[i0:i1+1,j0:j1+1]-sz)<=max(dep,wid)*.5+2.5
        near&=~_snow_pad_mask[i0:i1+1,j0:j1+1]|well
        heights[i0:i1+1,j0:j1+1]=np.where(near,np.minimum(win,top-.12),win)
# WORLD-BUILD-01G: the smugglers' trail's steep climbs as stone switchbacks - legs 45 deg off the fall
# line (a ~0.6 grade on these slopes, the stairs' own), landings at the turns, the treads at the ground's
# level along each leg and the ground cut under them (as the snow routes).
def stair_zigzag(top_xz,top_h,foot_xz,foot_h,legs,width=2.0):
    """From top to foot in `legs` legs zigzagging off the fall line, landings at the turns; each leg
    rises an equal share, its angle off the fall line set so the leg is no steeper than its treads."""
    fx,fz=foot_xz[0]-top_xz[0],foot_xz[1]-top_xz[1];F=math.hypot(fx,fz);fx,fz=fx/F,fz/F
    cx,cz=-fz,fx
    adv=(F-2.5*(legs-1))/legs
    rise=(foot_h-top_h)/legs
    L=max(adv,abs(rise)/.6+1.0)
    ca,sa=adv/L,math.sqrt(max(0.0,1-(adv/L)**2))
    nodes=[(top_xz[0],top_xz[1],top_h)];px,pz=top_xz;side=1.0;h=top_h
    for k in range(legs):
        px,pz=px+(fx*ca+cx*sa*side)*L,pz+(fz*ca+cz*sa*side)*L;h+=rise
        nodes.append((px,pz,h))
        if k<legs-1:
            px,pz=px+fx*2.5,pz+fz*2.5;nodes.append((px,pz,h))   # the turn's landing
        side=-side
    if math.hypot(foot_xz[0]-px,foot_xz[1]-pz)>0.5:nodes.append((foot_xz[0],foot_xz[1],h))   # level to the trail
    return nodes
# the ends at the cave mouth's floor (210.1, the finished ground before the cave) and the trail legs'
SMUGGLER_STAIRS=[('smugglers_stairs_X',(602.1,440.1),210.1,(625.0,445.0),188.2,4),
                 ('smugglers_stairs_mid',(840.0,355.0),231.6,(860.0,320.0),261.8,6),
                 ('smugglers_stairs_sh2',(900.0,288.0),281.5,(900.0,249.0),303.0,4)]
# the trail legs' finished decks at the stairs' ends (their profiles are smoothed: up to 1.3 m off the
# plan, a step no one climbs)
_deck={}
for _r in roads:
    if _r['id'].startswith('smugglers_trail'):
        _g=_r['geometry_points'];_deck[(round(_g[0][0]),round(_g[0][1]))]=_g[0][2];_deck[(round(_g[-1][0]),round(_g[-1][1]))]=_g[-1][2]
for _sid,_top,_th,_foot,_fh,_n in SMUGGLER_STAIRS:
    _th=_deck.get((round(_top[0]),round(_top[1])),_th);_fh=_deck.get((round(_foot[0]),round(_foot[1])),_fh)
    _nodes=stair_zigzag(_top,_th,_foot,_fh,_n);_st=[]
    for _a,_b in zip(_nodes,_nodes[1:]):
        if abs(_b[2]-_a[2])<1e-6 and math.dist(_a[:2],_b[:2])<3.0:
            # a turn: the landing without rails (tests54: its rails stopped the hero where the flights meet
            # it at ~117 deg; tests55: a 3.6 m square pad covered the next flight's first treads)
            _st.append(_rec((_a[0]+_b[0])*.5,(_a[1]+_b[1])*.5,_a[2],math.degrees(math.atan2(_b[0]-_a[0],_b[1]-_a[1])),3.0,2.4,0))
            continue
        # the level ends of a flight (by a turn) carry no rails either - the hero comes onto them off
        # the landing at an angle (tests56: stopped by them on the mid and Sh2 stairs); treads keep theirs
        _st+=[r_[:6]+[0] if r_[4]>0.6 else r_ for r_ in stair_route([_a,_b],2.0,())]
    BOOK_STAIRS.append({'id':_sid,'steps':_st})
    for sx,sz,top,_yaw,dep,wid,_r in _st:
        reach=max(dep,wid)*.5+4.5
        i0,i1=max(0,int((sz-reach)/STEP)),min(WIDTH-1,int((sz+reach)/STEP)+1)
        j0,j1=max(0,int((sx-reach)/STEP)),min(WIDTH-1,int((sx+reach)/STEP)+1)
        win=heights[i0:i1+1,j0:j1+1];near=np.hypot(x[i0:i1+1,j0:j1+1]-sx,z[i0:i1+1,j0:j1+1]-sz)<=reach
        heights[i0:i1+1,j0:j1+1]=np.where(near,np.minimum(win,top-.12),win)
# The meltwater channel between the middle terrace and the Academy (the book: a cut channel, the
# rope bridge over it, its bed 285 under the bridge): a dry stone-lined cut, 3 m bed, banks 1:1.
MELT=[(1034,262,290.0),(1040,284,285.0),(1044,312,279.0),(1040,330,274.5)]
for (ax,az,ah),(bx,bz,bh) in zip(MELT,MELT[1:]):
    reach=12.0
    sl=(slice(max(0,int((min(az,bz)-reach)/STEP)),min(WIDTH,int((max(az,bz)+reach)/STEP)+2)),slice(max(0,int((min(ax,bx)-reach)/STEP)),min(WIDTH,int((max(ax,bx)+reach)/STEP)+2)))
    xx,zz=x[sl],z[sl];dx,dz=bx-ax,bz-az
    t=np.clip(((xx-ax)*dx+(zz-az)*dz)/(dx*dx+dz*dz),0,1)
    dist=np.hypot(xx-(ax+t*dx),zz-(az+t*dz))
    bed=ah+t*(bh-ah)
    # not into the terraces: at their edge the cut stands as a retaining wall (the book's walls)
    inpad=np.zeros(xx.shape,bool)
    for pad in BOOK_PADS:
        if pad['id'].startswith('snow'):
            pd=poly_distance(pad['poly'])[sl];inpad|=pd<=0.0
    heights[sl]=np.where((dist<=reach)&~inpad,np.minimum(heights[sl],bed+np.maximum(dist-1.5,0)*1.0),heights[sl])
# WORLD-BUILD-01C (Codex's ground survey of the 41 snow plots on 1831cfb: 18 hung or were buried, up
# to 6 m across a plot and 3.4 m at its door): a level lot under every building of the book's snow
# sheet - its walls + 3.5 m, the dry apron in front of its door included - at the ground in front of the
# door (the back cuts into the slope behind its retaining wall); on the middle terrace and the Academy
# shelf a lot takes the terrace's level. A 3 m blend outside; roads, river channels and the stair
# flights keep their ground. The plots themselves are the book's (not moved).
SNOW_LOTS=[]
_snow_plan=json.loads((ROOT/'assets/world/snow-city-v1/plan.json').read_text(encoding='utf8')) if (ROOT/'assets/world/snow-city-v1/plan.json').exists() else {'buildings':[]}
_stair_keep=np.zeros(heights.shape,bool)
for _f in BOOK_STAIRS:
    if not _f['id'].startswith('snow'):continue
    for sx,sz,_t,_y,dep,wid,_r in _f['steps']:
        reach=max(dep,wid)*.5+3.0
        i0,i1=max(0,int((sz-reach)/STEP)),min(WIDTH-1,int((sz+reach)/STEP)+1)
        j0,j1=max(0,int((sx-reach)/STEP)),min(WIDTH-1,int((sx+reach)/STEP)+1)
        _stair_keep[i0:i1+1,j0:j1+1]|=np.hypot(x[i0:i1+1,j0:j1+1]-sx,z[i0:i1+1,j0:j1+1]-sz)<=reach
def _terrace_level(px,pz):
    for pad in BOOK_PADS:
        if pad['id'] in ('snow_middle_terrace','snow_academy_shelf'):
            poly=pad['poly'];inside=False
            for (ax_,az_),(bx_,bz_) in zip(poly,poly[1:]+poly[:1]):
                if (az_>pz)!=(bz_>pz) and px<(bx_-ax_)*(pz-az_)/(bz_-az_)+ax_:inside=not inside
            if inside:return float(pad['level'])
    return None
for b in _snow_plan['buildings']:
    bx_,bz_,w_,d_=float(b['x']),float(b['z']),float(b['w']),float(b['d'])
    yr=math.radians(float(b['yaw']))
    fx,fz=-math.sin(yr),math.cos(yr)          # the door's side (the plan's yaw: the front looks at 'face')
    sxv,szv=fz,-fx                            # across the front
    # walls + 3.5 m: on the 5 m grid a lot must hold the grid nodes round the house, or their
    # triangles pull a 6 m house's corners up and down the slope
    hw,hd=w_*.5+3.5,d_*.5+3.5
    door=(bx_+fx*(d_*.5+1.25),bz_+fz*(d_*.5+1.25))
    lvl=_terrace_level(bx_,bz_)
    if lvl is None:lvl=round(float(sample_grid(*door)),2)
    # the lot: walls + 1 m, the apron 2.5 m in front
    corners=[(bx_+sxv*u*hw+fx*v,bz_+szv*u*hw+fz*v) for u,v in ((-1,-hd),(1,-hd),(1,hd),(-1,hd))]
    SNOW_LOTS.append({'code':b['code'],'level':lvl,'poly':[[round(c[0],2),round(c[1],2)] for c in corners]})
# two passes: the blends first, then every lot's own ground exactly (neighbouring lots 2 m apart would
# otherwise pull each other's edges)
_keep=road_cells|channel|_stair_keep
_dists=[poly_distance([tuple(c) for c in lot['poly']]) for lot in SNOW_LOTS]
for lot,d_lot in zip(SNOW_LOTS,_dists):
    wgt=1-smooth(d_lot/3.0)
    heights=np.where(_keep|(wgt<=0)|(d_lot<=0),heights,heights*(1-wgt)+lot['level']*wgt)
for lot,d_lot in zip(SNOW_LOTS,_dists):
    heights=np.where(_keep|(d_lot>0.0),heights,lot['level'])
# The W1 sill (Codex 14 Oct: along the straight cut the ground lay 3 m under the 220 m mirror outside
# the outflow, the water's edge hung over the slope): a stone sill along the whole chord, its crest
# 0.6 m over the mirror, 4 m wide; the outflow's 12 m channel stays open.
for lake in D['lakes']:
    cz=lake.get('cut_z')
    if cz is None:continue
    lx,lz,level=lake['center'];rx,rz=lake['radii_m']
    half_chord=rx*math.sqrt(max(0.0,1-((cz-lz)/rz)**2))
    out_x=lake['outlet'][0]
    across=np.abs(z-cz)
    along=np.abs(x-lx)<=half_chord+2.0
    clear=np.abs(x-out_x)>7.0
    crest=level+.6-np.maximum(across-2.0,0)*1.0
    sill=along&clear&(across<=6.0)
    heights=np.where(sill,np.maximum(heights,crest),heights)
    # inside the lake, north of the sill, nothing stands out of the water (the rivers' levee by the
    # outflow had lifted three points to 220.5)
    q=np.hypot((x-lx)/rx,(z-lz)/rz)
    heights=np.where((q<0.97)&(z<cz-1.0),np.minimum(heights,level-.6),heights)
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
    if 'cut_z' in lake:lq=np.where(z>lake['cut_z'],np.maximum(lq,1.0+(z-lake['cut_z'])/lrz),lq)
    meadow=(1-smooth((lq-1.7)/.6))*(1-smooth((heights-300)/30))
    rock=rock*(1-meadow[:,:,None])
colors[:,:,:3]=colors[:,:,:3]*(1-rock)+np.array([.55,.56,.54])*rock
# WORLD-EDGES-01: bare rock on every slope steeper than ~35 deg (the edge ridge, gorges, cliffs), so
# no meadow colour - and no grass - climbs a cliff.
_gz,_gx=np.gradient(heights,STEP)
steep_rock=smooth((np.degrees(np.arctan(np.hypot(_gx,_gz)))-30.0)/12.0)[:,:,None]
colors[:,:,:3]=colors[:,:,:3]*(1-steep_rock)+np.array([.55,.56,.54])*steep_rock
snow=smooth((heights-280)/110)[:,:,None]
# WORLD-BUILD-01C (the atlas: the snow city under the Academy in an endless storm; Codex 0208 native:
# its ground read green-grey): snow cover over the city and its slopes - full within 120 m of the
# city's middle, gone at 200 m; bare rock stays on the cliffs, the streets are trodden at run time.
_snow_city=(1-smooth((np.hypot(x-1000,z-330)-120)/80))[:,:,None]
snow=np.maximum(snow,_snow_city*.92*(1-steep_rock))
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

# WORLD-BUILD-01A: the book's new places (PLACES.md), kept out of the source's sites on purpose -
# a source site flattens a plaza and pulls roads; these only mark a point on the land as it is.
BOOK_PLACES=[
    {'id':'old_pine_grove','kind':'camp','point':[248,1282],'key':'WORLD_SITE_OLD_PINE_GROVE','label_ru':'Старый бор','label_en':'Old Pine Grove','facing':[1,0,0]},
    {'id':'wolf_hollow','kind':'hollow','point':[215,1500],'key':'WORLD_SITE_WOLF_HOLLOW','label_ru':'Волчий лог','label_en':'Wolf Hollow','facing':[0,0,-1]},
    {'id':'watch_rock','kind':'lookout','point':[105,1330],'key':'WORLD_SITE_WATCH_ROCK','label_ru':'Смотровая скала','label_en':'Watch Rock','facing':[1,0,0]},
    {'id':'capital_ruins','kind':'ruins','point':[1200,1212],'key':'WORLD_SITE_CAPITAL_RUINS','label_ru':'Руины столицы','label_en':'Capital Ruins','facing':[-1,0,0]},
    {'id':'salt_flats','kind':'saltworks','point':[1820,700],'key':'WORLD_SITE_SALT_FLATS','label_ru':'Солончаки','label_en':'Salt Flats','facing':[0,0,1]},
    {'id':'peat_farmstead','kind':'farmstead','point':[600,1820],'key':'WORLD_SITE_PEAT_FARMSTEAD','label_ru':'Торфяной хутор','label_en':'Peat Farmstead','facing':[0,0,-1]},
    {'id':'outskirts_farmsteads','kind':'farmsteads','point':[760,1300],'key':'WORLD_SITE_OUTSKIRTS_FARMSTEADS','label_ru':'Хутора окраин','label_en':'Outskirts Farmsteads','facing':[0,0,1]},
    # sheet wfW1: the viewing platform by ledge 2 - the visible 6 x 4 m stone platform on its terrace
    {'id':'w1_viewpoint','kind':'viewpoint','point':[354,385],'key':'WORLD_SITE_W1_VIEWPOINT','label_ru':'Смотровая у водопада','label_en':'Falls viewpoint','facing':[-1,0,0],'arrival_at':[359.5,388.5]},
]
# Where the hero arrives at a book place (Codex 13 Oct: the spawns stood in the trees or faced a
# wall): towards its nearest road, past the place's own volumes (STANDOFF by kind) - on the road
# itself when it is nearer - so the hero comes from the way and looks at the place.
STANDOFF={'viewpoint':6.0,'camp':10.0,'hollow':14.0,'lookout':13.0,'ruins':10.0,'saltworks':18.0,'farmstead':15.0,'farmsteads':10.0}
def book_arrival(b):
    if 'arrival_at' in b:return list(b['arrival_at'])   # a place on a small terrace sets its own
    px,pz=b['point'];best=None
    for r in roads:
        for q in dense(r['geometry_points'],True):
            d=math.hypot(q[0]+HALF-px,q[2]+HALF-pz)
            if best is None or d<best[0]:best=(d,q[0]+HALF,q[2]+HALF)
    d,rx,rz=best
    step=min(STANDOFF.get(b['kind'],10.0),d)
    return [round(px+(rx-px)/d*step,2),round(pz+(rz-pz)/d*step,2)]
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
        'book_pads':BOOK_PADS,
        'book_stairs':BOOK_STAIRS,
        'snow_lots':SNOW_LOTS,
        'book_places':[{**b,'arrival':book_arrival(b),'spawn':[book_arrival(b)[0]-HALF,sample(*book_arrival(b))+.12,book_arrival(b)[1]-HALF]} for b in BOOK_PLACES],
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
# FOREST-CITY-01 (D-111): the forest city's plaza and the streets from its gates to it, painted like
# the roads (assets/world/forest-city-v1/plan.json).
CITY_PLAN=ROOT/'assets/world/forest-city-v1/plan.json'
if CITY_PLAN.exists():
    cp=json.loads(CITY_PLAN.read_text(encoding='utf8'))
    pcx,pcz=cp['plaza']['center'];pr=float(cp['plaza']['radius'])
    def paint_segment(a,b,half):
        a=np.array(a,float);b=np.array(b,float);outer=half+1.0
        x0,z0=np.floor(np.minimum(a,b)-outer).astype(int);x1,z1=np.ceil(np.maximum(a,b)+outer).astype(int)
        pz,px=np.mgrid[z0:z1+1,x0:x1+1].astype(float)+.5
        ab=b-a;t=np.clip(((px-a[0])*ab[0]+(pz-a[1])*ab[1])/max(ab@ab,1e-9),0,1)
        dd=np.hypot(px-a[0]-t*ab[0],pz-a[1]-t*ab[1])
        mask[z0:z1+1,x0:x1+1]=np.maximum(mask[z0:z1+1,x0:x1+1],1-smooth((dd-half)/(outer-half)))
    paint_segment((pcx,pcz),(pcx+.01,pcz),pr)
    pal=cp['palisade']
    for g in pal['gates']:
        t=math.radians(float(g['deg']))
        paint_segment((pcx,pcz),(pal['center'][0]+(pal['radius']+3)*math.cos(t),pal['center'][1]+(pal['radius']+3)*math.sin(t)),2.2)
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
