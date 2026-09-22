extends "res://scripts/tools/validate_combat_feedback.gd"
## Codex QA only: unchanged game resources, reproducible presentation and real contacts.
const OUT := "res://.tools/cons-captures/"
var visual: Node
var body: AnimatedSprite3D
var rig: Node3D
var camera: Camera3D
var records: Array[Dictionary] = []
var baseline_camera: Transform3D
var base_player: Vector3
var motion := false
var default_homes: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,720))
	DisplayServer.window_set_position(Vector2i(-10000,-10000))
	get_tree().create_timer(240).timeout.connect(func(): printerr("CONS_CAPTURE_TIMEOUT"); get_tree().quit(2))
	motion = "--motion" in OS.get_cmdline_user_args()
	run.call_deferred()

func ui_visible(value: bool) -> void:
	for n in sandbox.find_children("*", "CanvasLayer", true, false): n.visible = value

func freeze_body(frame: int = 0) -> void:
	visual._process(0.0)
	body.pause()
	body.set_frame_and_progress(mini(frame, body.sprite_frames.get_frame_count(body.animation)-1), 0.0)

func shot(id: String, meta: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	# SpringArm must not silently move the inspection camera out of the fixture.
	if meta.category != "world":
		var subject: Vector3 = player.global_position + Vector3.UP
		if meta.category == "enemy": subject = (guard if meta.enemy == "guard" else wolf).global_position + Vector3.UP * .7
		check(not camera.is_position_behind(subject) and get_viewport().get_visible_rect().has_point(camera.unproject_position(subject)), "subject inside capture "+id)
	var img := get_viewport().get_texture().get_image()
	check(img != null and not img.is_empty(), "nonempty capture "+id)
	check(img.get_size()==Vector2i(1280,720), "fixed capture dimensions "+id)
	check(img.save_jpg(OUT+id+".jpg", 0.94)==OK, "write "+id)
	meta.merge({"id":id,"file":id+".jpg","width":img.get_width(),"height":img.get_height(),"camera_transform":str(camera.global_transform),"player_position":str(player.global_position),"player_animation":str(body.animation),"frame":body.frame,"view":str(visual._current_view),"backpack":sandbox.is_backpack_enabled(),"technique":sandbox.technique,"platform":"Windows / Godot Mobile renderer"})
	records.append(meta)

func clear_case() -> void:
	player.stop_input()
	player.clear_feedback_stop()
	for actor in [wolf,guard]: actor.home=default_homes[actor.kind]
	session.reset_trial()
	player.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	player.notification(NOTIFICATION_APPLICATION_RESUMED)
	player.input_enabled = true
	player.velocity = Vector3.ZERO
	events.clear()

func same_camera() -> void:
	camera.global_transform = baseline_camera
	player.global_position = base_player

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_node("/root/Localization").load_preferences("user://cons-qa-language.cfg", "ru_RU")
	sandbox = load("res://scripts/tools/combat_dodge_sandbox.tscn").instantiate()
	add_child(sandbox)
	await settle()
	session = sandbox.defense
	player = sandbox.level.get_node("Actors/Player")
	wolf=session.enemies[0]; guard=session.enemies[1]
	default_homes={wolf.kind:wolf.home,guard.kind:guard.home}
	fx=session.get_node("CombatFeedbackFX")
	visual=player.get_node("Visual"); body=visual.get_node("Body")
	rig=sandbox.level.get_node("CameraRig"); camera=get_viewport().get_camera_3d()
	session.set_physics_process(false)
	for i in 20: await get_tree().physics_frame
	player.set_physics_process(false)
	session.resolved.connect(func(result): events.append(result))
	clear_case()
	rig.snap_to_target()
	await settle()
	baseline_camera=camera.global_transform; base_player=player.global_position
	camera.reparent(self, true) # QA camera detached from SpringArm's internal physics.
	rig.set_process(false)
	rig.get_node("SpringArm3D").set_physics_process(false)
	check(player.is_on_floor(), "grounded fixture")
	if motion:
		await record_motion()
	else:
		await hero_matrix()
		await enemy_matrix()
		await contact_matrix()
		await ui_matrix()
		await surroundings()
	var file := FileAccess.open(OUT+("motion" if motion else "manifest")+".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures":records,"errors":errors,"motion":motion}, "\t")); file.close()
	if errors.is_empty():
		print("ASHBOUND_CONS_CAPTURE_OK captures=%d motion=%s"%[records.size(),motion]); get_tree().quit(0)
	else:
		printerr("CONS_CAPTURE_FAILED ",errors); get_tree().quit(1)

func hero_matrix() -> void:
	ui_visible(false)
	var seen := {}
	for tech in ["novice","trained"]:
		check(sandbox.set_technique(tech), "technique")
		for pack in [false,true]:
			check(sandbox.set_backpack_enabled(pack), "backpack")
			for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
				for action in ["idle","windup","contact","guard","hit","dodge"]:
					clear_case(); same_camera()
					player.facing_direction=direction
					match action:
						"windup","contact": player.request_attack()
						"guard": check(session.set_guard(true), "guard pose")
						"hit": player.begin_feedback_stop(.05, &"hit")
						"dodge":
							check(player.request_dodge(), "dodge starts")
							player._physics_process(.08)
					player._update_visual()
					freeze_body(1 if action=="contact" else 0)
					var view := str(visual._current_view)
					seen[view]=true
					var id := "hero-%s-%s-%s-%s"%[tech,"pack" if pack else "bare",view,action]
					await shot(id,{"category":"hero","action":action,"mode":"posed resource / fixed camera; dodge sampled at 0.08s"})
	check(seen.size()==4,"four actual views")
	check(records.size()==96,"complete 96-cell hero matrix")

func enemy_matrix() -> void:
	clear_case(); same_camera(); ui_visible(false)
	player.visible=false
	for actor in [wolf,guard]:
		var old: Vector3 = actor.global_position
		actor.global_position=base_player
		for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
			for action in ["idle","walk","windup","attack","hit"]:
				var av: Node=actor.get_node("Visual")
				av.present(action,direction,0.0,false,false)
				var view := str(av._current_view)
				await shot("enemy-%s-%s-%s"%[actor.kind,view,action],{"category":"enemy","enemy":actor.kind,"enemy_view":view,"action":action,"mode":"posed game resource / same camera and floor anchor"})
		actor.global_position=old
		actor._present_visual()
	player.visible=true

func position_contact(actor: Node) -> void:
	clear_case(); same_camera(); sandbox.set_technique("trained")
	actor.global_position=base_player+Vector3(0,0,-1.3 if actor==guard else -1.8)
	actor.home=actor.global_position # QA relocates the encounter and its home together.
	actor.facing_direction=Vector3.BACK
	player.facing_direction=Vector3.FORWARD
	actor._present_visual()
	await settle() # Flush relocated colliders before real LOS/contact queries.

func contact_matrix() -> void:
	ui_visible(false)
	for actor in [guard,wolf]:
		for kind in ["windup","cue","hit","block","perfect_block","hero_hit"]:
			await position_contact(actor)
			if kind=="hero_hit":
				player.request_attack()
				for i in 20:
					player._physics_process(1.0/60.0)
					if session.is_hitstopped(): break
				check(session.feedback_snapshot().last_feedback=="hit","actual hero contact")
			else:
				if kind=="block": session.set_guard(true)
				until_cue()
				if kind=="perfect_block": session.set_guard(true)
				if kind=="windup":
					await position_contact(actor); tick(.22)
				elif kind!="cue":
					until_contact(actor)
					check(events.size()==1 and events[0]==kind,"actual enemy result "+kind)
			player._update_visual(); freeze_body(body.frame)
			await shot("combat-%s-%s"%[actor.kind,kind],{"category":"combat","enemy":actor.kind,"action":kind,"events":events.duplicate(),"mode":"actual game contact/state","feedback":session.feedback_snapshot()})
			camera.global_position=base_player+Vector3(3.0,2.07,0.8)
			camera.look_at(base_player+Vector3(0,1.03,-.65))
			await shot("combat-%s-%s-oblique"%[actor.kind,kind],{"category":"combat","enemy":actor.kind,"action":kind,"angle":"oblique","events":events.duplicate(),"mode":"same frozen game contact; QA side inspection camera","feedback":session.feedback_snapshot()})

func ui_matrix() -> void:
	ui_visible(true)
	for lang in ["ru","en"]:
		check(get_node("/root/Localization").set_language(lang)==OK,"QA language")
		for state in ["normal","pressed","disabled","cue"]:
			await position_contact(guard)
			if state=="pressed": session.set_guard(true)
			if state=="disabled": player.request_dodge()
			if state=="cue": until_cue()
			player._update_visual(); freeze_body()
			for i in 3: await get_tree().process_frame
			await shot("ui-%s-%s"%[lang,state],{"category":"ui","language":lang,"action":state,"mode":"actual toolbar state; disabled sampled during dodge"})

func surroundings() -> void:
	clear_case(); same_camera(); ui_visible(true)
	get_node("/root/Localization").set_language("ru")
	await shot("courtyard-gameplay",{"category":"world","action":"gameplay","mode":"current game camera and HUD"})
	ui_visible(false)
	await shot("courtyard-world",{"category":"world","action":"no-hud","mode":"same camera; QA hides UI only"})
	camera.global_position=Vector3(0,12,19)
	camera.look_at(Vector3(0,0,4))
	await shot("courtyard-overview",{"category":"world","action":"overview","mode":"QA overview only; not proposed gameplay camera"})

func record_motion() -> void:
	ui_visible(true)
	var n := 0
	for actor in [guard,wolf]:
		for response in ["hit","block","perfect_block","hero_hit","dodge"]:
			await position_contact(actor)
			if response=="block": session.set_guard(true)
			var triggered := false
			for frame in 120:
				if not triggered:
					if response=="hero_hit" and frame==24:
						player.request_attack(); triggered=true
					elif response in ["perfect_block","dodge"] and session.is_block_window_open():
						if response=="perfect_block": session.set_guard(true)
						else: check(player.request_dodge(),"motion dodge")
						triggered=true
				player._physics_process(1.0/60.0)
				session.advance(1.0/60.0)
				await shot("motion-%04d"%n,{"category":"motion","enemy":actor.kind,"enemy_state":actor.state,"action":response,"step":frame,"results":events.duplicate(),"mode":"scripted inputs; real simulation at 60 Hz"})
				n+=1
			if response in ["hit","block","perfect_block"]:
				check(not events.is_empty() and events[0]==response,"motion outcome "+actor.kind+" "+response)
			elif response=="hero_hit": check(actor.hits_received>0,"motion player landed hit")
			elif response=="dodge": check("miss" in events and not "hit" in events,"motion dodge avoids contact")
	check(n==1200,"ten complete motion segments")
