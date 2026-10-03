extends SceneTree
## STEP-01 (owner 29 Sep): the hero walks up onto low ledges and down from them without jumping;
## a ledge higher than STEP_MAX stays a wall. A bare test floor, the real hero rig, no saves.
var rig: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print("STEP_", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func block(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = at
	body.add_child(shape)
	parent.add_child(body)

## Walks along +x from x=-2 to x=goal_x on the lane z; true when he got there. Tracks the top y.
func walk(z: float, goal_x: float, seconds: float) -> Dictionary:
	var player: CharacterBody3D = rig.player
	var top := -INF
	var jumped := false
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		var to := goal_x - player.global_position.x
		if absf(to) < 0.15:
			rig.player.stop_input()
			return {"arrived": true, "top": top, "jumped": jumped}
		# The camera looks along -z: right is +x.
		rig.player.set_move_input(Vector2(signf(to), 0.0))
		await physics_frame
		top = maxf(top, player.global_position.y)
		jumped = jumped or player._in_jump
	rig.player.stop_input()
	return {"arrived": false, "top": top, "jumped": jumped, "x": player.global_position.x}

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	block(scene, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	# Lanes 3 m apart, each a 2 m deep ledge from x=0 to x=2, then the floor again.
	var lanes := {0.15: -6.0, 0.3: -3.0, 0.38: 0.0, 0.5: 3.0}
	for h in lanes:
		block(scene, Vector3(1.0, h * 0.5, lanes[h]), Vector3(2.0, h, 1.4))
	rig = load("res://scenes/world/player_rig.tscn").instantiate()
	scene.add_child(rig)
	var cam: Camera3D = rig.camera_rig.get_camera()
	for h in lanes:
		var z: float = lanes[h]
		rig.player.global_position = Vector3(-2.0, 0.05, z)
		rig.player.velocity = Vector3.ZERO
		rig.camera_rig._yaw = 0.0
		rig.camera_rig._apply_rotation()
		rig.camera_rig.snap_to_target()
		for i in 10:
			await physics_frame
		var up: Dictionary = await walk(z, 1.0, 4.0)
		if h <= rig.player.STEP_MAX:
			check(up.arrived and absf(float(up.top) - h) < 0.08, "walks up onto the %.2f m ledge (top %.3f)" % [h, up.top])
			check(not up.jumped, "no jump onto the %.2f m ledge" % h)
			var down: Dictionary = await walk(z, 3.5, 4.0)
			check(down.arrived and absf(rig.player.global_position.y) < 0.08, "walks down off the %.2f m ledge (y %.3f)" % [h, rig.player.global_position.y])
		else:
			check(not up.arrived and float(up.top) < 0.1, "the %.2f m ledge stays a wall (x %.2f, top %.3f)" % [h, up.get("x", 0.0), up.top])
	# Walking along the foot of a wall does not lift him.
	rig.player.global_position = Vector3(-2.0, 0.05, 3.0 - 1.1)
	for i in 10:
		await physics_frame
	var beside: Dictionary = await walk(3.0 - 1.1, 3.0, 4.0)
	check(beside.arrived and float(beside.top) < 0.1, "walking beside the high ledge stays on the floor (top %.3f)" % beside.top)
	print("STEP_UP checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
