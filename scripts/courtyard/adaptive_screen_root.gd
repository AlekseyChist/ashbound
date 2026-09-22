extends Control
## Адаптивный корневой Control: позиционирует себя по безопасной области экрана.
## На ПК/headless — весь видимый rect viewport; на мобильных — пересечение
## display safe area с окном, переведённое в логические координаты viewport.



func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_safe_rect()


func _process(_delta: float) -> void:
	var rect := get_safe_rect(get_viewport())
	if rect != _last_rect:
		_last_rect = rect
		_apply_safe_rect()


var _last_rect: Rect2 = Rect2(INF, INF, -INF, -INF)


func _apply_safe_rect() -> void:
	var vp := get_viewport()
	var logical := vp.get_visible_rect()
	var target := get_safe_rect(vp)
	# Ограничиваем результатом viewport.
	target = target.intersection(logical)
	if not target.has_area():
		target = logical
	position = target.position
	size = target.size


## Статическая чистая функция: пересечение safe area с окном, переведённое
## в логические координаты viewport.
static func map_safe_rect(logical_rect: Rect2, window_rect: Rect2, safe_rect: Rect2) -> Rect2:
	if not _is_valid_rect(logical_rect):
		return Rect2()
	if not _is_valid_rect(window_rect) or not _is_valid_rect(safe_rect):
		return logical_rect
	var w := window_rect.size
	if w.x <= 0.0 or w.y <= 0.0:
		return logical_rect
	# Пересечение safe area с окном в физических координатах.
	var clipped := safe_rect.intersection(window_rect)
	if not clipped.has_area():
		return logical_rect
	# Перевод из физических координат окна в логические координаты viewport.
	var scale_x: float = logical_rect.size.x / w.x
	var scale_y: float = logical_rect.size.y / w.y
	var origin := logical_rect.position
	var pos := Vector2(
		origin.x + (clipped.position.x - window_rect.position.x) * scale_x,
		origin.y + (clipped.position.y - window_rect.position.y) * scale_y
	)
	var sz := Vector2(clipped.size.x * scale_x, clipped.size.y * scale_y)
	var result := Rect2(pos, sz)
	if not _is_valid_rect(result):
		return logical_rect
	return result


## Статическая функция: реальный опрос safe area для данного viewport.
static func get_safe_rect(viewport: Viewport) -> Rect2:
	var vp := viewport
	if vp == null:
		return Rect2()
	var logical := vp.get_visible_rect()
	if not _is_valid_rect(logical):
		return Rect2()
	var platform := OS.get_name()
	var is_mobile := platform == "Android" or platform == "iOS"
	if not is_mobile:
		# ПК/headless: весь видимый rect viewport, safe area игнорируем.
		return logical
	var window_rect := Rect2(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	var safe_rect := DisplayServer.get_display_safe_area()
	return map_safe_rect(logical, window_rect, safe_rect)


static func _is_valid_rect(r: Rect2) -> bool:
	if not r.position.is_finite() or not r.size.is_finite():
		return false
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return false
	var end := r.end
	if not end.is_finite():
		return false
	return true
