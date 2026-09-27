extends "res://scripts/tools/validate_combat_feedback.gd"
## Independent Codex acceptance: physical displacement, contacts and real viewport input.
var toolbar: Node
var interactions := 0

func fresh() -> void:
	reset()
	player.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	player.notification(NOTIFICATION_APPLICATION_RESUMED)
	player.input_enabled = true
	player.set_physics_process(true)
	for i in 20: await get_tree().physics_frame
	player.set_physics_process(false)
	check(player.is_on_floor(), "fixture standing on floor")

func move_time(seconds: float, dt: float = 1.0/60.0, combat: bool = false) -> void:
	var left := seconds
	while left > .0000001:
		var step := minf(dt, left)
		player._physics_process(step)
		if combat: session.advance(step)
		left -= step

func button(name: String) -> Button:
	return sandbox.find_child(name, true, false) as Button

func touch(pos: Vector2, down: bool, finger: int = 13, canceled: bool = false) -> void:
	var e := InputEventScreenTouch.new()
	e.position=pos; e.pressed=down; e.index=finger; e.canceled=canceled
	get_tree().root.push_input(e, true)

func key_space(down: bool, echo: bool = false) -> void:
	var e := InputEventKey.new()
	e.physical_keycode=KEY_SPACE; e.pressed=down; e.echo=echo
	get_tree().root.push_input(e, true)

func mouse_dodge(pos: Vector2, down: bool, device: int = 0) -> void:
	var e := InputEventMouseButton.new()
	e.position=pos; e.global_position=pos; e.pressed=down; e.button_index=MOUSE_BUTTON_LEFT
	e.device=device; e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	get_tree().root.push_input(e, true)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var prefix := "user://" if OS.has_feature("android") else "res://.tools/"
	check(get_viewport().get_texture().get_image().save_png(prefix+"dodge-"+label+".png")==OK,"capture "+label)

func run() -> void:
	var loc: Node = get_node("/root/Localization")
	loc.load_preferences("user://dodge-qa-settings.cfg", "en_US")
	sandbox=load("res://scripts/tools/combat_dodge_sandbox.tscn").instantiate()
	sandbox.process_mode=Node.PROCESS_MODE_PAUSABLE; add_child(sandbox); await settle()
	session=sandbox.defense; player=sandbox.level.get_node("Actors/Player")
	wolf=session.enemies[0]; guard=session.enemies[1]; fx=session.get_node("CombatFeedbackFX")
	session.set_physics_process(false); player.set_physics_process(false)
	session.resolved.connect(func(result: String) -> void: events.append(result))
	player.interact_requested.connect(func() -> void: interactions+=1)
	toolbar=button("DodgeButton").get_parent().get_parent()
	check(guard.get_script().resource_path.ends_with("frame_guard_actor.gd"),"phase guard retained")
	check(fx.get_script().resource_path.ends_with("painted_combat_fx.gd"),"painted FX retained")
	for fps in [15,30,60,120]:
		await fresh()
		var origin: Vector3=player.global_position
		var face: Vector3=player.facing_direction
		check(player.request_dodge(), "grounded step accepted "+str(fps))
		check(player.is_dodging() and not player.request_dodge(),"one accepted request")
		move_time(.20,1.0/fps)
		var travel: Vector3=player.global_position-origin
		check(absf(Vector2(travel.x,travel.z).length()-1.35)<.015,"1.35m independent of delta "+str(fps))
		check(travel.normalized().dot(-face)>.99 and player.facing_direction.is_equal_approx(face),"backstep without turn")
		check(not player.is_dodging() and absf(travel.y)<.03,"ends grounded")
		check(not player.request_dodge(),"cooldown after movement ends")
		move_time(.41); check(player.request_dodge(),"cooldown expires while idle")
	group("physical backstep, variable delta, cooldown and fixed facing")

	for input_dir in [Vector2.RIGHT,Vector2(-1,-1),Vector2(0,1)]:
		await fresh()
		var rig: Node=sandbox.level.get_node("CameraRig")
		rig.rotate_view(Vector2(deg_to_rad(65)/rig.mouse_sensitivity,0)); await settle()
		var cam: Camera3D=get_viewport().get_camera_3d()
		var right:=cam.global_basis.x; right.y=0; right=right.normalized()
		var back:=cam.global_basis.z; back.y=0; back=back.normalized()
		var expected: Vector3=(right*input_dir.x+back*input_dir.y).normalized()
		player.set_move_input(input_dir)
		var origin: Vector3=player.global_position
		check(player.request_dodge(),"directional step")
		move_time(.2)
		var travel: Vector3=player.global_position-origin; travel.y=0
		check(travel.normalized().dot(expected)>.999 and absf(travel.length()-1.35)<.015,"camera-relative normalized direction")
	await fresh(); player.request_dodge()
	var p: Vector3=player.global_position; var cd: float=player.dodge_cooldown_remaining()
	for invalid in [0.0,-1.0,NAN,INF]: player._physics_process(invalid)
	check(player.global_position==p and player.dodge_cooldown_remaining()==cd,"invalid/zero delta no movement or timer")
	move_time(.25,.25)
	check(not player.is_dodging() and player.global_position.distance_to(p)<1.37,"long step does not overshoot")
	await fresh(); player.request_dodge(); move_time(.1995,.1995)
	check(player.is_dodging(),"does not finish 0.5ms before duration")
	move_time(.0005,.0005); check(not player.is_dodging(),"finishes at duration")
	await fresh(); player.velocity.x=4; p=player.global_position
	player._physics_process(0)
	check(player.global_position==p,"zero delta cannot move idle body")
	player.velocity=Vector3.ZERO
	group("camera-relative directions, diagonal, invalid delta and no overshoot")

	await fresh()
	var origin: Vector3=player.global_position
	var wall:=StaticBody3D.new(); wall.collision_layer=1; wall.collision_mask=0
	var shape:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=Vector3(3,3,.08)
	shape.shape=box; wall.add_child(shape); add_child(wall)
	wall.global_position=origin+Vector3(0,1,.8); await settle()
	check(player.request_dodge(),"step toward wall starts")
	move_time(.25,.25)
	check(player.global_position.z<origin.z+.55 and player.global_position.z>origin.z,"thin wall stops swept body")
	check(not player.is_dodging(),"obstruction cancels step")
	p=player.global_position; move_time(.25)
	check(player.global_position.distance_to(p)<.02,"no coasting after collision")
	wall.queue_free(); await settle()
	await fresh()
	var platform:=StaticBody3D.new(); platform.collision_layer=1; platform.collision_mask=0
	var floor_shape:=CollisionShape3D.new(); var floor_box:=BoxShape3D.new(); floor_box.size=Vector3(3,.2,.8)
	floor_shape.shape=floor_box; platform.add_child(floor_shape); add_child(platform)
	platform.global_position=Vector3(0,3,12); player.global_position=Vector3(0,3.2,12)
	player.set_physics_process(true)
	for i in 20: await get_tree().physics_frame
	player.set_physics_process(false)
	origin=player.global_position
	check(player.is_on_floor() and player.request_dodge(),"platform grounded setup")
	move_time(.2)
	check(player.global_position.y<origin.y-.01,"gravity acts when leaving platform during step")
	platform.queue_free(); await settle()
	group("thin-wall collision and no residual movement")

	for gate in ["attack","recovery","guard","hitstop","disabled","air"]:
		await fresh()
		match gate:
			"attack": player.request_attack()
			"recovery": player.request_attack(); move_time(.41)
			"guard": check(session.set_guard(true),"held guard setup")
			"hitstop": player.begin_feedback_stop(.1,&"hit")
			"disabled": player.input_enabled=false
			"air":
				player.global_position.y+=2; player.set_physics_process(true); await settle(); player.set_physics_process(false)
		check(not player.request_dodge() and not player.is_dodging(),"reject "+gate)
		player.input_enabled=true
	await fresh(); player.request_dodge()
	player.request_attack(); var old_interactions:=interactions; player.request_interaction()
	check(not player.is_attacking() and interactions==old_interactions,"dodge cannot attack/interact simultaneously")
	check(not session.set_guard(true),"cannot start guard during dodge")
	group("action conflicts, airborne and gameplay gates")

	for how in ["focus","pause","menu","technique","reset","clear","hit"]:
		await fresh(); check(player.request_dodge(),"interrupt setup "+how); move_time(.04)
		match how:
			"focus": player.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			"pause": player.notification(NOTIFICATION_APPLICATION_PAUSED)
			"menu": sandbox.level.get_node("InventoryMenu").request_open(); session.advance(0)
			"technique": sandbox.set_technique("novice")
			"reset": session.reset_trial()
			"clear": player.clear_movement_input()
			"hit": player.begin_feedback_stop(.05,&"hit")
		check(not player.is_dodging(),"immediate cancel "+how)
		p=player.global_position; move_time(.25)
		check(Vector2(player.global_position.x-p.x,player.global_position.z-p.z).length()<.02,"no latent movement "+how)
		if how=="menu": sandbox.level.get_node("InventoryMenu").close_menu(false)
		await settle()
	await fresh(); player.request_dodge(); cd=player.dodge_cooldown_remaining()
	player.begin_feedback_stop(NAN,&"hit"); check(player.is_dodging(),"invalid stop cannot cancel")
	player.begin_feedback_stop(.05,&"hit"); move_time(.025)
	check(is_equal_approx(player.dodge_cooldown_remaining(),cd),"hitstop freezes cooldown")
	group("focus, pause, menu, technique, reset and hit interruption")

	for actor in [guard,wolf]:
		await fresh(); place(actor); player.set_physics_process(true); await settle(); player.set_physics_process(false)
		until_cue(); check(player.request_dodge(),"escape cue "+actor.kind)
		move_time(.4,1.0/60,true)
		check(events==["miss"],"physical departure avoids "+actor.kind+str(events))
	await fresh(); place(guard); player.set_physics_process(true); await settle(); player.set_physics_process(false)
	until_cue(); tick(.16)
	player.facing_direction=Vector3.FORWARD # Default backstep moves TOWARD guard.
	check(player.request_dodge(),"unsafe dodge accepted")
	move_time(.08,1.0/60,true)
	check(events==["hit"] and not player.is_dodging(),"dodge has no invulnerability inside real contact")
	group("evade guard/wolf by distance; unsafe dodge still takes hit")

	for lang in ["en","ru"]:
		loc.set_language(lang); await fresh(); await settle()
		var b:=button("DodgeButton"); var rect:=b.get_global_rect()
		check(b.text==("Уклонение" if lang=="ru" else "Dodge"),"localized visible action")
		check(rect.size.x>=240 and rect.size.y>=88,"finger-sized dodge")
		check(get_viewport().get_visible_rect().encloses(rect),"button fits viewport")
		for other in ["GuardButton","AttackButton","InteractButton","RunButton"]:
			var other_button:=button(other)
			if other_button!=null: check(not rect.intersects(other_button.get_global_rect()),"no overlap "+other)
		var attack: Button=sandbox.level.get_node("HUD")._btn_attack
		check(b.get_theme_stylebox("normal")==attack.get_theme_stylebox("normal"),"shared HUD style")
		check(b.get_theme_font_size("font_size")==attack.get_theme_font_size("font_size"),"shared text size")
		await capture("ready-"+lang)
	group("EN/RU labels, touch geometry and consistent HUD style")

	await fresh(); key_space(true)
	check(player.is_dodging(),"physical Space DOWN works")
	move_time(.61); key_space(true,true)
	check(not player.is_dodging(),"keyboard echo never repeats")
	key_space(false); key_space(true); check(player.is_dodging(),"fresh key edge after cooldown")
	key_space(false)
	for mode in ["touch","emulated_first","touch_first","mouse"]:
		await fresh(); await settle()
		var pos:=button("DodgeButton").get_global_rect().get_center()
		if mode=="emulated_first": mouse_dodge(pos,true,InputEvent.DEVICE_ID_EMULATION)
		if mode=="mouse": mouse_dodge(pos,true)
		else: touch(pos,true)
		if mode=="touch_first": mouse_dodge(pos,true,InputEvent.DEVICE_ID_EMULATION)
		check(player.is_dodging() and not player.is_attacking(),"DOWN acts exactly once "+mode)
		move_time(.61)
		if mode=="mouse": mouse_dodge(pos,false)
		else: touch(pos,false)
		mouse_dodge(pos,false,InputEvent.DEVICE_ID_EMULATION)
		check(not player.is_dodging() and not player.is_attacking(),"UP cannot restart or attack "+mode)
	group("actual viewport key/mouse/touch and emulated duplicate input")

	await fresh(); await settle()
	var dodge_pos:=button("DodgeButton").get_global_rect().get_center()
	var guard_pos:=button("GuardButton").get_global_rect().get_center()
	touch(guard_pos,true,10); touch(dodge_pos,true,11)
	check(session.snapshot().guarding and not player.is_dodging(),"second finger cannot cancel held block")
	touch(dodge_pos,false,11); check(session.snapshot().guarding,"wrong finger UP cannot release block")
	touch(guard_pos,false,10); check(not session.snapshot().guarding,"owner release works")
	touch(guard_pos,true,10); touch(dodge_pos,false,10)
	check(not session.snapshot().guarding,"guard owner released over dodge still releases block")
	touch(dodge_pos,true,13); move_time(.61); touch(dodge_pos,true,13)
	check(not player.is_dodging(),"duplicate owned DOWN cannot repeat after cooldown")
	touch(Vector2(25,500),false,13)
	touch(dodge_pos,true,13); check(player.is_dodging(),"outside release frees old owner")
	touch(Vector2(25,500),false,13,true); move_time(.61)
	touch(dodge_pos,true,13,true)
	check(not player.is_dodging(),"cancelled DOWN never starts")
	button("DodgeButton").hide(); touch(dodge_pos,true); touch(dodge_pos,false)
	check(not player.is_dodging(),"hidden button cannot consume action")
	button("DodgeButton").show()
	sandbox.level.get_node("InventoryMenu").request_open(); await settle()
	touch(dodge_pos,true); touch(dodge_pos,false); key_space(true); key_space(false)
	check(not player.is_dodging(),"open menu does not trigger dodge")
	sandbox.level.get_node("InventoryMenu").close_menu(false); await settle()
	await fresh(); await settle()
	var right_pos:=button("Right").get_global_rect().get_center()
	touch(right_pos,true,19)
	check(player._touch_move.x>.5,"real movement finger reaches player")
	var expected_right:=get_viewport().get_camera_3d().global_basis.x; expected_right.y=0; expected_right=expected_right.normalized()
	origin=player.global_position; touch(dodge_pos,true,20); move_time(.2)
	var actual:=player.global_position-origin; actual.y=0
	check(actual.normalized().dot(expected_right)>.99,"second finger dodges along held touch direction")
	check(player._touch_move.x>.5,"held movement survives accepted dodge")
	p=player.global_position; move_time(.05)
	check(player.global_position.distance_to(p)>.001,"normal movement resumes while finger stays held")
	touch(right_pos,false,19); touch(dodge_pos,false,20)
	group("multitouch guard ownership, hidden controls and menu input")

	for pack in [false,true]:
		for technique in ["novice","trained"]:
			await fresh(); sandbox.set_technique(technique); sandbox.set_backpack_enabled(pack)
			var body: AnimatedSprite3D=player.get_node("Visual/Body")
			var scale_before: Vector3=body.scale; var tint: Color=body.modulate
			check(player.request_dodge(),"both techniques and equipment can step")
			move_time(.07); check(body.animation.begins_with("walk_"),"existing whole walk pose during dodge")
			check(body.scale==scale_before and body.modulate==tint,"no stretched or flashed body")
			await capture(technique+"-"+("pack" if pack else "bare"))
			move_time(.2); check(not player.is_dodging(),"returns from step")
	group("whole-frame backpack and novice/trained movement visuals")
	await fresh(); loc.set_language("ru")
	if errors.is_empty() and groups==10:
		print("ASHBOUND_COMBAT_DODGE_OK groups=10"); get_tree().quit(0)
	else:
		printerr("DODGE_INCOMPLETE groups=%d errors=%d"%[groups,errors.size()]); get_tree().quit(1)
