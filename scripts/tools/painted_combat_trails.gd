extends Node3D

var _pool: Node3D
var _initialized := false

func _ready() -> void:
	var tex: Texture2D = preload("res://assets/vfx/painted-combat-v1/swing.png")
	_pool = preload("res://scripts/tools/painted_effect_pool.gd").new()
	_pool.name = "TrailPool"
	add_child(_pool)
	_pool.setup({"hero": tex, "guard": tex, "wolf": tex}, 6)
	_initialized = true

func emit_swing(kind: String, at: Vector3, direction: Vector3) -> void:
	if not _initialized or _pool == null:
		return
	if kind != "hero" and kind != "guard" and kind != "wolf":
		return
	var lifetime := 0.24 if kind == "wolf" else 0.20
	var span := 1.1 if kind == "wolf" else 1.4
	_pool.emit(kind, at, direction, lifetime, span, 0.4)

func advance(delta: float) -> void:
	if not _initialized or _pool == null:
		return
	_pool.advance(delta)

func clear_all() -> void:
	if not _initialized or _pool == null:
		return
	_pool.clear_all()

func debug_snapshot() -> Dictionary:
	var snap := {}
	if _initialized and _pool != null and _pool.has_method("debug_snapshot"):
		snap = _pool.debug_snapshot()
	return {
		"active_trails": int(snap.get("active", 0)),
		"total_emitted": int(snap.get("emitted", 0)),
		"last_kind": str(snap.get("last_kind", "")),
		"pool_size": int(snap.get("pool_size", 0)),
		"painted": true,
		"pool": snap,
	}
