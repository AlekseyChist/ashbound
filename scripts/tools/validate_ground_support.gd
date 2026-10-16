extends SceneTree
## PAVILION-SUPPORT-02: a rounded edge may yield one steep contact, but a
## walkable floor already reachable by the real capsule must not leave it falling.
## Uses the actual player rig. Flat/step/jump/cliff/headroom controls remain real collisions.
var rig:Node3D
var player:CharacterBody3D
var checks=0
var failures:Array[String]=[]
var samples=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 checks+=1
 print("GROUND_", "PASS " if ok else "FAIL ",label)
 if not ok:failures.append(label)
func tick()->void:
 await physics_frame
 player._physics_process(1./60.)
func settle(count:int)->void:
 for i in count:await tick()
func block(at:Vector3,size:Vector3)->void:
 var body=StaticBody3D.new();body.position=at
 var collision=CollisionShape3D.new();var box=BoxShape3D.new();box.size=size;collision.shape=box;body.add_child(collision);root.add_child(body)
func place(at:Vector3)->void:
 player.clear_movement_input();player.position=at;player.velocity=Vector3.ZERO
 await settle(25)
func ramp(degrees:float,z:float)->void:
 var angle=deg_to_rad(degrees)
 var body=StaticBody3D.new();body.rotation.z=angle
 body.position=Vector3(2.*cos(angle)+.1*sin(angle),2.*sin(angle)-.1*cos(angle),z)
 var collision=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(4,.2,1.4);collision.shape=box;body.add_child(collision);root.add_child(body)
func walk(target:Vector3,label:String,max_ticks:int=220)->Dictionary:
 var rows=[];var reached=false;var top=player.position.y
 for i in max_ticks:
  var offset=target-player.position;offset.y=0
  if offset.length()<.1:reached=true;break
  var direction=offset.normalized();player.set_move_input(Vector2(direction.x,direction.z))
  var before=player.position;await tick()
  var collision=KinematicCollision3D.new()
  var hit=player.test_move(player.global_transform,Vector3.DOWN*player.floor_snap_length,collision)
  var reachable_floor=hit and collision.get_normal().y>=cos(player.floor_max_angle)
  top=maxf(top,player.position.y)
  rows.append({"position":player.position,"delta":player.position-before,"grounded":player.is_on_floor(),"walkableSnap":reachable_floor,"jump":player._in_jump})
 player.clear_movement_input()
 var available_air=0;var air=0;var jumped=false
 for row in rows:
  if not row.grounded:
   air+=1
   if row.walkableSnap and not row.jump:available_air+=1
  jumped=jumped or row.jump
 var result={"label":label,"reached":reached,"grounded":player.is_on_floor(),"top":top,"air":air,"availableAir":available_air,"jumped":jumped,"rows":rows}
 samples.append(result)
 return result
func run()->void:
 block(Vector3(0,-.5,0),Vector3(30,1,54))
 var heights=[0.,.06,.15,.3,.38,.5]
 for i in heights.size():
  var h:float=heights[i]
  if h>0:block(Vector3(1,h*.5,float(i)*3.),Vector3(2,h,1.4))
 # Two additional lanes expose partial headroom and an actually too-low ceiling.
 for lane in [[18.,1.95],[21.,1.78]]:
  block(Vector3(1,.075,lane[0]),Vector3(2,.15,1.4))
  block(Vector3(1,lane[1]+.05,lane[0]),Vector3(5,.1,1.4))
 rig=load("res://scenes/world/player_rig.tscn").instantiate();root.add_child(rig);player=rig.player
 rig.camera_rig._yaw=0.;rig.camera_rig._apply_rotation();rig.camera_rig.set_mouse_capture(false)
 player.set_physics_process(false)
 await settle(10)
 var angle=player.floor_max_angle;var snap=player.floor_snap_length
 for i in heights.size():
  var h:float=heights[i];var z=float(i)*3.
  await place(Vector3(-2,.05,z))
  var up=await walk(Vector3(1.2,0,z),"up-"+str(h))
  if h<=player.STEP_MAX:
   check(up.reached and absf(up.top-h)<.08,"up %.2f retains legal height"%h)
   check(not up.jumped,"up %.2f does not trigger jump"%h)
   var down=await walk(Vector3(4,0,z),"down-"+str(h))
   check(down.reached and down.grounded and absf(player.position.y)<.02,"down %.2f reaches base"%h)
   check(down.availableAir==0,"down %.2f has no airborne tick with a walkable capsule snap"%h)
   # The first rejected rounded-edge normal can be genuinely steeper than the floor.
   # Preserve its actual flag; do not manufacture a grounded bit or widen floor angle.
   check(down.air<=1,"down %.2f recovers after the single edge-contact tick"%h)
   var speed_ok=true
   for row in down.rows:
    var motion:Vector3=row.delta
    speed_ok=speed_ok and Vector2(motion.x,motion.z).length()<=player.move_speed/60.+.01
   check(speed_ok,"down %.2f adds no horizontal correction/boost"%h)
  else:
   check(not up.reached and up.top<.1,"%.2f remains a wall"%h)
 # Angled travel across the same real 15cm ledge.
 await place(Vector3(-2,.05,5.8))
 var angled_up=await walk(Vector3(1.2,0,6.2),"angled-up")
 var angled_down=await walk(Vector3(4,0,5.8),"angled-down")
 check(angled_up.reached and angled_down.reached and angled_down.availableAir==0,"diagonal ledge descent has reachable support")
 for lane in [[18.,true],[21.,false]]:
  await place(Vector3(-2,.05,lane[0]))
  var head=await walk(Vector3(1.2,0,lane[0]),"headroom-"+str(lane[0]))
  check(head.reached==lane[1],"headroom lane %.0f respects actual clearance"%lane[0])
 for slope in [[35.,-16.],[50.,-20.]]:
  ramp(slope[0],slope[1]);await place(Vector3(-2,.05,slope[1]))
  var climbed=await walk(Vector3(2,0,slope[1]),"slope-"+str(slope[0]))
  if slope[0]<45.:
   check(climbed.reached and climbed.grounded and player.position.y>1.,"35 degree slope stays walkable")
  else:
   check(not climbed.reached,"50 degree slope stays too steep")
 # Real deliberate jump must keep its airtime and must not be snapped back down.
 await place(Vector3(-4,.05,-5))
 player.request_jump();var peak=0.;var flight=0
 for i in 90:
  await tick();peak=maxf(peak,player.position.y)
  if not player.is_on_floor():flight+=1
 check(peak>=.4 and peak<=.55 and flight>=20 and player.is_on_floor(),"deliberate jump keeps height/flight and lands")
 # No floor under this remote platform: a missed snap must not become a sticky fall.
 block(Vector3(41,.5,0),Vector3(2,1,4));await place(Vector3(41,1.05,0))
 var cliff=await walk(Vector3(44,0,0),"real-cliff")
 check(cliff.reached and not cliff.grounded and player.position.y<.8,"large drop stays a real fall")
 check(is_equal_approx(angle,player.floor_max_angle) and is_equal_approx(snap,player.floor_snap_length),"floor angle and snap distance unchanged")
 var args=OS.get_cmdline_user_args()
 for arg in args:
  if arg.begins_with("--out="):
   var f=FileAccess.open(arg.substr(6),FileAccess.WRITE)
   f.store_string(JSON.stringify({"completed":true,"checks":checks,"failures":failures,"samples":samples,"jumpPeak":peak,"jumpFlight":flight},"  "))
 print("GROUND_SUPPORT checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty()else 1)
