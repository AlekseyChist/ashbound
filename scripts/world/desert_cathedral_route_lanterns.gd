extends Node3D
## Codex: supported fixtures for the actual cathedral approach and east aisle.
## Reuses the accepted forest-city timber post/arm and existing tavern lantern.
const LANTERN = preload("res://assets/props/tavern-v1/wooden_lantern_01.glb")
const OWNER_KEY := &"cathedral_route_lanterns_owner"
const PLAN := [
	{"name":"PortalWest", "at":Vector3(-4.1,0,9.5), "yaw":0.0, "outside":true},
	{"name":"PortalEast", "at":Vector3(4.1,0,9.5), "yaw":0.0, "outside":true},
	{"name":"NaveEntry", "at":Vector3(4.1,0,6.5), "yaw":-PI/2, "outside":false},
	{"name":"EastAisle", "at":Vector3(7.0,0,2.5), "yaw":PI/2, "outside":false},
]
var model:Node3D
var observer:Node3D
var atmosphere:Node
var holder:Node3D
var posts:Array[Node3D]=[]
var lights:Array[OmniLight3D]=[]
var supports:Array[Dictionary]=[]
var enabled:=true
var check_left:=0.0

func configure(target:Node3D,viewer:Node3D,weather:Node)->bool:
	if not is_instance_valid(target) or not is_instance_valid(viewer) or get_parent()!=target or not target.is_inside_tree():return false
	var old=target.get_meta(OWNER_KEY) if target.has_meta(OWNER_KEY) else null
	if old is WeakRef and is_instance_valid(old.get_ref()) and old.get_ref()!=self:return false
	var exclude:Array[RID]=[]
	if viewer is CollisionObject3D:exclude.append(viewer.get_rid())
	for body in find_children("*","CollisionObject3D",true,false):exclude.append(body.get_rid())
	var found:Array[Dictionary]=[]
	for spec in PLAN:
		var samples:Array[Vector3]=[]
		var support_name:=""
		for offset in [Vector2.ZERO,Vector2(-.1,-.1),Vector2(.1,-.1),Vector2(.1,.1),Vector2(-.1,.1)]:
			var at:Vector3=spec.at+Vector3(offset.x,0,offset.y)
			var ray=PhysicsRayQueryParameters3D.create(target.to_global(at+Vector3.UP*.5),target.to_global(at-Vector3.UP*.4),1,exclude)
			var hit=target.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty() or hit.normal.dot(Vector3.UP)<.97:return false
			var p:Vector3=target.to_local(hit.position)
			if absf(p.y-spec.at.y)>.12:return false
			samples.append(p);support_name=str(hit.collider.get_path())
		var base:Vector3=spec.at; base.y=samples[0].y
		for point in samples:
			if absf(point.y-base.y)>.035:return false
		var basis:=Basis(Vector3.UP,float(spec.yaw))
		# Require room for the real post, arm and lantern, not only an arbitrary light.
		for shape_spec in [[Vector3(0,1.46,0),Vector3(.22,2.88,.22)],[Vector3(0,2.8,.35),Vector3(.14,.14,.8)],[Vector3(0,2.43,.65),Vector3(.38,.56,.38)]]:
			var q:=PhysicsShapeQueryParameters3D.new();var box:=BoxShape3D.new();box.size=shape_spec[1]
			q.shape=box;q.transform=target.global_transform*Transform3D(basis,base)*Transform3D(Basis.IDENTITY,shape_spec[0]);q.collision_mask=1;q.exclude=exclude
			if not target.get_world_3d().direct_space_state.intersect_shape(q,1).is_empty():return false
		found.append({"name":spec.name,"base":base,"samples":samples,"support":support_name})
	restore();model=target;observer=viewer;atmosphere=weather;supports=found;transform=Transform3D.IDENTITY
	model.set_meta(OWNER_KEY,weakref(self));process_mode=Node.PROCESS_MODE_PAUSABLE
	holder=Node3D.new();holder.name="SupportedRouteLanterns";add_child(holder)
	for i in PLAN.size():_make_post(PLAN[i],found[i].base)
	check_left=0;_update();set_process(true);return true

func _box(parent:Node3D,label:String,at:Vector3,size:Vector3,material:Material)->void:
	var mesh:=MeshInstance3D.new();mesh.name=label;var box:=BoxMesh.new();box.size=size;mesh.mesh=box;mesh.material_override=material;mesh.position=at;parent.add_child(mesh)

func _make_post(spec:Dictionary,base:Vector3)->void:
	var post:=Node3D.new();post.name=spec.name;post.position=base;post.rotation.y=spec.yaw;holder.add_child(post)
	var wood:=StandardMaterial3D.new();wood.albedo_color=Color(.25,.18,.10);wood.roughness=1.0
	_box(post,"TimberPost",Vector3(0,1.25,0),Vector3(.16,3.3,.16),wood)
	_box(post,"Arm",Vector3(0,2.8,.35),Vector3(.1,.1,.75),wood)
	# Actual imported loop top .5174m, embedded .015m into cord/arm connection.
	var base_y:=2.18;var cord_bottom:=base_y+.5174;var cord_top:=2.8
	_box(post,"Cord",Vector3(0,(cord_top+cord_bottom)*.5,.65),Vector3(.018,cord_top-cord_bottom+.015,.018),wood)
	var lantern:=LANTERN.instantiate() as Node3D;lantern.position=Vector3(0,base_y,.65);post.add_child(lantern)
	for mesh in lantern.find_children("*","GeometryInstance3D",true,false):mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body:=StaticBody3D.new();body.name="PostContact";body.collision_layer=1|8;post.add_child(body)
	for part in [[Vector3(0,1.45,0),Vector3(.2,2.9,.2)],[Vector3(0,2.8,.35),Vector3(.1,.1,.75)],[Vector3(0,base_y+.25,.65),Vector3(.36,.54,.36)]]:
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=part[1];shape.shape=box;shape.position=part[0];body.add_child(shape)
	var lamp:=OmniLight3D.new();lamp.name="RouteLight";lamp.position=Vector3(0,base_y+.18,.65)
	lamp.light_color=Color(1,.76,.5);lamp.light_energy=1.3;lamp.omni_range=8.0;lamp.shadow_enabled=true;post.add_child(lamp)
	posts.append(post);lights.append(lamp)

func set_enabled(value:bool)->void:
	enabled=value
	if is_instance_valid(holder):_update()

func _update()->void:
	if not is_instance_valid(observer) or not is_instance_valid(model):return
	var hour:=12.0
	if is_instance_valid(atmosphere):hour=float(atmosphere.get("hour"))
	for i in lights.size():
		var near:=observer.global_position.distance_to(lights[i].global_position)<(40.0 if lights[i].visible else 35.0)
		var time_ok:bool=not PLAN[i].outside or hour>=18.5 or hour<6.5
		lights[i].visible=enabled and model.is_visible_in_tree() and near and time_ok

func _process(delta:float)->void:
	if not is_instance_valid(model) or not is_instance_valid(observer):restore();return
	check_left-=delta
	if check_left<=0:check_left=.25;_update()

func restore()->void:
	set_process(false)
	if is_instance_valid(holder):remove_child(holder);holder.queue_free()
	if is_instance_valid(model):
		var old=model.get_meta(OWNER_KEY) if model.has_meta(OWNER_KEY) else null
		if old is WeakRef and old.get_ref()==self:model.remove_meta(OWNER_KEY)
	model=null;observer=null;atmosphere=null;holder=null;posts.clear();lights.clear();supports.clear()

func _exit_tree()->void:restore()
