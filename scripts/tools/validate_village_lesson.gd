extends Node
## PLAYER-WORLD-01C (D-085): the courtyard lesson in the village on the world map.
## Real walks between the hostess, the woodpile, the watchman and the dummy; the action button,
## strikes, the journal for the pocket menu, and saved progress (own QA file).
const Scene = preload("res://scenes/world/world.tscn")
const SAVE := "user://world_lesson_qa.cfg"
var world: Node3D
var lesson: Node3D
var failures: Array[String] = []
var checks := 0

func _ready() -> void: call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("LESSON_FAIL ", label)

func settle(seconds: float = .25) -> void:
	await get_tree().create_timer(seconds, false, true).timeout

func plan(point: Vector2) -> Vector3:
	var local := point - Vector2(95, 95)
	return Vector3(local.x, world.terrain.height_at(local.x, local.y), local.y)

func drive(goal: Vector3, seconds: float, near := .9) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000 / Engine.time_scale)
	world.player.set_run_input(true)
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
	return rest.length() < near + .6

func walk(label: String, route: Array, near := .9) -> void:
	for i in range(route.size()):
		var goal: Vector3 = route[i]
		var d := Vector2(goal.x - world.player.global_position.x, goal.z - world.player.global_position.z).length()
		if not await drive(goal, d / 3.0 + 5.0, near if i == route.size() - 1 else .9):
			check(false, "%s: stuck before point %d at %s" % [label, i, world.player.global_position.round()])
			return
	await settle(.2)

## Stand next to a lesson point and press the action button (the same path as the HUD / E key).
func talk(label: String, point: Node3D, route: Array, stage_after: int) -> void:
	await walk(label, route + [point.global_position], 1.5)
	world._update_prompt()
	check(lesson.nearest_point() == point, "%s: the hero can reach %s" % [label, point.name])
	check(not world.interact_button.disabled and world.interact_button.text == Localization.text(point.prompt), "%s: the action button offers %s" % [label, point.prompt])
	world.interact()
	await settle(.1)
	check(lesson.quest.stage_index == stage_after, "%s: stage %d (got %d)" % [label, stage_after, lesson.quest.stage_index])
	check(world.hud._message_visible, "%s: the line is shown" % label)

func strike() -> void:
	world.player.request_attack()
	await settle(.9)

func run_checks() -> void:
	Engine.max_physics_steps_per_frame = 16
	world = Scene.instantiate()
	add_child(world)
	await settle(.6)
	lesson = world.lesson
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	lesson.use_save(SAVE)
	world.select_building(0)
	world._update_prompt()
	check(lesson.quest.stage_index == 0, "a new lesson starts with the hostess")
	check(world.hud._objective_key == "COURTYARD_OBJECTIVE_MEET_HOST", "the objective is shown outside")
	var provider: Node = world.pocket.get_pocket_panel()._sections._journal_provider
	check(provider == world and world.get_journal_entry().id == "village_lesson", "the pocket menu reads the lesson journal")
	var hostess: Vector3 = lesson.hostess.global_position
	check(Vector2(hostess.x, hostess.z).distance_to(Vector2(world.player.global_position.x, world.player.global_position.z)) < 8.0, "the hostess stands by the start")
	Engine.time_scale = 3.0
	var to_street := [plan(Vector2(83.19, 97.63)), plan(Vector2(82.75, 82.5)), plan(Vector2(96.0, 85.5))]
	var back_home := [plan(Vector2(82.75, 82.5)), plan(Vector2(83.19, 97.63))]
	await talk("woodpile first", lesson.woodpile, to_street, 0)
	check(lesson.woodpile.get_node("Label3D").visible, "the woodpile label stays before the job")
	await talk("hostess job", lesson.hostess, back_home, 1)
	await talk("take wood", lesson.woodpile, to_street, 2)
	check(not lesson.woodpile.get_node("Label3D").visible, "taken wood hides the woodpile label")
	await talk("reward", lesson.hostess, back_home, 3)
	check(lesson.quest.flags[&"reward_claimed"], "the reward is remembered")
	var to_gate := [plan(Vector2(83.19, 97.63)), plan(Vector2(82.75, 82.5)), plan(Vector2(111.25, 88.75)), plan(Vector2(131.75, 79)), plan(Vector2(145.75, 56))]
	await talk("watchman lesson", lesson.watchman, to_gate, 4)
	check(Vector2(lesson.tower.global_position.x - lesson.watchman.global_position.x, lesson.tower.global_position.z - lesson.watchman.global_position.z).length() < 7.0, "the watchtower stands by the watchman")
	check(world.hud._objective_key == "COURTYARD_OBJECTIVE_PRACTICE" and world.hud._objective_params == {"hits": 0, "total": 3}, "practice objective with the count")
	await strike()
	check(lesson.quest.counters[&"dummy_hits"] == 0, "a strike away from the dummy does not count")
	var dummy: Vector3 = lesson.dummy.global_position
	await walk("to the dummy", [dummy + Vector3(-1.3, 0, 0)], .35)
	world.player.facing_direction = Vector3(1, 0, 0)
	for i in 3: await strike()
	check(lesson.quest.counters[&"dummy_hits"] == 3 and lesson.quest.stage_index == 5, "three strikes finish the practice (hits %d, stage %d)" % [lesson.quest.counters[&"dummy_hits"], lesson.quest.stage_index])
	await strike()
	check(lesson.quest.counters[&"dummy_hits"] == 3, "no strikes count after the practice")
	await talk("report", lesson.watchman, [], 6)
	check(world.get_journal_entry().completed, "the lesson is completed in the journal")
	check(world.player.get_node("Progression").get_character_data().guard_practice_completed, "the guard practice mark is set")
	Engine.time_scale = 1.0
	# Saved progress: a new world continues; a damaged file starts over.
	var saved := ConfigFile.new()
	check(saved.load(SAVE) == OK and saved.get_value("lesson", "stage") == 6, "progress is saved")
	world.queue_free()
	await settle(.3)
	world = Scene.instantiate()
	add_child(world)
	await settle(.6)
	lesson = world.lesson
	lesson.use_save(SAVE)
	check(lesson.quest.stage_index == 6 and not lesson.woodpile.get_node("Label3D").visible, "a new session continues the finished lesson")
	var broken := FileAccess.open(SAVE, FileAccess.WRITE)
	broken.store_string("[lesson]\nstage=\"broken\"\n")
	broken.close()
	lesson.use_save(SAVE)
	check(lesson.quest.stage_index == 0 and lesson.woodpile.get_node("Label3D").visible, "a damaged file starts the lesson over")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("VILLAGE_LESSON_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
