extends SceneTree
## Run in a clean minimal fixture with only these tracked scenes/dependencies copied in.
## No local report is an input. --native additionally creates Godot viewport PNGs.
const SPECS := {
	"d_home_6x5": Vector2(6, 5), "d_home_7x6": Vector2(7, 6),
	"d_home_6x6": Vector2(6, 6), "d_poor_home_6x5": Vector2(6, 5)
}
const BASE := "res://scenes/buildings/world-architecture-v1/"
const QA := "res://local/qa/desert-residential-family/"
var failures: Array[String] = []
var reports: Array[Dictionary] = []
var stage: Node3D
var actor: CharacterBody3D
var camera: Camera3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var native := false
var legs := 0

func _initialize() -> void:
	native = "--native" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func ticks(count: int) -> void:
	for i in count:
		await physics_frame

func belongs(node: Node, model: Node) -> bool:
	return node == model or model.is_ancestor_of(node)

func ray(a: Vector3, b: Vector3, mask: int = 1) -> Dictionary:
	return stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, mask))

func bounds(mesh: MeshInstance3D, model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for surface in mesh.mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var p := model.to_local(mesh.to_global(vertex))
			if first:
				result = AABB(p, Vector3.ZERO)
				first = false
			else:
				result = result.expand(p)
	return result

func walk(target: Vector2, label: String, model: Node3D, inside: bool = true) -> void:
	for tick in 800:
		await physics_frame
		var delta := Vector3(target.x - actor.position.x, 0, target.y - actor.position.z)
		if delta.length() < .065:
			legs += 1
			check(actor.is_on_floor(), label + ": no floor contact")
			check(absf(actor.position.y - .875) < .035, label + ": incorrect walking floor")
			if inside:
				var hit := ray(actor.position, actor.position - Vector3.UP * 1.2)
				check(not hit.is_empty() and belongs(hit.collider, model), label + ": fixture substituted for model floor")
			return
		actor.velocity = delta.normalized() * 2
		actor.velocity.y = -2
		actor.move_and_slide()
	check(false, label + ": blocked at " + str(actor.position))

func snapshot(file: String, at: Vector3, target: Vector3, night: bool = false) -> void:
	camera.position = at
	camera.look_at(target)
	sun.light_energy = .04 if night else 1.2
	environment.environment.ambient_light_energy = .04 if night else .55
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(QA + file + ".png") == OK, "PNG capture failed " + file)

func inspect_model(identity: String, size: Vector2) -> void:
	var before := failures.size()
	var packed := load(BASE + identity + ".tscn") as PackedScene
	check(packed != null, identity + ": missing canonical scene")
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	stage.add_child(model)
	await ticks(3)
	check(model.scale.is_equal_approx(Vector3.ONE), identity + ": model stretched")
	var contract: Dictionary = model.find_child("ResidenceContract", true, false).get_meta("extras", {})
	check(Vector2(contract.wall_footprint[0], contract.wall_footprint[1]) == size, identity + ": footprint contract mismatch")
	var total := AABB()
	var first := true
	var triangles := 0
	var bed_found := false
	var mat_found := false
	var poor := identity.begins_with("d_poor")
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if model.lamp_root.is_ancestor_of(mesh):
			continue
		var b := bounds(mesh, model)
		total = b if first else total.merge(b)
		first = false
		if mesh.name.contains("bed_wooden_box") or mesh.name.contains("bed wooden box"):
			bed_found = true
			check(b.size.z >= 2.09 and b.size.x >= 1.1, identity + ": adult box bed too short/narrow")
		if mesh.name.contains("sleeping_reed_mat") or mesh.name.contains("sleeping reed mat"):
			mat_found = true
			check(b.size.z >= 2.0 and b.size.x >= 1.0 and b.position.y >= -.005 and b.end.y <= .11, identity + ": sleeping mat size or floor support")
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3 if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			check(material != null, identity + ": missing material")
			if material != null and (material.resource_name.contains("adobe") or material.resource_name.contains("plaster")):
				check(material.albedo_texture != null and material.vertex_color_use_as_albedo, identity + ": wall texture/weather absent")
				check(material.albedo_color.r > material.albedo_color.b + .1, identity + ": ochre lost")
	check(mat_found and not bed_found if poor else bed_found, identity + ": required sleeping mat/wooden bed missing")
	# Accepted reliefs may extend 0.30m; retain exact structural wall rays below.
	check(total.position.x >= -size.x/2-.305 and total.end.x <= size.x/2+.305 and total.position.z >= -size.y/2-.305 and total.end.z <= size.y/2+.305, identity+": exterior exceeds accepted 0.30m relief envelope "+str(total))
	var top := 4.445 if poor else 3.70
	check(absf(total.position.y+.24)<.02 and absf(total.end.y-top)<.025, identity+": vertical bounds "+str(total))
	check(model.interior_meshes.size() >= 3, identity + ": interior groups absent")
	var colliders := model.find_children("*", "CollisionShape3D", true, false).size()
	check(not model.set_interior_visible(false, true), identity+": occupied interior hidden")
	check(model.set_interior_visible(false), identity+": closed interior cannot sleep")
	for mesh in model.interior_meshes:
		check(not mesh.visible, identity+": furniture stayed visible during sleep")
	check(not model.interior_light.visible, identity+": hidden interior lamp remained on")
	check(colliders==model.find_children("*", "CollisionShape3D", true, false).size(), identity+": sleep removed physics")
	check(model.set_interior_visible(true), identity+": interior restore failed")
	model.set_interior_lights_enabled(false)
	check(not model.interior_light.visible, identity+": light override ignored")
	model.set_interior_lights_enabled(true)
	camera.position=Vector3(0,3,60)
	model._process(.6)
	check(not model.interior_light.visible, identity+": distant light did not sleep")
	camera.position=Vector3(0,2,0)
	model._process(.6)
	check(model.interior_light.visible, identity+": nearby light did not wake")
	var roof := ray(Vector3(0,5,0),Vector3(0,2,0))
	check(not roof.is_empty() and belongs(roof.collider, model) and absf(roof.position.y-3.10)<.025, identity+": physical flat roof absent")
	var floor_hit := ray(Vector3(0,.4,0),Vector3(0,-.5,0))
	check(not floor_hit.is_empty() and belongs(floor_hit.collider, model) and absf(floor_hit.position.y)<.01, identity+": real model floor absent")
	for side in [-1,1]:
		var hit := ray(Vector3(side*(size.x/2+1),1.1,0),Vector3(0,1.1,0))
		check(not hit.is_empty() and belongs(hit.collider,model) and absf(absf(hit.position.x)-size.x/2)<.025, identity+": side wall collision wrong")
	var rear := ray(Vector3(1,1,size.y/2+1),Vector3(1,1,0))
	check(not rear.is_empty() and belongs(rear.collider,model),identity+": rear wall hole")
	var lamp := ray(Vector3(.35,3,-.1),Vector3(.35,1.8,-.1))
	check(not lamp.is_empty() and lamp.collider.name=="LanternContact",identity+": lantern contact absent")
	var anchor := model.find_child("LampAnchor",true,false) as Node3D
	var ceiling := model.find_child("LampCeiling",true,false) as Node3D
	check(anchor.position.y>=2.0 and ceiling.position.y>anchor.position.y+.5174,identity+": lamp headroom/support invalid")
	# Capsule rests on the actual roof; fixture ground cannot supply this elevation.
	actor.position=Vector3(0,4.6,0)
	for i in 80:
		await physics_frame
		actor.velocity=Vector3(0,-2,0)
		actor.move_and_slide()
	check(actor.is_on_floor() and absf(actor.position.y-3.975)<.04,identity+": capsule did not contact actual roof")
	actor.position=Vector3(-.3,.9,-.5)
	await ticks(2)
	for i in 70:
		await physics_frame
		actor.velocity=Vector3(0,2,0)
		actor.move_and_slide()
	check(absf(actor.position.y-1.945)<.04 and actor.is_on_ceiling(),identity+": capsule did not contact ceiling underside at2.82m: "+str(actor.position))
	actor.position=Vector3(0,.9,size.y/2+1.3)
	await ticks(2)
	for i in 90:
		await physics_frame
		actor.velocity=Vector3(0,-2,-2)
		actor.move_and_slide()
	check(actor.position.z>size.y/2-.45,identity+": closed door pass-through")
	actor.position=Vector3(0,.9,size.y/2+1.3)
	var door = model.door
	check(door.leaves.size()==7,identity+": duplicate/missing door physics")
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer=8
	obstacle.position=Vector3(.2,1.1,size.y/2-1.2)
	var obstacle_shape := CollisionShape3D.new()
	var obstacle_box := BoxShape3D.new()
	obstacle_box.size=Vector3(.32,2,.32)
	obstacle_shape.shape=obstacle_box
	obstacle.add_child(obstacle_shape)
	stage.add_child(obstacle)
	await ticks(2)
	check(model.set_interior_visible(false),identity+": pre-open sleep failed")
	check(door.try_toggle(actor),identity+": exterior toggle failed")
	check(not model.set_interior_visible(false),identity+": moving leaf allowed sleeping")
	await ticks(90)
	check(door.blocked and door.fraction<1,identity+": leaf swept through obstacle")
	obstacle.queue_free()
	await ticks(90)
	check(is_equal_approx(door.fraction,1),identity+": exterior leaf jammed")
	check(model.interior_visible,identity+": opening did not wake contents")
	check(not model.set_interior_visible(false),identity+": open leaf allowed sleep")
	var start_legs := legs
	var route := [Vector2(0,size.y/2-.9),Vector2(0,.5),Vector2(-.6,-.1),
		Vector2(-.6,-.7),Vector2(0,-.7),Vector2(.65,-.7),Vector2(.65,.4),
		Vector2(.65,size.y/2-1.6),Vector2(0,size.y/2-.8),Vector2(0,0),
		Vector2(-.6,0),Vector2(0,-.1),Vector2(.35,-.1),Vector2(0,size.y/2-2.3)]
	for i in route.size():
		await walk(route[i],identity+": leg"+str(i+1),model)
	check(door.try_toggle(actor),identity+": close from inside failed")
	await ticks(90)
	check(is_zero_approx(door.fraction),identity+": interior close jammed")
	# A real actor blocks an inward swing; reversal preserves the swing side.
	actor.position=Vector3(.2,.875,size.y/2-1.2)
	await ticks(2)
	check(not door._arc_clear(0,1),identity+": occupied swing did not guard actor")
	actor.position=Vector3(0,.875,size.y/2-2.3)
	await ticks(2)
	check(door.try_toggle(actor),identity+": inside opening failed")
	await ticks(90)
	check(is_equal_approx(door.fraction,1),identity+": interior opening jammed")
	await walk(Vector2(0,size.y/2+1.3),identity+": leg15 outside return",model,false)
	check(legs-start_legs==15,identity+": did not complete15physical legs")
	if native:
		actor.position=Vector3(0,20,0)
		await snapshot(identity+"-front",Vector3(8,6,10),Vector3(0,1.4,0))
		await snapshot(identity+"-back",Vector3(-8,6,-10),Vector3(0,1.4,0))
		await snapshot(identity+"-east",Vector3(10,4,0),Vector3(0,1.4,0))
		await snapshot(identity+"-west",Vector3(-10,4,0),Vector3(0,1.4,0))
		await snapshot(identity+"-south",Vector3(0,4,10),Vector3(0,1.4,0))
		await snapshot(identity+"-north",Vector3(0,4,-10),Vector3(0,1.4,0))
		await snapshot(identity+"-interior",Vector3(.1,1.65,size.y/2-.65),Vector3(-.9,.9,-size.y/2+.7))
		await snapshot(identity+"-interior-east",Vector3(-.55,1.65,.55),Vector3(size.x/2-.9,.9,-.6))
		await snapshot(identity+"-interior-entry",Vector3(.2,1.65,-size.y/2+.65),Vector3(-.6,.9,size.y/2-.6))
		await snapshot(identity+"-night",Vector3(.1,1.65,size.y/2-.65),Vector3(-.9,.9,-size.y/2+.7),true)
	var glb := "res://assets/buildings/world-architecture-v1/"+identity+".glb"
	var file := FileAccess.open(glb,FileAccess.READ)
	reports.append({"id":identity,"bounds_position":str(total.position),"bounds_size":str(total.size),
		"triangles":triangles,"bytes":file.get_length(),"sha256":FileAccess.get_sha256(glb),
		"physical_legs":legs-start_legs,"collision_shapes":colliders,"failures":failures.slice(before)})
	model.queue_free()
	await ticks(3)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(QA)
	stage=Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	ground.collision_layer=16
	var col := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size=Vector3(50,.1,50)
	col.shape=ground_box
	col.position.y=-.05
	ground.add_child(col)
	stage.add_child(ground)
	if native:
		var mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size=Vector2(50,50)
		mesh.mesh=plane
		var mat := StandardMaterial3D.new()
		mat.albedo_color=Color(.48,.40,.29)
		mesh.material_override=mat
		mesh.position.y=-.01
		stage.add_child(mesh)
	actor=CharacterBody3D.new()
	actor.collision_layer=2
	actor.collision_mask=1|16
	var capsule := CapsuleShape3D.new()
	capsule.radius=.3
	capsule.height=1.75
	var actor_shape := CollisionShape3D.new()
	actor_shape.shape=capsule
	actor.add_child(actor_shape)
	stage.add_child(actor)
	camera=Camera3D.new()
	camera.fov=55
	stage.add_child(camera)
	camera.current=true
	sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-45,-30,0)
	sun.shadow_enabled=true
	stage.add_child(sun)
	environment=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.32,.38,.45)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(.70,.73,.78)
	environment.environment.ambient_light_energy=.55
	stage.add_child(environment)
	for identity in SPECS:
		await inspect_model(identity,SPECS[identity])
	if native:
		var packed := load(BASE+"d_courtyard_house.tscn") as PackedScene
		check(packed!=null,"D-H comparison scene missing")
		if packed!=null:
			var reference := packed.instantiate() as Node3D
			stage.add_child(reference)
			await ticks(3)
			await snapshot("accepted-D-H-front",Vector3(8,6,10),Vector3(0,1.4,0))
			await snapshot("accepted-D-H-back",Vector3(-8,6,-10),Vector3(0,1.4,0))
	var report := {"failures":failures,"models":reports,"capsule_height":1.75,"capsule_radius":.3,
		"fixture_ground_layer":16,"model_floor_mask":1,"physical_legs":legs,
		"scope":"isolated imported canonical models; no world placement or phone acceptance"}
	var file := FileAccess.open(QA+"metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("DESERT_RESIDENTIAL_FAMILY_RESULT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
