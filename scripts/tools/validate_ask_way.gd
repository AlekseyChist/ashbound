extends Node
## ASK-WAY-01: exercise the real world/menu, with a separate user directory supplied by QA.
const Scene = preload("res://scenes/world/world.tscn")
const SAVE := "user://ask_way_qa.cfg"
const EXPECTED := [
	["ASK_WAY_HERE", "ASK_WAY_HOST"], ["ASK_WAY_WOOD", "ASK_WAY_WOOD"],
	["ASK_WAY_HERE", "ASK_WAY_RETURN"], ["ASK_WAY_GUARD", "ASK_WAY_HERE"],
	["ASK_WAY_DUMMY", "ASK_WAY_DUMMY"], ["ASK_WAY_REPORT", "ASK_WAY_HERE"],
	["ASK_WAY_WOLVES", "ASK_WAY_WOLVES"], ["ASK_WAY_PAYMENT", "ASK_WAY_HERE"],
	["ASK_WAY_INN", "ASK_WAY_INN"],
]
var world: Node3D
var lesson: Node3D
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("ASK_WAY_FAIL ", label)

func settle() -> void:
	await get_tree().create_timer(.12, true).timeout

func snapshot() -> Dictionary:
	return {"stage": lesson.quest.stage_index, "flags": lesson.quest.flags.duplicate(true),
		"counters": lesson.quest.counters.duplicate(true), "gold": get_node("/root/Inventory").gold,
		"save": FileAccess.get_file_as_bytes(SAVE)}

func open_at(point: Node3D) -> void:
	world.player.global_position = point.global_position + Vector3(1.6, .1, 0)
	world.player.velocity = Vector3.ZERO
	world.player.stop_input()
	await settle()
	world.interact()
	await settle()
	check(world.choices.is_open, "%s opens choices" % point.name)

func button(id: String) -> void:
	var answer: Button = world.choices.list.get_node_or_null("Answer_" + id)
	check(answer != null, "button exists: " + id)
	if answer != null:
		answer.pressed.emit()

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event.pressed = false
	Input.parse_input_event(event)

func run_checks() -> void:
	world = Scene.instantiate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	await settle()
	lesson = world.lesson
	lesson.use_save(SAVE)
	lesson.quest.reset()
	world.select_building(0)
	for language in ["en", "ru"]:
		check(Localization.set_language(language) == OK, "language " + language)
		for stage in 9:
			lesson.quest.stage_index = stage
			lesson.quest.flags[&"reward_claimed"] = stage >= 3
			lesson.quest.counters[&"dummy_hits"] = 3 if stage >= 5 else 0
			lesson.save_progress()
			for person in 2:
				var point: Node3D = [lesson.hostess, lesson.watchman][person]
				var before := snapshot()
				await open_at(point)
				check(not world.is_input_available(), "menu owns movement input")
				world.interact()
				lesson.interact(point)
				check(world.choices.list.get_child_count() == 3, "reentry keeps three answers")
				button("lesson_way")
				var expected: String = EXPECTED[stage][person]
				check(world.hud._message_key == expected, "%s stage %d NPC %d hint" % [language, stage, person])
				check(Localization.text(expected) != expected, "translated hint " + expected)
				check(snapshot() == before, "directions leave quest, purse and save unchanged")
				check(world.is_input_available() and not world.choices.is_open, "answer restores input")
				world.choices.choose(&"lesson_business")
				check(snapshot() == before, "late duplicate answer has no effect")
	lesson.quest.reset()
	lesson.save_progress()
	var before := snapshot()
	await open_at(lesson.hostess)
	button("lesson_leave")
	check(snapshot() == before and world.is_input_available(), "leave cancels")
	await open_at(lesson.hostess)
	await key(KEY_ESCAPE)
	check(snapshot() == before and world.is_input_available(), "Escape cancels")
	await open_at(lesson.hostess)
	world.choices.choose(&"invalid")
	check(snapshot() == before and world.is_input_available(), "unknown answer does no work")
	await open_at(lesson.hostess)
	Localization.set_language("en")
	check(world.choices.list.get_node("Answer_lesson_way").text == "2. Ask the way", "open menu changes to English")
	Localization.set_language("ru")
	check(world.choices.list.get_node("Answer_lesson_way").text == "2. Спросить дорогу", "open menu changes to Russian")
	get_tree().paused = true
	await key(KEY_1)
	check(snapshot() == before and world.choices.is_open, "paused keys do not accept the job")
	get_tree().paused = false
	await key(KEY_ESCAPE)
	check(world.is_input_available(), "resume and cancel restores input")
	await open_at(lesson.hostess)
	world.player.global_position += Vector3(8, 0, 0)
	await settle()
	check(snapshot() == before and world.is_input_available(), "moving away cancels without effects")
	await open_at(lesson.hostess)
	await key(KEY_1)
	check(lesson.quest.stage_index == 1, "business accepts the original firewood job")
	world.choices.choose(&"lesson_business")
	check(lesson.quest.stage_index == 1, "business cannot fire twice")
	await open_at(lesson.watchman)
	lesson.watchman.queue_free()
	await settle()
	check(not world.choices.is_open and world.is_input_available(), "removed NPC releases input")
	# The shared menu is also used by the inn. Our listener must not survive an exchange.
	world.choices.open("INN_KEEPER_NAME", "INN_KEEPER_ASK", [[&"leave", "Leave"]])
	world.choices.choose(&"leave")
	check(lesson.quest.stage_index == 1, "unrelated menu does not change the lesson")
	await open_at(lesson.hostess)
	world.queue_free()
	await settle()
	check(not is_instance_valid(world), "world can close while waiting for an answer")
	print("ASK_WAY_CHECKS checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
