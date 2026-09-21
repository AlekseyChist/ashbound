class_name CourtyardCharacterVisual
extends Node3D
## Визуальная презентация 2D-персонажа двора: спрайт, вид, фазы.
## Отделена от движения/боевого состояния владельца (CourtyardPlayer).

const VIEW_HYSTERESIS := 0.08

signal inventory_access_finished()

var _current_action: StringName = &""
var _current_view: StringName = &"back"

# --- Pocket gesture state ---
var _pocket_active := false
var _pocket_finished := false
var _body_was_visible := true
var _body_was_playing := false


## Обновить визуал: действие (idle/walk/run/attack), направление взгляда, частота walk/run-позы.
func update_visual(action: StringName, facing_direction: Vector3, walk_pose_fps: int = 15, run_pose_fps: int = 15) -> void:
	var body: AnimatedSprite3D = $Body
	if body == null or body.sprite_frames == null:
		return

	var new_view := _resolve_view(facing_direction)

	# --- Pocket gesture active: обновляем только pocket view ---
	if _pocket_active:
		var pocket: AnimatedSprite3D = get_node_or_null("PocketPose") as AnimatedSprite3D
		if pocket != null and pocket.sprite_frames != null:
			var pocket_view_changed := new_view != _current_view
			if pocket_view_changed:
				_current_view = new_view
				_update_pocket_view(pocket, new_view)
		return

	var new_action := action
	var moving := new_action == &"walk" or new_action == &"run"

	var action_changed := new_action != _current_action
	var view_changed := new_view != _current_view

	if action_changed or view_changed:
		# Сохраняем фазу, чтобы смена вида не сбрасывала walk/run/attack
		var old_frame := body.frame
		var old_progress: float = body.frame_progress
		var was_playing := body.is_playing()
		var old_paused := not was_playing

		_current_action = new_action
		_current_view = new_view
		body.animation = _resolve_clip_name(body.sprite_frames, new_action, new_view)

		if action_changed:
			# Нормальная смена действия — старт с первого кадра
			body.frame = 0
			body.frame_progress = 0.0
			body.play()
		else:
			# Только смена вида — сохраняем фазу старого клипа
			var frame_count := body.sprite_frames.get_frame_count(body.animation)
			var clamped_frame: int = clampi(old_frame, 0, maxi(frame_count - 1, 0))
			body.set_frame_and_progress(clamped_frame, old_progress)
			if old_paused:
				body.pause()

	# Частота кадров: walk — walk_pose_fps, run — run_pose_fps, иначе 1.0
	var pose_fps := walk_pose_fps
	if new_action == &"run":
		pose_fps = run_pose_fps
	var target_scale := float(pose_fps) / 15.0 if moving else 1.0
	body.speed_scale = target_scale

	# Переворот спрайта: только для боковых видов (LEFT — flip_h)
	var flip := _current_view == &"left"
	if body.flip_h != flip:
		body.flip_h = flip

	_apply_sprite_scale(body)


## Текущее визуальное направление (front/back/left/right).
func _ready() -> void:
	# Камера обрабатывается на priority 0, рюкзак — на 10;
	# визуал героя должен обновляться после обоих.
	process_priority = 100
	# Тени-прокси создаются напрямую: _make_shadow_proxy добавляет детей
	# в этот Visual во время собственного _ready, а не в занятого родителя.
	_make_shadow_proxy($Body, "BodyShadow")
	_make_shadow_proxy($PocketPose, "PocketShadow")
	$Body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	$PocketPose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Инициализация ориентации по текущей камере.
	_process(0.0)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		# Поворачиваем весь Visual целиком (якорь — ноги, origin 0):
		# дети Body/PocketPose вращаются вокруг ног, сохраняя авторские
		# локальные смещения и пропорции на экране. Поворот отдельных
		# центров спрайтов сломал бы их взаимное расположение.
		# Без сглаживания (lerp/smooth): жёсткий basis камеры даёт
		# мгновенную, стабильную ориентацию без запаздывания/дрожания.
		global_basis = camera.global_basis.orthonormalized()
	# Тени-прокси синхронизируются всегда (даже без камеры):
	# только локальная позиция под актором, без pitch камеры.
	var body := $Body as AnimatedSprite3D
	var pocket := $PocketPose as AnimatedSprite3D
	if body != null:
		_sync_shadow(body, get_node_or_null("BodyShadow") as AnimatedSprite3D)
	if pocket != null:
		_sync_shadow(pocket, get_node_or_null("PocketShadow") as AnimatedSprite3D)
	# Кастомный depth-материал только для видимых Body/PocketPose;
	# тени оставляем со стандартным upright-материалом.
	if camera != null:
		if body != null:
			_sync_depth_material(body, camera)
		if pocket != null:
			_sync_depth_material(pocket, camera)


# Создаёт тень-прокси (только тень, FIXED_Y) как брата исходного спрайта.
func _make_shadow_proxy(source: AnimatedSprite3D, name: String) -> AnimatedSprite3D:
	# Тень — ребёнок этого Visual (не родителя): top_level=true сохраняет
	# её вертикальной (FIXED_Y billboard), но привязанной к актору.
	var shadow := AnimatedSprite3D.new()
	shadow.name = name
	shadow.top_level = true
	add_child(shadow)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	shadow.shaded = source.shaded
	shadow.alpha_cut = source.alpha_cut
	shadow.alpha_scissor_threshold = source.alpha_scissor_threshold
	shadow.texture_filter = source.texture_filter
	shadow.double_sided = source.double_sided
	return shadow


# Синхронизирует тень-прокси с исходным спрайтом (без независимого
# воспроизведения: только копирование состояния, локальная позиция).
func _sync_shadow(source: AnimatedSprite3D, shadow: AnimatedSprite3D) -> void:
	if shadow == null or source == null:
		return
	if shadow.sprite_frames != source.sprite_frames:
		shadow.sprite_frames = source.sprite_frames
	# Без явной анимации индексы кадров применяются к несуществующей
	# анимации по умолчанию.
	shadow.animation = source.animation
	# Явного свойства progress у AnimatedSprite3D нет — кадр и прогресс
	# задаются одним вызовом.
	shadow.set_frame_and_progress(source.frame, source.frame_progress)
	# Гарантированно останавливаем проигрывание: тень не должна
	# анимироваться самостоятельно, только зеркалить источник.
	shadow.pause()
	shadow.flip_h = source.flip_h
	shadow.flip_v = source.flip_v
	shadow.pixel_size = source.pixel_size
	shadow.offset = source.offset
	shadow.centered = source.centered
	shadow.visible = source.visible
	shadow.modulate = source.modulate
	shadow.axis = source.axis
	# Глобальная позиция: тень остаётся вертикальной под актором,
	# несмотря на вращение самого Visual.
	shadow.global_transform = get_parent().global_transform * Transform3D(Basis.IDENTITY, source.position)


## Текущее визуальное направление.
func _sync_depth_material(source: AnimatedSprite3D, camera: Camera3D) -> void:
	if source == null or camera == null:
		return
	var frames := source.sprite_frames
	if frames == null:
		return
	var anim := String(source.animation)
	if anim.is_empty() or not frames.has_animation(anim):
		return
	var frame := int(source.frame)
	if frame < 0 or frame >= frames.get_frame_count(anim):
		return
	var mat := source.material_override as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/character_depth.gdshader")
		source.material_override = mat
	var tex: Texture2D = frames.get_frame_texture(anim, frame)
	while tex is AtlasTexture:
		tex = (tex as AtlasTexture).atlas
	if tex == null:
		return
	mat.set_shader_parameter("texture_albedo", tex)
	mat.set_shader_parameter("foot_world", global_position)
	var upright := camera.global_basis.x
	upright.y = 0.0
	if upright.length_squared() < 1e-8:
		upright = Vector3.RIGHT
	mat.set_shader_parameter("upright_right", upright.normalized())

func get_visual_direction() -> StringName:
	return _current_view


# ============================================================
# Pocket gesture presentation API
# ============================================================

## Начать жест доступа к инвентарю. Возвращает false, если уже активен
## или отсутствуют валидные клипы. Скрывает Body, показывает PocketPose.
func begin_inventory_access() -> bool:
	if _pocket_active:
		return false
	var pocket: AnimatedSprite3D = get_node_or_null("PocketPose") as AnimatedSprite3D
	if pocket == null or pocket.sprite_frames == null:
		return false
	# Валидность: все 3 клипа pocket_back/front/side должны быть валидными
	# и non-looping (looping-клип не может завершиться жестом).
	for clip in [&"pocket_back", &"pocket_front", &"pocket_side"]:
		if not _clip_is_valid(pocket.sprite_frames, clip):
			return false
		if pocket.sprite_frames.get_animation_loop(clip):
			return false

	# Сохраняем состояние Body
	var body: AnimatedSprite3D = $Body
	_body_was_visible = body.visible
	_body_was_playing = body.is_playing()

	_pocket_active = true
	_pocket_finished = false

	# Подключаем сигнал завершения: каждый begin проверяем реальное состояние
	# подключения (флаг не ведёт — PocketPose-узел могли заменить).
	if not pocket.animation_finished.is_connected(_on_pocket_animation_finished):
		pocket.animation_finished.connect(_on_pocket_animation_finished)

	# Скрываем Body, показываем PocketPose
	body.visible = false
	pocket.visible = true

	# Старт с frame 0 текущего вида
	var view := _current_view
	pocket.animation = _resolve_pocket_clip(view)
	pocket.frame = 0
	pocket.frame_progress = 0.0
	pocket.play()
	_apply_pocket_scale(pocket, view)

	# Непосредственно применяем начальный flip (left — flip_h), даже если
	# вид не меняется в последующих кадрах.
	var flip := view == &"left"
	if pocket.flip_h != flip:
		pocket.flip_h = flip
	return true


## Завершить жест доступа (идемпотентно). Останавливает pocket-анимацию,
## отменяет состояние жеста и восстанавливает нормальный Body.
func end_inventory_access() -> void:
	if not _pocket_active:
		return
	var pocket: AnimatedSprite3D = get_node_or_null("PocketPose") as AnimatedSprite3D
	if pocket != null:
		pocket.stop()
		pocket.visible = false

	# Отменяем состояние жеста
	_pocket_active = false
	_pocket_finished = false

	# Восстанавливаем нормальный Body: вид синхронизируем с текущим
	# _current_view (не оставляем старый back-спрайт при front-виде).
	var body: AnimatedSprite3D = $Body
	if body != null and body.sprite_frames != null:
		var action := _current_action
		if action == &"":
			action = &"idle"
		body.animation = _resolve_clip_name(body.sprite_frames, action, _current_view)
		body.frame = 0
		body.frame_progress = 0.0
		var flip := _current_view == &"left"
		if body.flip_h != flip:
			body.flip_h = flip
		_apply_sprite_scale(body)
		body.visible = _body_was_visible
		if _body_was_playing and body.is_inside_tree():
			body.play()
		else:
			body.pause()


## Активен ли жест доступа к инвентарю.
func is_inventory_access_active() -> bool:
	return _pocket_active


func _resolve_pocket_clip(view: StringName) -> StringName:
	match view:
		&"front":
			return &"pocket_front"
		&"left", &"right":
			return &"pocket_side"
		_:
			return &"pocket_back"


func _apply_pocket_scale(pocket: AnimatedSprite3D, view: StringName) -> void:
	var frames := pocket.sprite_frames
	if frames == null:
		return
	var view_key := "back"
	match view:
		&"front":
			view_key = "front"
		&"left", &"right":
			view_key = "side"
	var pixel_size: float = frames.get_meta("pixel_size_" + view_key, 0.005)
	if pixel_size <= 0.0:
		pixel_size = 0.005
	pocket.pixel_size = pixel_size
	var baseline: float = frames.get_meta("baseline_offset_pixels", 240.0)
	pocket.position.y = baseline * pixel_size


func _update_pocket_view(pocket: AnimatedSprite3D, new_view: StringName) -> void:
	# Смена вида: сохраняем нормализованную фазу и паузу
	var old_frame := pocket.frame
	var old_progress: float = pocket.frame_progress
	var was_paused := not pocket.is_playing()

	pocket.animation = _resolve_pocket_clip(new_view)

	var frame_count := pocket.sprite_frames.get_frame_count(pocket.animation)
	var clamped_frame: int = clampi(old_frame, 0, maxi(frame_count - 1, 0))
	pocket.set_frame_and_progress(clamped_frame, old_progress)
	if was_paused:
		pocket.pause()

	# Flip для боковых видов (side facing right → left = flip_h)
	var flip := new_view == &"left"
	if pocket.flip_h != flip:
		pocket.flip_h = flip

	_apply_pocket_scale(pocket, new_view)


## Сигнал animation_finished: единственный источник "завершения" жеста.
## Пауза/отмена сигнала не дают — только активное non-looping завершение.
func _on_pocket_animation_finished() -> void:
	if not _pocket_active or _pocket_finished:
		return
	var pocket: AnimatedSprite3D = get_node_or_null("PocketPose") as AnimatedSprite3D
	if pocket == null or pocket.sprite_frames == null:
		return
	# Looping-клипы не считаются завершёнными
	if pocket.sprite_frames.get_animation_loop(pocket.animation):
		return
	# Фиксируем последний кадр (запозированная поза)
	var frame_count := pocket.sprite_frames.get_frame_count(pocket.animation)
	pocket.set_frame_and_progress(frame_count - 1, 0.0)
	if not pocket.is_playing():
		pocket.pause()
	_pocket_finished = true
	inventory_access_finished.emit()


## Заменить спрайт-ресурс на совместимый. Не валидно — вернуть false, ничего не меняя.
func set_appearance_frames(new_frames: SpriteFrames) -> bool:
	var body: AnimatedSprite3D = $Body
	if body == null or not _validate_frames(new_frames):
		return false
	if body.sprite_frames == new_frames:
		return true

	var old_frame := body.frame
	var old_progress: float = body.frame_progress
	var was_playing := body.is_playing()
	var old_paused := not was_playing
	# Захватываем autoplay ДО замены sprite_frames: присваивание new_frames
	# очищает body.autoplay, если старого клипа нет в новом ресурсе.
	var old_autoplay := String(body.autoplay)

	# До первого update_visual действие ещё не установлено — трактуем как idle
	# с текущим видом, чтобы стартовое применение сохранённого вида работало.
	var action_for_clip := _current_action
	if action_for_clip == &"":
		action_for_clip = &"idle"

	body.sprite_frames = new_frames

	# Текущее действие/вид сохраняем; имя клипа — через общий helper.
	var clip_name := _resolve_clip_name(new_frames, action_for_clip, _current_view)
	body.animation = clip_name

	var frame_count := new_frames.get_frame_count(clip_name)
	var clamped_frame: int = clampi(old_frame, 0, maxi(frame_count - 1, 0))
	body.set_frame_and_progress(clamped_frame, old_progress)
	if old_paused:
		body.pause()
	elif was_playing:
		body.play()

	# До добавления в дерево autoplay сцены ещё не запускался. Если он задан,
	# указываем его на выбранный клип, чтобы _ready запустил именно его;
	# пустой autoplay оставляем пустым. play() здесь не вызываем — запуск
	# произойдёт при добавлении в дерево.
	if not is_inside_tree() and old_autoplay != "":
		body.autoplay = String(clip_name)

	# Отслеживаемое действие фиксируем только после успешной валидации.
	if action_for_clip != _current_action:
		_current_action = action_for_clip

	_apply_sprite_scale(body)
	return true


func _validate_frames(frames: SpriteFrames) -> bool:
	if frames == null:
		return false
	# 9 базовых клипов обязательны: idle/walk/attack x back/front/side.
	for action in [&"idle", &"walk", &"attack"]:
		for view in [&"back", &"front", &"side"]:
			if not _clip_is_valid(frames, StringName(action + "_" + view)):
				return false
	# run опционален для старых наборов, но если есть любой из трёх — все три
	# обязаны быть валидными (кадры, текстуры, fps).
	var has_any_run := false
	for view in [&"back", &"front", &"side"]:
		if frames.has_animation(StringName("run_" + view)):
			has_any_run = true
			break
	if has_any_run:
		for view in [&"back", &"front", &"side"]:
			if not _clip_is_valid(frames, StringName("run_" + view)):
				return false
	return true


## Клип валиден: существует, >0 кадров, все текстуры ненулевые, fps > 0.
func _clip_is_valid(frames: SpriteFrames, clip_name: StringName) -> bool:
	if not frames.has_animation(clip_name):
		return false
	var frame_count := frames.get_frame_count(clip_name)
	if frame_count <= 0:
		return false
	for i in frame_count:
		var texture: Texture2D = frames.get_frame_texture(clip_name, i)
		if texture == null:
			return false
	var fps := frames.get_animation_speed(clip_name)
	if fps <= 0.0:
		return false
	return true


## Точное имя клипа для действия/вида с запасными алиасами:
## action_view -> action_side (для left/right) -> run -> walk (для run) -> action.
func _resolve_clip_name(frames: SpriteFrames, action: StringName, view: StringName) -> StringName:
	var clip_name := StringName(action + "_" + view)
	if frames.has_animation(clip_name):
		return clip_name
	if view == &"left" or view == &"right":
		var side_name := StringName(action + "_side")
		if frames.has_animation(side_name):
			return side_name
	if action == &"run":
		var walk_name := StringName("walk_" + view)
		if frames.has_animation(walk_name):
			return walk_name
		var walk_side := StringName("walk_side")
		if (view == &"left" or view == &"right") and frames.has_animation(walk_side):
			return walk_side
	return action


func _resolve_view(facing_direction: Vector3) -> StringName:
	var owner_node: Node3D
	if get_parent() is Node3D:
		owner_node = get_parent() as Node3D
	else:
		return _current_view
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return _current_view

	# Вектор от персонажа к камере (проекция на горизонталь)
	var to_camera: Vector3 = cam.global_position - owner_node.global_position
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.0001:
		return _current_view
	var view_back: Vector3 = to_camera.normalized()

	var right := cam.global_basis.x
	right.y = 0.0
	right = right.normalized()

	var facing := facing_direction
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return _current_view
	facing = facing.normalized()

	var vertical := facing.dot(view_back)
	var horizontal := facing.dot(right)

	# Гистерезис вокруг диагонали: вертикаль — front/back, горизонталь — left/right
	if absf(vertical) > absf(horizontal) + VIEW_HYSTERESIS:
		return &"front" if vertical > 0.0 else &"back"
	elif absf(horizontal) > absf(vertical) + VIEW_HYSTERESIS:
		return &"right" if horizontal > 0.0 else &"left"
	else:
		return _current_view


func _apply_sprite_scale(body: AnimatedSprite3D) -> void:
	var frames := body.sprite_frames
	if frames == null:
		return

	# Вид определяет базовый ключ; для run дополнительно пробуем
	# pixel_size_run_<view> с fallback на обычный pixel_size_<view>.
	var view_key := "side"
	match _current_view:
		&"back":
			view_key = "back"
		&"front":
			view_key = "front"

	var run_action := body.animation.begins_with("run")
	var pixel_size: float = 0.0
	if run_action:
		pixel_size = frames.get_meta("pixel_size_run_" + view_key, -1.0)
	if pixel_size <= 0.0:
		pixel_size = frames.get_meta("pixel_size_" + view_key, 0.006)
	if pixel_size <= 0.0:
		pixel_size = 0.006
	body.pixel_size = pixel_size
	body.position.y = float(frames.get_meta("baseline_offset_pixels", 150.0)) * pixel_size
