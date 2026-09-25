extends Node
## Independent Codex tests: actual scene, collision space and public input paths.
var errors: Array[String] = []
var groups := 0
var sandbox: Node
var session: Node
var player: CharacterBody3D
var wolf: CharacterBody3D
var guard: CharacterBody3D
var events: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(60.0).timeout.connect(func() -> void: printerr("CORNER_ENEMY_TIMEOUT"); get_tree().quit(2))
	run.call_deferred()

func last_event() -> String:
	return events[-1] if not events.is_empty() else "NO_CONTACT"

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("CORNER_ENEMY_FAIL: " + message)

func group(label: String) -> void:
	groups += 1
	print("CORNER_ENEMY_GROUP %d %s" % [groups, label])

func settle() -> void:
	for i in 3: await get_tree().physics_frame

func tick(seconds: float) -> void:
	var left: float = seconds
	while left > .0000001:
		var dt: float = minf(left, 1.0/60.0)
		session.advance(dt)
		left -= dt
	player._update_visual()

func reset() -> void:
	session.reset_trial()
	player.velocity = Vector3.ZERO
	events.clear()
	sandbox.set_technique("trained")

func place_near(actor: Node3D, distance: float) -> void:
	player.global_position = actor.global_position + Vector3(0, 0, -distance)
	player.facing_direction = Vector3.BACK

func until_state(actor: Node, wanted: String, timeout: float = 5.0) -> bool:
	for i in int(ceil(timeout * 60)):
		if actor.state == wanted: return true
		tick(1.0/60.0)
	return actor.state == wanted

func until_contact(actor: Node, before: int, timeout: float = 3.0) -> bool:
	for i in int(ceil(timeout * 60)):
		if actor.contacts > before: return true
		tick(1.0/60.0)
	return actor.contacts > before

func until_cue() -> bool:
	for i in 180:
		if session.is_block_window_open(): return true
		tick(1.0/60.0)
	return false

func wall_between(actor: Node3D) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 2.0, .20)
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	wall.global_position = (actor.global_position + player.global_position) * .5 + Vector3(0, .8, 0)
	return wall

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var prefix := "user://" if OS.has_feature("android") else "res://.tools/"
	check(get_viewport().get_texture().get_image().save_png(prefix + "enemy-" + label + ".png") == OK, "capture " + label)

func run() -> void:
	if not OS.has_feature("android"):
		get_tree().root.mode = Window.MODE_WINDOWED
		get_tree().root.size = Vector2i(1920,1080)
	Localization.load_preferences("user://corner-enemy-qa.cfg", "en_US")
	sandbox = load("res://scripts/tools/corner_enemy_sandbox.tscn").instantiate()
	sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sandbox)
	await settle()
	session = sandbox.defense
	player = sandbox.level.get_node("Actors/Player")
	player.set_physics_process(false)
	session.set_physics_process(false)
	check(session.enemies.size() == 2, "exactly two enemies")
	if session.enemies.size() != 2: finish(); return
	wolf = session.enemies[0]
	guard = session.enemies[1]
	session.resolved.connect(func(result: String) -> void: events.append(result))
	reset()
	check(wolf.kind == "wolf" and guard.kind == "guard", "distinct enemy types")
	check(wolf.global_position.distance_to(guard.global_position) > 15, "separate corners")
	check(sandbox.level.get_node_or_null("Environment/Props/Dummy") == null, "no dummy in enemy trial")
	check(sandbox.level.get_node_or_null("Persistence") == null, "campaign profile isolated")
	tick(4)
	check(wolf.state == "idle" and guard.state == "idle" and events.is_empty(), "safe initial center")
	group("isolated scene, two corners and safe spawn")
	for actor in [wolf, guard]:
		reset(); place_near(actor, 3.001); await settle(); tick(.1)
		check(actor.state == "idle", "outside small radius " + actor.kind)
		place_near(actor, 2.99); await settle(); tick(.04)
		check(actor.state == "chase", "inside radius starts chase " + actor.kind)
		var other: Node = guard if actor == wolf else wolf
		check(other.state == "idle", "no shared aggro")
	group("proximity boundaries and independent aggro")
	reset(); place_near(wolf, 2.0); player.global_position.y += 1.01
	await settle(); tick(.2)
	check(wolf.state == "idle", "vertical separation rejects proximity")
	reset(); place_near(wolf, 2.5)
	var wall := wall_between(wolf)
	await settle(); tick(.5)
	check(wolf.state == "idle", "no detection through wall")
	wall.queue_free(); await settle(); tick(.1)
	check(wolf.state == "chase", "detection after wall removed")
	group("line of sight gates detection")
	for actor in [wolf, guard]:
		reset(); place_near(actor, 2.8); await settle()
		var start: Vector3 = actor.global_position
		tick(.4)
		check(actor.global_position.distance_to(start) > .25, "visible chase movement " + actor.kind)
		check(actor.global_position.distance_to(player.global_position) >= .58, "no overlap in chase")
		player.global_position = Vector3(0, .02, 3)
		tick(8)
		check(actor.global_position.distance_to(actor.home) <= .13 and actor.state == "idle", "returns home " + actor.kind)
	group("movement, disengagement and return")
	for actor in [wolf, guard]:
		reset(); place_near(actor, 1.3 if actor == guard else 1.8); await settle()
		check(until_state(actor, "windup"), "windup begins")
		var start: Vector3 = actor.global_position
		var count: int = actor.contacts
		tick(.4)
		check(actor.contacts == count and not session.is_block_window_open(), "no early contact/cue")
		check(until_contact(actor, count), "attack resolves " + actor.kind)
		check(actor.contacts == count + 1 and events.size() == 1, "one contact " + actor.kind)
		check(last_event() == "hit", "unblocked attack reaches hero " + actor.kind)
		var movement: float = actor.global_position.distance_to(start)
		check(movement > .30 if actor == wolf else movement < .01, "wolf lunges, guard punches in place")
		check(session.get_visual_action() == &"hit", "hero hit pose")
	group("distinct telegraphed attacks and single hit")
	for fps in [15, 30, 120]:
		for actor in [wolf, guard]:
			reset(); place_near(actor, 1.3 if actor == guard else 1.8); await settle()
			for i in fps: session.advance(1.0/float(fps))
			check(actor.contacts == 1 and events.size() == 1 and last_event() == "hit", "single contact at %d FPS %s" % [fps, actor.kind])
			player.global_position = Vector3(0, .02, 3)
			tick(8)
			check(actor.state == "idle" and actor.global_position.distance_to(actor.home) <= .13, "return after completed attack " + actor.kind)
	for actor in [wolf, guard]:
		reset(); place_near(actor, 1.3 if actor == guard else 1.8); await settle()
		session.set_guard(true)
		check(until_contact(actor, 0), "held block resolves")
		check(last_event() == "block", "hold gives ordinary block " + actor.kind)
		reset(); place_near(actor, 1.3 if actor == guard else 1.8); await settle()
		check(until_state(actor, "windup"), "perfect windup")
		check(until_cue(), "cue arrives before perfect press")
		session.set_guard(true)
		check(until_contact(actor, 0), "perfect contact")
		check(last_event() == "perfect_block" and actor.state == "stagger", "fresh timing staggers " + actor.kind)
	group("ordinary and perfect block against both attackers")
	for technique in ["novice", "trained"]:
		reset(); sandbox.set_technique(technique); place_near(guard, 1.3)
		if technique == "trained": player.facing_direction = Vector3.FORWARD
		await settle(); session.set_guard(true); check(until_contact(guard, 0), "failed defense resolves")
		check(last_event() == "hit", "novice or rear attack is not blocked")
	reset(); place_near(guard, 1.3); await settle(); until_state(guard, "windup")
	player.global_position += Vector3(2.0, 0, 0)
	check(until_contact(guard, 0), "sidestep resolves")
	check(last_event() == "miss", "locked direction can be dodged by movement")
	group("training, facing and moving off attack line")
	reset(); place_near(guard, 1.2); await settle(); until_state(guard, "windup")
	check(session.eligible_target() == guard, "guard is actual punch target")
	player.request_attack()
	for i in 18: player._physics_process(1.0/60.0)
	check(guard.hits_received == 1 and guard.state == "stagger", "actual hero contact interrupts enemy")
	tick(.35)
	check(guard.contacts == 0, "interrupted attack cannot land later")
	player.stop_input()
	player.facing_direction = Vector3.FORWARD
	check(session.eligible_target() == null, "no target behind hero")
	group("real hero strike signal, target geometry and interruption")
	for notification in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_PAUSED]:
		reset(); place_near(guard, 1.3); await settle(); until_state(guard, "windup")
		check(until_cue(), "cue arrives before cancellation")
		session.set_guard(true); session.notification(notification)
		check(not session.is_block_window_open() and not session.snapshot().guarding, "immediate cancellation")
		check(guard.state != "windup", "pending enemy contact cancelled")
		if notification == NOTIFICATION_APPLICATION_FOCUS_OUT: session.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		elif notification == NOTIFICATION_APPLICATION_PAUSED: session.notification(NOTIFICATION_APPLICATION_RESUMED)
		else: session.notification(NOTIFICATION_UNPAUSED)
		tick(.1)
		check(guard.contacts == 0, "no stale contact on resume")
	group("focus/app/tree cancellation and no replay")
	for cancellation in ["menu", "tree"]:
		reset(); place_near(guard, 1.3); await settle(); until_state(guard, "windup"); until_cue()
		session.set_guard(true)
		if cancellation == "menu":
			check(sandbox.level.get_node("InventoryMenu").request_open(), "real inventory opens")
			session.advance(0)
		else: get_tree().paused = true
		check(not session.is_block_window_open() and not session.snapshot().guarding, "real cancellation " + cancellation)
		check(guard.state != "windup", "real pending strike cancelled " + cancellation)
		if cancellation == "menu": sandbox.level.get_node("InventoryMenu").close_menu(false)
		else: get_tree().paused = false
		await settle(); tick(.1)
		check(guard.contacts == 0, "no stale real cancellation contact")
	reset(); place_near(guard, 1.3); await settle(); until_state(guard, "windup")
	wall = wall_between(guard); await settle()
	check(until_contact(guard, 0), "obstructed attack resolves")
	check(last_event() == "obstructed", "no punch through wall")
	check(session.eligible_target() == null, "hero cannot punch through wall")
	wall.queue_free(); await settle()
	reset(); place_near(wolf, 1.8); await settle(); until_state(wolf, "windup")
	wall = wall_between(wolf); await settle()
	var wall_z: float = wall.global_position.z
	until_contact(wolf, 0)
	check(wolf.global_position.z > wall_z + .25, "wolf swept collision stops at wall")
	wall.queue_free(); await settle()
	group("contact obstruction and collision-safe lunge")
	reset()
	var before: Dictionary = session.snapshot().duplicate(true)
	session.advance(-1); session.advance(NAN); session.advance(INF); session.advance(0)
	check(session.snapshot() == before, "invalid or zero delta is read-only")
	for language in ["en", "ru"]:
		Localization.set_language(language)
		await settle()
		check(Localization.text("ENEMY_WOLF") != "ENEMY_WOLF" and Localization.text("ENEMY_HINT_TOUCH") != "ENEMY_HINT_TOUCH", "enemy strings actually translated")
		check(wolf.get_node("EnemyLabel").text == Localization.text("ENEMY_WOLF"), "localized wolf")
		check(guard.get_node("EnemyLabel").text == Localization.text("ENEMY_GUARD"), "localized guard")
	group("invalid time and EN/RU labels")
	reset()
	var toolbar: Node
	for child in sandbox.get_children():
		if child.get_script() == load("res://scripts/combat/corner_enemy_toolbar.gd"): toolbar = child
	check(toolbar != null, "actual enemy toolbar exists")
	if toolbar != null:
		toolbar._process(0)
		check(not toolbar._swing_btn.is_visible_in_tree(), "old incoming strike hidden")
		check(not toolbar._inside_button(toolbar._swing_btn, toolbar._swing_btn.get_global_rect().get_center()), "hidden button cannot capture touch")
		var touch := InputEventScreenTouch.new()
		touch.index = 7; touch.pressed = true; touch.position = toolbar._guard_btn.get_global_rect().get_center()
		toolbar._input(touch)
		check(session.snapshot().guarding and session.get_visual_action() == &"guard", "real touch BLOCK immediate guard")
		touch.pressed = false; touch.position = Vector2.ZERO
		toolbar._input(touch)
		check(not session.snapshot().guarding, "touch release outside clears guard")
	reset(); place_near(guard, 2.7); sandbox.level._snap_camera_to_player(); await settle(); until_state(guard, "windup")
	var rig: Node = sandbox.level.get_node("CameraRig")
	var locked: Vector3 = guard.facing_direction
	var contacts: int = guard.contacts
	for i in 4:
		rig.rotate_view(Vector2(deg_to_rad(90.0)/rig.mouse_sensitivity,0))
		await settle()
		check(guard.facing_direction == locked and guard.contacts == contacts, "camera cannot change enemy aim/time")
		player._update_visual()
		await capture("guard-view-" + str(i))
	reset(); place_near(wolf, 2.3); sandbox.level._snap_camera_to_player(); await settle()
	rig.rotate_view(Vector2(PI/rig.mouse_sensitivity,0)); await settle()
	until_state(wolf, "windup"); tick(.6); await capture("wolf-lunge")
	rig.rotate_view(Vector2(deg_to_rad(65)/rig.mouse_sensitivity,0)); await settle(); player._update_visual()
	await capture("wolf-lunge-side")
	group("four camera views and readable enemy artwork")
	finish()

func finish() -> void:
	if errors.is_empty() and groups == 12:
		print("ASHBOUND_CORNER_ENEMIES_OK groups=12")
		get_tree().quit(0)
	else:
		printerr("CORNER_ENEMY_INCOMPLETE groups=%d errors=%d" % [groups, errors.size()])
		get_tree().quit(1)
