extends Node
const Scene = preload("res://scenes/world/village_settlement.tscn")
var world: Node3D
var failures: Array[String] = []
var checks := 0
var output := "user://settlement-qa"
var capture := false
var measuring := false
var frame_ms: Array[float] = []

func _ready() -> void: call_deferred("run_checks")
func _process(delta: float) -> void:
	if measuring and capture: frame_ms.append(delta*1000)
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("SETTLEMENT_FAIL ",label)
func settle(seconds: float=.25) -> void: await get_tree().create_timer(seconds,false,true).timeout
func screen(label: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(label+".png"))==OK,"screenshot "+label)
func drive(goal: Vector3,seconds: float=5.0,run: bool=false) -> bool:
	var until := Time.get_ticks_msec()+int(seconds*1000)
	measuring=true
	world.player.set_run_input(run)
	while Time.get_ticks_msec()<until:
		var offset: Vector3 = goal-world.player.global_position
		offset.y=0
		if offset.length()<.22: break
		var camera: Camera3D=world.camera_rig.get_camera()
		var right:=camera.global_basis.x; right.y=0; right=right.normalized()
		var back:=camera.global_basis.z; back.y=0; back=back.normalized()
		world.player.set_move_input(Vector2(offset.normalized().dot(right),offset.normalized().dot(back)))
		await get_tree().physics_frame
	world.player.stop_input()
	measuring=false
	await settle(.08)
	var offset: Vector3 = goal-world.player.global_position;offset.y=0
	return offset.length()<.45
func interact_key() -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=KEY_E;event.keycode=KEY_E;event.pressed=true
	get_viewport().push_input(event,true)
	await get_tree().physics_frame
	event.pressed=false;get_viewport().push_input(event,true)
	await settle(.85)
func place(at: Vector3) -> void:
	world.player.stop_input();world.player.velocity=Vector3.ZERO
	world.player.global_position=at+Vector3.UP*.05
	world.camera_rig.snap_to_target()
	await settle(.35)

func run_checks() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.has("--output"): output=args[args.find("--output")+1]
	DirAccess.make_dir_recursive_absolute(output)
	capture=DisplayServer.get_name()!="headless"
	check_grid()
	world=Scene.instantiate();add_child(world)
	await settle(.5)
	check(world.buildings.size()==3,"three first yards")
	check(world.dressing.tree_positions.size()==280,"forest population")
	check(world.player.get_node("Visual/Body").sprite_frames==preload("res://assets/characters/world-graybox-v1/traveler_frames.tres"),"accepted frames")
	var positions := [Vector3(-21.5,0,1.5),Vector3(13.25,.4,-19.25),Vector3(-2.5,-.5,48)]
	for i in range(3): check(world.buildings[i].position.is_equal_approx(positions[i]),"reviewed building position "+str(i))
	var space:=world.get_world_3d().direct_space_state
	for pair in [Vector2(-12,7),Vector2(0,-5),Vector2(14,-7),Vector2(-18,27),Vector2(40,-40)]:
		var query:=PhysicsRayQueryParameters3D.create(Vector3(pair.x,25,pair.y),Vector3(pair.x,-5,pair.y),1)
		var hit:=space.intersect_ray(query)
		check(not hit.is_empty(),"ground from above "+str(pair))
		if not hit.is_empty(): check(absf(hit.position.y-world.terrain.height_at(pair.x,pair.y))<.14,"terrain sample "+str(pair))
	for tree in world.dressing.tree_positions:
		var p:=Vector2(tree.x,tree.z)
		var road: Vector2=world.terrain.road_info(p)
		check(road.x>=road.y*.5+3.39 and not world.terrain.reserved(p,2),"tree leaves routes clear")
	await check_forest_floor(space)
	for language in ["ru","en"]:
		Localization.set_language(language)
		await settle(.1)
		for control in [world.picker,world.language_button,world.interact_button]:
			check(not control.text.begins_with("VILLAGE_"),"translated "+language)
			check(world.hud.get_node("RootControl").get_global_rect().encloses(control.get_global_rect()),"safe HUD "+language)
	Localization.set_language("ru")
	await screen("start")
	for i in range(3): await door_route(i)
	world.select_building(0)
	await settle()
	# Follow the reviewed path through the first three yards, using real player motion.
	var path := [Vector2(83.1875,97.625),Vector2(83.25,102.5),Vector2(82.75,82.5),Vector2(95.25,85.24),Vector2(95.25,90),Vector2(95.25,85.24),Vector2(110.1,88.5),Vector2(111.25,88.75),Vector2(82.75,82.5),Vector2(83.25,102.5),Vector2(77.25,122.5),Vector2(80,141),Vector2(80.18,143)]
	for pair in path:
		var p: Vector2=pair-world.terrain.ORIGIN
		check(await drive(Vector3(p.x,0,p.y),8,true),"street route "+str(pair)+" actual="+str(world.player.global_position))
		check(world.player.is_on_floor(),"street grounded")
	await screen("barn-route")
	world._notification(NOTIFICATION_APPLICATION_PAUSED)
	check(not world.player.input_enabled,"background releases movement")
	world._notification(NOTIFICATION_APPLICATION_RESUMED)
	check(world.player.input_enabled,"resume enables movement")
	world.select_building(0)
	await settle()
	if capture:
		var cam:=Camera3D.new();world.add_child(cam)
		cam.position=Vector3(60,65,72);cam.look_at(Vector3(0,0,15));cam.make_current()
		world.hud.hide();await settle(.4);await screen("overview")
		cam.queue_free();world.hud.show();world.camera_rig.get_camera().make_current()
	frame_ms.sort()
	var timing: Dictionary={} if frame_ms.is_empty() else {"frames":frame_ms.size(),"p50_ms":frame_ms[frame_ms.size()/2],"p95_ms":frame_ms[int(frame_ms.size()*.95)]}
	var report: Dictionary={"version":"0.23.0","checks":checks,"failures":failures,"platform":OS.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"timings":timing}
	var file:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("SETTLEMENT_QA_COMPLETE ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func check_grid() -> void:
	var grid = preload("res://scripts/world/village_grid_mesh.gd")
	for slope in [0.0,0.4]:
		var mesh: ArrayMesh=grid.build(-2,-3,3,4,2.0,func(x: float,z: float)->float:return slope*x-.5*slope*z,func(_x: float,_z: float)->Color:return Color.WHITE)
		var arrays:=mesh.surface_get_arrays(0)
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		check(points.size()==20 and indices.size()==72,"grid handles incomplete edge cells")
		check(is_equal_approx(mesh.get_aabb().size.x,5) and is_equal_approx(mesh.get_aabb().size.z,7),"grid exact bounds")
		var valid:=true
		for i in range(points.size()):
			valid=valid and is_equal_approx(points[i].y,slope*points[i].x-.5*slope*points[i].z) and normals[i].dot(Vector3(-slope,1,.5*slope).normalized())>.9999
		for i in range(0,indices.size(),3):
			valid=valid and (points[indices[i+1]]-points[indices[i]]).cross(points[indices[i+2]]-points[indices[i]]).y<0
		check(valid,"grid heights normals and Godot clockwise faces")

func door_route(index: int) -> void:
	world.select_building(index);await settle(.3)
	var building: Node3D=world.buildings[index]
	var entry: Vector3=building.record.entry
	var door: Node3D=building.door
	var id:=str(building.record.id)
	check(world.player.is_on_floor(),id+" spawn grounded")
	await drive(building.to_global(entry+Vector3(0,0,-1)),1.3)
	var local: Vector3=building.to_local(world.player.global_position)
	check(local.z>entry.z+.2 and local.z<entry.z+.5,id+" closed door contact "+str(local))
	await interact_key()
	check(door.fraction>.99,id+" opens at contact")
	for leaf in door.leaves:
		var mesh: MeshInstance3D=leaf.mesh
		check(building.to_local(mesh.to_global(mesh.get_aabb().get_center())).z<entry.z-.3,id+" opens away inward")
	check(await drive(building.to_global(entry+Vector3(0,0,-1.8)),3),id+" walk inside")
	check(building.contains(world.player.global_position),id+" interior recognition")
	await screen(id+"-inside")
	await interact_key()
	check(door.fraction<.01,id+" close inside")
	await drive(building.to_global(entry+Vector3(0,0,1)),1)
	await interact_key()
	check(door.fraction>.99,id+" opens from inside")
	for leaf in door.leaves:
		var mesh: MeshInstance3D=leaf.mesh
		check(building.to_local(mesh.to_global(mesh.get_aabb().get_center())).z>entry.z+.3,id+" opens away outward")
	check(await drive(building.to_global(entry+Vector3(0,0,3)),3),id+" walk outside")
	check(world.player.is_on_floor(),id+" exit grounded")
	await screen(id+"-outside")

## LANDSCAPE-01: the Poly Haven forest floor. Stones on the meadow, logs, branches, roots and
## boulders between the trees, grass kept short around them; routes stay clear, big pieces are solid.
func check_forest_floor(space: PhysicsDirectSpaceState3D) -> void:
	var dressing: Node3D=world.dressing
	var counts: Dictionary=dressing.floor_counts
	check(int(counts.get("stone",0))>=30,"meadow stones "+str(counts))
	check(int(counts.get("log",0))>=20 and int(counts.get("boulder",0))>=25 and int(counts.get("branches",0))>=40,"forest floor pieces "+str(counts))
	check(int(counts.get("roots",0))>=80,"roots at a third of the trunks")
	check(int(counts.get("fern",0))>150,"ferns kept")
	check(dressing.get_node_or_null("boulder_boulder")==null,"old white boulder replaced")
	var fern_wind:=0
	for batch in dressing.foliage_batches:
		if String(batch.name).begins_with("fern_02"): fern_wind+=1
	check(fern_wind>0,"new ferns sway in the wind")
	# Every forest-floor batch instance stands on the ground and off the roads.
	var off_road:=true
	var grounded:=true
	var pieces:=0
	for placed in dressing.floor_pieces:
		var name:=String(placed[0])
		if not (name.begins_with("dead_tree_trunk") or name.begins_with("rock_moss") or name.begins_with("dry_branches")): continue
		var at: Vector3=(placed[1] as Transform3D).origin
		var p:=Vector2(at.x,at.z)
		var road: Vector2=world.terrain.road_info(p)
		pieces+=1
		if road.x<road.y*.5+.5: off_road=false
		if absf(at.y-world.terrain.height_at(p.x,p.y))>.3: grounded=false
	check(pieces>100,"forest floor batches present (%d)"%pieces)
	check(off_road,"no log, rock or branch on a road")
	check(grounded,"forest floor pieces rest on the ground")
	# Solid: the logs and boulders block the hero like the tree trunks do.
	var solids:=0
	for body in dressing.get_children():
		if body is StaticBody3D and String(body.name).begins_with("FloorSolid"): solids+=1
	check(solids>=int(counts.log)+int(counts.boulder),"logs and boulders are solid (%d)"%solids)
	for placed in dressing.floor_pieces:
		if placed[0]!="dead_tree_trunk": continue
		var centre: Vector3=dressing.to_global((placed[1] as Transform3D).origin)
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(centre+Vector3.UP*3,centre-Vector3.UP,1))
		check(not hit.is_empty() and String(hit.collider.name).begins_with("FloorSolid"),"a ray from above meets the log's collision")
		break
	# Grass: none right at a trunk, short around it, the reviewed density elsewhere.
	var grass: Node3D=world.grass
	var tree: Vector3=dressing.tree_positions[140]
	var key:=Vector2i(floori(tree.x/grass.CHUNK),floori(tree.z/grass.CHUNK))
	var at_trunk:=0
	var short:=0
	var near:=0
	for clump in grass.chunk_points(key):
		var d: float=clump.point.distance_to(Vector2(tree.x,tree.z))
		if d<.8: at_trunk+=1
		elif d<1.6:
			near+=1
			if clump.tall<.8: short+=1
	check(at_trunk==0,"no grass at the trunk")
	check(near>0 and short*2>near,"short grass around the trunk (%d of %d)"%[short,near])
	check(dressing.clearings.size()>=dressing.tree_positions.size()+int(counts.log)+int(counts.boulder),"grass clearings for trunks, logs and rocks")
