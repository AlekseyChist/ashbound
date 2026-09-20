class_name CourtyardCharacterVisual
extends Node3D
## Визуальная презентация 2D-персонажа двора: спрайт, вид, фазы.
## Отделена от движения/боевого состояния владельца (CourtyardPlayer).

const VIEW_HYSTERESIS := 0.08

var _current_action: StringName = &""
var _current_view: StringName = &"back"


## Обновить визуал: действие (idle/walk/attack), направление взгляда, частота walk-позы.
func update_visual(action: StringName, facing_direction: Vector3, walk_pose_fps: int = 15) -> void:
	var body: AnimatedSprite3D = $Body
	if body == null or body.sprite_frames == null:
		return

	var new_action := action
	var moving := new_action == &"walk"

	var new_view := _resolve_view(facing_direction)

	var action_changed := new_action != _current_action
	var view_changed := new_view != _current_view

	if action_changed or view_changed:
		# Сохраняем фазу, чтобы смена вида не сбрасывала walk/attack
		var old_frame := body.frame
		var old_progress: float = body.frame_progress
		var was_playing := body.is_playing()
		var old_paused := not was_playing

		_current_action = new_action
		_current_view = new_view
		var clip_name := StringName(new_action + "_" + new_view)
		if not body.sprite_frames.has_animation(clip_name):
			# Запасные алиасы, пока новые клипы импортируются
			if new_view == &"left" or new_view == &"right":
				clip_name = StringName(new_action + "_side")
			if not body.sprite_frames.has_animation(clip_name):
				clip_name = new_action
		body.animation = clip_name

		if action_changed:
			# Нормальная смена действия — старт с первого кадра
			body.frame = 0
			body.frame_progress = 0.0
			body.play()
		else:
			# Только смена вида — сохраняем фазу старого клипа
			var frame_count := body.sprite_frames.get_frame_count(clip_name)
			var clamped_frame: int = clampi(old_frame, 0, maxi(frame_count - 1, 0))
			body.set_frame_and_progress(clamped_frame, old_progress)
			if old_paused:
				body.pause()

	# Частота кадров: walk — walk_pose_fps, иначе 1.0
	var target_scale := float(walk_pose_fps) / 15.0 if moving else 1.0
	body.speed_scale = target_scale

	# Переворот спрайта: только для боковых видов (LEFT — flip_h)
	var flip := _current_view == &"left"
	if body.flip_h != flip:
		body.flip_h = flip

	_apply_sprite_scale(body)


## Текущее визуальное направление (front/back/left/right).
func get_visual_direction() -> StringName:
	return _current_view


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

	# Текущее действие/вид сохраняем; имя клипа — с теми же запасными алиасами.
	var clip_name := StringName(action_for_clip + "_" + _current_view)
	if not new_frames.has_animation(clip_name):
		if _current_view == &"left" or _current_view == &"right":
			clip_name = StringName(action_for_clip + "_side")
		if not new_frames.has_animation(clip_name):
			clip_name = action_for_clip
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
	for action in [&"idle", &"walk", &"attack"]:
		for view in [&"back", &"front", &"side"]:
			var clip_name := StringName(action + "_" + view)
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

	var key := "pixel_size_side"
	match _current_view:
		&"back":
			key = "pixel_size_back"
		&"front":
			key = "pixel_size_front"

	var pixel_size: float = frames.get_meta(key, 0.006)
	if pixel_size <= 0.0:
		pixel_size = 0.006
	body.pixel_size = pixel_size
	body.position.y = float(frames.get_meta("baseline_offset_pixels", 150.0)) * pixel_size
