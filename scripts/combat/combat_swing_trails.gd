extends Node3D
## Brief stylized air/speed trails for punches and wolf lunges (no contact sparks).

const _POOL_SIZE := 6
const _RIBBONS_PER_SLOTS := 3
const _MAIN_LEN := 1.15
const _MAIN_W := 0.08
const _SEGMENTS := 12
const _DRIFT_MAX := 0.55
const _FADE_HERO := 0.20
const _FADE_WOLF := 0.24

var _slots: Array[Node3D] = []
var _ages: Array[float] = []
var _durations: Array[float] = []
var _directions: Array[Vector3] = []
var _kinds: Array[String] = []
var _active: Array[bool] = []
var _anchors: Array[Vector3] = []
var _total_emitted := 0
var _last_kind := ""

func _ready() -> void:
	var mesh := _build_ribbon_mesh()
	for i in _POOL_SIZE:
		var root := Node3D.new()
		root.name = "Slot%d" % i
		root.visible = false
		add_child(root)
		for j in _RIBBONS_PER_SLOTS:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			mat.albedo_color = Color(0.96, 0.95, 0.90, 0.0)
			mi.material_override = mat
			root.add_child(mi)
		_slots.append(root)
		_ages.append(0.0)
		_durations.append(_FADE_HERO)
		_directions.append(Vector3.ZERO)
		_kinds.append("")
		_active.append(false)
		_anchors.append(Vector3.ZERO)

func emit_swing(kind: String, at: Vector3, direction: Vector3) -> void:
	if kind != "hero" and kind != "guard" and kind != "wolf":
		return
	var idx := -1
	for i in _POOL_SIZE:
		if not _active[i]:
			idx = i
			break
	if idx == -1:
		var oldest := 0
		var best_age := -INF
		for i in _POOL_SIZE:
			if _ages[i] > best_age:
				best_age = _ages[i]
				oldest = i
		idx = oldest
	var root: Node3D = _slots[idx]
	root.global_position = at
	root.visible = true
	_active[idx] = true
	_ages[idx] = 0.0
	_durations[idx] = _FADE_WOLF if kind == "wolf" else _FADE_HERO
	_directions[idx] = direction.normalized() if direction.length_squared() > 1e-8 else Vector3.FORWARD
	_kinds[idx] = kind
	_anchors[idx] = at
	_total_emitted += 1
	_last_kind = kind
	_layout(root, kind)


func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	for i in _POOL_SIZE:
		if not _active[i]:
			continue
		var age := _ages[i] + delta
		if age >= _durations[i]:
			_active[i] = false
			_slots[i].visible = false
			continue
		_ages[i] = age
		var t: float = clampf(age / _durations[i], 0.0, 1.0)
		var root: Node3D = _slots[i]
		root.global_position = _anchors[i] + _directions[i] * (_DRIFT_MAX * t)
		var alpha := _alpha_at(t)
		for j in _RIBBONS_PER_SLOTS:
			var mi: MeshInstance3D = root.get_child(j) as MeshInstance3D
			if mi == null:
				continue
			var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
			mat.albedo_color.a = alpha * _ribbon_alpha(j)


func clear_all() -> void:
	for i in _POOL_SIZE:
		_active[i] = false
		_slots[i].visible = false

func debug_snapshot() -> Dictionary:
	var active := 0
	for i in _POOL_SIZE:
		if _active[i]:
			active += 1
	return {
		"active_trails": active,
		"total_emitted": _total_emitted,
		"last_kind": _last_kind,
		"pool_size": _POOL_SIZE,
	}

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for i in _POOL_SIZE:
		if not _active[i]:
			continue
		var root: Node3D = _slots[i]
		var to_cam: Vector3 = cam.global_position - root.global_position
		if to_cam.length_squared() < 1e-8:
			continue
		var normal := to_cam.normalized()
		var dir_world: Vector3 = _directions[i]
		var x_axis := dir_world - normal * dir_world.dot(normal)
		if x_axis.length_squared() < 0.2025:
			var fallback: Vector3 = cam.global_transform.basis.x + 0.25 * cam.global_transform.basis.y
			x_axis = fallback - normal * fallback.dot(normal)
		if x_axis.length_squared() < 1e-8:
			continue
		x_axis = x_axis.normalized()
		var z_axis := normal
		var y_axis := z_axis.cross(x_axis).normalized()
		x_axis = y_axis.cross(z_axis).normalized()
		var s: Vector3 = root.scale
		var basis := Basis(x_axis, y_axis, z_axis).scaled(s)
		root.global_transform = Transform3D(basis, root.global_position)


func _layout(root: Node3D, kind: String) -> void:
	for j in _RIBBONS_PER_SLOTS:
		var mi: MeshInstance3D = root.get_child(j) as MeshInstance3D
		if mi == null:
			continue
		mi.position = Vector3.ZERO
		mi.rotation = Vector3.ZERO
		mi.scale = Vector3.ONE
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		mat.albedo_color.a = 0.0
		if j == 0:
			continue
		var off := 1 if j == 1 else -1
		if kind == "wolf":
			mi.position = Vector3(0.0, -0.06 * off, 0.12 * off)
			mi.scale = Vector3(0.45, 0.45, 0.8)
		else:
			mi.position = Vector3(0.0, 0.12 * off, 0.0)
			mi.scale = Vector3(0.45, 0.45, 0.65)
		mi.rotation = Vector3(0.0, 0.0, 0.18 * off)


func _alpha_at(t: float) -> float:
	var reveal := clampf(t / 0.15, 0.0, 1.0)
	var fade := 1.0 - smoothstep(0.35, 1.0, t)
	return lerpf(0.0, 0.75, reveal) * fade

func _ribbon_alpha(j: int) -> float:
	if j == 0:
		return 1.0
	return 0.6 if j == 1 else 0.45

func _build_ribbon_mesh() -> Mesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := _SEGMENTS
	for i in n + 1:
		var t: float = float(i) / float(n)
		var x: float = lerp(-0.5, 0.5, t) * _MAIN_LEN
		var y: float = sin(t * PI) * 0.22
		var w: float = sin(t * PI) * 0.5 * _MAIN_W
		verts.append(Vector3(x, y - w, 0.0))
		verts.append(Vector3(x, y + w, 0.0))
	for i in n:
		var a := i * 2
		idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
