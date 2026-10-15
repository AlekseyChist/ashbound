extends SceneTree
const Adapter=preload("res://scripts/world/interior_camera_visibility.gd")
var checks:=0
var failures:=[]
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label)
func settle(n:int)->void:
 for i in n:await physics_frame
func _initialize()->void:call_deferred("run")
func run()->void:
 var floor=StaticBody3D.new();var col=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(20,.2,20);col.shape=box;col.position.y=-.1;floor.add_child(col);root.add_child(floor)
 var rig=load("res://scenes/world/player_rig.tscn").instantiate();root.add_child(rig)
 var actor=rig.player;var cam=rig.camera_rig;cam.set_mouse_capture(false);await settle(60)
 var visual=actor.get_node("Visual");var body=visual.get_node("Body");var pocket=visual.get_node("PocketPose")
 var body_original=body.material_override;var pocket_original=pocket.material_override
 var mask:int=actor.collision_mask;var input:bool=actor.input_enabled;var height:float=cam.follow_height
 var adapter=Adapter.new();rig.add_child(adapter)
 check(not adapter.configure(null,actor),"invalid camera refused")
 check(adapter.configure(cam,actor),"ready real rig configured")
 check(adapter.materials.size()==2,"two actor materials owned")
 check(body.material_override!=body_original and pocket.material_override!=pocket_original,"instance materials duplicated")
 check(adapter.configure(cam,actor) and adapter.materials.size()==2,"reconfigure no duplicate ownership")
 cam._spring_arm.spring_length=.3;await settle(90)
 check(float(body.material_override.get_shader_parameter("camera_visibility"))<.99,"near body fades")
 check(float(pocket.material_override.get_shader_parameter("camera_visibility"))<.99,"near pocket fades")
 check(visual.begin_inventory_access(),"inventory gesture starts")
 await settle(12);check(pocket.visible,"pocket stays visible during gesture")
 visual.end_inventory_access();check(body.visible and not pocket.visible,"gesture restores body")
 cam._spring_arm.spring_length=3.0;await settle(90)
 check(float(body.material_override.get_shader_parameter("camera_visibility"))>.999,"wide body fully visible")
 check(float(pocket.material_override.get_shader_parameter("camera_visibility"))>.999,"wide pocket fully visible")
 check(actor.collision_mask==mask and actor.input_enabled==input and is_equal_approx(cam.follow_height,height),"physics input and pivot unchanged")
 check(visual.get_node("BodyShadow").cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,"shadow proxy unchanged")
 adapter.restore();adapter.restore()
 check(body.material_override==body_original and pocket.material_override==pocket_original,"idempotent exact restoration")
 check(adapter.configure(cam,actor),"reactivation works")
 adapter.queue_free();await process_frame;await process_frame
 check(body.material_override==body_original and pocket.material_override==pocket_original,"exit restores original resources")
 DirAccess.make_dir_recursive_absolute("res://local/qa/interior-camera")
 var f=FileAccess.open("res://local/qa/interior-camera/result.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Real PlayerRig lifecycle contract; no fullworld/mobile/art acceptance"},"  "));f.close()
 print("INTERIOR_CAMERA_DONE checks=",checks," failures=",failures.size())
 rig.queue_free();floor.queue_free();await process_frame;await process_frame;call_deferred("quit",0 if failures.is_empty() else 1)
