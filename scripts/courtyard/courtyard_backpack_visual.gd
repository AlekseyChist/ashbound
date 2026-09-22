extends Node3D
## Полнокадровая замена рюкзака для текущего путешественника.
## Узел Visual/BackpackLayer (без детей) переключает полные кадры Body/PocketPose
## между базовыми и нарисованными вариантами с рюкзаком.

const BACKPACK_BODY_FRAMES_PATH := "res://assets/characters/courtyard/traveler_backpack_frames.tres"
const BACKPACK_POCKET_FRAMES_PATH := "res://assets/characters/courtyard/traveler_backpack_pocket_frames.tres"

var _inventory: Node
var _body: AnimatedSprite3D
var _pocket: AnimatedSprite3D
var _worn := false
var _bare_body_frames: SpriteFrames
var _bare_pocket_frames: SpriteFrames
var _warned := false

# Опциональная пара body-кадров для явного предпросмотра техники (не экипировка).
var _configured_bare_body: SpriteFrames
var _configured_worn_body: SpriteFrames


func _ready() -> void:
	process_priority = 10
	_inventory = get_node_or_null("/root/Inventory")
	var visual := get_parent() as Node3D
	if visual != null:
		_body = visual.get_node_or_null("Body") as AnimatedSprite3D
		_pocket = visual.get_node_or_null("PocketPose") as AnimatedSprite3D
	refresh_visual()


func _process(_delta: float) -> void:
	refresh_visual()


## Публичное обновление для тестов и процесса.
func refresh_visual() -> void:
	if _inventory == null or _body == null or _pocket == null:
		return
	var worn_storage: Dictionary = _inventory.get_worn_storage("backpack")
	var is_worn := not worn_storage.is_empty()
	if is_worn == _worn:
		return
	if is_worn:
		_enter_worn()
	else:
		_exit_worn()


## Настроить пару body-кадров (bare/worn) для явного предпросмотра техники.
## Оба ресурса валидируются до любых изменений; несовместимая пара отклоняется
## атомарно. Не затрагивает pocket и авторитет экипировки Inventory.
func configure_body_frame_pair(bare_frames: SpriteFrames, worn_frames: SpriteFrames) -> bool:
	if not is_node_ready() or not is_inside_tree():
		return false
	var visual := get_parent() as Node3D
	if visual == null or _body == null or _pocket == null:
		return false
	if not visual._validate_frames(bare_frames) or not visual._validate_frames(worn_frames):
		return false
	if not _frame_pairs_compatible(bare_frames, worn_frames):
		return false

	# Синхронизируем фактическое состояние Inventory до выбора целевого члена
	# пары: вызов в том же кадре после equip/unequip не должен опереться на
	# устаревший _worn.
	refresh_visual()

	var target := worn_frames if _worn else bare_frames
	if not _apply_body_frames(target):
		return false

	# Коммитим новую конфигурацию только после успешного применения:
	# невалидный/сбойный вызов остаётся атомарным.
	_configured_bare_body = bare_frames
	_configured_worn_body = worn_frames
	return true


## Пара ресурсов совместима: одинаковые имена клипов, кадры, скорости,
## циклы и длительности кадров для каждого клипа.
func _frame_pairs_compatible(a: SpriteFrames, b: SpriteFrames) -> bool:
	var anims_a := a.get_animation_names()
	if anims_a.size() != b.get_animation_names().size():
		return false
	for anim in anims_a:
		if not b.has_animation(anim):
			return false
		if a.get_frame_count(anim) != b.get_frame_count(anim):
			return false
		var speed_a := a.get_animation_speed(anim)
		var speed_b := b.get_animation_speed(anim)
		if not is_finite(speed_a) or not is_finite(speed_b) or speed_a <= 0.0 or speed_b <= 0.0:
			return false
		if speed_a != speed_b:
			return false
		if a.get_animation_loop(anim) != b.get_animation_loop(anim):
			return false
		var count := a.get_frame_count(anim)
		for i in count:
			var delay_a := a.get_frame_duration(anim, i)
			var delay_b := b.get_frame_duration(anim, i)
			if not is_finite(delay_a) or not is_finite(delay_b) or delay_a <= 0.0 or delay_b <= 0.0:
				return false
			if delay_a != delay_b:
				return false
	return true


func _enter_worn() -> void:
	var body_frames := _configured_worn_body if _configured_worn_body != null else load(BACKPACK_BODY_FRAMES_PATH) as SpriteFrames
	var pocket_frames := load(BACKPACK_POCKET_FRAMES_PATH) as SpriteFrames
	if body_frames == null or pocket_frames == null:
		if not _warned:
			push_error("courtyard_backpack_visual: could not load painted backpack frames")
			_warned = true
		return
	var pocket_anim := _pocket.animation
	if pocket_anim.is_empty() or not pocket_frames.has_animation(pocket_anim) or pocket_frames.get_frame_count(pocket_anim) < _pocket.sprite_frames.get_frame_count(pocket_anim):
		if not _warned:
			push_error("courtyard_backpack_visual: incompatible pocket animation frames")
			_warned = true
		return
	_capture_bare_frames()
	var body_ok := _apply_body_frames(body_frames)
	if not body_ok:
		return
	_apply_pocket_frames(pocket_frames)
	_worn = true


func _exit_worn() -> void:
	var bare := _configured_bare_body if _configured_bare_body != null else _bare_body_frames
	var body_ok := _apply_body_frames(bare)
	if not body_ok:
		return
	_apply_pocket_frames(_bare_pocket_frames)
	_worn = false


func _capture_bare_frames() -> void:
	# Храним точные ссылки на ресурсы, а не дубликаты:
	# базовая кожа могла измениться между надеваниями.
	# Не перетираем настроенную bare-пару текущим (возможно, уже надетым) body.
	if _configured_bare_body == null:
		_bare_body_frames = _body.sprite_frames
	_bare_pocket_frames = _pocket.sprite_frames


func _apply_body_frames(frames: SpriteFrames) -> bool:
	var visual := get_parent() as Node3D
	if frames == null or visual == null:
		return false
	var speed_scale := _body.speed_scale
	var ok: bool = visual.set_appearance_frames(frames)
	if not ok:
		if not _warned:
			push_warning("BackpackLayer: could not apply backpack frames; appearance unchanged")
			_warned = true
		return false
	_body.speed_scale = speed_scale
	return true


func _apply_pocket_frames(frames: SpriteFrames) -> void:
	if frames == null:
		return
	var animation := _pocket.animation
	var frame := _pocket.frame
	var frame_progress := _pocket.frame_progress
	var is_playing: bool = _pocket.is_playing()
	var speed_scale := _pocket.speed_scale
	_pocket.sprite_frames = frames
	_pocket.animation = animation
	_pocket.speed_scale = speed_scale
	if is_playing:
		_pocket.play(animation)
	else:
		_pocket.pause()
	_pocket.set_frame_and_progress(frame, frame_progress)
