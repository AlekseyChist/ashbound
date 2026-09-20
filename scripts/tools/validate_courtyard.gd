extends SceneTree
## Integration validation for first_courtyard.tscn (run: godot --headless -s res://scripts/tools/validate_courtyard.gd)

const SCENE := "res://scenes/courtyard/first_courtyard.tscn"
const WALK_EPS := 0.28
const WALK_MAX_FRAMES := 360

var level: Node3D
var player: CharacterBody3D
var fails: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await _load_scene()
	if level == null or player == null:
		_check(false, "scene load failed")
		await _finish()
		return
	await _frames(3)
	await _phase1_reset_and_negative()
	await _phase2_quest_route()
	await _phase3_combat()
	await _phase4_stale_attack_reset()
	await _phase5_speed_independence()
	await _phase6_collision_optional()
	await _finish()

func _load_scene() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		return
	level = packed.instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Actors/Player") as CharacterBody3D

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		printerr("[FAIL] " + msg)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func _state() -> int:
	return int(level.get("state"))

func _hits() -> int:
	return int(level.get("dummy_hits"))

func _reward() -> bool:
	return bool(level.get("reward_claimed"))

func _interact() -> void:
	player.request_interaction()
	await _frames(3)

func _attack() -> void:
	player.request_attack()
	await _frames(40)

func _walk_to(target: Vector2) -> bool:
	for i in WALK_MAX_FRAMES:
		var pos: Vector3 = player.global_position
		var delta: Vector2 = target - Vector2(pos.x, pos.z)
		if delta.length() < WALK_EPS:
			player.stop_input()
			await _frames(2)
			return true
		player.set_move_input(delta.normalized())
		await physics_frame
	var pos: Vector3 = player.global_position
	_check(false, "walk_to failed at %s (target %s)" % [str(pos), str(target)])
	player.stop_input()
	return false

func _phase1_reset_and_negative() -> void:
	player.global_position = Vector3(-2.0, 0.1, 7.0)
	await _frames(3)
	await _interact()
	_check(_state() == 0, "spawn interact should keep state 0")
	# isolated negative teleports (allowed outside positive route)
	player.global_position = Vector3(-11.0, 0.1, 1.2)
	await _frames(3)
	await _interact()
	_check(_state() == 0, "woodpile approach before host should keep state 0")
	player.global_position = Vector3(7.0, 0.1, 0.0)
	await _frames(3)
	await _interact()
	_check(_state() == 0, "guard interact before job should keep state 0")
	level.reset_lesson()
	await _frames(3)

func _phase2_quest_route() -> void:
	if not await _walk_to(Vector2(-4.0, 2.0)):
		return
	if not await _walk_to(Vector2(-4.0, -2.7)):
		return
	if not await _walk_to(Vector2(-5.5, -2.0)):
		return
	await _interact()
	_check(_state() == 1, "after host state should be 1")
	_check(not _reward(), "reward must not be claimed yet")
	if not await _walk_to(Vector2(-11.0, 1.2)):
		return
	await _interact()
	_check(_state() == 2, "after woodpile state should be 2")
	if not await _walk_to(Vector2(-5.5, -2.0)):
		return
	await _interact()
	_check(_state() == 3, "after return to host state should be 3")
	_check(_reward(), "reward must be claimed at state 3")
	await _interact()
	_check(_state() == 3, "repeat interact must keep state 3")
	if not await _walk_to(Vector2(-4.0, -2.7)):
		return
	if not await _walk_to(Vector2(4.0, -2.7)):
		return
	if not await _walk_to(Vector2(7.0, 0.0)):
		return
	await _interact()
	_check(_state() == 4, "after guard state should be 4")

func _phase3_combat() -> void:
	await _attack()
	var dist: float = player.global_position.distance_to(Vector3(5.7, 0.1, 3.0))
	_check(_hits() == 0, "attack out of range must not hit (dist %f)" % dist)
	if not await _walk_to(Vector2(5.7, 3.0)):
		return
	player.facing_direction = Vector3.LEFT
	await _frames(3)
	await _attack()
	_check(_hits() == 0, "wrong facing must not hit")
	player.facing_direction = Vector3.RIGHT
	await _frames(3)
	for i in 10:
		player.request_attack()
	await _frames(40)
	_check(_hits() == 1, "burst of 10 attacks same frame must hit exactly once (got %d)" % _hits())
	await _attack()
	await _attack()
	_check(_hits() == 3, "two more attacks should reach 3 hits (got %d)" % _hits())
	_check(_state() == 5, "after 3 hits state should be 5")
	await _attack()
	_check(_hits() == 3, "fourth attack must not add hit (got %d)" % _hits())
	_check(_state() == 5, "state must stay 5 after fourth attack")
	if not await _walk_to(Vector2(7.0, 0.0)):
		return
	await _interact()
	_check(_state() == 6, "after guard reward state should be 6")
	await _interact()
	_check(_state() == 6, "repeat interact must keep state 6")

func _phase4_stale_attack_reset() -> void:
	player.global_position = Vector3(5.7, 0.1, 3.0)
	await _frames(3)
	player.request_attack()
	level.reset_lesson()
	await _frames(40)
	_check(_hits() == 0, "stale attack after reset must not hit")
	_check(_state() == 0, "state must be 0 after stale attack reset")
	_check(not _reward(), "reward must not be claimed after stale attack reset")
	var spawn: Vector2 = Vector2(-2.0, 7.0)
	var ppos: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	_check((ppos - spawn).length() < 0.2, "player must be within 0.2 of spawn (-2,7) after reset (got %s)" % str(ppos))
	var vel_xz: Vector2 = Vector2(player.velocity.x, player.velocity.z)
	_check(vel_xz.length() < 0.05, "velocity XZ must be near zero after reset (got %s)" % str(vel_xz))

func _phase5_speed_independence() -> void:
	var d1: float = await _measure_walk_distance(5)
	var d2: float = await _measure_walk_distance(15)
	player.walk_pose_fps = 15
	print("[INFO] walk distances: fps5=%.3f fps15=%.3f" % [d1, d2])
	_check(d1 > 3.0, "fps5 distance must exceed 3.0 (got %.3f)" % d1)
	_check(d2 > 3.0, "fps15 distance must exceed 3.0 (got %.3f)" % d2)
	_check(absf(d1 - d2) < 0.1, "distances must match within 0.1 (diff %.3f)" % absf(d1 - d2))

func _measure_walk_distance(fps: int) -> float:
	player.global_position = Vector3(-8.0, 0.1, 8.0)
	player.stop_input()
	player.velocity = Vector3.ZERO
	await _frames(3)
	var start: Vector3 = player.global_position
	player.walk_pose_fps = fps
	player.set_move_input(Vector2.RIGHT)
	await _frames(60)
	player.stop_input()
	var end: Vector3 = player.global_position
	return Vector2(end.x - start.x, end.z - start.z).length()

func _phase6_collision_optional() -> void:
	if fails.size() > 0:
		return
	player.global_position = Vector3(-8.0, 0.1, -4.0)
	player.stop_input()
	player.velocity = Vector3.ZERO
	await _frames(3)
	player.set_move_input(Vector2.UP)
	await _frames(60)
	player.stop_input()
	var z: float = player.global_position.z
	_check(z > -5.1, "player must not pass house front (z=%.3f)" % z)

func _finish() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
	await process_frame
	await process_frame
	if fails.is_empty():
		print("ASHBOUND_COURTYARD_OK")
		quit(0)
	else:
		printerr("ASHBOUND_COURTYARD_FAIL (%d)" % fails.size())
		quit(1)
