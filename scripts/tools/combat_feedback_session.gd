extends "res://scripts/tools/corner_enemy_session.gd"
## Изолированное превью боевой обратной связи: унаследованные правила
## движения/агрессии/контактов/дистанций не меняются; добавлены локальный
## hitstop (заморозка симуляции на фиксированное время), FX-подчинённый узел и
## снимок состояния для отладки.

const FX_SCRIPT_PATH := "res://scripts/combat/combat_feedback_fx.gd"
const TRAILS_SCRIPT_PATH := "res://scripts/combat/combat_swing_trails.gd"

const STOP_HIT := 0.050
const STOP_BLOCK := 2.0 / 60.0
const STOP_PERFECT := 5.0 / 60.0

var _fx: Node = null
var _trails: Node = null
var _swing_marked: Dictionary = {}
var _stop_remaining: float = 0.0
var _stop_count: int = 0
var _last_feedback: String = ""


func _create_feedback_fx() -> Node:
	var fx_script: GDScript = load(FX_SCRIPT_PATH)
	return fx_script.new()


func _create_swing_trails() -> Node:
	var trails_script: GDScript = load(TRAILS_SCRIPT_PATH)
	return trails_script.new()


func setup(sbx: Node, plr: CharacterBody3D) -> void:
	super.setup(sbx, plr)
	_fx = _create_feedback_fx()
	_fx.name = "CombatFeedbackFX"
	add_child(_fx)
	for e in enemies:
		if is_instance_valid(e):
			var visual: Node = e.get_node_or_null("Visual")
			if visual != null and "external_feedback" in visual:
				visual.set("external_feedback", true)
				visual._process(0.0)
	_trails = _create_swing_trails()
	_trails.name = "SwingTrails"
	add_child(_trails)

func is_hitstopped() -> bool:
	return _stop_remaining > 0.0


func feedback_snapshot() -> Dictionary:
	var snap: Dictionary = super.snapshot()
	snap["stop_remaining"] = _stop_remaining
	snap["stop_count"] = _stop_count
	snap["last_feedback"] = _last_feedback
	if _fx != null and _fx.has_method("debug_snapshot"):
		snap["fx"] = _fx.debug_snapshot()
	if _trails != null and _trails.has_method("debug_snapshot"):
		snap["trails"] = _trails.debug_snapshot()
	return snap


func advance(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	_apply_focus_state()
	if not enabled():
		cancel_trial()
		return
	var remaining: float = minf(delta, MAX_DELTA)
	while remaining > 0.0:
		if not enabled():
			cancel_trial()
			return
		if _stop_remaining > 0.0:
			var frozen: float = minf(remaining, _stop_remaining)
			_stop_remaining -= frozen
			remaining -= frozen
			_advance_fx(frozen)
			_update_feedback_cues()
			continue
		var step: float = minf(remaining, SUBSTEP_MAX)
		_sim_time += step
		for e in enemies:
			if is_instance_valid(e):
				e.step(step)
		_update_recoil(step)
		remaining -= step
		_advance_fx(step)
		_update_feedback_cues()


func _update_feedback_cues() -> void:
	if _fx == null or not _fx.has_method("update_cue") or not _fx.has_method("hide_cue"):
		return
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.state == "windup":
			var height: float = 1.3 if e.kind == "guard" else 0.75
			var center: Vector3 = e.global_position + e.facing_direction * 0.30 + Vector3(0.0, height, 0.0)
			_fx.update_cue(
				String(e.name),
				center,
				e.facing_direction,
				clampf(e.state_time / e._windup_time, 0.0, 1.0),
				e.is_block_window_open(),
				e.kind
			)
			if e.is_block_window_open() and not _swing_marked.has(String(e.name)):
				_swing_marked[String(e.name)] = true
				var trail_height: float = 1.3 if e.kind == "guard" else 0.65
				var side: Vector3 = e.facing_direction.cross(Vector3.UP).normalized() if e.kind == "guard" else Vector3.ZERO
				var trail_at: Vector3 = e.global_position + e.facing_direction * 0.35 + side * 0.38 + Vector3(0.0, trail_height, 0.0)
				if _trails != null and _trails.has_method("emit_swing"):
					_trails.emit_swing(e.kind, trail_at, e.facing_direction)
		else:
			_fx.hide_cue(String(e.name))
			_swing_marked.erase(String(e.name))

func _advance_fx(delta: float) -> void:
	if _fx != null and _fx.has_method("advance"):
		_fx.advance(delta)
	if _trails != null and _trails.has_method("advance"):
		_trails.advance(delta)


func _apply_result_fx(result: String) -> void:
	super._apply_result_fx(result)
	if not is_instance_valid(_active_source):
		return
	var source: CharacterBody3D = _active_source
	var kind: String = source.kind
	var at: Vector3 = player.global_position + Vector3(0.0, 1.2 if kind == "guard" else 0.8, 0.0)
	var to_attacker: Vector3 = source.global_position - player.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() > 0.0001:
		at += to_attacker.normalized() * 0.28
	var dir: Vector3 = -to_attacker.normalized() if to_attacker.length_squared() > 0.0001 else player.facing_direction
	match result:
		"hit":
			_last_feedback = "hit"
			if _fx != null and _fx.has_method("emit_impact"):
				_fx.emit_impact("hit", at, dir)
			_begin_stop(STOP_HIT, &"hit")
		"block":
			_last_feedback = "block"
			if _fx != null and _fx.has_method("emit_impact"):
				_fx.emit_impact("block", at, dir)
			_begin_stop(STOP_BLOCK, &"guard")
		"perfect_block":
			_last_feedback = "perfect_block"
			if _fx != null and _fx.has_method("emit_impact"):
				_fx.emit_impact("perfect_block", at, dir)
			_begin_stop(STOP_PERFECT, &"guard")
		_:
			pass


func _begin_stop(seconds: float, action: StringName) -> void:
	_stop_remaining = maxf(_stop_remaining, seconds)
	_stop_count += 1
	if is_instance_valid(player):
		player.begin_feedback_stop(seconds, action)

func hero_strike() -> void:
	if not enabled():
		return
	_emit_hero_swing()
	var target: Node3D = eligible_target()
	if target == null:
		return
	target.receive_hit()
	target._present_visual()
	_last_feedback = "hit"
	var kind: String = target.kind
	var at: Vector3 = target.global_position + Vector3(0.0, 1.15 if kind == "guard" else 0.65, 0.0)
	var to_hero: Vector3 = player.global_position - target.global_position
	to_hero.y = 0.0
	if to_hero.length_squared() > 0.0001:
		at += to_hero.normalized() * 0.28
	var dir: Vector3 = to_hero.normalized() if to_hero.length_squared() > 0.0001 else -target.facing_direction
	if _fx != null and _fx.has_method("emit_impact"):
		_fx.emit_impact("hit", at, dir)
	_begin_stop(STOP_HIT, &"attack")
	print("ASHBOUND_ENEMY_HERO_HIT kind=%s" % [target.kind])

func cancel_trial() -> void:
	_clear_feedback_local()
	super.cancel_trial()


func _clear_feedback_local() -> void:
	_stop_remaining = 0.0
	if is_instance_valid(player) and player.has_method("clear_feedback_stop"):
		player.clear_feedback_stop()
	if _fx != null and _fx.has_method("clear_all"):
		_fx.clear_all()
	if _trails != null and _trails.has_method("clear_all"):
		_trails.clear_all()
	_swing_marked.clear()


func _emit_hero_swing() -> void:
	if _trails == null or not _trails.has_method("emit_swing"):
		return
	if not is_instance_valid(player):
		return
	var side: Vector3 = player.facing_direction.cross(Vector3.UP).normalized()
	_trails.emit_swing(
		"hero",
		player.global_position + Vector3(0.0, 1.3, 0.0) + player.facing_direction * 0.35 + side * 0.38,
		player.facing_direction
	)

func set_guard(pressed: bool) -> bool:
	var fresh_press_during_stop: bool = pressed and _stop_remaining > 0.0 and not _guarding
	var result: bool = super.set_guard(pressed)
	if fresh_press_during_stop:
		_perfect_eligible = false
	return result
