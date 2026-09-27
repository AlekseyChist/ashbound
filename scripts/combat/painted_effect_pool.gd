extends Node3D
# Pooled renderer for hand-painted 2D RGBA VFX (2x2 atlases) placed in 3D.

var _textures: Dictionary = {}
var _capacity: int = 0
var _sprites: Array[Sprite3D] = []
var _age: Array[float] = []
var _life: Array[float] = []
var _anchor: Array[Vector3] = []
var _direction: Array[Vector3] = []
var _travel: Array[float] = []
var _span: Array[float] = []
var _order: Array[int] = []
var _kind: Array[String] = []
var _active: Array[bool] = []
var _emitted: int = 0
var _last_kind: String = ""
var _seq: int = 0

func setup(textures: Dictionary, capacity: int) -> void:
	if _capacity > 0 or not _sprites.is_empty():
		push_error("PaintedEffectPool.setup: already initialized")
		return
	if textures.is_empty() or capacity <= 0:
		push_error("PaintedEffectPool.setup: need non-empty textures and positive capacity")
		return
	for key in textures.keys():
		var tex = textures[key]
		if not (tex is Texture2D):
			push_error("PaintedEffectPool.setup: texture '%s' must be a Texture2D" % str(key))
			return
		var t := tex as Texture2D
		if t.get_width() <= 0 or t.get_height() <= 0 or t.get_width() != t.get_height() or t.get_width() % 2 != 0:
			push_error("PaintedEffectPool.setup: texture '%s' must be square with even nonzero width/height" % str(key))
			return
	_textures = textures.duplicate()
	_capacity = capacity
	for i in _capacity:
		var s := Sprite3D.new()
		s.name = "fx_%d" % i
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		s.transparent = true
		s.shaded = false
		s.double_sided = true
		s.no_depth_test = false
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		s.hframes = 2
		s.vframes = 2
		s.frame = 0
		s.modulate = Color.WHITE
		s.scale = Vector3.ONE
		s.visible = false
		add_child(s)
		_sprites.append(s)
		_age.append(0.0)
		_life.append(1.0)
		_anchor.append(Vector3.ZERO)
		_direction.append(Vector3.FORWARD)
		_travel.append(0.0)
		_span.append(1.0)
		_order.append(0)
		_kind.append("")
		_active.append(false)

func emit(kind: String, at: Vector3, direction: Vector3, lifetime: float, span: float, travel: float = 0.0) -> void:
	if not _textures.has(kind):
		return
	if not is_finite_v3(at) or not is_finite_v3(direction):
		return
	if not (is_finite(lifetime) and lifetime > 0.0) or not (is_finite(span) and span > 0.0):
		return
	if not (is_finite(travel) and travel >= 0.0):
		return
	var dir := direction.normalized() if direction.length_squared() > 1e-8 else Vector3.FORWARD
	var idx := _find_slot()
	if idx < 0:
		return
	var tex: Texture2D = _textures[kind]
	var s: Sprite3D = _sprites[idx]
	s.texture = tex
	s.pixel_size = span / float(tex.get_width() / 2)
	s.global_position = at
	s.frame = 0
	s.modulate = Color.WHITE
	s.scale = Vector3.ONE
	_age[idx] = 0.0
	_life[idx] = lifetime
	_anchor[idx] = at
	_direction[idx] = dir
	_travel[idx] = travel
	_span[idx] = span
	_order[idx] = _seq
	_seq += 1
	_kind[idx] = kind
	_active[idx] = true
	s.visible = true
	_emitted += 1
	_last_kind = kind

func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	for i in _capacity:
		if not _active[i]:
			continue
		_age[i] += delta
		var t := clampf(_age[i] / _life[i], 0.0, 1.0)
		if _age[i] >= _life[i]:
			_active[i] = false
			_sprites[i].visible = false
			continue
		var s: Sprite3D = _sprites[i]
		s.frame = int(clampf(t * 4.0, 0.0, 3.0))
		var fade := 1.0 if t < 0.5 else clampf(2.0 * (1.0 - t), 0.0, 1.0)
		s.modulate = Color(1, 1, 1, fade)
		var grow := lerpf(1.0, 1.12, t)
		s.scale = Vector3.ONE * grow
		s.global_position = _anchor[i] + _direction[i] * (_travel[i] * t)

func clear_all() -> void:
	for i in _capacity:
		_active[i] = false
		_sprites[i].visible = false

func debug_snapshot() -> Dictionary:
	var frames: Array[int] = []
	var ages: Array[float] = []
	var active_count := 0
	for i in _capacity:
		if _active[i]:
			active_count += 1
			frames.append(int(_sprites[i].frame))
			ages.append(_age[i])
	return {
		"active": active_count,
		"emitted": _emitted,
		"last_kind": _last_kind,
		"pool_size": _capacity,
		"frames": frames,
		"ages": ages,
	}

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for i in _capacity:
		if not _active[i]:
			continue
		_orient(_sprites[i], _direction[i])

func _orient(s: Sprite3D, dir: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := cam.global_position - s.global_position
	if to_cam.length_squared() < 1e-8:
		return
	var n := to_cam.normalized()
	var x := dir - n * dir.dot(n)
	if x.length_squared() < 0.2025:
		x = cam.global_transform.basis.x + 0.25 * cam.global_transform.basis.y
		x = x - n * x.dot(n)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT - n * Vector3.RIGHT.dot(n)
	if x.length_squared() < 1e-6:
		return
	x = x.normalized()
	var y := n.cross(x)
	y = y if y.length_squared() > 1e-8 else Vector3.UP
	y = y.normalized()
	x = y.cross(n).normalized()
	var basis := Basis(x, y, n)
	basis = basis.scaled(s.scale)
	s.global_transform = Transform3D(basis, s.global_position)

func _find_slot() -> int:
	var oldest := -1
	for i in _capacity:
		if not _active[i]:
			return i
		if oldest < 0 or _order[i] < _order[oldest]:
			oldest = i
	return oldest

func is_finite_v3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
