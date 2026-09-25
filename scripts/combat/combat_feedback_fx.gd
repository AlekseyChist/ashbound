extends Node3D
# World-space combat feedback for AshBound (Compatibility renderer, Android).
# Self-contained: procedural 3D ink-like ribbons + impact bursts. No gameplay logic.

const IMPACT_LIFE_MIN := 0.18
const IMPACT_LIFE_MAX := 0.32
const MAX_ACTIVE_IMPACTS := 8
const CUE_ARMED_T := 0.18          # last fraction of windup that is "armed"
const CUE_SPAN := 0.9              # ~meters, main readable span

# Palette (ivory / ochre / amber / dark ink)
var _c_ivory := Color(0.96, 0.93, 0.82)
var _c_ochre := Color(0.72, 0.52, 0.24)
var _c_amber := Color(0.98, 0.78, 0.36)
var _c_dark := Color(0.12, 0.09, 0.06)
var _c_white := Color(0.99, 0.98, 0.94)
var _c_gold := Color(0.95, 0.82, 0.42)

# Cue state (pooled, one per enemy key)
var _cue_nodes: Array[Node3D] = []
var _cue_keys: Array[String] = []
var _cue_visible: Array[bool] = []
var _cue_kind: Array[String] = []
var _cue_center: Array[Vector3] = []
var _cue_dir: Array[Vector3] = []
var _cue_progress: Array[float] = []
var _cue_armed: Array[bool] = []

# Impact pool
var _impacts: Array[Node3D] = []   # pooled impact roots (pre-built)
var _impact_alive: Array[bool] = []
var _impact_age: Array[float] = []
var _impact_life: Array[float] = []
var _impact_order: Array[int] = [] # active emission order, oldest first

var _last_result := ""
var _active_impacts := 0
var _visible_cues := 0

func _ready() -> void:
	_build_cue_nodes()
	_build_impact_pool()

# ---------------------------------------------------------------------------
# Public contract
# ---------------------------------------------------------------------------

func update_cue(key: String, at: Vector3, direction: Vector3, progress: float, armed: bool, enemy_kind: String) -> void:
	var idx := _find_cue(key)
	if idx < 0:
		idx = _alloc_cue(key, enemy_kind)
	_cue_keys[idx] = key
	_cue_center[idx] = at
	var d := direction
	if d.length_squared() < 1e-6:
		d = Vector3.FORWARD
	_cue_dir[idx] = d.normalized()
	_cue_progress[idx] = clampf(progress, 0.0, 1.0)
	_cue_armed[idx] = armed
	_cue_visible[idx] = true
	_apply_cue(idx)

func hide_cue(key: String) -> void:
	var idx := _find_cue(key)
	if idx < 0:
		return
	_cue_visible[idx] = false
	_set_cue_visible(idx, false)

func emit_impact(result: String, at: Vector3, direction: Vector3) -> void:
	if result != "hit" and result != "block" and result != "perfect_block":
		return  # miss / obstructed / unknown -> no contact effect
	var d := direction
	if d.length_squared() < 1e-6:
		d = Vector3.FORWARD
	var idx := _acquire_impact()
	if idx < 0:
		return
	_configure_impact(idx, result, at, d.normalized())
	_last_result = result

func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	if delta == 0.0:
		return
	for i in _impacts.size():
		if not _impact_alive[i]:
			continue
		_impact_age[i] += delta
		var t := _impact_age[i] / maxf(_impact_life[i], 1e-4)
		if t >= 1.0:
			_release_impact(i)
		else:
			_update_impact_visual(i, t)

func clear_all() -> void:
	for i in _cue_nodes.size():
		_cue_visible[i] = false
		_set_cue_visible(i, false)
	for i in _impacts.size():
		if _impact_alive[i]:
			_release_impact(i)
	_active_impacts = 0
	_recount()

func debug_snapshot() -> Dictionary:
	return {
		"active_impacts": _active_impacts,
		"visible_cues": _visible_cues,
		"last_result": _last_result,
		"cue_pool_size": _cue_nodes.size(),
		"impact_pool_size": _impacts.size(),
	}

# ---------------------------------------------------------------------------
# Camera-facing orientation (only job of _process)
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	for i in _cue_nodes.size():
		if not _cue_visible[i]:
			continue
		_orient_cue_to_camera(i, cam.global_transform)
	for i in _impacts.size():
		if not _impact_alive[i]:
			continue
		_orient_impact_to_camera(i, cam.global_transform)

# ---------------------------------------------------------------------------
# Cue construction / pooling
# ---------------------------------------------------------------------------

func _build_cue_nodes() -> void:
	for i in 2:
		var root := Node3D.new()
		root.name = "Cue%d" % i
		root.visible = false
		add_child(root)
		# Main ribbon (dark backing + ivory highlight)
		var main := _make_ribbon_node("Main", 1.0, 0.06)
		root.add_child(main)
		# Armed accent (different shape/scale) - short outward ticks
		var armed := Node3D.new()
		armed.name = "Armed"
		armed.visible = false
		root.add_child(armed)
		for s in [-1, 1]:
			var tick := _make_tick_node(s)
			armed.add_child(tick)
		# Wolf: lower forward paired strokes
		var wolf := Node3D.new()
		wolf.name = "Wolf"
		wolf.visible = false
		root.add_child(wolf)
		for s in [-1, 1]:
			var w := _make_ribbon_node("W%d" % s, 0.55, 0.04)
			w.position = Vector3(0.0, -0.12 * s, 0.18)
			w.rotation_degrees = Vector3(0.0, 0.0, 18.0 * s)
			wolf.add_child(w)
		# Guard: curved punch stroke (single, thicker)
		var guard := _make_ribbon_node("Guard", 0.8, 0.09)
		guard.name = "Guard"
		root.add_child(guard)

		_cue_nodes.append(root)
		_cue_keys.append("")
		_cue_visible.append(false)
		_cue_kind.append("")
		_cue_center.append(Vector3.ZERO)
		_cue_dir.append(Vector3.FORWARD)
		_cue_progress.append(0.0)
		_cue_armed.append(false)

func _alloc_cue(key: String, kind: String) -> int:
	# Reuse a hidden slot first
	for i in _cue_nodes.size():
		if not _cue_visible[i]:
			_cue_kind[i] = kind
			return i
	# Otherwise take the last (shouldn't happen with 2 slots + hide discipline)
	var i := _cue_nodes.size() - 1
	_cue_kind[i] = kind
	return i

func _find_cue(key: String) -> int:
	for i in _cue_keys.size():
		if _cue_visible[i] and _cue_keys[i] == key:
			return i
	return -1

func _apply_cue(idx: int) -> void:
	var root := _cue_nodes[idx]
	root.position = _cue_center[idx]
	var kind := _cue_kind[idx]
	var prog := _cue_progress[idx]
	var armed := _cue_armed[idx]
	# Base orientation: face attack direction (Y-up yaw), principal plane toward camera later.
	var d := _cue_dir[idx]
	root.rotation = Vector3.ZERO
	if d.length_squared() > 1e-6:
		root.rotate_y(atan2(d.x, d.z))
	# Show/hide per-kind sub-nodes
	var wolf_node: Node3D = root.get_node("Wolf")
	var guard_node: Node3D = root.get_node("Guard")
	var main_node: Node3D = root.get_node("Main")
	var armed_node: Node3D = root.get_node("Armed")
	wolf_node.visible = (kind == "wolf")
	guard_node.visible = (kind == "guard")
	main_node.visible = (kind != "wolf" and kind != "guard")
	armed_node.visible = armed
	# Charging: restrained narrowing stroke before armed
	if not armed:
		var s := lerpf(0.55, 1.0, prog)
		root.scale = Vector3(s, s, s)
	else:
		root.scale = Vector3.ONE * CUE_SPAN
	# Wolf/guard scale by progress too
	if kind == "wolf":
		wolf_node.scale = Vector3.ONE * lerpf(0.5, 1.0, prog)
	elif kind == "guard":
		guard_node.scale = Vector3.ONE * lerpf(0.6, 1.0, prog)
	# Apply charge/armed palette to the visible strokes (dark outline preserved).
	var front_color := _c_dark.lerp(_c_ivory, prog * 0.6) if not armed else _c_amber
	if kind == "wolf":
		for c in wolf_node.get_children():
			if c is Node3D:
				_set_stroke_colors(c as Node3D, front_color)
	elif kind == "guard":
		_set_stroke_colors(guard_node, front_color)
	else:
		_set_stroke_colors(main_node, front_color)
	# Make the cue actually visible.
	_set_cue_visible(idx, true)

func _set_stroke_colors(ribbon_root: Node3D, front_color: Color) -> void:
	# Ribbon nodes hold [backing (dark), front (ivory)] MeshInstance3D children.
	var children := ribbon_root.get_children()
	for i in children.size():
		var mi := children[i] as MeshInstance3D
		if mi == null or mi.material_override == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		if i == 0:
			mat.albedo_color = _c_dark  # preserve dark outline/backing
		else:
			mat.albedo_color = front_color

func _set_cue_visible(idx: int, v: bool) -> void:
	_cue_nodes[idx].visible = v
	_recount()

func _orient_cue_to_camera(idx: int, cam_xform: Transform3D) -> void:
	var root := _cue_nodes[idx]
	var to_cam := cam_xform.origin - root.global_position
	if to_cam.length_squared() < 1e-8:
		return
	var basis := _camera_basis(to_cam)
	# Сохраняем текущий глобальный масштаб, чтобы не сбивать заряд/расширение.
	var current_scale := root.global_transform.basis.get_scale()
	root.set_global_transform(Transform3D(basis.scaled(current_scale), root.global_position))


func _orient_impact_to_camera(idx: int, cam_xform: Transform3D) -> void:
	var root := _impacts[idx]
	var to_cam := cam_xform.origin - root.global_position
	if to_cam.length_squared() < 1e-8:
		return
	var basis := _camera_basis(to_cam)
	# Сохраняем текущий глобальный масштаб, чтобы не сбивать заряд/расширение.
	var current_scale := root.global_transform.basis.get_scale()
	root.set_global_transform(Transform3D(basis.scaled(current_scale), root.global_position))


# Full camera-facing basis (handles pitch/orbit), safe for zero-length input.
func _camera_basis(to_cam: Vector3) -> Basis:
	if to_cam.length_squared() < 1e-8:
		return Basis.IDENTITY
	var z := to_cam.normalized()
	var up := Vector3.UP
	if absf(z.dot(up)) > 0.99:
		up = Vector3.BACK
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return Basis(x, y, z)

# ---------------------------------------------------------------------------
# Impact construction / pooling
# ---------------------------------------------------------------------------

func _build_impact_pool() -> void:
	for i in MAX_ACTIVE_IMPACTS:
		var root := Node3D.new()
		root.name = "Impact%d" % i
		root.visible = false
		add_child(root)
		# Pre-build all three profiles as children, toggle visibility.
		var hit := _build_hit_profile()
		hit.name = "Hit"
		root.add_child(hit)
		var block := _build_block_profile()
		block.name = "Block"
		root.add_child(block)
		var perfect := _build_perfect_profile()
		perfect.name = "Perfect"
		root.add_child(perfect)
		_impacts.append(root)
		_impact_alive.append(false)
		_impact_age.append(0.0)
		_impact_life.append(IMPACT_LIFE_MIN)

func _acquire_impact() -> int:
	for i in _impacts.size():
		if not _impact_alive[i]:
			return i
	# Evict oldest (front of active order)
	var oldest := _impact_order[0]
	_release_impact(oldest)
	return oldest

func _release_impact(idx: int) -> void:
	if not _impact_alive[idx]:
		return
	_impact_alive[idx] = false
	_impacts[idx].visible = false
	_active_impacts -= 1
	# Remove from active order ring
	var pos := _impact_order.find(idx)
	if pos >= 0:
		_impact_order.remove_at(pos)

func _configure_impact(idx: int, result: String, at: Vector3, dir: Vector3) -> void:
	var root := _impacts[idx]
	root.position = at
	root.rotation = Vector3.ZERO
	if dir.length_squared() > 1e-6:
		root.rotate_y(atan2(dir.x, dir.z))
	root.get_node("Hit").visible = (result == "hit")
	root.get_node("Block").visible = (result == "block")
	root.get_node("Perfect").visible = (result == "perfect_block")
	var life := IMPACT_LIFE_MIN
	if result == "hit":
		life = 0.22
	elif result == "block":
		life = 0.26
	else:
		life = 0.30
	_impact_life[idx] = life
	_impact_age[idx] = 0.0
	_impact_alive[idx] = true
	root.visible = true
	_active_impacts += 1
	if not _impact_order.has(idx):
		_impact_order.append(idx)
	_update_impact_visual(idx, 0.0)

func _update_impact_visual(idx: int, t: float) -> void:
	var root := _impacts[idx]
	# Rapid expand then fade: scale up fast, alpha down in second half.
	var s := lerpf(0.4, 1.0, minf(t / 0.35, 1.0))
	root.scale = Vector3.ONE * s
	var a := 1.0 - smoothstep(0.45, 1.0, t)
	for child in root.get_children():
		if child is Node3D:
			for m in (child as Node3D).get_children():
				if m is MeshInstance3D:
					var mat := (m as MeshInstance3D).material_override
					if mat is StandardMaterial3D:
						var smat := mat as StandardMaterial3D
						var col := smat.albedo_color
						col.a = a
						smat.albedo_color = col

# ---------------------------------------------------------------------------
# Profile builders (immutable prototypes, shared materials)
# ---------------------------------------------------------------------------

func _build_hit_profile() -> Node3D:
	var n := Node3D.new()
	# Sharp asymmetric burst: dark backing + smaller ivory burst (no arcs)
	var back := _make_burst_mesh(0.42, 7, _c_dark)
	back.position = Vector3(0.0, 0.0, -0.012)
	n.add_child(back)
	var front := _make_burst_mesh(0.39, 7, _c_ivory)
	front.position = Vector3(0.0, 0.0, 0.0)
	n.add_child(front)
	# Small ochre dust chips near the contact point
	for i in 3:
		var chip := _make_chip_mesh(0.07 + 0.02 * i, _c_ochre)
		var ang := (i / 3.0) * TAU + 0.5
		chip.position = Vector3(cos(ang) * 0.16, sin(ang) * 0.10, 0.05 * i)
		n.add_child(chip)
	return n


func _build_block_profile() -> Node3D:
	var n := Node3D.new()
	# Dark thin backing ripple (slightly wider, behind)
	var back := _make_arc_mesh(0.50, 0.045, 2.6, _c_dark)
	back.position = Vector3(0.0, 0.0, -0.012)
	n.add_child(back)
	# Compressed broken ivory ripple (tapered tips, gap in the middle)
	var rip := _make_arc_mesh(0.48, 0.06, 2.6, _c_ivory)
	rip.position = Vector3(0.0, 0.0, 0.0)
	n.add_child(rip)
	# Small ochre fragment on the far side of the break
	var frag := _make_chip_mesh(0.09, _c_ochre)
	frag.position = Vector3(0.30, 0.14, 0.02)
	n.add_child(frag)
	return n


func _build_perfect_profile() -> Node3D:
	var n := Node3D.new()
	# Dark thin backing for both separated strokes (slightly wider, behind)
	var back0 := _make_arc_mesh(0.68, 0.05, 1.7, _c_dark)
	back0.rotation_degrees = Vector3(0.0, 0.0, -24.0)
	back0.position = Vector3(0.0, 0.0, -0.012)
	n.add_child(back0)
	var back1 := _make_arc_mesh(0.68, 0.05, 1.7, _c_dark)
	back1.rotation_degrees = Vector3(0.0, 0.0, 156.0)
	back1.position = Vector3(0.0, 0.0, -0.012)
	n.add_child(back1)
	# Two separated curved ivory strokes (tapered to near-zero tips)
	var st0 := _make_arc_mesh(0.66, 0.07, 1.7, _c_ivory)
	st0.rotation_degrees = Vector3(0.0, 0.0, -24.0)
	n.add_child(st0)
	var st1 := _make_arc_mesh(0.66, 0.07, 1.7, _c_white)
	st1.rotation_degrees = Vector3(0.0, 0.0, 156.0)
	st1.position = Vector3(0.0, 0.0, 0.004)
	n.add_child(st1)
	# Small gold point at the contact center
	var accent := _make_chip_mesh(0.16, _c_gold)
	accent.position = Vector3(0.0, 0.0, 0.04)
	n.add_child(accent)
	return n


# ---------------------------------------------------------------------------
# Mesh / material helpers (procedural, unshaded, transparent, double-sided)
# ---------------------------------------------------------------------------

func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	m.no_depth_test = false
	return m

func _make_ribbon_node(name: String, length: float, width: float) -> Node3D:
	var n := Node3D.new()
	n.name = name
	# Dark backing stroke (thin) behind ivory highlight
	var back := MeshInstance3D.new()
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.mesh = _make_ribbon_mesh(length, width * 1.6, 12)
	back.material_override = _make_material(_c_dark)
	n.add_child(back)
	var front := MeshInstance3D.new()
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	front.mesh = _make_ribbon_mesh(length, width, 12)
	front.position = Vector3(0.0, 0.0, 0.005)
	front.material_override = _make_material(_c_ivory)
	n.add_child(front)
	return n


func _make_tick_node(side: int) -> Node3D:
	var n := MeshInstance3D.new()
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.mesh = _make_ribbon_mesh(0.22, 0.03, 6)
	n.position = Vector3(0.18 * side, 0.0, 0.0)
	n.rotation_degrees = Vector3(0.0, 0.0, 70.0 * side)
	n.material_override = _make_material(_c_amber)
	return n


func _make_burst_mesh(radius: float, points: int, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var arr := PackedVector3Array()
	var idx := PackedInt32Array()
	# Asymmetric sharp burst: fan of tapered triangles from center
	for i in points:
		var a0 := (i / float(points)) * TAU
		var a1 := ((i + 1) / float(points)) * TAU
		var r0 := radius * (0.6 + 0.4 * fmod(i, 2))
		arr.append(Vector3.ZERO)
		arr.append(Vector3(cos(a0) * r0, sin(a0) * r0 * 0.7, 0.0))
		arr.append(Vector3(cos(a1) * r0 * 0.8, sin(a1) * r0 * 0.5, 0.0))
		idx.append(i * 3)
		idx.append(i * 3 + 1)
		idx.append(i * 3 + 2)
	var mesh := _mesh_from_arrays(arr, idx)
	mi.mesh = mesh
	mi.material_override = _make_material(color)
	return mi


func _make_chip_mesh(size: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var arr := PackedVector3Array()
	var idx := PackedInt32Array()
	# Small tapered chip (thin triangle)
	arr.append(Vector3(0.0, 0.0, 0.0))
	arr.append(Vector3(size, size * 0.4, 0.0))
	arr.append(Vector3(size * 0.3, -size * 0.5, 0.0))
	idx = PackedInt32Array([0, 1, 2])
	var mesh := _mesh_from_arrays(arr, idx)
	mi.mesh = mesh
	mi.material_override = _make_material(color)
	return mi


func _make_arc_mesh(radius: float, thickness: float, arc_angle: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var arr := PackedVector3Array()
	var idx := PackedInt32Array()
	var segs := 17
	var start := -arc_angle / 2.0
	for i in segs:
		var a0 := start + (i / float(segs)) * arc_angle
		var a1 := start + ((i + 1) / float(segs)) * arc_angle
		# Taper thickness along the arc: full at the middle, near-zero pointed tips
		var t0 := sin(PI * i / float(segs))
		var t1 := sin(PI * (i + 1) / float(segs))
		var th0 := thickness * maxf(t0, 0.02)
		var th1 := thickness * maxf(t1, 0.02)
		var p0o := Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1o := Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		var p0i := Vector3(cos(a0) * (radius - th0), sin(a0) * (radius - th0), 0.0)
		var p1i := Vector3(cos(a1) * (radius - th1), sin(a1) * (radius - th1), 0.0)
		var b := arr.size()
		arr.append(p0o); arr.append(p1o); arr.append(p1i); arr.append(p0i)
		idx.append(b); idx.append(b + 1); idx.append(b + 2)
		idx.append(b); idx.append(b + 2); idx.append(b + 3)
	var mesh := _mesh_from_arrays(arr, idx)
	mi.mesh = mesh
	mi.material_override = _make_material(color)
	return mi


func _make_ribbon_mesh(length: float, width: float, segs: int) -> Mesh:
	# Tapered curved stroke (not a box): centerline curves slightly, width tapers at ends.
	var arr := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in segs + 1:
		var t := i / float(segs)
		var x := lerpf(-length / 2.0, length / 2.0, t)
		var y := sin(t * PI) * width * 1.5   # gentle curve
		var w := width * (0.3 + 0.7 * sin(t * PI))  # taper
		arr.append(Vector3(x, y - w, 0.0))
		arr.append(Vector3(x, y + w, 0.0))
	for i in segs:
		var b := i * 2
		idx.append(b); idx.append(b + 1); idx.append(b + 2)
		idx.append(b + 1); idx.append(b + 3); idx.append(b + 2)
	return _mesh_from_arrays(arr, idx)

# Local typed helper: build an ArrayMesh from vertex/index arrays (no external utils).
func _mesh_from_arrays(vertices: PackedVector3Array, indices: PackedInt32Array) -> Mesh:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _recount() -> void:
	_visible_cues = 0
	for i in _cue_visible.size():
		if _cue_visible[i]:
			_visible_cues += 1
