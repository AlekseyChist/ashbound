extends Node3D

const POOL_SCRIPT: String = "res://scripts/combat/painted_effect_pool.gd"

const TEX_HIT: Texture2D = preload("res://assets/vfx/painted-combat-v1/hit.png")
const TEX_BLOCK: Texture2D = preload("res://assets/vfx/painted-combat-v1/block.png")
const TEX_PERFECT: Texture2D = preload("res://assets/vfx/painted-combat-v1/perfect_block.png")
const TEX_WINDUP: Texture2D = preload("res://assets/vfx/painted-combat-v1/windup.png")

const CUE_CAP: int = 2
const IMPACT_LIFETIME: Dictionary = {"hit": 0.22, "block": 0.26, "perfect_block": 0.30}
const IMPACT_SPAN: Dictionary = {"hit": 1.10, "block": 1.15, "perfect_block": 1.35}

var pool: Node3D
var _cues: Array[Dictionary] = []
var _last_result: String = ""


func _ready() -> void:
	pool = load(POOL_SCRIPT).new()
	pool.name = "ImpactPool"
	add_child(pool)
	var textures: Dictionary = {
		"hit": TEX_HIT,
		"block": TEX_BLOCK,
		"perfect_block": TEX_PERFECT,
	}
	pool.setup(textures, 8)
	for i in CUE_CAP:
		var root: Node3D = Node3D.new()
		root.name = "Cue%d" % i
		add_child(root)
		var stroke: Sprite3D = _make_cue_sprite("Stroke", TEX_WINDUP, root)
		var flash: Sprite3D = _make_cue_sprite("ArmedFlash", TEX_PERFECT, root)
		_cues.append({
			"key": "",
			"root": root,
			"stroke": stroke,
			"flash": flash,
			"at": Vector3.ZERO,
			"direction": Vector3.FORWARD,
			"progress": 0.0,
			"armed": false,
			"span": 0.9,
			"visible": false,
		})


func _make_cue_sprite(node_name: String, texture: Texture2D, parent: Node3D) -> Sprite3D:
	var sprite: Sprite3D = Sprite3D.new()
	sprite.name = node_name
	parent.add_child(sprite)
	sprite.texture = texture
	sprite.hframes = 2
	sprite.vframes = 2
	sprite.frame = 0
	sprite.modulate.a = 0.0
	sprite.transparent = true
	sprite.shaded = false
	sprite.double_sided = true
	sprite.no_depth_test = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.visible = false
	return sprite


func _process(_delta: float) -> void:
	if pool == null:
		return
	for cue in _cues:
		if not bool(cue["visible"]):
			continue
		var dir: Vector3 = cue["direction"]
		pool._orient(cue["stroke"], dir)
		pool._orient(cue["flash"], dir)


func update_cue(key: String, at: Vector3, direction: Vector3, progress: float, armed: bool, enemy_kind: String) -> void:
	if pool == null:
		return
	var p: float = clampf(progress, 0.0, 1.0)
	if not is_finite(p):
		p = 0.0
	var dir: Vector3 = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	var span: float = 1.15 if enemy_kind == "guard" else 0.9
	var cue: Dictionary = _find_cue(key)
	if cue.is_empty():
		cue = _allocate_cue(key)
		if cue.is_empty():
			return
	cue["at"] = at
	cue["direction"] = dir
	cue["progress"] = p
	cue["armed"] = armed
	cue["span"] = span
	cue["visible"] = true
	var stroke: Sprite3D = cue["stroke"]
	var flash: Sprite3D = cue["flash"]
	stroke.visible = true
	flash.visible = armed
	stroke.global_position = at
	flash.global_position = at
	var frame_width: float = stroke.texture.get_width() / 2.0
	stroke.pixel_size = span / frame_width
	if armed:
		stroke.frame = 3
		stroke.modulate.a = 1.0
		flash.frame = 0
		flash.scale = Vector3.ONE
		flash.pixel_size = 0.4 / (flash.texture.get_width() / 2.0)
		flash.modulate.a = 1.0
	else:
		stroke.frame = int(p * 2.999)
		stroke.modulate.a = lerpf(0.55, 0.85, p)
		flash.modulate.a = 0.0


func hide_cue(key: String) -> void:
	var cue: Dictionary = _find_cue(key)
	if cue.is_empty():
		return
	cue["key"] = ""
	cue["visible"] = false
	cue["stroke"].visible = false
	cue["flash"].visible = false


func clear_all() -> void:
	for cue in _cues:
		cue["key"] = ""
		cue["visible"] = false
		cue["stroke"].visible = false
		cue["flash"].visible = false
	if pool != null:
		pool.clear_all()


func emit_impact(result: String, at: Vector3, direction: Vector3) -> void:
	if pool == null:
		return
	var lifetime: Variant = IMPACT_LIFETIME.get(result)
	if lifetime == null:
		return
	var span: float = float(IMPACT_SPAN[result])
	pool.emit(result, at, direction, float(lifetime), span, 0.0)
	_last_result = result


func advance(delta: float) -> void:
	if pool != null:
		pool.advance(delta)


func debug_snapshot() -> Dictionary:
	var visible_cues: int = 0
	var cue_frames: Array[int] = []
	for cue in _cues:
		if bool(cue["visible"]):
			visible_cues += 1
			cue_frames.append(int(cue["stroke"].frame))
	var pool_snap: Dictionary = {}
	if pool != null:
		pool_snap = pool.debug_snapshot()
	return {
		"active_impacts": int(pool_snap.get("active", 0)),
		"visible_cues": visible_cues,
		"last_result": _last_result,
		"cue_pool_size": CUE_CAP,
		"impact_pool_size": 8,
		"painted": true,
		"pool": pool_snap,
		"cue_frames": cue_frames,
	}


func _find_cue(key: String) -> Dictionary:
	for cue in _cues:
		if str(cue["key"]) == key:
			return cue
	return {}


func _allocate_cue(key: String) -> Dictionary:
	for cue in _cues:
		if str(cue["key"]) == "":
			cue["key"] = key
			cue["progress"] = 0.0
			cue["armed"] = false
			return cue
	return {}
