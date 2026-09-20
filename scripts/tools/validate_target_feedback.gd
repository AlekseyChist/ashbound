extends SceneTree

var failures: Array[String] = []
var strikes := 0
var level: Node
var player: CharacterBody3D
var host: Node3D
var guard: Node3D
var host_body: AnimatedSprite3D
var base_color: Color
var interaction_focus: Node
var attack_focus: Node
var interaction_ring: MeshInstance3D
var attack_ring: MeshInstance3D
var interaction_mat: StandardMaterial3D
var attack_mat: StandardMaterial3D
var dummy: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	var scene: PackedScene = load("res://scenes/courtyard/first_courtyard.tscn")
	root.size = Vector2i(1920, 1080)
	level = scene.instantiate()
	root.add_child(level)
	await frames(3)
	await physics_frame
	await physics_frame
	await physics_frame
	player = level.get_node("Actors/Player")
	host = level.get_node("Actors/Innkeeper")
	guard = level.get_node("Actors/Watchman")
	host_body = host.get_node("Body")
	base_color = host_body.modulate
	interaction_focus = level.get_node("InteractionFocus")
	attack_focus = level.get_node("AttackFocus")
	interaction_ring = interaction_focus.get_node("Ring")
	attack_ring = attack_focus.get_node("Ring")
	interaction_mat = interaction_ring.material_override
	attack_mat = attack_ring.material_override

	# 1. Spawn: no targets, rings hidden.
	check(interaction_focus.get_target() == null, "spawn: interaction target not null")
	check(attack_focus.get_target() == null, "spawn: attack target not null")
	check(not interaction_ring.visible, "spawn: interaction ring visible")
	check(not attack_ring.visible, "spawn: attack ring visible")

	# 2. Approach host: highlight + E prompt.
	player.global_position = Vector3(-5.5, 0.1, -2)
	player.stop_input()
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	check(interaction_focus.get_target() == host, "approach: interaction target != host")
	check(interaction_ring.visible, "approach: ring not visible")
	check(host_body.modulate != base_color, "approach: body modulate unchanged")
	check(interaction_mat.no_depth_test == false, "approach: ring no_depth_test true")
	player.request_interaction()
	await physics_frame
	await physics_frame
	await physics_frame
	check(level.state == 1, "approach: level.state != 1 after E")

	# 3. Walk away: target cleared, host restored.
	player.global_position = Vector3(0.0, 0.1, 7.0)
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	check(interaction_focus.get_target() == null, "walkaway: interaction target not null")
	check(not interaction_ring.visible, "walkaway: ring still visible")
	check(host_body.modulate == base_color, "walkaway: host modulate not restored")

	# 4. Blocked LOS.
	player.global_position = Vector3(-5.5, 0.1, -2)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 3.0, 0.2)
	shape_node.shape = box
	shape_node.position = Vector3(-5.75, 1.5, -2.75)
	wall.add_child(shape_node)
	level.add_child(wall)
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	check(interaction_focus.get_target() == null, "blocked: target not null")
	check(host_body.modulate == base_color, "blocked: host modulate not restored")
	wall.queue_free()
	await physics_frame
	await physics_frame
	await physics_frame
	check(interaction_focus.get_target() == host, "unblocked: host not selected again")

	# 5. Guard in range.
	player.global_position = Vector3(7.0, 0.1, 0.0)
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	check(interaction_focus.get_target() == guard, "guard: interaction target != guard")
	check(host_body.modulate == base_color, "guard: host modulate not restored")

	# 6. PRACTICE attack on dummy.
	level._apply_state(4)
	player.global_position = Vector3(5.7, 0.1, 3.0)
	player.facing_direction = Vector3.RIGHT
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	dummy = level.get_node("Environment/Props/Dummy")
	check(attack_focus.get_target() == dummy, "practice: attack target != dummy")
	check(attack_mat.albedo_color == attack_focus.attack_color, "practice: ring color != attack_color")
	check(attack_mat.albedo_color != attack_focus.interaction_color, "practice: ring color == interaction_color")
	player.facing_direction = Vector3.LEFT
	await physics_frame
	await physics_frame
	await physics_frame
	check(attack_focus.get_target() == null, "facing left: attack target not null")
	check(not attack_ring.visible, "facing left: red ring still visible")
	player.facing_direction = Vector3.RIGHT
	var wall2 := StaticBody3D.new()
	wall2.collision_layer = 1
	wall2.collision_mask = 0
	var shape2 := CollisionShape3D.new()
	var box2 := BoxShape3D.new()
	box2.size = Vector3(0.1, 3.0, 2.0)
	shape2.shape = box2
	shape2.position = Vector3(6.4, 1.5, 3.0)
	wall2.add_child(shape2)
	level.add_child(wall2)
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	check(attack_focus.get_target() == null, "wall: attack target not null")
	wall2.queue_free()
	await physics_frame
	await physics_frame
	await physics_frame
	check(attack_focus.get_target() == dummy, "unblocked: dummy not selected again")

	# 7. Air attack at spawn: strikes increment, no dummy hits.
	player.global_position = Vector3(-2.0, 0.1, 7.0)
	player.stop_input()
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	await physics_frame
	player.strike_requested.connect(_on_strike_requested)
	player.request_attack()
	await physics_frame
	await physics_frame
	await physics_frame
	check(player._attack_active == true, "air attack: _attack_active false")
	await frames(30)
	check(strikes == 1, "air attack: strikes != 1 (got %d)" % strikes)
	check(level.dummy_hits == 0, "air attack: dummy_hits != 0 (got %d)" % level.dummy_hits)

	# 8. Reset lesson and cleanup.
	level.reset_lesson()
	check(interaction_focus.get_target() == null, "reset: interaction target not null")
	check(attack_focus.get_target() == null, "reset: attack target not null")
	check(not interaction_ring.visible, "reset: interaction ring visible")
	check(not attack_ring.visible, "reset: attack ring visible")
	check(host_body.modulate == base_color, "reset: host modulate not original")
	level.queue_free()
	for i in 2:
		await process_frame
	if failures.is_empty():
		print("ASHBOUND_TARGET_FEEDBACK_OK")
		quit(0)
	else:
		for f in failures:
			printerr(f)
		quit(1)

func _on_strike_requested() -> void:
	strikes += 1
