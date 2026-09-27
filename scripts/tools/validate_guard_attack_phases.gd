extends "res://scripts/tools/validate_combat_feedback.gd"
## Codex acceptance of real active windows, independent from the local worker.
var defaults: Resource = preload("res://assets/combat/guard_unarmed_v1.tres")

func until_state(wanted: String) -> void:
	for i in 180:
		if guard.state == wanted: return
		tick(1.0/60.0)
	check(false, "guard did not reach " + wanted)

func prime() -> void:
	reset(); guard.configure_attack(defaults); place(guard)
	await settle(); until_state("windup")
	check(guard.state_time == 0.0, "startup starts at zero")

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var prefix := "user://" if OS.has_feature("android") else "res://.tools/"
	check(get_viewport().get_texture().get_image().save_png(prefix + "phases-" + label + ".png") == OK, "capture " + label)

func run() -> void:
	check(defaults.is_valid() and is_equal_approx(defaults.total_seconds(),1.5), "valid 48/6/36 frame profile")
	for sample in [[0.0,"startup"],[.8-.000001,"startup"],[.8,"active"],[.9-.000001,"active"],[.9,"recovery"],[1.5-.000001,"recovery"],[1.5,"ready"],[-1.0,"invalid"],[NAN,"invalid"],[INF,"invalid"]]:
		check(defaults.phase_at(sample[0]) == sample[1], "half-open data boundary " + str(sample))
	for bad in [["startup_frames",0],["active_frames",0],["recovery_frames",601],["cue_seconds",NAN],["cue_seconds",.9],["attack_id",&""]]:
		var data: Resource = defaults.duplicate(true); data.set(bad[0],bad[1])
		check(not data.is_valid() and data.phase_at(0) == "invalid", "invalid data " + str(bad))
	group("resource bounds and exact phase intervals")

	sandbox = load("res://scripts/tools/guard_phases_sandbox.tscn").instantiate()
	sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE; add_child(sandbox); await settle()
	session = sandbox.defense; player = sandbox.level.get_node("Actors/Player")
	wolf=session.enemies[0]; guard=session.enemies[1]
	fx=session.get_node("CombatFeedbackFX")
	session.set_physics_process(false); player.set_physics_process(false)
	session.resolved.connect(func(result: String) -> void: events.append(result))
	check(guard.get_script().resource_path.ends_with("frame_guard_actor.gd"), "guard uses phases")
	check(wolf.get_script().resource_path.ends_with("corner_enemy_actor.gd"), "wolf retains prior behavior")
	reset()
	var custom: Resource = defaults.duplicate(true)
	custom.startup_frames=12; custom.active_frames=6; custom.recovery_frames=18; custom.cue_seconds=.10
	check(guard.configure_attack(custom), "configure idle actor")
	custom.startup_frames=60
	check(guard.attack_data.startup_frames==12, "actor owns data copy")
	place(guard); await settle(); until_state("windup")
	check(not guard.configure_attack(defaults), "cannot alter running attack")
	tick(.19); check(events.is_empty(), "changed data has no early contact")
	tick(.011); check(events==["hit"] and guard.state=="active", "new profile drives actual first contact")
	group("isolated factory and resource controls actual timing")

	await prime()
	var before: Dictionary = session.feedback_snapshot().duplicate(true)
	for i in 20: check(session.enemy_contact_geometry(guard)=="contact", "pure geometry reports contact")
	check(session.feedback_snapshot()==before and events.is_empty(), "geometry query has no effects")
	tick(.79); check(events.is_empty() and guard.state=="windup", "no damage during startup")
	tick(.011); check(events==["hit"] and guard.state=="active", "contact at active opening")
	var frozen: float=guard.state_time
	session.advance(.02); check(is_equal_approx(guard.state_time,frozen), "hitstop freezes phase clock")
	tick(.30); check(events==["hit"] and guard.contacts==1 and guard.state=="recovery", "one contact for whole active window")
	check(guard.snapshot().attack_phase=="recovery", "recovery visible in snapshot")
	until_state("idle"); check(events.size()==1, "recovery cannot attack")
	group("startup boundary, single contact, hitstop and recovery")

	await prime(); player.global_position=guard.global_position+Vector3(0,0,-1.9)
	until_state("active"); check(events.is_empty(), "active opening may miss without consuming attack")
	tick(.035); place(guard); await settle(); tick(.01)
	check(events==["hit"], "target entering later in active interval is struck")
	tick(.3); check(events.size()==1, "late hit not repeated")
	await prime(); player.global_position=guard.global_position+Vector3(0,0,-1.9)
	until_state("active"); tick(.10)
	check(events==["miss"] and guard.contacts==1 and not session.is_hitstopped(), "whole active miss reported once without hitstop")
	place(guard); tick(.05)
	check(events==["miss"] and fx.debug_snapshot().active_impacts==0, "entry after active end cannot hit")
	group("late entry, full miss and closed-window exclusion")

	for obstruction in ["cone","height","wall"]:
		await prime()
		var wall: StaticBody3D
		match obstruction:
			"cone": player.global_position=guard.global_position+Vector3(1.2,0,0)
			"height": player.global_position.y+=2
			"wall":
				wall=StaticBody3D.new(); wall.collision_layer=1; wall.collision_mask=0
				var shape:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=Vector3(2,2,.15)
				shape.shape=box; wall.add_child(shape); add_child(wall)
				wall.global_position=guard.global_position+Vector3(0,1,-.65)
		await settle(); until_state("recovery")
		check(events==["obstructed" if obstruction=="wall" else "miss"], "active contact respects " + obstruction)
		check(fx.debug_snapshot().active_impacts==0, "no impact through " + obstruction)
		if wall!=null: wall.queue_free(); await settle()
	group("height, cone and occlusion throughout active window")

	for result in ["block","perfect_block"]:
		await prime()
		if result=="block": session.set_guard(true)
		until_cue()
		if result=="perfect_block": session.set_guard(true)
		until_contact(guard)
		check(events==[result] and session.is_hitstopped(), "guard outcome " + result)
		check(guard.state==("stagger" if result=="perfect_block" else "active"), "correct next phase " + result)
		await capture(result)
		tick(.35); check(events.size()==1, "no repeated guarded strike")
	reset(); place(wolf); await settle(); until_contact(wolf)
	check(events==["hit"] and wolf.state=="recovery", "wolf still single contact at windup end")
	group("normal/perfect block and unchanged wolf")

	for how in ["hit-startup","hit-active","focus","menu","reset","technique"]:
		await prime(); player.global_position=guard.global_position+Vector3(0,0,-1.9)
		if how!="hit-startup": until_state("active")
		match how:
			"hit-startup","hit-active": guard.receive_hit()
			"focus": session.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			"menu": sandbox.level.get_node("InventoryMenu").request_open(); session.advance(0)
			"reset": session.reset_trial()
			"technique": sandbox.set_technique("novice")
		tick(.25); check(events.is_empty(), "cancelled attack has no delayed hit " + how)
		check(guard.state!="active" and guard.state!="windup", "cancel exits attack " + how)
		if how=="focus": session.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		if how=="menu": sandbox.level.get_node("InventoryMenu").close_menu(false)
		await settle()
	group("interruptions and no deferred contacts")

	for fps in [15,30,60,120]:
		await prime()
		for i in fps: session.advance(1.0/fps)
		check(events==["hit"] and guard.contacts==1, "one contact at variable delta " + str(fps))
	await prime(); before=session.feedback_snapshot().duplicate(true)
	session.advance(-1); session.advance(NAN); session.advance(INF)
	check(session.feedback_snapshot()==before, "invalid time cannot change phase")
	tick(.4); await capture("startup"); tick(.25); await capture("armed")
	until_state("active"); await capture("active"); tick(.25); await capture("recovery")
	group("variable update rate, invalid time and visual phase evidence")
	reset()
	if errors.is_empty() and groups==8:
		print("ASHBOUND_GUARD_PHASES_OK groups=8"); get_tree().quit(0)
	else:
		printerr("PHASES_INCOMPLETE groups=%d errors=%d" % [groups,errors.size()]); get_tree().quit(1)
