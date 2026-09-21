## Localization changes only presentation, including already open dialogue.
extends SceneTree

const SCENE := "res://scenes/courtyard/first_courtyard.tscn"
var loc: Node
var level: Node3D
var hud: Node
var player: CharacterBody3D
var fixture: Dictionary = {}
var failures: Array[String] = []
var completed := 0
var settings_path: String

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	loc = root.get_node("Localization")
	settings_path = "res://.tools/courtyard-locale-qa-%d.cfg" % OS.get_process_id()
	loc.load_preferences(settings_path, "ru_RU")
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://scripts/tools/fixtures/courtyard_localization.json")):
		fixture[entry.key] = entry
	level = load(SCENE).instantiate()
	hud = level.get_node("HUD")
	hud.force_touch_controls = true
	root.add_child(level)
	current_scene = level
	player = level.get_node("Actors/Player")
	await _frames(4)
	_initial_and_labels()
	await _open_dialogue()
	await _wood_and_reward()
	await _practice_and_controls()
	await _focus_prompts()
	await _retained_parameters()
	await _all_dialogue_branches()
	await _all_objectives()
	await _capture_profiles()
	_check(completed == 8, "all eight groups complete")
	level.queue_free()
	await process_frame
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if failures.is_empty():
		print("ASHBOUND_COURTYARD_LOCALIZATION_OK groups=8")
		quit(0)
	else:
		for failure in failures:
			printerr("COURTYARD_LOCALIZATION_FAIL: " + failure)
		printerr("ASHBOUND_COURTYARD_LOCALIZATION_FAILED groups=%d failures=%d" % [completed, failures.size()])
		quit(1)

func _check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func _label(path: String) -> String:
	return str(hud.get_node("RootControl/" + path).text)

func _expected(key: String) -> String:
	return fixture[key][loc.get_language()]

func _talk_near(path: String) -> void:
	# Dialogue now closes on departure. Keep the presentation fixture within
	# conversation range instead of triggering a remote NPC from the spawn.
	var point:Node3D=level.get_node(path)
	player.global_position=point.global_position+Vector3(0,0.1,1.5)
	player.velocity=Vector3.ZERO
	point.interact()

func _presentation_snapshot() -> Dictionary:
	return {"state": level.state, "hits": level.dummy_hits, "reward": level.reward_claimed,
		"message_visible": hud._message_visible, "wood_visible": level.get_node("Interactions/Woodpile/Label3D").visible,
		"run": hud._run_enabled, "touch_run": player._touch_run,
		"inventory": root.get_node("Inventory").get_save_data()}

func _switch(language: String) -> void:
	var before := _presentation_snapshot()
	_check(loc.set_language(language) == OK, "language selection persisted to QA path")
	await _frames(2)
	_check(_presentation_snapshot() == before, "translation changes no game/control/visibility state")

func _assert_labels() -> void:
	_check(_label("TopLeftPanel/VBox/SubtitleLabel") == _expected("COURTYARD_TITLE"), "courtyard title translated")
	_check(_label("TopRightPanel/RestartButton") == _expected("UI_RESTART"), "restart translated")
	_check(level.get_node("Actors/Innkeeper/NameLabel").text == _expected("COURTYARD_NAME_INNKEEPER"), "innkeeper label translated")
	_check(level.get_node("Actors/Watchman/NameLabel").text == _expected("COURTYARD_NAME_WATCHMAN"), "watchman label translated")
	_check(level.get_node("Interactions/Woodpile/Label3D").text == _expected("COURTYARD_NAME_WOODPILE"), "wood label translated")
	_check(_label("BottomLeft/LegendLabel") == _expected("COURTYARD_LEGEND_TOUCH"), "touch legend translated")

func _initial_and_labels() -> void:
	_assert_labels()
	_check(_label("TopLeftPanel/VBox/ObjectiveLabel") == _expected("COURTYARD_OBJECTIVE_MEET_HOST"), "initial objective")
	completed += 1

func _open_dialogue() -> void:
	_talk_near("Actors/Innkeeper")
	_check(level.state == 1 and hud._message_visible, "job dialogue opened")
	for language in ["en", "ru", "en"]:
		await _switch(language)
		_assert_labels()
		_check(_label("MessagePanel/VBox/SpeakerLabel") == _expected("COURTYARD_NAME_INNKEEPER"), "open speaker translated")
		_check(_label("MessagePanel/VBox/MessageText") == _expected("COURTYARD_DIALOGUE_HOST_JOB"), "same open line retranslated")
		_check(_label("TopLeftPanel/VBox/ObjectiveLabel") == _expected("COURTYARD_OBJECTIVE_FETCH_WOOD"), "ongoing objective translated")
	completed += 1

func _wood_and_reward() -> void:
	_talk_near("Interactions/Woodpile")
	_check(level.state == 2 and not level.get_node("Interactions/Woodpile/Label3D").visible, "wood collected")
	await _switch("ru")
	_check(_label("MessagePanel/VBox/SpeakerLabel").is_empty(), "narration has no invented speaker")
	_check(_label("MessagePanel/VBox/MessageText") == _expected("COURTYARD_DIALOGUE_WOOD_TAKEN"), "collection text translated")
	_talk_near("Actors/Innkeeper")
	_check(level.state == 3 and level.reward_claimed, "reward stage reached")
	await _switch("en")
	_check(_label("MessagePanel/VBox/MessageText") == _expected("COURTYARD_DIALOGUE_HOST_REWARD"), "reward dialogue retained")
	hud.clear_message()
	await _switch("ru")
	_check(not hud.get_node("RootControl/MessagePanel").visible, "closed message stays closed")
	_talk_near("Actors/Innkeeper")
	_check(level.state == 3 and level.reward_claimed, "repeated host interaction does not repeat reward")
	completed += 1

func _practice_and_controls() -> void:
	_talk_near("Actors/Watchman")
	_check(level.state == 4, "training begins")
	# Arrange a partial-count fixture; actual strikes are covered by the physical route test.
	level.dummy_hits = 1
	level._apply_state(4)
	hud._set_run_mode(true, true)
	for language in ["en", "ru"]:
		await _switch(language)
		var wanted := _expected("COURTYARD_OBJECTIVE_PRACTICE").replace("{hits}", "1").replace("{total}", "3")
		_check(_label("TopLeftPanel/VBox/ObjectiveLabel") == wanted, "partial hit count survives language refresh")
		_check(_label("BottomRight/VBox/RunButton") == ("Run" if language == "en" else "Бег"), "active run mode text")
		_check(_label("MessagePanel/VBox/MessageText") == _expected("COURTYARD_DIALOGUE_GUARD_LESSON"), "watchman line translated")
	hud.reset_controls()
	await _switch("en")
	_check(_label("BottomRight/VBox/RunButton") == "Walk", "idle walk mode text")
	completed += 1

func _focus_prompts() -> void:
	player.global_position = Vector3(-4.8, 0.1, -3.5)
	await _frames(4)
	for language in ["en", "ru"]:
		await _switch(language)
		var wanted := _expected("COURTYARD_FOCUS_INTERACT_TOUCH").replace("{action}", _expected("COURTYARD_ACTION_TALK")).replace("{name}", _expected("COURTYARD_NAME_INNKEEPER"))
		_check(_label("PromptLabel") == wanted, "same nearby target prompt translated")
	var dummy: Node3D = level._get_dummy()
	player.global_position = dummy.global_position + Vector3(0, 0.1, 1.2)
	player.facing_direction = Vector3.FORWARD
	await _frames(4)
	for language in ["en", "ru"]:
		await _switch(language)
		_check(_label("PromptLabel").contains(_expected("COURTYARD_NAME_DUMMY")), "eligible attack target translated")
	completed += 1

func _retained_parameters() -> void:
	var parameters := {"hits": 2, "total": 3}
	hud.show_message("", "COURTYARD_OBJECTIVE_PRACTICE", parameters)
	parameters["hits"] = 99
	await _switch("en")
	_check(_label("MessagePanel/VBox/MessageText").ends_with("(2/3)"), "HUD owns message parameter snapshot")
	hud.clear_message()
	await _switch("ru")
	_check(not hud._message_visible, "parameter refresh cannot reopen message")
	completed += 1

func _capture_profiles() -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	if DisplayServer.get_name() == "headless":
		_check(false, "capture requires rendering")
		return
	for touch in [false, true]:
		level.queue_free()
		await process_frame
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1920, 1080) if not touch else Vector2i(2340, 1080)
		level = load(SCENE).instantiate()
		hud = level.get_node("HUD")
		hud.force_touch_controls = touch
		root.add_child(level)
		current_scene = level
		player = level.get_node("Actors/Player")
		await _frames(8)
		_talk_near("Actors/Innkeeper")
		_talk_near("Interactions/Woodpile")
		_talk_near("Actors/Innkeeper")
		for language in ["en", "ru"]:
			await _switch(language)
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var file := "res://.tools/courtyard-localization-%s-%s.png" % ["touch" if touch else "pc", language]
			_check(image.save_png(file) == OK, "capture saved " + file)
			var message: Control = hud.get_node("RootControl/MessagePanel")
			var text: Label = hud.get_node("RootControl/MessagePanel/VBox/MessageText")
			_check(message.get_global_rect().encloses(text.get_global_rect()), "dialogue text remains in panel")
			_check(text.get_visible_line_count() >= text.get_line_count(), "long dialogue not vertically clipped")

func _all_dialogue_branches() -> void:
	var cases := [
		["Actors/Innkeeper", 0, false, "COURTYARD_DIALOGUE_HOST_JOB"],
		["Actors/Innkeeper", 2, false, "COURTYARD_DIALOGUE_HOST_REWARD"],
		["Actors/Innkeeper", 2, true, "COURTYARD_DIALOGUE_HOST_ACCEPTED"],
		["Actors/Innkeeper", 1, false, "COURTYARD_DIALOGUE_HOST_REMIND"],
		["Actors/Innkeeper", 6, true, "COURTYARD_DIALOGUE_HOST_AFTER"],
		["Interactions/Woodpile", 1, false, "COURTYARD_DIALOGUE_WOOD_TAKEN"],
		["Interactions/Woodpile", 0, false, "COURTYARD_DIALOGUE_WOOD_BEFORE"],
		["Interactions/Woodpile", 6, true, "COURTYARD_DIALOGUE_WOOD_ALREADY"],
		["Actors/Watchman", 3, true, "COURTYARD_DIALOGUE_GUARD_LESSON"],
		["Actors/Watchman", 5, true, "COURTYARD_DIALOGUE_GUARD_REPORT"],
		["Actors/Watchman", 4, true, "COURTYARD_DIALOGUE_GUARD_REMIND"],
		["Actors/Watchman", 0, false, "COURTYARD_DIALOGUE_GUARD_OTHER"],
	]
	for test_case in cases:
		level.reset_lesson()
		level.state = test_case[1]
		level.reward_claimed = test_case[2]
		_talk_near(test_case[0])
		for language in ["en", "ru"]:
			await _switch(language)
			_check(_label("MessagePanel/VBox/MessageText") == _expected(test_case[3]), "dialogue branch " + test_case[3] + " " + language)
	completed += 1

func _all_objectives() -> void:
	var keys := ["COURTYARD_OBJECTIVE_MEET_HOST", "COURTYARD_OBJECTIVE_FETCH_WOOD", "COURTYARD_OBJECTIVE_RETURN_WOOD", "COURTYARD_OBJECTIVE_MEET_GUARD", "COURTYARD_OBJECTIVE_PRACTICE", "COURTYARD_OBJECTIVE_REPORT", "COURTYARD_OBJECTIVE_DONE"]
	level.reset_lesson()
	level.dummy_hits = 2
	for state in range(7):
		level._apply_state(state)
		for language in ["en", "ru"]:
			await _switch(language)
			var expected := _expected(keys[state]).replace("{hits}", "2").replace("{total}", "3")
			_check(_label("TopLeftPanel/VBox/ObjectiveLabel") == expected, "objective state %d %s" % [state, language])
	completed += 1
