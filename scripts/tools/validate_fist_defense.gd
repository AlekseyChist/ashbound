extends Node
## Independent Codex QA: exact contact time, space, input cancellation and isolation.
var errors: Array[String] = []
var groups := 0
var resolved_count := 0
var sandbox: Node
var player: Node
var defense: Node
var root: Window
var settings_path := "res://.tools/defense-settings.cfg"

func _ready() -> void:
	root = get_tree().root
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		printerr("DEFENSE_FAIL: " + message)

func group(message: String) -> void:
	groups += 1
	print("DEFENSE_GROUP %d %s" % [groups, message])

func settle(count: int = 3) -> void:
	for i in count: await get_tree().process_frame

func reset(technique: String = "trained") -> void:
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	player.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	defense.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	defense.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	player.input_enabled = true
	player.stop_input()
	defense.reset_trial()
	check(sandbox.set_technique(technique), "technique accepted")
	player._update_visual()

func snapshot() -> Dictionary:
	return defense.snapshot()

func result(expected: String, message: String) -> void:
	check(snapshot().result == expected, message + " got " + str(snapshot()))
	check(snapshot().contacts == 1, message + " exactly one contact")

func steps(duration: float, fps: int) -> void:
	var left := duration
	while left > 0.000001:
		var dt: float = minf(left, 1.0 / fps)
		defense.advance(dt)
		left -= dt

func run() -> void:
	root.size = Vector2i(1920, 1080)
	if OS.has_feature("android"): settings_path = "user://defense-qa-settings.cfg"
	root.get_node("Localization").load_preferences(settings_path, "en_US")
	sandbox = load("res://scripts/tools/fist_defense_sandbox.tscn").instantiate()
	add_child(sandbox)
	await settle(6)
	player = sandbox.level.get_node("Actors/Player")
	defense = sandbox.get("defense")
	if defense == null:
		check(false, "defense controller exists")
		finish()
		return
	player.set_physics_process(false)
	defense.set_physics_process(false)
	defense.resolved.connect(func(_value: String): resolved_count += 1)
	var progress: Node = player.get_node("Progression")
	var initial: Dictionary = progress.get_character_data().duplicate(true)
	check(sandbox.level.get_node_or_null("Persistence") == null, "preview no campaign persistence")
	check(initial.unarmed_mastery == "novice", "no free training")
	reset()
	check(defense.start_swing(), "explicit first swing")
	check(not defense.start_swing(), "overlap rejected")
	defense.advance(0.79)
	check(snapshot().contacts == 0 and snapshot().phase == "windup", "no early invisible contact")
	var pad: MeshInstance3D = defense.get("_pad_mesh")
	var neutral_pad: Color = pad.material_override.albedo_color if pad != null else Color.WHITE
	check(pad != null, "visible training pad")
	if pad != null:
		var before_contact := Vector2(pad.global_position.x-player.global_position.x,pad.global_position.z-player.global_position.z).length()
		check(before_contact > 0.45, "preparation pad has not already reached hero")
	defense.advance(0.02)
	result("hit", "unprotected hit")
	if pad != null:
		var contact_distance := Vector2(pad.global_position.x-player.global_position.x,pad.global_position.z-player.global_position.z).length()
		check(contact_distance < 0.4 and pad.global_position.y >= 0.9 and pad.global_position.y <= 1.5, "visible pad agrees with resolved contact")
	check(not defense.start_swing(), "recovery rejects new swing")
	defense.advance(4.0)
	check(snapshot().contacts == 1 and snapshot().phase == "idle", "one resolution despite long frame")
	if pad != null:
		check(pad.material_override.albedo_color == neutral_pad, "pad returns neutral after recovery")
		var arm: MeshInstance3D = pad.get_parent().get_node("Arm")
		check(arm.position.z + arm.mesh.size.z / 2.0 <= pad.position.z + pad.mesh.size.z / 2.0, "wood spar does not poke through padded end")
	group("explicit windup/contact/recovery, no duplicate")

	for fps in [15, 30, 60, 120]:
		reset()
		defense.start_swing()
		steps(0.66, fps)
		check(defense.set_guard(true), "fresh trained guard")
		steps(0.15, fps)
		result("perfect_block", "timely guard fps=" + str(fps))
	reset()
	defense.start_swing()
	defense.advance(0.66)
	defense.set_guard(true)
	defense.advance(3.0)
	result("perfect_block", "long frame uses exact contact time")
	for guard_time in [0.619,0.621]:
		reset()
		defense.start_swing()
		defense.advance(guard_time)
		defense.set_guard(true)
		defense.advance(0.82-guard_time)
		result("block" if guard_time < 0.62 else "perfect_block", "perfect window boundary " + str(guard_time))
	reset()
	defense.start_swing()
	defense.advance(0.7998)
	check(snapshot().contacts == 0, "contact is not snapped early by coarse epsilon")
	defense.advance(0.0003)
	result("hit", "contact boundary crossed by small time slice")
	group("time window independent of frame subdivision")

	reset()
	defense.set_guard(true)
	defense.start_swing()
	defense.advance(0.81)
	result("block", "early held guard ordinary")
	defense.advance(1.0)
	defense.start_swing()
	defense.advance(0.81)
	check(snapshot().contacts == 2 and snapshot().result == "block", "holding never refreshes perfect")
	reset()
	defense.start_swing()
	defense.advance(0.7)
	defense.set_guard(true)
	defense.set_guard(true)
	defense.advance(0.11)
	result("perfect_block", "duplicate down doesn't invalidate valid first edge")
	reset()
	defense.start_swing()
	defense.advance(0.4)
	defense.set_guard(true)
	defense.advance(0.3)
	defense.set_guard(false)
	defense.set_guard(true)
	defense.advance(0.11)
	result("block", "release/repress cannot farm window")
	group("held and repeated input rules")

	reset()
	defense.start_swing()
	defense.advance(0.81)
	defense.set_guard(true)
	result("hit", "late defense cannot undo hit")
	reset()
	defense.start_swing()
	defense.advance(0.68)
	defense.set_guard(true)
	defense.set_guard(false)
	defense.advance(0.13)
	result("hit", "released guard not active")
	reset("novice")
	defense.start_swing()
	defense.advance(0.68)
	defense.set_guard(true)
	defense.advance(0.13)
	result("hit", "novice attempt has no technical block")
	group("late/released/novice attempts")

	reset()
	defense.set_guard(true)
	player.request_attack()
	check(not player.is_attacking(), "held guard suppresses attack")
	defense.set_guard(false)
	player.request_attack()
	check(player.is_attacking(), "attack after release")
	check(not defense.set_guard(true), "attack cannot also guard")
	check(not snapshot().guarding, "no queued guard")
	player.stop_input()
	group("attack/guard mutual exclusion")

	for position in [Vector3(0, 0.1, 5), Vector3(1.5, 0.1, 3.3), Vector3(0, 2.1, 4)]:
		reset()
		defense.start_swing()
		player.position = position
		defense.advance(0.81)
		result("miss", "distance/cone/elevation " + str(position))
	reset()
	defense.start_swing()
	defense.advance(0.5)
	player.position.x += 1.5
	defense.advance(0.31)
	result("miss", "real movement out of locked attack line")
	for distance in [1.899, 1.901]:
		reset()
		defense.start_swing()
		player.position.z = 2.4 + distance
		defense.advance(0.81)
		result("hit" if distance < 1.9 else "miss", "reach boundary " + str(distance))
	for angle in [29.9, 30.1]:
		reset()
		defense.start_swing()
		player.position = Vector3(0,0.1,2.4) + Vector3.BACK.rotated(Vector3.UP,deg_to_rad(angle)) * 1.6
		defense.advance(0.81)
		result("hit" if angle < 30 else "miss", "attack cone boundary " + str(angle))
	group("reach, locked direction, vertical separation")

	for angle in [0.0, PI / 2, PI]:
		reset()
		player.facing_direction = Vector3.FORWARD.rotated(Vector3.UP, angle)
		defense.start_swing()
		defense.advance(0.7)
		defense.set_guard(true)
		defense.advance(0.11)
		result("perfect_block" if angle == 0 else "hit", "guard world-facing " + str(angle))
	reset()
	defense.start_swing()
	defense.advance(0.7)
	defense.set_guard(true)
	var rig: Node = sandbox.level.get_node("CameraRig")
	rig.rotate_view(Vector2(PI / rig.mouse_sensitivity, 0))
	defense.advance(0.11)
	result("perfect_block", "camera rotation doesn't change guard")
	for angle in [54.9,55.1]:
		reset()
		player.facing_direction = Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(angle))
		defense.start_swing()
		defense.advance(0.7)
		defense.set_guard(true)
		defense.advance(0.11)
		result("perfect_block" if angle < 55 else "hit", "guard cone boundary " + str(angle))
	group("world-facing, camera independent")

	reset()
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 2, 0.15)
	collider.shape = shape
	wall.add_child(collider)
	sandbox.level.add_child(wall)
	wall.global_position = Vector3(0, 1, 3.2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	defense.start_swing()
	defense.advance(0.81)
	result("obstructed", "wall prevents contact")
	wall.queue_free()
	await get_tree().physics_frame
	group("physical obstacle")

	for notification_id in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_PAUSED]:
		reset()
		defense.start_swing()
		defense.advance(0.7)
		defense.set_guard(true)
		defense.notification(notification_id)
		check(snapshot().phase == "idle" and not snapshot().guarding, "immediate notification cancellation")
		defense.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		defense.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		defense.advance(2.0)
		check(snapshot().contacts == 0, "no resumed ghost contact")
	reset()
	defense.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	defense.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not defense.start_swing() and not defense.set_guard(true), "resume doesn't override missing focus")
	reset()
	defense.start_swing()
	defense.set_guard(true)
	get_tree().paused = true
	check(snapshot().phase == "idle" and not snapshot().guarding, "actual tree pause cancels immediately")
	check(not defense.start_swing(), "paused tree rejects swing")
	get_tree().paused = false
	defense.advance(1.0)
	check(snapshot().contacts == 0, "actual tree resume no ghost strike")
	check(defense.start_swing(), "new explicit strike works after tree resume")
	group("focus, pause, no replay")

	reset()
	defense.start_swing()
	defense.advance(0.7)
	defense.set_guard(true)
	player.input_enabled = false
	defense.advance(0.11)
	check(snapshot().contacts == 0 and not snapshot().guarding, "disabled input cancels before contact")
	reset()
	var menu: Node = sandbox.level.get_node("InventoryMenu")
	defense.start_swing()
	defense.advance(0.4)
	check(menu.request_open(), "actual pocket menu opens")
	defense.advance(0.5)
	check(snapshot().contacts == 0 and not snapshot().guarding, "opening menu cancels attack")
	check(not defense.start_swing() and not defense.set_guard(true), "menu blocks requests")
	menu.close_menu(false)
	await settle()
	reset()
	group("disabled control and actual menu")

	var before: Dictionary = snapshot().duplicate(true)
	for invalid in [-1.0, NAN, INF]: defense.advance(invalid)
	check(snapshot() == before, "invalid delta cannot corrupt state")
	for i in 100: defense.advance(0.0001)
	check(absf(snapshot().time - before.time - 0.01) < 0.00001, "small positive idle time is never discarded")
	defense.start_swing()
	defense.advance(0.5)
	defense.cancel_trial()
	defense.advance(2.0)
	check(snapshot().contacts == 0 and snapshot().phase == "idle", "explicit cancel")
	defense.start_swing()
	defense.advance(0.81)
	var contact_time: float = snapshot().time
	defense.cancel_trial()
	check(snapshot().contacts == 1 and snapshot().result == "hit" and snapshot().time == contact_time, "cancel preserves completed result and clock")
	group("invalid time and cancellation")

	for pack in [false, true]:
		check(sandbox.set_backpack_enabled(pack), "actual backpack toggles")
		for tech in ["novice", "trained"]:
			reset(tech)
			var visual: Node3D = player.get_node("Visual")
			var base_position := visual.position
			var body: AnimatedSprite3D = visual.get_node("Body")
			var original_scale := body.scale
			defense.start_swing()
			defense.advance(0.81)
			check(body.sprite_frames.get_meta("fist_preview_technique") == tech, "whole correct technique frame")
			defense.cancel_trial()
			check(visual.position.is_equal_approx(base_position) and body.scale == original_scale, "no accumulating distortion")
	check(progress.get_character_data() == initial, "no free points or campaign skill changes")
	reset("novice")
	defense.start_swing()
	defense.advance(0.5)
	sandbox.set_technique("trained")
	defense.advance(1.0)
	check(snapshot().contacts == 0 and snapshot().phase == "idle", "technique switch cancels pending swing")
	defense.start_swing()
	defense.advance(0.4)
	var unchanged: Dictionary = snapshot().duplicate(true)
	sandbox.set_backpack_enabled(not sandbox.is_backpack_enabled())
	check(snapshot() == unchanged, "whole backpack variant swap preserves combat phase")
	check(sandbox.level.get_node_or_null("Persistence") == null, "no persistence after trials")
	group("whole frames, restored transforms, campaign isolation")
	finish()

func finish() -> void:
	if groups == 12 and errors.is_empty():
		print("ASHBOUND_FIST_DEFENSE_OK groups=12 signals=%d" % resolved_count)
		get_tree().quit(0)
	else:
		printerr("DEFENSE_INCOMPLETE groups=%d errors=%d" % [groups, errors.size()])
		get_tree().quit(1)
