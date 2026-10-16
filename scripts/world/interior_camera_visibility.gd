extends Node
## Opt-in interior presentation; leaves camera, input, physics and shadow proxies intact.
var camera_rig:Node3D
var actor:Node3D
var materials:Array[Dictionary]=[]
func configure(rig:Node3D,target:Node3D)->bool:
 if not is_instance_valid(rig) or not is_instance_valid(target) or not rig.has_method("get_camera"):return false
 if not rig.get_camera() is Camera3D:return false
 for key in ["Visual/Body","Visual/PocketPose"]:
  var sprite=target.get_node_or_null(key) as AnimatedSprite3D
  if sprite==null or not sprite.material_override is ShaderMaterial:return false
 restore()
 camera_rig=rig;actor=target
 set_process(true)
 for key in ["Visual/Body","Visual/PocketPose"]:
  var sprite=actor.get_node_or_null(key) as AnimatedSprite3D
  if sprite==null or not sprite.material_override is ShaderMaterial:continue
  var original:ShaderMaterial=sprite.material_override
  var own=original.duplicate() as ShaderMaterial
  own.shader=load("res://assets/shaders/interior_character_depth.gdshader")
  own.set_shader_parameter("camera_visibility",1.0)
  sprite.material_override=own
  materials.append({"node":sprite,"original":original,"own":own,"visibility":1.0})
 return true
func _process(delta:float)->void:
 if not is_instance_valid(camera_rig) or not is_instance_valid(actor):return
 var camera:Camera3D=camera_rig.get_camera()
 var length=camera.global_position.distance_to(camera_rig.global_position)
 var screen_fraction=1.0
 var head=actor.global_position+Vector3.UP*1.7
 if not camera.is_position_behind(actor.global_position) and not camera.is_position_behind(head):
  screen_fraction=absf(camera.unproject_position(head).y-camera.unproject_position(actor.global_position).y)/maxf(camera.get_viewport().get_visible_rect().size.y,1.0)
 var proximity=clampf((1.4-length)/1.1,0,1)
 var occupancy=clampf((screen_fraction-.6)/.4,0,1)
 var visibility=1.0-maxf(proximity,occupancy)
 for item in materials:
  item.visibility=lerpf(item.visibility,visibility,clampf(delta*15,0,1))
  # Finish endpoint fades exactly: an asymptotic residual leaves isolated sprite pixels.
  if visibility<=0.001 and item.visibility<0.01:item.visibility=0.0
  elif visibility>=0.999 and item.visibility>0.99:item.visibility=1.0
  item.own.set_shader_parameter("camera_visibility",item.visibility)
func restore()->void:
 set_process(false)
 for item in materials:
  if is_instance_valid(item.node):item.node.material_override=item.original
 materials.clear();camera_rig=null;actor=null

func _exit_tree()->void:restore()
