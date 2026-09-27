extends SceneTree
## Регрессионный сценарий: API внешнего вида CourtyardCharacterVisual в реальной сцене.
## Проверяет set_appearance_frames (атомарность, сохранение фазы/паузы, метаданные),
## замену спрайтов во время атаки, независимость инстансов и восстановление исходного вида.

var errors: Array[String] = []
var strikes: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(cond: bool, msg: String) -> void:
	if not cond:
		errors.append(msg)

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func on_strike() -> void:
	strikes += 1

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var level: Node = load("res://scenes/courtyard/first_courtyard.tscn").instantiate()
	root.add_child(level)
	await frames(12)

	var player: CharacterBody3D = level.get_node("Actors/Player")
	var visual: CourtyardCharacterVisual = player.get_node("Visual")
	var body: AnimatedSprite3D = player.get_node("Visual/Body")
	var rig: Node3D = level.get_node("CameraRig")

	# 1. Компонент подключён, игрок пробрасывает направление, стартовый idle_back.
	check(visual != null, "visual component missing")
	check(player.get_visual_direction() == &"back", "player does not forward visual direction")
	check(body.animation == "idle_back", "initial animation not idle_back")
	check(visual.get_visual_direction() == &"back", "initial visual direction not back")

	var original_frames: SpriteFrames = body.sprite_frames
	check(original_frames != null, "original sprite frames missing")
	var original_meta_back: float = float(original_frames.get_meta("pixel_size_back", 0.0))
	var original_meta_front: float = float(original_frames.get_meta("pixel_size_front", 0.0))
	var original_meta_side: float = float(original_frames.get_meta("pixel_size_side", 0.0))
	var original_baseline: int = int(original_frames.get_meta("baseline_offset_pixels", 0))

	# 2. Альтернативный фикстура: deep duplicate валидных SpriteFrames с изменёнными метаданными.
	var alt_frames: SpriteFrames = original_frames.duplicate(true) as SpriteFrames
	check(alt_frames != null and alt_frames != original_frames, "fixture duplicate failed")
	alt_frames.set_meta("pixel_size_back", 0.012)
	alt_frames.set_meta("pixel_size_front", 0.014)
	alt_frames.set_meta("pixel_size_side", 0.016)
	alt_frames.set_meta("baseline_offset_pixels", 96)

	# 3. Недействительные ресурсы отклоняются атомарно, ничего не меняется.
	var before_frame: int = body.frame
	var before_progress: float = body.frame_progress
	check(visual.set_appearance_frames(null) == false, "null frames accepted")
	check(body.sprite_frames == original_frames, "null swap changed resource")
	var incomplete: SpriteFrames = SpriteFrames.new()
	check(visual.set_appearance_frames(incomplete) == false, "incomplete frames accepted")
	check(body.sprite_frames == original_frames, "invalid swap changed resource")
	check(body.frame == before_frame and is_equal_approx(body.frame_progress, before_progress), "invalid swap changed phase")
	incomplete = null

	# 4. Успешная замена: пауза, дробный прогресс, сохранение кадра/прогресса/паузы, масштаб по метаданным.
	body.pause()
	body.set_frame_and_progress(1, 0.37)
	var paused_frame: int = body.frame
	var paused_progress: float = body.frame_progress
	check(visual.set_appearance_frames(alt_frames) == true, "valid swap rejected")
	check(body.sprite_frames == alt_frames, "swap did not apply resource")
	check(body.is_playing() == false, "paused state lost after swap")
	check(body.frame == paused_frame, "frame changed on view-only swap")
	check(is_equal_approx(body.frame_progress, paused_progress), "progress changed on view-only swap")
	check(is_equal_approx(body.pixel_size, 0.012), "back pixel size not applied")
	check(is_equal_approx(body.position.y, 96.0 * 0.012), "baseline offset not applied")
	check(is_equal_approx(float(original_frames.get_meta("pixel_size_back", 0.0)), original_meta_back), "original meta back mutated")
	check(is_equal_approx(float(original_frames.get_meta("pixel_size_front", 0.0)), original_meta_front), "original meta front mutated")
	check(is_equal_approx(float(original_frames.get_meta("pixel_size_side", 0.0)), original_meta_side), "original meta side mutated")
	check(int(original_frames.get_meta("baseline_offset_pixels", 0)) == original_baseline, "original baseline mutated")

	# 5. Замена во время реальной атаки: состояние боя и фаза не сбрасываются.
	body.play()
	player.request_attack()
	await frames(2)
	var attack_time_before: float = float(player._attack_time)
	var body_phase_before: float = float(body.frame) + body.frame_progress
	check(visual.set_appearance_frames(original_frames) == true, "swap during attack rejected")
	# Синхронные проверки сразу после вызова (без ожидания кадров).
	check(float(player._attack_time) == attack_time_before, "attack time reset by swap")
	check(bool(player._attack_active), "attack state reset by swap")
	var body_phase_after: float = float(body.frame) + body.frame_progress
	check(is_equal_approx(body_phase_after, body_phase_before), "visual phase reset by swap")
	check(body.sprite_frames == original_frames, "swap during attack did not restore resource")
	player.strike_requested.connect(on_strike)
	await frames(40)
	check(strikes == 1, "expected exactly one strike, got %d" % strikes)

	# 6. Поворот камеры во время атаки/замены не перезапускает бой; facing/flip корректны.
	player.request_attack()
	await frames(2)
	var time_before_turn: float = float(player._attack_time)
	rig.rotate_view(Vector2(PI / float(rig.mouse_sensitivity), 0.0))
	await frames(2)
	check(bool(player._attack_active), "camera turn restarted combat")
	check(float(player._attack_time) > time_before_turn, "attack time not advancing after turn")
	check(body.animation == "attack_front", "facing anim after turn wrong: " + String(body.animation))
	check(body.flip_h == false, "flip wrong for front view")
	check(is_equal_approx(body.pixel_size, original_meta_front), "view scale does not match metadata after turn")
	await frames(40)
	check(strikes == 2, "second attack did not strike once")

	# 7. Стартовая регрессия: внешний вид загружается до первого update_visual.
	var second_scene: PackedScene = load("res://scenes/courtyard/courtyard_player.tscn")
	var second_player: CharacterBody3D = second_scene.instantiate() as CharacterBody3D
	check(second_player != null, "second player scene failed to instantiate")
	var second_visual: CourtyardCharacterVisual = second_player.get_node("Visual") as CourtyardCharacterVisual
	var second_body: AnimatedSprite3D = second_player.get_node("Visual/Body") as AnimatedSprite3D
	check(second_visual != null and second_body != null, "second player Visual/Body missing")

	# 7a. Стартовая замена ДО добавления в дерево: отдельная валидная копия без
	# устаревших алиасов (idle/walk/attack), только 9 обязательных клипов.
	var startup_frames: SpriteFrames = alt_frames.duplicate(true) as SpriteFrames
	check(startup_frames != null and startup_frames != alt_frames, "startup fixture duplicate failed")
	for legacy_alias in ["idle", "walk", "attack"]:
		if startup_frames.has_animation(legacy_alias):
			startup_frames.remove_animation(legacy_alias)
	check(second_visual.set_appearance_frames(startup_frames) == true, "startup swap rejected before first update")
	check(second_body.sprite_frames == startup_frames, "startup swap did not apply frames")
	check(second_body.animation == "idle_back", "startup animation not idle_back")
	check(is_equal_approx(second_body.pixel_size, 0.012), "startup baseline scale wrong")
	check(is_equal_approx(second_body.position.y, 96.0 * 0.012), "startup baseline offset wrong")

	# 7b. Второй реальный игрок сохраняет исходные кадры при изменении первого.
	second_player.position = Vector3(500.0, 0.0, 500.0)
	root.add_child(second_player)
	# Отключаем физический колбэк второго игрока сразу после добавления в дерево:
	# вызов ДО add_child переопределяется начальной регистрацией обработки скрипта,
	# и второй игрок реально запускал физику на своей дальней позиции.
	second_player.set_physics_process(false)
	await frames(4)
	check(second_body.sprite_frames == startup_frames, "startup frames lost after entering tree")
	check(second_body.animation == "idle_back", "startup animation overwritten by autoplay after tree entry")
	check(is_equal_approx(second_body.pixel_size, 0.012), "startup scale lost after tree entry")
	print("autoplay diag: autoplay=%s animation=%s is_playing=%s" % [second_body.autoplay, second_body.animation, second_body.is_playing()])
	var expected_playing := second_body.autoplay != "" and second_body.is_playing()
	check(expected_playing, "startup autoplay state inconsistent with configured autoplay")
	check(second_visual.set_appearance_frames(original_frames) == true, "restore before independence check rejected")
	check(second_body.sprite_frames == original_frames, "second player does not share original frames")
	visual.set_appearance_frames(alt_frames)
	check(second_body.sprite_frames == original_frames, "first player swap mutated shared appearance")
	check(body.sprite_frames == alt_frames, "first player lost alternate frames")
	second_player.queue_free()
	await frames(2)

	# 9. Восстановление исходного вида и обычного idle/направления.
	check(visual.set_appearance_frames(original_frames) == true, "restore swap rejected")
	player.stop_input()
	level.reset_lesson()
	await frames(12)
	check(body.sprite_frames == original_frames, "original frames not restored")
	check(body.animation == "idle_back", "restored animation not idle_back")
	check(player.get_visual_direction() == &"back", "restored direction not back")
	check(is_equal_approx(body.pixel_size, original_meta_back), "restored pixel size wrong")

	# D-057: no backpack layer; one attack still emits exactly one strike.
	check(player.get_node_or_null("Visual/BackpackLayer") == null,"no backpack layer on the hero")
	var before_strikes := strikes
	player.request_attack()
	await frames(44)
	check(body.sprite_frames==original_frames,"appearance unchanged by the attack")
	check(strikes==before_strikes+1,"one attack emits exactly one strike")

	level.queue_free()
	await frames(2)
	if errors.is_empty():
		print("ASHBOUND_CHARACTER_VISUAL_OK")
		quit(0)
	else:
		for e in errors:
			push_error(e)
		quit(1)
