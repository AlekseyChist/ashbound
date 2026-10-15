extends SceneTree
const Lanterns=preload("res://scripts/world/snow_city_lanterns.gd")
# Keep the whole authored street clear, including rotated .2m post half-diagonal.
# Check shipped positions: moving a post off a stoop must not block another route.
const STREET_EDGE_CLEARANCE:=0.15
func street_edge_clearance(at:Vector2,lines:Array)->float:
 var nearest:=INF
 for line in lines:
  if str(line.kind)!="street":continue
  for i in range(line.pts.size()-1):
   var a:=Vector2(float(line.pts[i][0]),float(line.pts[i][1]))
   var b:=Vector2(float(line.pts[i+1][0]),float(line.pts[i+1][1]))
   nearest=minf(nearest,at.distance_to(Geometry2D.get_closest_point_to_segment(at,a,b))-float(line.width)*0.5)
 return nearest
func _initialize()->void:
 var path={"test":[Vector2(0,0),Vector2(0,2),Vector2(0,5)]}
 var failures=[]
 var cases=[Vector2(1000,1001),Vector2(1000,1003),Vector2(1001.099,1003),Vector2(1001.101,1003),Vector2(1000,1005.5),Vector2(1000,1006.2),Vector2(1003,1003)]
 var expected=[true,true,true,false,true,false,false]
 for i in cases.size():
  if not Lanterns.stoop_conflicts(cases[i],path).is_empty()!=expected[i]:failures.append(i)
 if not Lanterns.stoop_conflicts(Vector2(1000,1000),{}).is_empty():failures.append(7)
 # A centre-only test would accept .7m on a 3m street; its edge must remain free.
 var street=[{"kind":"street","width":3.0,"pts":[[0,0],[0,10]]}]
 if street_edge_clearance(Vector2(.7,5),street)>=STREET_EDGE_CLEARANCE:failures.append("post inside street")
 if street_edge_clearance(Vector2(1.64,5),street)>=STREET_EDGE_CLEARANCE:failures.append("post clips street edge")
 if street_edge_clearance(Vector2(1.66,5),street)<STREET_EDGE_CLEARANCE:failures.append("post outside street")
 var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/snow-city-v1/plan.json"))
 var lamps:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Lanterns.PLAN))
 if plan.get("lines",[]).is_empty() or lamps.get("posts",[]).is_empty():failures.append("missing authored plan")
 for post in lamps.get("posts",[]):
  var at:=Vector2(float(post.at[0]),float(post.at[1]))
  var clearance:=street_edge_clearance(at,plan.get("lines",[]))
  if not is_finite(clearance) or clearance<STREET_EDGE_CLEARANCE:failures.append({"post":post.label,"street_edge_clearance":clearance})
 print("STOOP_GUARD_TEST_DONE guard_checks=11 street_posts=",lamps.get("posts",[]).size()," failures=",failures)
 quit(0 if failures.is_empty() else 1)
