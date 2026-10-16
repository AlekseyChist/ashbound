extends Node3D
## Codex local runtime candidate. Three existing tavern lanterns suspended from
## verified rendered ceilings; caller waits for model physics first.
## The west roof has no collider: use its actual triangles, never an invented height.
const OWNER_KEY := &"cathedral_lanterns_runtime_owner"
const LANTERN := preload("res://assets/props/tavern-v1/wooden_lantern_01.glb")
const Door := preload("res://scripts/world/village_door.gd")
const PLAN := [
	{"name":"Library", "base":Vector3(10.9,3.2,-4.0), "energy":1.15, "range":6.0},
	{"name":"WestNorth", "base":Vector3(-9.0,3.4,-4.0), "energy":1.05, "range":7.0},
	{"name":"WestSouth", "base":Vector3(-9.0,3.4,4.0), "energy":1.05, "range":7.0},
]
const WAKE := 35.0
const SLEEP := 40.0
var model:Node3D
var observer:Node3D
var holder:Node3D
var fixtures:Array[Node3D]=[]
var lights:Array[OmniLight3D]=[]
var supports:Array[Dictionary]=[]
var enabled := true
var check_left := 0.0

func configure(target:Node3D, viewer:Node3D)->bool:
	if not is_instance_valid(target) or not is_instance_valid(viewer) or get_parent()!=target or not target.is_inside_tree():
		return false
	var existing=target.get_meta(OWNER_KEY) if target.has_meta(OWNER_KEY) else null
	if existing is WeakRef and is_instance_valid(existing.get_ref()) and existing.get_ref()!=self:
		return false
	# Support validation is transactional: failure leaves any previous valid rig intact.
	var found:Array[Dictionary]=[]
	for spec in PLAN:
		var at:Vector3=spec.base
		var surface:Dictionary=_ceiling_surface(target,at+Vector3.UP*.6,Vector3(at.x,14.0,at.z))
		if surface.is_empty():return false
		var query=PhysicsRayQueryParameters3D.create(target.to_global(at+Vector3.UP*.6),target.to_global(Vector3(at.x,14.0,at.z)),1)
		query.hit_back_faces=true
		var hit:Dictionary=target.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and not target.is_ancestor_of(hit.collider):return false
		var local:Vector3=surface.position
		if local.y-at.y<.62:return false
		found.append({"name":spec.name,"ceiling":local,"mesh":surface.mesh,"physical_ceiling":str(hit.collider.get_path()) if not hit.is_empty() else "none in producer model; rendered roof triangles verified"})
	restore()
	model=target;observer=viewer;supports=found
	transform=Transform3D.IDENTITY
	model.set_meta(OWNER_KEY,weakref(self))
	process_mode=Node.PROCESS_MODE_PAUSABLE
	holder=Node3D.new();holder.name="SupportedInteriorLanterns";add_child(holder)
	for i in PLAN.size():_make_fixture(PLAN[i],supports[i].ceiling)
	check_left=0;_update_lights();set_process(true)
	return true

func _ceiling_surface(target:Node3D,from:Vector3,to:Vector3)->Dictionary:
	var closest:Dictionary={}
	var distance:=INF
	for mesh in target.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:continue
		# Exclude our own props on reconfiguration; evaluate the producer model only.
		if is_ancestor_of(mesh):continue
		var tr:Transform3D=target.global_transform.affine_inverse()*mesh.global_transform
		var faces:PackedVector3Array=mesh.mesh.get_faces()
		for i in range(0,faces.size(),3):
			var point=Geometry3D.segment_intersects_triangle(from,to,tr*faces[i],tr*faces[i+1],tr*faces[i+2])
			if point==null:continue
			var d:float=from.distance_squared_to(point)
			if d<distance:
				distance=d;closest={"position":point,"mesh":str(mesh.get_path())}
	return closest

func _make_fixture(spec:Dictionary,ceiling:Vector3)->void:
	var fixture=Node3D.new();fixture.name=spec.name;fixture.position=spec.base;holder.add_child(fixture)
	var lantern=LANTERN.instantiate() as Node3D;fixture.add_child(lantern)
	for mesh in lantern.find_children("*","GeometryInstance3D",true,false):
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The imported lantern's loop top is .5174m above its origin (existing residence rig).
	var top=.5174
	var length:float=ceiling.y-float(spec.base.y)-top+.015
	var rope=MeshInstance3D.new();rope.name="CeilingCord"
	var box=BoxMesh.new();box.size=Vector3(.018,length,.018);rope.mesh=box
	var material=StandardMaterial3D.new();material.albedo_color=Color(.22,.16,.10);material.roughness=1.0
	rope.material_override=material;rope.position=Vector3(0,top+length*.5,0)
	rope.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;fixture.add_child(rope)
	var body=StaticBody3D.new();body.name="LanternContact";body.collision_layer=1|Door.OBSTACLE_LAYER
	var shape=CollisionShape3D.new();var bounds=BoxShape3D.new();bounds.size=Vector3(.36,.54,.36);shape.shape=bounds
	body.position=Vector3(0,.25,0);body.add_child(shape);fixture.add_child(body)
	var light=OmniLight3D.new();light.name="WarmLanternLight";light.position=Vector3(0,.18,0)
	light.light_color=Color(1.0,.76,.5);light.light_energy=spec.energy;light.omni_range=spec.range
	light.shadow_enabled=true;fixture.add_child(light)
	fixtures.append(fixture);lights.append(light)

func set_enabled(value:bool)->void:
	enabled=value
	if is_instance_valid(holder):_update_lights()

func _update_lights()->void:
	if not is_instance_valid(observer) or not is_instance_valid(model):return
	for i in lights.size():
		var distance=observer.global_position.distance_to(lights[i].global_position)
		lights[i].visible=enabled and model.is_visible_in_tree() and distance<(SLEEP if lights[i].visible else WAKE)

func _process(delta:float)->void:
	if not is_instance_valid(model) or not is_instance_valid(observer):
		restore();return
	check_left-=delta
	if check_left<=0:
		check_left=.25;_update_lights()

func restore()->void:
	set_process(false)
	if is_instance_valid(holder):
		remove_child(holder);holder.queue_free()
	if is_instance_valid(model):
		var existing=model.get_meta(OWNER_KEY) if model.has_meta(OWNER_KEY) else null
		if existing is WeakRef and existing.get_ref()==self:model.remove_meta(OWNER_KEY)
	model=null;observer=null;holder=null
	fixtures.clear();lights.clear();supports.clear()

func _exit_tree()->void:restore()
