extends Node
## TAVERN-01B (D-089): the forest inn in the world. It replaces the grey landmark at forest_inn,
## stands on a level pad at the trail's height, its door works with the action button, and the
## hero walks from the trail end through the door into the common room. The village keeps its
## three yards (the house picker and the yard checks are not affected).
const Scene = preload("res://scenes/world/world.tscn")
var world: Node3D
var inn: Node3D
var failures: Array[String] = []
var checks := 0

func _ready() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("INN_FAIL ", label)

func settle(seconds: float = .3) -> void:
	await get_tree().create_timer(seconds, false, true).timeout

func drive(goal: Vector3, seconds: float, near := .6) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		var offset: Vector3 = goal - world.player.global_position
		offset.y = 0
		if offset.length() < near: break
		var camera: Camera3D = world.camera_rig.get_camera()
		var right := camera.global_basis.x; right.y = 0; right = right.normalized()
		var back := camera.global_basis.z; back.y = 0; back = back.normalized()
		world.player.set_move_input(Vector2(offset.normalized().dot(right), offset.normalized().dot(back)))
		await get_tree().physics_frame
	world.player.stop_input()
	var rest: Vector3 = goal - world.player.global_position
	rest.y = 0
	return rest.length() < near + .5

func run() -> void:
	world = Scene.instantiate()
	add_child(world)
	await settle(.8)
	inn = world.inn
	check(inn != null and inn.record.id == "T02A", "the forest inn is built")
	check(world.world_root.get_node_or_null("forest_inn") == null, "the grey landmark is gone")
	check(world.buildings.size() == 3 and not world.buildings.has(inn), "the village keeps its three yards")
	check(inn.door != null and not inn.door.leaves.is_empty(), "the inn door has its leaves")
	# Level pad: the grid is flat under the whole footprint, at the floor's base.
	var worst := 0.0
	for corner in [Vector3(-4.7, 0, -7.7), Vector3(4.7, 0, -7.7), Vector3(-4.7, 0, 9.4), Vector3(4.7, 0, 9.4), Vector3.ZERO]:
		var at: Vector3 = inn.global_transform * corner - world.world_root.global_position
		worst = maxf(worst, absf(world.world_ground(at.x, at.z) + world.world_root.global_position.y - inn.global_position.y))
	check(worst < .05, "level ground under the inn (worst %.3f m)" % worst)
	# From the trail end to the door.
	var outside: Vector3 = inn.to_global(Vector3(0, 0, 11.5))
	world.player.global_position = outside + Vector3.UP * .5
	world.player.velocity = Vector3.ZERO
	await settle(.5)
	check(absf(world.player.global_position.y - inn.global_position.y) < .5, "the trail end is level with the inn (%.2f m)" % (world.player.global_position.y - inn.global_position.y))
	world.camera_rig._yaw = inn.rotation.y
	world.camera_rig._apply_rotation()
	world.camera_rig.snap_to_target()
	check(await drive(inn.to_global(Vector3(0, 0, 9.0)), 6.0), "walks up to the door")
	world._update_prompt()
	check(world.current_door == inn.door and not world.interact_button.disabled, "the action button offers the inn door")
	world.interact()
	await settle(1.2)
	check(inn.door.fraction > .9, "the door opens")
	check(await drive(inn.to_global(Vector3(0, .4, 4.5)), 8.0), "walks through the door into the hall")
	check(inn.contains(world.player.global_position), "the hero is inside the inn")
	check(world.player.global_position.y > inn.global_position.y + .2, "stands on the floor, not under it")
	# The counter and tables are solid.
	check(await drive(inn.to_global(Vector3(2.7, .4, 0.2)), 3.0, .3) == false, "the counter blocks the way")
	print("FOREST_INN_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
