extends Node
## Codex independent checks. Real preview, public input, real contacts; watchdog + complete group count.
var errors: Array[String] = []
var groups := 0
var sandbox: Node
var session: Node
var player: CharacterBody3D
var wolf: CharacterBody3D
var guard: CharacterBody3D
var fx: Node3D
var events: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(90).timeout.connect(func() -> void: printerr("FEEDBACK_TIMEOUT"); get_tree().quit(2))
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("FEEDBACK_FAIL: " + message)

func group(label: String) -> void:
	groups += 1
	print("FEEDBACK_GROUP %d %s" % [groups, label])

func settle() -> void:
	for i in 3: await get_tree().physics_frame

func tick(seconds: float) -> void:
	var left := seconds
	while left > 0.0000001:
		var dt := minf(left, 1.0 / 60.0)
		session.advance(dt)
		left -= dt
	player._update_visual()

func reset() -> void:
	session.reset_trial()
	player.velocity = Vector3.ZERO
	events.clear()
	sandbox.set_technique("trained")

func place(actor: Node3D) -> void:
	player.global_position = actor.global_position + Vector3(0, 0, -1.3 if actor == guard else -1.8)
	player.facing_direction = Vector3.BACK

func until_contact(actor: Node) -> void:
	for i in 240:
		if not events.is_empty(): return
		tick(1.0 / 60.0)
	check(false, "contact timeout " + actor.kind)

func until_cue() -> void:
	for i in 240:
		if session.is_block_window_open(): return
		tick(1.0 / 60.0)
	check(false, "cue timeout")

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var prefix := "user://" if OS.has_feature("android") else "res://.tools/"
	check(get_viewport().get_texture().get_image().save_png(prefix + "feedback-" + label + ".png") == OK, "capture " + label)

func meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D: found.append(child)
		found.append_array(meshes(child))
	return found

func visible_meshes(root: Node) -> int:
	var count := 0
	for mesh in meshes(root):
		if mesh.is_visible_in_tree(): count += 1
	return count

func run() -> void:
	sandbox = load("res://scripts/tools/combat_feedback_sandbox.tscn").instantiate()
	sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sandbox)
	await settle()
	session = sandbox.defense
	player = sandbox.level.get_node("Actors/Player")
	wolf = session.enemies[0]
	guard = session.enemies[1]
	session.set_physics_process(false)
	player.set_physics_process(false)
	session.resolved.connect(func(result: String) -> void: events.append(result))
	for child in session.get_children():
		if child.has_method("debug_snapshot"): fx = child
	check(fx != null, "new FX renderer is attached")
	check(player.has_method("begin_feedback_stop"), "feedback player factory used")
	if fx == null: get_tree().quit(1); return
	var vertices := 0
	for mesh in meshes(fx):
		check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "transient ink cannot cast a solid shadow")
		for surface in mesh.mesh.get_surface_count():
			vertices += mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
	check(vertices < 6000, "effect pool geometry budget")
	reset(); tick(3)
	check(events.is_empty() and not session.is_hitstopped(), "safe spawn unchanged")
	check(Engine.time_scale == 1.0 and not get_tree().paused, "world clock unchanged")
	group("isolated preview wiring")

	fx.clear_all()
	fx.update_cue("qa", player.global_position + Vector3.UP, Vector3.FORWARD, .3, false, "guard")
	check(fx.debug_snapshot().visible_cues == 1 and visible_meshes(fx) > 0, "cue genuinely visible before timing window")
	var cue: Node3D
	for child in fx.get_children():
		if child is Node3D and child.visible: cue = child; break
	var cue_scale: Vector3 = cue.scale
	fx._process(0)
	check(cue.scale.is_equal_approx(cue_scale), "camera orientation retains cue charge scale")
	var early_count := visible_meshes(fx)
	fx.update_cue("qa", player.global_position + Vector3.UP, Vector3.FORWARD, .9, true, "guard")
	check(visible_meshes(fx) > early_count, "armed cue adds distinct geometry")
	fx.hide_cue("qa")
	check(fx.debug_snapshot().visible_cues == 0 and visible_meshes(fx) == 0, "hide immediate")
	for outcome in ["miss", "obstructed", "cancelled", "unknown"]:
		fx.emit_impact(outcome, Vector3.ZERO, Vector3.ZERO)
	check(fx.debug_snapshot().active_impacts == 0, "misses never spawn contact")
	var before_nodes := fx.get_child_count()
	for i in 20: fx.emit_impact("hit", Vector3.ZERO, Vector3.FORWARD)
	check(fx.debug_snapshot().active_impacts == 8 and fx.get_child_count() == before_nodes, "bounded pool under repeated contact")
	fx.advance(.4)
	check(fx.debug_snapshot().active_impacts == 0 and visible_meshes(fx) == 0, "all impacts expire")
	group("visible cue, shape change and bounded effect pool")

	fx.clear_all(); fx.emit_impact("hit", Vector3.ZERO, Vector3.FORWARD)
	var first_mesh: MeshInstance3D
	for mesh in meshes(fx):
		if mesh.is_visible_in_tree(): first_mesh = mesh; break
	check(first_mesh != null, "impact has real visible mesh")
	fx.advance(.16)
	var impact_root := first_mesh.get_parent().get_parent() as Node3D
	var impact_scale := impact_root.scale
	fx._process(0)
	check(impact_root.scale.is_equal_approx(impact_scale), "camera orientation retains impact expansion scale")
	var old_alpha: float = first_mesh.material_override.albedo_color.a
	check(old_alpha > 0 and old_alpha < .9, "impact fades before expiry")
	fx.emit_impact("hit", Vector3.RIGHT, Vector3.FORWARD)
	check(is_equal_approx(first_mesh.material_override.albedo_color.a, old_alpha), "new contact cannot reset old alpha")
	for mesh in meshes(fx):
		if mesh.is_visible_in_tree():
			check(mesh.material_override is StandardMaterial3D, "Compatibility material")
	fx.clear_all()
	check(visible_meshes(fx) == 0, "clear hides all pooled geometry")
	group("fade, independent materials and clear")

	for actor in [wolf, guard]:
		for outcome in ["hit", "block", "perfect_block"]:
			reset(); place(actor); await settle()
			sandbox.level._snap_camera_to_player()
			var camera_rig: Node = sandbox.level.get_node("CameraRig")
			camera_rig.rotate_view(Vector2(deg_to_rad(50)/camera_rig.mouse_sensitivity, 0))
			if outcome == "block": session.set_guard(true)
			until_cue()
			check(fx.debug_snapshot().visible_cues == 1, "natural cue " + actor.kind)
			check(not actor.get_node("Visual/AttackCue").visible, "legacy cue disabled only in new preview")
			if outcome == "perfect_block": session.set_guard(true)
			until_contact(actor)
			check(events == [outcome], "single " + outcome + " " + actor.kind)
			check(fx.debug_snapshot().last_result == outcome and fx.debug_snapshot().active_impacts == 1, "one corresponding effect")
			check(session.is_hitstopped(), "confirmed contact starts stop")
			await capture(actor.kind + "-contact-" + outcome)
			var pos: Vector3 = actor.global_position
			var state_time: float = actor.state_time
			var clock: float = session.snapshot().time
			var remaining: float = session.feedback_snapshot().stop_remaining
			var expected: float = .05 if outcome == "hit" else (2.0/60 if outcome == "block" else 5.0/60)
			check(absf(remaining - expected) <= 1.0/60 + .000001, "stop duration " + outcome)
			session.advance(remaining * .5)
			check(actor.global_position == pos and is_equal_approx(actor.state_time, state_time), "enemy motion/phase frozen")
			check(is_equal_approx(session.snapshot().time, clock), "simulation clock frozen")
			session.advance(remaining * .5 + .000001)
			check(not session.is_hitstopped(), "stop terminates")
			tick(.1)
			check(events.size() == 1, "no repeated contact after stop")
	group("natural hit/block/perfect against wolf and guard")

	reset(); place(guard); await settle()
	player.request_attack()
	for i in 8: player._physics_process(1.0/60)
	check(guard.hits_received == 1 and session.is_hitstopped(), "real outgoing punch creates stop once")
	var attack_t: float = player._attack_time
	var cooldown: float = player._cooldown
	var position_before := player.global_position
	player.set_move_input(Vector2(1, 0))
	player._physics_process(.01)
	check(player.global_position == position_before and is_equal_approx(player._attack_time, attack_t) and is_equal_approx(player._cooldown, cooldown), "hero movement and attack timers frozen")
	var body := player.get_node("Visual/Body") as AnimatedSprite3D
	check(String(body.animation).begins_with("attack") and body.frame == 1 and not body.is_playing(), "contact pose explicitly pinned")
	player._physics_process(.1)
	check(body.is_playing() and player.feedback_stop_remaining() <= 0, "hero animation resumes")
	player.begin_feedback_stop(.08, &"attack")
	player.begin_feedback_stop(.03, &"hit")
	check(is_equal_approx(player.feedback_stop_remaining(), .08), "short simultaneous hit cannot shorten stop")
	check(String(body.animation).begins_with("hit") and not body.is_playing(), "reaction change during stop remains paused")
	player.input_enabled = false
	player._physics_process(.01)
	check(player.feedback_stop_remaining() <= 0, "disabled player immediately clears stop")
	player.input_enabled = true
	tick(.4)
	check(guard.contacts == 0 and guard.hits_received == 1, "interrupted enemy does not strike later")
	group("outgoing hit, contact pose and local hero clock")

	reset(); place(guard); await settle(); until_contact(guard)
	var toolbar: Node
	for child in sandbox.get_children():
		if child.get_script() == load("res://scripts/tools/corner_enemy_toolbar.gd"): toolbar = child
	check(toolbar != null, "actual touch toolbar wired")
	var touch := InputEventScreenTouch.new()
	touch.index = 7; touch.pressed = true
	touch.position = toolbar._guard_btn.get_global_rect().get_center()
	toolbar._input(touch)
	check(session.snapshot().guarding and not session._perfect_eligible, "frozen press gives hold but no new perfect edge")
	touch.pressed = false; touch.position = Vector2.ZERO
	toolbar._input(touch)
	check(not session.snapshot().guarding, "release during stop immediate")
	var before: Dictionary = session.feedback_snapshot().duplicate(true)
	session.advance(-1); session.advance(NAN); session.advance(INF)
	check(session.feedback_snapshot() == before, "invalid delta cannot alter stop/effects")
	group("guard edge and invalid time during stop")

	for actor in [wolf, guard]:
		reset(); place(actor); await settle(); until_cue()
		player.global_position += Vector3(5, 0, 0)
		until_contact(actor)
		check(events == ["miss"] and not session.is_hitstopped() and fx.debug_snapshot().active_impacts == 0, "miss has no stop/impact " + actor.kind)
	for fps in [15, 30, 60, 120]:
		reset(); place(guard); await settle()
		for i in fps: session.advance(1.0 / fps)
		check(events == ["hit"], "single event at variable step " + str(fps))
	group("miss and variable update intervals")

	for how in ["focus", "app", "tree", "menu", "reset", "technique"]:
		reset(); place(guard); await settle(); until_contact(guard)
		check(session.is_hitstopped(), "stop active before " + how)
		match how:
			"focus": session.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			"app": session.notification(NOTIFICATION_APPLICATION_PAUSED)
			"tree": get_tree().paused = true
			"menu":
				check(sandbox.level.get_node("InventoryMenu").request_open(), "inventory opens during stop")
				session.advance(0)
			"reset": session.reset_trial()
			"technique": sandbox.set_technique("novice")
		check(not session.is_hitstopped() and player.feedback_stop_remaining() <= 0, "stop clears " + how)
		check(visible_meshes(fx) == 0, "FX clears " + how)
		match how:
			"focus": session.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
			"app": session.notification(NOTIFICATION_APPLICATION_RESUMED)
			"tree": get_tree().paused = false
			"menu": sandbox.level.get_node("InventoryMenu").close_menu(false)
		await settle()
		var contacts: int = events.size()
		tick(.1)
		check(events.size() == contacts, "no stale contact " + how)
	group("menu, focus, Android lifecycle, reset and technique clear")

	for actor in [wolf, guard]:
		reset(); place(actor); sandbox.level._snap_camera_to_player(); await settle(); until_cue()
		var rig: Node = sandbox.level.get_node("CameraRig")
		for view in 4:
			rig.rotate_view(Vector2(deg_to_rad(90.0)/rig.mouse_sensitivity, 0))
			await settle()
			fx._process(0)
			check(fx.debug_snapshot().visible_cues == 1, "cue retained during orbit")
			await capture(actor.kind + "-cue-" + str(view))
		for outcome in ["hit", "block", "perfect_block"]:
			fx.clear_all()
			fx.emit_impact(outcome, player.global_position + Vector3(0, 1.2, 0), Vector3.FORWARD)
			fx.advance(.065)
			await settle(); await capture(actor.kind + "-" + outcome)
	group("rendered cue and impact profiles")
	reset()
	if errors.is_empty() and groups == 9:
		print("ASHBOUND_COMBAT_FEEDBACK_OK groups=9")
		get_tree().quit(0)
	else:
		printerr("FEEDBACK_INCOMPLETE groups=%d errors=%d" % [groups, errors.size()])
		get_tree().quit(1)
